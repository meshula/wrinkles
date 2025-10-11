const std = @import("std");
const build_options = @import("build_options");

const treecode = @import("treecode.zig");

/// annotate the graph algorithms
// const GRAPH_CONSTRUCTION_TRACE_MESSAGES = true;
const GRAPH_CONSTRUCTION_TRACE_MESSAGES = (
    build_options.debug_graph_construction_trace_messages
);

/// Which style to render node labels in, as binary codes or hashes.  Codes are
/// more readable, but make large graphs impossible to read.
const LabelStyle = enum(u1) { treecode, hash };

const NodeIndex = usize;

const ROOT_CODE:treecode.Treecode = .EMPTY;

/// Bidirectional map of `treecode.Treecode` to a parameterized
/// `GraphNodeType` (presumably nodes in some graph).  This allows:
///
/// * Random access by path of `GraphNodeType`s in a hierarchy by path
/// * Fetching of a path from one `GraphNodeType` to another, by walking
///   along the `treecode.Treecode`s, including a PathIterator for walking
///   along computed paths.
pub fn Map(
    comptime GraphNodeType: type,
) type
{
    return struct {
        map_space_to_index:std.AutoHashMapUnmanaged(
                              GraphNodeType,
                              NodeIndex,
                          ) = .empty,
        /// mapping of `treecode.Treecode` to `NodeIndex`
        map_code_to_index:treecode.TreecodeHashMap(NodeIndex) = .empty,

        nodes:NodesListType = .empty,
        const MapType = @This();
        const NodesListType = std.MultiArrayList(PathNode);

        pub fn deinit(
            self: @This(),
            allocator: std.mem.Allocator,
        ) void 
        {
            // build a mutable alias of self
            var mutable_self = self;

            for (self.nodes.items(.code))
                |code|
            { 
                code.deinit(allocator);
            }

            // free the guts
            mutable_self.map_space_to_index.unlockPointers();
            mutable_self.map_space_to_index.deinit(allocator);
            mutable_self.map_code_to_index.unlockPointers();
            mutable_self.map_code_to_index.deinit(allocator);

            mutable_self.nodes.deinit(allocator);
        }

        pub fn lock_pointers(
            self: *@This(),
        ) void
        {
            self.map_code_to_index.lockPointers();
            self.map_space_to_index.lockPointers();

            // @TODO: could switch the implementation over to .Slice() here
        }

        /// add the PathNode to the map and return the newly created index
        pub fn put(
            self: *@This(),
            allocator: std.mem.Allocator,
            node: PathNode,
        ) !NodeIndex
        {
            const new_index = self.nodes.len;

            try self.nodes.append(allocator, node);

            try self.map_code_to_index.put(
                allocator,
                node.code,
                new_index,
            );
            try self.map_space_to_index.put(
                allocator,
                node.space,
                new_index,
            );

            if (node.parent_index)
                |parent_index|
            {
                const parent_code = self.nodes.items(.code)[parent_index];
                const dir = parent_code.next_step_towards(node.code);
                var child_indices = &self.nodes.items(
                    .child_indices
                )[parent_index];
                child_indices[@intFromEnum(dir)] = new_index;
            }
            
            return new_index;
        }

        pub fn get_space(
            self: @This(),
            code: treecode.Treecode,
        ) ?GraphNodeType
        {
            if (self.map_code_to_index.get(code))
                |index|
            {
                return self.nodes.items(.space)[index];
            }

            return null;
        }

        pub fn get_code(
            self: @This(),
            space: GraphNodeType,
        ) ?treecode.Treecode
        {
            if (self.map_space_to_index.get(space))
                |index|
            {
                return self.nodes.items(.code)[index];
            }

            return null;
        }

        /// return the root space associated with the `ROOT_CODE`
        pub fn root(
            self: @This(),
        ) GraphNodeType 
        {
            // should always have a root object, and root object should always
            // be the first entry in the nodes list
            return self.nodes.items(.space)[0];
        }

        /// Serialize this graph to dot and then use graphviz to convert that
        /// dot to a png.  Will create /var/tmp/`png_filepath`.dot.
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

            const nodes = self.nodes.slice();

            for (0..self.nodes.len)
                |current_index|
            {
                const current_code = nodes.items(.code)[current_index];

                const current_label = try node_label(
                    &label_buf,
                    nodes.items(.space)[current_index],
                    current_code,
                    options.label_style,
                );

                const current_children = (
                    self.nodes.items(.child_indices)[current_index]
                );
                for (current_children)
                    |maybe_child_index|
                {
                    if (maybe_child_index)
                        |child_index|
                    {
                        const next_label = try node_label(
                            &next_label_buf,
                            nodes.items(.space)[child_index],
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

            const arg = &[_][]const u8{
                // fetched from build configuration
                build_options.graphviz_dot_path.?,
                "-Tpng",
                png_filepath,
                "-o",
                pngfilepath,
            };

            if (
                build_options.graphviz_dot_path == null 
                or options.render_png == false
            ) {
                return;
            }

            // render to png
            const result = try std.process.Child.run(
                .{
                    .allocator = arena_allocator,
                    .argv = arg,
                }
            );
            _ = result;
        }

        pub fn sort_endpoint_indices(
            self: @This(),
            endpoints: *PathEndPointIndices,
        ) !bool
        {
            var source_code = self.nodes.items(.code)[endpoints.source];
            var destination_code = self.nodes.items(.code)[endpoints.destination];

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
                return error.NoPathBetweenSpaces;
            }

            // inverted
            if (source_code.code_length() > destination_code.code_length())
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

        /// Check to see if `endpoints` need to be swapped (iteration always
        /// proceeds from parent to child).  If needed, will swap endpoints in
        /// place and return `true` to indicate this happened.
        ///
        /// Will return an error if there is no path between the endpoints or
        /// one of the endpoints is not present in the mapping.
        pub fn sort_endpoints(
            self: @This(),
            endpoints: *PathEndPoints,
        ) !bool
        {
            const source_index = self.map_space_to_index.get(
                endpoints.source
            ) orelse return error.SourceNotInMap;
            const dest_index = self.map_space_to_index.get(
                endpoints.destination
            ) orelse return error.DestNotInMap;

            if (source_index == dest_index)
            {
                return false;
            }

            var source_code = self.nodes.items(.code)[source_index];
            var destination_code = self.nodes.items(.code)[dest_index];

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
                return error.NoPathBetweenSpaces;
            }

            // inverted
            if (source_code.code_length() > destination_code.code_length())
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

        /// Build a projection operator that projects from the args.source to
        /// args.destination spaces and print to the debug printer the structure.
        pub fn debug_print_time_hierarchy(
            self: @This(),
            allocator: std.mem.Allocator,
            endpoints_arg: PathEndPoints,
        ) !void 
        {
            var endpoints = endpoints_arg;
            _ = try self.sort_endpoints(&endpoints);

            var iter = (
                try MapType.PathIterator.init_from_to(
                    allocator,
                    &self,
                    endpoints,
                )
            );
            defer iter.deinit();

            if (GRAPH_CONSTRUCTION_TRACE_MESSAGES) {
                dbg_print(
                    @src(), 
                    "starting walk from: {f} to: {f}\n",
                    .{
                        iter.maybe_source.?.space,
                        iter.maybe_destination.?.space,
                    }
                );
            }

            // walk from current_code towards destination_code
            while (
                try iter.next()
                and iter.maybe_current.?.code.eql(
                    iter.maybe_destination.?.code
                ) == false
            ) 
            {
                const dest_to_current = (
                    try self.build_projection_operator(
                        allocator,
                        .{
                            .source = iter.maybe_destination.?.space,
                            .destination = iter.maybe_current.?.space,
                        },
                    )
                );

                dbg_print(
                    @src(), 
                    "space: {f}\n"
                    ++ "      local:  {f}\n",
                    .{ 
                        iter.maybe_current.?.space,
                        dest_to_current.src_to_dst_topo.output_bounds(),
                    },
                );
            }

            dbg_print(
                @src(), 
                "space: {f}\n"
                ++ "      destination:  {f}\n",
                .{ 
                    iter.maybe_current.?.space,
                    try iter.maybe_destination.?.space.ref.bounds_of(
                        allocator,
                        iter.maybe_destination.?.space.label
                    ),
                },
            );
        }

        /// Encoding of the end points of a path between `GraphNodeType`s in the 
        /// `Map`.
        pub const PathEndPoints = struct {
            source: GraphNodeType,
            destination: GraphNodeType,
        };

        const PathEndPointIndices = struct {
            source: NodeIndex,
            destination: NodeIndex,
        };

        /// A pair of space and code along a path within the `Map`.
        pub const PathNode = struct {
            space: GraphNodeType,
            code: treecode.Treecode,
            parent_index: ?NodeIndex = null,
            child_indices: [2]?NodeIndex = .{null, null},

            pub fn format(
                self: @This(),
                writer: *std.Io.Writer,
            ) !void 
            {
                try writer.print(
                    "Node(.space: {f}, .code: {f})",
                    .{
                        self.space,
                        self.code,
                    }
                );
            }
        };

        /// Walks across a `MapType` by walking through the treecodes and
        /// finding the ones that are present in the `MapType`.
        pub const PathIterator = struct{
            pub const IteratorType = @This();

            stack: std.ArrayList(NodeIndex) = .empty,
            maybe_current: ?NodeIndex,
            nodes: NodesListType.Slice,
            allocator: std.mem.Allocator,
            maybe_source: ?NodeIndex = null,
            maybe_destination: ?NodeIndex = null,

            /// Walk exhaustively, depth-first, starting from the root
            /// (treecode.MARKER) space down.
            pub fn init(
                allocator: std.mem.Allocator,
                map: *const MapType,
            ) !IteratorType
            {
                return IteratorType.init_from_index(
                    allocator,
                    map, 
                    0,
                );
            }

            pub fn init_from(
                allocator: std.mem.Allocator,
                map: *const MapType,
                /// a source in the map to start the map from
                source: GraphNodeType,
            ) !IteratorType
            {
                const start_index = (
                    map.map_space_to_index.get(source) 
                    orelse return error.NotInMapError
                );

                return IteratorType.init_from_index(
                    allocator,
                    map,
                    start_index,
                );
            }

            fn init_from_index(
                allocator: std.mem.Allocator,
                map: *const MapType,
                /// a source in the map to start the map from
                start_index: NodeIndex,
            ) !IteratorType
            {
                var result = IteratorType{
                    .stack = .empty,
                    .maybe_current = null,
                    .nodes = map.nodes.slice(),
                    .allocator = allocator,
                    .maybe_source = start_index,
                };

                try result.stack.append(allocator, start_index);

                return result;
            }

            /// an iterator that walks from the source node to the destination node
            pub fn init_from_to(
                allocator: std.mem.Allocator,
                map: *const MapType,
                endpoints: PathEndPoints,
            ) !IteratorType
            {
                const source_index = (
                    if (map.map_space_to_index.get(endpoints.source)) 
                    |index| 
                    index
                    else return error.SourceNotInMap
                );

                const destination_index = (
                    if (map.map_space_to_index.get(endpoints.destination)) 
                    |index| 
                    index
                    else return error.SourceNotInMap
                );

                var endpoint_indices = PathEndPointIndices{
                    .source = source_index,
                    .destination = destination_index,
                };

                _ = try map.sort_endpoint_indices(&endpoint_indices);

                var iterator = (
                    try IteratorType.init_from_index(
                        allocator,
                        map, 
                        endpoint_indices.source,
                    )
                );

                iterator.maybe_destination = endpoint_indices.destination;

                return iterator;
            }

            pub fn deinit(
                self: *@This(),
                allocator: std.mem.Allocator,
            ) void
            {
                self.stack.deinit(allocator);
            }

            pub fn next(
                self: *@This(),
                allocator: std.mem.Allocator,
            ) !?PathNode
            {
                if (self.stack.items.len == 0) {
                    self.maybe_current = null;
                    return null;
                }

                // there has to be a current node, since the length is > 0
                self.maybe_current = self.stack.pop();
                const current_index = self.maybe_current.?;

                if (self.maybe_destination)
                    |dest|
                {
                    if (current_index == dest) {
                        self.stack.clearAndFree(allocator);
                        return self.nodes.get(current_index);
                    }
                }

                const current_code = self.nodes.items(.code)[current_index];

                // if there is a destination, walk in that direction.
                // Otherwise, walk exhaustively
                const next_steps : []const treecode.l_or_r = (
                    if (self.maybe_destination) 
                    |dest| 
                    &[_]treecode.l_or_r{ 
                        current_code.next_step_towards(
                            self.nodes.items(.code)[dest]
                        )
                    }
                    else &.{ .left,.right }
                );

                const child_indices = (
                    self.nodes.items(.child_indices)[current_index]
                );

                for (next_steps)
                    |next_step|
                {
                    errdefer std.debug.print(
                        "trying to walk from {d} to {?d}\n",
                        .{
                            current_index,
                            self.maybe_destination,
                        }
                    );
                    if (child_indices[@intFromEnum(next_step)])
                        |next_index|
                    {
                        try self.stack.append(
                            allocator,
                            next_index,
                        );
                    }
                    else if (self.maybe_destination != null)
                    {
                        return error.InvalidGraphMissingConnection;
                    }
                }

                return self.nodes.get(current_index);
            }
        };

        /// generate a text label based on the format() of the `GraphNodeType`
        pub fn node_label(
            buf: []u8,
            ref: GraphNodeType,
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

const DEBUG_MESSAGES= (
    build_options.debug_graph_construction_trace_messages 
    or build_options.debug_print_messages 
);

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
