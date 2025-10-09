//! Slim OpenTimelineIO Reimplementation for testing high level API
//! Uses the rest of the wrinkles library to implement high level functions
//! that might eventually get ported to 'real' OTIO.
//!

const std = @import("std");

const build_options = @import("build_options");

const opentime = @import("opentime");
const curve = @import("curve");
const topology_m = @import("topology");
const treecode = @import("treecode");
const sampling = @import("sampling");

const test_data_m = @import("test_structures.zig");
const schema = @import("schema.zig");
const temporal_hierarchy = @import("temporal_hierarchy.zig");
const references = @import("references.zig");
const projections = @import("projection.zig");

/// annotate the graph algorithms
// const GRAPH_CONSTRUCTION_TRACE_MESSAGES = true;
const GRAPH_CONSTRUCTION_TRACE_MESSAGES = (
    build_options.debug_graph_construction_trace_messages
);

test "transform: track with two clips"
{
    const allocator = std.testing.allocator;

    var cl1 = schema.Clip {
        .bounds_s = test_data_m.T_INT_1_TO_9,
    };
    var cl2 = schema.Clip {
        .bounds_s = test_data_m.T_INT_1_TO_4,
    };
    const cl2_ref = references.ComposedValueRef.init(&cl2);

    var tr_children = [_]references.ComposedValueRef{
        references.ComposedValueRef.init(&cl1),
        cl2_ref 
    };
    var tr: schema.Track = .{
        .children = &tr_children,
    };
    const tr_ptr = references.ComposedValueRef.init(&tr);

    const map = try temporal_hierarchy.build_temporal_map(
        allocator,
        tr_ptr,
    );
    defer map.deinit(allocator);

    const track_presentation_space = try tr_ptr.space(.presentation);

    {
        const child_code = (
            try treecode.Treecode.init_word(allocator, 0b1110)
        );
        defer child_code.deinit(allocator);

        const child_space = map.get_space(child_code).?;

        const xform = try tr.transform_to_child(
            allocator,
            child_space
        );
        defer xform.deinit(allocator);

        const b = xform.input_bounds();

        try opentime.expectOrdinateEqual(
            8,
            b.start,
        );
    }

    {
        const xform = try topology_m.Topology.init_affine(
            allocator,
            .{
                .input_bounds_val = .{
                    .start = opentime.Ordinate.init(8),
                },
                .input_to_output_xform = .{
                    .offset = opentime.Ordinate.init(-8),
                },
            }
        );
        defer xform.deinit(allocator);
        const po = try temporal_hierarchy.build_projection_operator(
            allocator,
            map,
            .{
                .source = try cl2_ref.space(.presentation),
                .destination = try cl2_ref.space(.media),
            }
        );
        defer po.deinit(allocator);
        const result = try topology_m.join(
            allocator,
            .{
                .a2b = xform,
                .b2c = po.src_to_dst_topo,
            },
        );
        defer result.deinit(allocator);
        try std.testing.expect(
            result.mappings.len > 0
        );
    }

    {
        const xform = try temporal_hierarchy.build_projection_operator(
            allocator,
            map,
            .{
                .source = track_presentation_space,
                .destination = try cl2_ref.space(.media),
            }
        );
        defer xform.deinit(allocator);
        const b = xform.src_to_dst_topo.input_bounds();

        try std.testing.expect(xform.src_to_dst_topo.mappings.len > 0);

        const cl1_range = try cl1.bounds_of(
            allocator, 
            .media,
        );
        const cl2_range = try cl2.bounds_of(
            allocator,
            .media,
        );

        try std.testing.expectEqualSlices(
            opentime.Ordinate,
            &.{
                cl1_range.duration(),
                cl1_range.duration().add(cl2_range.duration())
            },
            &.{b.start, b.end},
        );
    }
}

test "ProjectionOperatorMap: track with two clips"
{
    const allocator = std.testing.allocator;

    var clips = [_]schema.Clip{
        .{
            .bounds_s = test_data_m.T_INT_1_TO_9,
        },
        .{
            .bounds_s = test_data_m.T_INT_1_TO_9,
        },
    };
    const cl_ptr = references.ComposedValueRef.init(&clips[1]);

    var tr_children = [_]references.ComposedValueRef{
        references.ComposedValueRef.init(&clips[0]),
        cl_ptr,  
    };
    var tr: schema.Track = .{ .children = &tr_children };
    const tr_ptr = references.ComposedValueRef.init(&tr);

    /////

    const map = try temporal_hierarchy.build_temporal_map(
        allocator,
        tr_ptr,
    );
    defer map.deinit(allocator);

    /////

    const source_space = try tr_ptr.space(.presentation);

    const p_o_map = (
        try projections.projection_map_to_media_from(
            allocator,
            map,
            source_space,
        )
    );
    defer p_o_map.deinit(allocator);

    /////

    try std.testing.expectEqualSlices(
        opentime.Ordinate,
        (&test_data_m.T_ORD_ARR_0_8_16_21)[0..3],
        p_o_map.end_points,
    );
    try std.testing.expectEqual(2, p_o_map.operators.len);

    const known_presentation_to_media = (
        try temporal_hierarchy.build_projection_operator(
            allocator,
            map,
            .{
                .source = try tr_ptr.space(.presentation),
                .destination = try cl_ptr.space(.media),
            },
        )
    );
    defer known_presentation_to_media.deinit(allocator);

    const known_input_bounds = (
        known_presentation_to_media.src_to_dst_topo.input_bounds()
    );

    const guess_presentation_to_media = p_o_map.operators[1][0];
    const guess_input_bounds = (
        guess_presentation_to_media.src_to_dst_topo.input_bounds()
    );

    // topology input bounds match
    try opentime.expectOrdinateEqual(
        known_input_bounds.start,
        guess_input_bounds.start,
    );
    try opentime.expectOrdinateEqual(
        known_input_bounds.end,
        guess_input_bounds.end,
    );

    // end points match topology
    try opentime.expectOrdinateEqual(
        8.0,
        guess_input_bounds.start,
    );
    try opentime.expectOrdinateEqual(
        16,
        guess_input_bounds.end,
    );
}

