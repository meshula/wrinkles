//! Sampling Library for OTIO V2
//!
//! Includes signal generators and samplers as well as tools for integrating
//! a sampling into the rest of the temporal framework.  Leverages libsamplerate
//! for test purposes.
//!
//! A "Sampling" represents a cyclical sampling, over time, of a signal,
//! including a buffer of the sample values.
//!
//! @TODO: handle acyclical sampling (IE - variable bitrate data, held frames)

const std = @import("std");
const libsamplerate = @import("libsamplerate").libsamplerate;
const kissfft = @import("kissfft").c;
const wav = @import("wav");

const curve = @import("curve");
const opentime = @import("opentime");
const topology = @import("topology");

const build_options = @import("build_options");

// configuration
const RESAMPLE_DEBUG_LOGGING = false;
const WRITE_TEST_FILES = build_options.write_sampling_test_wave_files;
const TMPDIR = build_options.test_data_out_dir;

/// type of a sample value, ie the amplitude in a sample in an audio buffer
pub const sample_value_t  = f32;
/// the type of an index of a sample in a sample buffer
pub const sample_index_t  = usize;
/// type of an ordinate in a continuous space that spans a sampling
pub const sample_ordinate_t  = opentime.Ordinate;

pub const sample_rate_base_t = u32;

// epsilon values for comparison against zero
const EPSILON_VALUE: sample_value_t = 1.0e-4;
// const EPSILON_ORD: sample_ordinate_t = opentime.Ordinate.EPSILON;

/// project a continuous ordinate into a discrete index sequence
pub fn project_instantaneous_cd(
    self: anytype,
    ord_continuous: sample_ordinate_t,
) sample_index_t
{
    const rate_hz_ord = self.sample_rate_hz.as_ordinate();
    return @as(
        sample_index_t,
        @intFromFloat(
            @floor(
                opentime.eval(
                    "ord * rate + (ONE / rate) / 2",
                    .{ 
                        .ord = ord_continuous,
                        .rate = rate_hz_ord, 
                        .ONE = sample_ordinate_t.ONE,
                    },
                ).as(f32)
            )
        )
    ) + self.start_index;
}

test "sampling: project_instantaneous_cd"
{
    const result = project_instantaneous_cd(
        SampleIndexGenerator{
            .sample_rate_hz = .{ .Int = 24 },
            .start_index = 12,
        },
        opentime.Ordinate.init(12),
    );

    //                          12*24 + 12
    try std.testing.expectEqual(300, result);
}

// @TODO: this should be symmetrical with cd - I think it is missing the 0.5
//        offset from the cd function
pub fn project_index_dc(
    self: anytype,
    ind_discrete: sample_index_t,
) opentime.ContinuousInterval
{
    var start = sample_ordinate_t.init(ind_discrete);
    start = start.sub(
        @as(sample_ordinate_t.BaseType, @floatFromInt(self.start_index))
    );
    const s_per_cycle = self.sample_rate_hz.inv_as_ordinate();
    start = start.mul(s_per_cycle);

    return .{
        .start = start,
        .end = start.add(s_per_cycle),
    };
}

test "sampling: project_index_dc"
{
    const result = project_index_dc(
        SampleIndexGenerator{
            .sample_rate_hz = .{ .Int = 24},
            .start_index = 12,
        },
        300,
    );

    try opentime.expectOrdinateEqual(
        12.0, result.start
    );
    try opentime.expectOrdinateEqual(
        12.0 + 1.0/24.0,
        result.end
    );
}

/// a set of samples and the parameters of those samples
pub const Sampling = struct {
    buffer: []sample_value_t,
    index_generator: SampleIndexGenerator,
    interpolating: bool,

    pub fn init(
        allocator: std.mem.Allocator,
        count:usize,
        index_generator: SampleIndexGenerator,
        interpolating: bool,
    ) !Sampling
    {
        const buffer: []sample_value_t = try allocator.alloc(sample_value_t, count);

        return .{
            .buffer = buffer,
            .index_generator = index_generator,
            .interpolating = interpolating,
        };
    }

    pub fn deinit(
        self: @This(),
        allocator: std.mem.Allocator,
    ) void 
    {
        allocator.free(self.buffer);
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
        
        var buf:[4096]u8 = undefined;
        var writer = file.writer(&buf);

        try wav.write_wav(
            &writer.interface,
            .i16,
            self.index_generator.sample_rate_hz.as_ordinate().as(
                sample_index_t
            ),
            1,
            sample_value_t,
            self.buffer,
        );
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
                "{s}/{s}{s}.amp_{d}_{d}s_{d}hz_signal_{f}hz_samples.wav",
                .{
                    dirname,
                    prefix,
                    @tagName(parent_signal.signal),
                    parent_signal.amplitude,
                    parent_signal.duration_s,
                    parent_signal.frequency_hz,
                    self.index_generator.sample_rate_hz,
                }
            )
        else 
            try std.fmt.allocPrint(
                allocator,
                "{s}/{s}_{d}hz_samples.wav",
                .{
                    dirname,
                    prefix,
                    self.index_generator.sample_rate_hz.Int,
                }
            )
        );
        defer allocator.free(name);

        return self.write_file(name);
    }

    /// fetch the value of the buffer at the provided ordinate
    pub fn sample_value_at_ordinate(
        self: @This(),
        input_ord: sample_ordinate_t,
    ) sample_value_t
    {
        return self.buffer[self.index_at_ordinate(input_ord)];
    }

    /// return the end points of an interval of the indices that fall within
    /// the bounds of the continuous interval in the input space
    ///
    /// assumes that indices will be linearly increasing.
    pub fn indices_within_interval(
        self: @This(),
        input_interval: opentime.ContinuousInterval,
    ) [2]sample_index_t
    {
        const start_index = self.index_generator.index_at_ordinate(
            input_interval.start
        );
        const end_index = self.index_generator.index_at_ordinate(
            input_interval.end
        );

        return .{ start_index, end_index };
    }

    /// fetch the slice of self.buffer that overlaps with the provided range
    pub fn samples_overlapping_interval(
        self: @This(),
        input_interval: opentime.ContinuousInterval,
    ) []sample_value_t
    {
        const index_bounds = self.indices_within_interval(
            input_interval,
        );

        return self.buffer[index_bounds[0]..index_bounds[1]];
    }

    /// assuming a time-0 start, build the range of continuous time
    /// ("intrisinsic space") of the sampling
    pub fn extents(
        self: @This(),
    ) opentime.ContinuousInterval
    {
        return .{
            .start = opentime.Ordinate.init(0),
            .end = self.index_generator.ordinate_at_index(
                self.buffer.len
            ),
        };
    }

    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) !void 
    {
        try writer.print(
            (
                  "Sampling{{ buffer.len: {d}, index_generator: {f}, "
                  ++ "interpolating: {any} }}"
            ),
            .
            {
                self.buffer.len,
                self.index_generator,
                self.interpolating,
            },
        );
    }
};

