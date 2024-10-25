//! Sampling Library for OTIO V2
//!
//! Includes signal generators and samplers as well as tools for integrating
//! a sampling into the rest of the temporal framework.  Leverages libsamplerate
//! for test purposes.
//!
//! A "Sampling" represents a cyclical sampling, over time, of a signal,
//! including a buffer of the sample values.
//!
//! @TODO: decoupling time as the domain to sample over
//! @TODO: handle acyclical sampling (IE - variable bitrate data, held frames)

const std = @import("std");
const libsamplerate = @import("libsamplerate").libsamplerate;
const kissfft = @import("kissfft").c;
const wav = @import("wav");

const curve = @import("curve");
const opentime = @import("opentime");
const time_topology = @import("time_topology");

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectApproxEqAbs = std.testing.expectApproxEqAbs;


// @TODO : move to util maybe?
const EPSILON: f32 = 1.0e-4;

const RETIME_DEBUG_LOGGING = false;
const WRITE_TEST_FILES = false;
const TMPDIR = "/var/tmp";

/// type of a sample VALUE (type of a sample ordinate is usize for a discrete
/// index or opentime.Ordinate for continuous
/// @TODO: make this comptime definable (anytype)
const sample_t  = f32;

/// project a continuous ordinate into a discrete index sequence
pub fn project_instantaneous_cd(
    self: anytype,
    ord_continuous: opentime.Ordinate,
) usize
{
    return @intFromFloat(
        @floor(
            ord_continuous*@as(
                opentime.Ordinate,
                @floatFromInt(self.sample_rate_hz)
            )
            + (1/@as(opentime.Ordinate, @floatFromInt(self.sample_rate_hz)))/2
        )
    );
}

test "project_instantaneous_cd"
{
    const result = project_instantaneous_cd(
        DiscreteDatasourceIndexGenerator{
            .sample_rate_hz = 24,
            .start_index = 12,
        },
        12,
    );

    try std.testing.expectEqual(result, 288);
}

// @TODO: this should be symmetrical with cd - I think it is missing the 0.5
//        offset from the cd function
pub fn project_index_dc(
    self: anytype,
    ind_discrete: usize,
) opentime.ContinuousTimeInterval
{
    var start:f32 = @floatFromInt(ind_discrete);
    start -= @floatFromInt(self.start_index);
    const s_per_cycle = 1 / @as(
        opentime.Ordinate,
        @floatFromInt(self.sample_rate_hz)
    );
    start *= s_per_cycle;

    return .{
        .start_seconds = start,
        .end_seconds = start + s_per_cycle,
    };
}

test "project_index_dc"
{
    const result = project_index_dc(
        DiscreteDatasourceIndexGenerator{
            .sample_rate_hz = 24,
            .start_index = 12,
        },
        288,
    );

    try std.testing.expectEqual(result.start_seconds, 11.5);
    try std.testing.expectApproxEqAbs(
        result.end_seconds,
        11.541667,
        EPSILON,
    );
}

/// a set of samples and the parameters of those samples
const Sampling = struct {
    allocator: std.mem.Allocator,
    buffer: []sample_t,
    sample_rate_hz: u32,
    interpolating: bool,

    pub fn init(
        allocator: std.mem.Allocator,
        count:usize,
        sample_rate_hz: u32,
        interpolating: bool,
    ) !Sampling
    {
        const buffer: []sample_t = try allocator.alloc(sample_t, count);

        return .{
            .allocator = allocator,
            .buffer = buffer,
            .sample_rate_hz = sample_rate_hz,
            .interpolating = interpolating,
        };
    }

    pub fn deinit(
        self: @This()
    ) void 
    {
        self.allocator.free(self.buffer);
    }

    /// serialize the sampling to a wav file
    pub fn write_file(
        self: @This(),
        fpath: []const u8,
    ) !void 
    {
        var file = try std.fs.cwd().createFile(
            fpath,
            .{},
        );
        defer file.close();

        var encoder = try wav.encoder(
            i16,
            file.writer(),
            file.seekableStream(),
            self.sample_rate_hz,
            1,
        );
        defer encoder.finalize() catch unreachable; 

        try encoder.write(f32, self.buffer);
    }

    /// write a file but procedurally generate the filename with data from the 
    /// sampling / parent signal
    pub fn write_file_prefix(
        self: @This(),
        allocator: std.mem.Allocator,
        dirname: []const u8,
        prefix: []const u8,
        maybe_parent_signal: ?SignalGenerator,
    ) !void
    {
        const name = (
            if (maybe_parent_signal)
            |parent_signal|
             try std.fmt.allocPrint(
                allocator,
                "{s}/{s}{s}.amp_{d}_{d}s_{d}hz_signal_{d}hz_samples.wav",
                .{
                    dirname,
                    prefix,
                    @tagName(parent_signal.signal),
                    parent_signal.signal_amplitude,
                    parent_signal.signal_duration_s,
                    parent_signal.signal_frequency_hz,
                    self.sample_rate_hz,
                }
            )
        else 
            try std.fmt.allocPrint(
                allocator,
                "{s}/{s}_{d}hz_samples.wav",
                .{
                    dirname,
                    prefix,
                    self.sample_rate_hz,
                }
            )
        );
        defer allocator.free(name);

        return self.write_file(name);
    }

    /// map a time to an index in the buffer
    pub fn index_at_time(
        self: @This(),
        t_s: opentime.Ordinate,
    ) usize
    {
        const hz_f:opentime.Ordinate = @floatFromInt(self.sample_rate_hz);

        return @intFromFloat(@floor(t_s*hz_f + (0.5 / hz_f)));
    }

    /// return an interval of the indices that span the specified time
    /// @TODO: assumes that indices will be linearly increasing.  problem?
    pub fn indices_between_time(
        self: @This(),
        start_time_inclusive_s: opentime.Ordinate,
        end_time_exclusive_s: opentime.Ordinate,
    ) [2]usize
    {
        const start_index:usize = self.index_at_time(start_time_inclusive_s);
        const end_index:usize = self.index_at_time(end_time_exclusive_s);

        return .{ start_index, end_index };
    }

    /// fetch the slice of self.buffer that overlaps with the provided range
    /// @TODO: this should align with the algebra functions (IE is it
    ///        overlaps?) since samples represent regions of time and not
    ///        instantaneous points in time
    pub fn samples_between_time(
        self: @This(),
        start_time_inclusive_s: sample_t,
        end_time_exclusive_s: sample_t,
    ) []sample_t
    {
        const index_bounds = self.indices_between_time(
            start_time_inclusive_s,
            end_time_exclusive_s
        );

        return self.buffer[index_bounds[0]..index_bounds[1]];
    }

    /// fetch the value of the buffer at the provided time
    pub fn sample_value_at_time(
        self: @This(),
        t_s:sample_t,
    ) sample_t
    {
        return self.buffer[self.index_at_time(t_s)];
    }

    /// assuming a time-0 start, build the range of continuous time
    /// ("intrisinsic space") of the sampling
    pub fn extents(
        self: @This(),
    ) opentime.ContinuousTimeInterval
    {
        return .{
            .start_seconds = 0,
            .end_seconds = (
                @as(opentime.Ordinate, @floatFromInt(self.buffer.len)) 
                / @as(opentime.Ordinate, @floatFromInt(self.sample_rate_hz))
            ),
        };
    }
};

