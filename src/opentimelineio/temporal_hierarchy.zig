//! Implements a path-to-temporal coordinate space mapping for OTIO.  
//!
//! Contents:
//! * `TemporalMap`, a bidirectional mapping of `core.SpaceReference` to
//!   `treecode.Treecode`. (Representing a map of the temporal spaces in an
//!   OTIO hierarchy).
//! * `build_temporal_map` function for constructing a mapping under a given
//!   root.
//! * `PathIterator` iterator that walks through a map between two end spaces.

const std = @import("std");

const build_options = @import("build_options");
const treecode = @import("treecode");
const opentime = @import("opentime");
const string = @import("string_stuff");

const schema = @import("schema.zig");
const core = @import("core.zig");
const topology_m = @import("topology");

/// annotate the graph algorithms
// const GRAPH_CONSTRUCTION_TRACE_MESSAGES = true;
const GRAPH_CONSTRUCTION_TRACE_MESSAGES = (
    build_options.debug_graph_construction_trace_messages
);

const T_ORD_10 =  opentime.Ordinate.init(10);
const T_CTI_1_10 = opentime.ContinuousInterval {
    .start = opentime.Ordinate.ONE,
    .end = T_ORD_10,
};

// lofting types back out of function
pub const TemporalMap = treecode.Map(core.SpaceReference);
pub const PathIterator = TemporalMap.PathIterator;
pub const PathEndPoints = TemporalMap.PathEndPoints;

fn walk_child_spaces(
    allocator: std.mem.Allocator,
    parent_otio_object: core.ComposedValueRef,
    parent_code: treecode.Treecode,
    parent_index: ?usize,
    map: *TemporalMap,
    otio_object_stack: anytype,
) !void
{
    // walk through the spaces on this object
    const children_ptrs = (
        try parent_otio_object.children_refs(allocator)
    );
    defer allocator.free(children_ptrs);

    var last_index = parent_index;

    // transforms to children
    // each child
    for (children_ptrs, 0..) 
        |item_ptr, index| 
    {
        const child_wrapper_space_code_ptr = (
            try sequential_child_code_leaky(
                allocator,
                parent_code,
                index,
            )
        );

        // insert the child scope of the parent
        const space_ref = core.SpaceReference{
            .ref = parent_otio_object,
            .label = .child,
            .child_index = index,
        };

        if (GRAPH_CONSTRUCTION_TRACE_MESSAGES) 
        {
            std.debug.assert(
                map.get_space(child_wrapper_space_code_ptr) == null
            );

            if (map.get_code(space_ref)) 
                |other_code| 
                {
                    opentime.dbg_print(
                        @src(), 
                        "\n ERROR SPACE ALREADY PRESENT[{d}] code: {f} "
                        ++ "other_code: {f} "
                        ++ "adding child space: '{s}.{s}.{d}'\n",
                        .{
                            index,
                            child_wrapper_space_code_ptr,
                            other_code,
                            @tagName(space_ref.ref),
                            @tagName(space_ref.label),
                            space_ref.child_index.?,
                        }
                    );

                    std.debug.assert(false);
                }
            opentime.dbg_print(
                @src(), 
                (
                 "[{d}] code: {f} hash: {d} arrptr: {*} adding child space:"
                 ++ " '{s}.{s}.{d}'\n"
                ),
                .{
                    index,
                    child_wrapper_space_code_ptr,
                    child_wrapper_space_code_ptr.hash(),
                    child_wrapper_space_code_ptr.words.ptr,
                    @tagName(space_ref.ref),
                    @tagName(space_ref.label),
                    space_ref.child_index.?,
                }
            );
        }

        last_index = try map.put(
            allocator,
            .{
                .code = child_wrapper_space_code_ptr,
                .space = space_ref,
                .parent_index = last_index,
            },
        );

        // insert the child node to the stack
        const child_code_ptr = try depth_child_code_leaky(
            allocator,
            child_wrapper_space_code_ptr,
            1,
        );

        try otio_object_stack.insert(
            allocator,
            0,
            .{ 
                .otio_object= item_ptr,
                .path_code = child_code_ptr,
                .parent_index = last_index,
            },
        );
    }
}

