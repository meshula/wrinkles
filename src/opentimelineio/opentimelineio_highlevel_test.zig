//! Demonstration of new features in this lib via unit tests

const std = @import("std");

const otio = @import("root.zig");

const opentime = @import("opentime");
const topology = @import("topology");
const sampling = @import("sampling");

// for verbose print of test
const PRINT_DEMO_OUTPUT = false;

const T_ORD_6 = opentime.Ordinate.init(6);
const T_INT_1_TO_6 = opentime.ContinuousInterval{
    .start = opentime.Ordinate.ONE,
    .end = T_ORD_6,
};
const T_AFF_N1_2 = opentime.AffineTransform1D {
    .offset = opentime.Ordinate.init(-1),
    .scale = opentime.Ordinate.init(2),
};

test "otio: high level procedural test [clip][   gap    ][clip]"
{
    const allocator = std.testing.allocator;

    // describe the timeline data structure
    ///////////////////////////////////////////////////////////////////////////
 
    // top level timeline
    var tl: otio.Timeline = .{};
    defer tl.recursively_deinit(allocator);

    tl.name = try allocator.dupe(u8, "Example Timeline");
    tl.discrete_info.presentation = .{
        .sample_rate_hz = .{ .Int = 24 },
        .start_index = 86400,
    };

    const tl_ptr = otio.ComposedValueRef{
        .timeline_ptr = &tl 
    };

    // track
    var tr: otio.Track = .{};
    tr.name = try allocator.dupe(u8, "Example Parent Track");

    // clips
    const cl1 = otio.Clip {
        .name = try allocator.dupe(
            u8,
            "Spaghetti.mov",
        ),
        .bounds_s = .{
            .start = opentime.Ordinate.ONE,
            .end = opentime.Ordinate.init(3),
        },
        .media = .{
            .discrete_info = .{
                .sample_rate_hz = .{ .Int = 24 },
                .start_index = 10,
            },
        },
    };
    try tr.append(allocator,cl1);

    // gap
    const gp = otio.Gap{
        .duration_seconds = opentime.Ordinate.ONE,
    };
    try tr.append(allocator,gp);

    // clip
    const cl2 = otio.Clip {
        .name = try allocator.dupe(
            u8,
            "Taco.mov"
        ),
        .media = .{
            .bounds_s = .{
                .start = opentime.Ordinate.init(10),
                .end = opentime.Ordinate.init(11), 
            },
            .discrete_info = .{
                .sample_rate_hz = .{ .Int = 30 },
                .start_index = 10,
            },
        },
    };

    // build some pointers into the structure
    const cl2_ptr = try tr.append_fetch_ref(
        allocator,
        cl2,
    );
    try tl.tracks.append(allocator,tr);

    // build the topological map
    ///////////////////////////////////////////////////////////////////////////
    const topo_map = try otio.build_topological_map(
        allocator,
        tl_ptr
    );
    defer topo_map.deinit();

    // could do individual specific end-to-end projections here
    ///////////////////////////////////////////////////////////////////////////
    const timeline_to_clip2 = (
        try topo_map.build_projection_operator(
            allocator,
            .{
                .source = try tl_ptr.space(.presentation),
                .destination = try cl2_ptr.space(.media),
            }
        )
    );
    defer timeline_to_clip2.deinit(allocator);
    const clip_indices = try timeline_to_clip2.project_range_cd(
        allocator,
        timeline_to_clip2.src_to_dst_topo.input_bounds(),
    );
    defer allocator.free(clip_indices);

    try std.testing.expectEqualSlices(
        sampling.sample_index_t,
        &.{ 
            310, 311, 312, 313, 314, 315, 316, 317, 318, 319, 
            320, 321, 322, 323, 324, 325, 326, 327, 328, 329, 
            330, 331, 332, 333, 334, 335, 336, 337, 338, 339, 
            340,
        },
        clip_indices,
    );

    // ...or a general projection: build the projection operator map
    ///////////////////////////////////////////////////////////////////////////
    const proj_map = (
        try otio.projection_map_to_media_from(
            allocator,
            topo_map, 
            try tl_ptr.space(.presentation)
        )
    );
    defer proj_map.deinit();

    const src_discrete_info = (
        try proj_map.source.ref.discrete_info_for_space(.presentation)
    );

    if (PRINT_DEMO_OUTPUT) 
    {
        opentime.dbg_print(@src(),
            "Media Frames Needed to Render '{s}'\n",
            .{
                tr.name orelse "pasta"
            }
        );
        opentime.dbg_print(@src(),
            "  Discrete Info:\n    sampling rate: {d}\n"
            ++ "    start index: {d}\n",
            .{
                src_discrete_info.?.sample_rate_hz,
                src_discrete_info.?.start_index,
            },
        );
        opentime.dbg_print(@src(),
            "    interval: [{d}, {d})\n",
            .{
                proj_map.end_points[0],
                proj_map.end_points[proj_map.end_points.len-1],
            },
        );
    }

    const known_frames = &[3][]const sampling.sample_index_t{
        &[_]sampling.sample_index_t{ 
                            34, 35, 36, 37, 38, 39,
            40, 41, 42, 43, 44, 45, 46, 47, 48, 49,
            50, 51, 52, 53, 54, 55, 56, 57, 58, 59,
            60, 61, 62, 63, 64, 65, 66, 67, 68, 69,
            70, 71, 72, 73, 74, 75, 76, 77, 78, 79,
            80, 81,
        },
        &[_]sampling.sample_index_t{ 
            310, 311, 312, 313, 314, 315, 316, 317, 318, 319,
            320, 321, 322, 323, 324, 325, 326, 327, 328, 329,
            330, 331, 332, 333, 334, 335, 336, 337, 338, 339,
            340, 341, 342, 343, 344, 345, 346, 347, 348, 349,
        },
        &[_]sampling.sample_index_t{ 
            310, 311, 312, 313, 314, 315, 316, 317, 318, 319,
            320, 321, 322, 323, 324, 325, 326, 327, 328, 329,
            330, 331, 332, 333, 334, 335, 336, 337, 338, 339,
            340, 
        },
    };

    // walk across the general projection operator map
    ///////////////////////////////////////////////////////////////////////////
    for (
        proj_map.end_points[0..(proj_map.end_points.len-1)],
        proj_map.end_points[1..],
        proj_map.operators,
        0..
    )
        |p0, p1, ops, op_ind|
    {
        if  (PRINT_DEMO_OUTPUT)
        {
            opentime.dbg_print(@src(),
                "  presentation space:\n    interval: [{d}, {d})\n",
                .{ p0, p1 },
            );
        }
        for (ops)
            |op|
        {
            if (PRINT_DEMO_OUTPUT)
            {
                opentime.dbg_print(@src(),
                    "    Topology\n      presentation:  {any}\n"
                    ++ "      media: {any}\n",
                    .{
                        op.src_to_dst_topo.input_bounds(),
                        op.src_to_dst_topo.output_bounds(),
                    },
                );
            }
            const di = (
                try op.destination.ref.discrete_info_for_space(.media)
            ).?;
            if (PRINT_DEMO_OUTPUT)
            {
                opentime.dbg_print(@src(),
                    "    Discrete Info:\n      sampling rate: {d}\n"
                    ++ "      start index: {d}\n",
                    .{
                        di.sample_rate_hz,
                        di.start_index,
                    },
                );
            }

            const dest_frames = try op.project_range_cd(
                allocator,
                .{
                    .start = p0,
                    .end = p1,
                }
            );
            defer allocator.free(dest_frames);

            errdefer std.debug.print(
                "error at op_ind: {d}\n",
                .{ op_ind }
            );

            try std.testing.expectEqualSlices(
                sampling.sample_index_t,
                known_frames[op_ind],
                dest_frames,
            );

            if (PRINT_DEMO_OUTPUT)
            {
                opentime.dbg_print(@src(),
                    "    Source: \n      target: {?s}\n"
                    ++ "      frames: {any}\n",
                    .{ 
                        op.destination.ref.clip_ptr.name orelse "pasta",
                        dest_frames,
                    }
                );
            }
        }
    }
}

