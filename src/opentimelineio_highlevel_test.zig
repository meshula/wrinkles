const std = @import("std");
const otio = @import("opentimelineio.zig");

test "otio: high level procedural test [clip][   gap    ][clip]"
{
    var tl = try otio.Timeline.init(std.testing.allocator);
    tl.name = try std.testing.allocator.dupe(u8, "Example Timeline");
    tl.discrete_info.presentation = .{
        .sample_rate_hz = 24,
        .start_index = 86400,
    };

    defer tl.recursively_deinit();
    const tl_ptr = otio.ItemPtr{ .timeline_ptr = &tl };

    var tr = otio.Track.init(std.testing.allocator);
    tr.name = try std.testing.allocator.dupe(u8, "Example Parent Track");

    const cl1 = otio.Clip {
        .name = try std.testing.allocator.dupe(u8, "Spaghetti.mov"),
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

    const gp = otio.Gap{
        .duration_seconds = 1,
    };
    try tr.append(.{ .gap = gp });

    const cl2 = otio.Clip {
        .name = try std.testing.allocator.dupe(u8, "Taco.mov"),
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

    const topo_map = try otio.build_topological_map(
        std.testing.allocator,
        tl_ptr
    );
    defer topo_map.deinit();

    const proj_map = try otio.projection_map_to_media_from(
        std.testing.allocator,
        topo_map, 
        try tl_ptr.space(.presentation)
    );
    defer proj_map.deinit();

    std.debug.print(
        "Media Frames Needed to Render '{s}'\n",
        .{
            tr.name orelse "pasta"
        }
    );
    const src_discrete_info = (
        try proj_map.source.item.discrete_info_for_space(.presentation)
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

    for (
        proj_map.end_points[0..(proj_map.end_points.len-1)],
        proj_map.end_points[1..],
        proj_map.operators,
    )
        |p0, p1, ops|
    {
        std.debug.print(
            "  presentation space:\n    interval: [{d}, {d})\n",
            .{ p0, p1 },
        );
        for (ops)
            |op|
        {
            std.debug.print(
                "    Topology\n      presentation:  {any}\n      media: {any}\n",
                .{
                    op.src_to_dst_topo.input_bounds(),
                    op.src_to_dst_topo.output_bounds(),
                },
            );
            std.debug.print(
                "    Discrete Info:\n      sampling rate: {d}\n      start index: {d}\n",
                .{
                    op.destination.item.clip_ptr.discrete_info.media.?.sample_rate_hz,
                    op.destination.item.clip_ptr.discrete_info.media.?.start_index,
                },
            );

            const dest_frames = try op.project_range_cd(
                std.testing.allocator,
                .{ .start_seconds = p0, .end_seconds = p1 }
            );
            defer std.testing.allocator.free(dest_frames);
            std.debug.print(
                "    Source: \n      target: {?s}\n      frames: {any}\n",
                .{ 
                    op.destination.item.clip_ptr.name orelse "pasta",
                    dest_frames,
                }
            );
        }
    }
}