test "samples_between_time" 
{
    const sine_signal_48khz = SignalGenerator{
        .sample_rate_hz = 48000,
        .signal_frequency_hz = 100,
        .signal_amplitude = 1,
        .signal_duration_s = 1,
        .signal = .sine,
    };
    const sine_samples = try sine_signal_48khz.rasterized(
        std.testing.allocator,
        true,
    );
    defer sine_samples.deinit();

    const first_half_samples = sine_samples.samples_between_time(
        0,
        0.5
    );

    try expectEqual(
        sine_signal_48khz.sample_rate_hz/2,
        first_half_samples.len,
    );
}

// @TODO: should this be folded into the SignalGenerator?

/// generate indices for frame numbers
pub const DiscreteDatasourceIndexGenerator = struct {
    sample_rate_hz: u32,
    start_index: usize = 0,
};

/// compact representation of a signal, can be rasterized into a buffer
pub const SignalGenerator = struct {
    sample_rate_hz: u32,
    signal_frequency_hz: u32,
    signal_amplitude: sample_t = 1.0,
    signal_duration_s: opentime.Ordinate,
    signal: Signal,

    const Signal= enum {
        sine,
        ramp,
        // used specifically to generate indices over time
        // discrete_data_source_index,
    };

    /// fill a buffer with values generated by this signal generator
    pub fn rasterized(
        self:@This(),
        allocator: std.mem.Allocator,
        interpolating_samples: bool,
    ) !Sampling
    {
        const sample_hz : opentime.Ordinate = @floatFromInt(self.sample_rate_hz);

        const samples_per_cycle = (
            sample_hz
            / @as(opentime.Ordinate, @floatFromInt(self.signal_frequency_hz))
        );

        const result = try Sampling.init(
            allocator, 
            // @TODO: f64 promotion of the signal duration?
            @intFromFloat(@ceil(@as(f64, self.signal_duration_s)*sample_hz)),
            self.sample_rate_hz,
            interpolating_samples,
        );

        const two_pi = std.math.pi * 2.0;

        // fill the sample buffer
        for (0.., result.buffer)
            |current_index, *sample|
        {
            const phase_angle:f32 = (
                @as(f32, @floatFromInt(current_index)) / samples_per_cycle
            );

            const mod_phase_angle = try std.math.mod(
                f32,
                phase_angle,
                1.0,
            );

            switch (self.signal) {
                .sine => {
                    sample.* = self.signal_amplitude * std.math.sin(
                        two_pi * mod_phase_angle
                    );
                },
                // @TODO: not bandwidth-limited, cannot be used for a proper
                //        synthesizer
                .ramp => {
                    sample.* = (
                        self.signal_amplitude 
                        * curve.bezier_math.lerp(
                            mod_phase_angle,
                            @as(sample_t,0),
                            1,
                        )
                    );
                }
            }
        }

        return result;
    }
};

test "rasterizing the sine" 
{
    const sine_signal_48khz = SignalGenerator{
        .sample_rate_hz = 48000,
        .signal_frequency_hz = 100,
        .signal_amplitude = 1,
        .signal_duration_s = 1,
        .signal = .sine,
    };
    const sine_samples = try sine_signal_48khz.rasterized(
        std.testing.allocator,
        true,
    );
    defer sine_samples.deinit();

    // check some known quantities
    try expectEqual(@as(usize, 48000), sine_samples.buffer.len);
    try expectEqual(@as(sample_t, 0), sine_samples.buffer[0]);
}

/// returns the peak to peak distance in indices of the samples in the buffer
pub fn peak_to_peak_distance(
    samples: []const sample_t,
) !usize 
{
    var maybe_last_peak_index:?usize = null;
    var maybe_distance_in_indices:?usize = null;

    const width = 3;

    for (width..samples.len-width)
        |current_index|
    {
        if (
            samples[current_index] > samples[current_index - width] 
            and samples[current_index] > samples[current_index + width]
            and (
                maybe_last_peak_index == null 
                or maybe_last_peak_index.? < current_index - 3
            )
        )
        {
            if (maybe_last_peak_index)
               |last_peak_index| 
            {
                maybe_distance_in_indices = current_index - last_peak_index;
                break;
            }
            maybe_last_peak_index = current_index;
        }
    }

    if (maybe_distance_in_indices)
        |distance_in_indices|
    {
        return distance_in_indices;
    }

    return error.CouldNotFindTwoPeaks;
}

test "peak_to_peak_distance: sine/48khz sample/100hz signal"
{
        const sine_signal_48khz_100 = SignalGenerator{
            .sample_rate_hz = 48000,
            .signal_frequency_hz = 100,
            .signal_amplitude = 1,
            .signal_duration_s = 1,
            .signal = .sine,
        };
        const sine_samples_48khz_100 = try sine_signal_48khz_100.rasterized(
            std.testing.allocator,
            true,
        );
        defer sine_samples_48khz_100.deinit();

        const sine_samples_48khz_100_p2p = try peak_to_peak_distance(
            sine_samples_48khz_100.buffer
        );

        try expectEqual(480, sine_samples_48khz_100_p2p);
    }

test "peak_to_peak_distance: sine/48khz sample/50hz signal"
{
    const sine_signal_48khz_50 = SignalGenerator{
        .sample_rate_hz = 48000,
        .signal_frequency_hz = 50,
        .signal_amplitude = 1,
        .signal_duration_s = 1,
        .signal = .sine,
    };
    const sine_samples_48_50 = try sine_signal_48khz_50.rasterized(
        std.testing.allocator,
        true,
    );
    defer sine_samples_48_50.deinit();

    const sine_samples_48_50_p2p = try peak_to_peak_distance(
        sine_samples_48_50.buffer
    );

    try expectEqual(960, sine_samples_48_50_p2p);
}