test "libsamplerate w/ high level test -- resample only"
{
    const allocator = std.testing.allocator;

    // top level timeline
    var tl: otio.Timeline = .{};
    defer tl.recursively_deinit(allocator);

    tl.name = try allocator.dupe(u8, "Example Timeline");
    tl.discrete_info.presentation = .{
        .sample_rate_hz = .{ .Int = 44100 },
        .start_index = 86400,
    };

    const tl_ptr = otio.ComposedValueRef{
        .timeline_ptr = &tl 
    };

    // track
    var tr: otio.Track = .{};
    tr.name = try allocator.dupe(u8, "Example Parent Track");

    // clips
    const cl1 = otio.Clip {
        .name = try allocator.dupe(
            u8,
            "Spaghetti.mov",
        ),
        .media = .{
            .bounds_s = T_INT_1_TO_6,
            .discrete_info = .{
                .sample_rate_hz = .{ .Int = 48000 },
                .start_index = 0,
            },
            .ref = .{ 
                .signal = .{
                    .signal_generator = .{
                        .signal = .sine,
                        .duration_s = T_ORD_6,
                        .frequency_hz = 200,
                    }
                }
            },
        }
    };
    const bounds = try cl1.bounds_of(
        allocator,
        .media
    );
    try std.testing.expect(
        cl1.media.bounds_s.?.start.lt(cl1.media.bounds_s.?.end)
    );
    try std.testing.expect(bounds.end.eql(0) == false);
    try std.testing.expect(bounds.start.lt(bounds.end));

    const cl_ptr = try tr.append_fetch_ref(
        allocator,
        cl1,
    );
    const tr_ptr = try tl.tracks.append_fetch_ref(
        allocator,
        tr,
    );

    // build the topological map
    ///////////////////////////////////////////////////////////////////////////
    const topo_map = try otio.build_topological_map(
        allocator,
        tl_ptr,
    );
    defer topo_map.deinit();

    const tr_pres_to_cl_media_po = (
        try topo_map.build_projection_operator(
            allocator,
            .{
                .source = try tr_ptr.space(.presentation),
                .destination = try cl_ptr.space(.media),
            },
        )
    );
    defer tr_pres_to_cl_media_po.deinit(allocator);

    try std.testing.expectEqual(
        .affine,
        std.meta.activeTag(
            tr_pres_to_cl_media_po.src_to_dst_topo.mappings[0]
        ),
    );

    try std.testing.expect(
        tr_pres_to_cl_media_po.source_bounds().end.gt(0),
    );

    const pres_bounds = tr_pres_to_cl_media_po.source_bounds();
    try opentime.expectOrdinateEqual(
        0,
        pres_bounds.start,
    );
    try opentime.expectOrdinateEqual(
        5,
        pres_bounds.end,
    );

    try std.testing.expect(
        cl1.media.ref.signal.signal_generator.duration_s.gt(0)
    );

    // synthesize media
    const media_samples = (
        try cl_ptr.clip_ptr.media.ref.signal.signal_generator.rasterized(
            allocator,
            cl_ptr.clip_ptr.media.discrete_info.?,
            true,
        )
    );
    defer media_samples.deinit();
    try std.testing.expect(media_samples.buffer.len > 0);

    // write the input file
    try media_samples.write_file_prefix(
        allocator,
        "/var/tmp",
        "highlevel_libsamplerate_test_clip_media.",
        cl1.media.ref.signal.signal_generator,
    );

    // goal
    const cl_media_samples_for_tr_pres = try sampling.transform_resample_dd(
        allocator,
        media_samples,
        tr_pres_to_cl_media_po.src_to_dst_topo,
        tl.discrete_info.presentation.?,
        false,
    );
    defer cl_media_samples_for_tr_pres.deinit();

    // result should match the timeline's discrete info
    try std.testing.expectEqual(
        tl.discrete_info.presentation.?.sample_rate_hz,
        cl_media_samples_for_tr_pres.index_generator.sample_rate_hz
    );

    try cl_media_samples_for_tr_pres.write_file_prefix(
        allocator, 
        "/var/tmp/",
        "highlevel_libsamplerate_test_track_presentation.resampled_only.",
        null,
    );

    try std.testing.expect(cl_media_samples_for_tr_pres.buffer.len > 0);
}