test "ProjectionOperatorMap: track [c1][gap][c2]"
{
    const allocator = std.testing.allocator;

    var cl = schema.Clip {
        .bounds_s = test_data_m.T_INT_1_TO_9,
    };
    var gp = schema.Gap{
        .duration_seconds = opentime.Ordinate.init(5),
    };
    var cl2 = cl;
    const cl_ptr = references.ComposedValueRef.init(&cl2);

    var tr_children = [_]references.ComposedValueRef{ 
        references.ComposedValueRef.init(&cl),
        references.ComposedValueRef.init(&gp),
        cl_ptr,
    };
    var tr: schema.Track = .{ .children = &tr_children, };
    const tr_ptr = references.ComposedValueRef.init(&tr);

    const map = try temporal_hierarchy.build_temporal_map(
        allocator,
        tr_ptr,
    );
    defer map.deinit(allocator);

    const source_space = try tr_ptr.space(.presentation);

    const p_o_map = (
        try projections.projection_map_to_media_from(
            allocator,
            map,
            source_space,
        )
    );

    defer p_o_map.deinit(allocator);

    try std.testing.expectEqualSlices(
        opentime.Ordinate,
        &test_data_m.T_ORD_ARR_0_8_13_21,
        p_o_map.end_points,
    );
    try std.testing.expectEqual(3, p_o_map.operators.len);

    const known_presentation_to_media = (
        try temporal_hierarchy.build_projection_operator(
            allocator,
            map,
            .{
                .source = try tr_ptr.space(.presentation),
                .destination = try cl_ptr.space(.media),
            },
        )
    );
    defer known_presentation_to_media.deinit(allocator);

    const known_input_bounds = (
        known_presentation_to_media.src_to_dst_topo.input_bounds()
    );

    const guess_presentation_to_media = p_o_map.operators[2][0];
    const guess_input_bounds = (
        guess_presentation_to_media.src_to_dst_topo.input_bounds()
    );

    // topology input bounds match
    try opentime.expectOrdinateEqual(
        known_input_bounds.start,
        guess_input_bounds.start,
    );
    try opentime.expectOrdinateEqual(
        known_input_bounds.end,
        guess_input_bounds.end,
    );

    // end points match topology
    try opentime.expectOrdinateEqual(
        13,
        guess_input_bounds.start,
    );
    try opentime.expectOrdinateEqual(
        21,
        guess_input_bounds.end,
    );
}

test "clip topology construction" 
{
    const allocator = std.testing.allocator;

    var cl = schema.Clip {
        .bounds_s = test_data_m.T_INT_1_TO_9,
    };

    const topo = try cl.topology(allocator);
    defer topo.deinit(allocator);

    try opentime.expectOrdinateEqual(
        test_data_m.T_INT_1_TO_9.start,
        topo.input_bounds().start,
    );

    try opentime.expectOrdinateEqual(
        test_data_m.T_INT_1_TO_9.end,
        topo.input_bounds().end,
    );
}

test "track topology construction" 
{
    const allocator = std.testing.allocator;

    var cl = schema.Clip {
        .bounds_s = test_data_m.T_INT_1_TO_9, 
    };

    var tr_children = [_]references.ComposedValueRef{
        references.ComposedValueRef.init(&cl)
    };
    var tr: schema.Track = .{
        .children = &tr_children,
    };

    const topo = try tr.topology(allocator);
    defer topo.deinit(allocator);

    try opentime.expectOrdinateEqual(
        test_data_m.T_INT_1_TO_9.start,
        topo.input_bounds().start,
    );

    try opentime.expectOrdinateEqual(
        test_data_m.T_INT_1_TO_9.end,
        topo.input_bounds().end,
    );
}

test "path_code: graph test" 
{
    const allocator = std.testing.allocator;

    var clips: [11]schema.Clip = undefined;
    var clip_ptrs: [11]references.ComposedValueRef = undefined;

    for (&clips, &clip_ptrs)
        |*cl, *cl_p|
    {
        cl.* = schema.Clip {
            .bounds_s = test_data_m.T_INT_1_TO_9,
        };

        cl_p.* = references.ComposedValueRef.init(cl);
    }
    var tr: schema.Track = .{
        .children = &clip_ptrs,
    };
    const tr_ref = references.ComposedValueRef.init(&tr);

    try std.testing.expectEqual(11, tr.children.len);

    const map = try temporal_hierarchy.build_temporal_map(
        allocator,
        tr_ref,
    );
    defer map.deinit(allocator);

    try std.testing.expectEqual(
        tr_ref.space(.presentation),
        map.root(),
    );

    try map.write_dot_graph(
        allocator,
        "/var/tmp/graph_test_output.dot",
        "graph_test",
        .{},
    );

    // should be the same length
    try std.testing.expectEqual(
        map.map_space_to_index.count(),
        map.map_code_to_index.count(),
    );
    try std.testing.expectEqual(
        35,
        map.map_space_to_index.count()
    );

    try map.write_dot_graph(
        allocator,
        "/var/tmp/current.dot",
        "current",
        .{},
    );

    const TestData = struct {
        ind: usize,
        expect: treecode.TreecodeWord, 
    };

    const test_data = [_]TestData{
        .{.ind = 0, .expect= 0b1010 },
        .{.ind = 1, .expect= 0b10110 },
        .{.ind = 2, .expect= 0b101110 },
    };
    for (0.., test_data)
        |t_i, t| 
    {
        const space = (
            try tr.children[t.ind].space(references.SpaceLabel.presentation)
        );
        const result = (
            map.get_code(space) 
            orelse return error.NoSpaceForCode
        );

        errdefer std.log.err(
            "\n[iteration: {d}] index: {d} expected: {b} result: {f} \n",
            .{t_i, t.ind, t.expect, result}
        );

        const expect = try treecode.Treecode.init_word(
            allocator,
            t.expect,
        );
        defer expect.deinit(allocator);

        try std.testing.expect(expect.eql(result));
    }
}