test "peak_to_peak_distance: sine/96khz sample/100hz signal"
{
    const sine_signal_96_100 = SignalGenerator{
        .sample_rate_hz = 96000,
        .signal_frequency_hz = 100,
        .signal_amplitude = 1,
        .signal_duration_s = 1,
        .signal = .sine,
    };
    const sine_samples_96_100 = try sine_signal_96_100.rasterized(
        std.testing.allocator,
        true,
    );
    defer sine_samples_96_100.deinit();

    const sine_samples_96_100_p2p = try peak_to_peak_distance(
        sine_samples_96_100.buffer
    );

    try expectEqual(960, sine_samples_96_100_p2p);
}

// test 0 - ensure that the contents of the c-library are visible
test "c lib interface test" 
{
    // libsamplerate
    try expectEqual(libsamplerate.SRC_SINC_BEST_QUALITY, 0);

    // kiss_fft
    const cpx = kissfft.kiss_fft_cpx{ .r = 1, .i = 1 };
    try expectEqual(cpx.r, 1);
}

/// resample in_samples to destination_sample_rate_hz' rate
pub fn resampled(
    allocator: std.mem.Allocator,
    in_samples: Sampling,
    destination_sample_rate_hz: u32,
) !Sampling
{
    // @TODO: should this only work for interpolating Samplings?

    const resample_ratio : f64 = (
        @as(f64, @floatFromInt(destination_sample_rate_hz))
        / @as(f64, @floatFromInt(in_samples.sample_rate_hz))
    );

    const num_output_samples: usize = @as(
        usize, 
        @intFromFloat(
            @floor(
                @as(f64, @floatFromInt(in_samples.buffer.len)) 
                * resample_ratio
            )
        )
    );

    const result = try Sampling.init(
        allocator,
        num_output_samples,
        destination_sample_rate_hz,
        in_samples.interpolating,
    );

    var src_data : libsamplerate.SRC_DATA = .{
        .data_in = @ptrCast(in_samples.buffer.ptr),
        .input_frames = @intCast(in_samples.buffer.len),
        .data_out = @ptrCast(result.buffer.ptr),
        .output_frames = @intCast(num_output_samples),
        .src_ratio = resample_ratio,
        .end_of_input = 0,
    };

    const resample_error = libsamplerate.src_simple(
        &src_data,
        libsamplerate.SRC_SINC_BEST_QUALITY,
        1,
    );

    if (resample_error != 0) {
        return error.ResamplingError;
    }

    return result;
}

/// linearize xform, then retime in_samples with xform, return a new Sampling
/// at the same sample rate
pub fn retimed(
    allocator: std.mem.Allocator,
    in_samples: Sampling,
    xform: curve.Bezier,
    step_retime: bool,
    output_sampling_info: DiscreteDatasourceIndexGenerator,
) !Sampling
{
    const lin_curve = try xform.linearized(allocator);
    defer lin_curve.deinit(allocator);

    return retimed_linear_curve(
        allocator,
        in_samples,
        lin_curve,
        step_retime,
        output_sampling_info,
    );
}

/// retime in_samples with xform, return a new Sampling at the same sample rate
pub fn retimed_linear_curve(
    allocator: std.mem.Allocator,
    in_samples: Sampling,
    lin_curve: curve.Linear.Monotonic,
    step_retime: bool,
    output_sampling_info: DiscreteDatasourceIndexGenerator,
) !Sampling
{
    return switch (in_samples.interpolating) {
        true => try retimed_linear_curve_interpolating(
            allocator,
            in_samples,
            lin_curve,
            step_retime,
            output_sampling_info,
        ),
        false => try retimed_linear_curve_non_interpolating(
            allocator,
            in_samples,
            lin_curve,
            output_sampling_info,
        ),
    };
}

/// analytical projection of a sampling modeled by an identity function
/// through the retiming curve and back to a discrete sampling
///
/// the retiming curve maps an implicit continuous space of the samples to the
/// retimed space
/// 
/// ->
///
/// the retiming curve maps the retimed space to the implicit space of the
/// samples
///
/// For example, given:
///
/// "A"
/// (implicit continuous space)
/// 0s          1s
/// *--*--*--*--)
/// 0  1  2  3
/// (sample indices)
/// 
/// -> transform/resample them to this space:
///
/// "B"
/// 0s          1s
/// *--*--*--*--)
/// 0  0  1  1
/// (result sample indices, on the same original media from A)
///
/// 1. stretch time by 2:
///
/// 0s          1s         2s
/// *-----*-----*-----*----)
/// 0     1     2     3
///
/// 2. crop to output space
///
/// 0s          1s
/// *-----*-----)
/// 0     1     
///
/// 3. [re]sample the output
///
/// 0s          1s
/// *--*--*--*--)
/// 0  0  1  1  
///
/// or
/// "B" (with a phase shift)
///
/// 0.5         1.5
/// *--*--*--*--)
/// 0  1  1  2
///
/// 1. start with "A"
///
/// 0s          1s
/// *--*--*--*--)
/// 0  1  2  3
///
/// 2. expand
/// 0s    0.5   1s    1.5   2s
/// *-----*-----*-----*----)
/// 0     1     2     3
///
/// 3. crop
///0s  0.25    1s  1.25   2s
/// *--[--*-----*--)--*----)
/// 0     1     2     3
///
/// 4. resample
///
/// 0.5         1.5
/// *--*--*--*--)
/// 0  1  1  2
///
///
pub fn retimed_linear_curve_non_interpolating(
    allocator: std.mem.Allocator,
    in_samples: Sampling,
    retimed_to_implicit_crv: curve.Linear,
    output_sampling_info: DiscreteDatasourceIndexGenerator,
) !Sampling
{
    // sampling: discrete sampling space
    // curve: continuous sample -> continuous output space
    // need to build discrete sampling -> continuous transform

    const retimed_to_implicit_topo = (
        try time_topology.Topology.init_from_linear(
            allocator,
            retimed_to_implicit_crv
        )
    );

    const extents = in_samples.extents();
    const implicit_to_sample_topo_aff = (
        time_topology.Topology.init_affine(
            .{
                .input_bounds_val = extents,
            }
        )
    );

    // const implicit_to_sample_topo = (
    //     try implicit_to_sample_topo_aff.affine.linearized(
    //         allocator,
    //     )        
    // );
    // defer implicit_to_sample_topo.deinit(allocator);

    const retimed_to_sample_topo = try time_topology.join(
        allocator,
        .{
            .a2b = retimed_to_implicit_topo,
            .b2c = implicit_to_sample_topo_aff,
        },
    );
    defer retimed_to_sample_topo.deinit(allocator);

    const input_range = (
        retimed_to_sample_topo.input_bounds()
    );

    const num_output_samples:usize = @intFromFloat(
        input_range.duration_seconds() 
        * @as(f32, @floatFromInt(output_sampling_info.sample_rate_hz))
    );

    const output_buffer_size = num_output_samples;

    const output_sampling = try Sampling.init(
        allocator,
        output_buffer_size,
        output_sampling_info.sample_rate_hz,
        false,
    );

    const s_per_sample_output:f32 = (
        1.0 / @as(f32, @floatFromInt(output_sampling_info.sample_rate_hz))
    );

    // fill the output buffer
    for (output_sampling.buffer, 0..)
        |*output_sample, output_index|
    {
        // output index -> output time (discrete->continuous)
        const output_sample_time: f32 = (
            @as(f32, @floatFromInt(output_index)) * s_per_sample_output
            + input_range.start_seconds
        );

        // output -> input time (continuous -> continuous)
        const input_sample_time = (
            try retimed_to_sample_topo.project_instantaneous_cc(output_sample_time)
        );

        // input time -> input index (continuous -> discrete)
        const input_sample_index :usize = @intFromFloat(
            @floor(
                input_sample_time 
                * @as(f32, @floatFromInt(in_samples.sample_rate_hz))
            )
        );

        output_sample.* = in_samples.buffer[input_sample_index];
    }

    return output_sampling;
}