test "libsamplerate w/ high level test.retime.interpolating"
{
    const allocator = std.testing.allocator;

    // top level timeline
    var tl: otio.Timeline = .{};
    tl.name = try allocator.dupe(u8, "Example Timeline");
    tl.discrete_info.presentation = .{
        // matches the media rate
        .sample_rate_hz = .{ .Int = 48000 },
        .start_index = 86400,
    };

    defer tl.recursively_deinit(allocator);
    const tl_ptr = otio.ComposedValueRef{
        .timeline_ptr = &tl 
    };

    // track
    var tr: otio.Track = .{};
    tr.name = try allocator.dupe(u8, "Example Parent Track");

    // clips
    const cl1 = otio.Clip {
        .name = try allocator.dupe(
            u8,
            "Spaghetti.mov",
        ),
        .media = .{
            .bounds_s = T_INT_1_TO_6,
            .discrete_info = .{
                .sample_rate_hz = .{ .Int = 48000 },
                .start_index = 0,
            },
            .ref = .{ 
                .signal = .{
                    .signal_generator = .{
                        .signal = .sine,
                        .duration_s = T_ORD_6,
                        .frequency_hz = 200,
                    },
                },
            },
        },
    };
    defer cl1.destroy(allocator);
    const cl_ptr : otio.ComposedValueRef = .{ .clip_ptr = &cl1 };

    // new for this test - add in an warp on the clip
    const wp: otio.Warp = .{
        .child = cl_ptr,
        .transform = try topology.Topology.init_affine(
            allocator,
            .{
                .input_to_output_xform = T_AFF_N1_2,
            },
        )
    };
    defer wp.transform.deinit(allocator);
    try tr.append(allocator,wp);
    const tr_ptr = try tl.tracks.append_fetch_ref(
        allocator,
        tr,
    );

    // build the topological map
    ///////////////////////////////////////////////////////////////////////////
    const topo_map = try otio.build_topological_map(
        allocator,
        tl_ptr
    );
    defer topo_map.deinit();

    try topo_map.write_dot_graph(
        allocator,
        "/var/tmp/track_clip_warp.dot"
    );

    const tr_pres_to_cl_media_po = (
        try topo_map.build_projection_operator(
            allocator,
            .{
                .source = try tr_ptr.space(.presentation),
                .destination = try cl_ptr.space(.media),
            },
        )
    );
    defer tr_pres_to_cl_media_po.deinit(allocator);

    // synthesize media
    const media = (
        try cl_ptr.clip_ptr.media.ref.signal.signal_generator.rasterized(
            allocator,
            cl_ptr.clip_ptr.media.discrete_info.?,
            true,
        )
    );
    defer media.deinit();
    try std.testing.expect(media.buffer.len > 0);

    // write the input file
    try media.write_file_prefix(
        allocator,
        "/var/tmp",
        "highlevel_libsamplerate_test_clip_media.",
        cl1.media.ref.signal.signal_generator,
    );

    // goal
    const result = try sampling.transform_resample_dd(
        allocator,
        media,
        tr_pres_to_cl_media_po.src_to_dst_topo,
        tl.discrete_info.presentation.?,
        false,
    );
    defer result.deinit();

    // result should match the timeline's discrete info
    try std.testing.expectEqual(
        tl.discrete_info.presentation.?.sample_rate_hz,
        result.index_generator.sample_rate_hz
    );

    const input_p2p = try sampling.peak_to_peak_distance(media.buffer);
    const result_p2p = try sampling.peak_to_peak_distance(result.buffer);

    try std.testing.expectEqual(input_p2p * 2, result_p2p);

    try result.write_file_prefix(
        allocator, 
        "/var/tmp/",
        "highlevel_libsamplerate_test_track_presentation.retimed.",
        null,
    );

    try std.testing.expect(result.buffer.len > 0);
}