test "schema.Track with clip with identity transform projection" 
{
    const allocator = std.testing.allocator;

    const range = test_data_m.T_INT_1_TO_9;

    const cl_template = schema.Clip{
        .bounds_s = range
    };

    var clips: [11]schema.Clip = undefined;
    var refs: [11]references.ComposedValueRef = undefined;

    for (&clips, &refs)
        |*cl_p, *ref|
    {
        cl_p.* = cl_template;
        ref.* = references.ComposedValueRef.init(cl_p);
    }
    const cl_ref = refs[0];

    var tr: schema.Track = .{ .children = &refs };
    const tr_ref = references.ComposedValueRef.init(&tr);

    const map = try temporal_hierarchy.build_temporal_map(
        allocator,
        tr_ref,
    );
    defer map.deinit(allocator);

    try std.testing.expectEqual(
        11,
        tr_ref.track.children.len
    );

    const track_to_clip = try temporal_hierarchy.build_projection_operator(
        allocator,
        map,
        .{
            .source = try tr_ref.space(references.SpaceLabel.presentation),
            .destination =  try cl_ref.space(references.SpaceLabel.media)
        }
    );
    defer track_to_clip.deinit(std.testing.allocator);

    // check the bounds
    try opentime.expectOrdinateEqual(
        0,
        track_to_clip.src_to_dst_topo.input_bounds().start,
    );

    try opentime.expectOrdinateEqual(
        range.end.sub(range.start),
        track_to_clip.src_to_dst_topo.input_bounds().end,
    );

    // check the projection
    try opentime.expectOrdinateEqual(
        4,
        try track_to_clip.project_instantaneous_cc(
            opentime.Ordinate.init(3)
        ).ordinate(),
    );
}


test "TemporalMap: schema.Track with clip with identity transform" 
{
    const allocator = std.testing.allocator;

    var cl = schema.Clip{
        .bounds_s = test_data_m.T_INT_0_TO_2,
    };
    const cl_ref = references.ComposedValueRef.init(&cl);

    var tr_children = [_]references.ComposedValueRef{ cl_ref, };
    var tr: schema.Track = .{ .children = &tr_children };

    const root = references.ComposedValueRef.init(&tr);

    const map = try temporal_hierarchy.build_temporal_map(
        allocator,
        root,
    );
    defer map.deinit(allocator);

    try std.testing.expectEqual(5, map.map_code_to_index.count());
    try std.testing.expectEqual(5, map.map_space_to_index.count());

    try std.testing.expectEqual(root, map.root().ref);

    const maybe_root_code = map.get_code(map.root());
    try std.testing.expect(maybe_root_code != null);
    const root_code = maybe_root_code.?;

    // root object code
    {
        var tc = try treecode.Treecode.init(allocator);
        defer tc.deinit(allocator);
        try std.testing.expect(tc.eql(root_code));
        try std.testing.expectEqual(0, tc.code_length());
    }

    const maybe_clip_code = map.get_code(
        try cl_ref.space(references.SpaceLabel.media)
    );
    try std.testing.expect(maybe_clip_code != null);
    const clip_code = maybe_clip_code.?;

    // clip object code
    {
        var tc = try treecode.Treecode.init_word(
            allocator,
            0b10010
        );
        defer tc.deinit(allocator);
        errdefer opentime.dbg_print(@src(), 
            "\ntc: {f}, clip_code: {f}\n",
            .{
                tc,
                clip_code,
            },
            );
        try std.testing.expectEqual(4, tc.code_length());
        try std.testing.expect(tc.eql(clip_code));
    }

    try std.testing.expect(
        treecode.path_exists(clip_code, root_code)
    );

    const root_presentation_to_clip_media = (
        try temporal_hierarchy.build_projection_operator(
            allocator,
            map,
            .{
                .source = try root.space(references.SpaceLabel.presentation),
                .destination = try cl_ref.space(references.SpaceLabel.media)
            }
        )
    );
    defer root_presentation_to_clip_media.deinit(allocator);

    try std.testing.expectError(
        topology_m.mapping.Mapping.ProjectionError.OutOfBounds,
        root_presentation_to_clip_media.project_instantaneous_cc(
            opentime.Ordinate.init(3)
        ).ordinate()
    );

    try opentime.expectOrdinateEqual(
        1,
        try root_presentation_to_clip_media.project_instantaneous_cc(
            opentime.Ordinate.init(1)
        ).ordinate(),
    );
}

test "Projection: schema.Track with single clip with identity transform and bounds" 
{
    const allocator = std.testing.allocator;

    var cl = schema.Clip{
        .bounds_s = test_data_m.T_INT_0_TO_2,
    };
    const clip = references.ComposedValueRef.init(&cl);

    var tr_children = [_]references.ComposedValueRef{ clip, };
    var tr: schema.Track = .{ .children = &tr_children };
    const root = references.ComposedValueRef{ .track = &tr };

    const map = try temporal_hierarchy.build_temporal_map(
        allocator,
        root,
    );
    defer map.deinit(allocator);

    try std.testing.expectEqual(
        5,
        map.map_code_to_index.count()
    );
    try std.testing.expectEqual(
        5,
        map.map_space_to_index.count()
    );

    const root_presentation_to_clip_media = try temporal_hierarchy.build_projection_operator(
        allocator,
        map,
        .{ 
            .source = try root.space(references.SpaceLabel.presentation),
            .destination = try clip.space(references.SpaceLabel.media),
        }
    );
    defer root_presentation_to_clip_media.deinit(allocator);

    const expected_media_temporal_bounds = (
        cl.bounds_s orelse opentime.ContinuousInterval{}
    );

    const actual_media_temporal_bounds = (
        root_presentation_to_clip_media.src_to_dst_topo.input_bounds()
    );

    // cexpected_media_temporal_bounds
    try opentime.expectOrdinateEqual(
        expected_media_temporal_bounds.start,
        actual_media_temporal_bounds.start,
    );

    try opentime.expectOrdinateEqual(
        expected_media_temporal_bounds.end,
        actual_media_temporal_bounds.end,
    );

    try std.testing.expectError(
        topology_m.mapping.Mapping.ProjectionError.OutOfBounds,
        root_presentation_to_clip_media.project_instantaneous_cc(
            opentime.Ordinate.init(3)
        ).ordinate()
    );
}

