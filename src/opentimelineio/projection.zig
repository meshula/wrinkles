const std = @import("std");

const opentime = @import("opentime");
const sampling = @import("sampling");
const topology_m = @import("topology");
const treecode = @import("treecode");
const curve = @import("curve");

const schema = @import("schema.zig");
const references = @import("references.zig");
const temporal_hierarchy = @import("temporal_hierarchy.zig");
const test_data = @import("test_structures.zig");

/// Combines a source, destination and transformation from the source to the
/// destination.  Allows continuous and discrete transformations.
pub const ProjectionOperator = struct {
    source: references.SpaceReference,
    destination: references.SpaceReference,
    src_to_dst_topo: topology_m.Topology,

    // options:
    //  instant
    //   project_instantaneous_cc -> ordinate -> ordinate
    //   project_instantaneous_cd -> ordinate -> index
    //  topology-based
    //   project_topology_cc -> topology -> topology
    //   project_topology_cd -> topology -> index array
    //
    //   derivatives:
    //
    //    project_range_cc -> range -> topology
    //    project_range_cd -> range -> index array
    //    project_index_dc -> index -> topology
    //    project_index_dd -> index -> index array
    //    project_indices_dc -> index array -> topology
    //    project_indices_dd -> index array -> index array

    pub fn source_bounds(
        self: @This(),
    ) opentime.ContinuousInterval
    {
        return self.src_to_dst_topo.input_bounds();
    }

    pub fn destination_bounds(
        self: @This(),
    ) opentime.ContinuousInterval
    {
        return self.src_to_dst_topo.output_bounds();
    }

    ///project a continuous ordinate to the continuous destination space
    pub fn project_instantaneous_cc(
        self: @This(),
        ordinate_in_source_space: opentime.Ordinate,
    ) opentime.ProjectionResult
    {
        return self.src_to_dst_topo.project_instantaneous_cc(
            ordinate_in_source_space
        );
    }

    /// project a continuous ordinate to the destination discrete sample index
    pub fn project_instantaneous_cd(
        self: @This(),
        ordinate_in_source_space: opentime.Ordinate,
    ) !sampling.sample_index_t 
    {
        const continuous_in_destination_space =  (
            try self.src_to_dst_topo.project_instantaneous_cc(
                ordinate_in_source_space
            ).ordinate()
        );

        return try self.destination.ref.continuous_ordinate_to_discrete_index(
            continuous_in_destination_space,
            self.destination.label,
        );
    }

    /// given a topology mapping "A" to "SOURCE" return a topology that maps
    /// "A" to the "DESTINATION" continuous space of the projection operator
    pub fn project_topology_cc(
        self: @This(),
        allocator: std.mem.Allocator,
        in_to_src_topo: topology_m.Topology,
    ) !topology_m.Topology
    {
        // project the source range into the destination space
        const in_to_dst_topo = (
            try topology_m.join(
                allocator,
                .{ 
                .a2b = in_to_src_topo,
                .b2c = self.src_to_dst_topo,
                },
            )
        );

        return in_to_dst_topo;
    }

    /// given a topology mapping "A" to "SOURCE" return a topology that maps
    /// "A" to the "DESTINATION" discrete space of the projection operator
    pub fn project_topology_cd(
        self: @This(),
        allocator: std.mem.Allocator,
        in_to_src_topo: topology_m.Topology,
    ) ![]sampling.sample_index_t
    {
        // project the source range into the destination space
        const in_to_dst_topo_c = (
            try self.project_topology_cc(
                allocator,
                in_to_src_topo,
            )
        );
        defer in_to_dst_topo_c.deinit(allocator);

        const dst_discrete_info = (
            try self.destination.ref.discrete_info_for_space(
                self.destination.label,
            )
        ).?;
        var index_buffer_destination_discrete: std.ArrayList(
            sampling.sample_index_t
        ) = .{};
        defer index_buffer_destination_discrete.deinit(allocator);

        const in_c_bounds = in_to_dst_topo_c.input_bounds();

        // const bounds_to_walk = dst_c_bounds;
        const bounds_to_walk = in_c_bounds;

        const duration = dst_discrete_info.sample_rate_hz.inv_as_ordinate();

        const sample_count = (
            bounds_to_walk.duration().div(duration).abs().as(usize)
        );
        try index_buffer_destination_discrete.ensureTotalCapacity(
            allocator,
            sample_count + 2,
        );

        const increasing = bounds_to_walk.end.gt(bounds_to_walk.start);

        const increment = (
            if (increasing) duration else duration.neg()
        );

        // walk across the continuous space at the sampling rate
        var t = bounds_to_walk.start;
        while (
            (increasing and t.lt(bounds_to_walk.end))
            or (increasing == false and t.gt(bounds_to_walk.end))
        ) : (t = t.add(increment))
        {
            const out_ord = (
                try in_to_dst_topo_c.project_instantaneous_cc(t).ordinate()
            );

            // ...project the continuous coordinate into the discrete space
            index_buffer_destination_discrete.appendAssumeCapacity(
                try self.destination.ref.continuous_ordinate_to_discrete_index(
                    out_ord,
                    self.destination.label,
                )
            );
        }

        return index_buffer_destination_discrete.toOwnedSlice(allocator);
    }

    /// project a continuous range into the continuous destination space
    pub fn project_range_cc(
        self: @This(),
        allocator: std.mem.Allocator,
        range_in_source: opentime.ContinuousInterval,
    ) !topology_m.Topology
    {
        // build a topology over the range in the source space
        const topology_in_source = (
            topology_m.Topology{
                .mappings = &.{
                    (
                     topology_m.mapping.MappingAffine{ 
                         .input_to_output_xform = .{ 
                             .offset = range_in_source.start,
                             .scale = .ONE,
                         },
                         .input_bounds_val = .{
                             .start = .ZERO,
                             .end = range_in_source.duration(),
                         },
                     }
                    ).mapping(),
                }
            }
        );

        return try self.project_topology_cc(
            allocator,
            topology_in_source,
        );
    }

    /// project a continuous range into the discrete index space
    pub fn project_range_cd(
        self: @This(),
        allocator: std.mem.Allocator,
        range_in_source: opentime.ContinuousInterval,
    ) ![]sampling.sample_index_t
    {
        // the range is bounding the source repo.  Therefore the topology is an
        // identity that is bounded 
        const in_to_source_topo = (
            topology_m.Topology{
                .mappings = &.{
                    (
                    topology_m.mapping.MappingAffine { 
                        .input_to_output_xform = .IDENTITY,
                        .input_bounds_val = range_in_source,
                    }
                    ).mapping(),
                },
            }
        );

        return try self.project_topology_cd(
            allocator,
            in_to_source_topo,
        );
    }

    /// project a discrete index into the continuous space
    pub fn project_index_dc(
        self: @This(),
        allocator: std.mem.Allocator,
        index_in_source: sampling.sample_index_t,
    ) !topology_m.Topology
    {
        const c_range_in_source = (
            try self.source.ref.discrete_index_to_continuous_range(
                index_in_source,
                self.source.label,
            )
        );

        return try self.project_range_cc(
            allocator,
            c_range_in_source,
        );
    }

    /// project an index from the source to the overlapping indices in the
    /// destination discrete space
    pub fn project_index_dd(
        self: @This(),
        allocator: std.mem.Allocator,
        index_in_source: sampling.sample_index_t,
    ) ![]sampling.sample_index_t
    {
        const c_range_in_source = (
            try self.source.ref.discrete_index_to_continuous_range(
                index_in_source,
                self.source.label,
            )
        );

        return try self.project_range_cd(
            allocator,
            c_range_in_source,
        );
    }

    pub fn deinit(
        self: @This(),
        allocator: std.mem.Allocator,
    ) void
    {
        self.src_to_dst_topo.deinit(allocator);
    }

    /// return true if lhs.topology.input_bounds().start_time < rhs...
    pub fn less_than_input_space_start_point(
        lhs: @This(),
        rhs: @This(),
    ) bool
    {
        return (
            lhs.src_to_dst_topo.input_bounds().start_time 
            < rhs.src_to_dst_topo.input_bounds().start_time
        );
    }

    pub fn clone(
        self: @This(),
        allocator: std.mem.Allocator,
    ) !ProjectionOperator
    {
        return .{
            .source = self.source,
            .destination = self.destination,
            .src_to_dst_topo = (
                try self.src_to_dst_topo.clone(allocator)
            ),
        };
    }
};