fn walk_internal_spaces(
    allocator: std.mem.Allocator,
    parent_otio_object: core.ComposedValueRef,
    parent_code: treecode.Treecode,
    parent_index: ?usize,
    map: *TemporalMap,
) !struct{ treecode.Treecode, ?usize }
{
    const spaces = try parent_otio_object.spaces(
        allocator
    );
    defer allocator.free(spaces);

    var last_space_code = parent_code;
    var last_index = parent_index;

    for (0.., spaces) 
        |index, space_ref| 
    {
        const space_code = (
            if (index > 0) try depth_child_code_leaky(
                allocator,
                parent_code,
                index,
            )
            else parent_code
        );

        if (GRAPH_CONSTRUCTION_TRACE_MESSAGES) 
        {
            std.debug.assert(
                map.get_space(space_code) == null
            );
            const maybe_fetched_code = (
                map.get_code(space_ref)
            );
            if (maybe_fetched_code)
                |code|
            {
                std.debug.print(
                    "space {f} fetched code {f}\n",
                    .{space_ref, code},
                );
            }
            else {
                std.debug.print("space {f} has no code\n", .{space_ref});
                return error.SpaceWasntInMap;
            }
            opentime.dbg_print(@src(), 
                (
                      "[{d}] code: {f} hash: {d} arrptr: {*} adding local space: "
                      ++ "'{s}.{s}'"
                ),
                .{
                    index,
                    space_code,
                    space_code.hash(), 
                    space_code.words.ptr,
                    @tagName(space_ref.ref),
                    @tagName(space_ref.label)
                }
            );
        }

        last_index = try map.put(
            allocator,
            .{
                .code = space_code,
                .space = space_ref,
                .parent_index = last_index,
            },
        );

        last_space_code = space_code;
    }

    return .{ last_space_code, last_index };
}

/// Walks from `root_item` through the hierarchy of OTIO objects to construct a
/// `TemporalMap` of all of the temporal spaces in the hierarchy.
///
/// For each OTIO Node, it walks through the spaces present inside the node
/// (Presentation, Intrinsic, etc) then into the children of the node.
pub fn build_temporal_map(
    parent_allocator: std.mem.Allocator,
    root_item: core.ComposedValueRef,
) !TemporalMap 
{
    var tmp_map = TemporalMap{};
    errdefer tmp_map.deinit(parent_allocator);

    // NOTE: because OTIO objects contain multiple internal spaces, there is a
    //       stack of objects to process.
    const StackNode = struct {
        path_code: treecode.Treecode,
        otio_object: core.ComposedValueRef,
        parent_index: ?usize,
    };

    var otio_object_stack: std.ArrayList(StackNode) = .{};
    try otio_object_stack.ensureTotalCapacity(parent_allocator, 1024);
    defer otio_object_stack.deinit(parent_allocator);

    const root_code_ptr = try treecode.Treecode.init(
        parent_allocator,
    );

    try otio_object_stack.append(
        parent_allocator, 
        .{
            .otio_object = root_item,
            .path_code = root_code_ptr,
            .parent_index = null,
        }
    );

    if (GRAPH_CONSTRUCTION_TRACE_MESSAGES) {
        opentime.dbg_print(
            @src(),
            "\nstarting graph...\n",
            .{},
        );
    }

    while (otio_object_stack.pop()) 
        |current_stack_node|
    {
        // presentation, intrinsic, etc.
        const new_stuff = try walk_internal_spaces(
            parent_allocator,
            current_stack_node.otio_object,
            current_stack_node.path_code,
            current_stack_node.parent_index,
            &tmp_map,
        );

        // items that are in a stack/track/warp etc.
        try walk_child_spaces(
            parent_allocator,
            current_stack_node.otio_object,
            new_stuff[0],
            new_stuff[1],
            &tmp_map,
            &otio_object_stack,
        );
    }

    tmp_map.lock_pointers();

    // return result;
    return tmp_map;
}

test "build_temporal_map: leak sentinel test track w/ clip"
{
    const allocator = std.testing.allocator;

    var cl = schema.Clip{};

    var tr_children = [_]core.ComposedValueRef{
        core.ComposedValueRef.init(&cl),
    };
    var tr: schema.Track = .{ .children = &tr_children };
    const tr_ref = core.ComposedValueRef.init(&tr);

    const map = try build_temporal_map(
        allocator,
        tr_ref,
    );
    defer map.deinit(allocator);
}

test "build_temporal_map check root node" 
{
    const allocator = std.testing.allocator;

    const start = opentime.Ordinate.ONE;
    const end = T_ORD_10;
    const cti = opentime.ContinuousInterval{
        .start = start,
        .end = end 
    };

    const SIZE = 11;

    var clips: [SIZE]schema.Clip = undefined;
    var refs: [SIZE]core.ComposedValueRef = undefined;

    for (&clips, &refs)
        |*cl_p, *ref|
    {
        cl_p.bounds_s = cti;

        ref.* = core.ComposedValueRef.init(cl_p);
    }

    var tr: schema.Track = .{.children = &refs };
    const tr_ref = core.ComposedValueRef.init(&tr);

    try std.testing.expectEqual(
        SIZE,
        tr.children.len
    );

    const map = try build_temporal_map(
        allocator,
        tr_ref,
    );
    defer map.deinit(allocator);

    try std.testing.expectEqual(
        tr_ref.space(.presentation),
        map.root(),
    );

    try validate_connections_in_map(map);
}