/// retime and interpolate the in_samples buffer using libsamplerate
pub fn retimed_linear_curve_interpolating(
    allocator: std.mem.Allocator,
    in_samples: Sampling,
    retimed_to_implicit_crv: curve.Linear,
    step_retime: bool,
    output_sampling_info: DiscreteDatasourceIndexGenerator,
) !Sampling
{
    var output_buffer_size:usize = 0;

    const RetimeSpec = struct {
        retime_ratio: f32,
        output_samples: usize,
        input_samples: usize,
        input_data: []sample_t,
    };

    var retime_specs = std.ArrayList(
        RetimeSpec
    ).init(allocator);
    defer retime_specs.deinit();

    for (
        retimed_to_implicit_crv.knots[0..retimed_to_implicit_crv.knots.len-1],
        retimed_to_implicit_crv.knots[1..]
    )  
        |l_knot, r_knot|
    {    
        const relevant_sample_indices = (
            in_samples.indices_between_time(
                l_knot.in,
                r_knot.in
            )
        );
        const relevant_input_samples = in_samples.buffer[
            relevant_sample_indices[0]..
        ];
        if (relevant_input_samples.len == 0) {
            return error.NoRelevantSamples;
        }
        const input_samples = (
            relevant_sample_indices[1] - relevant_sample_indices[0]
        );

        const sample_rate_f:f32 = @floatFromInt(
            output_sampling_info.sample_rate_hz
        );

        const output_samples:usize = @intFromFloat(
            @floor(
                (
                 (r_knot.out - l_knot.out) 
                 * sample_rate_f
                )
                + 0.5 / sample_rate_f
            )
        );

        if (output_samples == 0) {
            return error.NoOutputSamplesToCompute;
        }

        const retime_ratio:f32 = (
            ( @as(f32, @floatFromInt(output_samples ))) 
            / (
                @as(f32, @floatFromInt(input_samples))
            )
        );

        output_buffer_size += output_samples;

        try retime_specs.append(
            .{
                .retime_ratio = retime_ratio,
                .output_samples = output_samples,
                .input_data = relevant_input_samples,
                .input_samples = input_samples,
            }
        );
    }

    const full_output_buffer = try allocator.alloc(
        sample_t,
        output_buffer_size
    );
    var output_buffer = full_output_buffer[0..];

    const src_state = libsamplerate.src_new(
        // converter
        libsamplerate.SRC_SINC_BEST_QUALITY,
        // channels
        1,
        // error
        null,
    );
    defer _ = libsamplerate.src_delete(src_state);

    var src_data = libsamplerate.SRC_DATA{
        .data_in = @ptrCast(in_samples.buffer.ptr),
        .data_out = @ptrCast(output_buffer.ptr),
        .input_frames = 100,
        .output_frames = 100,
        // means that we're leaving additional data in the input buffer past
        // the end
        .end_of_input = 0,
    };

    if (RETIME_DEBUG_LOGGING) {
        std.debug.print(" \n\n----- retime info dump -----\n", .{});
    }

    var input_retime_samples = in_samples.buffer[0..];

    // @breakpoint();
    //
    var retime_index:usize = 0;
    while (retime_index < retime_specs.items.len)
    {
        // setup this chunk
        var spec = &retime_specs.items[retime_index];
        src_data.src_ratio = spec.retime_ratio;
        src_data.input_frames = @intCast(input_retime_samples.len);
        src_data.output_frames = @intCast(spec.output_samples);
        
        if (step_retime) {
            // calling this function forces it to be a step function
            _ = libsamplerate.src_set_ratio(src_state, spec.retime_ratio);
        }

        if (retime_index == retime_specs.items.len - 1)
        {
            src_data.end_of_input = 1;
        }

        // process the chunk
        const lsr_error = libsamplerate.src_process(src_state, &src_data);
        if (lsr_error != 0) {
            return error.LibSampleRateError;
        }

        if (RETIME_DEBUG_LOGGING) {
            std.debug.print(
                "in provided: {d} in used: {d} out requested: {d} out "
                ++ "generated: {d} ",
                .{
                    src_data.input_frames,
                    src_data.input_frames_used,
                    src_data.output_frames,
                    src_data.output_frames_gen,
                }
            );
            std.debug.print(
                "ratio: {d}\n",
                .{
                    src_data.src_ratio,
                }
            );
        }

        // slide buffers forward
        input_retime_samples = input_retime_samples[
            @intCast(src_data.input_frames_used)..
        ];
        src_data.data_in = @ptrCast(input_retime_samples.ptr);
        output_buffer = output_buffer[@intCast(src_data.output_frames_gen)..];
        src_data.data_out = @ptrCast(output_buffer.ptr);

        // if its time to advance to the next chunk
        if (
            src_data.output_frames <= 0 
            or input_retime_samples.len == 0
        )
        {
            retime_index += 1;
        }
        else
        {
            // slide buffers forward
            spec.output_samples -= @intCast(src_data.output_frames_gen);
        }
    }

    return Sampling{
        .allocator = allocator,
        .buffer = full_output_buffer,
        .sample_rate_hz = output_sampling_info.sample_rate_hz,
        .interpolating = true,
    };
}