test "Projection: schema.Track 3 bounded clips identity xform" 
{
    const allocator = std.testing.allocator;

    //
    //                                 0               3             6
    // track.presentation space       [---------------*-------------)
    // track.intrinsic space          [---------------*-------------)
    // child.clip presentation space  [--------)[-----*---)[-*------)
    //                                0        2 0    1   2 0       2 
    //

    // build timeline
    var clips: [3]schema.Clip = undefined;
    var refs: [3]references.ComposedValueRef = undefined;

    for (&clips, &refs)
        |*cl, *ref|
    {
        cl.* = schema.Clip {
            .bounds_s = test_data_m.T_INT_0_TO_2 
        };
        ref.* = references.ComposedValueRef.init(cl);
    }
    const cl2_ref = refs[2];

    var tr: schema.Track = .{
        .children = &refs,
    };
    const track_ptr = references.ComposedValueRef.init(&tr);

    // ----

    const map = try temporal_hierarchy.build_temporal_map(
        allocator,
        track_ptr,
    );
    defer map.deinit(allocator);

    // ---

    // check that the child transform is correctly built
    {
        const po = try temporal_hierarchy.build_projection_operator(
            allocator,
            map,
            .{
                .source = try track_ptr.space(.presentation),
                .destination = (
                    try cl2_ref.space(.media)
                ),
            }
        );
        defer po.deinit(std.testing.allocator);

        const b = po.src_to_dst_topo.input_bounds();

        try opentime.expectOrdinateEqual(
            4,
            b.start,
        );
        try opentime.expectOrdinateEqual(
            6,
            b.end,
        );
    }

    const po_map = try projections.projection_map_to_media_from(
        allocator,
        map,
        try track_ptr.space(.presentation),
    );
    defer po_map.deinit(allocator);

    try std.testing.expectEqual(
        3,
        po_map.operators.len,
    );

    // 1
    for (po_map.operators,
        &[_][2]opentime.Ordinate{ 
            .{ test_data_m.T_O_0, test_data_m.T_O_2 },
            .{ test_data_m.T_O_2, test_data_m.T_O_4 },
            .{ test_data_m.T_O_4, test_data_m.T_O_6 } 
        }
    )
        |ops, expected|
    {
        const b = (
            ops[0].src_to_dst_topo.input_bounds()
        );
        try std.testing.expectEqualSlices(
            opentime.Ordinate,
            &expected,
            &.{ b.start, b.end },
        );
    }

    try std.testing.expectEqualSlices(
        opentime.Ordinate,
        &.{
            test_data_m.T_O_0,
            test_data_m.T_O_2,
            test_data_m.T_O_4,
            test_data_m.T_O_6,
        },
        po_map.end_points,
    );

    const TestData = struct {
        index: usize,
        track_ord: opentime.Ordinate.BaseType,
        expected_ord: opentime.Ordinate.BaseType,
        err: bool
    };

    const tests = [_]TestData{
        .{ .index = 1, .track_ord = 3, .expected_ord = 1, .err = false},
        .{ .index = 0, .track_ord = 1, .expected_ord = 1, .err = false },
        .{ .index = 2, .track_ord = 5, .expected_ord = 1, .err = false },
        .{ .index = 0, .track_ord = 7, .expected_ord = 1, .err = true },
    };

    for (tests, 0..) 
        |t, t_i| 
    {
        const child = tr.children[t.index];

        const tr_presentation_to_clip_media = try temporal_hierarchy.build_projection_operator(
        allocator,
        map,
            .{
                .source = try track_ptr.space(references.SpaceLabel.presentation),
                .destination = try child.space(references.SpaceLabel.media),
            }
        );
        defer tr_presentation_to_clip_media.deinit(allocator);

        errdefer std.log.err(
            "[{d}] index: {d} track ordinate: {d} expected: {d} error: {any}\n",
            .{t_i, t.index, t.track_ord, t.expected_ord, t.err}
        );
        if (t.err)
        {
            try std.testing.expectError(
                opentime.ProjectionResult.Errors.OutOfBounds,
                tr_presentation_to_clip_media.project_instantaneous_cc(
                    opentime.Ordinate.init(t.track_ord)
                ).ordinate()
            );
        }
        else{
            const result = (
                try tr_presentation_to_clip_media.project_instantaneous_cc(
                    opentime.Ordinate.init(t.track_ord)
                ).ordinate()
            );

            try opentime.expectOrdinateEqual(
                t.expected_ord,
                result,
            );
        }
    }

    const clip = tr.children[0];

    const root_presentation_to_clip_media = try temporal_hierarchy.build_projection_operator(
        allocator,
        map,
        .{ 
            .source = try track_ptr.space(references.SpaceLabel.presentation),
            .destination = try clip.space(references.SpaceLabel.media),
        }
    );
    defer root_presentation_to_clip_media.deinit(allocator);

    const expected_range = (
        tr.children[0].clip.bounds_s orelse opentime.ContinuousInterval{}
    );
    const actual_range = (
        root_presentation_to_clip_media.src_to_dst_topo.input_bounds()
    );

    // check the bounds
    try opentime.expectOrdinateEqual(
        expected_range.start,
        actual_range.start,
    );

    try opentime.expectOrdinateEqual(
        expected_range.end,
        actual_range.end,
    );

    try std.testing.expectError(
        opentime.ProjectionResult.Errors.OutOfBounds,
        root_presentation_to_clip_media.project_instantaneous_cc(
            opentime.Ordinate.init(3)
        ).ordinate(),
    );
}

