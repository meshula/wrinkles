const std = @import("std");
const libsamplerate = @import("libsamplerate").libsamplerate;
const kissfft = @import("kissfft").c;
const wav = @import("wav");

const curve = @import("curve");

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

// @TODO : move to util maybe?
const EPSILON: f32 = 1.0e-6;

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

    pub fn deinit(self: @This()) void {
        self.allocator.free(self.buffer);
    }

    pub fn write_file(self: @This(), fpath: []const u8) !void {
        var file = try std.fs.cwd().createFile(fpath, .{});
        defer file.close();

        var encoder = try wav.encoder(
            i16,
            file.writer(),
            file.seekableStream(),
            self.sample_rate_hz,
            1
        );
        try encoder.write(f32, self.buffer);
        try encoder.finalize(); // Don't forget to finalize after you're done writing.
    }

    pub fn samples_between_time(
        self: @This(),
        start_time_inclusive_s: sample_t,
        end_time_exclusive_s: sample_t,
    ) []sample_t
    {
        const start_index:usize = @intFromFloat(
            start_time_inclusive_s*@as(f32, @floatFromInt(self.sample_rate_hz))
        );
        const end_index:usize = @intFromFloat(
            end_time_exclusive_s*@as(f32, @floatFromInt(self.sample_rate_hz))
        );

        return self.buffer[start_index..end_index];
    }
};

test "samples_between_time" {
    const samples_48 = SineSampleGenerator{
        .sampling_rate_hz = 48000,
        .signal_frequency_hz = 100,
        .signal_amplitude = 1,
        .signal_duration_s = 1,
    };
    const s48 = try samples_48.rasterized(std.testing.allocator);
    defer s48.deinit();

    const first_half_samples = s48.samples_between_time(0, 0.5);

    try expectEqual(
        samples_48.sampling_rate_hz/2,
        first_half_samples.len,
    );
}

const SineSampleGenerator = struct {
    sampling_rate_hz: u32,
    signal_frequency_hz: u32,
    signal_amplitude: f32,
    signal_duration_s: f32,

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
            |idx, *sample|
        {
            sample.* = std.math.sin(
                @as(sample_t, @floatFromInt(self.signal_frequency_hz))
                * 2.0 * std.math.pi 
                * (@as(sample_t, @floatFromInt(idx)) / sample_hz)
            );
        }

        return result;
    }
};

test "rasterizing the sine" {
    const samples_48 = SineSampleGenerator{
        .sampling_rate_hz = 48000,
        .signal_frequency_hz = 100,
        .signal_amplitude = 1,
        .signal_duration_s = 1,
    };
    const s48 = try samples_48.rasterized(std.testing.allocator);
    defer s48.deinit();

    // check some known quantities
    try expectEqual(@as(usize, 48000), s48.buffer.len);
    try expectEqual(@as(sample_t, 0), s48.buffer[0]);
}

// returns the peak to peak distance of the samples in the buffer
pub fn peak_to_peak_distance(
    samples: []const sample_t,
) usize 
{
    var last_max_idx:?usize = null;
    var peak_to_peak_samples:usize = 0;

    var idx : usize = 1;
    while (idx < samples.len) 
        : (idx += 1) 
    {
        if (
            samples[idx] > samples[idx - 1] 
            and samples[idx] > samples[idx + 1]
        ) 
        {
            if (last_max_idx) 
                |l_m_idx| 
            {
                peak_to_peak_samples = idx - l_m_idx;
                break;
            }
            last_max_idx = idx;
        }
    }

    return peak_to_peak_samples;
}

test "peak_to_peak_distance of sine 48khz" {
    const samples_48_100 = SineSampleGenerator{
        .sampling_rate_hz = 48000,
        .signal_frequency_hz = 100,
        .signal_amplitude = 1,
        .signal_duration_s = 1,
    };
    const s48_100 = try samples_48_100.rasterized(std.testing.allocator);
    defer s48_100.deinit();

    const samples_48_100_p2p = peak_to_peak_distance(s48_100.buffer);

    try expectEqual(480, samples_48_100_p2p);

    const samples_48_50 = SineSampleGenerator{
        .sampling_rate_hz = 48000,
        .signal_frequency_hz = 50,
        .signal_amplitude = 1,
        .signal_duration_s = 1,
    };
    const s48_50 = try samples_48_50.rasterized(std.testing.allocator);
    defer s48_50.deinit();

    const samples_48_50_p2p = peak_to_peak_distance(s48_50.buffer);

    try expectEqual(960, samples_48_50_p2p);

    const samples_96_100 = SineSampleGenerator{
        .sampling_rate_hz = 96000,
        .signal_frequency_hz = 100,
        .signal_amplitude = 1,
        .signal_duration_s = 1,
    };
    const s96_100 = try samples_96_100.rasterized(std.testing.allocator);
    defer s96_100.deinit();

    const samples_96_100_p2p = peak_to_peak_distance(s96_100.buffer);

    try expectEqual(960, samples_96_100_p2p);
}