// test 1
// have a set of samples over 48khz, resample them to 44khz
test "resample from 48khz to 44" 
{
    const sine_signal_48kz_100 = SignalGenerator{
        .sample_rate_hz = 48000,
        .signal_frequency_hz = 100,
        .signal_amplitude = 1,
        .signal_duration_s = 1,
        .signal = .sine,
    };
    const sine_samples_48khz_100 = (
        try sine_signal_48kz_100.rasterized(
            std.testing.allocator,
            true,
        )
    );
    defer sine_samples_48khz_100.deinit();

    if (WRITE_TEST_FILES) {
        try sine_samples_48khz_100.write_file_prefix(
            std.testing.allocator,
            TMPDIR,
            "resample_test_input.",
            sine_signal_48kz_100,
        );
    }

    const sine_samples_44khz = try resampled(
        std.testing.allocator,
        sine_samples_48khz_100,
        44100
    );
    defer sine_samples_44khz.deinit();

    if (WRITE_TEST_FILES) {
        try sine_samples_44khz.write_file_prefix(
            std.testing.allocator,
            TMPDIR,
            "resample_test_output.",
            sine_signal_48kz_100,
        );
    }

    const sine_samples_44khz_p2p = (
        try peak_to_peak_distance(sine_samples_44khz.buffer)
    );

    // peak to peak distance (a distance in sample indices) should be the same
    // independent of retiming those samples
    try expectEqual(@as(usize, 441), sine_samples_44khz_p2p);
}

// test 2
// have a set of samples over 48khz, retime them with a linear curve and then
// resample them to 44khz
test "retime 48khz samples: ident-2x-ident, then resample to 44.1khz" 
{
    const samples_48 = SignalGenerator{
        .sample_rate_hz = 48000,
        .signal_frequency_hz = 100,
        .signal_amplitude = 1,
        .signal_duration_s = 4,
        .signal = .sine,
    };
    const s48 = try samples_48.rasterized(
        std.testing.allocator,
        true,
    );
    defer s48.deinit();
    if (WRITE_TEST_FILES) {
        try s48.write_file_prefix(
            std.testing.allocator,
            TMPDIR,
            "retime_test_input.",
            samples_48,
        );
    }

    //
    //           ident
    //        2x   /
    //  ident     /
    //           /
    //          |
    //         |
    //        |
    //       /
    //      /
    //     /
    //    /
    //   /
    //  /
    //

    // @TODO: write this to a json file so we can image in curvet
    var retime_curve_segments = [_]curve.Bezier.Segment{
        // identity
        curve.Bezier.Segment.init_identity(0,  1.0),
        // go up
        curve.Bezier.Segment.init_from_start_end(
            .{ .in = 1.0, .out = 1.0 },
            .{ .in = 2.0, .out = 3.0 },
        ),
        // identity
        curve.Bezier.Segment.init_from_start_end(
            .{ .in = 2.0, .out = 3.0 },
            .{ .in = 3.0, .out = 4.0 },
        ),
    };
    const retime_curve : curve.Bezier = .{
        .segments = &retime_curve_segments
    };
    if (WRITE_TEST_FILES) {
        try curve.write_json_file_curve(
            std.testing.allocator,
            retime_curve,
            "/var/tmp/ours_retime_curve.curve.json"
        );
    }

    const output_sampling_info : DiscreteDatasourceIndexGenerator = .{
        .sample_rate_hz = s48.sample_rate_hz,
    };

    const samples_48_retimed = try retimed(
        std.testing.allocator,
        s48,
        retime_curve,
        true,
        output_sampling_info,
    );
    defer samples_48_retimed.deinit();
    if (WRITE_TEST_FILES) {
        try samples_48_retimed.write_file_prefix(
            std.testing.allocator,
            TMPDIR,
            "retime_test_retimed_pre_resample.",
            samples_48,
        );
    }

    const samples_44 = try resampled(
        std.testing.allocator,
        samples_48_retimed,
        44100,
    );
    defer samples_44.deinit();
    if (WRITE_TEST_FILES) {
        try samples_44.write_file_prefix(
            std.testing.allocator,
            TMPDIR,
            "retime_test_output.",
            samples_48,
        );
    }

    // identity
    const samples_44_p2p_0p25 = try peak_to_peak_distance(
        samples_44.buffer[0..11025]
    );
    try expectEqual(
        441,
        samples_44_p2p_0p25
    );

    // 2x
    const samples_44_p2p_0p5 = try peak_to_peak_distance(
        samples_44.buffer[48100..52000]
    );
    try expectApproxEqAbs(
        @as(f32, @floatFromInt(882)),
        @as(f32, @floatFromInt( samples_44_p2p_0p5)),
        2,
     );

    // identity
    const samples_44_p2p_1p0 = try peak_to_peak_distance(
        samples_44.buffer[(3*48000 + 100)..]
    );
    try expectEqual(
        441,
        samples_44_p2p_1p0
    );
}