test "sampling: samples_overlapping_interval" 
{
    const allocator = std.testing.allocator;

    const sine_signal_100hz = SignalGenerator{
        .frequency_hz = 100,
        .amplitude = 1,
        .duration_s = opentime.Ordinate.init(1),
        .signal = .sine,
    };
    const index_generator = SampleIndexGenerator{
        .sample_rate_hz = .{ .Int = 48000 }, 
    };
    const sine_100hz_samples_48khz = try sine_signal_100hz.rasterized(
        allocator,
        index_generator,
        true,
    );
    defer sine_100hz_samples_48khz.deinit(allocator);

    const first_half_samples = sine_100hz_samples_48khz.samples_overlapping_interval(
        opentime.ContinuousInterval.init(.{ .start = 0, .end = 0.5 }),
    );

    try std.testing.expectEqual(
        index_generator.sample_rate_hz.as_ordinate().div(2.0).as(sample_index_t),
        first_half_samples.len,
    );
}

/// a rational number for expressing rates
pub const URational = struct {
    /// Numerator (Cycles)
    num: sample_rate_base_t,
    /// Denominator (Seconds)
    den: sample_rate_base_t,

    /// convert the rational to a floating point number
    pub fn as_float(
        self: @This(),
    ) sample_ordinate_t.BaseType
    {
        const num : f32 = @floatFromInt(self.num);
        const den : f32 = @floatFromInt(self.den);

        return num/den;
    }
};

pub const RateSpecifier = union (enum) {
    Int: sample_rate_base_t,
    Rat: URational,

    pub fn as_ordinate(
        self: @This(),
    ) sample_ordinate_t
    {
        return opentime.Ordinate.init(
            @as(
                sample_ordinate_t.BaseType,
                switch (self) {
                    inline .Int => |b| @floatFromInt(b),
                    inline .Rat => |r| r.as_float(),
                }
            )
        );
    }

    // 1 / self as an ordaninte
    pub fn inv_as_ordinate(
        self: @This(),
    ) sample_ordinate_t
    {
        return opentime.Ordinate.init(
            1.0 / 
            @as(
                sample_ordinate_t.BaseType,
                switch (self) {
                    inline .Int => |b| @floatFromInt(b),
                    inline .Rat => |r| r.as_float(),
                }
            )
        );
    }

    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) !void 
    {
        try writer.print(
            "Rate{{ ",
            .{},
        );

        switch (self) {
            inline .Int => |b| try writer.print("{d}", .{ b }),
            inline .Rat => |r| try writer.print("{d}/{d}", .{r.num, r.den}),
        }

        try writer.print(
            " }}",
            .{},
        );
    }
};

/// generate indices based on a sample rate
pub const SampleIndexGenerator = struct {
    sample_rate_hz: RateSpecifier,
    start_index: sample_index_t = 0,

    // pub fn make_phase_ordinate(
    //     self: @This(),
    //     ord: opentime.Ordinate,
    // ) PhaseOrdinate
    // {
    // }
    //
    // pub fn make_ordinate(
    //     self: @This(),
    //     ord: opentime.Ordinate,
    // ) Ordinate
    // {
    // }

    pub fn index_at_ordinate(
        self: @This(),
        continuous_ord: sample_ordinate_t,
    ) sample_index_t
    {
        const hz_f = self.sample_rate_hz.as_ordinate();
        const inv_hz_f = self.sample_rate_hz.inv_as_ordinate();

        return @intFromFloat(
            @floor(
                opentime.eval(
                    "ord * hz_f + ( inv_hz_f * 0.5)",
                    .{
                        .ord = continuous_ord,
                        .hz_f = hz_f,  
                        .inv_hz_f = inv_hz_f,  
                    }
                ).as(f32)
            )
        );
    }

    pub fn ordinate_at_index(
        self: @This(),
        index: sample_index_t,
    ) sample_ordinate_t
    {
        return (
            opentime.Ordinate.init(index).div(self.sample_rate_hz.as_ordinate())
        );
    }

    pub fn buffer_size_for_length(
        self: @This(),
        length: sample_ordinate_t,
    ) sample_index_t
    {
        // @TODO: ceil?  Floor?
        return @intFromFloat(
            length.mul(self.sample_rate_hz.as_ordinate()).as(f32)
        );
    }

    pub fn ord_interval_for_index(
        self: @This(),
        index: sample_index_t,
    ) opentime.interval.ContinuousInterval
    {
        const s_per_cycle = self.sample_rate_hz.inv_as_ordinate();

        const index_ord = sample_ordinate_t.init(index);

        return .{
            .start = index_ord.mul(s_per_cycle),
            .end = (index_ord.add(1)).mul(s_per_cycle),
        };
    }

    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) !void 
    {
        try writer.print(
            "DiscreteIndexGenerator{{ sample_rate_hz: {f}, start_index: {d} }}",
            .{ self.sample_rate_hz, self.start_index, },
        );
    }
};

/// compact representation of a signal, can be rasterized into a buffer
pub const SignalGenerator = struct {
    frequency_hz: u32,
    amplitude: sample_value_t = 1.0,
    duration_s: sample_ordinate_t,
    signal: Signal,

    const Signal= enum {
        sine,
        ramp,
    };

    /// fill a buffer with values generated by this signal generator
    pub fn rasterized(
        self:@This(),
        allocator: std.mem.Allocator,
        index_generator: SampleIndexGenerator,
        interpolating_samples: bool,
    ) !Sampling
    {
        const sample_hz  = index_generator.sample_rate_hz.as_ordinate();

        const samples_per_cycle = sample_hz.div(
            @as(f32, @floatFromInt(self.frequency_hz))
        );

        const result = try Sampling.init(
            allocator, 
            // signal_duration_s is promoted to an f64 for precision in the
            // loop boundary
            @intFromFloat(@ceil(self.duration_s.mul(sample_hz).as(f32))),
            index_generator,
            interpolating_samples,
        );

        const two_pi = std.math.pi * 2.0;

        // fill the sample buffer
        for (0.., result.buffer)
            |current_index, *sample|
        {
            const phase_angle:sample_ordinate_t = (
                sample_ordinate_t.init(current_index).div(samples_per_cycle)
            );

            const mod_phase_angle = @mod(phase_angle.as(f32), 1.0,);

            switch (self.signal) {
                .sine => {
                    sample.* = self.amplitude * std.math.sin(
                        two_pi * mod_phase_angle
                    );
                },
                // @TODO: not bandwidth-limited, cannot be used for a proper
                //        synthesizer
                .ramp => {
                    sample.* = (
                        self.amplitude 
                        * curve.bezier_math.lerp(
                            mod_phase_angle,
                            @as(sample_value_t,0),
                            1,
                        )
                    );
                }
            }
        }

        return result;
    }
};

test "sampling: rasterizing the sine" 
{
    const allocator = std.testing.allocator;

    const sine_signal_100hz = SignalGenerator{
        .frequency_hz = 100,
        .amplitude = 1,
        .duration_s = opentime.Ordinate.init(1),
        .signal = .sine,
    };

    const sine_100hz_samples_48khz = try sine_signal_100hz.rasterized(
        allocator,
        .{ .sample_rate_hz = .{ .Int = 48000 } },
        true,
    );
    defer sine_100hz_samples_48khz.deinit(allocator);

    // check some known quantities
    try std.testing.expectEqual(
        48000,
        sine_100hz_samples_48khz.buffer.len
    );
    try std.testing.expectEqual(
        @as(sample_value_t, 0),
        sine_100hz_samples_48khz.buffer[0]
    );
}

