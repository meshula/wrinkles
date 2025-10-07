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

var ROOT_WORDS = [_]treecode.TreecodeWord{treecode.MARKER}; 

/// static code for the root of the graph
const ROOT_CODE = treecode.Treecode {
    .words = &ROOT_WORDS,
};

/// Bidirectional map of `treecode.Treecode` to `core.SpaceReference`.  This
/// allows:
///
/// * Random access by path of `core.SpaceReference`s in an OTIO temporal
///   hierarchy
/// * Fetching of a path from one `core.SpaceReference` to another, by walking
///   along the `treecode.Treecode`s.
/// * Construction of `core.ProjectionOperator` based on end points in this
///   mapping
pub fn Map(
    comptime GraphNodeType: type,
) type
{
    return struct {
        /// mapping of `GraphNodeType` to `treecode.Treecode`
        /// NOTE: should contain the same `treecode.Treecode`s as the ones present
        ///       in `map_code_to_space`.  Only one of the two mappings will be
        ///       mappings' treecodes will have deinit() called.
        map_space_to_code:std.AutoHashMapUnmanaged(
                              GraphNodeType,
                              treecode.Treecode,
                          ) = .empty,
        /// mapping of `treecode.Treecode` to `GraphNodeType`
        map_code_to_space:treecode.TreecodeHashMap(GraphNodeType) = .empty,

        const MapType = @This();

        pub fn deinit(
            self: @This(),
            allocator: std.mem.Allocator,
        ) void 
        {
            // build a mutable alias of self
            var mutable_self = self;

            var code_iter = (
                mutable_self.map_space_to_code.valueIterator()
            );

            while (code_iter.next())
                |code|
                { 
                    code.deinit(allocator);
                }

            // free the guts
            mutable_self.map_space_to_code.unlockPointers();
            mutable_self.map_space_to_code.deinit(allocator);
            mutable_self.map_code_to_space.unlockPointers();
            mutable_self.map_code_to_space.deinit(allocator);
            // self.map_space_to_code.deinit(allocator);
            // self.map_code_to_space.deinit(allocator);
        }

        /// return the root space of this topological map
        pub fn root(
            self: @This(),
        ) GraphNodeType 
        {
            // should always have a root object
            return self.map_code_to_space.get(ROOT_CODE) orelse unreachable;
        }

        /// Serialize this graph to dot and then use graphviz to convert that dot
        /// to a png.  Will create /var/tmp/`png_filepath`.dot.
        ///
        /// If graphviz is disabled in the build, will still write the .dot file,
        /// but will return before attempting to call dot on it to convert it to a 
        /// png.
        pub fn write_dot_graph(
            self:@This(),
            allocator: std.mem.Allocator,
            /// path to the desired resulting png file
            png_filepath: []const u8,
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

            var buf: [16*1024]u8 = undefined;
            var file_writer = file.writer(&buf);
            var writer = &file_writer.interface;

            _ = try writer.write("digraph OTIO_TopologicalMap {\n");

            var stack: std.ArrayList(MapType.PathNode) = .empty;

            try stack.append(
                arena_allocator,
                .{
                    .space = self.root(),
                    .code = ROOT_CODE,
                },
                );

            var label_buf: [1024]u8 = undefined;
            var next_label_buf: [1024]u8 = undefined;

            while (stack.pop()) 
                |current|
                {
                    const current_label = try node_label(
                        &label_buf,
                        current.space,
                        current.code,
                        options.label_style,
                    );

                    // left
                    {
                        var left = try current.code.clone(arena_allocator);
                        try left.append(arena_allocator, .left);

                        if (self.map_code_to_space.get(left)) 
                            |next| 
                            {
                                @branchHint(.likely);

                                const next_label = try node_label(
                                    &next_label_buf,
                                    next,
                                    left,
                                    options.label_style,
                                );
                                _ = try writer.print(
                                    "  \"{s}\" -> \"{s}\"\n",
                                    .{current_label, next_label}
                                );
                                try stack.append(
                                    arena_allocator,
                                    .{
                                        .space = next,
                                        .code = left
                                    }
                                );
                            } 
                        else 
                        {
                            _ = try writer.print(
                                " {f} \n  [shape=point]\"{s}\" -> {f}\n",
                                .{current.code, current_label, current.code}
                            );
                        }
                    }

                    // right
                    {
                        var right = try current.code.clone(arena_allocator);
                        try right.append(arena_allocator, .right);

                        if (self.map_code_to_space.get(right)) 
                            |next| 
                            {
                                const next_label = try node_label(
                                    &next_label_buf,
                                    next,
                                    right,
                                    options.label_style,
                                );
                                _ = try writer.print(
                                    "  \"{s}\" -> \"{s}\"\n",
                                    .{current_label, next_label},
                                );
                                try stack.append(
                                    arena_allocator,
                                    .{
                                        .space = next,
                                        .code = right
                                    }
                                );
                            } 
                        else
                        {
                            _ = try writer.print(
                                " {f} \n  [shape=point]\"{s}\" -> {f}\n",
                                .{current.code, current_label, current.code}
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

        /// Check to see if `endpoints` need to be swapped (iteration always
        /// proceeds from parent to child).  If needed, will swap endpoints in
        /// place and return `true` to indicate this happened.
        ///
        /// Will return an error if there is no path between the endpoints or one
        /// of the endpoints is not present in the mapping.
        pub fn sort_endpoints(
            self: @This(),
            endpoints: *PathEndPoints,
        ) !bool
        {
            var source_code = (
                if (self.map_space_to_code.get(endpoints.source)) 
                |code| 
                code
                else return error.SourceNotInMap
            );

            var destination_code = (
                if (self.map_space_to_code.get(endpoints.destination)) 
                |code| 
                code
                else return error.DestinationNotInMap
            );

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
                dbg_print(@src(), 
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

        /// A pair of space and code along a path within the `Map`.
        const PathNode = struct {
            space: GraphNodeType,
            code: treecode.Treecode,

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

            stack: std.ArrayList(PathNode) = .empty,
            maybe_current: ?PathNode,
            maybe_previous: ?PathNode,
            map: *const MapType,
            allocator: std.mem.Allocator,
            maybe_source: ?PathNode = null,
            maybe_destination: ?PathNode = null,

            /// Walk exhaustively, depth-first, starting from the root
            /// (treecode.MARKER) space down.
            pub fn init(
                allocator: std.mem.Allocator,
                map: *const MapType,
            ) !IteratorType
            {
                return IteratorType.init_from(
                    allocator,
                    map, 
                    map.root()
                );
            }


            pub fn init_from(
                allocator: std.mem.Allocator,
                map: *const MapType,
                /// a source in the map to start the map from
                source: GraphNodeType,
            ) !IteratorType
            {
                const start_code = (
                    map.map_space_to_code.get(source) 
                    orelse return error.NotInMapError
                );

                var result = IteratorType{
                    .stack = .{},
                    .maybe_current = null,
                    .maybe_previous = null,
                    .map = map,
                    .allocator = allocator,
                    .maybe_source = .{
                        .code = start_code,
                        .space = source,
                    },
                };

                try result.stack.append(
                    allocator,
                    .{
                        .space = source,
                        .code = try start_code.clone(allocator),
                    }
                );

                return result;
            }

            /// an iterator that walks from the source node to the destination node
            pub fn init_from_to(
                allocator: std.mem.Allocator,
                map: *const MapType,
                endpoints: PathEndPoints,
            ) !IteratorType
            {
                var source_code = (
                    if (map.map_space_to_code.get(endpoints.source)) 
                    |code| 
                    code
                    else return error.SourceNotInMap
                );

                var destination_code = (
                    if (map.map_space_to_code.get(endpoints.destination)) 
                    |code| 
                    code
                    else return error.DestinationNotInMap
                );

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

                const needs_inversion = (
                    source_code.code_length() > destination_code.code_length()
                );

                if (needs_inversion) {
                    const tmp = source_code;
                    source_code = destination_code;
                    destination_code = tmp;
                }

                var iterator = (
                    try IteratorType.init_from(
                        allocator,
                        map, 
                        endpoints.source,
                    )
                );

                iterator.maybe_destination = .{
                    .code = (
                        map.map_space_to_code.get(endpoints.destination) 
                        orelse return error.SpaceNotInMap
                    ),
                    .space = endpoints.destination,
                };

                return iterator;
            }

            pub fn deinit(
                self: *@This(),
                allocator: std.mem.Allocator,
            ) void
            {
                if (self.maybe_previous)
                    |n|
                {
                    n.code.deinit(allocator);
                }
                if (self.maybe_current)
                    |n|
                {
                    n.code.deinit(allocator);
                }
                for (self.stack.items)
                    |n|
                {
                    n.code.deinit(allocator);
                }
                self.stack.deinit(allocator);
            }

            pub fn next(
                self: *@This(),
                allocator: std.mem.Allocator,
            ) !bool
            {
                if (self.stack.items.len == 0) {
                    return false;
                }

                if (self.maybe_previous)
                    |prev|
                {
                    prev.code.deinit(allocator);
                }
                self.maybe_previous = self.maybe_current;

                self.maybe_current = self.stack.pop();
                const current = self.maybe_current.?;

                // if there is a destination, walk in that direction. Otherwise, walk
                // exhaustively
                const next_steps : []const treecode.l_or_r = (
                    if (self.maybe_destination) |dest| &[_]treecode.l_or_r{ 
                        current.code.next_step_towards(dest.code)
                    }
                    else &.{ .left,.right }
                );

                for (next_steps)
                    |next_step|
                {
                    var next_code = try current.code.clone(allocator);
                    try next_code.append(allocator, next_step);

                    if (self.map.map_code_to_space.get(next_code))
                        |next_node|
                    {
                        try self.stack.append(
                            allocator,
                            .{
                                .space = next_node,
                                .code = next_code,
                            }
                        );
                    }
                    else {
                        next_code.deinit(allocator);
                    }
                }

                return self.maybe_current != null;
            }
        };

        /// generate a text label based on a space reference and treecode
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


pub const DEBUG_MESSAGES= (
    build_options.debug_graph_construction_trace_messages 
    or build_options.debug_print_messages 
);

/// utility function that injects the calling info into the debug print
pub fn dbg_print(
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