// last test: use the projection_operator_map to render out the component media
// to an entire timeline
//
// also: same stuff but with non-interpolating media

test "libsamplerate w/ high level test.retime.non_interpolating"
{
    const allocator = std.testing.allocator;

    // top level timeline
    var tl: otio.Timeline = .{};
    tl.name = try allocator.dupe(u8, "Example Timeline");
    tl.discrete_info.presentation = .{
        // matches the media rate
        .sample_rate_hz = .{ .Int = 48000 },
        .start_index = 86400,
    };

    defer tl.recursively_deinit(allocator);
    const tl_ptr = otio.ComposedValueRef{
        .timeline_ptr = &tl 
    };

    // track
    var tr: otio.Track = .{};
    tr.name = try allocator.dupe(u8, "Example Parent Track");

    // clips
    const cl1 = otio.Clip {
        .name = try allocator.dupe(
            u8,
            "Spaghetti.mov",
        ),
        .media = .{
            .bounds_s = T_INT_1_TO_6,
            .discrete_info = .{
                .sample_rate_hz = .{ .Int = 48000 },
                .start_index = 0,
            },
            .ref = .{
                .signal = .{
                    .signal_generator = .{
                        .signal = .sine,
                        .duration_s = T_ORD_6,
                        .frequency_hz = 200,
                    },
                },
            },
        }
    };
    defer cl1.destroy(allocator);
    const cl_ptr = otio.ComposedValueRef.init(&cl1);

    const warp = otio.Warp{
        .child = cl_ptr,
        .transform = try topology.Topology.init_affine(
            allocator,
            .{
                .input_to_output_xform = T_AFF_N1_2,
            }
        )
    };
    defer warp.transform.deinit(allocator);

    // new for this test - add in an warp on the clip
    try tr.append(allocator,warp);

    const tr_ptr = try tl.tracks.append_fetch_ref(
        allocator,
        tr,
    );

    // build the topological map
    ///////////////////////////////////////////////////////////////////////////
    const topo_map = try otio.build_topological_map(
        allocator,
        tl_ptr
    );
    defer topo_map.deinit();

    const tr_pres_to_cl_media_po = (
        try topo_map.build_projection_operator(
            allocator,
            .{
                .source = try tr_ptr.space(.presentation),
                .destination = try cl_ptr.space(.media),
            },
        )
    );
    defer tr_pres_to_cl_media_po.deinit(allocator);

    // synthesize media
    const media = (
        try cl_ptr.clip_ptr.media.ref.signal.signal_generator.rasterized(
            allocator,
            cl_ptr.clip_ptr.media.discrete_info.?,
            false,
        )
    );
    defer media.deinit();
    try std.testing.expect(media.buffer.len > 0);

    // write the input file
    try media.write_file_prefix(
        allocator,
        "/var/tmp",
        "highlevel_libsamplerate_test_clip_media.",
        cl1.media.ref.signal.signal_generator,
    );

    // goal
    const indices_tr_pres = try sampling.transform_resample_dd(
        allocator,
        media,
        tr_pres_to_cl_media_po.src_to_dst_topo,
        tl.discrete_info.presentation.?,
        false,
    );
    defer indices_tr_pres.deinit();

    // result should match the timeline's discrete info
    try std.testing.expectEqual(
        tl.discrete_info.presentation.?.sample_rate_hz,
        indices_tr_pres.index_generator.sample_rate_hz
    );

    const input_p2p = try sampling.peak_to_peak_distance(media.buffer);
    const result_p2p = try sampling.peak_to_peak_distance(indices_tr_pres.buffer);

    // because the warp is scaling the presentation space by 2, the
    // presentation space should have half the peak to peak of the media
    // @TODO? ^ Nick is this correct?

    try std.testing.expectEqual(input_p2p / 2, result_p2p);

    try indices_tr_pres.write_file_prefix(
        allocator, 
        "/var/tmp/",
        "highlevel_libsamplerate_test_track_presentation.retimed.",
        null,
 
    );

    try std.testing.expect(indices_tr_pres.buffer.len > 0);

    // check the actual indices

    {
        const start_tr_pres = tr_pres_to_cl_media_po.source_bounds().start;

        const cl_media_indices = (
            try tr_pres_to_cl_media_po.project_range_cd(
                allocator,
                .{
                    .start = start_tr_pres,
                    .end = start_tr_pres.add(2.0/48000.0),
                },
            )
        );
        defer allocator.free(cl_media_indices);

        try std.testing.expectEqualSlices(
            sampling.sample_index_t, 
            &.{ 48000, 48002, },
            cl_media_indices,
        );
    }
}

