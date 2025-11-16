//! Includes the `ProjectionBuilder` Struct - an acceleration structure for
//! computing projections over large topologies.

const std = @import("std");

const build_options = @import("build_options");

const opentime = @import("opentime");
const topology_m = @import("topology");
const treecode = @import("treecode");

const GRAPH_CONSTRUCTION_TRACE_MESSAGES = (
    build_options.debug_graph_construction_trace_messages
);

/// Acceleration structure that decomposes the tree of spaces under `source`
/// into a list of intervals in the source space associated with the
/// transformation into the terminal space.
///
/// Given a timeline with two tracks:
///
/// ```
///     0     3     6
/// t1: [ c1 )[  c2 )
/// t2: [    c3     )
/// ```
///
/// Creates a flat data structure:
///
/// ```
/// [
///     { [0, 3): -> c1, -> c3 },
///     { [3, 6): -> c2, -> c3 },
/// ]
/// ```
///
/// This allows fast construction of projection operators over large trees.
///
/// Includes a `cache` for interior transformations and a tree of all the
/// spaces under the `source` space.
pub fn ProjectionBuilder(
    /// A reference to a single space in the hierarchy
    comptime SpaceReferenceType: type,
    /// An operator which can project between different points in the hierarchy
    comptime ProjectionOperatorType: type,
    /// A function which can be called and given a root space to generate a
    /// `treecode.BinaryTree` specialized over the `SpaceReferenceType` of all
    /// spaces under the source space.
    comptime tree_builder_fn: (
        fn (
            std.mem.Allocator,
            SpaceReferenceType
        ) anyerror!treecode.BinaryTree(SpaceReferenceType)
    )
) type
{
    return struct {
        /// Alias to this type
        pub const ProjectionBuilderType = @This();
        /// Alias to the `treecode.BinaryTree` specialization for
        /// `SpaceReferenceType` 
        pub const TreeType = treecode.BinaryTree(SpaceReferenceType);

        /// index of the root node
        const SOURCE_INDEX = 0;

        // @TODO: remove these
        pub const NodeIndex = treecode.binary_tree.NodeIndex;
        pub const SpaceNodeIndex = treecode.binary_tree.NodeIndex;

        /// the source space for the ProjectionBuilder
        source: SpaceReferenceType,
        /// Tree of all spaces underneath the `source` space.
        tree: TreeType,
        /// cache of intermediate topologies inside the tree
        cache: SingleSourceTopologyCache,

        /// Linking the mapping to the destination space in `tree`
        mappings: std.MultiArrayList(
            struct {
                /// index of the target space in `tree`
                destination: SpaceNodeIndex,
                /// mapping that projects from `source` space to this space
                mapping: topology_m.Mapping,
            },
        ),

        /// Sorted list of intervals and which mappings they associate with.
        /// Multiple intervals can be associated with the same mapping.
        intervals: std.MultiArrayList(
            struct {
                mapping_index: []NodeIndex,
                input_bounds: opentime.ContinuousInterval,
            },
        ),

        /// Construct a `ReferenceTopologyType` rooted at `source_reference`.
        pub fn init_from(
            allocator_parent: std.mem.Allocator,
            source_reference: SpaceReferenceType,
        ) !ProjectionBuilderType
        {
            var arena = std.heap.ArenaAllocator.init(
                allocator_parent,
            );
            defer arena.deinit();
            const allocator_arena = arena.allocator();

            // Build out the hierarchy of all the coordinate spaces
            ///////////////////////////////
            const tree = (
                try tree_builder_fn(
                // try temporal_tree.build_temporal_tree(
                    allocator_parent,
                    source_reference,
                )
            );

            // Initialize a cache for topologies
            ///////////////////////////////
            const cache = (
                try SingleSourceTopologyCache.init(
                    allocator_parent,
                    tree,
                )
            );

            var self: ProjectionBuilderType = .{
                .source = source_reference,
                .mappings = .empty,
                .intervals = .empty,
                .tree = tree,
                .cache = cache,
            };

            // Assemble the components
            //////////////////////
            const start_or_end = enum(u1) { start, end };

            // to sort and split the intervals
            var unsorted_vertices : std.MultiArrayList(
                struct{ 
                    ordinate: opentime.Ordinate,
                    interval_index: NodeIndex,
                    kind: start_or_end,
                },
            ) = .empty;
            defer unsorted_vertices.deinit(allocator_arena);

            // Gather up all the operators and intervals
            /////////////
            const tree_nodes = tree.tree_data.slice();

            const start_index = tree.index_for_node(
                source_reference
            ) orelse return error.SourceNotInMap;
            std.debug.assert(start_index == SOURCE_INDEX);

            var proj_args:TreeType.PathEndPointIndices = .{
                .source = start_index,
                .destination = start_index,
            };

            const codes = tree_nodes.items(.code);
            const source_code = codes[start_index];
            const maybe_child_indices = (
                tree_nodes.items(.child_indices)
            );

            // for each terminal space, build the topology to transform to that
            // space.  For each mapping in each topology, add the end points
            // for the mapping to the unsorted_vertices list
            for (codes, maybe_child_indices, 0..)
                |current_code, maybe_children, current_index|
            {
                if (
                    // only looking for terminal scopes (gaps, clips, etc)
                    (maybe_children[0] != null or maybe_children[1] != null)
                    // skip all media spaces that don't have a path to source
                    or source_code.is_prefix_of(current_code) == false
                ) 
                {
                    continue;
                }

                proj_args.destination = current_index;

                const source_to_current_proj_op = (
                    try build_projection_operator_indices(
                        allocator_parent,
                        tree,
                        proj_args,
                        cache,
                    )
                );

                const to_dest_topo = (
                    source_to_current_proj_op.src_to_dst_topo
                );

                try self.mappings.ensureUnusedCapacity(
                    allocator_parent,
                    to_dest_topo.mappings.len
                );
                try unsorted_vertices.ensureUnusedCapacity(
                    allocator_arena,
                    2 * to_dest_topo.mappings.len,
                );

                const first_mapping_index = self.mappings.len;
                for (to_dest_topo.mappings, first_mapping_index..)
                    |child_mapping, new_mapping_index|
                {
                    const interval_bounds = (
                        child_mapping.input_bounds()
                    );
                    self.mappings.appendAssumeCapacity(
                        .{
                            .destination = proj_args.destination,
                            .mapping = child_mapping,
                        },
                    );
                    unsorted_vertices.appendAssumeCapacity(
                        .{
                            .interval_index = new_mapping_index,
                            .ordinate = interval_bounds.start,
                            .kind = .start,
                        },
                    );
                    unsorted_vertices.appendAssumeCapacity(
                        .{
                            .interval_index = new_mapping_index,
                            .ordinate = interval_bounds.end,
                            .kind = .end,
                        },
                    );
                }
            }

            // sort the vertices in time.  given the intervals:
            // 1:[0, 3), 2:[0, 6) and 3:[3, 6)
            // the result should be:
            // [0.1, 0.2, 3.1, 3.3, 6.2, 6.3]
            ///////////
            const sorted_vertices = unsorted_vertices.slice();
            unsorted_vertices.sortUnstable(
                struct{
                    ordinates: []opentime.Ordinate,

                    pub fn lessThan(
                        ctx: @This(),
                        a_index: NodeIndex,
                        b_index: NodeIndex,
                    ) bool
                    {
                        const a_ord = ctx.ordinates[a_index];
                        const b_ord = ctx.ordinates[b_index];

                        return a_ord.lt(b_ord);
                    }
                }{ 
                    .ordinates = (
                        sorted_vertices.items(.ordinate) 
                    )
                }
            );

            var cut_points: std.MultiArrayList(
                struct{
                    ordinate: opentime.Ordinate,
                    indices: []NodeIndex,
                    kind: []start_or_end,
                }
            ) = .empty;
            try cut_points.ensureTotalCapacity(
                allocator_arena,
                sorted_vertices.len,
            );
            defer {
                for (
                    cut_points.items(.indices),
                    cut_points.items(.kind),
                ) |indices, kinds|
                {
                    allocator_arena.free(indices);
                    allocator_arena.free(kinds);
                }
                cut_points.deinit(allocator_arena);
            }
            var current_intervals: std.MultiArrayList(
                struct {
                    index: NodeIndex,
                    kind: start_or_end,
                }
            ) = .empty;

            // merge the sorted vertices and create lists of associated
            // interval start/end.
            //
            // Given the previous result:
            // [0.1, 0.2, 3.1, 3.3, 6.2, 6.3]
            // merged/sorted_lists: [
            //            0: {1.start, 2.start}, 
            //            3: {1.end, 3.start}, 
            //            6: {2.end, 3.end}
            //  ]
            ///////////
            var cut_point = sorted_vertices.items(.ordinate)[0];
            try current_intervals.append(
                allocator_arena, 
                .{
                    .index = sorted_vertices.items(.interval_index)[0],
                    .kind = sorted_vertices.items(.kind)[0],
                },
            );

            for (
                sorted_vertices.items(.interval_index),
                sorted_vertices.items(.kind),
                sorted_vertices.items(.ordinate),
            ) |int_ind, kind, vert|
            {
                // if the ordinate is not close enough, then create a new vert
                if (vert.eql_approx(cut_point) == false)
                {
                    var current_slice = current_intervals.toOwnedSlice();

                    cut_points.appendAssumeCapacity(
                        .{
                            .ordinate = cut_point,
                            .indices = current_slice.items(.index),
                            .kind = current_slice.items(.kind),
                        }
                    );
                    current_intervals = .empty;
                    cut_point = vert;
                }

                try current_intervals.append(
                    allocator_arena,
                    .{
                        .index = int_ind,
                        .kind = kind,
                    },
                );
            }

            // append the last segment
            {
                var current_slice = current_intervals.toOwnedSlice();
                try cut_points.append(
                    allocator_arena,
                    .{
                        .ordinate = cut_point,
                        .indices = current_slice.items(.index),
                        .kind = current_slice.items(.kind),
                    }
                );
            }

            // print current structure
            // std.debug.print(
            //     "cut_points:\n",
            //     .{},
            // );
            const cut_point_slice = cut_points.slice();
            // for (0..cut_point_slice.len)
            //     |ind|
            // {
            //     std.debug.print(
            //         "  ordinate: {f}\n  intervals:\n",
            //         .{cut_point_slice.items(.ordinate)[ind]}
            //     );
            //     for (
            //         cut_point_slice.items(.indices)[ind],
            //         cut_point_slice.items(.kind)[ind]
            //     )
            //         |int_ind, kind|
            //     {
            //         std.debug.print(
            //             "    {d}: {s}\n",
            //             .{int_ind, @tagName(kind)},
            //         );
            //     }
            // }
            // std.debug.print("done.\n", .{});
            
            // split and merge intervals together
            // given: [
            //            0: {1.start, 2.start}, 
            //            3: {1.end, 3.start}, 
            //            6: {2.end, 3.end}
            //  ]
            //  track which mappings are active over which segments:
            //  [ 
            //      { [0, 3): 1, 2 },
            //      { [3, 6): 2, 3 } 
            //  ]
            ////////////
            var active_mappings = try (
                std.DynamicBitSetUnmanaged.initEmpty(
                    allocator_arena,
                    self.mappings.len,
                )
            );

            const ordinates = cut_point_slice.items(.ordinate);
            const len = ordinates.len;

            std.debug.assert(ordinates.len == cut_point_slice.len);

            try self.intervals.ensureTotalCapacity(
                allocator_parent,
                len - 1
            );

            var indices:  std.ArrayList(NodeIndex) = .empty;

            for (
                ordinates[0..len - 1],
                ordinates[1..],
                cut_point_slice.items(.kind)[0..len - 1],
                cut_point_slice.items(.indices)[0..len - 1],
            ) |ord_start, ord_end, kinds, mappings|
            {
                for (kinds, mappings)
                    |kind, mapping|
                {
                    // std.debug.print(
                    //     "interval: {d} active_intervals_len: {d}\n",
                    //     .{interval, active_intervals.bit_length },
                    // );
                    std.debug.assert(mapping < active_mappings.bit_length);

                    if (kind == .start)
                    {
                        active_mappings.setValue(mapping, true);
                    }
                    else if (kind == .end)
                    {
                        active_mappings.setValue(mapping, false);
                    }
                }

                var bit_iter = (
                    active_mappings.iterator(.{})
                );

                try indices.ensureTotalCapacity(
                    allocator_parent,
                    active_mappings.count(),
                );

                while (bit_iter.next())
                    |active_mapping_index|
                {
                    indices.appendAssumeCapacity(active_mapping_index);
                }

                self.intervals.appendAssumeCapacity(
                    .{
                        .input_bounds = .{
                            .start = ord_start,
                            .end = ord_end,
                        },
                        .mapping_index = try indices.toOwnedSlice(
                            allocator_parent
                        ),
                    },
                );
            }

            // print current structure
            // std.debug.print(
            //     "Final Cut Points:\n",
            //     .{},
            // );
            // const interval_slice = self.intervals.slice();
            // for (0..interval_slice.len)
            //     |ind|
            // {
            //     std.debug.print(
            //         "  bounds: {f}\n  intervals:\n",
            //         .{interval_slice.items(.input_bounds)[ind]}
            //     );
            //     for (
            //         interval_slice.items(.mapping_index)[ind],
            //     )
            //         |int_ind|
            //     {
            //         std.debug.print(
            //             "    {d}\n",
            //             .{int_ind},
            //         );
            //     }
            // }
            // std.debug.print("done.\n", .{});

            return self;
        }

        pub fn deinit(
            self: *@This(),
            allocator: std.mem.Allocator,
        ) void
        {
            for (self.intervals.items(.mapping_index))
                |indices|
            {
                allocator.free(indices);
            }

            self.intervals.deinit(allocator);
            self.mappings.deinit(allocator);
            self.tree.deinit(allocator);
            self.cache.deinit(allocator);
        }

        pub fn projection_operator_to(
            self: @This(),
            allocator: std.mem.Allocator,
            destination_space: SpaceReferenceType,
        ) !ProjectionOperatorType
        {
            return try build_projection_operator_assume_sorted(
                allocator,
                self.tree,
                .{
                    .source = SOURCE_INDEX,
                    .destination = (
                        self.tree.map_node_to_index.get(
                            destination_space
                        ) 
                        orelse return error.DestinationSpaceNotChildOfSource
                    ),
                },
                self.cache,
            );
        }

        /// build a projection from `target` space to `self.source` space
        pub fn projection_operator_from_leaky(
            self: @This(),
            allocator: std.mem.Allocator,
            target: SpaceReferenceType,
        ) !ProjectionOperatorType
        {
            var result = (
                try build_projection_operator_assume_sorted(
                    allocator,
                    self.tree,
                    .{
                        .source = SOURCE_INDEX,
                        .destination = (
                            self.tree.map_node_to_index.get(target)
                            orelse return error.DestinationSpaceNotUnderSource
                        ),
                    },
                    self.cache,
                )
            );

            const inverted_topologies = (
                try result.src_to_dst_topo.inverted(allocator)
            );
            errdefer opentime.deinit_slice(
                allocator,
                topology_m.Topology,
                inverted_topologies
            );

            if (inverted_topologies.len > 1) 
            {
                return error.MoreThanOneInversionIsNotImplemented;
            }
            if (inverted_topologies.len > 0) 
            {
                result.src_to_dst_topo = inverted_topologies[0];
                std.mem.swap(
                    SpaceReferenceType,
                    &result.source,
                    &result.destination,
                );
                allocator.free(inverted_topologies);
            }
            else 
            {
                return error.NoInvertedTopologies;
            }

            return result;
        }

        pub fn projection_operator_to_index(
            self: @This(),
            allocator: std.mem.Allocator,
            destination_space_index: NodeIndex,
        ) !ProjectionOperatorType
        {
            return try build_projection_operator_indices(
                allocator,
                self.tree,
                .{
                    .source = 0,
                    .destination = destination_space_index,
                },
                self.cache,
            );
        }

        /// return the input range for this ReferenceTopology
        pub fn input_bounds(
            self: @This(),
        ) opentime.ContinuousInterval
        {
            const bounds = self.intervals.items(.input_bounds);

            return .{
                .start = bounds[0].start,
                .end = bounds[self.intervals.len-1].end,
            };
        }

        pub fn format(
            self: @This(),
            writer: *std.Io.Writer,
        ) !void 
        {
            try writer.print(
                "Total timeline interval: {f}\n",
                .{ self.input_bounds() },
            );

            try writer.print(
                "Intervals mapping (index<100):\n",
                .{},
            );
            for (0..@min(100, self.intervals.len))
                |ind|
            {
                const first_interval_mapping = (
                    self.intervals.get(ind)
                );
                try writer.print(
                    "  Presentation Space Range: {f}\n",
                    .{ first_interval_mapping.input_bounds }
                );
                for (first_interval_mapping.mapping_index)
                    |mapping_ind|
                {
                    const mapping = self.mappings.get(
                        mapping_ind
                    );
                    const output_bounds = (
                        mapping.mapping.output_bounds()
                    );
                    const destination = (
                        self.tree.nodes.get(mapping.destination)
                    );

                    try writer.print(
                        "    -> {f} | {f}\n",
                        .{ destination, output_bounds, }
                    );
                }
            }
        }

        pub fn build_projection_operator_indices(
            parent_allocator: std.mem.Allocator,
            tree: TreeType,
            endpoints: TreeType.PathEndPointIndices,
            operator_cache: SingleSourceTopologyCache,
        ) !ProjectionOperatorType
        {
            // sort endpoints so that the higher node is always the source
            var sorted_endpoints = endpoints;
            const endpoints_were_swapped = try tree.sort_endpoint_indices(
                &sorted_endpoints
            );

            // var result = try build_projection_operator_assume_sorted(
            var result = try build_projection_operator_assume_sorted(
                parent_allocator,
                tree,
                sorted_endpoints,
                operator_cache
            );

            // check to see if end points were inverted
            if (endpoints_were_swapped and result.src_to_dst_topo.mappings.len > 0) 
            {
                const inverted_topologies = (
                    try result.src_to_dst_topo.inverted(parent_allocator)
                );
                errdefer opentime.deinit_slice(
                    parent_allocator,
                    topology_m.Topology,
                    inverted_topologies
                );

                if (inverted_topologies.len > 1) 
                {
                    return error.MoreThanOneInversionIsNotImplemented;
                }
                if (inverted_topologies.len > 0) 
                {
                    result.src_to_dst_topo = inverted_topologies[0];
                    std.mem.swap(
                        SpaceReferenceType,
                        &result.source,
                        &result.destination,
                    );
                }
                else 
                {
                    return error.NoInvertedTopologies;
                }
            }

            return result;
        }

        pub fn build_projection_operator_assume_sorted(
            parent_allocator: std.mem.Allocator,
            tree: TreeType,
            sorted_endpoints: TreeType.PathEndPointIndices,
            operator_cache: SingleSourceTopologyCache,
        ) !ProjectionOperatorType
        {
            const space_nodes = tree.nodes.slice();

            // if destination is already present in the cache
            if (operator_cache.items[sorted_endpoints.destination])
                |cached_topology|
            {
                return .{
                    .source = (
                        space_nodes.get(sorted_endpoints.source)
                    ),
                    .destination = space_nodes.get(
                        sorted_endpoints.destination
                    ),
                    .src_to_dst_topo = cached_topology,
                };
            }

            var arena = std.heap.ArenaAllocator.init(parent_allocator);
            defer arena.deinit();
            const allocator_arena = arena.allocator();

            var root_to_current:topology_m.Topology = .INFINITE_IDENTITY;

            if (GRAPH_CONSTRUCTION_TRACE_MESSAGES) 
            {
                opentime.dbg_print(@src(), 
                    "[START] root_to_current: {f}\n",
                    .{ root_to_current }
                );
            }

            const source_index = sorted_endpoints.source;

            const path_nodes = tree.tree_data.slice();
            const codes = path_nodes.items(.code);

            // compute the path length
            const path = try tree.path(
                allocator_arena,
                .{ 
                    .source = source_index,
                    .destination = sorted_endpoints.destination,
                },
            );

            if (GRAPH_CONSTRUCTION_TRACE_MESSAGES) 
            {
                opentime.dbg_print(@src(), 
                    "starting walk from: {f} to: {f}\n"
                    ++ "starting projection: {f}\n"
                    ,
                    .{
                        space_nodes.get(path[0]),
                        space_nodes.get(sorted_endpoints.destination),
                        root_to_current,
                    }
                );
            }

            if (path.len < 2)
            {
                return .{
                    .source = space_nodes.get(
                        sorted_endpoints.source,
                    ),
                    .destination = space_nodes.get(
                        sorted_endpoints.destination
                    ),
                    .src_to_dst_topo = .INFINITE_IDENTITY,
                };
            }

            var path_step:TreeType.PathEndPointIndices = .{
                .source = @intCast(source_index),
                .destination = @intCast(source_index),
            };

            // walk from current_code towards destination_code - path[0] is the
            // current node, can be skipped
            for (path[0..path.len - 1], path[1..])
                |current, next|
            {
                path_step.destination = @intCast(next);

                if (operator_cache.items[next])
                    |cached_topology|
                {
                    root_to_current = cached_topology;
                    continue;
                }

                const next_step = codes[current].next_step_towards(codes[next]);

                if (GRAPH_CONSTRUCTION_TRACE_MESSAGES) { 
                    opentime.dbg_print(
                        @src(), 
                        "  next step {b} towards next node: {f}\n",
                        .{ next_step, space_nodes.get(next) },
                    );
                }

                const current_to_next = (
                    try space_nodes.items(.ref)[current].build_transform(
                        allocator_arena,
                        space_nodes.items(.label)[current],
                        space_nodes.get(next),
                        next_step,
                    )
                );

                if (GRAPH_CONSTRUCTION_TRACE_MESSAGES) 
                {
                    opentime.dbg_print(
                        @src(), 
                        "    joining!\n"
                        ++ "    a2b {f}/root_to_current: {f}\n"
                        ++ "    b2c {f}/current_to_next: {f}\n"
                        ,
                        .{
                            space_nodes.get(current),
                            root_to_current,
                            space_nodes.get(next),
                            current_to_next,
                        },
                    );
                }

                const root_to_next = try topology_m.join(
                    parent_allocator,
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

                    opentime.dbg_print(
                        @src(), 
                        "    root_to_next (next root to current!): {f}\n"
                        ++ "    composed transform ranges {f}: {f},"
                        ++ " {f}: {f}\n"
                        ,
                        .{
                            root_to_next,
                            space_nodes.get(source_index),
                            i_b,
                            space_nodes.get(next),
                            o_b,
                        },
                    );
                }

                root_to_current = root_to_next;
                operator_cache.items[next] = root_to_current;
            }

            return .{
                .source = space_nodes.get(sorted_endpoints.source),
                .destination = space_nodes.get(sorted_endpoints.destination),
                .src_to_dst_topo = root_to_current,
            };
        }

        pub fn space_from_mapping_index(
            self: @This(),
            mapping_index: usize,
        ) SpaceReferenceType
        {
            const destination_ind = (
                self.mappings.items(.destination)[mapping_index]
            );
            return self.tree.nodes.get(destination_ind);
        }

        pub const SingleSourceTopologyCache = struct { 
            items: []?topology_m.Topology,

            pub fn init(
                allocator: std.mem.Allocator,
                tree: TreeType,
            ) !SingleSourceTopologyCache
            {
                const cache = try allocator.alloc(
                    ?topology_m.Topology,
                    tree.nodes.len,
                );
                @memset(cache, null);

                return .{ .items = cache };
            }

            pub fn deinit(
                self: @This(),
                allocator: std.mem.Allocator,
            ) void
            {
                for (self.items) 
                    |*maybe_topo|
                {
                    if (maybe_topo.*)
                        |topo|
                    {
                        topo.deinit(allocator);
                    }
                    maybe_topo.* = null;
                }
                allocator.free(self.items);   
            }
        };
    };
}

