const std = @import("std");
const libsamplerate = @import("libsamplerate").libsamplerate;
const kissfft = @import("kissfft").c;
const wav = @import("wav");

const curve = @import("curve");

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

// @TODO : move to util maybe?
const EPSILON: f32 = 1.0e-6;

const RETIME_DEBUG_LOGGING = false;
const WRITE_TEST_FILES = false;

/// alias around the sample type @TODO: make this comptime definable (anytype)
const sample_t  = f32;

/// a set of samples and the parameters of those samples
const Sampling = struct {
    buffer: []sample_t,
    sample_rate_hz: u32,
    allocator: std.mem.Allocator,

    pub fn init(
        allocator: std.mem.Allocator,
        count:usize,
        sample_rate_hz: u32,
    ) !Sampling
    {
        const buffer: []sample_t = try allocator.alloc(sample_t, count);

        return .{
            .buffer = buffer,
            .sample_rate_hz = sample_rate_hz,
            .allocator = allocator,
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
        fpath: []const u8
    ) !void 
    {
        var file = try std.fs.cwd().createFile(
            fpath,
            .{}
        );
        defer file.close();

        var encoder = try wav.encoder(
            i16,
            file.writer(),
            file.seekableStream(),
            self.sample_rate_hz,
            1
        );
        defer encoder.finalize() catch unreachable; 

        try encoder.write(f32, self.buffer);
    }

    pub fn indices_between_time(
        self: @This(),
        start_time_inclusive_s: sample_t,
        end_time_exclusive_s: sample_t,
    ) [2]usize
    {
        const start_index:usize = @intFromFloat(
            start_time_inclusive_s*@as(f32, @floatFromInt(self.sample_rate_hz))
        );
        const end_index:usize = @intFromFloat(
            end_time_exclusive_s*@as(f32, @floatFromInt(self.sample_rate_hz))
        );

        return .{ start_index, end_index };
    }

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
};

test "samples_between_time" 
{
    const samples_48 = SampleGenerator{
        .sampling_rate_hz = 48000,
        .signal_frequency_hz = 100,
        .signal_amplitude = 1,
        .signal_duration_s = 1,
        .signal = .sine,
    };
    const s48 = try samples_48.rasterized(std.testing.allocator);
    defer s48.deinit();

    const first_half_samples = s48.samples_between_time(0, 0.5);

    try expectEqual(
        samples_48.sampling_rate_hz/2,
        first_half_samples.len,
    );
}

const SampleGenerator = struct {
    sampling_rate_hz: u32,
    signal_frequency_hz: u32,
    signal_amplitude: f32 = 1.0,
    signal_duration_s: f32,
    signal: Signal,

    const Signal= enum {
        sine,
        ramp,
    };

    pub fn rasterized(
        self:@This(),
        allocator: std.mem.Allocator
    ) !Sampling
    {
        const sample_hz : sample_t = @floatFromInt(self.sampling_rate_hz);

        const result = try Sampling.init(
            allocator, 
            @intFromFloat(@ceil(@as(f64, self.signal_duration_s)*sample_hz)),
            self.sampling_rate_hz,
        );

        // fill the sample buffer
        for (0.., result.buffer)
            |current_index, *sample|
        {
            switch (self.signal) {
                .sine => {
                    sample.* = self.signal_amplitude * std.math.sin(
                        @as(sample_t, @floatFromInt(self.signal_frequency_hz))
                        * 2.0 * std.math.pi 
                        * (@as(sample_t, @floatFromInt(current_index)) / sample_hz)
                    );
                },
                // @TODO: not bandwidth-limited, cannot be used for a proper
                //        synthesizer
                .ramp => {
                    sample.* = self.signal_amplitude * curve.bezier_math.lerp(
                        @as(
                            sample_t,
                            try std.math.mod(
                                sample_t,
                                @as(sample_t, @floatFromInt(current_index)),
                                @as(sample_t, sample_hz)
                            ) / sample_hz
                        ),
                        @as(sample_t,0),
                        1,
                    );
                }
            }
        }

        return result;
    }
};

test "rasterizing the sine" 
{
    const samples_48 = SampleGenerator{
        .sampling_rate_hz = 48000,
        .signal_frequency_hz = 100,
        .signal_amplitude = 1,
        .signal_duration_s = 1,
        .signal = .sine,
    };
    const s48 = try samples_48.rasterized(std.testing.allocator);
    defer s48.deinit();

    // check some known quantities
    try expectEqual(@as(usize, 48000), s48.buffer.len);
    try expectEqual(@as(sample_t, 0), s48.buffer[0]);
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

test "peak_to_peak_distance of sine 48khz" 
{
    const samples_48_100 = SampleGenerator{
        .sampling_rate_hz = 48000,
        .signal_frequency_hz = 100,
        .signal_amplitude = 1,
        .signal_duration_s = 1,
        .signal = .sine,
    };
    const s48_100 = try samples_48_100.rasterized(
        std.testing.allocator
    );
    defer s48_100.deinit();

    const samples_48_100_p2p = try peak_to_peak_distance(
        s48_100.buffer
    );

    try expectEqual(480, samples_48_100_p2p);

    const samples_48_50 = SampleGenerator{
        .sampling_rate_hz = 48000,
        .signal_frequency_hz = 50,
        .signal_amplitude = 1,
        .signal_duration_s = 1,
        .signal = .sine,
    };
    const s48_50 = try samples_48_50.rasterized(
        std.testing.allocator
    );
    defer s48_50.deinit();

    const samples_48_50_p2p = try peak_to_peak_distance(s48_50.buffer);

    try expectEqual(960, samples_48_50_p2p);

    const samples_96_100 = SampleGenerator{
        .sampling_rate_hz = 96000,
        .signal_frequency_hz = 100,
        .signal_amplitude = 1,
        .signal_duration_s = 1,
        .signal = .sine,
    };
    const s96_100 = try samples_96_100.rasterized(
        std.testing.allocator
    );
    defer s96_100.deinit();

    const samples_96_100_p2p = try peak_to_peak_distance(s96_100.buffer);

    try expectEqual(960, samples_96_100_p2p);
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

/// computes a resample_ratio based on the destination_sample_rate_hz
pub fn resampled(
    allocator: std.mem.Allocator,
    in_samples: Sampling,
    destination_sample_rate_hz: u32,
) !Sampling
{
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
        destination_sample_rate_hz
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

pub fn retimed(
    allocator: std.mem.Allocator,
    in_samples: Sampling,
    xform: curve.TimeCurve,
    step_retime: bool,
) !Sampling
{
    const lin_curve = try xform.linearized(allocator);
    defer lin_curve.deinit(allocator);

    return retimed_linear_curve(
        allocator,
        in_samples,
        lin_curve,
        step_retime,
    );
}


/// retime in_samples with xform, return a new Sampling at the same rate
pub fn retimed_linear_curve(
    allocator: std.mem.Allocator,
    in_samples: Sampling,
    lin_curve: curve.TimeCurveLinear,
    step_retime: bool,
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

    for (lin_curve.knots[0..lin_curve.knots.len-1], lin_curve.knots[1..]) 
        |l_knot, r_knot|
    {    
        const relevant_sample_indices = in_samples.indices_between_time(
            l_knot.time,
            r_knot.time
        );
        const relevant_input_samples = in_samples.buffer[
            relevant_sample_indices[0]..
        ];
        if (relevant_input_samples.len == 0) {
            return error.NoRelevantSamples;
        }
        const input_samples = relevant_sample_indices[1] - relevant_sample_indices[0];
        // const input_samples = relevant_input_samples.len;

        const output_samples:usize = @intFromFloat(
            (r_knot.value - l_knot.value) 
             * @as(f32, @floatFromInt(in_samples.sample_rate_hz))
        );

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
                "in provided: {d} in used: {d} out requested: {d} out generated: {d} ",
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
        if (src_data.output_frames == 0)
        {
            retime_index += 1;
        }
        else
        {
            // slide buffers forward
            spec.output_samples -= @intCast(src_data.output_frames_gen);
        }
    }

    _ = libsamplerate.src_delete(src_state);

    return Sampling{
        .allocator = allocator,
        .buffer = full_output_buffer,
        .sample_rate_hz = in_samples.sample_rate_hz,
    };
}

// test 1
// have a set of samples over 48khz, resample them to 44khz
test "resample from 48khz to 44" 
{
    const samples_48 = SampleGenerator{
        .sampling_rate_hz = 48000,
        .signal_frequency_hz = 100,
        .signal_amplitude = 1,
        .signal_duration_s = 1,
        .signal = .sine,
    };
    const s48 = try samples_48.rasterized(std.testing.allocator);
    defer s48.deinit();

    if (WRITE_TEST_FILES) {
        try s48.write_file("/var/tmp/ours_100hz_48test.wav");
    }

    const samples_44 = try resampled(
        std.testing.allocator,
        s48,
        44100
    );
    defer samples_44.deinit();

    if (WRITE_TEST_FILES) {
        try samples_44.write_file("/var/tmp/ours_100hz_441test.wav");
    }

    const samples_44_p2pd = try peak_to_peak_distance(samples_44.buffer);

    // peak to peak distance (a distance in sample indices) should be the same
    // independent of retiming those samples
    try expectEqual(@as(usize, 441), samples_44_p2pd);
}

// test 2
// have a set of samples over 48khz, retime them with a linear curve and then
// resample them to 44khz
test "retime 48khz samples: ident-2x-ident, then resample to 44.1khz" 
{
    const samples_48 = SampleGenerator{
        .sampling_rate_hz = 48000,
        .signal_frequency_hz = 100,
        .signal_amplitude = 1,
        .signal_duration_s = 4,
        .signal = .sine,
    };
    const s48 = try samples_48.rasterized(std.testing.allocator);
    defer s48.deinit();
    if (WRITE_TEST_FILES) {
        try s48.write_file("/var/tmp/ours_s48_input.wav");
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
    var retime_curve_segments = [_]curve.Segment{
        // identity
        curve.Segment.init_identity(0,  1.0),
        // go up
        curve.Segment.init_from_start_end(
            .{ .time = 1.0, .value = 1.0 },
            .{ .time = 2.0, .value = 3.0 },
        ),
        // identity
        curve.Segment.init_from_start_end(
            .{ .time = 2.0, .value = 3.0 },
            .{ .time = 3.0, .value = 4.0 },
        ),
    };
    const retime_curve : curve.TimeCurve = .{
        .segments = &retime_curve_segments
    };
    // try curve.write_json_file_curve(
    //     std.testing.allocator,
    //     retime_curve,
    //     "/var/tmp/ours_retime_curve.curve.json"
    // );

    const samples_48_retimed = try retimed(
        std.testing.allocator,
        s48,
        retime_curve,
        true,
    );
    defer samples_48_retimed.deinit();
    if (WRITE_TEST_FILES) {
        try samples_48_retimed.write_file("/var/tmp/ours_s48_retimed.wav");
    }

    const samples_44 = try resampled(
        std.testing.allocator,
        samples_48_retimed,
        44100,
    );
    defer samples_44.deinit();
    if (WRITE_TEST_FILES) {
        try samples_44.write_file("/var/tmp/ours_s44_retimed.wav");
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
    try expectEqual(
        883,
        samples_44_p2p_0p5
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
// in curvet, create a set of samples over one rate, then after projection,
// resample to another rate
test "retime 48khz samples with a nonlinear acceleration curve and resample" 
{
    const samples_48 = SampleGenerator{
        .sampling_rate_hz = 48000,
        .signal_frequency_hz = 100,
        .signal_amplitude = 1,
        .signal_duration_s = 4,
        .signal = .sine,
    };
    const s48 = try samples_48.rasterized(std.testing.allocator);
    defer s48.deinit();

    var cubic_retime_curve_segments = [_]curve.Segment{
        // identity
        curve.Segment.init_identity(0, 1),
        // go up
        curve.Segment{
            .p0 = .{ .time = 1, .value = 1.0 },
            .p1 = .{ .time = 1.5, .value = 1.25 },
            .p2 = .{ .time = 2, .value = 1.35 },
            .p3 = .{ .time = 2.5, .value = 1.5 },
        },
    };
    const cubic_retime_curve : curve.TimeCurve = .{
        .segments = &cubic_retime_curve_segments
    };
    if (WRITE_TEST_FILES) {
        try curve.write_json_file_curve(
            std.testing.allocator,
            cubic_retime_curve,
            "/var/tmp/ours_retime_24hz.linear.json"
        );
    }

    const samples_48_retimed_cubic = try retimed(
        std.testing.allocator,
        s48,
        cubic_retime_curve,
        true,
    );
    defer samples_48_retimed_cubic.deinit();
    if (WRITE_TEST_FILES) {
        try samples_48_retimed_cubic.write_file(
            "/var/tmp/ours_s48_retimed_acceleration_cubic.wav"
        );
    }

    // linearize at 24hz
    const retime_curve_extents = (
        cubic_retime_curve.extents_time()
    );
    const inc:sample_t = 4.0/24.0;

    var knots = std.ArrayList(curve.ControlPoint).init(
        std.testing.allocator
    );
    defer knots.deinit();

    try knots.append(
        .{
            .time = retime_curve_extents.start_seconds,
            .value = try cubic_retime_curve.evaluate(
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
                .time = t,
                .value = try cubic_retime_curve.evaluate(t),
            }
        );
    }

    const retime_24hz_lin = curve.TimeCurveLinear{
        .knots = try knots.toOwnedSlice(),
    };
    defer retime_24hz_lin.deinit(std.testing.allocator);

    // const retime_24hz = try curve.TimeCurve.init_from_linear_curve(
    //     std.testing.allocator,
    //     retime_24hz_lin,
    // );
    // defer retime_24hz.deinit(std.testing.allocator);

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
    );
    defer samples_48_retimed.deinit();
    if (WRITE_TEST_FILES) {
        try samples_48_retimed.write_file(
            "/var/tmp/ours_s48_retimed_acceleration_24_aliasing.wav"
        );
    }
    const samples_44 = try resampled(
        std.testing.allocator,
        samples_48_retimed,
        44100,
    );
    defer samples_44.deinit();
    if (WRITE_TEST_FILES) {
        try samples_44.write_file(
            "/var/tmp/ours_s44_retimed_acceleration_24.wav"
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
    const signal_ramp = SampleGenerator{
        .sampling_rate_hz = 48000,
        .signal_frequency_hz = 24,
        .signal_duration_s = 2,
        .signal = .ramp,

    };

    const s48_ramp = try signal_ramp.rasterized(std.testing.allocator);
    defer s48_ramp.deinit();
    if (WRITE_TEST_FILES) {
        try s48_ramp.write_file(
            "/var/tmp/ramp_24hz_signal_48kz_sampling.wav"
        );
    }

    try expectEqual(0, s48_ramp.buffer[0]);
    try std.testing.expectApproxEqAbs(
        1,
        s48_ramp.buffer[47999],
        0.0001,
    );
    try expectEqual(0, s48_ramp.buffer[48000]);
}

test "sampling: frame phase slide 2: (time*2 freq*1 phase+0) 0,1,2,3->0,0,1,1"
{
    const signal_ramp = SampleGenerator{
        .sampling_rate_hz = 48000,
        .signal_frequency_hz = 24,
        .signal_duration_s = 2,
        .signal = .ramp,

    };

    const s48_ramp = try signal_ramp.rasterized(std.testing.allocator);
    defer s48_ramp.deinit();
    if (WRITE_TEST_FILES) {
        try s48_ramp.write_file(
            "/var/tmp/ramp_24hz_signal_48kz_sampling.wav"
        );
    }

    try expectEqual(0, s48_ramp.buffer[0]);
    try std.testing.expectApproxEqAbs(
        1,
        s48_ramp.buffer[47999],
        0.0001,
    );
    try expectEqual(0, s48_ramp.buffer[48000]);

    const lin = curve.TimeCurveLinear.init_from_start_end(

    );
    defer lin.deinit();

    retimed_linear_curve(
        std.testing.allocator,
        signal_ramp.buffer,
        lin,
        false,
    );

    return error.SkipZigTest;
}

// hold on even twos - short frames
test "sampling: frame phase slide 3: (time*1 freq*2 phase+0) 0,1,2,3->0,0,1,1..(over same duration, but with 2x the hz)"
{
    // @TODO: Nick/Stephan pick up here
    return error.SkipZigTest;
}

// // hold on even twos 2x the number of frames
// test "sampling: frame phase slide 3: (time*2 freq*2 phase+0) 0,1,2,3->0,0,1,1..(over double duration)"
// {
//     return error.SkipZigError;
// }
//
// // hold on odd twos
// test "sampling: frame phase slide 3: (time*2 freq*1 phase+0.5) 0,1,2,3->0,1,1,2"
// {
//     return error.SkipZigError;
// }
//
// test "sampling: frame phase slide 3: arbitrary held frames 0,1,2->0,0,0,0,1,1,2,2,2"
// {
//     return error.SkipZigError;
// }

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
    const samples_48 = SampleGenerator{
        .sampling_rate_hz = 48000,
        .signal_frequency_hz = 100,
        .signal_amplitude = 1,
        .signal_duration_s = 1,
        .signal = .sine,
    };
    const s48 = try samples_48.rasterized(std.testing.allocator);
    defer s48.deinit();

    if (WRITE_TEST_FILES) {
        try s48.write_file("/var/tmp/ours_givemesine.wav");
    }
}