// test 3
// retime a set of samples with a cubic function.  also linearize the function
// at an intentionally low rate to reproduce an error we've seen on some
// editing systems with retiming
test "retime 48khz samples with a nonlinear acceleration curve and resample" 
{
    const samples_48 = SignalGenerator{
        .sample_rate_hz = 48000,
        .signal_frequency_hz = 100,
        .signal_amplitude = 1,
        .signal_duration_s = 4,
        .signal = .sine,
    };
    const s48 = try samples_48.rasterized(
        std.testing.allocator,
        true,
    );
    defer s48.deinit();

    var cubic_retime_curve_segments = [_]curve.Bezier.Segment{
        // identity
        curve.Bezier.Segment.init_identity(0, 1),
        // go up
        curve.Bezier.Segment{
            .p0 = .{ .in = 1, .out = 1.0 },
            .p1 = .{ .in = 1.5, .out = 1.25 },
            .p2 = .{ .in = 2, .out = 1.35 },
            .p3 = .{ .in = 2.5, .out = 1.5 },
        },
    };
    const cubic_retime_curve : curve.Bezier = .{
        .segments = &cubic_retime_curve_segments
    };
    if (WRITE_TEST_FILES) {
        try curve.write_json_file_curve(
            std.testing.allocator,
            cubic_retime_curve,
            "/var/tmp/ours_retime_24hz.linear.json"
        );
    }

    const output_sampling_info : DiscreteDatasourceIndexGenerator = .{
        .sample_rate_hz = s48.sample_rate_hz,
    };

    const samples_48_retimed_cubic = try retimed(
        std.testing.allocator,
        s48,
        cubic_retime_curve,
        true,
        output_sampling_info,
    );
    defer samples_48_retimed_cubic.deinit();
    if (WRITE_TEST_FILES) {
        try samples_48_retimed_cubic.write_file_prefix(
            std.testing.allocator,
            TMPDIR,
            "retime_cubic_test_retimed_pre_resample.",
            samples_48,
        );
    }

    // linearize at 24hz
    const retime_curve_extents = (
        cubic_retime_curve.extents_input()
    );
    const inc:sample_t = 4.0/24.0;

    var knots = std.ArrayList(curve.ControlPoint).init(
        std.testing.allocator
    );
    defer knots.deinit();

    try knots.append(
        .{
            .in = retime_curve_extents.start_seconds,
            .out = try cubic_retime_curve.output_at_input(
                retime_curve_extents.start_seconds
            ),
        }
    );

    var t = retime_curve_extents.start_seconds + inc;
    while (t < retime_curve_extents.end_seconds)
        : (t += inc)
    {
        try knots.append(
            .{
                .in = t,
                .out = try cubic_retime_curve.output_at_input(t),
            }
        );
    }

    const retime_24hz_lin = curve.Linear{
        .knots = try knots.toOwnedSlice(),
    };
    defer retime_24hz_lin.deinit(std.testing.allocator);

    if (WRITE_TEST_FILES) {
        try curve.write_json_file_curve(
            std.testing.allocator,
            retime_24hz_lin,
            "/var/tmp/ours_retime_24hz.linear.json"
        );
        try curve.write_json_file_curve(
            std.testing.allocator,
            cubic_retime_curve,
            "/var/tmp/ours_retime_acceleration.curve.json"
        );
    }

    const samples_48_retimed = try retimed_linear_curve(
        std.testing.allocator,
        s48,
        retime_24hz_lin,
        true,
        output_sampling_info,
    );
    defer samples_48_retimed.deinit();
    if (WRITE_TEST_FILES) {
        try samples_48_retimed.write_file_prefix(
            std.testing.allocator,
            TMPDIR,
            "retime_cubic_test_retimed_linearized24hz_pre_resample.",
            samples_48,
        );
    }
    const samples_44 = try resampled(
        std.testing.allocator,
        samples_48_retimed,
        44100,
    );
    defer samples_44.deinit();
    if (WRITE_TEST_FILES) {
        try samples_44.write_file_prefix(
            std.testing.allocator,
            TMPDIR,
            "retime_cubic_test_retimed_linearized24hz_resampled.",
            samples_48,
        );
    }

    // identity
    const samples_44_p2p_0p25 = try peak_to_peak_distance(
        samples_44.buffer[0..11025]
    );
    try expectEqual(
        441,
        samples_44_p2p_0p25
    );

    // 2x
    const samples_44_p2p_0p5 = try peak_to_peak_distance(
        samples_44.buffer[(44100+1000)..]
    );
    try expectEqual(
        207,
        samples_44_p2p_0p5
     );
}

test "sampling: frame phase slide 1: (identity) 0,1,2,3->0,1,2,3"
{
    const ramp_signal = SignalGenerator{
        .sample_rate_hz = 48000,
        .signal_frequency_hz = 1,
        .signal_duration_s = 2,
        .signal = .ramp,
    };

    const ramp_samples = try ramp_signal.rasterized(
        std.testing.allocator,
        false,
    );
    defer ramp_samples.deinit();
    if (WRITE_TEST_FILES) {
        try ramp_samples.write_file(
            "/var/tmp/ramp_2s_1hz_signal_48000hz_sampling.wav"
        );
    }

    try expectEqual(0, ramp_samples.buffer[0]);
    try std.testing.expectApproxEqAbs(
        1,
        ramp_samples.buffer[47999],
        EPSILON
    );
    try expectEqual(0, ramp_samples.buffer[48000]);
}

// only meaningfull if serializing test data to disk
test "serialize a 24hz ramp to disk, to visualize ramp output" 
{
    const ramp_signal = SignalGenerator{
        .sample_rate_hz = 48000,
        .signal_frequency_hz = 24,
        .signal_duration_s = 1,
        .signal = .ramp,
        // .signal_amplitude = 4,
    };

    const ramp_samples = try ramp_signal.rasterized(
        std.testing.allocator,
        true,
    );
    defer ramp_samples.deinit();
    if (WRITE_TEST_FILES) {
        try ramp_samples.write_file_prefix(
            std.testing.allocator,
            TMPDIR,
            "24hz_signal.",
            ramp_signal,
        );
    }
}

test "sampling: frame phase slide 1: (time*1 freq*1 phase+0) 0,1,2,3->0,1,2,3"
{    
    const ramp_signal = SignalGenerator{
        .sample_rate_hz = 4,
        .signal_frequency_hz = 1,
        .signal_duration_s = 1,
        .signal = .ramp,
        .signal_amplitude = 4,
    };

    const ramp_samples = try ramp_signal.rasterized(
        std.testing.allocator,
        false,
    );

    defer ramp_samples.deinit();

    try expectEqual(false, ramp_samples.interpolating);

    // @TODO: return here after threading interpolating through
    const sample_to_output_crv = (
        try curve.linear_curve.Linear.init_identity(
            std.testing.allocator,
            &.{0, 2},
        )
    );
    defer sample_to_output_crv.deinit(std.testing.allocator);

    const output_sampling_info:DiscreteDatasourceIndexGenerator = .{
        .sample_rate_hz = 4,
    };

    const retimed_ramp_samples = try retimed_linear_curve(
        std.testing.allocator, 
        ramp_samples,
        sample_to_output_crv,
        false,
        output_sampling_info,
    );
    defer retimed_ramp_samples.deinit();

    try expectEqual(4, retimed_ramp_samples.buffer.len);

    const expected = &[_]sample_t{ 0, 1, 2, 3};

    try std.testing.expectEqualSlices(
        sample_t,
        expected,
        retimed_ramp_samples.buffer,
    );
}

