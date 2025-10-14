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

pub const PathNodeIndex = usize;
pub const SpaceNodeIndex = usize;

const ROOT_CODE:treecode.Treecode = .EMPTY;

/// Bidirectional map of `treecode.Treecode` to a parameterized
/// `SpaceNodeType` (presumably nodes in some graph).  This allows:
///
/// * Random access by path of `GraphNodeType`s in a hierarchy by path
/// * Fetching of a path from one `GraphNodeType` to another, by walking
///   along the `treecode.Treecode`s, including a PathIterator for walking
///   along computed paths.
pub fn Map(
    comptime SpaceNodeType: type,
) type
{
    return struct {
        /// Encoding of the end points of a path between `GraphNodeType`s in the 
        /// `Map`.
        pub const PathEndPoints = struct {
            source: SpaceNodeType,
            destination: SpaceNodeType,
        };

        pub const PathEndPointIndices = struct {
            source: PathNodeIndex,
            destination: PathNodeIndex,
        };

        /// A pair of space and code along a path within the `Map`.
        pub const PathNode = struct {
            code: treecode.Treecode,
            parent_index: ?PathNodeIndex = null,
            child_indices: [2]?PathNodeIndex = .{null, null},

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

        const MapType = @This();
        pub const SpaceNodeList = std.MultiArrayList(SpaceNodeType);
        const PathNodesList = std.MultiArrayList(PathNode);

        map_space_to_path_index: std.AutoHashMapUnmanaged(
            SpaceNodeType,
            PathNodeIndex,
        ),
        path_nodes:PathNodesList,
        space_nodes:SpaceNodeList,

        pub const empty = MapType{
            .map_space_to_path_index = .empty,
            .path_nodes = .empty,
            .space_nodes = .empty,
        };

        pub fn deinit(
            self: @This(),
            allocator: std.mem.Allocator,
        ) void 
        {
            // build a mutable alias of self
            var mutable_self = self;

            for (self.path_nodes.items(.code))
                |code|
            { 
                code.deinit(allocator);
            }

            // free the guts
            mutable_self.map_space_to_path_index.unlockPointers();
            mutable_self.map_space_to_path_index.deinit(allocator);

            mutable_self.path_nodes.deinit(allocator);
            mutable_self.space_nodes.deinit(allocator);
        }

        pub fn lock_pointers(
            self: *@This(),
        ) void
        {
            self.map_space_to_path_index.lockPointers();

            // @TODO: could switch the implementation over to .Slice() here
        }

        pub fn ensure_unused_capacity(
            self: *@This(),
            allocator: std.mem.Allocator,
            capacity: usize,
        ) !void
        {
            try self.path_nodes.ensureUnusedCapacity(
                allocator,
                capacity
            );
            try self.space_nodes.ensureUnusedCapacity(
                allocator,
                capacity
            );
            try self.map_space_to_path_index.ensureUnusedCapacity(
                allocator,
                @intCast(capacity)
            );
        }

        /// add the PathNode to the map and return the newly created index
        pub fn put(
            self: *@This(),
            allocator: std.mem.Allocator,
            node: struct{
                code: treecode.Treecode,
                space: SpaceNodeType,
                parent_index: ?PathNodeIndex,
            },
        ) !PathNodeIndex
        {

            try self.space_nodes.append(allocator, node.space);

            const new_path_index = self.path_nodes.len;
            try self.path_nodes.append(
                allocator,
                .{
                    .code = node.code,
                    .parent_index = node.parent_index,
                }
            );

            try self.map_space_to_path_index.put(
                allocator,
                node.space,
                new_path_index,
            );

            if (node.parent_index)
                |parent_index|
            {
                const parent_code = self.path_nodes.items(.code)[parent_index];
                const dir = parent_code.next_step_towards(node.code);
                var child_indices = &self.path_nodes.items(
                    .child_indices
                )[parent_index];
                child_indices[@intFromEnum(dir)] = new_path_index;
            }
            
            return new_path_index;
        }

        /// add the PathNode to the map and return the newly created index
        pub fn put_assumes_capacity(
            self: *@This(),
            node: struct{
                code: treecode.Treecode,
                space: SpaceNodeType,
                parent_index: ?PathNodeIndex,
            },
        ) PathNodeIndex
        {

            self.space_nodes.appendAssumeCapacity(node.space);

            const new_path_index = self.path_nodes.len;
            self.path_nodes.appendAssumeCapacity(
                .{
                    .code = node.code,
                    .parent_index = node.parent_index,
                }
            );

            self.map_space_to_path_index.putAssumeCapacity(
                node.space,
                new_path_index,
            );

            if (node.parent_index)
                |parent_index|
            {
                const parent_code = self.path_nodes.items(.code)[parent_index];
                const dir = parent_code.next_step_towards(node.code);
                var child_indices = &self.path_nodes.items(
                    .child_indices
                )[parent_index];
                child_indices[@intFromEnum(dir)] = new_path_index;
            }
            
            return new_path_index;
        }

        pub fn get_code(
            self: @This(),
            space: SpaceNodeType,
        ) ?treecode.Treecode
        {
            if (self.map_space_to_path_index.get(space))
                |index|
            {
                return self.path_nodes.items(.code)[index];
            }

            return null;
        }

        pub fn index_from_space(
            self: @This(),
            space: SpaceNodeType,
        ) ?PathNodeIndex
        {
            return self.map_space_to_path_index.get(space);
        }

        /// return the root space associated with the `ROOT_CODE`
        pub fn root(
            self: @This(),
        ) SpaceNodeType 
        {
            // should always have a root object, and root object should always
            // be the first entry in the nodes list
            return self.space_nodes.get(0);
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

            const nodes = self.path_nodes.slice();

            for (0..self.path_nodes.len)
                |current_index|
            {
                const current_code = nodes.items(.code)[current_index];

                const current_label = try node_label(
                    &label_buf,
                    self.space_nodes.get(current_index),
                    current_code,
                    options.label_style,
                );

                const current_children = (
                    self.path_nodes.items(.child_indices)[current_index]
                );
                for (current_children)
                    |maybe_child_index|
                {
                    if (maybe_child_index)
                        |child_index|
                    {
                        const next_label = try node_label(
                            &next_label_buf,
                            self.space_nodes.get(child_index),
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

        pub fn sort_endpoint_indices(
            self: @This(),
            endpoints: *PathEndPointIndices,
        ) !bool
        {
            const source_code = self.path_nodes.items(.code)[endpoints.source];
            const destination_code = self.path_nodes.items(.code)[endpoints.destination];

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
            if (source_code.code_length > destination_code.code_length)
            {
                std.mem.swap(
                    PathNodeIndex,
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
            const source_index = self.index_from_space(
                endpoints.source
            ) orelse return error.SourceNotInMap;
            const dest_index = self.index_from_space(
                endpoints.destination
            ) orelse return error.DestNotInMap;

            if (source_index == dest_index)
            {
                return false;
            }

            const source_code = self.path_nodes.items(.code)[source_index];
            const destination_code = self.path_nodes.items(.code)[dest_index];

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

        pub fn nodes_under(
            self: @This(),
            allocator: std.mem.Allocator,
            start: SpaceNodeType,
        ) ![]PathNodeIndex
        {
            const nodes = self.path_nodes.slice();
            const start_index = self.index_from_space(start).?;

            var result: std.ArrayList(PathNodeIndex) = .empty;
            try result.ensureTotalCapacity(allocator, nodes.len);

            var stack: std.ArrayList(PathNodeIndex) = .empty;
            defer stack.deinit(allocator);
            try stack.ensureTotalCapacity(
                allocator,
                nodes.len
            );

            stack.appendAssumeCapacity(start_index);

            while (stack.pop())
                |next|
            {
                result.appendAssumeCapacity(next);
                const maybe_children = nodes.items(.child_indices)[next];
                if (maybe_children[0])
                    |child|
                {
                    stack.appendAssumeCapacity(child);
                }
                if (maybe_children[1])
                    |child|
                {
                    stack.appendAssumeCapacity(child);
                }
            }

            return result.toOwnedSlice(allocator);
        }

        /// return the indices inclusive of the endpoints
        pub fn path(
            self: @This(),
            allocator: std.mem.Allocator,
            endpoints: PathEndPointIndices,
        ) ![]PathNodeIndex
        { 
            var sorted_endpoint_indices = endpoints;
            const swapped = try self.sort_endpoint_indices(
                &sorted_endpoint_indices
            );

            const nodes = self.path_nodes.slice();

            const source_code = (
                nodes.items(.code)[sorted_endpoint_indices.source]
            );
            const destination_code = (
                nodes.items(.code)[sorted_endpoint_indices.destination]
            );

            var result: std.ArrayList(PathNodeIndex) = .empty;
            try result.ensureTotalCapacity(
                allocator,
                (
                   destination_code.code_length 
                   - source_code.code_length 
                   // + 1 for the start point
                   + 1
                ),
            );
            result.appendAssumeCapacity(sorted_endpoint_indices.source);

            var current: PathNodeIndex = sorted_endpoint_indices.source;
            var current_code = source_code;
            while (current != sorted_endpoint_indices.destination)
            {
                const next_step = current_code.next_step_towards(destination_code);

                const next = nodes.items(.child_indices)[current][
                    @intFromEnum(next_step)
                ];

                result.appendAssumeCapacity(next.?);

                current = next.?;
                current_code = nodes.items(.code)[current];
            }

            if (swapped)
            {
                std.mem.reverse(PathNodeIndex, result.items);
            }

            return try result.toOwnedSlice(allocator);
        }

        /// generate a text label based on the format() of the `SpaceNodeType`
        pub fn node_label(
            buf: []u8,
            ref: SpaceNodeType,
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
