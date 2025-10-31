//! Structures and functions around projections through the temporal hierarchy

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

const GRAPH_CONSTRUCTION_TRACE_MESSAGES = false;

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

    ///project a continuous ordinate to the continuous destination space,
    ///assuming that the ordinate_in_source_space is within the bounds of the
    ///src_to_dst_topo (will _not_ perform a bounds check)
    pub fn project_instantaneous_cc_assume_in_bounds(
        self: @This(),
        ordinate_in_source_space: opentime.Ordinate,
    ) opentime.ProjectionResult
    {
        return self.src_to_dst_topo.project_instantaneous_cc_assume_in_bounds(
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
            self.destination.ref.discrete_info_for_space(
                self.destination.label,
            )
        ) orelse {
            return error.NoDiscreteInfoForDestinationSpace;
        };
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

test "ReferenceTopology: leak test"
{
    const allocator = std.testing.allocator;

    var cl = schema.Clip {
        .bounds_s = test_data.T_INT_1_TO_9,
    };
    const cl_ptr = references.ComposedValueRef.init(&cl);

    var cl_pres_proj_topo = try ProjectionTopology.init_from(
        allocator,
        cl_ptr.space(.presentation)
    );
    defer cl_pres_proj_topo.deinit(allocator);

    const cl_pres_to_cl_media = (
        try cl_pres_proj_topo.projection_operator_to(
            allocator,
            cl_ptr.space(.media),
        )
    );

    try opentime.expectOrdinateEqual(
        4,
        cl_pres_to_cl_media.project_instantaneous_cc(
            opentime.Ordinate.init(3)
        ).ordinate()
    );
}

test "ProjectionOperatorMap: clip"
{
    const allocator = std.testing.allocator;

    var cl = schema.Clip {
        .bounds_s = test_data.T_INT_1_TO_9,
    };
    const cl_ptr = references.ComposedValueRef{ .clip = &cl };

    var cl_pres_projection_builder = (
        try ProjectionTopology.init_from(
            allocator,
            cl_ptr.space(.presentation),
        )
    );
    defer cl_pres_projection_builder.deinit(allocator);

    try std.testing.expectEqual(
        1,
        cl_pres_projection_builder.intervals.len,
    );
    try std.testing.expectEqual(
        1,
        cl_pres_projection_builder.mappings.len,
    );

    const known_presentation_to_media = (
        try build_projection_operator(
            allocator,
            cl_pres_projection_builder.temporal_space_graph,
            .{
                .source = cl_ptr.space(.presentation),
                .destination = cl_ptr.space(.media),
            },
            cl_pres_projection_builder.cache,
        )
    );

    const known_input_bounds = (
        known_presentation_to_media.src_to_dst_topo.input_bounds()
    );

    const guess_presentation_to_media = (
        cl_pres_projection_builder.mappings.items(.mapping)[0]
    );
    const guess_input_bounds = (
        guess_presentation_to_media.input_bounds()
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
        cl_pres_projection_builder.intervals.items(.input_bounds)[0].start,
        guess_input_bounds.start,
    );
    try opentime.expectOrdinateEqual(
        cl_pres_projection_builder.intervals.items(.input_bounds)[0].end,
        guess_input_bounds.end,
    );

    // known input bounds matches end point
    try opentime.expectOrdinateEqual(
        known_input_bounds.start,
        cl_pres_projection_builder.intervals.items(.input_bounds)[0].start,
    );
    try opentime.expectOrdinateEqual(
        known_input_bounds.end,
        cl_pres_projection_builder.intervals.items(.input_bounds)[0].end,
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

    const source_space = tr_ptr.space(.presentation);

    var test_maps = [_]ProjectionTopology{
        try ProjectionTopology.init_from(
            allocator,
            cl_ptr.space(.presentation),
        ),
        try ProjectionTopology.init_from(
            allocator,
            source_space,
        ),
    };

    for (&test_maps)
        |*projection_builder|
    {
        defer projection_builder.deinit(allocator);

        try std.testing.expectEqual(
            1,
            projection_builder.mappings.len,
        );
        try std.testing.expectEqual(
            1,
            projection_builder.intervals.len,
        );

        const known_presentation_to_media = try build_projection_operator(
            allocator,
            projection_builder.temporal_space_graph,
            .{
                .source = projection_builder.source,
                .destination = cl_ptr.space(.media),
            },
            projection_builder.cache,
        );
        const known_input_bounds = (
            known_presentation_to_media.src_to_dst_topo.input_bounds()
        );

        const guess_presentation_to_media = (
            projection_builder.mappings.items(.mapping)[0]
        );
        const guess_input_bounds = guess_presentation_to_media.input_bounds();

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
            projection_builder.intervals.items(.input_bounds)[0].start,
            guess_input_bounds.start,
        );
        try opentime.expectOrdinateEqual(
            projection_builder.intervals.items(.input_bounds)[0].end,
            guess_input_bounds.end,
        );

        // known input bounds matches end point
        try opentime.expectOrdinateEqual(
            known_input_bounds.start,
            projection_builder.intervals.items(.input_bounds)[0].start,
        );
        try opentime.expectOrdinateEqual(
            known_input_bounds.end,
            projection_builder.intervals.items(.input_bounds)[0].end,
        );
    }
}

test "ProjectionOperator: clone"
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

    const map = try temporal_hierarchy.build_temporal_graph(
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
            try SingleSourceTopologyCache.init(
                allocator,
                map,
            )
        );
        defer cache.deinit(allocator);

        const po = try build_projection_operator(
            allocator,
            map,
            .{
                .source = cl2_ref.space(.presentation),
                .destination = cl2_ref.space(.media),
            },
            cache,
        );
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
            try SingleSourceTopologyCache.init(
                allocator,
                map,
            )
        );
        defer cache.deinit(allocator);

        const xform = try build_projection_operator(
            allocator,
            map,
            .{
                .source = track_presentation_space,
                .destination = cl2_ref.space(.media),
            },
            cache,
        );
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

