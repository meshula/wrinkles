//! Demonstration of new features in this lib via unit tests

const std = @import("std");
const otio = @import("opentimelineio.zig");
const opentime = @import("opentime");
const topology = @import("topology");
const sampling = @import("sampling");

// for verbose print of test
const PRINT_DEMO_OUTPUT = false;

test "otio: high level procedural test [clip][   gap    ][clip]"
{
    const allocator = std.testing.allocator;

    // describe the timeline data structure
    ///////////////////////////////////////////////////////////////////////////
 
    // top level timeline
    var tl = try otio.Timeline.init(allocator);
    tl.name = try allocator.dupe(u8, "Example Timeline");
    tl.discrete_info.presentation = .{
        .sample_rate_hz = 24,
        .start_index = 86400,
    };

    defer tl.recursively_deinit();
    const tl_ptr = otio.ComposedValueRef{
        .timeline_ptr = &tl 
    };

    // track
    var tr = otio.Track.init(allocator);
    tr.name = try allocator.dupe(u8, "Example Parent Track");

    // clips
    const cl1 = otio.Clip {
        .name = try allocator.dupe(
            u8,
            "Spaghetti.mov",
        ),
        .media_temporal_bounds = .{
            .start = 1,
            .end = 3 
        },
        .discrete_info = .{
            .media = .{
                .sample_rate_hz = 24,
                .start_index = 10,
            },
        },
    };
    try tr.append(cl1);

    // gap
    const gp = otio.Gap{
        .duration_seconds = 1,
    };
    try tr.append(gp);

    // clip
    const cl2 = otio.Clip {
        .name = try allocator.dupe(
            u8,
            "Taco.mov"
        ),
        .media_temporal_bounds = .{
            .start = 10,
            .end = 11, 
        },
        .discrete_info = .{
            .media = .{
                .sample_rate_hz = 30,
                .start_index = 10,
            },
        },
    };

    // build some pointers into the structure
    const cl2_ptr = try tr.append_fetch_ref(cl2);
    try tl.tracks.append(tr);

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
            "  Discrete Info:\n    sampling rate: {d}\n    start index: {d}\n",
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

    // walk across the general projection operator map
    ///////////////////////////////////////////////////////////////////////////
    for (
        proj_map.end_points[0..(proj_map.end_points.len-1)],
        proj_map.end_points[1..],
        proj_map.operators,
    )
        |p0, p1, ops|
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
                    .end = p1 
                }
            );
            defer allocator.free(dest_frames);

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
    var tl = try otio.Timeline.init(allocator);
    tl.name = try allocator.dupe(u8, "Example Timeline");
    tl.discrete_info.presentation = .{
        .sample_rate_hz = 44100,
        .start_index = 86400,
    };

    defer tl.recursively_deinit();
    const tl_ptr = otio.ComposedValueRef{
        .timeline_ptr = &tl 
    };

    // track
    var tr = otio.Track.init(allocator);
    tr.name = try allocator.dupe(u8, "Example Parent Track");

    // clips
    const cl1 = otio.Clip {
        .name = try allocator.dupe(
            u8,
            "Spaghetti.mov",
        ),
        .media_temporal_bounds = .{
            .start = 1,
            .end = 6,
        },
        .discrete_info = .{
            .media = .{
                .sample_rate_hz = 48000,
                .start_index = 0,
            },
        },
        .media_reference = .{
            .signal_reference = .{
                .sample_index_generator = .{
                    .sample_rate_hz = 48000, 
                },
                .signal_generator = .{ 
                    .signal = .sine,
                    .duration_s = 6.0,
                    .frequency_hz = 200,
                },
                .interpolating = true,
            },
        }
    };
    try std.testing.expect(
        cl1.media_temporal_bounds.?.start < 
        cl1.media_temporal_bounds.?.end
    );
    try std.testing.expect(
        (try cl1.bounds_of(allocator, .media)).end != 0,
    );
    try std.testing.expect(
        (try cl1.bounds_of(allocator, .media)).start < 
        (try cl1.bounds_of(allocator, .media)).end
    );

    const cl_ptr = try tr.append_fetch_ref(cl1);
    const tr_ptr = try tl.tracks.append_fetch_ref(tr);

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

    try std.testing.expectEqual(
        .affine,
        std.meta.activeTag(
            tr_pres_to_cl_media_po.src_to_dst_topo.mappings[0]
        ),
    );

    try std.testing.expect(
        tr_pres_to_cl_media_po.src_to_dst_topo.input_bounds().end > 0,
    );

    try std.testing.expect(
        cl1.media_reference.?.signal_reference.signal_generator.duration_s > 0
    );

    // synthesize media
    const media = (
        try cl_ptr.clip_ptr.media_reference.?.signal_reference.rasterized(
            allocator,
        )
    );
    defer media.deinit();
    try std.testing.expect(media.buffer.len > 0);

    // write the input file
    try media.write_file_prefix(
        allocator,
        "/var/tmp",
        "highlevel_libsamplerate_test_clip_media.",
        cl1.media_reference.?.signal_reference.signal_generator,
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

    try result.write_file_prefix(
        allocator, 
        "/var/tmp/",
        "highlevel_libsamplerate_test_track_presentation.resampled_only.",
        null,
 
    );

    try std.testing.expect(result.buffer.len > 0);
}

