//! A `BinaryTree` of nodes whose position in a hierarchy is encoded via
//! `treecode.Treecode`.

const std = @import("std");
const build_options = @import("build_options");
const builtin = @import("builtin");

const treecode = @import("treecode.zig");

/// annotate the tree algorithms
const GRAPH_CONSTRUCTION_TRACE_MESSAGES = (
    build_options.debug_graph_construction_trace_messages
);
// const GRAPH_CONSTRUCTION_TRACE_MESSAGES = true;

const DEBUG_MESSAGES= (
    build_options.debug_graph_construction_trace_messages 
    or build_options.debug_print_messages 
);

/// Which style to render node labels in, as binary codes or hashes.  Codes are
/// more readable, but make large graphs impossible to read.
const LabelStyle = enum(u1) { treecode, hash };

/// The index type for nodes stored in the `BinaryTree`
pub const NodeIndex = usize;

/// Root code refers the root node the `BinaryTree`
const ROOT_CODE:treecode.Treecode = .EMPTY;

/// Type function that returns a `BinaryTree` of nodes parameterized by
/// `NodeType`.
///
/// `NodeType` must have a hash() function.  
///
/// `NodeTypes` are stored in a flat `std.MultiArrayList` (SoA style) and
/// referred to by index.
///
/// The `path` function can be used to efficiently compute a path of node
/// indices between two nodes, using the treecodes and pointers to avoid a
/// search.
///
/// Owns all the data put into the `BinaryTree`, including nodes in the `.nodes`
/// list and treecodes in the `.graph_data` list.
pub fn BinaryTree(
    comptime NodeType: type,
) type
{
    return struct {
        // type alias
        const BinaryTreeType = @This();

        /// Encoding of the end points of a path between `NodeType`s in the 
        /// `BinaryTree`.
        pub const PathEndPoints = struct {
            source: NodeType,
            destination: NodeType,
        };

        /// End points of a path via the indices of the nodes
        pub const PathEndPointIndices = struct {
            source: NodeIndex,
            destination: NodeIndex,
        };

        /// The graph information (Parent/Child/`treecode.Treecode`) for a
        /// given node in the `BinaryTree`.
        pub const TreeData = struct {
            /// address in the `BinaryTree`, see `treecode.Treecode` for more
            /// information.
            code: treecode.Treecode,
            /// Index in the `.nodes` list of parent, if one is present
            parent_index: ?NodeIndex = null,
            /// Indices of children, if present
            child_indices: [2]?NodeIndex = .{null, null},
        };

        /// `std.AutoHashMapUnmanaged` mapping the hash of a `NodeType` to the
        /// index of the node in the `BinaryTree` the `.nodes` and
        /// `.tree_data` lists.
        ///
        /// XXX: this currently does not support node types with slices in them,
        ///      due to constrants in the autohasher (as of zig 0.15.2)
        map_node_to_index: std.AutoHashMapUnmanaged(
            NodeType,
            NodeIndex,
        ),

        /// The graph data (Parent/Child indices, `treecode.Treecode`) for the
        /// corresponding index in the `.nodes` list.
        tree_data: std.MultiArrayList(TreeData),

        /// Store of nodes in the `BinaryTree`
        nodes:std.MultiArrayList(NodeType),

        /// Empty BinaryTree
        pub const empty = BinaryTreeType{
            .map_node_to_index = .empty,
            .tree_data = .empty,
            .nodes = .empty,
        };

        pub fn deinit(
            self: @This(),
            allocator: std.mem.Allocator,
        ) void 
        {
            // build a mutable alias of self
            var mutable_self = self;

            for (self.tree_data.items(.code))
                |code|
            { 
                code.deinit(allocator);
            }

            // free the guts
            if (builtin.mode == .Debug 
                and self.map_node_to_index.pointer_stability.state == .locked
            )
            {
                mutable_self.map_node_to_index.unlockPointers();
            }
            mutable_self.map_node_to_index.deinit(allocator);

            mutable_self.tree_data.deinit(allocator);
            mutable_self.nodes.deinit(allocator);
        }

        /// Lock the pointers in the hash map when done with construction.
        pub fn lock_pointers(
            self: *@This(),
        ) void
        {
            self.map_node_to_index.lockPointers();

            // @TODO: could switch the implementation over to .Slice() here
        }

        /// Allocate capacity for the given count of nodes.
        pub fn ensure_unused_capacity(
            self: *@This(),
            allocator: std.mem.Allocator,
            capacity: usize,
        ) !void
        {
            try self.tree_data.ensureUnusedCapacity(
                allocator,
                capacity
            );
            try self.nodes.ensureUnusedCapacity(
                allocator,
                capacity
            );
            try self.map_node_to_index.ensureUnusedCapacity(
                allocator,
                @intCast(capacity)
            );
        }

        /// Add a Node to the `BinaryTree` and return the index of the new node.
        ///
        /// Note that `tree_data` is owned by the `BinaryTree`, specifically 
        /// the `treecode.Treecode`.
        pub fn put(
            self: *@This(),
            allocator: std.mem.Allocator,
            node: NodeType,
            tree_data: TreeData,
        ) !NodeIndex
        {

            try self.nodes.append(allocator, node);

            const new_path_index = self.tree_data.len;
            try self.tree_data.append(
                allocator,
                tree_data,
            );

            try self.map_node_to_index.put(
                allocator,
                node,
                new_path_index,
            );

            if (tree_data.parent_index)
                |parent_index|
            {
                const parent_code = self.tree_data.items(.code)[parent_index];
                const dir = parent_code.next_step_towards(tree_data.code);
                var child_indices = &self.tree_data.items(
                    .child_indices
                )[parent_index];
                child_indices[@intFromEnum(dir)] = new_path_index;
            }

            if (tree_data.child_indices[@intFromEnum(treecode.l_or_r.left)])
                |left_child|
            {
                self.tree_data.items(.parent_index)[left_child] = new_path_index;
            }
            if (tree_data.child_indices[@intFromEnum(treecode.l_or_r.right)])
                |right_child|
            {
                self.tree_data.items(.parent_index)[right_child] = new_path_index;
            }

            return new_path_index;
        }

        /// Add a Node to the `BinaryTree` and return the index of the new
        /// node, assuming that capacity has already been allocated.
        ///
        /// Note that `tree_data` is owned by the `BinaryTree`, specifically 
        /// the `treecode.Treecode`.
        pub fn put_assumes_capacity(
            self: *@This(),
            node: NodeType,
            tree_data: TreeData,
        ) NodeIndex
        {
            const new_index = self.nodes.len;
            self.nodes.appendAssumeCapacity(node);

            self.tree_data.appendAssumeCapacity(tree_data);

            self.map_node_to_index.putAssumeCapacity(
                node,
                new_index,
            );

            // connect parent pointer
            if (tree_data.parent_index)
                |parent_index|
            {
                const parent_code = self.tree_data.items(.code)[parent_index];
                const dir = parent_code.next_step_towards(tree_data.code);
                var child_indices = &self.tree_data.items(
                    .child_indices
                )[parent_index];
                child_indices[@intFromEnum(dir)] = new_index;
            }
            
            return new_index;
        }

        /// Fetch the treecode associated with a given node.
        ///
        /// Note that this `treecode.Treecode` is still owned by the
        /// `BinaryTree`.
        pub fn code_from_node(
            self: @This(),
            node: NodeType,
        ) ?treecode.Treecode
        {
            if (self.map_node_to_index.get(node))
                |index|
            {
                return self.tree_data.items(.code)[index];
            }

            return null;
        }

        /// Fetch the index of the given `node`.
        pub fn index_for_node(
            self: @This(),
            node: NodeType,
        ) ?NodeIndex
        {
            return self.map_node_to_index.get(node);
        }

        /// Return the root node associated with the `ROOT_CODE`.
        pub fn root_node(
            self: @This(),
        ) NodeType 
        {
            // should always have a root object, and root object should always
            // be the first entry in the nodes list
            return self.nodes.get(0);
        }

        /// Serialize this `BinaryTree` to dot and then use graphviz to convert
        /// that dot to a png.  Will create /var/tmp/`png_filepath`.dot.
        ///
        /// If graphviz is disabled in the build, will still write the .dot
        /// file, but will return before attempting to call dot on it to
        /// convert it to a png.
        pub fn write_dot_graph(
            self:@This(),
            allocator: std.mem.Allocator,
            /// path to the desired resulting png file
            png_filepath: []const u8,
            /// name to put at the top of the graph - may not contain spaces 
            header_name: []const u8,
            comptime options: struct {
                /// by default show the hashes in the node labels
                label_style: LabelStyle = .hash,
                /// if this is off, will generate the .dot file and return
                render_png: bool = true,
            },
        ) !void 
        {
            var arena = std.heap.ArenaAllocator.init(allocator);
            defer arena.deinit();
            const arena_allocator = arena.allocator();

            // open the file
            var file = try std.fs.createFileAbsolute(
                png_filepath,
                .{},
            );
            defer file.close();

            var file_writer_buffer: [16*1024]u8 = undefined;
            var file_writer = file.writer(&file_writer_buffer);
            var writer = &file_writer.interface;

            // header text for the dot file
            _ = try writer.print(
                "digraph {s} {{\n",
                .{ header_name }
            );

            var label_buf: [1024]u8 = undefined;
            var next_label_buf: [1024]u8 = undefined;

            const nodes = self.tree_data.slice();

            for (0..self.tree_data.len)
                |current_index|
            {
                const current_code = nodes.items(.code)[current_index];

                const current_label = try node_label(
                    &label_buf,
                    self.nodes.get(current_index),
                    current_code,
                    options.label_style,
                );

                const current_children = (
                    self.tree_data.items(.child_indices)[current_index]
                );
                for (current_children)
                    |maybe_child_index|
                {
                    if (maybe_child_index)
                        |child_index|
                    {
                        const next_label = try node_label(
                            &next_label_buf,
                            self.nodes.get(child_index),
                            nodes.items(.code)[child_index],
                            options.label_style,
                        );
                        _ = try writer.print(
                            "  \"{s}\" -> \"{s}\"\n",
                            .{current_label, next_label}
                        );
                    } 
                    else 
                    {
                        _ = try writer.print(
                            " {f} \n  [shape=point]\"{s}\" -> {f}\n",
                            .{current_code, current_label, current_code}
                        );
                    }
                }
            }

            _ = try writer.write("}\n");

            try writer.flush();

            const pngfilepath = try std.fmt.bufPrint(
                &label_buf,
                "{s}.png",
                .{ png_filepath }
            );

            if (
                build_options.graphviz_dot_path == null 
                or options.render_png == false
            ) {
                return;
            }

            const arg = &[_][]const u8{
                // fetched from build configuration
                build_options.graphviz_dot_path.?,
                "-Tpng",
                png_filepath,
                "-o",
                pngfilepath,
            };

            // render to png
            const result = try std.process.Child.run(
                .{
                    .allocator = arena_allocator,
                    .argv = arg,
                }
            );
            _ = result;
        }

        /// Sort the endpoints in place and return whether they were switched
        /// or not.  Sorting places parent-most node in the
        /// `PathEndPointIndices.source` field and the child-most node in the
        /// `PathEndPointIndices.destination` field.
        ///
        /// Returns an error if there is no path between the nodes.
        ///
        /// This variation operates on `PathEndPointIndices`.
        pub fn sort_endpoint_indices(
            self: @This(),
            endpoints: *PathEndPointIndices,
        ) !bool
        {
            const source_code = self.tree_data.items(.code)[endpoints.source];
            const destination_code = self.tree_data.items(.code)[endpoints.destination];

            if (
                treecode.path_exists(
                    source_code,
                    destination_code,
                ) == false
            )
            {
                errdefer dbg_print(
                    @src(), 
                    "\nERROR\nsource: {f} dest: {f}\n",
                    .{
                        source_code,
                        destination_code,
                    }
                );
                return error.NoPathBetweenNodes;
            }

            // inverted
            if (source_code.code_length > destination_code.code_length)
            {
                std.mem.swap(
                    NodeIndex,
                    &endpoints.source,
                    &endpoints.destination
                );
                return true;
            }
            else 
            {
                return false;
            }
        }

        /// Sort the endpoints in place and return whether they were switched
        /// or not.  Sorting places parent-most node in the
        /// `PathEndPointIndices.source` field and the child-most node in the
        /// `PathEndPointIndices.destination` field.
        ///
        /// Returns an error if there is no path between the nodes, or if
        /// either node is not present in the `BinaryTree`.
        ///
        /// This variation operates on `PathEndPoints`.
        pub fn sort_endpoints(
            self: @This(),
            endpoints: *PathEndPoints,
        ) !bool
        {
            const source_index = self.index_for_node(
                endpoints.source
            ) orelse return error.SourceNotInTree;
            const dest_index = self.index_for_node(
                endpoints.destination
            ) orelse return error.DestinationNotInTree;

            if (source_index == dest_index)
            {
                return false;
            }

            const source_code = self.tree_data.items(.code)[source_index];
            const destination_code = self.tree_data.items(.code)[dest_index];

            if (
                treecode.path_exists(
                    source_code,
                    destination_code,
                ) == false
            )
            {
                errdefer std.debug.print(
                    "ERROR \nERROR\nsource: {f} dest: {f}\n",
                    .{
                        source_code,
                        destination_code,
                    }
                );
                return error.NoPathBetweenNodes;
            }

            // inverted
            if (source_code.code_length > destination_code.code_length)
            {
                const dest = endpoints.destination;
                endpoints.destination = endpoints.source;
                endpoints.source = dest;
                return true;
            }
            else 
            {
                return false;
            }
        }

        /// Compute the path between the endpoints and return a caller-owned
        /// slice of the indices from the source to the destination, inclusive
        /// of the endpoints.
        ///
        /// Will return an error if there is no possible path or if endpoints
        /// are not present in the `BinaryTree`.
        pub fn path(
            self: @This(),
            allocator: std.mem.Allocator,
            endpoints: PathEndPointIndices,
        ) ![]NodeIndex
        { 
            var sorted_endpoint_indices = endpoints;
            const swapped = try self.sort_endpoint_indices(
                &sorted_endpoint_indices
            );

            const result = try self.path_assume_sorted(
                allocator,
                sorted_endpoint_indices.source,
                sorted_endpoint_indices.destination,
            );

            if (swapped)
            {
                std.mem.reverse(NodeIndex, result);
            }

            return result;
        }

        pub fn path_assume_sorted(
            self: @This(),
            allocator: std.mem.Allocator,
            source_index: usize,
            destination_index: usize,
        ) ![]usize
        {
            const tree_slice = self.tree_data.slice();
            const codes = tree_slice.items(.code);
            const parents = tree_slice.items(.parent_index);

            const source_code = codes[source_index];
            const dest_code = codes[destination_index];

            const length = dest_code.code_length - source_code.code_length + 1;

            const result_path = try allocator.alloc(
                usize,
                length,
            );

            fill_path_buffer(
                source_index,
                destination_index,
                result_path,
                parents,
            );

            return result_path;
        }


        /// Generate a text label for a given node based on the format() of the
        /// `NodeType`.
        pub fn node_label(
            buf: []u8,
            ref: NodeType,
            code: treecode.Treecode,
            comptime label_style: LabelStyle,
        ) ![]const u8
        {
            return switch (label_style) {
                .treecode => std.fmt.bufPrint(
                    buf,
                    "{f}.{f}",
                    .{ ref, code, },
                ),
                .hash => std.fmt.bufPrint(
                    buf,
                    "{f}.{x}",
                    .{ ref, code.hash(), },
                ),
            };
        }
    };
}