test "Single schema.Clip bezier transform" 
{
    const allocator = std.testing.allocator;

    //
    // xform: s-curve read from sample curve file
    //        curves map from the presentation space to the intrinsic space for clips
    //
    //              0                             10
    // presentation       [-----------------------------)
    //                               _,-----------x
    // transform                   _/
    // (curve)                   ,/
    //              x-----------'
    // intrinsic    [-----------------------------)
    //              0                             10 (seconds)
    // media        100                          110 (seconds)
    //
    // the media space is defined by the source range
    //

    const base_curve = try curve.read_curve_json(
        "curves/scurve.curve.json",
        allocator,
    );
    defer base_curve.deinit(allocator);

    // this curve is [-0.5, 0.5), rescale it into test range
    const xform_curve = try curve.rescaled_curve(
        allocator,
        base_curve,
        //  the range of the clip for testing - rescale factors
        .{
            curve.ControlPoint.init(.{ .in = 0, .out = 0, }),
            curve.ControlPoint.init(.{ .in = 10, .out = 10, }),
        }
    );
    defer xform_curve.deinit(allocator);
    const curve_topo = try topology_m.Topology.init_bezier(
        allocator,
        xform_curve.segments,
    );
    defer curve_topo.deinit(allocator);

    // test the input space range
    const curve_bounds_input = curve_topo.input_bounds();
    try opentime.expectOrdinateEqual(
        0,
        curve_bounds_input.start,
    );
    try opentime.expectOrdinateEqual(
        10,
        curve_bounds_input.end,
    );

    // test the output space range (the media space of the clip)
    const curve_bounds_output = (
        xform_curve.extents_output()
    );
    try opentime.expectOrdinateEqual(
        0,
        curve_bounds_output.start,
    );
    try opentime.expectOrdinateEqual(
        10,
        curve_bounds_output.end,
    );

    try std.testing.expect(curve_topo.mappings.len > 0);

    const media_temporal_bounds:opentime.ContinuousInterval = .{
        .start = opentime.Ordinate.init(100),
        .end = opentime.Ordinate.init(110),
    };
    var cl = schema.Clip {
        .bounds_s = media_temporal_bounds,
    };
    const cl_ptr:references.ComposedValueRef = .{ .clip = &cl };

    var wp: schema.Warp = .{
        .child = cl_ptr,
        .transform = curve_topo,
    };

    const wp_ptr : references.ComposedValueRef = .{ .warp = &wp };

    const map = try temporal_hierarchy.build_temporal_map(
        allocator,
        wp_ptr,
    );
    defer map.deinit(allocator);

    // presentation->media (forward projection)
    {
        const clip_presentation_to_media_proj = (
            try temporal_hierarchy.build_projection_operator(
                allocator,
                map,
                .{
                    .source =  try wp_ptr.space(references.SpaceLabel.presentation),
                    .destination = try cl_ptr.space(references.SpaceLabel.media),
                }
            )
        );
        defer clip_presentation_to_media_proj.deinit(allocator);

        // note that the clips presentation space is the curve's input space
        const input_bounds = (
            clip_presentation_to_media_proj.src_to_dst_topo.input_bounds()
        );
        try opentime.expectOrdinateEqual(
            curve_bounds_output.start, 
            input_bounds.start,
        );
        try opentime.expectOrdinateEqual(
            curve_bounds_output.end, 
            input_bounds.end,
        );

        // invert it back and check it against the inpout curve bounds
        const clip_media_to_output = (
            try clip_presentation_to_media_proj.src_to_dst_topo.inverted(
                allocator
            )
        );
        defer {
            for (clip_media_to_output)
                |t|
            {
                t.deinit(allocator);
            }
            allocator.free(clip_media_to_output);
        }

        for (clip_media_to_output)
            |topo|
        {
            const clip_media_to_presentation_input_bounds = (
                topo.input_bounds()
            );
            try opentime.expectOrdinateEqual(
                100,
                clip_media_to_presentation_input_bounds.start,
            );
            try opentime.expectOrdinateEqual(
                110,
                clip_media_to_presentation_input_bounds.end,
            );

            try std.testing.expect(
                clip_presentation_to_media_proj.src_to_dst_topo.mappings.len > 0
            );

            // walk over the presentation space of the curve
            const o_s_time = input_bounds.start;
            const o_e_time = input_bounds.end;
            var output_time = o_s_time;
            while (output_time.lt(o_e_time) )
                : (output_time = output_time.add(0.01))
            {
                // output time -> media time
                const media_time = (
                    try clip_presentation_to_media_proj.project_instantaneous_cc(
                        output_time
                    ).ordinate()
                );
                const clip_pres_to_media_topo = (
                    clip_presentation_to_media_proj.src_to_dst_topo
                );

                errdefer std.log.err(
                    "\nERR1\n  output_time: {d} \n"
                    ++ "  topology input_bounds: {any} \n"
                    ,
                    .{
                        output_time,
                        clip_pres_to_media_topo.input_bounds(),
                    }
                );

                // media time -> output time
                const computed_output_time = (
                    try topo.project_instantaneous_cc(media_time).ordinate()
                ); 

                errdefer std.log.err(
                    "\nERR\n  output_time: {d} \n"
                    ++ "  computed_output_time: {d} \n"
                    ++ " media_temporal_bounds: {any}\n"
                    ++ "  output_bounds: {any} \n",
                    .{
                        output_time,
                        computed_output_time,
                        media_temporal_bounds,
                        input_bounds,
                    }
                );

                try opentime.expectOrdinateEqual(
                    computed_output_time,
                    output_time,
                );
            }
        }
    }

    // media->presentation (reverse projection)
    {
        const clip_media_to_presentation = (
            try temporal_hierarchy.build_projection_operator(
                allocator,
                map,
                .{
                    .source =  try cl_ptr.space(references.SpaceLabel.media),
                    .destination = try wp_ptr.space(references.SpaceLabel.presentation),
                }
            )
        );
        defer clip_media_to_presentation.deinit(allocator);

        try opentime.expectOrdinateEqual(
            6.5745,
            try clip_media_to_presentation.project_instantaneous_cc(
                opentime.Ordinate.init(107),
            ).ordinate(),
        );
    }
}

test "test spaces list" 
{
    var cl = schema.Clip{};
    const it = references.ComposedValueRef{ .clip = &cl };
    const spaces = try it.spaces(std.testing.allocator);
    defer std.testing.allocator.free(spaces);

    try std.testing.expectEqual(
       references.SpaceLabel.presentation,
       spaces[0].label, 
    );
    try std.testing.expectEqual(
       references.SpaceLabel.media,
       spaces[1].label, 
    );
    try std.testing.expectEqual(
       "presentation",
       @tagName(references.SpaceLabel.presentation),
    );
    try std.testing.expectEqual(
       "media",
       @tagName(references.SpaceLabel.media),
    );
}