/// maps projection to clip.media spaces to regions of whatever space is
/// the source space
pub fn projection_map_to_media_from(
    allocator: std.mem.Allocator,
    map: temporal_hierarchy.TemporalMap,
    source: references.SpaceReference,
) !ProjectionOperatorMap
{
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    const result = try projection_map_to_media_from_leaky(
        arena_allocator,
        map,
        source,
    );

    return try result.clone(allocator);
}

pub fn projection_map_to_media_from_leaky(
    allocator: std.mem.Allocator,
    map: temporal_hierarchy.TemporalMap,
    source: references.SpaceReference,
) !ProjectionOperatorMap
{
    var result = ProjectionOperatorMap{
        .source = source,
    };

    // start with an identity end points
    var proj_args = temporal_hierarchy.PathEndPoints{
        .source = source,
        .destination = source,
    };

    const space_nodes = map.space_nodes.slice();

    const cache = (
        try temporal_hierarchy.SingleSourceTopologyCache.init(
            allocator,
            map,
        )
    );
    defer cache.deinit(allocator);

    for (space_nodes.items(.label), 0..)
        |label, index|
    {
        // skip spaces that aren't media spaces
        if (label != .media)
        {
            continue;
        }

        proj_args.destination = space_nodes.get(index);

        const child_op = (
            try temporal_hierarchy.build_projection_operator(
                allocator,
                map,
                proj_args,
                cache,
            )
        );

        const new_bounds = (
            child_op.src_to_dst_topo.input_bounds()
        );

        const child_op_map = ProjectionOperatorMap {
            .end_points = &. {
                new_bounds.start, new_bounds.end,
            },
            .operators = &.{
                &.{ child_op }, 
            },
            .source = source,
        };

        result = try ProjectionOperatorMap.merge_composite(
            allocator,
            .{
                .over = result,
                .under = child_op_map,
            }
        );
    }

    return result;
}

test "ProjectionOperatorMap: init_operator leak test"
{
    const allocator = std.testing.allocator;

    var cl = schema.Clip{};
    const cl_ptr = references.ComposedValueRef{ 
        .clip = &cl 
    };
    const child_op_map = (
        try ProjectionOperatorMap.init_operator(
            allocator,
            .{
                .source = cl_ptr.space(.presentation),
                .destination = cl_ptr.space(.media),
                .src_to_dst_topo = .EMPTY,
            },
        )
    );
    defer child_op_map.deinit(allocator);

    const clone = try child_op_map.clone(allocator);
    defer clone.deinit(allocator);
}

test "ProjectionOperatorMap: projection_map_to_media_from leak test"
{
    const allocator = std.testing.allocator;

    var cl = schema.Clip {
        .bounds_s = test_data.T_INT_1_TO_9,
    };
    const cl_ptr = references.ComposedValueRef.init(&cl);

    const map = try temporal_hierarchy.build_temporal_map(
        allocator,
        cl_ptr,
    );
    defer map.deinit(allocator);

    const m = try projection_map_to_media_from(
        allocator,
        map,
        cl_ptr.space(.presentation),
    );
    defer m.deinit(allocator);

    const mapp = m.operators[0][0].src_to_dst_topo.mappings[0];
    try opentime.expectOrdinateEqual(
        4,
        mapp.project_instantaneous_cc(opentime.Ordinate.init(3)).ordinate()
    );

    try opentime.expectOrdinateEqual(
        4,
        try m.operators[0][0].project_instantaneous_cc(
            opentime.Ordinate.init(3)
        ).ordinate(),
    );
}

// @TODO: remove ProjectionOperatorMap

