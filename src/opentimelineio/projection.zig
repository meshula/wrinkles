//! Structures and functions around projections through the temporal tree.

const std = @import("std");

const build_options = @import("build_options");

const opentime = @import("opentime");
const sampling = @import("sampling");
const topology_m = @import("topology");
const treecode = @import("treecode");
const curve = @import("curve");

const schema = @import("schema.zig");
const references = @import("references.zig");
const temporal_tree = @import("temporal_tree.zig");
const test_data = @import("test_structures.zig");
const projection_builder = @import("projection_builder.zig");
const domain_mod = @import("domain.zig");

const GRAPH_CONSTRUCTION_TRACE_MESSAGES = (
    build_options.debug_graph_construction_trace_messages
);

/// Combines a source, destination and transformation from the source to the
/// destination.  Allows continuous and discrete transformations.
pub const ProjectionOperator = struct {
    source: references.SpaceReference,
    destination: references.SpaceReference,
    src_to_dst_topo: topology_m.Topology,

    //
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
    //

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
        domain: domain_mod.Domain,
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
            domain,
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
        domain: domain_mod.Domain,
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
                domain,
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
                    domain,
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
        domain: domain_mod.Domain,
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
            domain,
        );
    }

    /// project a discrete index into the continuous space
    pub fn project_index_dc(
        self: @This(),
        allocator: std.mem.Allocator,
        index_in_source: sampling.sample_index_t,
        domain: domain_mod.Domain,
    ) !topology_m.Topology
    {
        const c_range_in_source = (
            try self.source.ref.discrete_index_to_continuous_range(
                index_in_source,
                self.source.label,
                domain,
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
        domain: domain_mod.Domain,
    ) ![]sampling.sample_index_t
    {
        const c_range_in_source = (
            try self.source.ref.discrete_index_to_continuous_range(
                index_in_source,
                self.source.label,
                domain,
            )
        );

        return try self.project_range_cd(
            allocator,
            c_range_in_source,
            domain,
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
        .media = .null_picture,
        .maybe_bounds_s = test_data.T_INT_1_TO_9,
    };
    const cl_ptr = references.ComposedValueRef.init(&cl);

    var cl_pres_proj_topo = try TemporalProjectionBuilder.init_from(
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

test "ProjectionBuilder: clip"
{
    const allocator = std.testing.allocator;

    var cl = schema.Clip {
        .media = .null_picture,
        .maybe_bounds_s = test_data.T_INT_1_TO_9,
    };
    const cl_ptr = references.ComposedValueRef{ .clip = &cl };

    var cl_pres_projection_builder = (
        try TemporalProjectionBuilder.init_from(
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
            cl_pres_projection_builder.tree,
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

test "ProjectionBuilder: track with single clip"
{
    const allocator = std.testing.allocator;

    var cl = schema.Clip {
        .media = .null_picture,
        .maybe_bounds_s = test_data.T_INT_1_TO_9,
    };
    const cl_ptr = references.ComposedValueRef.init(&cl);

    var tr_children = [_]references.ComposedValueRef{ cl_ptr, };
    var tr: schema.Track = .{ .children = &tr_children };
    const tr_ptr = references.ComposedValueRef.init(&tr);

    const source_space = tr_ptr.space(.presentation);

    var test_maps = [_]TemporalProjectionBuilder{
        try TemporalProjectionBuilder.init_from(
            allocator,
            cl_ptr.space(.presentation),
        ),
        try TemporalProjectionBuilder.init_from(
            allocator,
            source_space,
        ),
    };

    for (&test_maps)
        |*pb|
    {
        defer pb.deinit(allocator);

        try std.testing.expectEqual(
            1,
            pb.mappings.len,
        );
        try std.testing.expectEqual(
            1,
            pb.intervals.len,
        );

        const known_presentation_to_media = try build_projection_operator(
            allocator,
            pb.tree,
            .{
                .source = pb.source,
                .destination = cl_ptr.space(.media),
            },
            pb.cache,
        );
        const known_input_bounds = (
            known_presentation_to_media.src_to_dst_topo.input_bounds()
        );

        const guess_presentation_to_media = (
            pb.mappings.items(.mapping)[0]
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
            pb.intervals.items(.input_bounds)[0].start,
            guess_input_bounds.start,
        );
        try opentime.expectOrdinateEqual(
            pb.intervals.items(.input_bounds)[0].end,
            guess_input_bounds.end,
        );

        // known input bounds matches end point
        try opentime.expectOrdinateEqual(
            known_input_bounds.start,
            pb.intervals.items(.input_bounds)[0].start,
        );
        try opentime.expectOrdinateEqual(
            known_input_bounds.end,
            pb.intervals.items(.input_bounds)[0].end,
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

    var cl: schema.Clip = .null_picture;
    const cl_ptr = cl.reference();

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
        .media = .null_picture,
        .maybe_bounds_s = test_data.T_INT_1_TO_9,
    };
    var cl2 = schema.Clip {
        .media = .null_picture,
        .maybe_bounds_s = test_data.T_INT_1_TO_4,
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

    const map = try temporal_tree.build_temporal_tree(
        allocator,
        tr_ptr.space(.presentation),
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
            try TemporalProjectionBuilder.SingleSourceTopologyCache.init(
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
            try TemporalProjectionBuilder.SingleSourceTopologyCache.init(
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
            .media = .null_picture,
            .maybe_bounds_s = test_data.T_INT_1_TO_9,
        },
        .{
            .media = .null_picture,
            .maybe_bounds_s = test_data.T_INTERVAL_ARR_0_8_12_20[1],
        },
        .{
            .media = .null_picture,
            .maybe_bounds_s = test_data.T_INT_1_TO_9,
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
        try TemporalProjectionBuilder.init_from(
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
            cl_pres_projection_builder.tree,
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

test "ProjectionBuilder: track [c1][gap][c2]"
{
    const allocator = std.testing.allocator;

    var cl = schema.Clip {
        .media = .null_picture,
        .maybe_bounds_s = test_data.T_INT_1_TO_9,
    };
    var gp = schema.Gap{
        .duration_seconds = opentime.Ordinate.init(4),
    };
    var cl2 = schema.Clip {
        .media = .null_picture,
        .maybe_bounds_s = test_data.T_INT_1_TO_9,
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
        try TemporalProjectionBuilder.init_from(
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
        .media = .null_picture,
        .maybe_bounds_s = test_data.T_INT_0_TO_2,
    };
    const clip = references.ComposedValueRef.init(&cl);

    var tr_children = [_]references.ComposedValueRef{ clip, };
    var tr: schema.Track = .{ .children = &tr_children };
    const root = references.ComposedValueRef{ .track = &tr };

    const map = try temporal_tree.build_temporal_tree(
        allocator,
        root.space(.presentation),
    );
    defer map.deinit(allocator);

    try std.testing.expectEqual(5, map.tree_data.len);
    try std.testing.expectEqual(5, map.nodes.len);
    try std.testing.expectEqual(
        5,
        map.map_node_to_index.count()
    );

    const cache = (
        try TemporalProjectionBuilder.SingleSourceTopologyCache.init(
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
        cl.maybe_bounds_s orelse opentime.ContinuousInterval{}
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
            .media = .null_picture,
            .maybe_bounds_s = test_data.T_INT_0_TO_2 
        };
        ref.* = cl.*.reference();
    }

    var tr: schema.Track = .{
        .children = &refs,
    };
    const track_ptr = tr.reference();

    var tr_pres_projection_builder = (
        try TemporalProjectionBuilder.init_from(
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
        tr.children[0].clip.maybe_bounds_s orelse opentime.ContinuousInterval{}
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
        .media = .null_picture,
        .maybe_bounds_s = media_temporal_bounds,
    };
    const cl_ptr:references.ComposedValueRef = .{ .clip = &cl };

    var wp: schema.Warp = .{
        .child = cl_ptr,
        .transform = curve_topo,
    };

    const wp_ptr : references.ComposedValueRef = .{ .warp = &wp };

    var wp_pres_projection_builder = (
        try TemporalProjectionBuilder.init_from(
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
            .data_reference = .null,
            .domain = .picture,
            .maybe_bounds_s = media_source_range,
            .maybe_discrete_partition = media_discrete_info,
        },
    };
    const cl_ptr = cl.reference();

    var tr_children = [_]references.ComposedValueRef{ cl_ptr, };
    var tr: schema.Track = .{ .children = &tr_children };
    const tr_ptr = tr.reference();

    var tr_pres_projection_builder = (
        try TemporalProjectionBuilder.init_from(
            allocator,
            tr_ptr.space(.presentation),
        )
    );
    defer tr_pres_projection_builder.deinit(allocator);

    try temporal_tree.validate_connections_in_tree(
        tr_pres_projection_builder.tree,
    );

    try tr_pres_projection_builder.tree.write_dot_graph(
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
                .picture,
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
                    .picture,
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
            .data_reference = .null,
            .domain = .picture,
            .maybe_bounds_s = media_source_range,
            .maybe_discrete_partition = media_discrete_info,
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
        .discrete_space_partitions = .{ 
            .presentation = .{
                .picture = .{
                    .sample_rate_hz = .{ .Int = 24 },
                    .start_index = 12,
                },
                .audio = null,
            },
        },
        .tracks = .{ .children = &tl_children },
    };
    const tl_ptr = tl.reference();
    const tr_ptr = tl.tracks.children[0];

    var tr_pres_projection_builder = (
        try TemporalProjectionBuilder.init_from(
            allocator, 
            tr_ptr.space(.presentation)
        )
    );
    defer tr_pres_projection_builder.deinit(allocator);

    try tr_pres_projection_builder.tree.write_dot_graph(
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
                opentime.Ordinate.init(3),
                .picture,
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
                    .picture,
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
                try TemporalProjectionBuilder.init_from(
                    allocator, 
                    tl_ptr.space(.presentation),
                )
            );
            defer tl_pres_projection_builder.deinit(allocator);

            try tl_pres_projection_builder.tree.write_dot_graph(
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
                    .picture,
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
                 tl.discrete_space_partitions.presentation.picture.?.sample_rate_hz.inv_as_ordinate().mul(2)
                 )
                ),
                output_range.end,
            );

            const result_indices = (
                try timeline_to_media.project_index_dd(
                    allocator,
                    12,
                    .picture,
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
        .media = .null_picture,
        .maybe_bounds_s = media_temporal_bounds,
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
            try TemporalProjectionBuilder.init_from(
                allocator, 
                wp_ptr.space(.presentation),
            )
        );
        defer wp_pres_projection_builder.deinit(allocator);

        try temporal_tree.validate_connections_in_tree(
            wp_pres_projection_builder.tree,
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

pub const TemporalProjectionBuilder = projection_builder.ProjectionBuilder(
    references.SpaceReference,
    ProjectionOperator,
    temporal_tree.build_temporal_tree,
);

test "ReferenceTopology: init_from_reference"
{
    const allocator = std.testing.allocator;

    // build timeline
    /////////////////////////////////////
    var cl = schema.Clip {
        .maybe_name = "clip1",
        .maybe_bounds_s = test_data.T_INT_1_TO_9,
        .media = .{
            .data_reference = .null,
            .domain = .picture,
            .maybe_bounds_s = null,
            .maybe_discrete_partition = .{
                .sample_rate_hz = .{ .Int = 24 },
                .start_index = 86400,
            } 
        }
    };
    const cl_ptr = cl.reference();

    var cl2 = schema.Clip {
        .maybe_name = "clip2",
        .maybe_bounds_s = test_data.T_INT_1_TO_9,
        .media = .{
            .data_reference = .null,
            .domain = .picture,
            .maybe_bounds_s = null,
            .maybe_discrete_partition = .{
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
        .media = .null_picture,
        .maybe_name = "clip3_warped",
        .maybe_bounds_s = test_data.T_INT_1_TO_9,
    };
    cl3.media.maybe_discrete_partition = .{
        .sample_rate_hz = .{ .Int = 24 },
        .start_index = 0,
    };
    const cl3_ptr = cl3.reference();
    var wp1 = schema.Warp {
        .maybe_name = "Warp on Clip3",
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
        .discrete_space_partitions = .{ 
            .presentation = .{
                .picture = .{
                    .sample_rate_hz = .{ .Int = 24 },
                    .start_index = 86400,
                },
                .audio = null,
            }
        }
    };
    const tl_ref = tl.reference();

    // build ProjectionTopology
    //////////////////////////
    var projection_topo = (
        try TemporalProjectionBuilder.init_from(
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
        cl.media.maybe_discrete_partition.?.start_index,
        try tl_ref.continuous_ordinate_to_discrete_index(
            interval.start, 
            .presentation,
            .picture,
        ),
    );
    try std.testing.expectEqual(
        @as(
            usize,
            @intFromFloat(
                @as(
                    opentime.Ordinate.BaseType,
                    @floatFromInt(tl.discrete_space_partitions.presentation.picture.?.start_index)
                )
                + (
                    interval.end.v 
                    * @as(
                        opentime.Ordinate.BaseType,
                        @floatFromInt(tl.discrete_space_partitions.presentation.picture.?.sample_rate_hz.Int)
                    )
                )
            )
        ),
        try tl_ref.continuous_ordinate_to_discrete_index(
            interval.end, 
            .presentation,
            .picture,
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

/// build a projection operator that projects from the endpoints.source to
/// endpoints.destination spaces
pub fn build_projection_operator(
    allocator_parent: std.mem.Allocator,
    tree: TemporalProjectionBuilder.TreeType,
    endpoints: TemporalProjectionBuilder.TreeType.PathEndPoints,
    operator_cache: TemporalProjectionBuilder.SingleSourceTopologyCache,
) !ProjectionOperator 
{
    return TemporalProjectionBuilder.build_projection_operator_indices(
        allocator_parent,
        tree,
        .{
            .source = tree.index_for_node(endpoints.source).?,
            .destination = tree.index_for_node(endpoints.destination).?,
        },
        operator_cache,
    );
}

test "projection builder over warp with negative scale"
{
    const allocator = std.testing.allocator;

    var cl = schema.Clip {
        .media = .null_picture,
        .maybe_bounds_s = test_data.T_INT_1_TO_9,
    };

    const xform = opentime.AffineTransform1D {
        .offset = .ZERO,
        .scale = opentime.Ordinate.init(-2),
    };

    var wp = schema.Warp {
        .child = cl.reference(),
        .transform = try topology_m.Topology.init_affine(
            allocator, 
            .{
                .input_to_output_xform = xform,
                .input_bounds_val = .INF,
            },
        ),
    };
    defer wp.transform.deinit(allocator);
    const wp_ptr = wp.reference();

    var builder = (
        try TemporalProjectionBuilder.init_from(
            allocator,
            wp_ptr.space(.presentation),
        )
    );
    defer builder.deinit(allocator);

    std.debug.print("b: {f}\n", .{builder});

    const wp_pres_to_child = try wp.topology(allocator);
    defer wp_pres_to_child.deinit(allocator);

    try std.testing.expectEqual(
        wp_pres_to_child.input_bounds(),
        builder.input_bounds(),
    );
}
