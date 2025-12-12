//! Library for converting the objects from `schema` into a
//! `treecode.BinaryTree` via their `references.SpaceReference`s.
//!
//! Includes:
//! * `TemporalTree`: a specialization of `treecode.BinaryTree` over
//!    `references.SpaceReference`
//! * `build_temporal_tree`: that builds the `TemporalTree` under a given 
//!    `references.SpaceReference`

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
    .start = .one,
    .end = T_ORD_10,
};

/// Specialization of `treecode.BinaryTree` over
/// `references.TemporalSpaceReference`.
pub const TemporalTree = treecode.BinaryTree(
    references.TemporalSpaceNode
);

/// End points of a path in the tree.
pub const PathEndPoints = TemporalTree.PathEndPoints;

/// End points of a path in the tree expressed as indices.
pub const PathEndPointIndices = TemporalTree.PathEndPointIndices;

/// walk through the spaces that lead to child objects
fn walk_child_spaces(
    allocator: std.mem.Allocator,
    parent_otio_object: references.CompositionItemHandle,
    parent_code: treecode.Treecode,
    parent_index: ?usize,
    tree: *TemporalTree,
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
    try tree.ensure_unused_capacity(
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
        const space_ref = references.TemporalSpaceNode{
            .item = parent_otio_object,
            .space = .{ .child = @intCast(index) },
        };

        if (GRAPH_CONSTRUCTION_TRACE_MESSAGES) 
        {
            if (tree.code_from_node(space_ref)) 
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
                        @tagName(space_ref.item),
                        @tagName(space_ref.space),
                        space_ref.space.child,
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
                    @tagName(space_ref.item),
                    @tagName(space_ref.space),
                    space_ref.space.child,
                }
            );
        }

        last_index = tree.put_assumes_capacity(
            space_ref,
            .{
                .code = child_wrapper_space_code_ptr,
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
    parent_otio_object: references.CompositionItemHandle,
    parent_code: treecode.Treecode,
    parent_index: ?usize,
    tree: *TemporalTree,
) !struct{ treecode.Treecode, ?usize }
{
    const spaces = parent_otio_object.spaces();

    var last_space_code = parent_code;
    var last_index = parent_index;

    for (0.., spaces) 
        |index, space_label| 
    {
        const space_ref = references.TemporalSpaceNode{
            .item = parent_otio_object,
            .space = space_label,
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
        last_index = try tree.put(
            allocator,
            space_ref,
            .{
                .code = space_code,
                .parent_index = last_index,
            },
        );

        if (GRAPH_CONSTRUCTION_TRACE_MESSAGES) 
        {
            if (tree.code_from_node(space_ref))
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
                return error.SpaceWasntInTree;
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
                    @tagName(space_ref.item),
                    @tagName(space_ref.space)
                }
            );
        }

        last_space_code = space_code;
    }

    return .{ last_space_code, last_index };
}

/// Walks from `root_space` through the hierarchy of OTIO `schema` items to
/// construct a `TemporalTree` of all of the temporal spaces in the hierarchy.
pub fn build_temporal_tree(
    parent_allocator: std.mem.Allocator,
    /// root item of the tree
    root_space: references.TemporalSpaceNode,
) !TemporalTree 
{
    var tmp_tree: TemporalTree = .empty;
    errdefer tmp_tree.deinit(parent_allocator);

    const root_item = root_space.item;

    // NOTE: because OTIO objects contain multiple internal spaces, there is a
    //       stack of objects to process.
    const StackNode = struct {
        path_code: treecode.Treecode,
        otio_object: references.CompositionItemHandle,
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
        },
    );

    if (GRAPH_CONSTRUCTION_TRACE_MESSAGES) {
        opentime.dbg_print(
            @src(),
            "\nstarting tree...\n",
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
            &tmp_tree,
        );

        // items that are in a stack/track/warp etc.
        try walk_child_spaces(
            parent_allocator,
            current_stack_node.otio_object,
            new_stuff[0],
            new_stuff[1],
            &tmp_tree,
            &otio_object_stack,
        );
    }

    tmp_tree.lock_pointers();

    // return result;
    return tmp_tree;
}