/// maps a timeline to sets of projection operators, one set per temporal slice
pub const ProjectionOperatorMap = struct {
    /// segment endpoints in the input space
    end_points: []const opentime.Ordinate = &.{},
    /// segment projection operators 
    operators : []const []const ProjectionOperator = &.{},

    /// root space for the map
    source : references.SpaceReference,

    /// initialize from an operator, so that the operator can be merged into 
    /// the map
    pub fn init_operator(
        allocator: std.mem.Allocator,
        op: ProjectionOperator,
    ) !ProjectionOperatorMap
    {
        const input_bounds = op.src_to_dst_topo.input_bounds();
        const end_points = try allocator.dupe(
            opentime.Ordinate,
            &.{ input_bounds.start, input_bounds.end } 
        );

        var operators = try allocator.alloc(
            []const ProjectionOperator,
            1
        );
        operators[0] = try allocator.dupe(ProjectionOperator, &.{ op });
        
        return .{
            .end_points = end_points,
            .operators = operators,
            .source = op.source,
        };
    }

    pub fn deinit(
        self: @This(),
        allocator: std.mem.Allocator,
    ) void
    {
        allocator.free(self.end_points);
        for (self.operators)
            |segment_ops|
        {
            for (segment_ops)
                |op|
            {
                op.deinit(allocator);
            }
            allocator.free(segment_ops);
        }
        allocator.free(self.operators);
    }

    const OverlayArgs = struct{
        over: ProjectionOperatorMap,
        under: ProjectionOperatorMap,
    };

    pub fn merge_composite(
        parent_allocator: std.mem.Allocator,
        args: OverlayArgs,
    ) !ProjectionOperatorMap
    {
        if (args.over.is_empty() and args.under.is_empty())
        {
            return .{
                .source = args.over.source,
            };
        }
        if (args.over.is_empty())
        {
            return try args.under.clone(parent_allocator);
        }
        if (args.under.is_empty())
        {
            return try args.over.clone(parent_allocator);
        }

        var arena = std.heap.ArenaAllocator.init(
            parent_allocator
        );
        defer arena.deinit();
        const arena_allocator = arena.allocator();

        const over = args.over;
        const undr = args.under;

        const full_range = opentime.ContinuousInterval{
            .start = opentime.min(
                over.end_points[0],
                undr.end_points[0],
            ),
            .end = opentime.max(
                over.end_points[over.end_points.len - 1],
                undr.end_points[undr.end_points.len - 1],
            ),
        };

        const over_extended = try over.extend_to(
            arena_allocator,
            full_range,
        );
        const undr_extended = try undr.extend_to(
            arena_allocator,
            full_range,
        );

        // project all splits from over to undr
        const over_conformed = try over_extended.split_at_each(
            arena_allocator,
            undr_extended.end_points,
        );
        const undr_conformed = try undr_extended.split_at_each(
            arena_allocator,
            over_conformed.end_points,
        );

        const entries = over_conformed.end_points.len;
        var end_points: std.ArrayList(opentime.Ordinate) = .empty;
        try end_points.ensureTotalCapacity(
            parent_allocator,
            entries,
        );

        var operators: std.ArrayList([]const ProjectionOperator) = .empty;
        try operators.ensureTotalCapacity(
            parent_allocator,
            entries,
        );
        var current_segment: std.ArrayList(ProjectionOperator) = .empty;

        // both end point arrays are the same
        for (over_conformed.end_points[0..entries - 1], 0..)
            |p, ind|
        {
            end_points.appendAssumeCapacity(p);
            try current_segment.ensureTotalCapacity(
                parent_allocator,
                over_conformed.operators[ind].len
                + undr_conformed.operators[ind].len
            );
            defer current_segment.clearAndFree(parent_allocator);

            for (over_conformed.operators[ind])
                |op|
            {
                current_segment.appendAssumeCapacity(
                    try op.clone(parent_allocator),
                );
            }
            for (undr_conformed.operators[ind])
                |op|
            {
                current_segment.appendAssumeCapacity(
                    try op.clone(parent_allocator),
                );
            }
            operators.appendAssumeCapacity(
                try current_segment.toOwnedSlice(parent_allocator),
            );
        }

        end_points.appendAssumeCapacity(
            over_conformed.end_points[over_conformed.end_points.len - 1],
        );

        return .{
            .end_points  = 
                try end_points.toOwnedSlice(parent_allocator),
            .operators  = 
                try operators.toOwnedSlice(parent_allocator),
            .source = args.over.source,
        };
    }

    pub fn is_empty(
        self: @This(),
    ) bool
    {
        return self.end_points.len == 0 or self.operators.len == 0;
    }

    pub fn clone(
        self: @This(),
        allocator: std.mem.Allocator,
    ) !ProjectionOperatorMap
    {
        var cloned_projection_operators: std.ArrayList(ProjectionOperator) = .{};
        defer cloned_projection_operators.deinit(allocator);

        return .{
            .source = self.source,
            .end_points = try allocator.dupe(
                opentime.Ordinate,
                self.end_points
            ),
            .operators = ops: {
                const outer = (
                    try allocator.alloc(
                        []const ProjectionOperator,
                        self.operators.len,
                    )
                );
                for (outer, self.operators)
                    |*inner, source|
                {
                    try cloned_projection_operators.ensureTotalCapacity(
                        allocator,
                        source.len,
                    );
                    for (source)
                        |s_mapping|
                    {
                        cloned_projection_operators.appendAssumeCapacity(
                            try s_mapping.clone(allocator)
                        );
                    }

                    inner.* = try cloned_projection_operators.toOwnedSlice(
                        allocator,
                    );
                }
                break :ops outer;
            }
        };
    }

    pub fn extend_to(
        self: @This(),
        allocator: std.mem.Allocator,
        range: opentime.ContinuousInterval,
    ) !ProjectionOperatorMap
    {
        var tmp_pts: std.ArrayList(opentime.Ordinate) = .empty;
        defer tmp_pts.deinit(allocator);
        try tmp_pts.ensureTotalCapacity(
            allocator,
            // possible extra end point + internal points
            1 + self.end_points.len + 1
        );

        var tmp_ops: std.ArrayList([]const ProjectionOperator) = .empty;
        defer tmp_ops.deinit(allocator);
        try tmp_ops.ensureTotalCapacity(
            allocator,
            // possible extra end point + internal points
            1 + self.operators.len + 1
        );

        if (self.end_points[0].gt(range.start)) 
        {
            tmp_pts.appendAssumeCapacity(range.start);
            tmp_ops.appendAssumeCapacity(&.{});
        }

        tmp_pts.appendSliceAssumeCapacity(self.end_points);

        for (self.operators) 
            |self_ops|
        {
            tmp_ops.appendAssumeCapacity(
                try opentime.slice_with_cloned_contents_allocator(
                    allocator,
                    ProjectionOperator,
                    self_ops,
                )
            );
        }

        if (range.end.gt(self.end_points[self.end_points.len - 1])) 
        {
            tmp_pts.appendAssumeCapacity(range.end);
            tmp_ops.appendAssumeCapacity(&.{});
        }

        return .{
            .end_points = try tmp_pts.toOwnedSlice(allocator),
            .operators = try tmp_ops.toOwnedSlice(allocator),
            .source = self.source,
        };
    }

    pub fn split_at_each(
        self: @This(),
        allocator: std.mem.Allocator,
        /// pts should have the same start and end point as self
        pts: []const opentime.Ordinate,
    ) !ProjectionOperatorMap
    {
        var tmp_pts: std.ArrayList(opentime.Ordinate) = .empty;
        defer tmp_pts.deinit(allocator);
        try tmp_pts.ensureTotalCapacity(
            allocator,
            self.end_points.len + pts.len
        );

        var tmp_ops: std.ArrayList([]const ProjectionOperator) = .empty;
        defer tmp_ops.deinit(allocator);
        try tmp_ops.ensureTotalCapacity(
            allocator,
            self.operators.len + pts.len
        );

        var ind_self:usize = 0;
        var ind_other:usize = 0;

        var t_next_self = self.end_points[1];
        var t_next_other = pts[1];

        // append origin
        tmp_pts.appendAssumeCapacity(self.end_points[0]);

        while (
            ind_self < self.end_points.len - 1
            and ind_other < pts.len - 1 
        )
        {
            tmp_ops.appendAssumeCapacity(
                try opentime.slice_with_cloned_contents_allocator(
                    allocator,
                    ProjectionOperator,
                    self.operators[ind_self],
                )
            );

            t_next_self = self.end_points[ind_self+1];
            t_next_other = pts[ind_other+1];

            if (t_next_self.eql_approx(t_next_other))
            {
                tmp_pts.appendAssumeCapacity(t_next_self);
                if (ind_self < self.end_points.len - 1) {
                    ind_self += 1;
                }
                if (ind_other < pts.len - 1) {
                    ind_other += 1;
                }
            }
            else if (t_next_self.lt(t_next_other))
            {
                tmp_pts.appendAssumeCapacity(t_next_self);
                ind_self += 1;
            }
            else 
            {
                tmp_pts.appendAssumeCapacity(t_next_other);
                ind_other += 1;
            }
        }

        return .{
            .end_points = try tmp_pts.toOwnedSlice(allocator),
            .operators = try tmp_ops.toOwnedSlice(allocator),
            .source = self.source,
        };
    }
};