pub fn validate_connections_in_map(
    map: TemporalMap,
) !void
{
    // check the parent/child pointers
    for (map.nodes.items(.parent_index), map.nodes.items(.child_indices), 0..)
        |maybe_parent_index, child_indices, index|
    {
        errdefer std.debug.print(
            "[{d}] parent: {?d} children ({?d}, {?d})\n",
            .{
                index,
                maybe_parent_index,
                child_indices[0],
                child_indices[1],
            },
        );
        try std.testing.expect(
            maybe_parent_index != null 
            or child_indices[0] != null 
            or child_indices[1] != null
        );

        // if there is a parent, expect that one of its children is this index
        if (maybe_parent_index)
            |parent_index|
        {
            const parent_code = map.nodes.items(.code)[parent_index];
            const current_code = map.nodes.items(.code)[index];

            const parent_to_current = parent_code.next_step_towards(current_code);

            const parent_children = (
                map.nodes.items(.child_indices)[parent_index]
            );

            try std.testing.expect(
                parent_children[@intFromEnum(parent_to_current)] == index
            );
        }
    }
}

test "build_temporal_map: leak sentinel test - single clip"
{
    const allocator = std.testing.allocator;

    var cl = schema.Clip {};

    const map = try build_temporal_map(
        allocator,
        core.ComposedValueRef.init(&cl)
    );
    defer map.deinit(allocator);
}

test "TestWalkingIterator: clip"
{
    const allocator = std.testing.allocator;

    // media is 9 seconds long and runs at 4 hz.
    const media_source_range = T_CTI_1_10;

    var cl = schema.Clip {
        .bounds_s = media_source_range,
    };
    const cl_ptr = core.ComposedValueRef.init(&cl);

    const map = try build_temporal_map(
        allocator,
        cl_ptr,
    );
    defer map.deinit(allocator);

    try map.write_dot_graph(
        allocator,
        "/var/tmp/walk.dot",
        "walk",
        .{},
    );

    var node_iter = try PathIterator.init(
        allocator,
        &map,
    );
    defer node_iter.deinit(allocator);

    var count:usize = 0;
    while (try node_iter.next(allocator))
        |_|
    {
        count += 1;
    }

    // 5: clip presentation, clip media
    try std.testing.expectEqual(2, count);
}

test "TestWalkingIterator: track with clip"
{
    const allocator = std.testing.allocator;

    // media is 9 seconds long and runs at 4 hz.
    const media_source_range = T_CTI_1_10;

    var cl = schema.Clip {
        .bounds_s = media_source_range,
    };
    const cl_ptr = core.ComposedValueRef.init(&cl);

    var tr_children = [_]core.ComposedValueRef{ cl_ptr, };
    var tr: schema.Track = .{ .children = &tr_children };
    const tr_ptr = core.ComposedValueRef.init(&tr);

    const map = try build_temporal_map(
        std.testing.allocator,
        tr_ptr
    );
    defer map.deinit(allocator);

    try map.write_dot_graph(
        allocator,
        "/var/tmp/walk.dot",
        "walk",
        .{},
    );

    var count:usize = 0;

    // from the top
    {
        var node_iter = try PathIterator.init(
            allocator,
            &map,
        );
        defer node_iter.deinit(allocator);

        while (try node_iter.next(allocator))
            |_|
        {
            count += 1;
        }

        // 5: track presentation, input, child, clip presentation, clip media
        try std.testing.expectEqual(5, count);
    }

    // from the clip
    {
        var node_iter = (
            try PathIterator.init_from(
                std.testing.allocator,
                &map,
                try cl_ptr.space(.presentation),
            )
        );
        defer node_iter.deinit(allocator);

        count = 0;
        while (try node_iter.next(allocator))
            |_|
        {
            count += 1;
        }

        // 2: clip presentation, clip media
        try std.testing.expectEqual(2, count);
    }
}

