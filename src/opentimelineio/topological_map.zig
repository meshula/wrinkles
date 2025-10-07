//! Implements a path-to-temporal coordinate space mapping for OTIO.  
//!
//! Contents:
//! * `TopologicalMap`, a bidirectional mapping of `core.SpaceReference` to
//!   `treecode.Treecode`. (Representing a map of the temporal spaces in an
//!   OTIO hierarchy).
//! * `build_topological_map` function for constructing a mapping under a given
//!   root.
//! * `TreenodeWalkingIterator` iterator that walks through a map between two
//!   end points.

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
pub const TopologicalMap = treecode.Map(core.SpaceReference);
pub const TreenodeWalkingIterator = TopologicalMap.TreenodeWalkingIterator;

fn walk_child_spaces(
    allocator: std.mem.Allocator,
    parent_otio_object: core.ComposedValueRef,
    parent_code: treecode.Treecode,
    topo_map: *TopologicalMap,
    otio_object_stack: anytype,
) !void
{
    // walk through the spaces on this object
    const children_ptrs = (
        try parent_otio_object.children_refs(allocator)
    );
    defer allocator.free(children_ptrs);

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
                topo_map.map_code_to_space.get(child_wrapper_space_code_ptr) == null
            );

            if (topo_map.map_space_to_code.get(space_ref)) 
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

        try topo_map.map_space_to_code.put(
            allocator,
            space_ref,
            child_wrapper_space_code_ptr,
        );
        try topo_map.map_code_to_space.put(
            allocator,
            child_wrapper_space_code_ptr,
            space_ref
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
            },
        );
    }
}

fn walk_internal_spaces(
    allocator: std.mem.Allocator,
    parent_otio_object: core.ComposedValueRef,
    parent_code: treecode.Treecode,
    topo_map: *TopologicalMap,
) !treecode.Treecode
{
    const spaces = try parent_otio_object.spaces(
        allocator
    );
    defer allocator.free(spaces);

    var last_space_code = parent_code;

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
                topo_map.map_code_to_space.get(space_code.hash()) == null
            );
            const maybe_fetched_code = (
                topo_map.map_space_to_code.get(space_ref)
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

        try topo_map.map_space_to_code.put(
            allocator,
            space_ref,
            space_code,
        );

        try topo_map.map_code_to_space.put(
            allocator,
            space_code,
            space_ref,
        );

        last_space_code = space_code;
    }

    return last_space_code;
}

/// Walks from `root_item` through the hierarchy of OTIO objects to construct a
/// `TopologicalMap` of all of the temporal spaces in the hierarchy.
///
/// For each OTIO Node, it walks through the spaces present inside the node
/// (Presentation, Intrinsic, etc) then into the children of the node.
pub fn build_topological_map(
    parent_allocator: std.mem.Allocator,
    root_item: core.ComposedValueRef,
) !TopologicalMap 
{
    // first off, arena this up
    var tmp_topo_map = TopologicalMap{};
    errdefer tmp_topo_map.deinit(parent_allocator);

    const StackNode = struct {
        path_code: treecode.Treecode,
        otio_object: core.ComposedValueRef,
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
        const last_space = try walk_internal_spaces(
            parent_allocator,
            current_stack_node.otio_object,
            current_stack_node.path_code,
            &tmp_topo_map,
        );

        // items that are in a stack/track/warp etc.
        try walk_child_spaces(
            parent_allocator,
            current_stack_node.otio_object,
            last_space,
            &tmp_topo_map,
            &otio_object_stack,
        );
    }

    // lock the maps
    tmp_topo_map.map_code_to_space.lockPointers();
    tmp_topo_map.map_space_to_code.lockPointers();

    // return result;
    return tmp_topo_map;
}

test "build_topological_map: leak sentinel test track w/ clip"
{
    const allocator = std.testing.allocator;

    var cl = schema.Clip{};

    var tr_children = [_]core.ComposedValueRef{
        core.ComposedValueRef.init(&cl),
    };
    var tr: schema.Track = .{ .children = &tr_children };
    const tr_ref = core.ComposedValueRef.init(&tr);

    const map = try build_topological_map(
        allocator,
        tr_ref,
    );
    defer map.deinit(allocator);
}

