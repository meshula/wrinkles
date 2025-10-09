const std = @import("std");

const opentime = @import("opentime");
const sampling = @import("sampling");
const topology_m = @import("topology");

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
            try topology_m.Topology.init_affine(
                allocator,
                .{ 
                    .input_to_output_xform = .{ 
                        .offset = range_in_source.start,
                        .scale = opentime.Ordinate.init(1.0),
                    },
                    .input_bounds_val = .{
                        .start = opentime.Ordinate.init(0),
                        .end = range_in_source.duration(),
                    },
                }
            )
        );
        defer topology_in_source.deinit(allocator);

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
            try topology_m.Topology.init_affine(
                allocator,
                .{ 
                    .input_bounds_val = range_in_source,
                }
            )
        );
        defer in_to_source_topo.deinit(allocator);

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

/// maps projections to clip.media spaces to regions of whatever space is
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

    const all_spaces = map.nodes.items(.space);
    for (all_spaces)
        |current|
    {
        // skip all spaces that are not media spaces
        if (current.label != .media) {
            continue;
        }

        proj_args.destination = current;

        const child_op = (
            try temporal_hierarchy.build_projection_operator(
                allocator,
                map,
                proj_args,
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
                .source = try cl_ptr.space(.presentation),
                .destination = try cl_ptr.space(.media),
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
        try cl_ptr.space(.presentation),
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
            try cl_ptr.space(.presentation),
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
            try cl_ptr.space(.presentation),
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
            try cl_ptr.space(.presentation),
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
            try cl_ptr.space(.presentation),
        )
    );
    defer cl_presentation_pmap.deinit(allocator);

    try std.testing.expectEqual(1, cl_presentation_pmap.operators.len);
    try std.testing.expectEqual(2, cl_presentation_pmap.end_points.len);

    const known_presentation_to_media = (
        try temporal_hierarchy.build_projection_operator(
            allocator,
            map,
            .{
                .source = try cl_ptr.space(.presentation),
                .destination = try cl_ptr.space(.media),
            },
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

    const source_space = try tr_ptr.space(.presentation);

    const test_maps = &[_]ProjectionOperatorMap{
        // try build_projection_operator_map(
        //     allocator,
        //     map,
        //     try cl_ptr.space(.presentation),
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

        const known_presentation_to_media = try temporal_hierarchy.build_projection_operator(
            allocator,
            map,
            .{
                .source = try tr_ptr.space(.presentation),
                .destination = try cl_ptr.space(.media),
            },
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

test "projections.ProjectionOperator: clone"
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
        .source = try cl_ptr.space(.presentation),
        .destination = try cl_ptr.space(.media),
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
                .source = try cl_ptr.space(.presentation),
                .destination = try cl_ptr.space(.media),
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