test "TestWalkingIterator: track with clip w/ destination"
{
    const allocator = std.testing.allocator;

    // media is 9 seconds long and runs at 4 hz.
    const media_source_range = T_CTI_1_10;

    // construct the clip and add it to the track
    var cl = schema.Clip {
        .bounds_s = media_source_range,
    };
    var cl2 = schema.Clip {
        .bounds_s = media_source_range,
    };
    const cl_ptr = core.ComposedValueRef.init(&cl2);

    var tr_children = [_]core.ComposedValueRef{
        core.ComposedValueRef.init(&cl),
        cl_ptr,
    };
    var tr: schema.Track = .{ .children = &tr_children };
    const tr_ptr = core.ComposedValueRef.init(&tr);

    const map = try build_temporal_map(
        std.testing.allocator,
        tr_ptr
    );
    defer map.deinit(allocator);

    try map.write_dot_graph(
        allocator,
        "/var/tmp/walk.dot",
        "walk",
        .{},
   );

    var count:usize = 0;

    // from the top to the second clip
    {
        var node_iter = (
            try PathIterator.init_from_to(
                allocator,
                &map,
                .{
                    .source = try tr_ptr.space(.presentation),
                    .destination = try cl_ptr.space(.media),
                },
            )
        );
        defer node_iter.deinit(allocator);

        count = 0;
        while (try node_iter.next(allocator))
               |_|
            : (count += 1)
        {
        }

        // 2: clip presentation, clip media
        try std.testing.expectEqual(6, count);
    }
}

fn depth_child_code_leaky(
    allocator: std.mem.Allocator,
    parent_code: treecode.Treecode,
    index: usize,
) !treecode.Treecode 
{
    var result = try parent_code.clone(allocator);

    for (0..index)
        |_|
    {
        try result.append(allocator, .left);
    }

    return result;
}

test "depth_child_hash: math" 
{
    const allocator = std.testing.allocator;

    var root = try treecode.Treecode.init_word(
        allocator,
        0b1000
    );
    defer root.deinit(allocator);

    const expected_root:treecode.TreecodeWord = 0b1000;

    for (0..4)
        |i|
    {
        var result = try depth_child_code_leaky(
            allocator,
            root,
            i,
        );
        defer result.deinit(allocator);

        const expected = std.math.shl(
            treecode.TreecodeWord,
            expected_root,
            i,
        ); 

        errdefer opentime.dbg_print(@src(), 
            "iteration: {d}, expected: {b} got: {f}\n",
            .{ i, expected, result }
        );

        try std.testing.expectEqual(
            expected,
            result.words[0],
        );
    }
}

fn sequential_child_code_leaky(
    allocator: std.mem.Allocator,
    parent_code: treecode.Treecode,
    index: usize,
) !treecode.Treecode 
{
    var result = try parent_code.clone(allocator);

    for (0..index+1)
        |_|
    {
        try result.append(allocator, .right);
    }

    return result;
}

test "sequential_child_code_leaky lifetime"
{
    const allocator = std.testing.allocator;

    var start_code = try treecode.Treecode.init(allocator);

    var next_code = try sequential_child_code_leaky(
        allocator,
        start_code,
        1,
    );
    defer next_code.deinit(allocator);

    const next_code_hash = next_code.hash();

    start_code.deinit(allocator);

    try std.testing.expectEqual(
        next_code_hash,
        next_code.hash()
    );
}

test "depth_child_code_leaky lifetime"
{
    const allocator = std.testing.allocator;

    var start_code = try treecode.Treecode.init(allocator);

    var next_code = try depth_child_code_leaky(
        allocator,
        start_code,
        1,
    );
    defer next_code.deinit(allocator);

    const next_code_hash = next_code.hash();

    start_code.deinit(allocator);

    try std.testing.expectEqual(
        next_code_hash,
        next_code.hash()
    );
}

test "sequential_child_hash: math" 
{
    const allocator = std.testing.allocator;

    var root = try treecode.Treecode.init_word(
        allocator,
        0b1000,
    );
    defer root.deinit(allocator);

    var test_code = try root.clone(allocator);
    defer test_code.deinit(allocator);

    for (0..4)
        |i|
    {
        var result = try sequential_child_code_leaky(
            allocator,
            root,
            i,
        );
        defer result.deinit(allocator);

        try test_code.append(allocator, .right);

        errdefer opentime.dbg_print(@src(), 
            "iteration: {d}, expected: {f} got: {f}\n",
            .{ i, test_code, result }
        );

        try std.testing.expect(test_code.eql(result));
    }
}