test "ProjectionOperatorMap: extend_to"
{
    const allocator = std.testing.allocator;

    var cl = schema.Clip {
        .bounds_s = test_data.T_INT_1_TO_9,
    };
    const cl_ptr = references.ComposedValueRef{ .clip = &cl };

    const map = try temporal_hierarchy.build_temporal_map(
        allocator,
        cl_ptr,
    );
    defer map.deinit(allocator);

    const cl_presentation_pmap = (
        try projection_map_to_media_from(
            allocator,
            map,
            cl_ptr.space(.presentation),
        )
    );
    defer cl_presentation_pmap.deinit(allocator);

    // extend_to no change
    {
        const result = try cl_presentation_pmap.extend_to(
            allocator,
            .{
                .start = cl_presentation_pmap.end_points[0],
                .end = cl_presentation_pmap.end_points[1],
            },
        );
        defer result.deinit(allocator);

        try std.testing.expectEqualSlices(
            opentime.Ordinate,
            cl_presentation_pmap.end_points,
            result.end_points,
        );
        try std.testing.expectEqual(
            cl_presentation_pmap.operators.len,
            result.operators.len,
        );
    }

    // add before
    {
        const result = try cl_presentation_pmap.extend_to(
            allocator,
            .{
                .start = opentime.Ordinate.init(-10),
                .end = opentime.Ordinate.init(8),
            },
        );
        defer result.deinit(allocator);

        try std.testing.expectEqualSlices(
            opentime.Ordinate,
            &.{
                opentime.Ordinate.init(-10),
                opentime.Ordinate.init(0),
                opentime.Ordinate.init(8)
            },
            result.end_points,
        );

        try std.testing.expectEqual(
            2,
            result.operators.len,
        );
    }

    // add after
    {
        const result = try cl_presentation_pmap.extend_to(
            allocator,
            .{
                .start = opentime.Ordinate.init(0),
                .end = opentime.Ordinate.init(18),
            },
        );
        defer result.deinit(allocator);

        try std.testing.expectEqualSlices(
            opentime.Ordinate,
            &.{
                opentime.Ordinate.init(0),
                opentime.Ordinate.init(8),
                opentime.Ordinate.init(18)
            },
            result.end_points,
        );

        try std.testing.expectEqual(
            2,
            result.operators.len,
        );
    }
}

test "ProjectionOperatorMap: split_at_each"
{
    const allocator = std.testing.allocator;

    var cl = schema.Clip {
        .bounds_s = test_data.T_INT_1_TO_9,
    };
    const cl_ptr = references.ComposedValueRef{ .clip = &cl };

    const map = try temporal_hierarchy.build_temporal_map(
        allocator,
        cl_ptr,
    );
    defer map.deinit(allocator);

    const cl_presentation_pmap = (
        try projection_map_to_media_from(
            allocator,
            map,
            cl_ptr.space(.presentation),
        )
    );
    defer cl_presentation_pmap.deinit(allocator);

    // split_at_each -- no change
    {
        const result = try cl_presentation_pmap.split_at_each(
            allocator,
            cl_presentation_pmap.end_points,
        );
        defer result.deinit(allocator);

        try std.testing.expectEqualSlices(
            opentime.Ordinate,
            cl_presentation_pmap.end_points,
            result.end_points,
        );
        try std.testing.expectEqual(
            cl_presentation_pmap.operators.len,
            result.operators.len,
        );
    }

    // split_at_each -- end points are same, split in middle
    {
        const pts = [_]opentime.Ordinate{ opentime.Ordinate.init(0), opentime.Ordinate.init(4), opentime.Ordinate.init(8) };

        const result = try cl_presentation_pmap.split_at_each(
            allocator,
            &pts,
        );
        defer result.deinit(allocator);

        try std.testing.expectEqualSlices(
            opentime.Ordinate,
            &pts,
            result.end_points,
        );

        try std.testing.expectEqual(
            cl_presentation_pmap.operators.len + 1,
            result.operators.len,
        );
    }

    // split_at_each -- end points are same, split in middle twice
    {
        const pts = [_]opentime.Ordinate{
            opentime.Ordinate.init(0),
            opentime.Ordinate.init(1),
            opentime.Ordinate.init(4),
            opentime.Ordinate.init(8),
        };

        const result = try cl_presentation_pmap.split_at_each(
            allocator,
            &pts,
        );
        defer result.deinit(allocator);

        try std.testing.expectEqualSlices(
            opentime.Ordinate,
            &pts,
            result.end_points,
        );

        try std.testing.expectEqual(
            3,
            result.operators.len,
        );
    }

    // split_at_each -- end points are same, split offset
    {
        const pts1 = [_]opentime.Ordinate{
            opentime.Ordinate.init(0),
            opentime.Ordinate.init(4),
            opentime.Ordinate.init(8),
        };
        const pts2 = pts1;

        const inter = try cl_presentation_pmap.split_at_each(
            allocator,
            &pts1,
        );
        defer inter.deinit(allocator);

        const result = try inter.split_at_each(
            allocator,
            &pts2,
        );
        defer result.deinit(allocator);

        try std.testing.expectEqualSlices(
            opentime.Ordinate,
            &pts1,
            result.end_points,
        );

        try std.testing.expectEqual(
            2,
            result.operators.len,
        );
    }
}

test "ProjectionOperatorMap: merge_composite"
{
    const allocator = std.testing.allocator;

    var cl = schema.Clip {
        .bounds_s = test_data.T_INT_1_TO_9,
    };
    const cl_ptr = references.ComposedValueRef{ .clip = &cl };

    const map = try temporal_hierarchy.build_temporal_map(
        allocator,
        cl_ptr,
    );
    defer map.deinit(allocator);

    const cl_presentation_pmap = (
        try projection_map_to_media_from(
            allocator,
            map,
            cl_ptr.space(.presentation),
        )
    );
    defer cl_presentation_pmap.deinit(allocator);

    {
        const result = (
            try ProjectionOperatorMap.merge_composite(
                allocator,
                .{
                    .over = cl_presentation_pmap,
                    .under = cl_presentation_pmap,
                }
            )
        );
        defer result.deinit(allocator);

        try std.testing.expectEqualSlices(
            opentime.Ordinate,
            cl_presentation_pmap.end_points,
            result.end_points,
        );
        try std.testing.expectEqual(
            1,
            result.operators.len
        );
    }
}

test "ProjectionOperatorMap: clip"
{
    const allocator = std.testing.allocator;

    var cl = schema.Clip {
        .bounds_s = test_data.T_INT_1_TO_9,
    };
    const cl_ptr = references.ComposedValueRef{ .clip = &cl };

    const map = try temporal_hierarchy.build_temporal_map(
        allocator,
        cl_ptr,
    );
    defer map.deinit(allocator);

    const cl_presentation_pmap = (
        try projection_map_to_media_from(
            allocator,
            map,
            cl_ptr.space(.presentation),
        )
    );
    defer cl_presentation_pmap.deinit(allocator);

    try std.testing.expectEqual(1, cl_presentation_pmap.operators.len);
    try std.testing.expectEqual(2, cl_presentation_pmap.end_points.len);

    const cache = (
        try temporal_hierarchy.SingleSourceTopologyCache.init(
            allocator,
            map,
        )
    );
    defer cache.deinit(allocator);

    const known_presentation_to_media = (
        try temporal_hierarchy.build_projection_operator(
            allocator,
            map,
            .{
                .source = cl_ptr.space(.presentation),
                .destination = cl_ptr.space(.media),
            },
            cache,
        )
    );
    defer known_presentation_to_media.deinit(allocator);

    const known_input_bounds = (
        known_presentation_to_media.src_to_dst_topo.input_bounds()
    );

    const guess_presentation_to_media = (
        cl_presentation_pmap.operators[0][0]
    );
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
        cl_presentation_pmap.end_points[0],
        guess_input_bounds.start,
    );
    try opentime.expectOrdinateEqual(
        cl_presentation_pmap.end_points[1],
        guess_input_bounds.end,
    );

    // known input bounds matches end point
    try opentime.expectOrdinateEqual(
        known_input_bounds.start,
        cl_presentation_pmap.end_points[0],
    );
    try opentime.expectOrdinateEqual(
        known_input_bounds.end,
        cl_presentation_pmap.end_points[1],
    );
}