test "otio projection: track with single clip"
{
    const allocator = std.testing.allocator;

    // media is 9 seconds long and runs at 4 hz.
    const media_source_range = test_data_m.T_INT_1_TO_9;
    const media_discrete_info = (
        sampling.SampleIndexGenerator{
            .sample_rate_hz = .{ .Int = 4 },
            .start_index = 0,
        }
    );

    // construct the clip and add it to the track
    var cl = schema.Clip {
        .media = .{
            .bounds_s = media_source_range,
            .discrete_info = media_discrete_info,
        },
    };
    const cl_ptr = references.ComposedValueRef.init(&cl);

    var tr_children = [_]references.ComposedValueRef{ cl_ptr, };
    var tr: schema.Track = .{ .children = &tr_children };
    const tr_ptr = references.ComposedValueRef.init(&tr);

    const map = try temporal_hierarchy.build_temporal_map(
        allocator,
        tr_ptr
    );
    defer map.deinit(allocator);

    try temporal_hierarchy.validate_connections_in_map(map);

    try map.write_dot_graph(
        allocator,
        "/var/tmp/sampling_test.dot",
        "sampling_test",
        .{},
    );

    const track_to_media = (
        try temporal_hierarchy.build_projection_operator(
            allocator,
            map,
            .{
                .source = try tr_ptr.space(references.SpaceLabel.presentation),
                // does the discrete / continuous need to be disambiguated?
                .destination = try cl_ptr.space(references.SpaceLabel.media),
            },
        )
    );
    defer track_to_media.deinit(allocator);

    // instantaneous projection tests
    {
        // continuous time projection to the continuous intrinsic space for
        // continuous or interpolated samples
        try opentime.expectOrdinateEqual(
            4.5,
            try track_to_media.project_instantaneous_cc(
                opentime.Ordinate.init(3.5)
            ).ordinate(),
        );

        // for discrete non-interpolated data sources, allow projection to a
        // discrete index space
        try std.testing.expectEqual(
            // ??? - can't be prescriptive about how data sources are indexed, ie
            // paths to EXR frames or something
            (3 + 1) * 4,
            try track_to_media.project_instantaneous_cd(
                opentime.Ordinate.init(3),
            ),
        );
    }

    // range projection tests
    {
        const test_range_in_track:opentime.ContinuousInterval = .{
            .start = opentime.Ordinate.init(3.5),
            .end = opentime.Ordinate.init(4.5),
        };

        // continuous
        {
            const result_range_in_media = (
                try track_to_media.project_range_cc(
                    allocator,
                    test_range_in_track,
                )
            );
            defer result_range_in_media.deinit(allocator);

            const r = try cl.bounds_of(
                allocator,
                .media,
            );
            const b = result_range_in_media.output_bounds();
            errdefer {
                opentime.dbg_print(@src(), 
                    "clip trimmed range: [{d}, {d})\n",
                    .{
                        r.start,
                        r.end,
                    },
                );
                opentime.dbg_print(@src(), 
                    "result range: [{d}, {d})\n",
                    .{
                        b.start,
                        b.end,
                    },
                );
            }

            try opentime.expectOrdinateEqual(
                4.5,
                b.start,
            );

            try opentime.expectOrdinateEqual(
                5.5,
                b.end,
            );
        }

        // discrete
        {
            //                                   3.5s + 1s
            const expected = (
                [_]sampling.sample_index_t{ 18, 19, 20, 21 }
            );

            const r = track_to_media.src_to_dst_topo.input_bounds();
            const b = track_to_media.src_to_dst_topo.output_bounds();

            errdefer {
                opentime.dbg_print(@src(), 
                    "track range (c): [{d}, {d})\n",
                    .{
                        r.start,
                        r.end,
                    },
                );
                opentime.dbg_print(@src(), 
                    "media range (c): [{d}, {d})\n",
                    .{
                        b.start,
                        b.end,
                    },
                );
                opentime.dbg_print(@src(), 
                    "test range (c) in track: [{d}, {d})\n",
                    .{
                        test_range_in_track.start,
                        test_range_in_track.end,
                    },
                );
            }

            const result_media_indices = (
                try track_to_media.project_range_cd(
                    allocator,
                    test_range_in_track,
                )
            );
            defer allocator.free(result_media_indices);

            try std.testing.expectEqualSlices(
                sampling.sample_index_t,
                &expected,
                result_media_indices,
            );
        }
    }
}

test "otio projection: track with single clip with transform"
{
    const allocator = std.testing.allocator;

    // media is 9 seconds long and runs at 4 hz.
    const media_source_range = test_data_m.T_INT_1_TO_9;
    const media_discrete_info = (
        sampling.SampleIndexGenerator{
            .sample_rate_hz = .{ .Int = 4 },
            .start_index = 0,
        }
    );

    var cl = schema.Clip {
        .media = .{
            .bounds_s = media_source_range,
            .discrete_info = media_discrete_info,
        },
    };
    const cl_ptr = references.ComposedValueRef.init(&cl);

    var wp : schema.Warp = .{
        .child = cl_ptr,
        .transform = try topology_m.Topology.init_affine(
            allocator,
            .{
                .input_to_output_xform = .{
                    .scale = opentime.Ordinate.init(2),
                },
            },
        ),
    };
    defer wp.transform.deinit(allocator);

    var tr_children = [_]references.ComposedValueRef{
        references.ComposedValueRef.init(&wp),
    };
    var tr: schema.Track = .{
        .children = &tr_children,
    };

    var tl_children = [_]references.ComposedValueRef{
        references.ComposedValueRef.init(&tr),
    };
    var tl: schema.Timeline = .{
        .discrete_info = .{ 
            .presentation = .{
                .sample_rate_hz = .{ .Int = 24 },
                .start_index = 12,
            },
        },
        .tracks = .{ .children = &tl_children },
    };
    const tl_ptr = references.ComposedValueRef.init(&tl);

    const tr_ptr = tl.tracks.children[0];

    // build map and tests

    const map_tr = try temporal_hierarchy.build_temporal_map(
        allocator,
        tr_ptr
    );
    defer map_tr.deinit(allocator);

    const map_tl = try temporal_hierarchy.build_temporal_map(
        allocator,
        tl_ptr
    );
    defer map_tl.deinit(allocator);

    try map_tr.write_dot_graph(
        allocator,
        "/var/tmp/sampling_test.dot",
        "sampling_test",
        .{},
    );

    const track_to_media = (
        try temporal_hierarchy.build_projection_operator(
            allocator,
            map_tr,
            .{
                .source = try tr_ptr.space(.presentation),
                // does the discrete / continuous need to be disambiguated?
                .destination = try cl_ptr.space(.media),
            },
        )
    );
    defer track_to_media.deinit(allocator);

    // instantaneous projection tests
    {
        // continuous time projection to the continuous intrinsic space for
        // continuous or interpolated samples
        try opentime.expectOrdinateEqual(
            // (3.5*2 + 1),
            8,
            try track_to_media.project_instantaneous_cc(
                opentime.Ordinate.init(3.5)
            ).ordinate(),
        );

        // for discrete non-interpolated data sources, allow projection to a
        // discrete index space
        try std.testing.expectEqual(
            // ??? - can't be prescriptive about how data sources are indexed, ie
            // paths to EXR frames or something
            (3*2 + 1) * 4,
            try track_to_media.project_instantaneous_cd(
                opentime.Ordinate.init(3)
            ),
        );
    }

    // range projection tests
    {
        const test_range_in_track:opentime.ContinuousInterval = .{
            .start = opentime.Ordinate.init(3.0),
            .end = opentime.Ordinate.init(4.0),
        };

        // continuous
        {
            const result_range_in_media = (
                try track_to_media.project_range_cc(
                    allocator,
                    test_range_in_track,
                )
            );
            defer result_range_in_media.deinit(allocator);

            const r = try cl.bounds_of(
                allocator,
                .media,
            );
            const b = result_range_in_media.output_bounds();
            errdefer {
                opentime.dbg_print(@src(), 
                    "clip trimmed range: [{d}, {d})\n",
                    .{
                        r.start,
                        r.end,
                    },
                );
                opentime.dbg_print(@src(), 
                    "result range: [{d}, {d})\n",
                    .{
                        b.start,
                        b.end,
                    },
                );
            }

            try opentime.expectOrdinateEqual(
                7,
                b.start,
            );

            try opentime.expectOrdinateEqual(
                // (4.5 * 2 + 1)
                9,
                b.end,
            );
        }

        // continuous -> discrete
        {
            //                                   (3.0s*2 + 1s)*4
            const expected = [_]sampling.sample_index_t{ 
                28,30,32,34
            };

            const result_media_indices = (
                try track_to_media.project_range_cd(
                    allocator,
                    test_range_in_track,
                )
            );

            defer allocator.free(result_media_indices);

            try std.testing.expectEqualSlices(
                sampling.sample_index_t,
                &expected,
                result_media_indices,
            );
        }

        // discrete -> continuous
        {
            try map_tl.write_dot_graph(
                allocator,
                "/var/tmp/discrete_to_continuous_test.dot",
                "discrete_to_continuous_test",
                .{},
            );

            const timeline_to_media = (
                try temporal_hierarchy.build_projection_operator(
                    allocator,
                    map_tl,
                    .{
                        .source = try tl_ptr.space(.presentation),
                        // does the discrete / continuous need to be disambiguated?
                        .destination = try cl_ptr.space(.media),
                    },
                )
            );
            defer timeline_to_media.deinit(allocator);

            const result_tp = (
                try timeline_to_media.project_index_dc(
                    allocator,
                    12,
                )
            );
            defer result_tp.deinit(allocator);

            const output_range = (
                result_tp.output_bounds()
            );

            errdefer opentime.dbg_print(@src(), 
                "output_range: {d}, {d}\n",
                .{ output_range.start, output_range.end },
            );

            try std.testing.expectEqual(
                track_to_media.src_to_dst_topo.output_bounds().start,
                output_range.start
            );

            const start = (
                track_to_media.src_to_dst_topo.output_bounds().start
            );

            try opentime.expectOrdinateEqual(
                (
                 start.add(
                 // @TODO: should the 2.0 be a 1.0?
                 tl.discrete_info.presentation.?.sample_rate_hz.inv_as_ordinate().mul(2)
                 )
                ),
                output_range.end,
            );

            const result_indices = (
                try timeline_to_media.project_index_dd(
                    allocator,
                    12,
                )
            );
            defer allocator.free(result_indices);

            try std.testing.expectEqualSlices(
                sampling.sample_index_t,
                &.{ 4 },
                result_indices,
            );
        }
    }
}