test "sampling: frame phase slide 2: (time*2 bounds*1 freq*1 phase+0) 0,1,2,3->0,0,1,1"
{
    const ramp_signal = SignalGenerator{
        .sample_rate_hz = 4,
        .signal_frequency_hz = 1,
        .signal_duration_s = 1,
        .signal = .ramp,
        .signal_amplitude = 4,
    };

    const ramp_samples = try ramp_signal.rasterized(
        std.testing.allocator,
        false,
    );
    defer ramp_samples.deinit();

    const input_data = &[_]sample_t{ 0, 1, 2, 3};

    try std.testing.expectEqualSlices(
        sample_t,
        input_data,
        ramp_samples.buffer,
    );

    try expectEqual(false, ramp_samples.interpolating);

    // @TODO: return here after threading interpolating through
    const sample_to_output_crv = (
        try curve.linear_curve.Linear.init_identity(
            std.testing.allocator,
            &.{0, 1},
        )
    );
    defer sample_to_output_crv.deinit(std.testing.allocator);

    // don't want an identity
    sample_to_output_crv.knots[1].out = 0.5;

    const crv_str = try sample_to_output_crv.debug_json_str(
        std.testing.allocator
    );
    defer std.testing.allocator.free(crv_str);
    errdefer std.debug.print(
        "Sample to output curve: {s}\n",
        .{ crv_str}
    );

    // trivial check that curve behaves as expected
    try expectApproxEqAbs(
        0.5,
        try sample_to_output_crv.output_at_input(1.0),
        EPSILON
    );
    try expectApproxEqAbs(
        0.0,
        try sample_to_output_crv.output_at_input(0.0),
        EPSILON
    );

    const output_sampling_info : DiscreteDatasourceIndexGenerator = .{
        .sample_rate_hz = 4,
    };

    const output_ramp_samples = try retimed_linear_curve(
        std.testing.allocator, 
        ramp_samples,
        sample_to_output_crv,
        false,
        output_sampling_info,
    );
    defer output_ramp_samples.deinit();

    const expected = &[_]sample_t{ 0, 0, 1, 1};

    try std.testing.expectEqualSlices(
        sample_t,
        expected,
        output_ramp_samples.buffer,
    );

    try expectEqual(
        4,
        output_ramp_samples.buffer.len,
    );
}

test "sampling: frame phase slide 2.5: (time*2 bounds*2 freq*1 phase+0) 0,1,2,3->0,0,1,1,2,2,3,3"
{
    const ramp_signal = SignalGenerator{
        .sample_rate_hz = 4,
        .signal_frequency_hz = 1,
        .signal_duration_s = 1,
        .signal = .ramp,
        .signal_amplitude = 4,
    };

    const ramp_samples = try ramp_signal.rasterized(
        std.testing.allocator,
        false,
    );
    defer ramp_samples.deinit();

    const input_data = &[_]sample_t{ 0, 1, 2, 3};

    try std.testing.expectEqualSlices(
        sample_t,
        input_data,
        ramp_samples.buffer,
    );

    try expectEqual(false, ramp_samples.interpolating);

    // @TODO: return here after threading interpolating through
    const retimed_to_sample_crv = (
        try curve.linear_curve.Linear.init_identity(
            std.testing.allocator,
            &.{0, 2.0},
        )
    );
    defer retimed_to_sample_crv.deinit(std.testing.allocator);

    // don't want an identity
    retimed_to_sample_crv.knots[1].out = 1;

    // trivial check that curve behaves as expected
    try expectApproxEqAbs(
        0.5,
        try retimed_to_sample_crv.output_at_input(1.0),
        EPSILON
    );
    try expectApproxEqAbs(
        0.0,
        try retimed_to_sample_crv.output_at_input(0.0),
        EPSILON
    );

    const output_sampling_info : DiscreteDatasourceIndexGenerator = .{
        .sample_rate_hz = 4,
    };

    const output_ramp_samples = try retimed_linear_curve(
        std.testing.allocator, 
        ramp_samples,
        retimed_to_sample_crv,
        false,
        output_sampling_info,
    );
    defer output_ramp_samples.deinit();

    const expected = &[_]sample_t{ 0, 0, 1, 1, 2, 2, 3, 3};

    try std.testing.expectEqualSlices(
        sample_t,
        expected,
        output_ramp_samples.buffer,
    );

    try expectEqual(
        8,
        output_ramp_samples.buffer.len,
    );
}


// hold on even twos - short frames
test "sampling: frame phase slide 3: (time*1 freq*2 phase+0) 0,1,2,3->0,0,1,1..(over same duration, but with 2x the hz)"
{
    const ramp_signal = SignalGenerator{
        .sample_rate_hz = 4,
        .signal_frequency_hz = 1,
        .signal_duration_s = 1,
        .signal = .ramp,
        .signal_amplitude = 4,
    };

    const ramp_samples = try ramp_signal.rasterized(
        std.testing.allocator,
        false,
    );
    defer ramp_samples.deinit();

    const input_data = &[_]sample_t{ 0, 1, 2, 3};

    try std.testing.expectEqualSlices(
        sample_t,
        input_data,
        ramp_samples.buffer,
    );

    try expectEqual(false, ramp_samples.interpolating);

    // @TODO: return here after threading interpolating through
    const sample_to_output_crv = (
        try curve.linear_curve.Linear.init_identity(
            std.testing.allocator,
            &.{0, 1.0},
        )
    );
    defer sample_to_output_crv.deinit(std.testing.allocator);

    const crv_str = try sample_to_output_crv.debug_json_str(
        std.testing.allocator
    );
    defer std.testing.allocator.free(crv_str);
    errdefer std.debug.print(
        "Sample to output curve: {s}\n",
        .{ crv_str}
    );

    // trivial check that curve behaves as expected
    try expectApproxEqAbs(
        0.5,
        try sample_to_output_crv.output_at_input(0.5),
        EPSILON
    );
    try expectApproxEqAbs(
        0.0,
        try sample_to_output_crv.output_at_input(0.0),
        EPSILON
    );

    const output_to_inter_crv = try curve.inverted_linear(
        std.testing.allocator,
        sample_to_output_crv
    );
    defer output_to_inter_crv.deinit(std.testing.allocator);

    const output_sampling_info : DiscreteDatasourceIndexGenerator = .{
        .sample_rate_hz = 8,
    };

    const output_ramp_samples = try retimed_linear_curve(
        std.testing.allocator, 
        ramp_samples,
        output_to_inter_crv,
        false,
        output_sampling_info,
    );
    defer output_ramp_samples.deinit();

    const expected = &[_]sample_t{ 0, 0, 1, 1, 2, 2, 3, 3};

    try std.testing.expectEqualSlices(
        sample_t,
        expected,
        output_ramp_samples.buffer,
    );
    
    try expectApproxEqAbs(
        1.0,
        output_ramp_samples.extents().end_seconds,
        EPSILON
    );

    try expectEqual(
        8,
        output_ramp_samples.buffer.len,
    );

}