test "build_temporal_tree: leak sentinel test track w/ clip"
{
    const allocator = std.testing.allocator;

    var cl: schema.Clip = .null_picture;

    var tr_children = [_]references.CompositionItemHandle{
        references.CompositionItemHandle.init(&cl),
    };
    var tr: schema.Track = .{ .children = &tr_children };
    const tr_ref = references.CompositionItemHandle.init(&tr);

    const tree = try build_temporal_tree(
        allocator,
        tr_ref.space(.presentation),
    );
    defer tree.deinit(allocator);
}

test "build_temporal_tree check root node" 
{
    const allocator = std.testing.allocator;

    const start = opentime.Ordinate.one;
    const end = T_ORD_10;
    const cti = opentime.ContinuousInterval{
        .start = start,
        .end = end 
    };

    const SIZE = 11;

    var clips: [SIZE]schema.Clip = undefined;
    var refs: [SIZE]references.CompositionItemHandle = undefined;

    for (&clips, &refs)
        |*cl_p, *ref|
    {
        cl_p.maybe_bounds_s = cti;

        ref.* = references.CompositionItemHandle.init(cl_p);
    }

    var tr: schema.Track = .{.children = &refs };
    const tr_ref = references.CompositionItemHandle.init(&tr);

    try std.testing.expectEqual(
        SIZE,
        tr.children.len
    );

    const tree = try build_temporal_tree(
        allocator,
        tr_ref.space(.presentation),
    );
    defer tree.deinit(allocator);

    try std.testing.expectEqual(
        tr_ref.space(.presentation),
        tree.root_node(),
    );

    try validate_connections_in_tree(tree);
}

/// Ensure that parent/child pointers in a tree are correctly set.
pub fn validate_connections_in_tree(
    tree: TemporalTree,
) !void
{
    // check the parent/child pointers
    for (
        tree.tree_data.items(.parent_index),
        tree.tree_data.items(.child_indices),
        0..,
    ) |maybe_parent_index, child_indices, index|
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
            const parent_code = tree.tree_data.items(.code)[parent_index];
            const current_code = tree.tree_data.items(.code)[index];

            const parent_to_current = parent_code.next_step_towards(current_code);

            const parent_children = (
                tree.tree_data.items(.child_indices)[parent_index]
            );

            try std.testing.expect(
                parent_children[@intFromEnum(parent_to_current)] == index
            );
        }
    }
}

test "build_temporal_tree: leak sentinel test - single clip"
{
    const allocator = std.testing.allocator;

    var cl : schema.Clip = .null_picture;

    const tree = try build_temporal_tree(
        allocator,
        cl.reference().space(.presentation)
    );
    defer tree.deinit(allocator);
}

test "TestWalkingIterator: clip"
{
    const allocator = std.testing.allocator;

    // media is 9 seconds long and runs at 4 hz.
    const media_source_range = T_CTI_1_10;

    var cl = schema.Clip {
        .maybe_bounds_s = media_source_range,
        .media = .null_picture,
    };
    const cl_ptr = references.CompositionItemHandle.init(&cl);

    const tree = try build_temporal_tree(
        allocator,
        cl_ptr.space(.presentation),
    );
    defer tree.deinit(allocator);

    try tree.write_dot_graph(
        allocator,
        "/var/tmp/walk.dot",
        "walk",
        .{},
    );

    // 5: clip presentation, clip media
    try std.testing.expectEqual(2, tree.tree_data.len);
}