test "ProjectionTopology: track with two clips"
{
    const allocator = std.testing.allocator;

    var clips = [_]schema.Clip{
        .{
            .bounds_s = test_data.T_INT_1_TO_9,
        },
        .{
            .bounds_s = test_data.T_INTERVAL_ARR_0_8_12_20[1],
        },
        .{
            .bounds_s = test_data.T_INT_1_TO_9,
        },
    };
    const cl_ptr = references.ComposedValueRef.init(&clips[1]);

    var tr_children = [_]references.ComposedValueRef{
        clips[0].reference(),
        clips[1].reference(),
        clips[2].reference(),
    };
    var tr: schema.Track = .{ .children = &tr_children };
    const tr_ptr = references.ComposedValueRef.init(&tr);

    const source_space = tr_ptr.space(.presentation);

    var cl_pres_projection_builder = (
        try ProjectionTopology.init_from(
            allocator,
            source_space,
        )
    );
    defer cl_pres_projection_builder.deinit(allocator);

    try std.testing.expectEqualSlices(
        opentime.ContinuousInterval,
        &test_data.T_INTERVAL_ARR_0_8_12_20,
        cl_pres_projection_builder.intervals.items(.input_bounds),
    );
    try std.testing.expectEqual(
        3,
        cl_pres_projection_builder.intervals.len,
    );

    const known_presentation_to_media = (
        try build_projection_operator(
            allocator,
            cl_pres_projection_builder.temporal_space_graph,
            .{
                .source = tr_ptr.space(.presentation),
                .destination = cl_ptr.space(.media),
            },
            cl_pres_projection_builder.cache,
        )
    );

    const known_input_bounds = (
        known_presentation_to_media.src_to_dst_topo.input_bounds()
    );

    const guess_presentation_to_media = cl_pres_projection_builder.mappings.items(.mapping)[1];
    const guess_input_bounds = guess_presentation_to_media.input_bounds();

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
        12,
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
        .duration_seconds = opentime.Ordinate.init(4),
    };
    var cl2 = schema.Clip {
        .bounds_s = test_data.T_INT_1_TO_9,
    };
    const cl2_ptr = cl2.reference();

    var tr_children = [_]references.ComposedValueRef{ 
        cl.reference(),
        references.ComposedValueRef.init(&gp),
        cl2_ptr,
    };
    var tr: schema.Track = .{ .children = &tr_children, };
    const tr_ptr = references.ComposedValueRef.init(&tr);

    var tr_pres_projection_builder = (
        try ProjectionTopology.init_from(
            allocator,
            tr_ptr.space(.presentation),
        )
    );
    defer tr_pres_projection_builder.deinit(allocator);

    try std.testing.expectEqualSlices(
        opentime.ContinuousInterval,
        &test_data.T_INTERVAL_ARR_0_8_12_20,
        tr_pres_projection_builder.intervals.items(.input_bounds),
    );
    try std.testing.expectEqual(
        3,
        tr_pres_projection_builder.intervals.len,
    );

    const tr_pres_to_cl_media = (
        try tr_pres_projection_builder.projection_operator_to(
            allocator, cl2_ptr.space(.media)
        )
    );

    const guess_tr_presentation_bounds = (
        tr_pres_to_cl_media.src_to_dst_topo.input_bounds()
    );

    try std.testing.expectEqualDeep(
        test_data.T_INTERVAL_ARR_0_8_12_20[2],
        guess_tr_presentation_bounds,
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

    const map = try temporal_hierarchy.build_temporal_graph(
        allocator,
        root,
    );
    defer map.deinit(allocator);

    try std.testing.expectEqual(5, map.tree_data.len);
    try std.testing.expectEqual(5, map.nodes.len);
    try std.testing.expectEqual(
        5,
        map.map_node_to_index.count()
    );

    const cache = (
        try SingleSourceTopologyCache.init(
            allocator,
            map,
        )
    );
    defer cache.deinit(allocator);

    const root_presentation_to_clip_media = try build_projection_operator(
        allocator,
        map,
        .{ 
            .source = root.space(.presentation),
            .destination = clip.space(.media),
        },
        cache,
    );

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
        ref.* = cl.*.reference();
    }

    var tr: schema.Track = .{
        .children = &refs,
    };
    const track_ptr = tr.reference();

    var tr_pres_projection_builder = (
        try ProjectionTopology.init_from(
            allocator,
            track_ptr.space(.presentation),
        )
    );
    defer tr_pres_projection_builder.deinit(allocator);

    try std.testing.expectEqual(
        3,
        tr_pres_projection_builder.mappings.len,
    );

    // 1
    for (
        tr_pres_projection_builder.intervals.items(.mapping_index),
        tr_pres_projection_builder.intervals.items(.input_bounds),
        &[_]opentime.ContinuousInterval{ 
            .{ .start = test_data.T_O_0, .end = test_data.T_O_2 },
            .{ .start = test_data.T_O_2, .end = test_data.T_O_4 },
            .{ .start = test_data.T_O_4, .end = test_data.T_O_6 } 
        }
    )
        |mapping_index, measured_interval, expected_interval|
    {
        const b = (
            tr_pres_projection_builder.mappings.items(.mapping)[mapping_index[0]]
        );
        try std.testing.expectEqualDeep(
            expected_interval,
            measured_interval,
        );
        try std.testing.expectEqualDeep(
            expected_interval,
            b.input_bounds(),
        );
    }

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

        const tr_presentation_to_child_media = (
            try tr_pres_projection_builder.projection_operator_to(
                allocator,
                child.space(.media),
            )
        );

        errdefer {
            std.log.err(
                "[{d}] index: {d} track ordinate: {d} expected: {d} error: {any}\n",
                .{t_i, t.index, t.track_ord, t.expected_ord, t.err}
            );
        }
        if (t.err)
        {
            try std.testing.expectError(
                opentime.ProjectionResult.Errors.OutOfBounds,
                tr_presentation_to_child_media.project_instantaneous_cc(
                    opentime.Ordinate.init(t.track_ord)
                ).ordinate()
            );
        }
        else{
            const result = (
                try tr_presentation_to_child_media.project_instantaneous_cc(
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

    const tr_pres_to_cl_media = (
        try tr_pres_projection_builder.projection_operator_to(
            allocator,
            clip.space(.media),
        )
    );

    const expected_range = (
        tr.children[0].clip.bounds_s orelse opentime.ContinuousInterval{}
    );
    const actual_range = (
        tr_pres_to_cl_media.src_to_dst_topo.input_bounds()
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
        tr_pres_to_cl_media.project_instantaneous_cc(
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

    var wp_pres_projection_builder = (
        try ProjectionTopology.init_from(
            allocator,
            wp_ptr.space(.presentation),
        )
    );
    defer wp_pres_projection_builder.deinit(allocator);

    // presentation->media (forward projection)
    {
        const clip_presentation_to_media_proj = (
            try wp_pres_projection_builder.projection_operator_to(
                allocator,
                cl_ptr.space(.media),
            )
        );

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

        // invert it back and check it against the in/out curve bounds
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
        const clip_media_to_presentation = (
            try wp_pres_projection_builder.projection_operator_from_leaky(
                allocator,
                cl_ptr.space(.media),
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
    const cl_ptr = cl.reference();

    var tr_children = [_]references.ComposedValueRef{ cl_ptr, };
    var tr: schema.Track = .{ .children = &tr_children };
    const tr_ptr = tr.reference();

    var tr_pres_projection_builder = (
        try ProjectionTopology.init_from(
            allocator,
            tr_ptr.space(.presentation),
        )
    );
    defer tr_pres_projection_builder.deinit(allocator);

    try temporal_hierarchy.validate_connections_in_map(
        tr_pres_projection_builder.temporal_space_graph,
    );

    try tr_pres_projection_builder.temporal_space_graph.write_dot_graph(
        allocator,
        "/var/tmp/sampling_test.dot",
        "sampling_test",
        .{},
    );

    const tr_pres_to_cl_media = (
        try tr_pres_projection_builder.projection_operator_to(
            allocator,
            cl_ptr.space(.media),
        )
    );

    // instantaneous projection tests
    {
        // continuous time projection to the continuous intrinsic space for
        // continuous or interpolated samples
        try opentime.expectOrdinateEqual(
            4.5,
            try tr_pres_to_cl_media.project_instantaneous_cc(
                opentime.Ordinate.init(3.5)
            ).ordinate(),
        );

        // for discrete non-interpolated data sources, allow projection to a
        // discrete index space
        try std.testing.expectEqual(
            // ??? - can't be prescriptive about how data sources are indexed, ie
            // paths to EXR frames or something
            (3 + 1) * 4,
            try tr_pres_to_cl_media.project_instantaneous_cd(
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
                try tr_pres_to_cl_media.project_range_cc(
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

            const r = tr_pres_to_cl_media.src_to_dst_topo.input_bounds();
            const b = tr_pres_to_cl_media.src_to_dst_topo.output_bounds();

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
                try tr_pres_to_cl_media.project_range_cd(
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
    const tl_ptr = tl.reference();
    const tr_ptr = tl.tracks.children[0];

    var tr_pres_projection_builder = (
        try ProjectionTopology.init_from(
            allocator, 
            tr_ptr.space(.presentation)
        )
    );
    defer tr_pres_projection_builder.deinit(allocator);

    try tr_pres_projection_builder.temporal_space_graph.write_dot_graph(
        allocator,
        "/var/tmp/sampling_test.dot",
        "sampling_test",
        .{},
    );

    const tr_pres_to_cl_media = (
        try tr_pres_projection_builder.projection_operator_to(
            allocator,
            cl_ptr.space(.media),
        )
    );

    // instantaneous projection tests
    {
        // continuous time projection to the continuous intrinsic space for
        // continuous or interpolated samples
        try opentime.expectOrdinateEqual(
            // (3.5*2 + 1),
            8,
            try tr_pres_to_cl_media.project_instantaneous_cc(
                opentime.Ordinate.init(3.5)
            ).ordinate(),
        );

        // for discrete non-interpolated data sources, allow projection to a
        // discrete index space
        try std.testing.expectEqual(
            // ??? - can't be prescriptive about how data sources are indexed, ie
            // paths to EXR frames or something
            (3*2 + 1) * 4,
            try tr_pres_to_cl_media.project_instantaneous_cd(
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
                try tr_pres_to_cl_media.project_range_cc(
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
                try tr_pres_to_cl_media.project_range_cd(
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
            var tl_pres_projection_builder = (
                try ProjectionTopology.init_from(
                    allocator, 
                    tl_ptr.space(.presentation),
                )
            );
            defer tl_pres_projection_builder.deinit(allocator);

            try tl_pres_projection_builder.temporal_space_graph.write_dot_graph(
                allocator,
                "/var/tmp/discrete_to_continuous_test.dot",
                "discrete_to_continuous_test",
                .{},
            );

            const timeline_to_media = (
                try tl_pres_projection_builder.projection_operator_to(
                    allocator,
                    cl_ptr.space(.media),
                )
            );

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
                tr_pres_to_cl_media.src_to_dst_topo.output_bounds().start,
                output_range.start
            );

            const start = (
                tr_pres_to_cl_media.src_to_dst_topo.output_bounds().start
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

    const cl_media = cl_ptr.space(.media);

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
        errdefer opentime.dbg_print(
            @src(), 
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
            opentime.dbg_print(
                @src(), 
                "produced transform: {f}\n",
                .{ xform }
            );
        }

        var warp : schema.Warp = .{
            .child = cl_ptr,
            .transform = xform,
        };

        const wp_ptr : references.ComposedValueRef = .{ .warp =  &warp };

        var wp_pres_projection_builder = (
            try ProjectionTopology.init_from(
                allocator, 
                wp_ptr.space(.presentation),
            )
        );
        defer wp_pres_projection_builder.deinit(allocator);

        try temporal_hierarchy.validate_connections_in_map(
            wp_pres_projection_builder.temporal_space_graph,
        );

        // presentation->media (forward projection)
        {
            const warp_pres_to_media_topo = (
                try wp_pres_projection_builder.projection_operator_to(
                    allocator,
                    cl_media,
                )
            );
            const input_bounds = (
                warp_pres_to_media_topo.src_to_dst_topo.input_bounds()
            );
            const output_bounds = (
                warp_pres_to_media_topo.src_to_dst_topo.output_bounds()
            );

            errdefer opentime.dbg_print(
                @src(), 
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
            // @TODO: inverted topologies are owned by the caller, but
            //        non-inverted ones are owned by the cache.  Need to make
            //        this consistent.
            const clip_media_to_presentation = (
                try wp_pres_projection_builder.projection_operator_from_leaky(
                    allocator,
                    cl_media,
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

/// A graph of temporal spaces in `schema` objects combined with a cache of
/// `topology.Topology` so that `ProjectionOperator`s can be efficiently
/// created across the entire temporal graph.
pub fn ReferenceTopology(
    comptime SpaceReferenceType: type,
) type
{
    return struct {
        pub const ReferenceTopologyType = @This();

        /// index of the root node
        const SOURCE_INDEX = 0;

        // @TODO: remove these
        pub const NodeIndex = treecode.binary_tree.NodeIndex;
        pub const SpaceNodeIndex = treecode.binary_tree.NodeIndex;

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

        temporal_space_graph: temporal_hierarchy.TemporalSpaceGraph,
        cache: SingleSourceTopologyCache,

        pub fn init_from(
            parent_allocator: std.mem.Allocator,
            source_reference: SpaceReferenceType,
        ) !ReferenceTopologyType
        {
            var arena = std.heap.ArenaAllocator.init(
                parent_allocator,
            );
            defer arena.deinit();
            const allocator_arena = arena.allocator();

            // Build out the hierarchy of all the coordinate spaces
            ///////////////////////////////
            const temporal_map = (
                try temporal_hierarchy.build_temporal_graph(
                    parent_allocator,
                    source_reference.ref,
                )
            );

            // Initialize a cache for projections
            ///////////////////////////////
            const cache = (
                try SingleSourceTopologyCache.init(
                    parent_allocator,
                    temporal_map,
                )
            );

            var self: ReferenceTopologyType = .{
                .source = source_reference,
                .mappings = .empty,
                .intervals = .empty,
                .temporal_space_graph = temporal_map,
                .cache = cache,
            };

            // Assemble the components
            //////////////////////

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

            // Gather up all the operators and intervals
            /////////////
            const map_nodes = temporal_map.tree_data.slice();

            const start_index = temporal_map.index_for_node(
                source_reference
            ) orelse return error.SourceNotInMap;
            std.debug.assert(start_index == SOURCE_INDEX);

            var proj_args:temporal_hierarchy.PathEndPointIndices = .{
                .source = start_index,
                .destination = start_index,
            };

            const codes = map_nodes.items(.code);
            const source_code = codes[start_index];
            const maybe_child_indices = map_nodes.items(.child_indices);

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

                const proj_op = (
                    try build_projection_operator_indices(
                        parent_allocator,
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
                    // std.debug.print(
                    //     "interval: {d} active_intervals_len: {d}\n",
                    //     .{interval, active_intervals.bit_length },
                    // );

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
            self.temporal_space_graph.deinit(allocator);
            self.cache.deinit(allocator);
        }

        pub fn projection_operator_to(
            self: @This(),
            allocator: std.mem.Allocator,
            destination_space: references.SpaceReference,
        ) !ProjectionOperator
        {
            return try build_projection_operator_assume_sorted(
                allocator,
                self.temporal_space_graph,
                .{
                    .source = SOURCE_INDEX,
                    .destination = (
                        self.temporal_space_graph.map_node_to_index.get(
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
            target: references.SpaceReference,
        ) !ProjectionOperator
        {
            var result = (
                try build_projection_operator_assume_sorted(
                    allocator,
                    self.temporal_space_graph,
                    .{
                        .source = SOURCE_INDEX,
                        .destination = (
                            self.temporal_space_graph.map_node_to_index.get(target)
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
                    references.SpaceReference,
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
        ) !ProjectionOperator
        {
            return try build_projection_operator_indices(
                allocator,
                self.temporal_space_graph,
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
                        self.temporal_space_graph.nodes.get(mapping.destination)
                    );

                    try writer.print(
                        "    -> {f} | {f}\n",
                        .{ destination, output_bounds, }
                    );
                }
            }
        }
    };
}

pub const ProjectionTopology = ReferenceTopology(
    references.SpaceReference
);

test "ReferenceTopology: init_from_reference"
{
    const allocator = std.testing.allocator;

    // build timeline
    /////////////////////////////////////
    var cl = schema.Clip {
        .name = "clip1",
        .bounds_s = test_data.T_INT_1_TO_9,
        .media = .{
            .discrete_info = .{
                .sample_rate_hz = .{ .Int = 24 },
                .start_index = 86400,
            } 
        }
    };
    const cl_ptr = cl.reference();

    var cl2 = schema.Clip {
        .name = "clip2",
        .bounds_s = test_data.T_INT_1_TO_9,
        .media = .{
            .discrete_info = .{
                .sample_rate_hz = .{ .Int = 30 },
                .start_index = 0,
            },
        },
    };
    const cl2_ptr = cl2.reference();

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
        .discrete_info = .{ 
            .presentation = .{
                .sample_rate_hz = .{ .Int = 24 },
                .start_index = 86400,
            }

        }
    };
    const tl_ref = tl.reference();

    // build ProjectionTopology
    //////////////////////////
    var projection_topo = (
        try ProjectionTopology.init_from(
            allocator,
            tl_ref.space(.presentation),
        )
    );
    defer projection_topo.deinit(allocator);


    const intervals = projection_topo.intervals.items(
        .input_bounds
    );

    const interval:opentime.ContinuousInterval = .{
        .start = intervals[0].start,
        .end = intervals[intervals.len - 1].end,
    };


    try std.testing.expectEqual(
        cl.media.discrete_info.?.start_index,
        try tl_ref.continuous_ordinate_to_discrete_index(
            interval.start, 
            .presentation,
        ),
    );
    try std.testing.expectEqual(
        @as(
            usize,
            @intFromFloat(
                @as(
                    opentime.Ordinate.BaseType,
                    @floatFromInt(tl.discrete_info.presentation.?.start_index)
                )
                + (
                    interval.end.v 
                    * @as(
                        opentime.Ordinate.BaseType,
                        @floatFromInt(tl.discrete_info.presentation.?.sample_rate_hz.Int)
                    )
                )
            )
        ),
        try tl_ref.continuous_ordinate_to_discrete_index(
            interval.end, 
            .presentation,
        ),
    );

    // std.debug.print(
    //     "Intervals mapping (showing intervals 0-10):\n",
    //     .{},
    // );
    // for (0..@min(10, projection_topo.intervals.len))
    //     |ind|
    // {
    //     const first_interval_mapping = (
    //         projection_topo.intervals.get(ind)
    //     );
    //     std.debug.print(
    //         "  Presentation Space Range: {f} (index: [{d}, {d}])\n",
    //         .{
    //             first_interval_mapping.input_bounds,
    //             try tl_ref.continuous_ordinate_to_discrete_index(
    //                 first_interval_mapping.input_bounds.start, 
    //                 .presentation,
    //             ),
    //             try tl_ref.continuous_ordinate_to_discrete_index(
    //                 first_interval_mapping.input_bounds.end,
    //                 .presentation
    //             ) - 1,
    //         }
    //     );
    //     for (first_interval_mapping.mapping_index)
    //         |mapping_ind|
    //     {
    //         const mapping = projection_topo.mappings.get(
    //             mapping_ind
    //         );
    //         const output_bounds = (
    //             mapping.mapping.output_bounds()
    //         );
    //         const destination = (
    //             projection_topo.temporal_map.space_nodes.get(
    //                 mapping.destination
    //             )
    //         );
    //
    //         const start_ind = (
    //             try destination.ref.continuous_ordinate_to_discrete_index(
    //                 output_bounds.start, 
    //                 .media,
    //             )
    //         );
    //         const end_ind_inc = (
    //             try destination.ref.continuous_ordinate_to_discrete_index(
    //                 output_bounds.end,
    //                 .media
    //             ) - 1
    //         );
    //
    //         std.debug.print(
    //             "    -> {f} | {f} ([{d}, {d}] / {d} samples)\n",
    //             .{
    //                 destination,
    //                 output_bounds,
    //                 start_ind,
    //                 end_ind_inc,
    //                 end_ind_inc-start_ind,
    //             }
    //         );
    //     }
    // }
    // std.debug.print(
    //     "~~**~~**~~** END:init_from_reference ~~**~~**~~**\n",
    //     .{},
    // );
}

/// A cache that maps an implied single source to a list of destinations, by
/// index relative to some map
pub const SingleSourceTopologyCache = struct { 
    items: []?topology_m.Topology,

    pub fn init(
        allocator: std.mem.Allocator,
        map: temporal_hierarchy.TemporalSpaceGraph,
    ) !SingleSourceTopologyCache
    {
        const cache = try allocator.alloc(
            ?topology_m.Topology,
            map.nodes.len,
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

pub fn build_projection_operator_indices(
    parent_allocator: std.mem.Allocator,
    map: temporal_hierarchy.TemporalSpaceGraph,
    endpoints: temporal_hierarchy.TemporalSpaceGraph.PathEndPointIndices,
    operator_cache: SingleSourceTopologyCache,
) !ProjectionOperator 
{
    // sort endpoints so that the higher node is always the source
    var sorted_endpoints = endpoints;
    const endpoints_were_swapped = try map.sort_endpoint_indices(
        &sorted_endpoints
    );

    // var result = try build_projection_operator_assume_sorted(
    var result = try build_projection_operator_assume_sorted(
        parent_allocator,
        map,
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
                references.SpaceReference,
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
    map: temporal_hierarchy.TemporalSpaceGraph,
    sorted_endpoints: temporal_hierarchy.TemporalSpaceGraph.PathEndPointIndices,
    operator_cache: SingleSourceTopologyCache,
) !ProjectionOperator 
{
    const space_nodes = map.nodes.slice();

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

    const path_nodes = map.tree_data.slice();
    const codes = path_nodes.items(.code);

    // compute the path length
    const path = try temporal_hierarchy.path_from_parents(
        allocator_arena,
        source_index,
        sorted_endpoints.destination,
        codes,
        path_nodes.items(.parent_index),
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

    var path_step:temporal_hierarchy.TemporalSpaceGraph.PathEndPointIndices = .{
        .source = @intCast(source_index),
        .destination = @intCast(source_index),
    };

    // walk from current_code towards destination_code - path[0] is the current
    // node, can be skipped
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

        const current_to_next = try space_nodes.items(.ref)[current].build_transform(
            allocator_arena,
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

/// build a projection operator that projects from the endpoints.source to
/// endpoints.destination spaces
pub fn build_projection_operator(
    parent_allocator: std.mem.Allocator,
    map: temporal_hierarchy.TemporalSpaceGraph,
    endpoints: temporal_hierarchy.TemporalSpaceGraph.PathEndPoints,
    operator_cache: SingleSourceTopologyCache,
) !ProjectionOperator 
{
    return build_projection_operator_indices(
        parent_allocator,
        map,
        .{
            .source = map.index_for_node(endpoints.source).?,
            .destination = map.index_for_node(endpoints.destination).?,
        },
        operator_cache,
    );
}