test "ProjectionOperatorMap: track with single clip"
{
    const allocator = std.testing.allocator;

    var cl = schema.Clip {
        .bounds_s = test_data.T_INT_1_TO_9,
    };
    const cl_ptr = references.ComposedValueRef.init(&cl);

    var tr_children = [_]references.ComposedValueRef{ cl_ptr, };
    var tr: schema.Track = .{ .children = &tr_children };
    const tr_ptr = references.ComposedValueRef.init(&tr);

    const map = try temporal_hierarchy.build_temporal_map(
        allocator,
        tr_ptr,
    );
    defer map.deinit(allocator);

    const source_space = tr_ptr.space(.presentation);

    const test_maps = &[_]ProjectionOperatorMap{
        // try build_projection_operator_map(
        //     allocator,
        //     map,
        //     cl_ptr.space(.presentation),
        // ),
        try projection_map_to_media_from(
            allocator,
            map,
            source_space,
        ),
    };

    for (test_maps)
        |projection_operator_map|
    {
        defer projection_operator_map.deinit(allocator);

        try std.testing.expectEqual(1, projection_operator_map.operators.len);
        try std.testing.expectEqual(2, projection_operator_map.end_points.len);

    const cache = (
        try temporal_hierarchy.SingleSourceTopologyCache.init(
            allocator,
            map,
        )
    );
    defer cache.deinit(allocator);

        const known_presentation_to_media = try temporal_hierarchy.build_projection_operator(
            allocator,
            map,
            .{
                .source = tr_ptr.space(.presentation),
                .destination = cl_ptr.space(.media),
            },
            cache,
        );
        defer known_presentation_to_media.deinit(allocator);
        const known_input_bounds = (
            known_presentation_to_media.src_to_dst_topo.input_bounds()
        );

        const guess_presentation_to_media = (
            projection_operator_map.operators[0][0]
        );
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
            projection_operator_map.end_points[0],
            guess_input_bounds.start,
        );
        try opentime.expectOrdinateEqual(
            projection_operator_map.end_points[1],
            guess_input_bounds.end,
        );

        // known input bounds matches end point
        try opentime.expectOrdinateEqual(
            known_input_bounds.start,
            projection_operator_map.end_points[0],
        );
        try opentime.expectOrdinateEqual(
            known_input_bounds.end,
            projection_operator_map.end_points[1],
        );
    }
}

test "projection.ProjectionOperator: clone"
{
    const allocator = std.testing.allocator;

    const aff1 = try topology_m.Topology.init_affine(
        allocator,
        .{
            .input_bounds_val = .{
                .start = opentime.Ordinate.init(0),
                .end = opentime.Ordinate.init(8),
            },
            .input_to_output_xform = .{
                .offset = opentime.Ordinate.init(1),
            },
        },
    );
    defer aff1.deinit(allocator);

    var cl = schema.Clip{};
    const cl_ptr = references.ComposedValueRef.init(&cl);

    const po = ProjectionOperator{
        .source = cl_ptr.space(.presentation),
        .destination = cl_ptr.space(.media),
        .src_to_dst_topo = aff1,
    };

    const po_cloned = try po.clone(allocator);
    const po_cloned_again = try po_cloned.clone(allocator);
    defer po_cloned_again.deinit(allocator);
    po_cloned.deinit(allocator);

    try opentime.expectOrdinateEqual(
        4,
        try po_cloned_again.project_instantaneous_cc(
            opentime.Ordinate.init(3),
        ).ordinate(),
    );
}

test "ProjectionOperatorMap: clone"
{
    const allocator = std.testing.allocator;
    var cl = schema.Clip{};
    const cl_ptr = references.ComposedValueRef{ 
        .clip = &cl 
    };
    const aff1 = try topology_m.Topology.init_affine(
        allocator,
        .{
            .input_bounds_val = .{
                .start = opentime.Ordinate.init(0),
                .end = opentime.Ordinate.init(8),
            },
            .input_to_output_xform = .{
                .offset = opentime.Ordinate.init(1),
            },
        },
    );
    const child_op_map = (
        try ProjectionOperatorMap.init_operator(
            allocator,
            .{
                .source = cl_ptr.space(.presentation),
                .destination = cl_ptr.space(.media),
                .src_to_dst_topo = aff1,
            },
        )
    );

    const clone = try child_op_map.clone(allocator);
    defer clone.deinit(allocator);

    child_op_map.deinit(allocator);

    const topo = clone.operators[0][0].src_to_dst_topo;

    try opentime.expectOrdinateEqual(
        4,
        try topo.project_instantaneous_cc(opentime.Ordinate.init(3)).ordinate()
    );
}