/// build a projection operator that projects from the endpoints.source to
/// endpoints.destination spaces
pub fn build_projection_operator(
    allocator: std.mem.Allocator,
    map: TemporalMap,
    endpoints: TemporalMap.PathEndPoints,
) !core.ProjectionOperator 
{
    // sort endpoints so that the higher node is always the source
    var sorted_endpoints = endpoints;
    const endpoints_were_swapped = try map.sort_endpoints(
        &sorted_endpoints
    );

    var root_to_current = (
        try topology_m.Topology.init_identity_infinite(allocator)
    );
    errdefer root_to_current.deinit(allocator);

    if (GRAPH_CONSTRUCTION_TRACE_MESSAGES) {
        opentime.dbg_print(@src(), 
            "[START] root_to_current: {f}\n",
            .{ root_to_current }
        );
    }

    var iter = (
        try TemporalMap.PathIterator.init_from_to(
            allocator,
            &map,
            sorted_endpoints,
        )
    );
    defer iter.deinit(allocator);

    var current = (try iter.next(allocator)).?;

    if (GRAPH_CONSTRUCTION_TRACE_MESSAGES) {
        opentime.dbg_print(@src(), 
            "starting walk from: {f} to: {f}\n"
            ++ "starting projection: {f}\n"
            ,
            .{
                current,
                sorted_endpoints.destination,
                root_to_current,
            }
        );
    }

    // walk from current_code towards destination_code
    while (try iter.next(allocator)) 
        |next|
    {
        const next_step = current.code.next_step_towards(
            next.code,
        );

        if (GRAPH_CONSTRUCTION_TRACE_MESSAGES) { 
            opentime.dbg_print(@src(), 
                "  next step {b} towards next node: {f}\n"
                ,
                .{ next_step, next }
            );
        }

        var current_to_next = (
            try current.space.ref.build_transform(
                allocator,
                current.space.label,
                next.space,
                next_step,
            )
        );
        defer current_to_next.deinit(allocator);

        if (GRAPH_CONSTRUCTION_TRACE_MESSAGES) 
        {
            opentime.dbg_print(@src(), 
                "    joining!\n"
                ++ "    a2b/root_to_current: {f}\n"
                ++ "    b2c/current_to_next: {f}\n"
                ,
                .{
                    root_to_current,
                    current_to_next,
                },
            );
        }

        const root_to_next = try topology_m.join(
            allocator,
            .{
                .a2b = root_to_current,
                .b2c = current_to_next,
            },
        );
        errdefer root_to_next.deinit(allocator);

        if (GRAPH_CONSTRUCTION_TRACE_MESSAGES) 
        {
            opentime.dbg_print(@src(), 
                "    root_to_next: {f}\n",
                .{root_to_next}
            );
            const i_b = root_to_next.input_bounds();
            const o_b = root_to_next.output_bounds();

            opentime.dbg_print(@src(), 
                "    root_to_next (next root to current!): {f}\n"
                ++ "    composed transform ranges {f}: {f},"
                ++ " {f}: {f}\n"
                ,
                .{
                    root_to_next,
                    iter.maybe_source.?.space,
                    i_b,
                    next.space,
                    o_b,
                },
                );
        }
        root_to_current.deinit(allocator);

        current = next;
        root_to_current = root_to_next;
    }

    // check to see if end points were inverted
    if (endpoints_were_swapped and root_to_current.mappings.len > 0) 
    {
        // const old_proj = root_to_current;
        const inverted_topologies = (
            try root_to_current.inverted(allocator)
        );
        defer allocator.free(inverted_topologies);
        root_to_current.deinit(allocator);
        errdefer opentime.deinit_slice(
            allocator,
            topology_m.Topology,
            inverted_topologies
        );
        if (inverted_topologies.len > 1)
        {
            return error.MoreThanOneCurveIsNotImplemented;
        }
        if (inverted_topologies.len > 0) {
            root_to_current = inverted_topologies[0];
        }
        else {
            return error.NoInvertedTopologies;
        }
    }

    return .{
        .source = sorted_endpoints.source,
        .destination = sorted_endpoints.destination,
        .src_to_dst_topo = root_to_current,
    };
}

test "label_for_node_leaky" 
{
    const allocator = std.testing.allocator;

    var buf: [1024]u8 = undefined;

    var tr: schema.Track = .{};
    const sr = core.SpaceReference{
        .label = .presentation,
        .ref = .{ .track = &tr },
    };

    var tc = try treecode.Treecode.init_word(
        allocator,
        0b1101001,
    );
    defer tc.deinit(allocator);

    const result = try TemporalMap.node_label(
        &buf,
        sr,
        tc,
        .treecode,
    );

    try std.testing.expectEqualStrings(
        "null.track.presentation.1101001",
        result,
    );
}