test "libsamplerate w/ high level test.retime.interpolating"
{
    const allocator = std.testing.allocator;

    // top level timeline
    var tl = try otio.Timeline.init(allocator);
    tl.name = try allocator.dupe(u8, "Example Timeline");
    tl.discrete_info.presentation = .{
        // matches the media rate
        .sample_rate_hz = 48000,
        .start_index = 86400,
    };

    defer tl.recursively_deinit();
    const tl_ptr = otio.ComposedValueRef{
        .timeline_ptr = &tl 
    };

    // track
    var tr = otio.Track.init(allocator);
    tr.name = try allocator.dupe(u8, "Example Parent Track");

    // clips
    const cl1 = otio.Clip {
        .name = try allocator.dupe(
            u8,
            "Spaghetti.mov",
        ),
        .media_temporal_bounds = .{
            .start = 1,
            .end = 6,
        },
        .discrete_info = .{
            .media = .{
                .sample_rate_hz = 48000,
                .start_index = 0,
            },
        },
        .media_reference = .{
            .signal_reference = .{
                .sample_index_generator = .{
                    .sample_rate_hz = 48000, 
                },
                .signal_generator = .{
                    .signal = .sine,
                    .duration_s = 6.0,
                    .frequency_hz = 200,
                },
                .interpolating = true,
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
                .input_to_output_xform = .{
                    .offset = -1,
                    .scale = 2,
                },
            },
        )
    };
    defer wp.transform.deinit(allocator);
    try tr.append(wp);
    const tr_ptr = try tl.tracks.append_fetch_ref(tr);

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
        try cl_ptr.clip_ptr.media_reference.?.signal_reference.rasterized(
            allocator,
        )
    );
    defer media.deinit();
    try std.testing.expect(media.buffer.len > 0);

    // write the input file
    try media.write_file_prefix(
        allocator,
        "/var/tmp",
        "highlevel_libsamplerate_test_clip_media.",
        cl1.media_reference.?.signal_reference.signal_generator,
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
    var tl = try otio.Timeline.init(allocator);
    tl.name = try allocator.dupe(u8, "Example Timeline");
    tl.discrete_info.presentation = .{
        // matches the media rate
        .sample_rate_hz = 48000,
        .start_index = 86400,
    };

    defer tl.recursively_deinit();
    const tl_ptr = otio.ComposedValueRef{
        .timeline_ptr = &tl 
    };

    // track
    var tr = otio.Track.init(allocator);
    tr.name = try allocator.dupe(u8, "Example Parent Track");

    // clips
    const cl1 = otio.Clip {
        .name = try allocator.dupe(
            u8,
            "Spaghetti.mov",
        ),
        .media_temporal_bounds = .{
            .start = 1,
            .end = 6,
        },
        .discrete_info = .{
            .media = .{
                .sample_rate_hz = 48000,
                .start_index = 0,
            },
        },
        .media_reference = .{
            .signal_reference = .{
                .sample_index_generator = .{
                    .sample_rate_hz = 48000, 
                },
                .signal_generator = .{
                    .signal = .sine,
                    .duration_s = 6.0,
                    .frequency_hz = 200,
                },
                .interpolating = false,
            },
        },
    };
    defer cl1.destroy(allocator);
    const cl_ptr = otio.ComposedValueRef.init(&cl1);

    const warp = otio.Warp{
        .child = cl_ptr,
        .transform = try topology.Topology.init_affine(
            allocator,
            .{
                .input_to_output_xform = .{
                    .offset = -1,
                    .scale = 2,
                },
            }
        )
    };
    defer warp.transform.deinit(allocator);

    // new for this test - add in an warp on the clip
    try tr.append(warp);

    const tr_ptr = try tl.tracks.append_fetch_ref(tr);

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
        try cl_ptr.clip_ptr.media_reference.?.signal_reference.rasterized(
            allocator,
        )
    );
    defer media.deinit();
    try std.testing.expect(media.buffer.len > 0);

    // write the input file
    try media.write_file_prefix(
        allocator,
        "/var/tmp",
        "highlevel_libsamplerate_test_clip_media.",
        cl1.media_reference.?.signal_reference.signal_generator,
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

    // because the warp is scaling the presentation space by 2, the
    // presentation space should have half the peak to peak of the media
    // @TODO? ^ Nick is this correct?

    try std.testing.expectEqual(input_p2p / 2, result_p2p);

    try result.write_file_prefix(
        allocator, 
        "/var/tmp/",
        "highlevel_libsamplerate_test_track_presentation.retimed.",
        null,
 
    );

    try std.testing.expect(result.buffer.len > 0);

    // check the actual indices

    {
        const start = (
            tr_pres_to_cl_media_po.src_to_dst_topo.input_bounds().start
        );

        const result_buf = (
            try tr_pres_to_cl_media_po.project_range_cd(
                allocator,
                .{
                    .start = start,
                    .end = start + 2.0/48000.0,
                },
            )
        );
        defer allocator.free(result_buf);

        try std.testing.expectEqualSlices(
            usize, 
            &.{ 48000, 48002, },
            result_buf,
        );
    }
}