// test 0 - ensure that the contents of the c-library are visible
test "c lib interface test" {
    // libsamplerate
    try expectEqual(libsamplerate.SRC_SINC_BEST_QUALITY, 0);

    // kiss_fft
    const cpx = kissfft.kiss_fft_cpx{ .r = 1, .i = 1 };
    try expectEqual(cpx.r, 1);
}

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
            @floor(@as(f64, @floatFromInt(in_samples.buffer.len)) * resample_ratio)
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
        .end_of_input = 1,
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
) !Sampling
{
    const lin_curve = xform.linearized();

    var result = std.ArrayList(sample_t).init(allocator);

    for (lin_curve.knots[0..lin_curve.knots.len-1], lin_curve.knots[1..]) 
        |l_knot, r_knot|
    {    
        const relevant_samples = in_samples.samples_between_time(
            l_knot.time,
            r_knot.time
        );
        const relevant_sampling = Sampling{
            .allocator = allocator,
            .buffer = relevant_samples,
            .sample_rate_hz = in_samples.sample_rate_hz,
        };

        const retime_ratio = (
            ((r_knot.value - l_knot.value) * @as(f32, @floatFromInt(in_samples.sample_rate_hz)))
            / @as(f32, @floatFromInt(relevant_samples.len))
        );

        const output_chunk = try resampled(
            allocator,
            relevant_sampling,
            @intFromFloat(retime_ratio * @as(f32, @floatFromInt(in_samples.sample_rate_hz)))
        );
        defer output_chunk.deinit();

        try result.appendSlice(output_chunk.buffer);
    }

    return Sampling{
        .allocator = allocator,
        .buffer = try result.toOwnedSlice(),
        .sample_rate_hz = in_samples.sample_rate_hz,
    };
}

// test 1
// have a set of samples over 48khz, resample them to 44khz
test "resample from 48khz to 44" {
    const samples_48 = SineSampleGenerator{
        .sampling_rate_hz = 48000,
        .signal_frequency_hz = 100,
        .signal_amplitude = 1,
        .signal_duration_s = 1,
    };
    const s48 = try samples_48.rasterized(std.testing.allocator);
    defer s48.deinit();

    try s48.write_file("/var/tmp/ours_100hz_48test.wav");

    const samples_44 = try resampled(
        std.testing.allocator,
        s48,
        44100
    );
    defer samples_44.deinit();

    try samples_44.write_file("/var/tmp/ours_100hz_441test.wav");

    const samples_44_p2pd = peak_to_peak_distance(samples_44.buffer);

    // peak to peak distance (a distance in sample indices) should be the same
    // independent of retiming those samples
    try expectEqual(@as(usize, 441), samples_44_p2pd);
}

// test 2
// have a set of samples over 48khz, retime them with a curve and then resample
// them to 44khz
test "retime 48khz samples with a curve, and then resample that retimed data" {
    const samples_48 = SineSampleGenerator{
        .sampling_rate_hz = 48000,
        .signal_frequency_hz = 100,
        .signal_amplitude = 1,
        .signal_duration_s = 1,
    };
    const s48 = try samples_48.rasterized(std.testing.allocator);
    defer s48.deinit();

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
        curve.create_identity_segment(0, 0.25),
        // go up
        curve.create_linear_segment(
            .{ .time = 0.25, .value = 0.25 },
            .{ .time = 0.5, .value = 0.75 },
        ),
        // identity
        curve.create_linear_segment(
            .{ .time = 0.5, .value = 0.75 },
            .{ .time = 1.0, .value = 1.25 },
        ),
    };
    const retime_curve : curve.TimeCurve = .{
        .segments = &retime_curve_segments
    };
    try curve.write_json_file_curve(
        retime_curve,
        "/var/tmp/ours_retime_curve.curve.json"
    );

    const samples_48_retimed = try retimed(
        std.testing.allocator,
        s48,
        retime_curve
    );
    defer samples_48_retimed.deinit();
    const samples_44 = try resampled(
        std.testing.allocator,
        samples_48_retimed,
        44100,
    );
    defer samples_44.deinit();
    try samples_44.write_file("/var/tmp/ours_s44_retimed.wav");

    // identity
    const samples_44_p2p_0p25 = peak_to_peak_distance(
        samples_44.buffer[0..11025]
    );
    try expectEqual(
        441,
        samples_44_p2p_0p25
    );

    // @TODO: Test failures are here -- questions
    //        1. are we really passing the right values to libsamplerate (96 vs
    //           192, etc)
    //        2. is there an official API for doing pitch shifting?

    // 2x
    const samples_44_p2p_0p5 = peak_to_peak_distance(
        samples_44.buffer[11025..22050]
    );
    try expectEqual(
        441,
        samples_44_p2p_0p5
     );

    // identity
    const samples_44_p2p_1p0 = peak_to_peak_distance(
        samples_44.buffer[22050..]
    );
    try expectEqual(
        441,
        samples_44_p2p_1p0
    );
}