test "build_topological_map check root node" 
{
    const allocator = std.testing.allocator;

    const start = opentime.Ordinate.ONE;
    const end = T_ORD_10;
    const cti = opentime.ContinuousInterval{
        .start = start,
        .end = end 
    };

    var clips: [11]schema.Clip = undefined;
    var refs: [11]core.ComposedValueRef = undefined;

    for (&clips, &refs)
        |*cl_p, *ref|
    {
        cl_p.bounds_s = cti;

        ref.* = core.ComposedValueRef.init(cl_p);
    }

    var tr: schema.Track = .{.children = &refs };
    const tr_ref = core.ComposedValueRef.init(&tr);

    try std.testing.expectEqual(
        11,
        tr.children.len
    );

    const map = try build_topological_map(
        allocator,
        tr_ref,
    );
    defer map.deinit(allocator);

    try std.testing.expectEqual(
        tr_ref.space(.presentation),
        map.root(),
    );
}

test "build_topological_map: leak sentinel test - single clip"
{
    const allocator = std.testing.allocator;

    var cl = schema.Clip {};

    const map = try build_topological_map(
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

    const map = try build_topological_map(
        allocator,
        cl_ptr,
    );
    defer map.deinit(allocator);

    try map.write_dot_graph(
        allocator,
        "/var/tmp/walk.dot",
        .{},
    );

    var node_iter = try TreenodeWalkingIterator.init(
        allocator,
        &map,
    );
    defer node_iter.deinit(allocator);

    var count:usize = 0;
    while (try node_iter.next(allocator))
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

    const map = try build_topological_map(
        std.testing.allocator,
        tr_ptr
    );
    defer map.deinit(allocator);

    try map.write_dot_graph(
        allocator,
        "/var/tmp/walk.dot",
        .{},
    );

    var count:usize = 0;

    // from the top
    {
        var node_iter = try TreenodeWalkingIterator.init(
            allocator,
            &map,
        );
        defer node_iter.deinit(allocator);

        while (try node_iter.next(allocator))
        {
            count += 1;
        }

        // 5: track presentation, input, child, clip presentation, clip media
        try std.testing.expectEqual(5, count);
    }

    // from the clip
    {
        var node_iter = (
            try TreenodeWalkingIterator.init_from(
                std.testing.allocator,
                &map,
                try cl_ptr.space(.presentation),
            )
        );
        defer node_iter.deinit(allocator);

        count = 0;
        while (try node_iter.next(allocator))
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

    const map = try build_topological_map(
        std.testing.allocator,
        tr_ptr
    );
    defer map.deinit(allocator);

    try map.write_dot_graph(
        allocator,
        "/var/tmp/walk.dot",
        .{},
   );

    var count:usize = 0;

    // from the top to the second clip
    {
        var node_iter = (
            try TreenodeWalkingIterator.init_from_to(
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
    map: TopologicalMap,
    endpoints: TopologicalMap.PathEndPoints,
) !core.ProjectionOperator 
{
    // sort endpoints so that the higher node is always the source
    var sorted_endpoints = endpoints;
    const endpoints_were_swapped = try map.sort_endpoints(&sorted_endpoints);

    var root_to_current = (
        try topology_m.Topology.init_identity_infinite(allocator)
    );

    if (GRAPH_CONSTRUCTION_TRACE_MESSAGES) {
        opentime.dbg_print(@src(), 
            "[START] root_to_current: {f}\n",
            .{ root_to_current }
        );
    }

    var iter = (
        try TopologicalMap.TreenodeWalkingIterator.init_from_to(
            allocator,
            &map,
            sorted_endpoints,
        )
    );
    defer iter.deinit(allocator);

    _ = try iter.next(allocator);

    var current = iter.maybe_current.?;

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
    {
        const next = (
            iter.maybe_current orelse return error.TreeCodeNotInMap
        );

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

        // in case build_transform errors
        errdefer root_to_current.deinit(allocator);

        var current_to_next = (
            try current.space.ref.build_transform(
                allocator,
                current.space.label,
                next.space,
                next_step
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

    const result = try TopologicalMap.node_label(
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