test "Clip: Animated Parameter example"
{
    const root_allocator = std.testing.allocator;

    var arena = std.heap.ArenaAllocator.init(root_allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    const media_source_range = test_data_m.T_INT_1_TO_9;
    const media_discrete_info = (
        sampling.SampleIndexGenerator{
            .sample_rate_hz = .{ .Int = 4 },
            .start_index = 0,
        }
    );

    var cl = try schema.Clip.init(
        allocator,
        .{ 
            .media = .{
                .bounds_s = media_source_range,
                .discrete_info = media_discrete_info 
            },
        }
    );
    defer cl.destroy(allocator);

    const focus_distance = (
        schema.Clip.ParameterVarying{
            .domain = .time,
            .mapping = try topology_m.Topology.init_from_linear(
                allocator,
                try curve.Linear.init(
                    allocator,
                    &.{ 
                        curve.ControlPoint.init(.{ .in = 0, .out = 1 }),
                        curve.ControlPoint.init(.{ .in = 1, .out = 1.25 }),
                        curve.ControlPoint.init(.{ .in = 5, .out = 8}),
                        curve.ControlPoint.init(.{ .in = 8, .out = 10}),
                    },
                )
            ),
        }
    ).parameter();

    var lens_data = schema.Clip.ParameterMap.init(allocator);
    try lens_data.put("focus_distance", focus_distance);

    const param = schema.Clip.to_param(&lens_data);
    try cl.parameters.?.put( "lens",param );
}

// 
// Trace test
//
// What I want: trace spaces from a -> b, ie tl.presentation to clip.media
// 
// timeline.presentation: [0, 10)
//
//  timeline.presentation -> timline.child
//  affine transform: [blah, blaah)
//
// timeline.child: [0, 12)
//
test "test debug_print_time_hierarchy"
{
    const allocator = std.testing.allocator;

    // top level timeline

    // track

    // clips
    var cl1 = schema.Clip {
        .name = "Spaghetti.wav",
        .media = .{
            .bounds_s = null,
            .discrete_info = .{
                .sample_rate_hz = .{ .Int = 24 },
                .start_index = 0,
            },
            .ref = .{ 
                .signal = .{
                    .signal_generator = .{
                        .signal = .sine,
                        .duration_s = opentime.Ordinate.init(6.0),
                        .frequency_hz = 24,
                    },
                },
            },
        }
    };
    const cl_ptr = references.ComposedValueRef.init(&cl1);

    // new for this test - add in an warp on the clip, which holds the frame
    var wp = schema.Warp {
        .child = cl_ptr,
        .interpolating = true,
        .transform = try topology_m.Topology.init_identity(
            allocator,
            test_data_m.T_INT_1_TO_9,
        ),
    };
    defer wp.transform.deinit(allocator);

    var tr_children = [_]references.ComposedValueRef{
        references.ComposedValueRef.init(&wp),
    };
    var tr: schema.Track = .{
        .name = "Example Parent schema.Track",
        .children = &tr_children,
    };

    var tl_children = [_]references.ComposedValueRef{
        references.ComposedValueRef.init(&tr),
    };
    var tl: schema.Timeline = .{
        .name = "test debug_print_time_hierarchy",
        .discrete_info = .{ 
            .presentation = .{
                // matches the media rate
                .sample_rate_hz = .{ .Int = 24 },
                .start_index = 0,
            },
        },
        .tracks = .{ .children = &tl_children },
    };
    const tl_ptr = references.ComposedValueRef{
        .timeline = &tl 
    };

    //////

    const tp = try temporal_hierarchy.build_temporal_map(
        allocator,
        tl_ptr
    );
    defer tp.deinit(allocator);

    //////

    // count the scopes
    var i: usize = 0;
    var values = tp.map_code_to_index.valueIterator();
    while (values.next())
        |_|
    {
        i += 1;
    }

    try std.testing.expectEqual(13, i);
}

test "Single clip, schema.Warp bulk"
{
    //
    // This test runs through a number of configurations of a warp with a clip.
    // In each test, the clip has the media range of 100->110.
    //

    const allocator = std.testing.allocator;

    const media_temporal_bounds:opentime.ContinuousInterval = .{
        .start = opentime.Ordinate.init(100),
        .end = opentime.Ordinate.init(110),
    };

    var cl = schema.Clip {
        .bounds_s = media_temporal_bounds,
    };
    defer cl.destroy(allocator);
    const cl_ptr = references.ComposedValueRef.init(&cl);

    const cl_media = try cl_ptr.space(references.SpaceLabel.media);

    const TestCase = struct {
        label: []const u8,
        presentation_range : [2]opentime.Ordinate.BaseType, 
        warp_child_range : [2]opentime.Ordinate.BaseType,
        presentation_test : opentime.Ordinate.BaseType,
        clip_media_test : opentime.Ordinate.BaseType,
        project_to_finite: bool = true,
    };

    const tests = [_]TestCase{
        .{
            .label = "forward identity",
            .presentation_range = .{ 0, 10 },
            .warp_child_range = .{ 0, 10 },
            .presentation_test = 2,
            .clip_media_test = 102,
        },
        .{
            .label = "forward scale 2",
            .presentation_range = .{ 0, 5 },
            .warp_child_range = .{ 0, 10 },
            .presentation_test = 2,
            .clip_media_test = 104,
        },
        .{
            .label = "reverse identity",
            .presentation_range = .{ 0, 10 },
            .warp_child_range = .{ 10 , 0 },
            .presentation_test = 2,
            .clip_media_test = 108,
        },
        .{
            .label = "reverse identity 2",
            .presentation_range = .{ 0, 5 },
            .warp_child_range = .{ 10, 0 },
            .presentation_test = 2,
            .clip_media_test = 106,
        },
        .{
            .label = "held frame",
            .presentation_range = .{ 0, 5 },
            .warp_child_range = .{7, 7},
            .presentation_test = 2,
            .clip_media_test = 107,
            .project_to_finite = false,
        },
    };

    for (&tests, 0..)
        |t, ind|
    {
        errdefer opentime.dbg_print(@src(), 
            "Error\n Error with test: [{d}] {s}\n",
            .{ ind, t.label },
        );

        // mapping is presentation -> input so in: presentation, out = child
        const start:curve.ControlPoint = .{
            .in = opentime.Ordinate.init(t.presentation_range[0]),
            .out = opentime.Ordinate.init(t.warp_child_range[0]),
        };
        const end:curve.ControlPoint = .{
            .in = opentime.Ordinate.init(t.presentation_range[1]),
            .out = opentime.Ordinate.init(t.warp_child_range[1]),
        };

        const xform = (
            try topology_m.Topology.init_from_linear_monotonic(
                allocator,
                .{
                    .knots = &.{
                        start,
                        end,
                    },
                },
            )
        );
        defer xform.deinit(allocator);

        errdefer {
            opentime.dbg_print(@src(), 
                "produced transform: {f}\n",
                .{ xform }
            );
        }

        var warp : schema.Warp = .{
            .child = cl_ptr,
            .transform = xform,
        };

        const wp_ptr : references.ComposedValueRef = .{ .warp =  &warp };
        const wp_pres = try wp_ptr.space(references.SpaceLabel.presentation);

        const map = try temporal_hierarchy.build_temporal_map(
            allocator,
            wp_ptr,
        );
        defer map.deinit(allocator);

        try temporal_hierarchy.validate_connections_in_map(map);

        // presentation->media (forward projection)
        {
            const warp_pres_to_media_topo = (
                try temporal_hierarchy.build_projection_operator(
                    allocator,
                    map,
                    .{
                        .source =  wp_pres,
                        .destination = cl_media,
                    }
                )
            );
            defer warp_pres_to_media_topo.deinit(allocator);
            const input_bounds = (
                warp_pres_to_media_topo.src_to_dst_topo.input_bounds()
            );
            const output_bounds = (
                warp_pres_to_media_topo.src_to_dst_topo.output_bounds()
            );

            errdefer opentime.dbg_print(@src(), 
                "test data:\nprovided: {f}\n"
                ++ "input:  [{d}, {d})\n"
                ++ "output: [{d}, {d})\n"
                ++ "test presentaiton pt: {d}\n"
                ++ "TEST NAME: {s}\n"
                ,
                .{
                    opentime.ContinuousInterval{
                        .start =  start.in,
                        .end = end.in,
                    },
                    input_bounds.start, input_bounds.end ,
                    output_bounds.start, output_bounds.end,
                    t.presentation_test,
                    t.label,
                },
            );

            try opentime.expectOrdinateEqual(
                start.in,
                input_bounds.start,
            );

            try opentime.expectOrdinateEqual(
                end.in,
                input_bounds.end,
            );

            try opentime.expectOrdinateEqual(
                t.clip_media_test,
                try warp_pres_to_media_topo.project_instantaneous_cc(
                    opentime.Ordinate.init(t.presentation_test),
                ).ordinate(),
            );
        }

        // media->presentation (reverse projection)
        {
            const clip_media_to_presentation = (
                try temporal_hierarchy.build_projection_operator(
                    allocator,
                    map,
                    .{
                        .source =  cl_media,
                        .destination = wp_pres,
                    }
                )
            );
            defer clip_media_to_presentation.deinit(allocator);

            if (t.project_to_finite) 
            {
                try opentime.expectOrdinateEqual(
                    t.presentation_test,
                    try clip_media_to_presentation.project_instantaneous_cc(
                        opentime.Ordinate.init(t.clip_media_test),
                    ).ordinate(),
                );
            }
            else 
            {
                const r = clip_media_to_presentation.project_instantaneous_cc(
                    opentime.Ordinate.init(t.clip_media_test),
                );
                try opentime.expectOrdinateEqual(
                    0,
                    r.SuccessInterval.start
                );
                try opentime.expectOrdinateEqual(
                    5,
                    r.SuccessInterval.end
                );
            }
        }
    }
}