// track -> warp (Reverse) -> clip
test "libsamplerate w/ high level test.retime.non_interpolating_reverse"
{
    const allocator = std.testing.allocator;

    // top level timeline
    var tl: otio.Timeline = .{};
    tl.name = try allocator.dupe(u8, "Timeline w/ 48000khz+86400 start");
    tl.discrete_info.presentation = .{
        // matches the media rate
        .sample_rate_hz = .{ .Int = 48000 },
        .start_index = 86400,
    };

    defer tl.recursively_deinit(allocator);
    const tl_ptr = otio.ComposedValueRef.init(&tl);

    // track
    var tr: otio.Track = .{};
    tr.name = try allocator.dupe(u8, "Parent Track");

    // clips
    const cl1 = otio.Clip {
        .name = try allocator.dupe(
            u8,
            "Spaghetti.mov",
        ),
        .media = .{
            .bounds_s = T_INT_1_TO_6,
            .discrete_info = .{
                .sample_rate_hz = .{ .Int = 48000 },
                .start_index = 0,
            },
            .ref = .{
                .signal = .{
                    .signal_generator = .{
                        .signal = .sine,
                        .duration_s = T_ORD_6,
                        .frequency_hz = 200,
                    },
                },
            },
        },
    };
    defer cl1.destroy(allocator);
    const cl_ptr = otio.ComposedValueRef.init(&cl1);

    // reverse the first 6 seconds of the target
    const wp_reverse: otio.Warp = .{
        .child = cl_ptr,
        .transform = try topology.Topology.init_from_linear_monotonic(
            allocator,
            .{
                .knots = &.{
                    .{ .in = opentime.Ordinate.ZERO, .out = T_ORD_6, },
                    .{ .in = T_ORD_6, .out = opentime.Ordinate.ZERO },   
                },
            },
        )
    };
    defer wp_reverse.transform.deinit(allocator);
    try tr.append(allocator,wp_reverse);

    const tr_ptr = try tl.tracks.append_fetch_ref(
        allocator,
        tr,
    );


    // build the topological map (Timeline.presentation -> ...)
    ///////////////////////////////////////////////////////////////////////////
    const topo_map = try otio.build_topological_map(
        allocator,
        tl_ptr,
    );
    defer topo_map.deinit();

    // build the projection operator (Track.presentation -> clip.media)
    ///////////////////////////////////////////////////////////////////////////
    const tr_pres_to_cl_media_po = (
        try topo_map.build_projection_operator(
            allocator,
            .{
                .source = try tr_ptr.space(.presentation),
                .destination = try cl_ptr.space(.media),
            },
        )
    );
    defer tr_pres_to_cl_media_po.deinit(allocator);

    {
        // start ordinate of the Track.presentation space
        const start_tr_pres = (
            tr_pres_to_cl_media_po.source_bounds().start
        );

        // project into the media index
        const start_ind_cl_media = (
            try tr_pres_to_cl_media_po.project_instantaneous_cd(start_tr_pres)
        );

        // 6 second signal at 48000 that starts 1 second in = 
        // [48000, 288000) -> [288000, 48000)
        try std.testing.expectEqual(
            288000,
            start_ind_cl_media,
        );

        const indices_cl_media = (
            try tr_pres_to_cl_media_po.project_range_cd(
                allocator,
                .{
                    .start = start_tr_pres,
                    .end = start_tr_pres.add(4.0/48000.0),
                },
            )
        );
        defer allocator.free(indices_cl_media);

        try std.testing.expect(indices_cl_media.len > 0);

        try std.testing.expectEqualSlices(
            sampling.sample_index_t, 
            &.{ 288000, 287999, 287998, 287997,},
            indices_cl_media,
        );
    }
}