// hold on odd twos
test "sampling: frame phase slide 4: (time*2 freq*1 phase+0.5) 0,1,2,3->0,1,1,2"
{
    const ramp_signal = SignalGenerator{
        .sample_rate_hz = 4,
        .signal_frequency_hz = 1,
        .signal_duration_s = 1,
        .signal = .ramp,
        .signal_amplitude = 4,
    };

    const ramp_samples = try ramp_signal.rasterized(
        std.testing.allocator,
        false,
    );
    defer ramp_samples.deinit();

    //
    // 0s          1s
    // *--*--*--*--)
    // 0  1  2  3
    //
    // expand
    // 0s    0.5   1s    1.5   2s
    // *-----*-----*-----*----)
    // 0     1     2     3
    //
    // crop
    //0s  0.25    1s  1.25   2s
    // *--[--*-----*--)--*----)
    // 0     1     2     3
    //
    // 0.25 0.75
    // 0 1
    //
    // 0.5         1.5
    // *--*--*--*--)
    // 0  1  1  2
    //
    const input_data = &[_]sample_t{ 0, 1, 2, 3};

    try std.testing.expectEqualSlices(
        sample_t,
        input_data,
        ramp_samples.buffer,
    );

    try expectEqual(false, ramp_samples.interpolating);

    // @TODO: return here after threading interpolating through
    const inter_to_sample_crv = (
        try curve.linear_curve.Linear.init_identity(
            std.testing.allocator,
            &.{0, 2},
        )
    );
    defer inter_to_sample_crv.deinit(std.testing.allocator);

    inter_to_sample_crv.knots[0].out = 0;
    inter_to_sample_crv.knots[1].out = 1;

    const retime_to_inter_crv = (
        try curve.linear_curve.Linear.init_identity(
            std.testing.allocator,
            &.{0.25, 1.25},
        )
    );
    defer retime_to_inter_crv.deinit(std.testing.allocator);

    const retimed_to_sample_crv = try inter_to_sample_crv.project_curve_single_result(
        std.testing.allocator,
        retime_to_inter_crv,
    );
    defer retimed_to_sample_crv.deinit(std.testing.allocator);

    // trivial check that curve behaves as expected
    try expectApproxEqAbs(
        0.375,
        try retimed_to_sample_crv.output_at_input(0.75),
        EPSILON
    );
    try expectApproxEqAbs(
        0.125,
        try retimed_to_sample_crv.output_at_input(0.25),
        EPSILON
    );

    const output_sampling_info : DiscreteDatasourceIndexGenerator = .{
        .sample_rate_hz = 4,
    };

    const output_ramp_samples = try retimed_linear_curve(
        std.testing.allocator, 
        ramp_samples,
        retimed_to_sample_crv,
        false,
        output_sampling_info,
    );
    defer output_ramp_samples.deinit();

    const expected = &[_]sample_t{ 0, 1, 1 , 2};

    try std.testing.expectEqualSlices(
        sample_t,
        expected,
        output_ramp_samples.buffer,
    );
    
    try expectApproxEqAbs(
        1.0,
        output_ramp_samples.extents().end_seconds,
        EPSILON
    );
}

test "sampling: frame phase slide 5: arbitrary held frames 0,1,2->0,0,0,0,1,1,2,2,2"
{
    const ramp_signal = SignalGenerator{
        .sample_rate_hz = 4,
        .signal_frequency_hz = 1,
        .signal_duration_s = 1,
        .signal = .ramp,
        .signal_amplitude = 4,
    };

    const ramp_samples = try ramp_signal.rasterized(
        std.testing.allocator,
        false,
    );
    defer ramp_samples.deinit();

    const input_data = &[_]sample_t{ 0, 1, 2, 3};

    // test input data
    // ///////////////
    try std.testing.expectEqualSlices(
        sample_t,
        input_data,
        ramp_samples.buffer,
    );

    try expectEqual(false, ramp_samples.interpolating);
    // ///////////////

    var knots = [_]curve.ControlPoint{
        .{ .in = 0,    .out = 0 },
        .{ .in = 1.25, .out = 0 },
        .{ .in = 1.25, .out = 0.25 },
        .{ .in = 1.75, .out = 0.25 },
        .{ .in = 1.75, .out = 0.5 },
        .{ .in = 2.5,  .out = 0.5 },
    };

    const output_to_sample_crv = curve.Linear{
        .knots = &knots,
    };

    const output_sampling_info : DiscreteDatasourceIndexGenerator = .{
        .sample_rate_hz = 4,
    };

    const output_ramp_samples = try retimed_linear_curve(
        std.testing.allocator, 
        ramp_samples,
        output_to_sample_crv,
        false,
        output_sampling_info,
    );
    defer output_ramp_samples.deinit();

    const expected = &[_]sample_t{ 0, 0, 0, 0, 0, 1, 1, 2, 2, 2 };

    try std.testing.expectEqualSlices(
        sample_t,
        expected,
        output_ramp_samples.buffer,
    );
}

//@{
// test 4 <-- goal
// within the nomenclature of OTIO itself, describe samples on one media and
// resample them to another space (IE have a clip at 48khz and the timeline at
// 44khz)-
// 
// test 5 
// resample according to centered kernels
//@}

test "wav.zig generator test" 
{
    const samples_48 = SignalGenerator{
        .sample_rate_hz = 48000,
        .signal_frequency_hz = 100,
        .signal_amplitude = 1,
        .signal_duration_s = 1,
        .signal = .sine,
    };
    const s48 = try samples_48.rasterized(
        std.testing.allocator,
        true,
    );
    defer s48.deinit();

    if (WRITE_TEST_FILES) {
        try s48.write_file("/var/tmp/ours_givemesine.wav");
    }
}

test "retimed leak test"
{
    var buf = [_]sample_t{0, 1, 2, 3};

    const ramp_samples = Sampling{
        .allocator = std.testing.allocator,
        .interpolating = false,
        .sample_rate_hz = 4,
        .buffer = &buf,
    };

    var knots = [_]curve.ControlPoint{
        .{ .in = 0, .out = 0 },
        .{ .in = 1, .out = 1 },
    };
    const retimed_to_sample_crv = curve.Linear{
        .knots = &knots,
    };

    const output_sampling_info : DiscreteDatasourceIndexGenerator = .{
        .sample_rate_hz = 8,
    };

    const output_ramp_samples = try retimed_linear_curve(
        std.testing.allocator, 
        ramp_samples,
        retimed_to_sample_crv,
        false,
        output_sampling_info,
    );
    defer output_ramp_samples.deinit();
}