// test "retime 48khz samples with a curve projection, and then resample" {
//     const samples_48 = SineSampleGenerator{
//         .sampling_rate_hz = 48000,
//         .signal_frequency_hz = 100,
//         .signal_amplitude = 1,
//         .signal_duration_s = 1,
//     };
//
//     // @TODO: write this to a json file so we can image in curvet
//     var retime_curve_segments = [_]Segment{
//         // identity
//         create_identity_segment(0, 0.25),
//         // go up
//         create_linear_segment(
//             .{ .time = 0.25, .value = 0.25 },
//             .{ .time = 0.5, .value = 2 },
//         ),
//         // hold
//         create_linear_segment(
//             .{ .time = 0.5, .value = 2.0 },
//             .{ .time = 1.0, .value = 2.0 },
//         ),
//     };
//     const retime_curve : TimeCurve = .{
//         .segments = &retime_curve_segments
//     };
//
//    const samples_48_retimed = samples_48.retimed(retime_curve);
//    const samples_44 = samples_48_retimed.resampled(44100);
//
//    // do the measurement of what we've generated
//    const samples_44_p2p_0p1 = samples_44.peak_to_peak_distance(0.1);
//
//    // @TODO: listen to this and hear if we get the chirp/sweep
//    // const samples_44_p2p_0p35 = samples_44.peak_to_peak_distance(0.35);
//
//    const samples_44_p2p_0p75 = samples_44.peak_to_peak_distance(0.75);
//
//
//    // make the reference data
//    const samples_44100_at_200 = SineSampleGenerator{
//        .sampling_rate_hz = 44100,
//        .signal_frequency_hz = 200,
//        .signal_amplitude = 1,
//        .signal_duration_s = 1,
//    };
//    const samples_44100_at_200_p2p = samples_44100_at_200.peak_to_peak_distance(
//        0.5
//    );
//    try expect(
//        @abs(samples_44100_at_200_p2p - samples_44_p2p_0p1) <= 2
//    );
//
//    const samples_44100_at_100 = SineSampleGenerator{
//        .sampling_rate_hz = 44100,
//        .signal_frequency_hz = 200,
//        .signal_amplitude = 1,
//        .signal_duration_s = 1,
//    };
//    const samples_44100_at_100_p2p = samples_44100_at_100.peak_to_peak_distance(
//        0.5
//     );
//    try expect(
//        @abs(samples_44100_at_100_p2p - samples_44_p2p_0p75) <= 2
//    );
// }

// test 3
// in curvet, create a set of samples over one rate, then after projection,
// resample to another rate
//
// test 4 <-- goal
// within the nomenclature of OTIO itself, describe samples on one media and
// resample them to another space (IE have a clip at 48khz and the timeline at
// 44khz)-
// 
// test 5 
// resample according to centered kernels

/// Naive sine with pitch 440Hz.
fn generateSine(sample_rate: f32, data: []f32) void {
    const radians_per_sec: f32 = 440.0 * 2.0 * std.math.pi;
    var i: usize = 0;
    while (i < data.len) : (i += 1) {
        data[i] = 0.5 * std.math.sin(@as(f32, @floatFromInt(i)) * radians_per_sec / sample_rate);
    }
}

test "wav.zig generator test (purely their code)" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var file = try std.fs.cwd().createFile("/var/tmp/theirs_givemeasine.wav", .{});
    defer file.close();

    const sample_rate: usize = 44100;
    const num_channels: usize = 1;

    const data = try alloc.alloc(f32, 10 * sample_rate);
    defer alloc.free(data);

    generateSine(@as(f32, @floatFromInt(sample_rate)), data);

    // Write out samples as 16-bit PCM int.
    var encoder = try wav.encoder(i16, file.writer(), file.seekableStream(), sample_rate, num_channels);
    try encoder.write(f32, data);
    try encoder.finalize(); // Don't forget to finalize after you're done writing.

}

test "wav.zig generator test (our code)" {
    const samples_48 = SineSampleGenerator{
        .sampling_rate_hz = 48000,
        .signal_frequency_hz = 100,
        .signal_amplitude = 1,
        .signal_duration_s = 1,
    };
    const s48 = try samples_48.rasterized(std.testing.allocator);
    defer s48.deinit();

    try s48.write_file("/var/tmp/ours_givemesine.wav");
}
