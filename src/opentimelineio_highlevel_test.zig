//! Demonstration of new features in this lib via unit tests

const std = @import("std");
const otio = @import("opentimelineio.zig");
const time_topology = @import("time_topology");
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
    const tl_ptr = otio.ItemPtr{
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
            .start_seconds = 1,
            .end_seconds = 3 
        },
        .discrete_info = .{
            .media = .{
                .sample_rate_hz = 24,
                .start_index = 10,
            },
        },
    };
    try tr.append(.{ .clip = cl1 });

    // gap
    const gp = otio.Gap{
        .duration_seconds = 1,
    };
    try tr.append(.{ .gap = gp });

    // clip
    const cl2 = otio.Clip {
        .name = try allocator.dupe(
            u8,
            "Taco.mov"
        ),
        .media_temporal_bounds = .{
            .start_seconds = 10,
            .end_seconds = 11, 
        },
        .discrete_info = .{
            .media = .{
                .sample_rate_hz = 30,
                .start_index = 10,
            },
        },
    };
    try tr.append(.{ .clip = cl2 });

    try tl.tracks.children.append(.{ .track = tr });

    // build some pointers into the structure
    const tr_ptr = tl.tracks.child_ptr_from_index(0);
    const cl2_ptr = tr_ptr.track_ptr.child_ptr_from_index(2);

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
        try proj_map.source.item.discrete_info_for_space(.presentation)
    );

    if (PRINT_DEMO_OUTPUT) 
    {
        std.debug.print(
            "Media Frames Needed to Render '{s}'\n",
            .{
                tr.name orelse "pasta"
            }
        );
        std.debug.print(
            "  Discrete Info:\n    sampling rate: {d}\n    start index: {d}\n",
            .{
                src_discrete_info.?.sample_rate_hz,
                src_discrete_info.?.start_index,
            },
        );
        std.debug.print(
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
            std.debug.print(
                "  presentation space:\n    interval: [{d}, {d})\n",
                .{ p0, p1 },
            );
        }
        for (ops)
            |op|
        {
            if (PRINT_DEMO_OUTPUT)
            {
                std.debug.print(
                    "    Topology\n      presentation:  {any}\n"
                    ++ "      media: {any}\n",
                    .{
                        op.src_to_dst_topo.input_bounds(),
                        op.src_to_dst_topo.output_bounds(),
                    },
                    );
            }
            const di = (
                try op.destination.item.discrete_info_for_space(.media)
            ).?;
            if (PRINT_DEMO_OUTPUT)
            {
                std.debug.print(
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
                    .start_seconds = p0,
                    .end_seconds = p1 
                }
            );
            defer allocator.free(dest_frames);

            if (PRINT_DEMO_OUTPUT)
            {
                std.debug.print(
                    "    Source: \n      target: {?s}\n"
                    ++ "      frames: {any}\n",
                    .{ 
                        op.destination.item.clip_ptr.name orelse "pasta",
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
    const tl_ptr = otio.ItemPtr{
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
            .start_seconds = 1,
            .end_seconds = 6,
        },
        .discrete_info = .{
            .media = .{
                .sample_rate_hz = 48000,
                .start_index = 0,
            },
        },
        .media_reference = .{
            .signal_generator = .{
                .sample_rate_hz = 48000,
                .signal = .sine,
                .signal_duration_s = 6.0,
                .signal_frequency_hz = 200,
            },
        }
    };
    try std.testing.expect(
        cl1.media_temporal_bounds.?.start_seconds < 
        cl1.media_temporal_bounds.?.end_seconds
    );
    try std.testing.expect(
        (try cl1.bounds_of(allocator, .media)).end_seconds != 0,
    );
    try std.testing.expect(
        (try cl1.bounds_of(allocator, .media)).start_seconds < 
        (try cl1.bounds_of(allocator, .media)).end_seconds
    );

    try tr.append(.{ .clip = cl1 });
    try tl.tracks.children.append(.{ .track = tr });

    // build some pointers into the structure
    const tr_ptr = tl.tracks.child_ptr_from_index(0);
    const cl_ptr = tr_ptr.track_ptr.child_ptr_from_index(0);

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

    try std.testing.expectEqual(
        .affine,
        std.meta.activeTag(tr_pres_to_cl_media_po.src_to_dst_topo),
    );

    try std.testing.expect(
        tr_pres_to_cl_media_po.src_to_dst_topo.affine.bounds.end_seconds > 0,
    );

    try std.testing.expect(
        cl1.media_reference.?.signal_generator.signal_duration_s > 0
    );

    // synthesize media
    const media = (
        try cl_ptr.clip_ptr.media_reference.?.signal_generator.rasterized(
            allocator,
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
        cl1.media_reference.?.signal_generator,
    );

    const tr_pres_to_cl_media_lin = (
        try tr_pres_to_cl_media_po.src_to_dst_topo.linearized(allocator)
    );
    defer tr_pres_to_cl_media_lin.deinit(allocator);
    const tr_pres_to_cl_media_crv = (
        tr_pres_to_cl_media_lin.linear_curve.curve
    );

    // goal
    const result = try sampling.retimed_linear_curve(
        allocator,
        media,
        tr_pres_to_cl_media_crv,
        false,
        tl.discrete_info.presentation.?,
    );
    defer result.deinit();

    // result should match the timeline's discrete info
    try std.testing.expectEqual(
        tl.discrete_info.presentation.?.sample_rate_hz,
        result.sample_rate_hz
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
    const tl_ptr = otio.ItemPtr{
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
            .start_seconds = 1,
            .end_seconds = 6,
        },
        .discrete_info = .{
            .media = .{
                .sample_rate_hz = 48000,
                .start_index = 0,
            },
        },
        .media_reference = .{
            .signal_generator = .{
                .sample_rate_hz = 48000,
                .signal = .sine,
                .signal_duration_s = 6.0,
                .signal_frequency_hz = 200,
            },
        },
    };
    defer cl1.destroy(allocator);
    const cl_ptr : otio.ItemPtr = .{ .clip_ptr = &cl1 };

    // new for this test - add in an warp on the clip
    const wp: otio.Warp = .{
        .child = cl_ptr,
        .transform = time_topology.TimeTopology.init_affine(
            .{
                .transform = .{
                    .offset_seconds = -1,
                    .scale = 2,
                },
            },
        )
    };
    try tr.append(.{ .warp = wp });
    try tl.tracks.children.append(.{ .track = tr });

    // build some pointers into the structure
    const tr_ptr = tl.tracks.child_ptr_from_index(0);

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

    // synthesize media
    const media = (
        try cl_ptr.clip_ptr.media_reference.?.signal_generator.rasterized(
            allocator,
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
        cl1.media_reference.?.signal_generator,
    );

    const tr_pres_to_cl_media_lin = (
        try tr_pres_to_cl_media_po.src_to_dst_topo.linearized(allocator)
    );
    defer tr_pres_to_cl_media_lin.deinit(allocator);
    const tr_pres_to_cl_media_crv = (
        tr_pres_to_cl_media_lin.linear_curve.curve
    );

    // goal
    const result = try sampling.retimed_linear_curve(
        allocator,
        media,
        tr_pres_to_cl_media_crv,
        false,
        tl.discrete_info.presentation.?,
    );
    defer result.deinit();

    // result should match the timeline's discrete info
    try std.testing.expectEqual(
        tl.discrete_info.presentation.?.sample_rate_hz,
        result.sample_rate_hz
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
    const tl_ptr = otio.ItemPtr{
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
            .start_seconds = 1,
            .end_seconds = 6,
        },
        .discrete_info = .{
            .media = .{
                .sample_rate_hz = 48000,
                .start_index = 0,
            },
        },
        .media_reference = .{
            .signal_generator = .{
                .sample_rate_hz = 48000,
                .signal = .sine,
                .signal_duration_s = 6.0,
                .signal_frequency_hz = 200,
            },
        },
    };
    defer cl1.destroy(allocator);
    const cl_ptr : otio.ItemPtr = .{ .clip_ptr = &cl1 };

    // new for this test - add in an warp on the clip
    const wp: otio.Warp = .{
        .child = cl_ptr,
        .transform = time_topology.TimeTopology.init_affine(
            .{
                .transform = .{
                    .offset_seconds = -1,
                    .scale = 2,
                },
            },
        )
    };
    try tr.append(.{ .warp = wp });

    try tl.tracks.children.append(.{ .track = tr });

    // build some pointers into the structure
    const tr_ptr = tl.tracks.child_ptr_from_index(0);

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

    // synthesize media
    const media = (
        try cl_ptr.clip_ptr.media_reference.?.signal_generator.rasterized(
            allocator,
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
        cl1.media_reference.?.signal_generator,
    );

    const tr_pres_to_cl_media_lin = (
        try tr_pres_to_cl_media_po.src_to_dst_topo.linearized(allocator)
    );
    defer tr_pres_to_cl_media_lin.deinit(allocator);
    const tr_pres_to_cl_media_crv = (
        tr_pres_to_cl_media_lin.linear_curve.curve
    );

    // goal
    const result = try sampling.retimed_linear_curve(
        allocator,
        media,
        tr_pres_to_cl_media_crv,
        false,
        tl.discrete_info.presentation.?,
    );
    defer result.deinit();

    // result should match the timeline's discrete info
    try std.testing.expectEqual(
        tl.discrete_info.presentation.?.sample_rate_hz,
        result.sample_rate_hz
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
            tr_pres_to_cl_media_po.src_to_dst_topo.input_bounds().start_seconds
        );

        const result_buf = (
            try tr_pres_to_cl_media_po.project_range_cd(
                allocator,
                .{
                    .start_seconds = start,
                    .end_seconds = start + 2.0/48000.0,
                },
            )
        );
        defer allocator.free(result_buf);

        try std.testing.expectEqualSlices(
            usize, 
            &.{ 48000, 48001, 48002, 48003, },
            result_buf,
        );
    }
}
