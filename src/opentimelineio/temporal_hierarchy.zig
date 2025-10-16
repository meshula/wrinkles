//! Implements a path-to-temporal coordinate space mapping for OTIO.  
//!
//! Contents:
//! * `TemporalMap`, a bidirectional mapping of `references.SpaceReference` to
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
const topology_m = @import("topology");

const schema = @import("schema.zig");
const references = @import("references.zig");
const projection = @import("projection.zig");
const test_data_m = @import("test_structures.zig");

/// annotate the graph algorithms
// const GRAPH_CONSTRUCTION_TRACE_MESSAGES = true;
const GRAPH_CONSTRUCTION_TRACE_MESSAGES = (
    build_options.debug_graph_construction_trace_messages
);

const T_ORD_10 =  opentime.Ordinate.init(10);
const T_CTI_1_10 = opentime.ContinuousInterval {
    .start = .ONE,
    .end = T_ORD_10,
};

// lofting types back out of function
pub const TemporalMap = treecode.Map(references.SpaceReference);
pub const PathEndPoints = TemporalMap.PathEndPoints;
pub const PathEndPointIndices = TemporalMap.PathEndPointIndices;

fn walk_child_spaces(
    allocator: std.mem.Allocator,
    parent_otio_object: references.ComposedValueRef,
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
    var last_code = parent_code;

    try otio_object_stack.ensureUnusedCapacity(allocator, children_ptrs.len);
    try map.ensure_unused_capacity(
        allocator,
        children_ptrs.len,
    );

    // transforms to children
    // each child
    for (children_ptrs, 0..) 
        |item_ptr, index| 
    {
        const child_wrapper_space_code_ptr = (
            try sequential_child_code_leaky(
                allocator,
                last_code,
                0,
            )
        );
        last_code = child_wrapper_space_code_ptr;

        // insert the child scope of the parent
        const space_ref = references.SpaceReference{
            .ref = parent_otio_object,
            .label = .child,
            .child_index = @intCast(index),
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

        last_index = map.put_assumes_capacity(
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

        otio_object_stack.appendAssumeCapacity(
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
    parent_otio_object: references.ComposedValueRef,
    parent_code: treecode.Treecode,
    parent_index: ?usize,
    map: *TemporalMap,
) !struct{ treecode.Treecode, ?usize }
{
    const spaces = parent_otio_object.spaces();

    var last_space_code = parent_code;
    var last_index = parent_index;

    for (0.., spaces) 
        |index, space_label| 
    {
        const space_ref = references.SpaceReference{
            .ref = parent_otio_object,
            .label = space_label,
        };
        const space_code = (
            if (index > 0) (
                try depth_child_code_leaky(
                    allocator,
                    last_space_code,
                    1,
                )
            ) else parent_code
        );

        if (GRAPH_CONSTRUCTION_TRACE_MESSAGES) 
        {
            std.debug.assert(
                map.get_space(space_code) == null
            );
            if (map.get_code(space_ref))
                |code|
            {
                std.debug.print(
                    "space {f} fetched code {f}\n",
                    .{space_ref, code},
                );
            }
            else {
                std.debug.print(
                    "space {f} has no code\n",
                    .{space_ref},
                );
                return error.SpaceWasntInMap;
            }
            opentime.dbg_print(
                @src(), 
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
    root_item: references.ComposedValueRef,
) !TemporalMap 
{
    var tmp_map: TemporalMap = .empty;
    errdefer tmp_map.deinit(parent_allocator);

    // NOTE: because OTIO objects contain multiple internal spaces, there is a
    //       stack of objects to process.
    const StackNode = struct {
        path_code: treecode.Treecode,
        otio_object: references.ComposedValueRef,
        parent_index: ?usize,
    };

    var otio_object_stack: std.ArrayList(StackNode) = .{};
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

    var tr_children = [_]references.ComposedValueRef{
        references.ComposedValueRef.init(&cl),
    };
    var tr: schema.Track = .{ .children = &tr_children };
    const tr_ref = references.ComposedValueRef.init(&tr);

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
    var refs: [SIZE]references.ComposedValueRef = undefined;

    for (&clips, &refs)
        |*cl_p, *ref|
    {
        cl_p.bounds_s = cti;

        ref.* = references.ComposedValueRef.init(cl_p);
    }

    var tr: schema.Track = .{.children = &refs };
    const tr_ref = references.ComposedValueRef.init(&tr);

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
    for (map.path_nodes.items(.parent_index), map.path_nodes.items(.child_indices), 0..)
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
            const parent_code = map.path_nodes.items(.code)[parent_index];
            const current_code = map.path_nodes.items(.code)[index];

            const parent_to_current = parent_code.next_step_towards(current_code);

            const parent_children = (
                map.path_nodes.items(.child_indices)[parent_index]
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
        references.ComposedValueRef.init(&cl)
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
    const cl_ptr = references.ComposedValueRef.init(&cl);

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

    // 5: clip presentation, clip media
    try std.testing.expectEqual(2, map.path_nodes.len);
}

test "TestWalkingIterator: track with clip"
{
    const allocator = std.testing.allocator;

    // media is 9 seconds long and runs at 4 hz.
    const media_source_range = T_CTI_1_10;

    var cl = schema.Clip {
        .bounds_s = media_source_range,
    };
    const cl_ptr = references.ComposedValueRef.init(&cl);

    var tr_children = [_]references.ComposedValueRef{ cl_ptr, };
    var tr: schema.Track = .{ .children = &tr_children };
    const tr_ptr = references.ComposedValueRef.init(&tr);

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

    // from the top
    {
        // 5: track presentation, input, child, clip presentation, clip media
        try std.testing.expectEqual(5, map.path_nodes.len);
    }

    // from the clip
    {
        const path_nodes = try map.nodes_under(
            allocator,
            cl_ptr.space(.presentation)
        );
        defer allocator.free(path_nodes);

        // 2: clip presentation, clip media
        try std.testing.expectEqual(2, path_nodes.len);
    }
}

pub fn path_from_parents(
    allocator: std.mem.Allocator,
    source_index: usize,
    destination_index: usize,
    codes: []treecode.Treecode,
    parents: []?usize,
) ![]const usize
{
    const source_code = codes[source_index];
    const dest_code = codes[destination_index];

    const length = dest_code.code_length - source_code.code_length + 1;

    const path = try allocator.alloc(
        usize,
        length,
    );
    
    fill_path_buffer(
        source_index,
        destination_index,
        path,
        parents,
    );

    return path;
}

pub fn fill_path_buffer(
    source_index: usize,
    destination_index: usize,
    path: []usize,
    parents: []?usize,
) void
{
    var current = destination_index;

    path[0] = source_index;

    for (0..path.len-1)
        |ind|
    {
        path[path.len - 1 - ind] = current;
        current = parents[current].?;
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
    const cl_ptr = references.ComposedValueRef.init(&cl2);

    var tr_children = [_]references.ComposedValueRef{
        references.ComposedValueRef.init(&cl),
        cl_ptr,
    };
    var tr: schema.Track = .{ .children = &tr_children };
    const tr_ptr = references.ComposedValueRef.init(&tr);

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

    // from the top to the second clip
    {
        const path = try map.path(
            allocator, 
            .{
                .source = map.index_from_space(
                    tr_ptr.space(.presentation)
                ).?,
                .destination = map.index_from_space(
                    cl_ptr.space(.media)
                ).?,
            },
        );
        defer allocator.free(path);

        const parent_path = try path_from_parents(
            allocator, 
            map.index_from_space(
                tr_ptr.space(.presentation)
            ).?,
            map.index_from_space(
                cl_ptr.space(.media)
            ).?,
            map.path_nodes.items(.code), 
            map.path_nodes.items(.parent_index)
        );
        defer allocator.free(parent_path);

        try std.testing.expectEqualSlices(
            usize,
            path,
            parent_path,
        );

        // 2: clip presentation, clip media
        try std.testing.expectEqual(6, path.len);
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

// pub const OperatorCache = std.AutoHashMapUnmanaged(
//     usize,
//     topology_m.Topology,
// );

/// A cache that maps an implied single source to a list of destinations, by
/// index relative to some map
pub const SingleSourceTopologyCache = struct { 
    items: []?topology_m.Topology,

    pub fn init(
        allocator: std.mem.Allocator,
        map: TemporalMap,
    ) !SingleSourceTopologyCache
    {
        const cache = try allocator.alloc(
            ?topology_m.Topology,
            map.space_nodes.len,
        );
        @memset(cache, null);

        return .{ .items = cache };
    }

    pub fn deinit(
        self: @This(),
        allocator: std.mem.Allocator,
    ) void
    {
        allocator.free(self.items);   
    }
};

pub fn build_projection_operator_indices(
    parent_allocator: std.mem.Allocator,
    map: TemporalMap,
    endpoints: TemporalMap.PathEndPointIndices,
    operator_cache: SingleSourceTopologyCache,
) !projection.ProjectionOperator 
{
    // sort endpoints so that the higher node is always the source
    var sorted_endpoints = endpoints;
    const endpoints_were_swapped = try map.sort_endpoint_indices(
        &sorted_endpoints
    );

    var arena = std.heap.ArenaAllocator.init(parent_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var root_to_current:topology_m.Topology = .INFINITE_IDENTITY;

    if (GRAPH_CONSTRUCTION_TRACE_MESSAGES) {
        opentime.dbg_print(@src(), 
            "[START] root_to_current: {f}\n",
            .{ root_to_current }
        );
    }

    const source_index = sorted_endpoints.source;

    const path_nodes = map.path_nodes.slice();
    const codes = path_nodes.items(.code);
    const space_nodes = map.space_nodes.slice();

    // compute the path length
    const path = try path_from_parents(
        allocator,
        source_index,
        sorted_endpoints.destination,
        codes,
        path_nodes.items(.parent_index),
    );

    if (GRAPH_CONSTRUCTION_TRACE_MESSAGES) {
        opentime.dbg_print(@src(), 
            "starting walk from: {f} to: {f}\n"
            ++ "starting projection: {f}\n"
            ,
            .{
                space_nodes.get(path[0]),
                sorted_endpoints.destination,
                root_to_current,
            }
        );
    }

    if (path.len < 2){
        return .{
            .source = map.space_nodes.get(
                endpoints.source
            ),
            .destination = map.space_nodes.get(
                endpoints.destination
            ),
            .src_to_dst_topo = .INFINITE_IDENTITY,
        };
    }

    var current = path[0];

    var path_step = TemporalMap.PathEndPointIndices{
        .source = @intCast(source_index),
        .destination = @intCast(source_index),
    };

    // walk from current_code towards destination_code - path[0] is the current
    // node, can be skipped
    for (path[1..])
        |next|
    {
        path_step.destination = @intCast(next);

        if (operator_cache.items[next])
            |cached_topology|
        {
            current = next;
            root_to_current = cached_topology;
            continue;
        }

        const next_step = codes[current].next_step_towards(codes[next]);

        if (GRAPH_CONSTRUCTION_TRACE_MESSAGES) { 
            opentime.dbg_print(@src(), 
                "  next step {b} towards next node: {f}\n"
                ,
                .{ next_step, next }
            );
        }

        const current_to_next = try space_nodes.items(.ref)[current].build_transform(
            allocator,
            space_nodes.items(.label)[current],
            space_nodes.get(next),
            next_step,
        );

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
                    source_index,
                    i_b,
                    next.space,
                    o_b,
                },
            );
        }

        operator_cache.items[next] = root_to_next;

        current = next;
        root_to_current = root_to_next;
    }

    // check to see if end points were inverted
    if (endpoints_were_swapped and root_to_current.mappings.len > 0) 
    {
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
            return error.MoreThanOneInversionIsNotImplemented;
        }
        if (inverted_topologies.len > 0) {
            root_to_current = inverted_topologies[0];
        }
        else {
            return error.NoInvertedTopologies;
        }
    }

    return .{
        .source = map.space_nodes.get(
            endpoints.source
        ),
        .destination = map.space_nodes.get(
            endpoints.destination
        ),
        .src_to_dst_topo = try root_to_current.clone(parent_allocator),
    };
}

/// build a projection operator that projects from the endpoints.source to
/// endpoints.destination spaces
pub fn build_projection_operator(
    parent_allocator: std.mem.Allocator,
    map: TemporalMap,
    endpoints: TemporalMap.PathEndPoints,
    operator_cache: SingleSourceTopologyCache,
) !projection.ProjectionOperator 
{
    return build_projection_operator_indices(
        parent_allocator,
        map,
        .{
            .source = map.index_from_space(endpoints.source).?,
            .destination = map.index_from_space(endpoints.destination).?,
        },
        operator_cache,
    );
}

test "label_for_node_leaky" 
{
    const allocator = std.testing.allocator;

    var buf: [1024]u8 = undefined;

    var tr: schema.Track = .EMPTY;
    const sr = references.SpaceReference{
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

    const map = try build_temporal_map(
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
        map.map_space_to_path_index.count(),
        map.path_nodes.len,
    );
    try std.testing.expectEqual(
        35,
        map.map_space_to_path_index.count()
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
            tr.children[t.ind].space(references.SpaceLabel.presentation)
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

    const map = try build_temporal_map(
        allocator,
        tr_ref,
    );
    defer map.deinit(allocator);

    try std.testing.expectEqual(
        11,
        tr_ref.track.children.len
    );

    const cache = (
        try SingleSourceTopologyCache.init(
            allocator,
            map,
        )
    );
    defer cache.deinit(allocator);

    const track_to_clip = try build_projection_operator(
        allocator,
        map,
        .{
            .source = tr_ref.space(references.SpaceLabel.presentation),
            .destination =  cl_ref.space(references.SpaceLabel.media)
        },
        cache,
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

    const map = try build_temporal_map(
        allocator,
        root,
    );
    defer map.deinit(allocator);

    try std.testing.expectEqual(
        5,
        map.map_space_to_path_index.count()
    );

    try std.testing.expectEqual(root, map.root().ref);

    const maybe_root_code = map.get_code(map.root());
    try std.testing.expect(maybe_root_code != null);
    const root_code = maybe_root_code.?;

    // root object code
    {
        var tc = try treecode.Treecode.init(allocator);
        defer tc.deinit(allocator);
        try std.testing.expect(tc.eql(root_code));
        try std.testing.expectEqual(0, tc.code_length);
    }

    const maybe_clip_code = map.get_code(
        cl_ref.space(references.SpaceLabel.media)
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
        try std.testing.expectEqual(4, tc.code_length);
        try std.testing.expect(tc.eql(clip_code));
    }

    try std.testing.expect(
        treecode.path_exists(clip_code, root_code)
    );

    const cache = (
        try SingleSourceTopologyCache.init(
            allocator,
            map,
        )
    );
    defer cache.deinit(allocator);

    const root_presentation_to_clip_media = (
        try build_projection_operator(
            allocator,
            map,
            .{
                .source = root.space(references.SpaceLabel.presentation),
                .destination = cl_ref.space(references.SpaceLabel.media)
            },
            cache,
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

    const tp = try build_temporal_map(
        allocator,
        tl_ptr
    );
    defer tp.deinit(allocator);

    std.debug.print("spaces:\n", .{});
    for (tp.space_nodes.items(.ref), tp.space_nodes.items(.label))
        |ref, label|
    {
        std.debug.print("  space: {f}.{f}\n", .{ref, label});
    }

    try std.testing.expectEqual(
        13,
        tp.map_space_to_path_index.count(),
    );
}

