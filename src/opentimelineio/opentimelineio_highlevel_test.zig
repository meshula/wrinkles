//! Demonstration of new features in this lib via unit tests

const std = @import("std");

const otio = @import("root.zig");

const opentime = @import("opentime");
const topology = @import("topology");
const sampling = @import("sampling");

// for verbose print of test
const PRINT_DEMO_OUTPUT = false;

// Duration of the test signal
const T_SIGNAL_DURATION = 1;
const T_ORD_SIGNAL_DURATION = opentime.Ordinate.init(
    T_SIGNAL_DURATION
);
const T_SIGNAL_START = 1;
const T_ORD_SIGNAL_GEN_DURATION = T_ORD_SIGNAL_DURATION.mul(
    2
);
const T_SIGNAL_START_ORD = opentime.Ordinate.init(
    T_SIGNAL_START,
);
const T_INT_SIGNAL = opentime.ContinuousInterval{
    .start = T_SIGNAL_START_ORD,
    .end = T_ORD_SIGNAL_DURATION.add(T_SIGNAL_START_ORD),
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
    // clips
    var cl1:otio.Clip = .{
        .name = "Spaghetti.mov",
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
    var gp = otio.Gap{
        .duration_seconds = opentime.Ordinate.ONE,
    };
    var cl2: otio.Clip = .{
        .name = "Taco.mov",
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
    var track_children = [_]otio.ComposedValueRef{
        .{ .clip = &cl1 },
        .{ .gap = &gp },
        .{ .clip = &cl2 },
    };

    // track
    var tr: otio.Track = .{
        .name = "Example Parent Track",
        .children = &track_children,
    };

    // top level timeline
    var tl_children = [_]otio.ComposedValueRef{
        tr.reference(),
    };
    var tl: otio.Timeline = .{
        .name = "Example Timeline - high level procedural test",
        .discrete_info = .{ 
            .presentation = .{
                .sample_rate_hz = .{ .Int = 24 },
                .start_index = 86400,
            },
        },
        .tracks = .{ 
            .children = &tl_children, 
        },
    };
    const tl_ptr = tl.reference();

    // build the temporal map
    ///////////////////////////////////////////////////////////////////////////
    var proj_topo = (
        try otio.ProjectionTopology.init_from(
            allocator, 
            tl_ptr.space(.presentation)
        )
    );
    defer proj_topo.deinit(allocator);

    const timeline_to_clip2 = (
        try proj_topo.projection_operator_to(
            allocator,
            tr.children[2].space(.media)
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

    const src_discrete_info = (
        proj_topo.source.ref.discrete_info_for_space(.presentation)
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
                proj_topo.input_bounds().start,
                proj_topo.input_bounds().end,
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
        proj_topo.intervals.items(.input_bounds),
        proj_topo.intervals.items(.mapping_index),
        0..
    ) |interval, mappings, ind|
    {
        if  (PRINT_DEMO_OUTPUT)
        {
            opentime.dbg_print(
                @src(),
                "  presentation space:\n    interval: {f}\n",
                .{interval},
            );
        }
        for (mappings)
            |map_ind|
        {
            const op = proj_topo.mappings.get(map_ind);

            if (PRINT_DEMO_OUTPUT)
            {
                opentime.dbg_print(
                    @src(),
                    "    Topology\n      presentation:  {any}\n"
                    ++ "      media: {any}\n",
                    .{
                        op.src_to_dst_topo.input_bounds(),
                        op.src_to_dst_topo.output_bounds(),
                    },
                );
            }
            const destination = proj_topo.temporal_space_graph.nodes.get(
                op.destination
            );

            const di = (
                destination.ref.discrete_info_for_space(.media)
            );

            if (di == null)
            {
                continue;
            }

            if (PRINT_DEMO_OUTPUT and di != null)
            {
                opentime.dbg_print(
                    @src(),
                    "    Discrete Info:\n      sampling rate: {d}\n"
                    ++ "      start index: {d}\n",
                    .{
                        di.sample_rate_hz,
                        di.start_index,
                    },
                );
            }

            const po = otio.ProjectionOperator{
                .source = proj_topo.source,
                .destination = destination,
                .src_to_dst_topo = .{
                    .mappings = &.{ op.mapping },
                },
            };

            const dest_frames = try po.project_range_cd(
                allocator,
                interval,
            );
            defer allocator.free(dest_frames);

            errdefer std.debug.print(
                "error at op_ind: {d}\n",
                .{ ind }
            );

            try std.testing.expectEqualSlices(
                sampling.sample_index_t,
                known_frames[ind],
                dest_frames,
            );

            if (PRINT_DEMO_OUTPUT)
            {
                opentime.dbg_print(@src(),
                    "    Source: \n      target: {?s}\n"
                    ++ "      frames: {any}\n",
                    .{ 
                        op.destination.ref.clip.name orelse "pasta",
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

    var cl1 = otio.Clip {
        .name = "Spaghetti.mov",
        .media = .{
            .bounds_s = T_INT_SIGNAL,
            .discrete_info = .{
                .sample_rate_hz = .{ .Int = 48000 },
                .start_index = 0,
            },
            .ref = .{ 
                .signal = .{
                    .signal_generator = .{
                        .signal = .sine,
                        .duration_s = T_ORD_SIGNAL_GEN_DURATION,
                        .frequency_hz = 200,
                    }
                }
            },
        }
    };
    var track_children = [_]otio.ComposedValueRef{
        otio.ComposedValueRef.init(&cl1),
    };
    const cl_ptr = track_children[0];
    var tr: otio.Track = .{
        .name = "Example Parent Track",
        .children = &track_children,
    };
    var stack_children = [_]otio.ComposedValueRef{
        otio.ComposedValueRef.init(&tr),
    };
    const tr_ptr = stack_children[0];
    var tl: otio.Timeline = .{
        .name = "Example Timeline - resample only test",
        .discrete_info = .{ 
            .presentation = .{
                .sample_rate_hz = .{ .Int = 44100 },
                .start_index = 86400,
            },
        },
        .tracks = .{
            .children = &stack_children,
        },
    };
    const tl_ptr = otio.ComposedValueRef.init(&tl);

    {
        const bounds = try cl1.bounds_of(
            allocator,
            .media
        );
        try std.testing.expect(
            cl1.media.bounds_s.?.start.lt(cl1.media.bounds_s.?.end)
        );
        try std.testing.expect(bounds.end.eql(0) == false);
        try std.testing.expect(bounds.start.lt(bounds.end));
    }

    // build the temporal map
    ///////////////////////////////////////////////////////////////////////////
    const graph = try otio.build_temporal_graph(
        allocator,
        tl_ptr,
    );
    defer graph.deinit(allocator);

    const cache = (
        try otio.temporal_hierarchy.SingleSourceTopologyCache.init(
            allocator,
            graph,
        )
    );
    defer cache.deinit(allocator);

    const tr_pres_to_cl_media_po = (
        try otio.build_projection_operator(
            allocator,
            graph,
            .{
                .source = tr_ptr.space(.presentation),
                .destination = cl_ptr.space(.media),
            },
            cache,
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
        T_ORD_SIGNAL_DURATION,
        pres_bounds.end,
    );

    try std.testing.expect(
        cl1.media.ref.signal.signal_generator.duration_s.gt(0)
    );

    // synthesize media
    const media_samples = (
        try cl1.media.ref.signal.signal_generator.rasterized(
            allocator,
            cl1.media.discrete_info.?,
            true,
        )
    );
    defer media_samples.deinit(allocator);
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
    defer cl_media_samples_for_tr_pres.deinit(allocator);

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

    var cl1 = otio.Clip {
        .name = "Clip w/ media ref pointing at a Sine Signal",
        .media = .{
            .bounds_s = T_INT_SIGNAL,
            .discrete_info = .{
                .sample_rate_hz = .{ .Int = 48000 },
                .start_index = 0,
            },
            .ref = .{ 
                .signal = .{
                    .signal_generator = .{
                        .signal = .sine,
                        .duration_s = T_ORD_SIGNAL_GEN_DURATION,
                        .frequency_hz = 200,
                    },
                },
            },
        },
    };
    
    const cl_ptr = otio.ComposedValueRef{
        .clip = &cl1,
    };

    // new for this test - add in an warp on the clip
    var wp: otio.Warp = .{
        .name = "-1 offset 2 scale",
        .child = cl_ptr,
        .transform = try topology.Topology.init_affine(
            allocator,
            .{
                .input_to_output_xform = T_AFF_N1_2,
                .input_bounds_val = .INF,
            },
        )
    };
    defer wp.transform.deinit(allocator);

    var track_children = [_]otio.ComposedValueRef{
        otio.ComposedValueRef.init(&wp),
    };
    var tr: otio.Track = .{
        .name ="Example Parent Track",
        .children = &track_children,
    };
    const tr_ptr = otio.ComposedValueRef.init(&tr);

    var stack_children = [_]otio.ComposedValueRef{tr_ptr};
    var tl: otio.Timeline = .{
        .name = "Example Timeline test.retime.interpolating",
        .discrete_info = .{ 
            .presentation = .{
                // matches the media rate
                .sample_rate_hz = .{ .Int = 48000 },
                .start_index = 86400,
            },
        },
        .tracks = .{
            .children = &stack_children,
        },
    };
    const tl_ptr = otio.ComposedValueRef.init(&tl);

    // build the temporal map
    ///////////////////////////////////////////////////////////////////////////
    var proj_topo_from_tl_pres = (
        try otio.ProjectionTopology.init_from(
            allocator, 
            tl_ptr.space(.presentation)
        )
    );
    defer proj_topo_from_tl_pres.deinit(allocator);

    try proj_topo_from_tl_pres.temporal_space_graph.write_dot_graph(
        allocator,
        "/var/tmp/track_clip_warp.dot",
        "track_clip_warp",
        .{},
    );

    const tl_pres_to_cl_media_po = (
        try proj_topo_from_tl_pres.projection_operator_to(
            allocator,
            cl_ptr.space(.media),
        )
    );
    defer tl_pres_to_cl_media_po.deinit(allocator);

    try std.testing.expect(
        tl_pres_to_cl_media_po.src_to_dst_topo.mappings[0] != .empty
    );

    // synthesize media
    const media = (
        try cl1.media.ref.signal.signal_generator.rasterized(
            allocator,
            cl1.media.discrete_info.?,
            true,
        )
    );
    defer media.deinit(allocator);
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
        // @TODO: this should be input_c_to_output_c, so the inversion happens
        //        ABOVE the resample.  its weird that its written the other way
        //        here.
        tl_pres_to_cl_media_po.src_to_dst_topo,
        tl.discrete_info.presentation.?,
        false,
    );
    defer result.deinit(allocator);

    // result should match the timeline's discrete info
    try std.testing.expectEqual(
        tl.discrete_info.presentation.?.sample_rate_hz,
        result.index_generator.sample_rate_hz,
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

    var cl1 = otio.Clip {
        .name = "Sine Wave",
        .media = .{
            .bounds_s = T_INT_SIGNAL,
            .discrete_info = .{
                .sample_rate_hz = .{ .Int = 48000 },
                .start_index = 0,
            },
            .ref = .{
                .signal = .{
                    .signal_generator = .{
                        .signal = .sine,
                        .duration_s = T_ORD_SIGNAL_GEN_DURATION,
                        .frequency_hz = 200,
                    },
                },
            },
        }
    };
    const cl_ptr = otio.ComposedValueRef.init(&cl1);

    var warp = otio.Warp{
        .child = cl_ptr,
        .transform = try topology.Topology.init_affine(
            allocator,
            .{
                .input_to_output_xform = T_AFF_N1_2,
                .input_bounds_val = .INF,
            }
        )
    };
    defer warp.transform.deinit(allocator);

    var track_children = [_]otio.ComposedValueRef{
        .{ .warp = &warp },
    };
    var tr: otio.Track = .{
        .name = "Example Parent Track",
        .children = &track_children,
    };
    const tr_ptr = otio.ComposedValueRef{
        .track = &tr 
    };

    var timeline_children = [_]otio.ComposedValueRef{
        tr_ptr,
    };
    const tl: otio.Timeline = .{
        .name = (
            "Example Timeline - high level test.retime.non_interpolating"
        ),
        .discrete_info = .{ 
            .presentation = .{
                // matches the media rate
                .sample_rate_hz = .{ .Int = 48000 },
                .start_index = 86400,
            },
        },
        .tracks = .{
            .children = &timeline_children,
        },
    };

    // build the temporal map
    ///////////////////////////////////////////////////////////////////////////
    var proj_topo_from_tr_pres = (
        try otio.ProjectionTopology.init_from(
            allocator, 
            tr_ptr.space(.presentation)
        )
    );
    defer proj_topo_from_tr_pres.deinit(allocator);

    const tr_pres_to_cl_media_po = (
        try proj_topo_from_tr_pres.projection_operator_to(
            allocator,
            cl_ptr.space(.media),
        )
    );
    defer tr_pres_to_cl_media_po.deinit(allocator);

    // synthesize media
    const media = (
        try cl1.media.ref.signal.signal_generator.rasterized(
            allocator,
            cl1.media.discrete_info.?,
            false,
        )
    );
    defer media.deinit(allocator);
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
    defer indices_tr_pres.deinit(allocator);

    // result should match the timeline's discrete info
    try std.testing.expectEqual(
        tl.discrete_info.presentation.?.sample_rate_hz,
        indices_tr_pres.index_generator.sample_rate_hz
    );

    const input_p2p = try sampling.peak_to_peak_distance(media.buffer);
    const result_p2p = try sampling.peak_to_peak_distance(
        indices_tr_pres.buffer
    );

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

    const sample_rate = 48000;

    var cl1 = otio.Clip {
        .name = "Spaghetti.mov",
        .media = .{
            .bounds_s = T_INT_SIGNAL,
            .discrete_info = .{
                .sample_rate_hz = .{ .Int = sample_rate },
                .start_index = 0,
            },
            .ref = .{
                .signal = .{
                    .signal_generator = .{
                        .signal = .sine,
                        .duration_s = T_ORD_SIGNAL_GEN_DURATION,
                        .frequency_hz = 200,
                    },
                },
            },
        },
    };
    const cl_ptr = otio.ComposedValueRef.init(&cl1);

    // reverse the first 6 seconds of the target
    var wp_reverse: otio.Warp = .{
        .child = cl_ptr,
        .transform = try topology.Topology.init_from_linear_monotonic(
            allocator,
            .{
                .knots = &.{
                    .{
                        .in = opentime.Ordinate.ZERO,
                        .out = T_ORD_SIGNAL_DURATION, 
                    },
                    .{
                        .in = T_ORD_SIGNAL_DURATION,
                        .out = opentime.Ordinate.ZERO 
                    },   
                },
            },
        )
    };
    defer wp_reverse.transform.deinit(allocator);

    var track_children = [_]otio.ComposedValueRef{
        .{ .warp = &wp_reverse },
    };
    var tr: otio.Track = .{
        .name = "Parent Track",
        .children = &track_children,
    };

    const tr_ptr = otio.ComposedValueRef{
        .track = &tr,
    };

    // build the temporal map (Tr.presentation -> ...)
    ///////////////////////////////////////////////////////////////////////////
    var proj_topo_from_tr_pres = (
        try otio.ProjectionTopology.init_from(
            allocator, 
            tr_ptr.space(.presentation)
        )
    );
    defer proj_topo_from_tr_pres.deinit(allocator);

    // build the projection operator (Track.presentation -> clip.media)
    ///////////////////////////////////////////////////////////////////////////
    const tr_pres_to_cl_media_po = (
        try proj_topo_from_tr_pres.projection_operator_to(
            allocator, 
            cl_ptr.space(.media),
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

        const expected_start_index = (
            T_SIGNAL_START * sample_rate 
            + T_SIGNAL_DURATION * sample_rate
        );

        // 6 second signal at 48000 that starts 1 second in = 
        // [48000, 288000) -> [288000, 48000)
        try std.testing.expectEqual(
            expected_start_index,
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
            &.{
                expected_start_index,
                expected_start_index - 1,
                expected_start_index - 2,
                expected_start_index - 3,
            },
            indices_cl_media,
        );
    }
}

test "timeline w/ warp that holds the tenth frame"
{
    const allocator = std.testing.allocator;

    // track

    // clips
    var cl1 = otio.Clip {
        .name = "Spaghetti.mov",
        .media = .{
            .bounds_s = T_INT_SIGNAL,
            .discrete_info = .{
                .sample_rate_hz = .{ .Int = 24 },
                .start_index = 0,
            },
            .ref = .{
                .signal = .{
                    .signal_generator = .{ 
                        .signal = .sine,
                        .duration_s = T_ORD_SIGNAL_DURATION,
                        .frequency_hz = 24,
                    },
                },
            },
        },
    };
    const cl_ptr = otio.ComposedValueRef.init(&cl1);

    const ord_10f24hz = opentime.Ordinate.init(10.0/24.0);

    // new for this test - add in an warp on the clip, which holds the frame
    var wp = otio.Warp {
        .child = cl_ptr,
        .transform = try topology.Topology.init_from_linear_monotonic(
            allocator,
            .{
                .knots = &.{
                    .{
                        .in = opentime.Ordinate.ZERO,
                        .out = ord_10f24hz,
                    },
                    .{
                        .in = opentime.Ordinate.init(5),
                        .out = ord_10f24hz,
                    },
                },
            },
        )
    };
    defer wp.transform.deinit(allocator);
    const warp_ptr =  otio.ComposedValueRef.init(&wp);

    const w_ib = (
        warp_ptr.warp.transform.input_bounds()
    );
    const w_ob = (
        warp_ptr.warp.transform.output_bounds()
    );

    var tr_children = [_]otio.ComposedValueRef{
        warp_ptr,
    };
    var tr: otio.Track = .{
        .name = "Example Parent Track",
        .children = &tr_children,
    };
    const tr_ptr = otio.ComposedValueRef.init(&tr);

    errdefer opentime.dbg_print(
        @src(),
        "WARP\n input bounds: {f}\n output bounds: {f}\n",
        .{ w_ib, w_ob },
    );

    try std.testing.expect(w_ib.start.is_nan() == false);
    try std.testing.expect(w_ib.end.is_nan() == false);

    try std.testing.expect(w_ob.start.is_nan() == false);
    try std.testing.expect(w_ob.end.is_nan() == false);

    // build the temporal map
    ///////////////////////////////////////////////////////////////////////////
    var proj_topo_from_tr_pres = (
        try otio.ProjectionTopology.init_from(
            allocator, 
            tr_ptr.space(.presentation)
        )
    );
    defer proj_topo_from_tr_pres.deinit(allocator);

    // build projection operator
    const tr_pres_to_cl_media_po = (
        try proj_topo_from_tr_pres.projection_operator_to(
            allocator,
            cl_ptr.space(.media),
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
            tr_ptr.track.children[0].warp.transform
        );
        
        const ident:topology.Topology = .INFINITE_IDENTITY;

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

    var cl = otio.Clip {
        .name = "Clip at 24",
        .media = .{
            .bounds_s = .{
                .start = opentime.Ordinate.ZERO,
                .end = opentime.Ordinate.init(24000),
            },
            .discrete_info = .{
                .sample_rate_hz = .{ .Int = 24 },
                .start_index = 0,
            },
        },
    };
    const cl_ptr = otio.ComposedValueRef.init(&cl);

    var tr_children = [_]otio.ComposedValueRef{
        cl_ptr
    };
    var tr: otio.Track = .{
        .name = "Track for clip",
        .children = &tr_children,
    };

    var tl_children = [_]otio.ComposedValueRef{
        otio.ComposedValueRef.init(&tr),
    };
    var tl: otio.Timeline = .{
        .name = "Timeline @ 24 * 1000/1001 with media showing skew",
        .discrete_info = .{ 
            .presentation = .{
                .sample_rate_hz = .{ 
                    // matches the media rate
                    .Rat = .{
                        .num = 24 * 1000,
                        .den = 1001 
                    } 
                },
                .start_index = 0,
            },
        },
        .tracks = .{ .children = &tl_children },
    };
    const tl_ptr = otio.ComposedValueRef.init(&tl);

    // build the temporal map
    ///////////////////////////////////////////////////////////////////////////
    var proj_topo_from_tl_pres = (
        try otio.ProjectionTopology.init_from(
            allocator, 
            tl_ptr.space(.presentation)
        )
    );
    defer proj_topo_from_tl_pres.deinit(allocator);

    // Build the projection from Timeline Presentation -> Clip Media
    ///////////////////////////////////////////////////////////////////////////
    const tl_pres_to_cl_media_po = (
        try proj_topo_from_tl_pres.projection_operator_to(
            allocator,
            cl_ptr.space(.media),
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
                // can assume in bounds because the bounds are being explicitly
                // walked over
                tl_pres_to_cl_media_po.project_instantaneous_cc_assume_in_bounds(
                    i
                ).ordinate(),
            );
        }
    }

    // test discrete sample projection
    ////////////////////////////////////

    const TestCase = struct {
        name: []const u8,
        tl_pres_index: sampling.sample_index_t,
        cl_media_indices: []const sampling.sample_index_t,
    };

    // because the top level timeline is 24 * 1000 / 1001 hz (slightly fewer
    // samples per second) and the clip is 24 hz samples from the top level
    // timeline will always overlap multiple samples of the clip
    const tests = [_]TestCase{
        .{ 
            .name = "zero",
            // 24 * 1000/1001
            .tl_pres_index = 0,
            // 24
            .cl_media_indices = &.{ 0, 1 },
        },
        .{ 
            .name = "one thousand",
            .tl_pres_index = 1000,
            .cl_media_indices = &.{ 1001, 1002 },
        },
        .{ 
            .name = "24 thousand",
            .tl_pres_index = 24000,
            .cl_media_indices = &.{ 24024, 24025 },
        },
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