test "TestWalkingIterator: track with clip w/ destination"
{
    const allocator = std.testing.allocator;

    // media is 9 seconds long and runs at 4 hz.
    const media_source_range = T_CTI_1_10;

    // construct the clip and add it to the track
    var cl = schema.Clip {
        .maybe_bounds_s = media_source_range,
        .media = .null_picture,
    };
    var cl2 = schema.Clip {
        .maybe_bounds_s = media_source_range,
        .media = .null_picture,
    };
    const cl_ptr = references.CompositionItemHandle.init(&cl2);

    var tr_children = [_]references.CompositionItemHandle{
        references.CompositionItemHandle.init(&cl),
        cl_ptr,
    };
    var tr: schema.Track = .{ .children = &tr_children };
    const tr_ptr = references.CompositionItemHandle.init(&tr);

    const tree = try build_temporal_tree(
        allocator,
        tr_ptr.space(.presentation)
    );
    defer tree.deinit(allocator);

    try tree.write_dot_graph(
        allocator,
        "/var/tmp/walk.dot",
        "walk",
        .{},
   );

    // from the top to the second clip
    {
        const path = try tree.path(
            allocator, 
            .{
                .source = tree.index_for_node(
                    tr_ptr.space(.presentation)
                ).?,
                .destination = tree.index_for_node(
                    cl_ptr.space(.media)
                ).?,
            },
        );
        defer allocator.free(path);

        const parent_path = try tree.path(
            allocator, 
            .{
                .source = tree.index_for_node(
                    tr_ptr.space(.presentation)
                ).?,
                .destination = tree.index_for_node(
                        cl_ptr.space(.media)
                    ).?,
                },
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

test "label_for_node_leaky" 
{
    const allocator = std.testing.allocator;

    var buf: [1024]u8 = undefined;

    var tr: schema.Track = .empty;
    const sr = references.TemporalSpaceNode{
        .space = .presentation,
        .item = .{ .track = &tr },
    };

    var tc = try treecode.Treecode.init_word(
        allocator,
        0b1101001,
    );
    defer tc.deinit(allocator);

    const result = try TemporalTree.node_label(
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

test "path_code: tree test" 
{
    const allocator = std.testing.allocator;

    var clips: [11]schema.Clip = undefined;
    var clip_ptrs: [11]references.CompositionItemHandle = undefined;

    for (&clips, &clip_ptrs)
        |*cl, *cl_p|
    {
        cl.* = schema.Clip {
            .maybe_bounds_s = test_data_m.T_INT_1_TO_9,
            .media = .null_picture,
        };

        cl_p.* = references.CompositionItemHandle.init(cl);
    }
    var tr: schema.Track = .{
        .children = &clip_ptrs,
    };
    const tr_ref = references.CompositionItemHandle.init(&tr);

    try std.testing.expectEqual(11, tr.children.len);

    const tree = try build_temporal_tree(
        allocator,
        tr_ref.space(.presentation),
    );
    defer tree.deinit(allocator);

    try std.testing.expectEqual(
        tr_ref.space(.presentation),
        tree.root_node(),
    );

    try tree.write_dot_graph(
        allocator,
        "/var/tmp/graph_test_output.dot",
        "graph_test",
        .{},
    );

    // should be the same length
    try std.testing.expectEqual(
        tree.map_node_to_index.count(),
        tree.tree_data.len,
    );
    try std.testing.expectEqual(
        35,
        tree.map_node_to_index.count()
    );

    try tree.write_dot_graph(
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
            tr.children[t.ind].space(.presentation)
        );
        const result = (
            tree.code_from_node(space) 
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
        .maybe_bounds_s = range,
        .media = .null_picture,
    };

    var clips: [11]schema.Clip = undefined;
    var refs: [11]references.CompositionItemHandle = undefined;

    for (&clips, &refs)
        |*cl_p, *ref|
    {
        cl_p.* = cl_template;
        ref.* = references.CompositionItemHandle.init(cl_p);
    }

    var tr: schema.Track = .{ .children = &refs };
    const tr_ref = references.CompositionItemHandle.init(&tr);

    const tree = try build_temporal_tree(
        allocator,
        tr_ref.space(.presentation),
    );
    defer tree.deinit(allocator);

    try std.testing.expectEqual(
        11,
        tr_ref.track.children.len
    );
}


test "Temporaltree: schema.Track with clip with identity transform" 
{
    const allocator = std.testing.allocator;

    var cl = schema.Clip{
        .maybe_bounds_s = test_data_m.T_INT_0_TO_2,
        .media = .null_picture,
    };
    const cl_ref = references.CompositionItemHandle.init(&cl);

    var tr_children = [_]references.CompositionItemHandle{ cl_ref, };
    var tr: schema.Track = .{ .children = &tr_children };

    const root = references.CompositionItemHandle.init(&tr);

    const tree = try build_temporal_tree(
        allocator,
        root.space(.presentation),
    );
    defer tree.deinit(allocator);

    try std.testing.expectEqual(
        5,
        tree.map_node_to_index.count()
    );

    try std.testing.expectEqual(root, tree.root_node().item);

    const maybe_root_code = tree.code_from_node(tree.root_node());
    try std.testing.expect(maybe_root_code != null);
    const root_code = maybe_root_code.?;

    // root object code
    {
        var tc = try treecode.Treecode.init(allocator);
        defer tc.deinit(allocator);
        try std.testing.expect(tc.eql(root_code));
        try std.testing.expectEqual(0, tc.code_length);
    }

    const maybe_clip_code = tree.code_from_node(
        cl_ref.space(.media)
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
        errdefer opentime.dbg_print(
            @src(), 
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
        .maybe_name = "Spaghetti.wav",
        .media = .{
            .domain = .picture,
            .maybe_bounds_s = null,
            .maybe_discrete_partition = .{
                .sample_rate_hz = .{ .Int = 24 },
                .start_index = 0,
            },
            .data_reference = .{ 
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
    const cl_ptr = references.CompositionItemHandle.init(&cl1);

    // new for this test - add in an warp on the clip, which holds the frame
    var wp = schema.Warp {
        .child = cl_ptr,
        .transform = try topology_m.Topology.init_identity(
            allocator,
            test_data_m.T_INT_1_TO_9,
        ),
    };
    defer wp.transform.deinit(allocator);

    var tr_children = [_]references.CompositionItemHandle{
        references.CompositionItemHandle.init(&wp),
    };
    var tr: schema.Track = .{
        .maybe_name = "Example Parent schema.Track",
        .children = &tr_children,
    };

    var tl_children = [_]references.CompositionItemHandle{
        references.CompositionItemHandle.init(&tr),
    };
    var tl: schema.Timeline = .{
        .maybe_name = "test debug_print_time_hierarchy",
        .discrete_space_partitions = .{ 
            .presentation = .{
                .picture = .{ 
                    // matches the media rate
                    .sample_rate_hz = .{ .Int = 24 },
                    .start_index = 0,
                },
                .audio = null,
            },
        },
        .tracks = .{ .children = &tl_children },
    };
    const tl_ptr = tl.reference();

    //////

    const tp = try build_temporal_tree(
        allocator,
        tl_ptr.space(.presentation),
    );
    defer tp.deinit(allocator);
}

test "track child after gap - use presentation space to compute offset" 
{
    const allocator = std.testing.allocator;

    var gp = schema.Gap{
        .duration_s = opentime.Ordinate.init(3),
    };
    var cl = schema.Clip {
        .maybe_name = "target_clip",
        .maybe_bounds_s = @import(
            "test_structures.zig"
        ).T_INT_1_TO_9, 
        .media = .null_picture,
    };
    const cl_ref = references.CompositionItemHandle.init(&cl);
    var gp2 = schema.Gap{
        .duration_s = opentime.Ordinate.init(4),
    };

    var tr_children = [_]references.CompositionItemHandle{
        references.CompositionItemHandle.init(&gp),
        cl_ref,
        references.CompositionItemHandle.init(&gp2),
    };
    var tr: schema.Track = .{
        .maybe_name = "root",
        .children = &tr_children,
    };
    const tr_ref = references.CompositionItemHandle.init(&tr);

    var proj_topo = (
        try projection.TemporalProjectionBuilder.init_from(
            allocator,
            tr_ref.space(.presentation),
        )
    );
    defer proj_topo.deinit(allocator);

    const tr_pres_to_cl_media = (
        try proj_topo.projection_operator_to(
            allocator,
             cl_ref.space(.media),
        )
    );

    errdefer std.debug.print(
        "ERROR:\n  source_bounds: {?f}\n  destination_bounds: {?f}\n",
        .{
            tr_pres_to_cl_media.source_bounds(),
            tr_pres_to_cl_media.destination_bounds(),
        },
    );

    try opentime.expectOrdinateEqual(
        gp.duration_s, 
        tr_pres_to_cl_media.source_bounds().?.start,
    );
    try opentime.expectOrdinateEqual(
        gp.duration_s.add(cl.maybe_bounds_s.?.duration()), 
        tr_pres_to_cl_media.source_bounds().?.end,
    );

    try opentime.expectOrdinateEqual(
        1, 
        tr_pres_to_cl_media.destination_bounds().?.start,
    );
    try opentime.expectOrdinateEqual(
        9, 
        tr_pres_to_cl_media.destination_bounds().?.end,
    );

    try opentime.expectOrdinateEqual(
        0, 
        proj_topo.input_bounds().?.start,
    );
    try opentime.expectOrdinateEqual(
        15,
        proj_topo.input_bounds().?.end,
    );
}
