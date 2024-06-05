// @TODO : move to util maybe?
const EPSILON: f32 = 1.0e-6;

const SineSampleGenerator = struct {
    sampling_frequency_hz: 
};

// test 1
// have a set of samples over 48khz, resample them to 44khz
test "resample from 48khz to 44" {
    const samples_48 = SineSampleGenerator{
        .sampling_frequency_hz = 48000,
        .signal_frequency_hz = 100,
        .signal_amplitude = 1,
        .signal_duration_s = 1,
    };

    const samples_48_peak_to_peak_distance = samples_48.peak_to_peak_distance();
    
    // find a zero crossing
    // const s_i_48_half = samples_48.sample_index_near_s(0.5);
    // const s_48_half = samples_48.sample_at_index(s_i_48_half);
    // const s_48_half_sign = s_48_half > 0;
    //
    // var s_i = s_i_48_half + 1;
    // while (s_i < samples_48.last_index) : (s_i += 1) {
    //     const s = samples_48.sample_at_index(s_i);
    //     if (s_48_half * s <= EPSILON) {
    //         break;
    //     }
    // }
    //
    // // s_i is either the last index or the 0 cross
    // if (s_i == samples_48.last_index) {
    //     return error.NoZeroCrossing;
    // }
    //
    // const s_48_half_next = samples_48.sample_at_index(s_i_48_half + 1);

    const samples_44 = samples_48.resampled(44100);
    const samples_44_peak_to_peak_distance = samples_44.peak_to_peak_distance(
        0.5
    );

    try expectEqual(
        samples_48_peak_to_peak_distance,
        samples_44_peak_to_peak_distance
    );
}

// test 2
// have a set of samples over 48khz, retime them with a curve and then resample
// them to 44khz
test "retime 48khz samples with a curve, and then resample that retimed data" {
    const samples_48 = SineSampleGenerator{
        .sampling_frequency_hz = 48000,
        .signal_frequency_hz = 100,
        .signal_amplitude = 1,
        .signal_duration_s = 1,
    };

    // @TODO: write this to a json file so we can image in curvet
    var retime_curve_segments = [_]Segment{
        // identity
        create_identity_segment(0, 0.25),
        // go up
        create_linear_segment(
            .{ .time = 0.25, .value = 0.25 },
            .{ .time = 0.5, .value = 2 },
        ),
        // hold
        create_linear_segment(
            .{ .time = 0.5, .value = 2.0 },
            .{ .time = 1.0, .value = 2.0 },
        ),
    };
    const retime_curve : TimeCurve = .{
        .segments = &retime_curve_segments
    };

   const samples_48_retimed = samples_48.retimed(retime_curve);
   const samples_44 = samples_48_retimed.resampled(44100);

   // do the measurement of what we've generated
   const samples_44_p2p_0p1 = samples_44.peak_to_peak_distance(0.1);

   // @TODO: listen to this and hear if we get the chirp/sweep
   // const samples_44_p2p_0p35 = samples_44.peak_to_peak_distance(0.35);

   const samples_44_p2p_0p75 = samples_44.peak_to_peak_distance(0.75);


   // make the reference data
   const samples_44100_at_200 = SineSampleGenerator{
       .sampling_frequency_hz = 44100,
       .signal_frequency_hz = 200,
       .signal_amplitude = 1,
       .signal_duration_s = 1,
   };
   const samples_44100_at_200_p2p = samples_44100_at_200.peak_to_peak_distance(
       0.5
   );
   try expect(
       @abs(samples_44100_at_200_p2p - samples_44_p2p_0p1) <= 2
   );

   const samples_44100_at_100 = SineSampleGenerator{
       .sampling_frequency_hz = 44100,
       .signal_frequency_hz = 200,
       .signal_amplitude = 1,
       .signal_duration_s = 1,
   };
   const samples_44100_at_100_p2p = samples_44100_at_100.peak_to_peak_distance(
       0.5
    );
   try expect(
       @abs(samples_44100_at_100_p2p - samples_44_p2p_0p75) <= 2
   );
}

// test "retime 48khz samples with a curve projection, and then resample" {
//     const samples_48 = SineSampleGenerator{
//         .sampling_frequency_hz = 48000,
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
//        .sampling_frequency_hz = 44100,
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
//        .sampling_frequency_hz = 44100,
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