test "timeline w/ warp that holds the tenth frame"
{
    const allocator = std.testing.allocator;

    // top level timeline
    var tl: otio.Timeline = .{};
    defer tl.recursively_deinit(allocator);
    tl.name = try allocator.dupe(u8, "Example Timeline");
    tl.discrete_info.presentation = .{
        // matches the media rate
        .sample_rate_hz = .{ .Int = 24 },
        .start_index = 0,
    };

    const tl_ptr = otio.ComposedValueRef{
        .timeline_ptr = &tl 
    };

    // track
    var tr: otio.Track = .{};
    tr.name = try allocator.dupe(u8, "Example Parent Track");

    // clips
    const cl1 = otio.Clip {
        .name = try allocator.dupe(
            u8,
            "Spaghetti.mov",
        ),
        .media = .{
            .bounds_s = T_INT_1_TO_6,
            .discrete_info = .{
                .sample_rate_hz = .{ .Int = 24 },
                .start_index = 0,
            },
            .ref = .{
                .signal = .{
                    .signal_generator = .{ 
                        .signal = .sine,
                        .duration_s = T_ORD_6,
                        .frequency_hz = 24,
                    },
                },
            },
        },
    };
    defer cl1.destroy(allocator);
    const cl_ptr = otio.ComposedValueRef.init(&cl1);

    const ord_10f24hz = opentime.Ordinate.init(10.0/24.0);


    // new for this test - add in an warp on the clip, which holds the frame
    const wp = otio.Warp {
        .child = cl_ptr,
        .transform = try topology.Topology.init_from_linear_monotonic(
            allocator,
            .{
                .knots = &.{
                    .{ .in = opentime.Ordinate.ZERO, .out = ord_10f24hz,},
                    .{ .in = opentime.Ordinate.init(5), .out = ord_10f24hz,},
                },
            },
        )
    };
    defer wp.transform.deinit(allocator);
    try tr.append(allocator,wp);

    const tr_ptr = try tl.tracks.append_fetch_ref(
        allocator,
        tr,
    );

    const warp_ptr = (
        tr_ptr.track_ptr.child_ptr_from_index(0)
    );
    const w_ib = (
        warp_ptr.warp_ptr.transform.input_bounds()
    );
    const w_ob = (
        warp_ptr.warp_ptr.transform.output_bounds()
    );

    errdefer opentime.dbg_print(@src(),
        "WARP\n input bounds: {s}\n output bounds: {s}\n",
        .{ w_ib, w_ob },
    );

    try std.testing.expect(w_ib.start.is_nan() == false);
    try std.testing.expect(w_ib.end.is_nan() == false);

    try std.testing.expect(w_ob.start.is_nan() == false);
    try std.testing.expect(w_ob.end.is_nan() == false);

    // build the topological map
    ///////////////////////////////////////////////////////////////////////////
    const topo_map = try otio.build_topological_map(
        allocator,
        tl_ptr
    );
    defer topo_map.deinit();

    const tr_pres_to_cl_media_po = (
        try topo_map.build_projection_operator(
            allocator,
            .{
                .source = try tr_ptr.space(.presentation),
                .destination = try cl_ptr.space(.media),
            },
        )
    );
    defer tr_pres_to_cl_media_po.deinit(allocator);

    try std.testing.expect(
        std.meta.activeTag(
            tr_pres_to_cl_media_po.src_to_dst_topo.mappings[0]
        ) != .empty
    );

    // check the actual indices
    {
        const warp_pres_to_warp_child_xform = (
            tr_ptr.track_ptr.child_ptr_from_index(0).warp_ptr.transform
        );
        
        const ident = (
            try topology.Topology.init_identity_infinite(
                allocator
            )
        );
        defer ident.deinit(allocator);

        const test_result = try topology.join(
            std.testing.allocator,
            .{ 
                .a2b = ident,
                .b2c = warp_pres_to_warp_child_xform,
            },
        );
        defer test_result.deinit(allocator);

        const result_buf = (
            try tr_pres_to_cl_media_po.project_range_cd(
                allocator,
                .{
                    .start = opentime.Ordinate.ZERO,
                    .end =  opentime.Ordinate.init(4.0/24.0),
                },
            )
        );
        defer allocator.free(result_buf);

        try std.testing.expectEqualSlices(
            sampling.sample_index_t, 
            // 34 because of the 1 second start time in the destination
            &.{ 34, 34, 34, 34, },
            result_buf,
        );
    }
}