/// returns the peak to peak distance in indices of the samples in the buffer
pub fn peak_to_peak_distance(
    samples: []const sample_value_t,
) !sample_index_t 
{
    var maybe_last_peak_index:?sample_index_t = null;
    var maybe_distance_in_indices:?sample_index_t = null;

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

test "sampling: peak_to_peak_distance: sine/48khz sample/100hz signal"
{
    const allocator = std.testing.allocator;

    const sine_signal_100hz = SignalGenerator{
        .frequency_hz = 100,
        .amplitude = 1,
        .duration_s = opentime.Ordinate.init(1),
        .signal = .sine,
    };
    const sine_100_samples_48khz = try sine_signal_100hz.rasterized(
        allocator,
        .{ .sample_rate_hz = .{ .Int = 48000 }, },
        true,
    );
    defer sine_100_samples_48khz.deinit(allocator);

    const sine_samples_48khz_100_p2p = try peak_to_peak_distance(
        sine_100_samples_48khz.buffer
    );

    try std.testing.expectEqual(480, sine_samples_48khz_100_p2p);
}

test "sampling: peak_to_peak_distance: sine/48khz sample/50hz signal"
{
    const allocator = std.testing.allocator;

    const sine_signal_48khz_50 = SignalGenerator{
        .frequency_hz = 50,
        .amplitude = 1,
        .duration_s = opentime.Ordinate.init(1),
        .signal = .sine,
    };
    const sine_samples_48_50 = try sine_signal_48khz_50.rasterized(
        allocator,
        .{ .sample_rate_hz = .{ .Int = 48000 }, },
        true,
    );
    defer sine_samples_48_50.deinit(allocator);

    const sine_samples_48_50_p2p = try peak_to_peak_distance(
        sine_samples_48_50.buffer
    );

    try std.testing.expectEqual(960, sine_samples_48_50_p2p);
}

test "sampling: peak_to_peak_distance: sine/96khz sample/100hz signal"
{
    const allocator = std.testing.allocator;

    const sine_signal_100 = SignalGenerator{
        .frequency_hz = 100,
        .amplitude = 1,
        .duration_s = opentime.Ordinate.init(1),
        .signal = .sine,
    };
    const sine_samples_96_100 = try sine_signal_100.rasterized(
        allocator,
        .{ .sample_rate_hz = .{ .Int = 96000 } , },
        true,
    );
    defer sine_samples_96_100.deinit(allocator);

    const sine_samples_96_100_p2p = try peak_to_peak_distance(
        sine_samples_96_100.buffer
    );

    try std.testing.expectEqual(960, sine_samples_96_100_p2p);
}

// test 0 - ensure that the contents of the c-library are visible
test "sampling: c lib interface test" 
{
    // libsamplerate
    try std.testing.expectEqual(libsamplerate.SRC_SINC_BEST_QUALITY, 0);

    // kiss_fft
    const cpx = kissfft.kiss_fft_cpx{ .r = 1, .i = 1 };
    try std.testing.expectEqual(cpx.r, 1);
}

/// resample in_samples to output_d_sampling_info
pub fn resampled_dd(
    allocator: std.mem.Allocator,
    input_d_samples: Sampling,
    output_d_sampling_info: SampleIndexGenerator,
) !Sampling
{
    const resample_ratio = (
        output_d_sampling_info.sample_rate_hz.as_ordinate().as(f64)
        / input_d_samples.index_generator.sample_rate_hz.as_ordinate().as(f64)
    );

    const num_output_samples: sample_index_t =
        @intFromFloat(
            @floor(
                @as(f64, @floatFromInt(input_d_samples.buffer.len)) 
                * resample_ratio
            )
        );

    const result = try Sampling.init(
        allocator,
        num_output_samples,
        output_d_sampling_info,
        input_d_samples.interpolating,
    );

    var src_data : libsamplerate.SRC_DATA = .{
        .data_in = @ptrCast(input_d_samples.buffer.ptr),
        .input_frames = @intCast(input_d_samples.buffer.len),
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

/// Walk across each output samples described by the output_d_sampling_info,
/// and transform each index into the input space to determine which indices
/// from the input correspond to the output samples that need to be rendered.
///
/// If the sample is interpolating, will resample by interpolation via
/// libsamplerate, otherwise will use heuristic to pick the sample value to
/// hold from the input sampling.
///
/// result is a sample buffer computed from the input sampling.
pub fn transform_resample_dd(
    allocator: std.mem.Allocator,
    input_d_sampling: Sampling,
    output_c_to_input_c: topology.Topology,
    output_d_sampling_info: SampleIndexGenerator,
    /// for interpolating samplings, libsamplerate can be told to make the rate 
    /// of change be a step function rather than using the linearized curve in
    /// the output_c_to_input_c directly.
    step_transform: bool,
) !Sampling
{
    // bound input_c_to_output_c_topo by the implicit space of in_samples
    const input_c_bound = input_d_sampling.extents();

    const output_c_to_input_c_trimmed = (
        try output_c_to_input_c.trim_in_output_space(
            allocator,
            input_c_bound,
        )
    );
    defer output_c_to_input_c_trimmed.deinit(allocator);

    var output_buffer: std.ArrayList(sample_value_t) = .empty;

    // walk across each mapping in the trimmed topology and transform (or omit)
    // the samples into the output space
    for (output_c_to_input_c_trimmed.mappings)
        |output_c_to_input_c_m|
    {
        switch (output_c_to_input_c_m) {
            .empty => |e| {
                const output_range = e.output_bounds();

                const output_buffer_size = (
                    output_d_sampling_info.buffer_size_for_length(
                        output_range.duration()
                    )
                );

                const empty_sampling = try Sampling.init(
                    allocator,
                    output_buffer_size,
                    output_d_sampling_info,
                    false,
                );
                defer empty_sampling.deinit(allocator);

                try output_buffer.appendSlice(
                    allocator,
                    empty_sampling.buffer,
                );
            },
            .linear => |lin| {
                const new_sampling = (
                    try transform_resample_linear_dd(
                        allocator,
                        input_d_sampling,
                        lin,
                        output_d_sampling_info,
                        step_transform,
                    )
                );
                defer new_sampling.deinit(allocator);
                try output_buffer.appendSlice(
                    allocator,
                    new_sampling.buffer,
                );
            },
            .affine => |aff| {
                const ib = aff.input_bounds();
                const ob = aff.output_bounds();

                const lin = (
                    topology.mapping.MappingCurveLinearMonotonic{
                        .input_to_output_curve = .{
                            .knots = &.{
                                .{ .in = ib.start, .out = ob.start },
                                .{ .in = ib.end, .out = ob.end },
                            },
                        },
                    }
                );

                const new_sampling = (
                    try transform_resample_linear_dd(
                        allocator,
                        input_d_sampling,
                        lin,
                        output_d_sampling_info,
                        step_transform,
                    )
                );
                defer new_sampling.deinit(allocator);
                try output_buffer.appendSlice(
                    allocator,
                    new_sampling.buffer,
                );
            },
        }
    }

    return .{
        .buffer = try output_buffer.toOwnedSlice(allocator),
        .index_generator = output_d_sampling_info,
        .interpolating = input_d_sampling.interpolating,
    };
}

/// transform and resample in_samples into a new Sampling
pub fn transform_resample_linear_dd(
    allocator: std.mem.Allocator,
    input_d_samples: Sampling,
    output_c_to_input_c_crv: topology.mapping.MappingCurveLinearMonotonic,
    output_d_sampling_info: SampleIndexGenerator,
    step_transform: bool,
) !Sampling
{
    return switch (input_d_samples.interpolating) {
        true => try transform_resample_linear_interpolating_dd(
            allocator,
            input_d_samples,
            output_c_to_input_c_crv.input_to_output_curve,
            output_d_sampling_info,
            step_transform,
        ),
        false => try transform_resample_linear_non_interpolating_dd(
            allocator,
            input_d_samples,
            output_c_to_input_c_crv,
            output_d_sampling_info,
        ),
    };
}

/// analytical projection of a sampling modeled by an identity function
/// through the retiming curve and back to a discrete sampling
///
/// the retiming curve maps an implicit continuous space of the samples to the
/// transformed space
/// 
/// ->
///
/// the retiming curve maps the transformed space to the implicit space of the
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
pub fn transform_resample_linear_non_interpolating_dd(
    allocator: std.mem.Allocator,
    input_d_samples: Sampling,
    output_c_to_input_c_crv: topology.mapping.MappingCurveLinearMonotonic,
    output_d_sampling_info: SampleIndexGenerator,
) !Sampling
{
    const input_d_extents_c = input_d_samples.extents();

    const input_c_to_input_d = topology.mapping.MappingAffine{
        .input_bounds_val = input_d_extents_c,
        .input_to_output_xform = .IDENTITY,
    };

    const output_c_to_input_d = (
        try topology.mapping.join(
            allocator,
            .{
                .a2b = output_c_to_input_c_crv.mapping(),
                .b2c = input_c_to_input_d.mapping(),
            },
        )
    );
    defer output_c_to_input_d.deinit(allocator);

    const output_d_extents = (
        output_c_to_input_d.input_bounds()
    );

    std.debug.assert(output_d_extents.is_infinite() == false);

    const num_output_samples = (
        output_d_sampling_info.buffer_size_for_length(
            output_d_extents.duration()
        )
    );

    const output_buffer_size = num_output_samples;

    const output_sampling = try Sampling.init(
        allocator,
        output_buffer_size,
        output_d_sampling_info,
        false,
    );
    errdefer output_sampling.deinit(allocator);

    // fill the output buffer
    for (output_sampling.buffer, 0..)
        |*output_sample, output_index|
    {
        const output_sample_interval = (
            output_d_sampling_info.ord_interval_for_index(output_index)
        );

        const output_sample_ord = (
            output_sample_interval.start.add(output_d_extents.start)
        );

        // output -> input time (continuous -> continuous)
        const input_ord = (
            (
             output_c_to_input_d.project_instantaneous_cc(
                 output_sample_ord,
             ).ordinate() 
            )
            catch |err| 
            {
                // out of bounds means that this sample has a value of 0
                if (err == error.OutOfBounds) {
                    output_sample.* = 0;
                    continue;
                }

                return err;
            }
        );

        // input ordinate -> input index (continuous -> discrete)
        const input_sample_index = (
            input_d_samples.index_generator.index_at_ordinate(input_ord)
        );

        output_sample.* = input_d_samples.buffer[input_sample_index];
    }

    return output_sampling;
}

/// transform and interpolate the in_samples buffer using libsamplerate
pub fn transform_resample_linear_interpolating_dd(
    allocator: std.mem.Allocator,
    input_d_samples: Sampling,
    output_c_to_input_c_crv: curve.Linear.Monotonic,
    output_sampling_info: SampleIndexGenerator,
    step_transform: bool,
) !Sampling
{
    var output_buffer_size:usize = 0;

    const TransformSpec = struct {
        /// ratio of output sample count to input sample count
        transform_ratio: f32,
        output_samples: usize,
        input_samples: usize,
        input_data: []sample_value_t,
    };

    var transform_specs: std.ArrayList(TransformSpec) = .{};
    defer transform_specs.deinit(allocator);

    for (
        output_c_to_input_c_crv.knots[0..output_c_to_input_c_crv.knots.len-1],
        output_c_to_input_c_crv.knots[1..]
    )  
        |l_knot, r_knot|
    {    
        const relevant_sample_indices = (
            input_d_samples.indices_within_interval(
                .{.start = l_knot.in,.end = r_knot.in },
            )
        );
        const relevant_input_samples = input_d_samples.buffer[
            relevant_sample_indices[0]..
        ];
        if (relevant_input_samples.len == 0) {
            return error.NoRelevantSamples;
        }
        const input_samples = (
            relevant_sample_indices[1] - relevant_sample_indices[0]
        );

        const sample_rate_f = (
            output_sampling_info.sample_rate_hz.as_ordinate()
        );
        const inv_rate_f = (
            output_sampling_info.sample_rate_hz.inv_as_ordinate()
        );

        const output_samples:sample_index_t = @intFromFloat(
            @floor(
                opentime.eval(
                    "(r - l) * rate + inv_rate * 0.5",
                    .{ 
                        .r = r_knot.out, 
                        .l = l_knot.out,
                        .rate = sample_rate_f,
                        .inv_rate = inv_rate_f,
                    }
                ).as(f32)
            )
        );

        if (output_samples == 0) {
            return error.NoOutputSamplesToCompute;
        }

        const transform_ratio:f32 = (
            ( @as(f32, @floatFromInt(output_samples))) 
            / (
                @as(f32, @floatFromInt(input_samples))
            )
        );

        output_buffer_size += output_samples;

        try transform_specs.append(
            allocator,
            .{
                .transform_ratio = transform_ratio,
                .output_samples = output_samples,
                .input_data = relevant_input_samples,
                .input_samples = input_samples,
            }
        );
    }

    const full_output_buffer = try allocator.alloc(
        sample_value_t,
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
        .data_in = @ptrCast(input_d_samples.buffer.ptr),
        .data_out = @ptrCast(output_buffer.ptr),
        .input_frames = 100,
        .output_frames = 100,
        // means that we're leaving additional data in the input buffer past
        // the end
        .end_of_input = 0,
    };

    if (RESAMPLE_DEBUG_LOGGING) {
        std.log.debug(" \n\n----- resample info dump -----\n", .{});
    }

    var input_transform_samples = input_d_samples.buffer[0..];

    // walk across each transform spec to compute the output samples
    // XXX: not a for loop because the condition that advances this counter 
    var transform_index:sample_index_t = 0;
    while (transform_index < transform_specs.items.len)
    {
        // setup this chunk
        var spec = &transform_specs.items[transform_index];
        src_data.src_ratio = spec.transform_ratio;
        src_data.input_frames = @intCast(input_transform_samples.len);
        src_data.output_frames = @intCast(spec.output_samples);
        
        if (step_transform) 
        {
            // calling this function forces it to be a step function
            _ = libsamplerate.src_set_ratio(src_state, spec.transform_ratio);
        }

        if (transform_index == transform_specs.items.len - 1)
        {
            src_data.end_of_input = 1;
        }

        // process the chunk
        const lsr_error = libsamplerate.src_process(
            src_state,
            &src_data,
        );
        if (lsr_error != 0) {
            return error.LibSampleRateError;
        }

        if (RESAMPLE_DEBUG_LOGGING) 
        {
            std.log.debug(
                "in provided: {d} in used: {d} out requested: {d} out "
                ++ "generated: {d} ",
                .{
                    src_data.input_frames,
                    src_data.input_frames_used,
                    src_data.output_frames,
                    src_data.output_frames_gen,
                }
            );
            std.log.debug(
                "ratio: {d}\n",
                .{
                    src_data.src_ratio,
                }
            );
        }

        // slide buffers forward
        input_transform_samples = input_transform_samples[
            @intCast(src_data.input_frames_used)..
        ];
        src_data.data_in = @ptrCast(input_transform_samples.ptr);
        output_buffer = output_buffer[@intCast(src_data.output_frames_gen)..];
        src_data.data_out = @ptrCast(output_buffer.ptr);

        // if its time to advance to the next chunk
        if (
            src_data.output_frames <= 0 
            or input_transform_samples.len == 0
        )
        {
            transform_index += 1;
        }
        else
        {
            // slide buffers forward
            spec.output_samples -= @intCast(src_data.output_frames_gen);
        }
    }

    return Sampling{
        .buffer = full_output_buffer,
        .index_generator = output_sampling_info,
        .interpolating = true,
    };
}

// test 1
// have a set of samples over 48khz, resample them to 44khz
test "sampling: resample from 48khz to 44" 
{
    const allocator = std.testing.allocator;

    const sine_signal_48kz_100 = SignalGenerator{
        .frequency_hz = 100,
        .amplitude = 1,
        .duration_s = opentime.Ordinate.init(1),
        .signal = .sine,
    };
    const sine_samples_48khz_100 = (
        try sine_signal_48kz_100.rasterized(
            allocator,
            .{ .sample_rate_hz = .{ .Int = 48000 } , },
            true,
        )
    );
    defer sine_samples_48khz_100.deinit(allocator);

    if (WRITE_TEST_FILES) {
        try sine_samples_48khz_100.write_file_prefix(
            allocator,
            TMPDIR,
            "resample_test_input.",
            sine_signal_48kz_100,
        );
    }

    const sine_samples_44khz = try resampled_dd(
        allocator,
        sine_samples_48khz_100,
        .{ .sample_rate_hz = .{ .Int = 44100 } },
    );
    defer sine_samples_44khz.deinit(allocator);

    if (WRITE_TEST_FILES) {
        try sine_samples_44khz.write_file_prefix(
            allocator,
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
    try std.testing.expectEqual(441, sine_samples_44khz_p2p);
}

// test 2
// have a set of samples over 48khz, transform them with a linear curve and then
// resample them to 44khz
test "sampling: transform 48khz samples: ident-2x-ident, then resample to 44.1khz" 
{
    const allocator = std.testing.allocator;

    const samples_48 = SignalGenerator{
        .frequency_hz = 100,
        .amplitude = 1,
        .duration_s = opentime.Ordinate.init(4),
        .signal = .sine,
    };

    const s48 = try samples_48.rasterized(
        allocator,
        .{ .sample_rate_hz = .{ .Int = 48000 } , },
        true,
    );
    defer s48.deinit(allocator);

    if (WRITE_TEST_FILES) {
        try s48.write_file_prefix(
            allocator,
            TMPDIR,
            "transform_test_input.",
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

    var transform_curve_segments = [_]curve.Bezier.Segment{
        // identity
        curve.Bezier.Segment.init_identity(
            opentime.Ordinate.init(0),
            opentime.Ordinate.init(1.0)
        ),
        // go up
        curve.Bezier.Segment.init_from_start_end(
            curve.ControlPoint.init(.{ .in = 1.0, .out = 1.0 }),
            curve.ControlPoint.init(.{ .in = 2.0, .out = 3.0 }),
        ),
        // identity
        curve.Bezier.Segment.init_from_start_end(
            curve.ControlPoint.init(.{ .in = 2.0, .out = 3.0 }),
            curve.ControlPoint.init(.{ .in = 3.0, .out = 4.0 }),
        ),
    };
    const transform_curve : curve.Bezier = .{
        .segments = &transform_curve_segments,
    };
    if (WRITE_TEST_FILES) {
        try curve.write_json_file_curve(
            allocator,
            transform_curve,
            "/var/tmp/ours_transform_curve.curve.json"
        );
    }

    const output_sampling_info = s48.index_generator;

    const input_to_output_cc = try topology.Topology.init_bezier(
        allocator,
        transform_curve.segments,
    );
    defer input_to_output_cc.deinit(allocator);

    const samples_48_transformd = try transform_resample_dd(
        allocator,
        s48,
        input_to_output_cc,
        output_sampling_info,
        true,
    );
    defer samples_48_transformd.deinit(allocator);
    if (WRITE_TEST_FILES) {
        try samples_48_transformd.write_file_prefix(
            allocator,
            TMPDIR,
            "transform_test_transformd_pre_resample.",
            samples_48,
        );
    }

    const samples_44 = try resampled_dd(
        allocator,
        samples_48_transformd,
        .{
            .sample_rate_hz = .{ .Int = 44100 } 
        },
    );
    defer samples_44.deinit(allocator);
    if (WRITE_TEST_FILES) {
        try samples_44.write_file_prefix(
            allocator,
            TMPDIR,
            "transform_test_output.",
            samples_48,
        );
    }

    // identity
    const samples_44_p2p_0p25 = try peak_to_peak_distance(
        samples_44.buffer[0..11025]
    );
    try std.testing.expectEqual(
        441,
        samples_44_p2p_0p25
    );

    // 2x
    const samples_44_p2p_0p5 = try peak_to_peak_distance(
        samples_44.buffer[48100..52000]
    );
    try std.testing.expectEqual(882, samples_44_p2p_0p5);

    // identity
    const samples_44_p2p_1p0 = try peak_to_peak_distance(
        samples_44.buffer[(3*48000 + 100)..]
    );
    try std.testing.expectEqual(441, samples_44_p2p_1p0);
}

// test 3
// transform a set of samples with a cubic function.  also linearize the function
// at an intentionally low rate to reproduce an error we've seen on some
// editing systems with retiming
test "sampling: transform 48khz samples with a nonlinear acceleration curve and resample" 
{
    const allocator = std.testing.allocator;

    const samples_48 = SignalGenerator{
        .frequency_hz = 100,
        .amplitude = 1,
        .duration_s = opentime.Ordinate.init(4),
        .signal = .sine,
    };
    const s48 = try samples_48.rasterized(
        allocator,
        .{ .sample_rate_hz = .{ .Int = 48000 } , },
        true,
    );
    defer s48.deinit(allocator);

    var cubic_transform_curve_segments = [_]curve.Bezier.Segment{
        // identity
        curve.Bezier.Segment.init_identity(
            opentime.Ordinate.init(0),
            opentime.Ordinate.init(1),
        ),
        // go up
        curve.Bezier.Segment.init_f32(
            .{
                .p0 = .{ .in = 1, .out = 1.0 },
                .p1 = .{ .in = 1.5, .out = 1.25 },
                .p2 = .{ .in = 2, .out = 1.35 },
                .p3 = .{ .in = 2.5, .out = 1.5 },
            }
        ),
    };
    const cubic_transform_curve : curve.Bezier = .{
        .segments = &cubic_transform_curve_segments
    };
    if (WRITE_TEST_FILES) {
        try curve.write_json_file_curve(
            allocator,
            cubic_transform_curve,
            "/var/tmp/ours_transform_24hz.linear.json"
        );
    }

    const output_sampling_info = s48.index_generator;

    const input_to_output_cc = try topology.Topology.init_bezier(
        allocator,
        cubic_transform_curve.segments,
    );
    defer input_to_output_cc.deinit(allocator);

    const samples_48_transformd_cubic = try transform_resample_dd(
        allocator,
        s48,
        input_to_output_cc,
        output_sampling_info,
        true,
    );
    defer samples_48_transformd_cubic.deinit(allocator);

    if (WRITE_TEST_FILES)
    {
        try samples_48_transformd_cubic.write_file_prefix(
            allocator,
            TMPDIR,
            "transform_cubic_test_transformd_pre_resample.",
            samples_48,
        );
    }

    // linearize at 24hz
    const transform_curve_extents = (
        cubic_transform_curve.extents_input()
    );
    const inc:sample_value_t = 4.0/24.0;

    var knots: std.ArrayList(curve.ControlPoint) = .{};
    defer knots.deinit(allocator);

    try knots.append(
        allocator,
        .{
            .in = transform_curve_extents.start,
            .out = try cubic_transform_curve.output_at_input(
                transform_curve_extents.start
            ),
        }
    );

    var t = transform_curve_extents.start.add(inc);
    while (t.lt(transform_curve_extents.end))
        : (t = t.add(inc))
    {
        try knots.append(
            allocator,
            .{
                .in = t,
                .out = try cubic_transform_curve.output_at_input(t),
            }
        );
    }

    const transform_24hz_lin = curve.Linear{
        .knots = try knots.toOwnedSlice(allocator),
    };
    defer transform_24hz_lin.deinit(allocator);

    const input_to_output_lin_cc = 
        (
         try topology.Topology.init_from_linear(
             allocator,
             transform_24hz_lin,
         )
    );
    defer input_to_output_lin_cc.deinit(allocator);

    if (WRITE_TEST_FILES) {
        try curve.write_json_file_curve(
            allocator,
            transform_24hz_lin,
            "/var/tmp/ours_transform_24hz.linear.json"
        );
        try curve.write_json_file_curve(
            allocator,
            cubic_transform_curve,
            "/var/tmp/ours_transform_acceleration.curve.json"
        );
    }

    const samples_48_transformd = try transform_resample_dd(
        allocator,
        s48,
        input_to_output_lin_cc,
        output_sampling_info,
        true,
    );
    defer samples_48_transformd.deinit(allocator);

    if (WRITE_TEST_FILES) {
        try samples_48_transformd.write_file_prefix(
            allocator,
            TMPDIR,
            "transform_cubic_test_transformd_linearized24hz_pre_resample.",
            samples_48,
        );
    }

    const samples_44 = try resampled_dd(
        allocator,
        samples_48_transformd,
        .{
            .sample_rate_hz = .{ .Int = 44100 } 
        },
    );
    defer samples_44.deinit(allocator);

    if (WRITE_TEST_FILES) {
        try samples_44.write_file_prefix(
            allocator,
            TMPDIR,
            "transform_cubic_test_transformd_linearized24hz_resampled.",
            samples_48,
        );
    }

    // identity
    const samples_44_p2p_0p25 = try peak_to_peak_distance(
        samples_44.buffer[0..11025]
    );
    try std.testing.expectEqual(
        441,
        samples_44_p2p_0p25
    );

    // 2x
    const samples_44_p2p_0p5 = try peak_to_peak_distance(
        samples_44.buffer[(44100+1000)..]
    );
    try std.testing.expectEqual(
        207,
        samples_44_p2p_0p5
     );
}

test "sampling: frame phase slide 1: (identity) 0,1,2,3->0,1,2,3"
{
    const allocator = std.testing.allocator;

    const ramp_signal = SignalGenerator{
        .frequency_hz = 1,
        .duration_s = opentime.Ordinate.init(2),
        .signal = .ramp,
    };

    const ramp_samples = try ramp_signal.rasterized(
        allocator,
        .{
            .sample_rate_hz = .{ .Int = 48000 }, 
        },
        false,
    );
    defer ramp_samples.deinit(allocator);
    if (WRITE_TEST_FILES) {
        try ramp_samples.write_file(
            "/var/tmp/ramp_2s_1hz_signal_48000hz_sampling.wav"
        );
    }

    try std.testing.expectEqual(0, ramp_samples.buffer[0]);
    try std.testing.expectApproxEqAbs(
        1,
        ramp_samples.buffer[47999],
        EPSILON_VALUE,
    );
    try std.testing.expectEqual(0, ramp_samples.buffer[48000]);
}

// only meaningfull if serializing test data to disk
test "sampling: serialize a 24hz ramp to disk, to visualize ramp output" 
{
    const allocator = std.testing.allocator;

    const ramp_signal = SignalGenerator{
        .frequency_hz = 24,
        .duration_s = opentime.Ordinate.init(1),
        .signal = .ramp,
        // .signal_amplitude = 4,
    };

    const ramp_samples = try ramp_signal.rasterized(
        allocator,
        .{
            .sample_rate_hz = .{ .Int = 48000 }, 
        },
        true,
    );
    defer ramp_samples.deinit(allocator);
    if (WRITE_TEST_FILES) {
        try ramp_samples.write_file_prefix(
            allocator,
            TMPDIR,
            "24hz_signal.",
            ramp_signal,
        );
    }
}

test "sampling: frame phase slide 1: (time*1 freq*1 phase+0) 0,1,2,3->0,1,2,3"
{    
    const allocator = std.testing.allocator;

    const ramp_signal = SignalGenerator{
        .frequency_hz = 1,
        .duration_s = opentime.Ordinate.init(1),
        .signal = .ramp,
        .amplitude = 4,
    };

    const ramp_samples = try ramp_signal.rasterized(
        allocator,
        .{ .sample_rate_hz = .{ .Int = 4 } , },
        false,
    );

    defer ramp_samples.deinit(allocator);

    try std.testing.expectEqual(false, ramp_samples.interpolating);

    const sample_to_output_crv = (
        topology.mapping.MappingCurveLinearMonotonic{
            .input_to_output_curve = (
                try curve.linear_curve.Linear.init_identity(
                    allocator,
                    &.{0, 2},
                )
            )
        }
    );
    defer sample_to_output_crv.deinit(std.testing.allocator);

    const output_sampling_info:SampleIndexGenerator = .{
        .sample_rate_hz = .{ .Int = 4 } ,
    };

    const transformd_ramp_samples = try transform_resample_linear_dd(
        allocator, 
        ramp_samples,
        sample_to_output_crv,
        output_sampling_info,
        false,
    );
    defer transformd_ramp_samples.deinit(allocator);

    try std.testing.expectEqual(
        4,
        transformd_ramp_samples.buffer.len
    );

    const expected = &[_]sample_value_t{ 0, 1, 2, 3};

    try std.testing.expectEqualSlices(
        sample_value_t,
        expected,
        transformd_ramp_samples.buffer,
    );
}

test "sampling: frame phase slide 2: (time*2 bounds*1 freq*1 phase+0) 0,1,2,3->0,0,1,1"
{
    const allocator = std.testing.allocator;

    const ramp_signal = SignalGenerator{
        .frequency_hz = 1,
        .duration_s = opentime.Ordinate.init(1),
        .signal = .ramp,
        .amplitude = 4,
    };

    const ramp_samples = try ramp_signal.rasterized(
        allocator,
        .{
            .sample_rate_hz = .{ .Int = 4 },
        },
        false,
    );
    defer ramp_samples.deinit(allocator);

    const input_data = &[_]sample_value_t{ 0, 1, 2, 3};

    try std.testing.expectEqualSlices(
        sample_value_t,
        input_data,
        ramp_samples.buffer,
    );

    try std.testing.expectEqual(false, ramp_samples.interpolating);

    const sample_to_output_crv = (
        topology.mapping.MappingCurveLinearMonotonic{
            .input_to_output_curve = curve.linear_curve.Linear.Monotonic{
                .knots = &.{
                    curve.ControlPoint.init(.{ .in = 0, .out = 0 }),
                    curve.ControlPoint.init(.{ .in = 1, .out = 0.5 }),
                },
            }
        }
    );

    errdefer std.log.err(
        "Sample to output curve: {f}\n",
        .{ sample_to_output_crv.mapping() }
    );

    // trivial check that curve behaves as expected
    try opentime.expectOrdinateEqual(
        0.5,
        try sample_to_output_crv.project_instantaneous_cc(opentime.Ordinate.init(1.0)).ordinate(),
    );
    try opentime.expectOrdinateEqual(
        0.0,
        try sample_to_output_crv.project_instantaneous_cc(opentime.Ordinate.init(0.0)).ordinate(),
    );

    const output_sampling_info : SampleIndexGenerator = .{
        .sample_rate_hz = .{ .Int = 4 },
    };

    const output_ramp_samples = try transform_resample_linear_dd(
        allocator, 
        ramp_samples,
        sample_to_output_crv,
        output_sampling_info,
        false,
    );
    defer output_ramp_samples.deinit(allocator);

    const expected = &[_]sample_value_t{ 0, 0, 1, 1};

    try std.testing.expectEqualSlices(
        sample_value_t,
        expected,
        output_ramp_samples.buffer,
    );

    try std.testing.expectEqual(
        4,
        output_ramp_samples.buffer.len,
    );
}

test "sampling: frame phase slide 2.5: (time*2 bounds*2 freq*1 phase+0) 0,1,2,3->0,0,1,1,2,2,3,3"
{
    const allocator = std.testing.allocator;

    const ramp_signal = SignalGenerator{
        .frequency_hz = 1,
        .duration_s = opentime.Ordinate.init(1),
        .signal = .ramp,
        .amplitude = 4,
    };

    const ramp_samples = try ramp_signal.rasterized(
        allocator,
        .{
            .sample_rate_hz = .{ .Int = 4 },
        },
        false,
    );
    defer ramp_samples.deinit(allocator);

    const input_data = &[_]sample_value_t{ 0, 1, 2, 3};

    try std.testing.expectEqualSlices(
        sample_value_t,
        input_data,
        ramp_samples.buffer,
    );

    try std.testing.expectEqual(false, ramp_samples.interpolating);

    const transformd_to_sample_crv = (
        topology.mapping.MappingCurveLinearMonotonic{
            .input_to_output_curve = curve.linear_curve.Linear.Monotonic {
                .knots = &.{
                    curve.ControlPoint.init(.{ .in = 0.0, .out = 0.0, }),
                    curve.ControlPoint.init(.{ .in = 2.0, .out = 1.0, }),
                },
            }
        }
    );

    // trivial check that curve behaves as expected
    try opentime.expectOrdinateEqual(
        0.5,
        try transformd_to_sample_crv.project_instantaneous_cc(opentime.Ordinate.init(1.0)).ordinate(),
    );
    try opentime.expectOrdinateEqual(
        0.0,
        try transformd_to_sample_crv.project_instantaneous_cc(opentime.Ordinate.init(0.0)).ordinate(),
    );

    const output_sampling_info : SampleIndexGenerator = .{
        .sample_rate_hz = .{ .Int = 4 },
    };

    const output_ramp_samples = try transform_resample_linear_dd(
        allocator, 
        ramp_samples,
        transformd_to_sample_crv,
        output_sampling_info,
        false,
    );
    defer output_ramp_samples.deinit(allocator);

    const expected = &[_]sample_value_t{ 0, 0, 1, 1, 2, 2, 3, 3};

    try std.testing.expectEqualSlices(
        sample_value_t,
        expected,
        output_ramp_samples.buffer,
    );

    try std.testing.expectEqual(
        8,
        output_ramp_samples.buffer.len,
    );
}


// hold on even twos - short frames
test "sampling: frame phase slide 3: (time*1 freq*2 phase+0) 0,1,2,3->0,0,1,1..(over same duration, but with 2x the hz)"
{
    const allocator = std.testing.allocator;

    const ramp_signal = SignalGenerator{
        .frequency_hz = 1,
        .duration_s = opentime.Ordinate.init(1),
        .signal = .ramp,
        .amplitude = 4,
    };

    const ramp_samples = try ramp_signal.rasterized(
        allocator,
        .{
            .sample_rate_hz = .{ .Int = 4 },
        },
        false,
    );
    defer ramp_samples.deinit(allocator);

    const input_data = &[_]sample_value_t{ 0, 1, 2, 3};

    try std.testing.expectEqualSlices(
        sample_value_t,
        input_data,
        ramp_samples.buffer,
    );

    try std.testing.expectEqual(false, ramp_samples.interpolating);

    const sample_to_output_crv = (
        topology.mapping.MappingCurveLinearMonotonic{
            .input_to_output_curve = (
                try curve.linear_curve.Linear.init_identity(
                    allocator,
                    &.{0, 1.0},
                )
            )
        }
    );
    defer sample_to_output_crv.deinit(std.testing.allocator);

    errdefer std.log.err(
        "Sample to output curve: {f}\n",
        .{ sample_to_output_crv.mapping() }
    );

    // trivial check that curve behaves as expected
    try opentime.expectOrdinateEqual(
        0.5,
        try sample_to_output_crv.project_instantaneous_cc(opentime.Ordinate.init(0.5)).ordinate(),
    );
    try opentime.expectOrdinateEqual(
        0.0,
        try sample_to_output_crv.project_instantaneous_cc(opentime.Ordinate.init(0.0)).ordinate(),
    );

    const output_sampling_info : SampleIndexGenerator = .{
        .sample_rate_hz = .{ .Int = 8 },
    };

    const output_ramp_samples = try transform_resample_linear_dd(
        allocator, 
        ramp_samples,
        sample_to_output_crv,
        output_sampling_info,
        false,
    );
    defer output_ramp_samples.deinit(allocator);

    const expected = &[_]sample_value_t{ 0, 0, 1, 1, 2, 2, 3, 3};

    try std.testing.expectEqualSlices(
        sample_value_t,
        expected,
        output_ramp_samples.buffer,
    );
    
    try opentime.expectOrdinateEqual(
        1.0,
        output_ramp_samples.extents().end,
    );

    try std.testing.expectEqual(
        8,
        output_ramp_samples.buffer.len,
    );

}

// hold on odd twos
test "sampling: frame phase slide 4: (time*2 freq*1 phase+0.5) 0,1,2,3->0,1,1,2"
{
    const allocator = std.testing.allocator;

    const ramp_signal = SignalGenerator{
        .frequency_hz = 1,
        .duration_s = opentime.Ordinate.init(1),
        .signal = .ramp,
        .amplitude = 4,
    };

    const ramp_samples = try ramp_signal.rasterized(
        allocator,
        .{
            .sample_rate_hz = .{ .Int = 4 },
        },
        false,
    );
    defer ramp_samples.deinit(allocator);

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
    const input_data = &[_]sample_value_t{ 0, 1, 2, 3};

    try std.testing.expectEqualSlices(
        sample_value_t,
        input_data,
        ramp_samples.buffer,
    );

    try std.testing.expectEqual(
        false,
        ramp_samples.interpolating
    );

    const transform_to_inter_crv = (
        topology.mapping.MappingCurveLinearMonotonic {
            .input_to_output_curve = curve.linear_curve.Linear.Monotonic {
                .knots = &.{ 
                    curve.ControlPoint.init(.{ .in = 0.25, .out = 0.25 }),
                    curve.ControlPoint.init(.{ .in = 1.25, .out = 1.25 }),
                },
            }
        }
    ).mapping();

    const inter_to_sample_crv = (
        topology.mapping.MappingCurveLinearMonotonic {
            .input_to_output_curve = curve.linear_curve.Linear.Monotonic{
                .knots = &.{ 
                    curve.ControlPoint.init(.{ .in = 0, .out = 0 }),
                    curve.ControlPoint.init(.{ .in = 2, .out = 1 }),
                },
            },
        }
    ).mapping();

    const transformd_to_sample_crv = try topology.mapping.join(
        allocator,
        .{ 
            .a2b = transform_to_inter_crv,
            .b2c = inter_to_sample_crv,
        }
    );
    defer transformd_to_sample_crv.deinit(std.testing.allocator);

    // trivial check that curve behaves as expected
    try opentime.expectOrdinateEqual(
        0.375,
        try transformd_to_sample_crv.project_instantaneous_cc(opentime.Ordinate.init(0.75)).ordinate(),
    );
    try opentime.expectOrdinateEqual(
        0.125,
        try transformd_to_sample_crv.project_instantaneous_cc(opentime.Ordinate.init(0.25)).ordinate(),
    );

    const output_sampling_info : SampleIndexGenerator = .{
        .sample_rate_hz = .{ .Int = 4 },
    };

    const output_ramp_samples = try transform_resample_linear_dd(
        allocator, 
        ramp_samples,
        transformd_to_sample_crv.linear,
        output_sampling_info,
        false,
    );
    defer output_ramp_samples.deinit(allocator);

    const expected = &[_]sample_value_t{ 0, 1, 1 , 2};

    try std.testing.expectEqualSlices(
        sample_value_t,
        expected,
        output_ramp_samples.buffer,
    );
    
    try opentime.expectOrdinateEqual(
        1.0,
        output_ramp_samples.extents().end,
    );
}

test "sampling: frame phase slide 5: arbitrary held frames 0,1,2->0,0,0,0,1,1,2,2,2"
{
    const allocator = std.testing.allocator;

    const ramp_signal = SignalGenerator{
        .frequency_hz = 1,
        .duration_s = opentime.Ordinate.init(1),
        .signal = .ramp,
        .amplitude = 4,
    };

    const ramp_samples = try ramp_signal.rasterized(
        allocator,
        .{
            .sample_rate_hz = .{ .Int = 4 },
        },
        false,
    );
    defer ramp_samples.deinit(allocator);

    const input_data = &[_]sample_value_t{ 0, 1, 2, 3};

    // test input data
    // ///////////////
    try std.testing.expectEqualSlices(
        sample_value_t,
        input_data,
        ramp_samples.buffer,
    );

    try std.testing.expectEqual(
        false,
        ramp_samples.interpolating,
    );
    // ///////////////

    const output_to_input_topo = (
        topology.Topology {
            .mappings = &.{
                (
                 topology.mapping.MappingCurveLinearMonotonic{
                     .input_to_output_curve = .{
                         .knots = &.{
                             curve.ControlPoint.init(.{ .in = 0.0,    .out = 0.0 }),
                             curve.ControlPoint.init(.{ .in = 1.25, .out = 0.0 }),
                         },
                     },
                 }
                ).mapping(),
                (
                 topology.mapping.MappingCurveLinearMonotonic{
                     .input_to_output_curve = .{
                         .knots = &.{
                             curve.ControlPoint.init(.{ .in = 1.25, .out = 0.25 }),
                             curve.ControlPoint.init(.{ .in = 1.75, .out = 0.25 }),
                         }
                     },
                 }
                ).mapping(),
                (
                 topology.mapping.MappingCurveLinearMonotonic{
                     .input_to_output_curve = .{
                         .knots = &.{
                             curve.ControlPoint.init(.{ .in = 1.75, .out = 0.5 }),
                             curve.ControlPoint.init(.{ .in = 2.5,  .out = 0.5 }),
                         }
                     },
                 }
                ).mapping(),
            },
        }
    );

    // var knots = [_]curve.ControlPoint{
    //     // held 1
    //     .{ .in = 0,    .out = 0 },
    //     .{ .in = 1.25, .out = 0 },
    //     // held 2
    //     .{ .in = 1.25, .out = 0.25 },
    //     .{ .in = 1.75, .out = 0.25 },
    //     // held 3
    //     .{ .in = 1.75, .out = 0.5 },
    //     .{ .in = 2.5,  .out = 0.5 },
    // };
    //
    // const output_to_input_topo = (
    //     try topology.Topology.init_from_linear(
    //         allocator,
    //         curve.Linear{
    //             .knots = &knots,
    //         }
    //     )
    // );
    // defer output_to_input_topo.deinit(allocator);

    try std.testing.expectEqual(
        3,
        output_to_input_topo.mappings.len
    );

    const output_sampling_info : SampleIndexGenerator = .{
        .sample_rate_hz = .{ .Int = 4 } ,
    };

    const output_ramp_samples = try transform_resample_dd(
        allocator, 
        ramp_samples,
        output_to_input_topo,
        output_sampling_info,
        false,
    );
    defer output_ramp_samples.deinit(allocator);

    const expected = &[_]sample_value_t{ 0, 0, 0, 0, 0, 1, 1, 2, 2, 2 };

    try std.testing.expectEqualSlices(
        sample_value_t,
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

test "sampling: wav.zig generator test" 
{
    const allocator = std.testing.allocator;

    const samples_48 = SignalGenerator{
        .frequency_hz = 100,
        .amplitude = 1,
        .duration_s = opentime.Ordinate.init(1),
        .signal = .sine,
    };
    const s48 = try samples_48.rasterized(
        allocator,
        .{
            .sample_rate_hz = .{ .Int = 48000 },
        },
        true,
    );
    defer s48.deinit(allocator);

    if (WRITE_TEST_FILES) {
        try s48.write_file("/var/tmp/ours_givemesine.wav");
    }
}

test "sampling: transformed leak test"
{
    const allocator = std.testing.allocator;

    var buf = [_]sample_value_t{0, 1, 2, 3};

    const ramp_samples = Sampling{
        .interpolating = false,
        .index_generator = .{
            .sample_rate_hz = .{ .Int = 4 },
        },
        .buffer = &buf,
    };

    var knots = [_]curve.ControlPoint{
        curve.ControlPoint.init(.{ .in = 0, .out = 0 }),
        curve.ControlPoint.init(.{ .in = 1, .out = 1 }),
    };
    const transformed_to_sample_crv = (
        topology.mapping.MappingCurveLinearMonotonic{
            .input_to_output_curve = (
                curve.Linear.Monotonic{
                    .knots = &knots,
                }
            )
        }
    );

    const output_sampling_info : SampleIndexGenerator = .{
        .sample_rate_hz = .{ .Int = 8 },
    };

    const output_ramp_samples = try transform_resample_linear_dd(
        allocator, 
        ramp_samples,
        transformed_to_sample_crv,
        output_sampling_info,
        false,
    );
    defer output_ramp_samples.deinit(allocator);
}