/// utility function that injects the calling info into the debug print
fn dbg_print(
    src: std.builtin.SourceLocation,
    comptime fmt: []const u8,
    args: anytype,
) void 
{
    if (DEBUG_MESSAGES) 
    {
        std.debug.print(
            "[{s}:{s}:{d}] " ++ fmt ++ "\n",
            .{
                src.file,
                src.fn_name,
                src.line,
            } ++ args,
        );
    }
}

const DummyNode = struct {
    label: enum (u8) { A, B, C, D, E },

    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) !void 
    {
        try writer.print("Node: {s}",.{@tagName(self.label)});
    }
};

test "BinaryTree: build w/ dummy node type and test path"
{
    const allocator = std.testing.allocator;

    //
    // Builds Tree:
    //
    // A
    // |\
    // B
    // |\
    // C D
    //   |\
    //     E
    //

    const DummyTree = BinaryTree(DummyNode);

    var tree: DummyTree = .empty;
    defer tree.deinit(allocator);

    const d_a = DummyNode{ .label = .A };

    const root_code: treecode.Treecode = .EMPTY;

    const root_index = try tree.put(
        allocator,
        d_a,
        .{
            .code = try root_code.clone(allocator),
        }
    );

    const d_b = DummyNode{ .label = .B };
    var b_code = try root_code.clone(allocator);
    try b_code.append(
        allocator,
        .left,
    );
    const b_index = try tree.put(
        allocator,
        d_b,
        .{
            .code = b_code,
            .parent_index = root_index,
        }
    );

    const d_c = DummyNode{ .label = .C };
    var c_code = try b_code.clone(allocator);
    try c_code.append(
        allocator,
        .left,
    );
    const c_index = try tree.put(
        allocator,
        d_c,
        .{
            .code = c_code,
            .parent_index = b_index,
        }
    );

    // add d in the reverse order - add child first and then parent
    var d_code = try b_code.clone(allocator);
    try d_code.append(
        allocator,
        .right,
    );

    // add e without a parent pointer
    const d_e = DummyNode{ .label = .E };
    var e_code = try d_code.clone(allocator);
    try e_code.append(
        allocator,
        .right,
    );
    const e_index = try tree.put(
        allocator,
        d_e,
        .{
            .code = e_code,
        },
    );

    const d_d = DummyNode{ .label = .D };
    const d_index = try tree.put(
        allocator,
        d_d,
        .{
            .code = d_code,
            .parent_index = b_index,
            .child_indices = .{
                null,
                e_index,
            },
        }
    );

    tree.lock_pointers();

    try std.testing.expectEqual(
        e_index,
        tree.tree_data.items(.child_indices)[d_index][
            @intFromEnum(treecode.l_or_r.right)
        ]
    );

    {
        const path_A_C = try tree.path(
            allocator,
            .{
                .source = tree.map_node_to_index.get(d_a).?,
                .destination = tree.map_node_to_index.get(d_c).?,
            }
        );
        defer allocator.free(path_A_C);

        try std.testing.expectEqualSlices(
            NodeIndex,
            &.{ root_index, b_index, c_index, },
            path_A_C,
        );
    }

    {
        const path_A_E = try tree.path(
            allocator,
            .{
                .source = root_index,
                .destination = e_index,
            }
        );
        defer allocator.free(path_A_E);

        try std.testing.expectEqualSlices(
            NodeIndex,
            &.{ root_index, b_index, d_index, e_index },
            path_A_E,
        );
    }

    {
        const path_B_E = try tree.path(
            allocator,
            .{
                .source = b_index,
                .destination = e_index,
            }
        );
        defer allocator.free(path_B_E);

        try std.testing.expectEqualSlices(
            NodeIndex,
            &.{ b_index, d_index, e_index },
            path_B_E,
        );
    }

    // reverse the order of the endpoints
    {
        const path_E_B = try tree.path(
            allocator,
            .{
                .source = e_index,
                .destination = b_index,
            }
        );
        defer allocator.free(path_E_B);

        try std.testing.expectEqualSlices(
            NodeIndex,
            &.{ e_index, d_index, b_index },
            path_E_B,
        );
    }

    // single node
    {
        const path_E_E = try tree.path(
            allocator,
            .{
                .source = e_index,
                .destination = e_index,
            }
        );
        defer allocator.free(path_E_E);

        try std.testing.expectEqualSlices(
            NodeIndex,
            &.{ e_index, },
            path_E_E,
        );
    }

    // invalid path end points
    {
        try std.testing.expectError(
            error.NoPathBetweenNodes,
            tree.path(
                allocator,
                .{
                    .source = c_index,
                    .destination = e_index,
                }
            )        
        );
    }

    try tree.write_dot_graph(
        allocator,
        "/var/tmp/binary_tree_test.dot",
       "Binary_Tree_Test", 
       .{
           .label_style = .treecode,
           .render_png = true,
       },
    );
}

fn fill_path_buffer(
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