test "timeline running at 24*1000/1001 with media at 24 showing skew"
{
    const allocator = std.testing.allocator;

    // build the timeline
    ///////////////////////////////////////////////////////////////////////////

    // top level timeline
    var tl: otio.Timeline = .{};
    defer tl.recursively_deinit(allocator);

    tl.name = try allocator.dupe(u8, "Timeline @ 24 * 1000/1001");
    tl.discrete_info.presentation = .{
        .sample_rate_hz = .{ 
        // matches the media rate
            .Rat = .{
                .num = 24 * 1000,
                .den = 1001 
            } 
        },
        .start_index = 0,
    };

    const tl_ptr = otio.ComposedValueRef.init(&tl);

    // track
    var tr: otio.Track = .{};

    tr.name = try allocator.dupe(u8, "Track for clip");

    // clip
    const cl = otio.Clip {
        .name = try allocator.dupe(
            u8,
            "Clip at 24",
        ),
        .media = .{
            .bounds_s = .{
                .start = opentime.Ordinate.ZERO,
                .end = opentime.Ordinate.init(60000),
            },
            .discrete_info = .{
                .sample_rate_hz = .{ .Int = 24 },
                .start_index = 0,
            },
        },
    };

    const cl_ptr = try tr.append_fetch_ref(
        allocator,
        cl,
    );
    try tl.tracks.append(allocator,tr);

    // build the topological map
    ///////////////////////////////////////////////////////////////////////////
    const topo_map = try otio.build_topological_map(
        allocator,
        tl_ptr,
    );
    defer topo_map.deinit();

    // Build the projection from Timeline Presentation -> Clip Media
    ///////////////////////////////////////////////////////////////////////////
    const tl_pres_to_cl_media_po = (
        try topo_map.build_projection_operator(
            allocator,
            .{
                .source = try tl_ptr.space(.presentation),
                .destination = try cl_ptr.space(.media),
            },
        )
    );
    defer tl_pres_to_cl_media_po.deinit(allocator);

    // Run the Tests
    ///////////////////////////////////////////////////////////////////////////

    // walk across the domain and ensure that continuous projection is an
    // identity
    {
        const tl_pres_bounds = (
            tl_pres_to_cl_media_po.source_bounds()
        );

        // continuous projection is an identity across the entire domain,
        // because the discretization happens before and after the continuous
        // transformation
        var i = tl_pres_bounds.start;
        while (i.lt(tl_pres_bounds.end))
            : (i = i.add(0.01))
        {
            try opentime.expectOrdinateEqual(
                i,
                tl_pres_to_cl_media_po.project_instantaneous_cc(
                    i
                ).ordinate(),
            );
        }
    }

    const TestCase = struct {
        name: []const u8,
        tl_pres_index: sampling.sample_index_t,
        cl_media_indices: []const sampling.sample_index_t,
    };

    const tests = [_]TestCase{
        .{ 
            .name = "zero",
            // 23.97
            .tl_pres_index = 0,
            // 24
            .cl_media_indices = &.{ 0, 1 },
        },
        .{ 
            .name = "one thousand",
            .tl_pres_index = 1000,
            .cl_media_indices = &.{ 1001, 1002 },
        },
        // .{ 
        //     .name = "24 thousand (err?)",
        //     .tl_pres_index = 24000,
        //     .cl_media_indices = &.{ 24024, 24025 },
        // },
    };

    for (&tests)
        |t|
    {
        const clip_media_indices = (
            try tl_pres_to_cl_media_po.project_index_dd(
                allocator,
                t.tl_pres_index,
            )
        );
        defer allocator.free(clip_media_indices);

        // test a point before the skew
        try std.testing.expectEqualSlices(
            sampling.sample_index_t,
            t.cl_media_indices,
            clip_media_indices,
        );
    }
}