test "libsamplerate w/ high level test.retime.non_interpolating_reverse"
{
    const allocator = std.testing.allocator;

    // top level timeline
    var tl = try otio.Timeline.init(allocator);
    tl.name = try allocator.dupe(u8, "Example Timeline");
    tl.discrete_info.presentation = .{
        // matches the media rate
        .sample_rate_hz = 48000,
        .start_index = 86400,
    };

    defer tl.recursively_deinit();
    const tl_ptr = otio.ComposedValueRef{
        .timeline_ptr = &tl 
    };

    // track
    var tr = otio.Track.init(allocator);
    tr.name = try allocator.dupe(u8, "Example Parent Track");

    // clips
    const cl1 = otio.Clip {
        .name = try allocator.dupe(
            u8,
            "Spaghetti.mov",
        ),
        .media_temporal_bounds = .{
            .start = 1,
            .end = 6,
        },
        .discrete_info = .{
            .media = .{
                .sample_rate_hz = 48000,
                .start_index = 0,
            },
        },
        .media_reference = .{
            .signal_reference = .{
                .sample_index_generator = .{
                    .sample_rate_hz = 48000, 
                },
                .signal_generator = .{
                    .signal = .sine,
                    .duration_s = 6.0,
                    .frequency_hz = 200,
                },
                .interpolating = true,
            },
        },
    };
    defer cl1.destroy(allocator);
    const cl_ptr = otio.ComposedValueRef.init(&cl1);

    // new for this test - add in an warp on the clip
    const wp: otio.Warp = .{
        .child = cl_ptr,
        .transform = try topology.Topology.init_from_linear_monotonic(
            allocator,
            .{
                .knots = &.{
                    .{ .in = 0, .out = 6 },
                    .{ .in = 6, .out = 0 },   
                },
            },
        )
    };
    defer wp.transform.deinit(allocator);
    try tr.append(wp);

    const tr_ptr = try tl.tracks.append_fetch_ref(tr);

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

    {
        const start = (
            tr_pres_to_cl_media_po.src_to_dst_topo.input_bounds().start
        );

        const start_frame_in_destination_d = (
            try tr_pres_to_cl_media_po.project_instantaneous_cd(start)
        );

        // 6 second signal at 48000 that starts 1 second in = 
        // [48000, 288000) -> [288000, 48000)
        try std.testing.expectEqual(
            288000,
            start_frame_in_destination_d
        );

        const result_buf = (
            try tr_pres_to_cl_media_po.project_range_cd(
                allocator,
                .{
                    .start = start,
                    .end = start + 4.0/48000.0,
                },
            )
        );
        defer allocator.free(result_buf);

        try std.testing.expect(result_buf.len > 0);

        try std.testing.expectEqualSlices(
            usize, 
            &.{ 288000, 287999, 287998, 287996,},
            result_buf,
        );
    }
}