test "transform: track with two clips"
{
    const allocator = std.testing.allocator;

    var cl1 = schema.Clip {
        .bounds_s = test_data.T_INT_1_TO_9,
    };
    var cl2 = schema.Clip {
        .bounds_s = test_data.T_INT_1_TO_4,
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

    const track_presentation_space = tr_ptr.space(.presentation);

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

        const cache = (
            try temporal_hierarchy.SingleSourceTopologyCache.init(
                allocator,
                map,
            )
        );
        defer cache.deinit(allocator);

        const po = try temporal_hierarchy.build_projection_operator(
            allocator,
            map,
            .{
                .source = cl2_ref.space(.presentation),
                .destination = cl2_ref.space(.media),
            },
            cache,
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
    const cache = (
        try temporal_hierarchy.SingleSourceTopologyCache.init(
            allocator,
            map,
        )
    );
    defer cache.deinit(allocator);

        const xform = try temporal_hierarchy.build_projection_operator(
            allocator,
            map,
            .{
                .source = track_presentation_space,
                .destination = cl2_ref.space(.media),
            },
            cache,
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
            .bounds_s = test_data.T_INT_1_TO_9,
        },
        .{
            .bounds_s = test_data.T_INT_1_TO_9,
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

    const source_space = tr_ptr.space(.presentation);

    const p_o_map = (
        try projection_map_to_media_from(
            allocator,
            map,
            source_space,
        )
    );
    defer p_o_map.deinit(allocator);

    /////

    try std.testing.expectEqualSlices(
        opentime.Ordinate,
        (&test_data.T_ORD_ARR_0_8_16_21)[0..3],
        p_o_map.end_points,
    );
    try std.testing.expectEqual(2, p_o_map.operators.len);

    const cache = (
        try temporal_hierarchy.SingleSourceTopologyCache.init(
            allocator,
            map,
        )
    );
    defer cache.deinit(allocator);

    const known_presentation_to_media = (
        try temporal_hierarchy.build_projection_operator(
            allocator,
            map,
            .{
                .source = tr_ptr.space(.presentation),
                .destination = cl_ptr.space(.media),
            },
            cache,
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
        .bounds_s = test_data.T_INT_1_TO_9,
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

    const source_space = tr_ptr.space(.presentation);

    const p_o_map = (
        try projection_map_to_media_from(
            allocator,
            map,
            source_space,
        )
    );

    defer p_o_map.deinit(allocator);

    try std.testing.expectEqualSlices(
        opentime.Ordinate,
        &test_data.T_ORD_ARR_0_8_13_21,
        p_o_map.end_points,
    );
    try std.testing.expectEqual(3, p_o_map.operators.len);

    const cache = (
        try temporal_hierarchy.SingleSourceTopologyCache.init(
            allocator,
            map,
        )
    );
    defer cache.deinit(allocator);

    const known_presentation_to_media = (
        try temporal_hierarchy.build_projection_operator(
            allocator,
            map,
            .{
                .source = tr_ptr.space(.presentation),
                .destination = cl_ptr.space(.media),
            },
            cache,
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

test "Projection: schema.Track with single clip with identity transform and bounds" 
{
    const allocator = std.testing.allocator;

    var cl = schema.Clip{
        .bounds_s = test_data.T_INT_0_TO_2,
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

    try std.testing.expectEqual(5, map.path_nodes.len);
    try std.testing.expectEqual(5, map.space_nodes.len);
    try std.testing.expectEqual(
        5,
        map.map_space_to_path_index.count()
    );

    const cache = (
        try temporal_hierarchy.SingleSourceTopologyCache.init(
            allocator,
            map,
        )
    );
    defer cache.deinit(allocator);

    const root_presentation_to_clip_media = try temporal_hierarchy.build_projection_operator(
        allocator,
        map,
        .{ 
            .source = root.space(references.SpaceLabel.presentation),
            .destination = clip.space(references.SpaceLabel.media),
        },
        cache,
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
            .bounds_s = test_data.T_INT_0_TO_2 
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
    const cache = (
        try temporal_hierarchy.SingleSourceTopologyCache.init(
            allocator,
            map,
        )
    );
    defer cache.deinit(allocator);

        const po = try temporal_hierarchy.build_projection_operator(
            allocator,
            map,
            .{
                .source = track_ptr.space(.presentation),
                .destination = (
                    cl2_ref.space(.media)
                ),
            },
            cache,
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

    const po_map = try projection_map_to_media_from(
        allocator,
        map,
        track_ptr.space(.presentation),
    );
    defer po_map.deinit(allocator);

    try std.testing.expectEqual(
        3,
        po_map.operators.len,
    );

    // 1
    for (po_map.operators,
        &[_][2]opentime.Ordinate{ 
            .{ test_data.T_O_0, test_data.T_O_2 },
            .{ test_data.T_O_2, test_data.T_O_4 },
            .{ test_data.T_O_4, test_data.T_O_6 } 
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
            test_data.T_O_0,
            test_data.T_O_2,
            test_data.T_O_4,
            test_data.T_O_6,
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

    const cache = (
        try temporal_hierarchy.SingleSourceTopologyCache.init(
            allocator,
            map,
        )
    );
    defer cache.deinit(allocator);

        const tr_presentation_to_clip_media = try temporal_hierarchy.build_projection_operator(
        allocator,
        map,
            .{
                .source = track_ptr.space(references.SpaceLabel.presentation),
                .destination = child.space(references.SpaceLabel.media),
            },
            cache,
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

    const cache = (
        try temporal_hierarchy.SingleSourceTopologyCache.init(
            allocator,
            map,
        )
    );
    defer cache.deinit(allocator);

    const root_presentation_to_clip_media = try temporal_hierarchy.build_projection_operator(
        allocator,
        map,
        .{ 
            .source = track_ptr.space(references.SpaceLabel.presentation),
            .destination = clip.space(references.SpaceLabel.media),
        },
        cache,
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
    const cache = (
        try temporal_hierarchy.SingleSourceTopologyCache.init(
            allocator,
            map,
        )
    );
    defer cache.deinit(allocator);

        const clip_presentation_to_media_proj = (
            try temporal_hierarchy.build_projection_operator(
                allocator,
                map,
                .{
                    .source =  wp_ptr.space(references.SpaceLabel.presentation),
                    .destination = cl_ptr.space(references.SpaceLabel.media),
                },
                cache,
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
    const cache = (
        try temporal_hierarchy.SingleSourceTopologyCache.init(
            allocator,
            map,
        )
    );
    defer cache.deinit(allocator);

        const clip_media_to_presentation = (
            try temporal_hierarchy.build_projection_operator(
                allocator,
                map,
                .{
                    .source =  cl_ptr.space(references.SpaceLabel.media),
                    .destination = wp_ptr.space(references.SpaceLabel.presentation),
                },
                cache,
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
    const spaces = it.spaces();

    try std.testing.expectEqual(
       references.SpaceLabel.presentation,
       spaces[0], 
    );
    try std.testing.expectEqual(
       references.SpaceLabel.media,
       spaces[1], 
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
    const media_source_range = test_data.T_INT_1_TO_9;
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

    const cache = (
        try temporal_hierarchy.SingleSourceTopologyCache.init(
            allocator,
            map,
        )
    );
    defer cache.deinit(allocator);

    const track_to_media = (
        try temporal_hierarchy.build_projection_operator(
            allocator,
            map,
            .{
                .source = tr_ptr.space(references.SpaceLabel.presentation),
                // does the discrete / continuous need to be disambiguated?
                .destination = cl_ptr.space(references.SpaceLabel.media),
            },
            cache,
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
    const media_source_range = test_data.T_INT_1_TO_9;
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
                .input_bounds_val = .INF,
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

    const cache_tr = (
        try temporal_hierarchy.SingleSourceTopologyCache.init(
            allocator,
            map_tr,
        )
    );
    defer cache_tr.deinit(allocator);

    const track_to_media = (
        try temporal_hierarchy.build_projection_operator(
            allocator,
            map_tr,
            .{
                .source = tr_ptr.space(.presentation),
                // does the discrete / continuous need to be disambiguated?
                .destination = cl_ptr.space(.media),
            },
            cache_tr,
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

    const cache = (
        try temporal_hierarchy.SingleSourceTopologyCache.init(
            allocator,
            map_tl,
        )
    );
    defer cache.deinit(allocator);

            const timeline_to_media = (
                try temporal_hierarchy.build_projection_operator(
                    allocator,
                    map_tl,
                    .{
                        .source = tl_ptr.space(.presentation),
                        // does the discrete / continuous need to be disambiguated?
                        .destination = cl_ptr.space(.media),
                    },
                    cache,
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

    const cl_media = cl_ptr.space(references.SpaceLabel.media);

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
        const wp_pres = wp_ptr.space(references.SpaceLabel.presentation);

        const map = try temporal_hierarchy.build_temporal_map(
            allocator,
            wp_ptr,
        );
        defer map.deinit(allocator);

        try temporal_hierarchy.validate_connections_in_map(map);

        // presentation->media (forward projection)
        {
            const cache = (
                try temporal_hierarchy.SingleSourceTopologyCache.init(
                    allocator,
                    map,
                )
            );
            defer cache.deinit(allocator);

            const warp_pres_to_media_topo = (
                try temporal_hierarchy.build_projection_operator(
                    allocator,
                    map,
                    .{
                        .source =  wp_pres,
                        .destination = cl_media,
                    },
                    cache,
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
            const cache = (
                try temporal_hierarchy.SingleSourceTopologyCache.init(
                    allocator,
                    map,
                )
            );
            defer cache.deinit(allocator);

            const clip_media_to_presentation = (
                try temporal_hierarchy.build_projection_operator(
                    allocator,
                    map,
                    .{
                        .source =  cl_media,
                        .destination = wp_pres,
                    },
                    cache,
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

pub fn ReferenceTopology(
    comptime SpaceReferenceType: type,
) type
{
    return struct {
        pub const ReferenceTopologyType = @This();

        // @TODO: remove these
        pub const NodeIndex = usize;
        pub const SpaceNodeIndex = usize;

        /// a transformation to a particular destination space
        const ReferenceMapping = struct {
            destination: SpaceNodeIndex,
            mapping: topology_m.Mapping,
        };

        /// associates an interval with a mapping
        const IntervalMapping = struct {
            mapping_index: []NodeIndex,
            input_bounds: opentime.ContinuousInterval,
        };

        source: SpaceReferenceType,
        mappings: std.MultiArrayList(ReferenceMapping),

        // temporally sorted, could be more efficient with a BVH of some kind
        intervals: std.MultiArrayList(IntervalMapping),
        temporal_map: treecode.Map(SpaceReferenceType),

        pub fn init_from_reference(
            parent_allocator: std.mem.Allocator,
            temporal_map: treecode.Map(SpaceReferenceType),
            source_reference: SpaceReferenceType,
        ) !ReferenceTopologyType
        {
            var arena = std.heap.ArenaAllocator.init(
                parent_allocator,
            );
            defer arena.deinit();
            const allocator_arena = arena.allocator();

            var self: ReferenceTopologyType = .{
                .source = source_reference,
                .mappings = .empty,
                .intervals = .empty,
                .temporal_map = temporal_map,
            };

            var unsplit_intervals: std.MultiArrayList(
                struct {
                    mapping_index: NodeIndex,
                    input_bounds: opentime.ContinuousInterval,
                }
            ) = .empty;
            defer unsplit_intervals.deinit(allocator_arena);

            const vertex_kind = enum(u1) { start, end };

            // to sort and split the intervals
            var vertices_builder : std.MultiArrayList(
                struct{ 
                    ordinate: opentime.Ordinate,
                    interval_index: NodeIndex,
                    kind: vertex_kind,
                },
            ) = .empty;
            defer vertices_builder.deinit(allocator_arena);

            const cache = (
                try temporal_hierarchy.SingleSourceTopologyCache.init(
                    allocator_arena,
                    temporal_map,
                )
            );
            defer cache.deinit(allocator_arena);

            // Gather up all the operators and intervals
            /////////////
            const map_nodes = temporal_map.path_nodes.slice();

            const start_index = temporal_map.index_from_space(
                source_reference
            ) orelse return error.SourceNotInMap;

            var proj_args:temporal_hierarchy.PathEndPointIndices = .{
                .source = start_index,
                .destination = start_index,
            };

            const codes = map_nodes.items(.code);
            const source_code = codes[start_index];
            const children = map_nodes.items(.child_indices);

            for (codes, children, 0..)
                |current_code, child_ptrs, current_index|
            {
                if (
                    // only looking for terminal scopes (gaps, clips, etc)
                    (child_ptrs[0] != null or child_ptrs[1] != null)
                    // skip all media spaces that don't have a path to source
                    or source_code.is_prefix_of(current_code) == false
                ) 
                {
                    continue;
                }

                proj_args.destination = current_index;

                const proj_op = (
                    try temporal_hierarchy.build_projection_operator_indices(
                        allocator_arena,
                        temporal_map,
                        proj_args,
                        cache,
                    )
                );

                const to_dest_topo = proj_op.src_to_dst_topo;

                try unsplit_intervals.ensureUnusedCapacity(
                    allocator_arena,
                    to_dest_topo.mappings.len
                );
                try self.mappings.ensureUnusedCapacity(
                    parent_allocator,
                    to_dest_topo.mappings.len
                );
                try vertices_builder.ensureUnusedCapacity(
                    allocator_arena,
                    2 * to_dest_topo.mappings.len,
                );

                for (to_dest_topo.mappings)
                    |child_mapping|
                {
                    const new_index = self.mappings.len;
                    const new_bounds = (
                        child_mapping.input_bounds()
                    );
                    unsplit_intervals.appendAssumeCapacity(
                        .{
                            .input_bounds = new_bounds,
                            .mapping_index = new_index,
                        },
                    );
                    self.mappings.appendAssumeCapacity(
                        .{
                            .destination = proj_args.destination,
                            .mapping = child_mapping,
                        },
                    );
                    vertices_builder.appendAssumeCapacity(
                        .{
                            .interval_index = new_index,
                            .ordinate = new_bounds.start,
                            .kind = .start,
                        },
                    );
                    vertices_builder.appendAssumeCapacity(
                        .{
                            .interval_index = new_index,
                            .ordinate = new_bounds.end,
                            .kind = .end,
                        },
                    );
                }
            }

            // sort the vertices
            ///////////
            const vertices = vertices_builder.slice();
            vertices_builder.sortUnstable(
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
                }{ .ordinates = vertices.items(.ordinate) }
            );

            const IntervalRef = struct {
                index: NodeIndex,
                kind: vertex_kind,
            };

            var cut_points: std.MultiArrayList(
                struct{
                    ordinate: opentime.Ordinate,
                    indices: []NodeIndex,
                    kind: []vertex_kind,
                }
            ) = .empty;
            try cut_points.ensureTotalCapacity(
                allocator_arena,
                vertices.len,
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

            // merge the intervals and combine the lists
            ///////////
            var cut_point = vertices.items(.ordinate)[0];
            var current_intervals: std.MultiArrayList(IntervalRef) = .empty;
            try current_intervals.append(
                allocator_arena, 
                .{
                    .index = vertices.items(.interval_index)[0],
                    .kind = vertices.items(.kind)[0],
                },
            );

            for (
                vertices.items(.interval_index),
                vertices.items(.kind),
                vertices.items(.ordinate),
            ) |int_ind, kind, vert|
            {
                // if the ordinate is not close enough, then create a new vert
                if (vert.eql_approx(cut_point) == false)
                {
                    var compled = current_intervals.toOwnedSlice();

                    cut_points.appendAssumeCapacity(
                        .{
                            .ordinate = cut_point,
                            .indices = compled.items(.index),
                            .kind = compled.items(.kind),
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
                var compled = current_intervals.toOwnedSlice();
                try cut_points.append(
                    allocator_arena,
                    .{
                        .ordinate = cut_point,
                        .indices = compled.items(.index),
                        .kind = compled.items(.kind),
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
            ////////////
            var active_intervals = try (
                std.DynamicBitSetUnmanaged.initEmpty(
                    allocator_arena,
                    cut_point_slice.len,
                )
            );

            const ordinates = cut_point_slice.items(.ordinate);
            const len = ordinates.len;

            try self.intervals.ensureTotalCapacity(
                parent_allocator,
                len - 1
            );

            var indices:  std.ArrayList(NodeIndex) = .empty;

            for (
                ordinates[0..len - 1],
                ordinates[1..],
                cut_point_slice.items(.kind)[0..len - 1],
                cut_point_slice.items(.indices)[0..len - 1],
            ) |ord_start, ord_end, kinds, intervals|
            {
                for (kinds, intervals)
                    |kind, interval|
                {
                    if (kind == .start)
                    {
                        active_intervals.setValue(interval, true);
                    }
                    else if (kind == .end)
                    {
                        active_intervals.setValue(interval, false);
                    }
                }

                var bit_iter = (
                    active_intervals.iterator(.{})
                );

                try indices.ensureTotalCapacity(
                    parent_allocator,
                    active_intervals.count()
                );

                while (bit_iter.next())
                    |index|
                {
                    indices.appendAssumeCapacity(index);
                }

                self.intervals.appendAssumeCapacity(
                    .{
                        .input_bounds = .{
                            .start = ord_start,
                            .end = ord_end,
                        },
                        .mapping_index = try indices.toOwnedSlice(
                            parent_allocator
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
        }

        /// return the input range for this ReferenceTopology
        pub fn input_bounds(
            self: @This(),
        ) opentime.ContinuousInterval
        {
            return .{
                .start = self.intervals.items(.input_bounds)[0].start,
                .end = self.intervals.items(.input_bounds)[self.intervals.len-1].end,
            };
        }

        pub fn format(
            self: @This(),
            writer: *std.Io.Writer,
        ) !void 
        {
            try writer.print(
                "Total timeline interval: {f}\n",
                .{ self.input_bounds(), },
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
                    const output_bounds = mapping.mapping.output_bounds();
                    const destination = (
                        self.temporal_map.space_nodes.get(
                        mapping.destination
                    )
                    );

                    try writer.print(
                        "    -> {f} | {f}\n",
                        .{
                            destination,
                            output_bounds,
                        }
                    );
                }
            }

        }
    };
}

pub const ProjectionTopology = ReferenceTopology(references.SpaceReference);

test "ReferenceTopology: init_from_reference"
{
    const allocator = std.testing.allocator;

    var cl = schema.Clip {
        .name = "clip1",
        .bounds_s = test_data.T_INT_1_TO_9,
    };
    const cl_ptr = cl.reference();
    cl.media.discrete_info = .{
        .sample_rate_hz = .{ .Int = 24 },
        .start_index = 86400,
    };

    var cl2 = schema.Clip {
        .name = "clip2",
        .bounds_s = test_data.T_INT_1_TO_9,
    };
    const cl2_ptr = cl2.reference();
    cl2.media.discrete_info = .{
        .sample_rate_hz = .{ .Int = 30 },
        .start_index = 0,
    };

    var tr_children: [2]references.ComposedValueRef = .{cl_ptr, cl2_ptr};
    var tr1 = schema.Track {
        .children = &tr_children,
    };
    const tr1_ptr = tr1.reference();

    var cl3 = schema.Clip {
        .name = "clip3_warped",
        .bounds_s = test_data.T_INT_1_TO_9,
    };
    cl3.media.discrete_info = .{
        .sample_rate_hz = .{ .Int = 24 },
        .start_index = 0,
    };
    const cl3_ptr = cl3.reference();
    var wp1 = schema.Warp {
        .name = "Warp on Clip3",
        .child = cl3_ptr,
        .transform = .{
            .mappings = &.{ 
                (
                 topology_m.mapping.MappingAffine{
                     .input_to_output_xform = .{
                         .scale = opentime.Ordinate.init(3),
                     },
                     .input_bounds_val = .INF,
                 }
                ).mapping(),
            },
        },
    };
    const wp_ref = wp1.reference();
    var tr2_children: [1]references.ComposedValueRef = .{wp_ref};
    var tr2 = schema.Track {
        .children = &tr2_children,
    };
    const tr2_ptr = tr2.reference();

    var st_children: [2]references.ComposedValueRef = .{ tr1_ptr, tr2_ptr };
    var tl = schema.Timeline {
        .tracks = .{
            .children = &st_children,
        },
    };
    const tl_ref = tl.reference();

    const map = try temporal_hierarchy.build_temporal_map(
        allocator,
        tl_ref,
    );
    defer map.deinit(allocator);

    var projection_topo = (
        try ProjectionTopology.init_from_reference(
            allocator,
            map,
            tl_ref.space(.presentation),
        )
    );
    defer projection_topo.deinit(allocator);

    std.debug.print("Mappings:\n", .{});
    for (projection_topo.mappings.items(.mapping), 0..)
        |m, ind|
    {
        std.debug.print("  {d}: {f}\n", .{ind, m});
    }

    std.debug.print("Tracks: {d}\n", .{tl.tracks.children.len});
    var items: usize = 0;
    for (tl.tracks.children, 0..)
        |child, ind|
    {
        std.debug.print(
            "  Track [{d}]: {d} items\n",
            .{ind, child.track.children.len},
        );
        items += child.track.children.len;
        for (child.track.children)
            |tc|
        {
            std.debug.print("    {f}\n", .{tc});
        }
    }

    tl.discrete_info.presentation = .{
        .sample_rate_hz = .{ .Int = 24 },
        .start_index = 86400,
    };

    std.debug.print("Total items: {d}\n", .{items});

    const intervals = projection_topo.intervals.items(
        .input_bounds
    );

    const interval:opentime.ContinuousInterval = .{
        .start = intervals[0].start,
        .end = intervals[intervals.len - 1].end,
    };

    std.debug.print(
        "\n\nTotal timeline interval: {f} indices: [{d}, {d}]\n",
        .{
            interval,
            try tl_ref.continuous_ordinate_to_discrete_index(
                interval.start, 
                .presentation,
            ),
            try tl_ref.continuous_ordinate_to_discrete_index(
                interval.end,
                .presentation
            ) - 1,
        },
    );

    std.debug.print(
        "Intervals mapping (showing intervals 0-10):\n",
        .{},
    );
    for (0..@min(10, projection_topo.intervals.len))
        |ind|
    {
        const first_interval_mapping = (
            projection_topo.intervals.get(ind)
        );
        std.debug.print(
            "  Presentation Space Range: {f} (index: [{d}, {d}])\n",
            .{
                first_interval_mapping.input_bounds,
                try tl_ref.continuous_ordinate_to_discrete_index(
                    first_interval_mapping.input_bounds.start, 
                    .presentation,
                ),
                try tl_ref.continuous_ordinate_to_discrete_index(
                    first_interval_mapping.input_bounds.end,
                    .presentation
                ) - 1,
            }
        );
        for (first_interval_mapping.mapping_index)
            |mapping_ind|
        {
            const mapping = projection_topo.mappings.get(
                mapping_ind
            );
            const output_bounds = (
                mapping.mapping.output_bounds()
            );
            const destination = map.space_nodes.get(
                mapping.destination
            );

            const start_ind = (
                try destination.ref.continuous_ordinate_to_discrete_index(
                    output_bounds.start, 
                    .media,
                )
            );
            const end_ind_inc = (
                try destination.ref.continuous_ordinate_to_discrete_index(
                    output_bounds.end,
                    .media
                ) - 1
            );

            std.debug.print(
                "    -> {f} | {f} ([{d}, {d}] / {d} samples)\n",
                .{
                    destination,
                    output_bounds,
                    start_ind,
                    end_ind_inc,
                    end_ind_inc-start_ind,
                }
            );
        }
    }
}