test "timeline w/ warp that holds the tenth frame"
{
    const allocator = std.testing.allocator;

    // top level timeline
    var tl = try otio.Timeline.init(allocator);
    tl.name = try allocator.dupe(u8, "Example Timeline");
    tl.discrete_info.presentation = .{
        // matches the media rate
        .sample_rate_hz = 24,
        .start_index = 0,
    };

    defer tl.recursively_deinit();
    const tl_ptr = otio.ComposedValueRef{
        .timeline_ptr = &tl 
    };

    // track
    var tr = otio.Track.init(allocator);
    tr.name = try allocator.dupe(u8, "Example Parent Track");

    // clips
    const cl1 = otio.Clip {
        .name = try allocator.dupe(
            u8,
            "Spaghetti.mov",
        ),
        .media_temporal_bounds = .{
            .start = 1,
            .end = 6,
        },
        .discrete_info = .{
            .media = .{
                .sample_rate_hz = 24,
                .start_index = 0,
            },
        },
        .media_reference = .{
            .signal_reference = .{
                .sample_index_generator = .{
                    .sample_rate_hz = 24, 
                },
                .signal_generator = .{ 
                    .signal = .sine,
                    .duration_s = 6.0,
                    .frequency_hz = 24,
                },
                .interpolating = true,
            },
        },
    };
    defer cl1.destroy(allocator);
    const cl_ptr = otio.ComposedValueRef.init(&cl1);

    // new for this test - add in an warp on the clip, which holds the frame
    const wp = otio.Warp {
        .child = cl_ptr,
        .transform = try topology.Topology.init_from_linear_monotonic(
            allocator,
            .{
                .knots = &.{
                    .{ .in = 0, .out = 10.0/24.0,},
                    .{ .in = 5, .out = 10.0/24.0,},
                },
            },
        )
    };
    defer wp.transform.deinit(allocator);
    try tr.append(wp);

    const tr_ptr = try tl.tracks.append_fetch_ref(tr);

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

    try std.testing.expect(std.math.isNan(w_ib.start) == false);
    try std.testing.expect(std.math.isNan(w_ib.end) == false);

    try std.testing.expect(std.math.isNan(w_ob.start) == false);
    try std.testing.expect(std.math.isNan(w_ob.end) == false);

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
                    .start = 0,
                    .end =  4.0/24.0,
                },
            )
        );
        defer allocator.free(result_buf);

        try std.testing.expectEqualSlices(
            usize, 
            // 34 because of the 1 second start time in the destination
            &.{ 34, 34, 34, 34, },
            result_buf,
        );
    }
}
