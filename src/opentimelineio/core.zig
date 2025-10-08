//! Slim OpenTimelineIO Reimplementation for testing high level API
//! Uses the rest of the wrinkles library to implement high level functions
//! that might eventually get ported to 'real' OTIO.
//!

const std = @import("std");

const build_options = @import("build_options");

const opentime = @import("opentime");
const curve = @import("curve");
const topology_m = @import("topology");

const treecode = @import("treecode");
const sampling = @import("sampling");

const schema = @import("schema.zig");
const temporal_hierarchy = @import("temporal_hierarchy.zig");

/// annotate the graph algorithms
// const GRAPH_CONSTRUCTION_TRACE_MESSAGES = true;
const GRAPH_CONSTRUCTION_TRACE_MESSAGES = (
    build_options.debug_graph_construction_trace_messages
);

// TEST STRUCTS
const T_INT_1_TO_9 = opentime.ContinuousInterval{
    .start = opentime.Ordinate.ONE,
    .end = opentime.Ordinate.init(9),
};
const T_INT_1_TO_4 = opentime.ContinuousInterval{
    .start = opentime.Ordinate.ONE,
    .end = opentime.Ordinate.init(4),
};
const T_INT_0_TO_2 = opentime.ContinuousInterval{
    .start = opentime.Ordinate.ZERO,
    .end = opentime.Ordinate.init(2),
};
const T_O_0 = opentime.Ordinate.ZERO;
const T_O_2 = opentime.Ordinate.init(2);
const T_O_4 = opentime.Ordinate.init(4);
const T_O_6 = opentime.Ordinate.init(6);
const T_ORD_ARR_0_8_16_21 = [_]opentime.Ordinate{
            opentime.Ordinate.ZERO,
            opentime.Ordinate.init(8),
            opentime.Ordinate.init(16),
            opentime.Ordinate.init(21),
};
const T_ORD_ARR_0_8_13_21 = [_]opentime.Ordinate{
            opentime.Ordinate.ZERO,
            opentime.Ordinate.init(8),
            opentime.Ordinate.init(13),
            opentime.Ordinate.init(21),
};

/// a pointer to something in the composition hierarchy
pub const ComposedValueRef = union(enum) {
    clip: *schema.Clip,
    gap: *schema.Gap,
    track: *schema.Track,
    timeline: *schema.Timeline,
    stack: *schema.Stack,
    warp: *schema.Warp,

    pub fn init_type(
        comptime Type: type,
        input: *Type,
    ) ComposedValueRef
    {
        return ComposedValueRef.init(input);
    }

    /// construct a ComposedValueRef from a ComposableValue or value type
    pub fn init(
        input: anytype,
    ) ComposedValueRef
    {
        comptime {
            const ti= @typeInfo(@TypeOf(input));
            if (std.meta.activeTag(ti) != .pointer) 
            {
                @compileError(
                    "ComposedValueRef can only be constructed from "
                    ++ "pointers to previously allocated OTIO objects, not "
                    ++ @typeName(@TypeOf(input))
                );
            }
        }

        return switch (@TypeOf(input.*)) 
        {
            schema.Clip => .{ .clip = input },
            schema.Gap   => .{ .gap = input },
            schema.Track => .{ .track = input },
            schema.Stack => .{ .stack = input },
            schema.Warp => .{ .warp = input },
            schema.Timeline => .{ .timeline = input },
            inline else => @compileError(
                "ComposedValueRef cannot reference to type: "
                ++ @typeName(@TypeOf(input))
            ),
        };
    }

    pub fn recursively_deinit(
        self: *@This(),
        allocator: std.mem.Allocator,
    ) void
    {
        switch (self.*) 
        {
            .track => |tr| {
                tr.recursively_deinit(allocator);
                allocator.destroy(tr);
            },
            .stack => |st| {
                st.recursively_deinit(allocator);
                allocator.destroy(st);
            },
            .clip => |cl| {
                cl.destroy(allocator);
                allocator.destroy(cl);
            },
            inline else => |o| {
                if (o.name)
                    |n|
                {
                    allocator.free(n);
                    o.name = null;
                }
                allocator.destroy(o);
            },
        }
    }

    /// return the name field of the referenced object
    pub fn name(
        self: @This(),
    ) ?[]const u8
    {
        return switch (self) {
            inline else => |t| t.name
        };
    }

    pub fn topology(
        self: @This(),
        allocator: std.mem.Allocator,
    ) error{OutOfMemory,NotImplementedFetchTopology}!topology_m.Topology 
    {
        return switch (self) {
            .warp => |wp_ptr| wp_ptr.transform,
            inline else => |it_ptr| try it_ptr.topology(allocator),
        };
    }

    pub fn bounds_of(
        self: @This(),
        allocator: std.mem.Allocator,
        target_space: SpaceLabel,
    ) !opentime.ContinuousInterval 
    {
        const presentation_to_intrinsic_topo = (
            try self.topology(allocator)
        );
        defer presentation_to_intrinsic_topo.deinit(allocator);

        return switch (target_space) {
            .media, .intrinsic => presentation_to_intrinsic_topo.output_bounds(),
            .presentation => presentation_to_intrinsic_topo.input_bounds(),
            else => error.UnsupportedSpaceError,
        };
    }

    /// return list of SpaceReference for this object
    pub fn spaces(
        self: @This(),
        allocator: std.mem.Allocator,
    ) ![]const SpaceReference 
    {
        var result: std.ArrayList(SpaceReference) = .{};

        switch (self) {
            .clip, => {
                try result.append(
                    allocator,
                    .{
                        .ref = self,
                        .label = SpaceLabel.presentation,
                    },
                );
                try result.append(
                    allocator,
                    .{
                        .ref = self,
                        .label = SpaceLabel.media,
                    },
                );
            },
            .track, .timeline, .stack => {
                try result.append(
                    allocator,
                    .{
                        .ref = self,
                        .label = SpaceLabel.presentation,
                    },
                );
                try result.append(
                    allocator,
                    .{
                        .ref = self,
                        .label = SpaceLabel.intrinsic,
                    },
                );
            },
            .gap, .warp => {
                try result.append(
                    allocator,
                    .{
                        .ref = self,
                        .label = SpaceLabel.presentation,
                    },
                );
            },
            // else => { return error.NotImplemented; }
        }

        return result.toOwnedSlice(allocator);

    }

    /// build a space reference to the specified space on this CV
    pub fn space(
        self: @This(),
        label: SpaceLabel
    ) !SpaceReference 
    {
        return .{ .ref = self, .label = label };
    }

    /// build a topology that projections a value from_space to_space
    pub fn build_transform(
        self: @This(),
        allocator: std.mem.Allocator,
        from_space: SpaceLabel,
        to_space: SpaceReference,
        step: treecode.l_or_r,
    ) !topology_m.Topology 
    {
        if (GRAPH_CONSTRUCTION_TRACE_MESSAGES) {
            opentime.dbg_print(@src(), 
                "    transform from space: {s}.{s} to space: {s}.{s} ",
                .{
                    @tagName(self),
                    @tagName(from_space),
                    @tagName(to_space.ref),
                    @tagName(to_space.label),
                }
            );

            if (to_space.child_index)
                |ind|
            {
                opentime.dbg_print(@src(), 
                    " index: {d}",
                    .{ind}
                );

            }
            opentime.dbg_print(@src(),  "\n", .{});
        }

        return switch (self) {
            .track => |*tr| {
                switch (from_space) {
                    SpaceLabel.presentation => (
                        return try topology_m.Topology.init_identity_infinite(
                            allocator
                        )
                    ),
                    SpaceLabel.intrinsic => (
                        return try topology_m.Topology.init_identity_infinite(
                            allocator
                        )
                    ),
                    SpaceLabel.child => {
                        if (GRAPH_CONSTRUCTION_TRACE_MESSAGES) {
                            opentime.dbg_print(@src(), "     CHILD STEP: {b}\n", .{ step});
                        }

                        // no further transformation INTO the child
                        if (step == .left) {
                            return (
                                try topology_m.Topology.init_identity_infinite(
                                    allocator,
                                )
                            );
                        } 
                        else 
                        {
                            // transform to the next child
                            return try tr.*.transform_to_child(
                                allocator,
                                to_space,
                            );
                        }

                    },
                    // track supports no other spaces
                    else => return error.UnsupportedSpaceError,
                }
            },
            .clip => |*cl| {
                // schema.Clip spaces and transformations
                //
                // key: 
                //   + space
                //   * transformation
                //
                // +--- presentation
                // |
                // *--- (implicit) presentation -> media (set origin, bounds)
                // |
                // +--- MEDIA
                //
                // initially only exposing the MEDIA and presentation spaces
                //

                return switch (from_space) {
                    .presentation => {
                        // goes to media
                        const pres_to_intrinsic_topo = (
                            try topology_m.Topology.init_identity_infinite(
                                allocator
                            )
                        );
                        defer pres_to_intrinsic_topo.deinit(allocator);

                        const media_bounds = (
                            try cl.*.bounds_of(
                                allocator,
                                .media
                            )
                        );
                        const intrinsic_to_media_xform = (
                            opentime.AffineTransform1D{
                                .offset = media_bounds.start,
                                .scale = opentime.Ordinate.ONE,
                            }
                        );
                        const intrinsic_bounds = opentime.ContinuousInterval{
                            .start = opentime.Ordinate.ZERO,
                            .end = media_bounds.duration()
                        };
                        const intrinsic_to_media = (
                            try topology_m.Topology.init_affine(
                                allocator,
                                .{
                                    .input_to_output_xform = intrinsic_to_media_xform,
                                    .input_bounds_val = intrinsic_bounds,
                                }
                            )
                        );
                        defer intrinsic_to_media.deinit(allocator);

                        const pres_to_media = try topology_m.join(
                            allocator,
                            .{ 
                                .a2b = pres_to_intrinsic_topo,
                                .b2c = intrinsic_to_media,
                            },
                        );

                        return pres_to_media;
                    },
                    else => try topology_m.Topology.init_identity(
                        allocator,
                        try cl.*.bounds_of(
                            allocator,
                            .media,
                        )
                    ),
                };
            },
            .warp => |wp_ptr| switch(from_space) {
                .presentation => wp_ptr.transform.clone(allocator),
                else => try topology_m.Topology.init_identity_infinite(
                    allocator
                ),
            },
            // wrapped as identity
            .gap, .timeline, .stack => (
                try topology_m.Topology.init_identity_infinite(
                    allocator
                )
            ),
            // else => |case| { 
            //     std.log.err("Not Implemented: {any}\n", .{ case });
            //
            //     // return error.NotImplemented;
            //     return topology_m.Topology.init_identity_infinite();
            // },
        };
    }

    pub fn discrete_index_to_continuous_range(
        self: @This(),
        ind_discrete: sampling.sample_index_t,
        in_space: SpaceLabel,
    ) !opentime.ContinuousInterval
    {
        const maybe_di = (
            try self.discrete_info_for_space(in_space)
        );

        if (maybe_di) 
            |di|
        {
            return sampling.project_index_dc(
                di,
                ind_discrete
            );
        }

        return error.NoDiscreteInfoForSpace;
    }

    pub fn continuous_ordinate_to_discrete_index(
        self: @This(),
        ord_continuous: opentime.Ordinate,
        in_space: SpaceLabel,
    ) !sampling.sample_index_t
    {
        const maybe_di = (
            try self.discrete_info_for_space(in_space)
        );

        if (maybe_di) 
            |di|
        {
            return sampling.project_instantaneous_cd(
                di,
                ord_continuous
            );
        }

        return error.NoDiscreteInfoForSpace;
    }
   
    pub fn continuous_to_discrete_topology(
        self: @This(),
        allocator: std.mem.Allocator,
        in_space: SpaceLabel,
    ) !topology_m.Topology
    {
        const maybe_discrete_info = (
            try self.discrete_info_for_space(in_space)
        );
        if (maybe_discrete_info == null)
        {
            return error.SpaceOnObjectHasNoDiscreteSpecification;
        }

        const discrete_info = maybe_discrete_info.?;

        const target_topo = try self.topology(allocator);
        const extents = target_topo.input_bounds();

        return try topology_m.Topology.init_step_mapping(
            allocator,
            extents,
            // start
            @floatFromInt(discrete_info.start_index),
            // held durations
            1.0 / @as(
                opentime.Ordinate,
                @floatFromInt(discrete_info.sample_rate_hz)
            ),
            // increment -- @TODO: support other increments ("on twos", etc)
            1.0,
        );
    }

    pub fn discrete_info_for_space(
        self: @This(),
        in_space: SpaceLabel,
    ) !?sampling.SampleIndexGenerator
    {
        return switch (self) {
            .timeline => |tl| switch (in_space) {
                .presentation => tl.discrete_info.presentation,
                inline else => error.SpaceOnObjectCannotBeDiscrete,
            },
            .clip => |cl| switch (in_space) {
                .media => cl.media.discrete_info,
                inline else => error.SpaceOnObjectCannotBeDiscrete,
            },
            inline else => error.ObjectDoesNotSupportDiscretespaces,
        };
    }

    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) !void 
    {
        try writer.print(
            "{s}.{s}",
            .{
                self.name() orelse "null",
                @tagName(self),
            }
        );
    }

    /// return a caller-owned slice of the children of this composed value ref
    pub fn children_refs(
        self: @This(),
        allocator: std.mem.Allocator,
    ) ![]ComposedValueRef
    {
        var children_ptrs: std.ArrayList(ComposedValueRef) = .{};
        defer children_ptrs.deinit(allocator);

        switch (self) {
            inline .track, .stack => |st_or_tr| (
                try children_ptrs.appendSlice(
                    allocator,
                    st_or_tr.children,
                )
            ),
            .timeline => |tl| try children_ptrs.append(
                allocator,
                ComposedValueRef.init(&tl.tracks)
            ),
            .warp => |wp| {
                try children_ptrs.append(allocator,wp.child);
            },
            inline else => {},
        }

        return try children_ptrs.toOwnedSlice(allocator);
    }
};

test "ComposedValueRef init test"
{
    var clip = schema.Clip{.name = "hi"};

    const cvr_clip = ComposedValueRef.init(&clip);

    try std.testing.expectEqualStrings(
        clip.name.?,
        cvr_clip.clip.name.?,
    );
    try std.testing.expectEqual(&clip, cvr_clip.clip);
}


/// used to identify spaces on objects in the hierarchy
pub const SpaceLabel = enum(i8) {
    presentation = 0,
    intrinsic,
    media,
    child,

    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) !void 
    {
        try writer.print( "{s}", .{ @tagName(self) });
    }
};

/// references a specific space on a specific object
pub const SpaceReference = struct {
    ref: ComposedValueRef,
    label: SpaceLabel,
    child_index: ?usize = null,

    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) !void 
    {
        try writer.print(
            "{f}.{f}",
            .{
                self.ref,
                self.label,
            }
        );

        if (self.child_index)
            |ind|
        {
            try writer.print(
                ".{d}",
                .{
                    ind,
                }
            );
        }
    }
};

/// Combines a source, destination and transformation from the source to the
/// destination.  Allows continuous and discrete transformations.
pub const ProjectionOperator = struct {
    source: SpaceReference,
    destination: SpaceReference,
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
            try index_buffer_destination_discrete.append(
                allocator,
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
    source: SpaceReference,
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

    var space_iter = (
        map.map_space_to_code.keyIterator()
    );
    while (space_iter.next())
        |current|
    {
        // skip all spaces that are not media spaces
        if (current.label != .media) {
            continue;
        }

        proj_args.destination = current.*;

        const child_op = (
            try temporal_hierarchy.build_projection_operator(
                allocator,
                map,
                proj_args,
            )
        );
        defer child_op.deinit(allocator);

        const new_bounds = child_op.src_to_dst_topo.input_bounds();

        const child_op_map = ProjectionOperatorMap {
            .end_points = &. {
                new_bounds.start, new_bounds.end,
            },
            .operators = &.{
                &.{ child_op }, 
            },
            .source = source,
        };

        const last = result;
        defer last.deinit(allocator);

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
    const cl_ptr = ComposedValueRef{ 
        .clip = &cl 
    };
    const child_op_map = (
        try ProjectionOperatorMap.init_operator(
            allocator,
            .{
                .source = try cl_ptr.space(.presentation),
                .destination = try cl_ptr.space(.media),
                .src_to_dst_topo = topology_m.EMPTY,
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
        .bounds_s = T_INT_1_TO_9,
    };
    const cl_ptr = ComposedValueRef.init(&cl);

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
       try m.operators[0][0].project_instantaneous_cc(opentime.Ordinate.init(3)).ordinate(),
    );
}

/// maps a timeline to sets of projection operators, one set per temporal slice
pub const ProjectionOperatorMap = struct {
    /// segment endpoints
    end_points: []const opentime.Ordinate = &.{},
    /// segment projection operators 
    operators : [][]const ProjectionOperator = &.{},

    /// root space for the map
    source : SpaceReference,

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
            .start = opentime.min(over.end_points[0], undr.end_points[0]),
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
            undr_extended.end_points
        );
        const undr_conformed = try undr_extended.split_at_each(
            arena_allocator,
            over_conformed.end_points
        );

        var end_points: std.ArrayList(opentime.Ordinate) = .empty;
        var operators: std.ArrayList([]const ProjectionOperator) = .empty;
        var current_segment: std.ArrayList(ProjectionOperator) = .empty;

        // both end point arrays are the same
        for (over_conformed.end_points[0..over_conformed.end_points.len - 1], 0..)
            |p, ind|
        {
            try end_points.append(parent_allocator,p);
            for (over_conformed.operators[ind])
                |op|
            {
                try current_segment.append(
                    parent_allocator,
                    try op.clone(parent_allocator),
                );
            }
            for (undr_conformed.operators[ind])
                |op|
            {
                try current_segment.append(
                    parent_allocator,
                    try op.clone(parent_allocator),
                );
            }
            try operators.append(
                parent_allocator,
                try current_segment.toOwnedSlice(parent_allocator),
            );

            current_segment.clearAndFree(parent_allocator);
        }

        try end_points.append(
            parent_allocator,
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
                    for (source)
                        |s_mapping|
                    {
                        try cloned_projection_operators.append(
                            allocator,
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
        var tmp_ops: std.ArrayList([]const ProjectionOperator) = .empty;
        defer tmp_ops.deinit(allocator);

        if (self.end_points[0].gt(range.start)) 
        {
            try tmp_pts.append(allocator,range.start);
            try tmp_ops.append(allocator, &.{});
        }

        try tmp_pts.appendSlice(allocator,self.end_points);

        for (self.operators) 
            |self_ops|
        {
            try tmp_ops.append(
                allocator,
                try opentime.slice_with_cloned_contents_allocator(
                    allocator,
                    ProjectionOperator,
                    self_ops,
                )
            );
        }

        if (range.end.gt(self.end_points[self.end_points.len - 1])) 
        {
            try tmp_pts.append(allocator,range.end);
            try tmp_ops.append(allocator, &.{});
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
        var tmp_pts: std.ArrayList(opentime.Ordinate) = .{};
        var tmp_ops: std.ArrayList([]const ProjectionOperator) = .{};

        var ind_self:usize = 0;
        var ind_other:usize = 0;

        var t_next_self = self.end_points[1];
        var t_next_other = pts[1];

        // append origin
        try tmp_pts.append(allocator,self.end_points[0]);

        while (
            ind_self < self.end_points.len - 1
            and ind_other < pts.len - 1 
        )
        {
            try tmp_ops.append(
                allocator,
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
                try tmp_pts.append(allocator,t_next_self);
                if (ind_self < self.end_points.len - 1) {
                    ind_self += 1;
                }
                if (ind_other < pts.len - 1) {
                    ind_other += 1;
                }
            }
            else if (t_next_self.lt(t_next_other))
            {
                try tmp_pts.append(allocator,t_next_self);
                ind_self += 1;
            }
            else 
            {
                try tmp_pts.append(allocator,t_next_other);
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
        .bounds_s = T_INT_1_TO_9,
    };
    const cl_ptr = ComposedValueRef{ .clip = &cl };

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
        .bounds_s = T_INT_1_TO_9,
    };
    const cl_ptr = ComposedValueRef{ .clip = &cl };

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
        .bounds_s = T_INT_1_TO_9,
    };
    const cl_ptr = ComposedValueRef{ .clip = &cl };

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
        .bounds_s = T_INT_1_TO_9,
    };
    const cl_ptr = ComposedValueRef{ .clip = &cl };

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
        .bounds_s = T_INT_1_TO_9,
    };
    const cl_ptr = ComposedValueRef.init(&cl);

    var tr_children = [_]ComposedValueRef{ cl_ptr, };
    var tr: schema.Track = .{ .children = &tr_children };
    const tr_ptr = ComposedValueRef.init(&tr);

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

test "transform: track with two clips"
{
    const allocator = std.testing.allocator;

    var cl1 = schema.Clip {
        .bounds_s = T_INT_1_TO_9,
    };
    var cl2 = schema.Clip {
        .bounds_s = T_INT_1_TO_4,
    };
    const cl2_ref = ComposedValueRef.init(&cl2);

    var tr_children = [_]ComposedValueRef{
        ComposedValueRef.init(&cl1),
        cl2_ref 
    };
    var tr: schema.Track = .{
        .children = &tr_children,
    };
    const tr_ptr = ComposedValueRef.init(&tr);

    const map = try temporal_hierarchy.build_temporal_map(
        allocator,
        tr_ptr,
    );
    defer map.deinit(allocator);

    const track_presentation_space = try tr_ptr.space(.presentation);

    {
        const child_code = (
            try treecode.Treecode.init_word(allocator, 0b1110)
        );
        defer child_code.deinit(allocator);

        const child_space = map.map_code_to_space.get(child_code).?;

        const xform = try tr.transform_to_child(
            allocator,
            child_space
        );
        defer xform.deinit(allocator);

        const b = xform.input_bounds();

        try opentime.expectOrdinateEqual(
            8,
            b.start,
        );
    }

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
        const po = try temporal_hierarchy.build_projection_operator(
            allocator,
            map,
            .{
                .source = try cl2_ref.space(.presentation),
                .destination = try cl2_ref.space(.media),
            }
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
        const xform = try temporal_hierarchy.build_projection_operator(
            allocator,
            map,
            .{
                .source = track_presentation_space,
                .destination = try cl2_ref.space(.media),
            }
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
            .bounds_s = T_INT_1_TO_9,
        },
        .{
            .bounds_s = T_INT_1_TO_9,
        },
    };
    const cl_ptr = ComposedValueRef.init(&clips[1]);

    var tr_children = [_]ComposedValueRef{
        ComposedValueRef.init(&clips[0]),
        cl_ptr,  
    };
    var tr: schema.Track = .{ .children = &tr_children };
    const tr_ptr = ComposedValueRef.init(&tr);

    /////

    const map = try temporal_hierarchy.build_temporal_map(
        allocator,
        tr_ptr,
    );
    defer map.deinit(allocator);

    /////

    const source_space = try tr_ptr.space(.presentation);

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
        (&T_ORD_ARR_0_8_16_21)[0..3],
        p_o_map.end_points,
    );
    try std.testing.expectEqual(2, p_o_map.operators.len);

    const known_presentation_to_media = (
        try temporal_hierarchy.build_projection_operator(
            allocator,
            map,
            .{
                .source = try tr_ptr.space(.presentation),
                .destination = try cl_ptr.space(.media),
            },
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
        .bounds_s = T_INT_1_TO_9,
    };
    var gp = schema.Gap{
        .duration_seconds = opentime.Ordinate.init(5),
    };
    var cl2 = cl;
    const cl_ptr = ComposedValueRef.init(&cl2);

    var tr_children = [_]ComposedValueRef{ 
        ComposedValueRef.init(&cl),
        ComposedValueRef.init(&gp),
        cl_ptr,
    };
    var tr: schema.Track = .{ .children = &tr_children, };
    const tr_ptr = ComposedValueRef.init(&tr);

    const map = try temporal_hierarchy.build_temporal_map(
        allocator,
        tr_ptr,
    );
    defer map.deinit(allocator);

    const source_space = try tr_ptr.space(.presentation);

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
        &T_ORD_ARR_0_8_13_21,
        p_o_map.end_points,
    );
    try std.testing.expectEqual(3, p_o_map.operators.len);

    const known_presentation_to_media = (
        try temporal_hierarchy.build_projection_operator(
            allocator,
            map,
            .{
                .source = try tr_ptr.space(.presentation),
                .destination = try cl_ptr.space(.media),
            },
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

test "clip topology construction" 
{
    const allocator = std.testing.allocator;

    var cl = schema.Clip {
        .bounds_s = T_INT_1_TO_9,
    };

    const topo = try cl.topology(allocator);
    defer topo.deinit(allocator);

    try opentime.expectOrdinateEqual(
        T_INT_1_TO_9.start,
        topo.input_bounds().start,
    );

    try opentime.expectOrdinateEqual(
        T_INT_1_TO_9.end,
        topo.input_bounds().end,
    );
}

test "track topology construction" 
{
    const allocator = std.testing.allocator;

    var cl = schema.Clip {
        .bounds_s = T_INT_1_TO_9, 
    };

    var tr_children = [_]ComposedValueRef{
        ComposedValueRef.init(&cl)
    };
    var tr: schema.Track = .{
        .children = &tr_children,
    };

    const topo = try tr.topology(allocator);
    defer topo.deinit(allocator);

    try opentime.expectOrdinateEqual(
        T_INT_1_TO_9.start,
        topo.input_bounds().start,
    );

    try opentime.expectOrdinateEqual(
        T_INT_1_TO_9.end,
        topo.input_bounds().end,
    );
}

test "path_code: graph test" 
{
    const allocator = std.testing.allocator;

    var clips: [11]schema.Clip = undefined;
    var clip_ptrs: [11]ComposedValueRef = undefined;

    for (&clips, &clip_ptrs)
        |*cl, *cl_p|
    {
        cl.* = schema.Clip {
            .bounds_s = T_INT_1_TO_9,
        };

        cl_p.* = ComposedValueRef.init(cl);
    }
    var tr: schema.Track = .{
        .children = &clip_ptrs,
    };
    const tr_ref = ComposedValueRef.init(&tr);

    try std.testing.expectEqual(11, tr.children.len);

    const map = try temporal_hierarchy.build_temporal_map(
        allocator,
        tr_ref,
    );
    defer map.deinit(allocator);

    try std.testing.expectEqual(
        tr_ref.space(.presentation),
        map.root(),
    );

    try map.write_dot_graph(
        allocator,
        "/var/tmp/graph_test_output.dot",
        "graph_test",
        .{},
    );

    // should be the same length
    try std.testing.expectEqual(
        map.map_space_to_code.count(),
        map.map_code_to_space.count(),
    );
    try std.testing.expectEqual(
        35,
        map.map_space_to_code.count()
    );

    try map.write_dot_graph(
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
            try tr.children[t.ind].space(SpaceLabel.presentation)
        );
        const result = (
            map.get_code(space) 
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

    const range = T_INT_1_TO_9;

    const cl_template = schema.Clip{
        .bounds_s = range
    };

    var clips: [11]schema.Clip = undefined;
    var refs: [11]ComposedValueRef = undefined;

    for (&clips, &refs)
        |*cl_p, *ref|
    {
        cl_p.* = cl_template;
        ref.* = ComposedValueRef.init(cl_p);
    }
    const cl_ref = refs[0];

    var tr: schema.Track = .{ .children = &refs };
    const tr_ref = ComposedValueRef.init(&tr);

    const map = try temporal_hierarchy.build_temporal_map(
        allocator,
        tr_ref,
    );
    defer map.deinit(allocator);

    try std.testing.expectEqual(
        11,
        tr_ref.track.children.len
    );

    const track_to_clip = try temporal_hierarchy.build_projection_operator(
        allocator,
        map,
        .{
            .source = try tr_ref.space(SpaceLabel.presentation),
            .destination =  try cl_ref.space(SpaceLabel.media)
        }
    );
    defer track_to_clip.deinit(std.testing.allocator);

    // check the bounds
    try opentime.expectOrdinateEqual(
        0,
        track_to_clip.src_to_dst_topo.input_bounds().start,
    );

    try opentime.expectOrdinateEqual(
        range.end.sub(range.start),
        track_to_clip.src_to_dst_topo.input_bounds().end,
    );

    // check the projection
    try opentime.expectOrdinateEqual(
        4,
        try track_to_clip.project_instantaneous_cc(
            opentime.Ordinate.init(3)
        ).ordinate(),
    );
}


test "TemporalMap: schema.Track with clip with identity transform" 
{
    const allocator = std.testing.allocator;

    var cl = schema.Clip{
        .bounds_s = T_INT_0_TO_2,
    };
    const cl_ref = ComposedValueRef.init(&cl);

    var tr_children = [_]ComposedValueRef{ cl_ref, };
    var tr: schema.Track = .{ .children = &tr_children };

    const root = ComposedValueRef.init(&tr);

    const map = try temporal_hierarchy.build_temporal_map(
        allocator,
        root,
    );
    defer map.deinit(allocator);

    try std.testing.expectEqual(5, map.map_code_to_space.count());
    try std.testing.expectEqual(5, map.map_space_to_code.count());

    try std.testing.expectEqual(root, map.root().ref);

    const maybe_root_code = map.get_code(map.root());
    try std.testing.expect(maybe_root_code != null);
    const root_code = maybe_root_code.?;

    // root object code
    {
        var tc = try treecode.Treecode.init(allocator);
        defer tc.deinit(allocator);
        try std.testing.expect(tc.eql(root_code));
        try std.testing.expectEqual(0, tc.code_length());
    }

    const maybe_clip_code = map.map_space_to_code.get(
        try cl_ref.space(SpaceLabel.media)
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
        errdefer opentime.dbg_print(@src(), 
            "\ntc: {f}, clip_code: {f}\n",
            .{
                tc,
                clip_code,
            },
            );
        try std.testing.expectEqual(4, tc.code_length());
        try std.testing.expect(tc.eql(clip_code));
    }

    try std.testing.expect(
        treecode.path_exists(clip_code, root_code)
    );

    const root_presentation_to_clip_media = (
        try temporal_hierarchy.build_projection_operator(
            allocator,
            map,
            .{
                .source = try root.space(SpaceLabel.presentation),
                .destination = try cl_ref.space(SpaceLabel.media)
            }
        )
    );
    defer root_presentation_to_clip_media.deinit(allocator);

    try std.testing.expectError(
        topology_m.mapping.Mapping.ProjectionError.OutOfBounds,
        root_presentation_to_clip_media.project_instantaneous_cc(
            opentime.Ordinate.init(3)
        ).ordinate()
    );

    try opentime.expectOrdinateEqual(
        1,
        try root_presentation_to_clip_media.project_instantaneous_cc(
            opentime.Ordinate.init(1)
        ).ordinate(),
    );
}

test "Projection: schema.Track with single clip with identity transform and bounds" 
{
    const allocator = std.testing.allocator;

    var cl = schema.Clip{
        .bounds_s = T_INT_0_TO_2,
    };
    const clip = ComposedValueRef.init(&cl);

    var tr_children = [_]ComposedValueRef{ clip, };
    var tr: schema.Track = .{ .children = &tr_children };
    const root = ComposedValueRef{ .track = &tr };

    const map = try temporal_hierarchy.build_temporal_map(
        allocator,
        root,
    );
    defer map.deinit(allocator);

    try std.testing.expectEqual(
        5,
        map.map_code_to_space.count()
    );
    try std.testing.expectEqual(
        5,
        map.map_space_to_code.count()
    );

    const root_presentation_to_clip_media = try temporal_hierarchy.build_projection_operator(
        allocator,
        map,
        .{ 
            .source = try root.space(SpaceLabel.presentation),
            .destination = try clip.space(SpaceLabel.media),
        }
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
    var refs: [3]ComposedValueRef = undefined;

    for (&clips, &refs)
        |*cl, *ref|
    {
        cl.* = schema.Clip {
            .bounds_s = T_INT_0_TO_2 
        };
        ref.* = ComposedValueRef.init(cl);
    }
    const cl2_ref = refs[2];

    var tr: schema.Track = .{
        .children = &refs,
    };
    const track_ptr = ComposedValueRef.init(&tr);

    // ----

    const map = try temporal_hierarchy.build_temporal_map(
        allocator,
        track_ptr,
    );
    defer map.deinit(allocator);

    // ---

    // check that the child transform is correctly built
    {
        const po = try temporal_hierarchy.build_projection_operator(
            allocator,
            map,
            .{
                .source = try track_ptr.space(.presentation),
                .destination = (
                    try cl2_ref.space(.media)
                ),
            }
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
        try track_ptr.space(.presentation),
    );
    defer po_map.deinit(allocator);

    try std.testing.expectEqual(
        3,
        po_map.operators.len,
    );

    // 1
    for (po_map.operators,
        &[_][2]opentime.Ordinate{ 
            .{ T_O_0, T_O_2 },
            .{ T_O_2, T_O_4 },
            .{ T_O_4, T_O_6 } 
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
        &.{T_O_0, T_O_2, T_O_4, T_O_6},
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

        const tr_presentation_to_clip_media = try temporal_hierarchy.build_projection_operator(
        allocator,
        map,
            .{
                .source = try track_ptr.space(SpaceLabel.presentation),
                .destination = try child.space(SpaceLabel.media),
            }
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

    const root_presentation_to_clip_media = try temporal_hierarchy.build_projection_operator(
        allocator,
        map,
        .{ 
            .source = try track_ptr.space(SpaceLabel.presentation),
            .destination = try clip.space(SpaceLabel.media),
        }
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
    const cl_ptr:ComposedValueRef = .{ .clip = &cl };

    var wp: schema.Warp = .{
        .child = cl_ptr,
        .transform = curve_topo,
    };

    const wp_ptr : ComposedValueRef = .{ .warp = &wp };

    const map = try temporal_hierarchy.build_temporal_map(
        allocator,
        wp_ptr,
    );
    defer map.deinit(allocator);

    // presentation->media (forward projection)
    {
        const clip_presentation_to_media_proj = (
            try temporal_hierarchy.build_projection_operator(
                allocator,
                map,
                .{
                    .source =  try wp_ptr.space(SpaceLabel.presentation),
                    .destination = try cl_ptr.space(SpaceLabel.media),
                }
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
        const clip_media_to_presentation = (
            try temporal_hierarchy.build_projection_operator(
                allocator,
                map,
                .{
                    .source =  try cl_ptr.space(SpaceLabel.media),
                    .destination = try wp_ptr.space(SpaceLabel.presentation),
                }
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
    const it = ComposedValueRef{ .clip = &cl };
    const spaces = try it.spaces(std.testing.allocator);
    defer std.testing.allocator.free(spaces);

    try std.testing.expectEqual(
       SpaceLabel.presentation,
       spaces[0].label, 
    );
    try std.testing.expectEqual(
       SpaceLabel.media,
       spaces[1].label, 
    );
    try std.testing.expectEqual(
       "presentation",
       @tagName(SpaceLabel.presentation),
    );
    try std.testing.expectEqual(
       "media",
       @tagName(SpaceLabel.media),
    );
}

test "otio projection: track with single clip"
{
    const allocator = std.testing.allocator;

    // media is 9 seconds long and runs at 4 hz.
    const media_source_range = T_INT_1_TO_9;
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
    const cl_ptr = ComposedValueRef.init(&cl);

    var tr_children = [_]ComposedValueRef{ cl_ptr, };
    var tr: schema.Track = .{ .children = &tr_children };
    const tr_ptr = ComposedValueRef.init(&tr);

    const map = try temporal_hierarchy.build_temporal_map(
        allocator,
        tr_ptr
    );
    defer map.deinit(allocator);

    try map.write_dot_graph(
        allocator,
        "/var/tmp/sampling_test.dot",
        "sampling_test",
        .{},
    );

    const track_to_media = (
        try temporal_hierarchy.build_projection_operator(
            allocator,
            map,
            .{
                .source = try tr_ptr.space(SpaceLabel.presentation),
                // does the discrete / continuous need to be disambiguated?
                .destination = try cl_ptr.space(SpaceLabel.media),
            },
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
    const media_source_range = T_INT_1_TO_9;
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
    const cl_ptr = ComposedValueRef.init(&cl);

    var wp : schema.Warp = .{
        .child = cl_ptr,
        .transform = try topology_m.Topology.init_affine(
            allocator,
            .{
                .input_to_output_xform = .{
                    .scale = opentime.Ordinate.init(2),
                },
            },
        ),
    };
    defer wp.transform.deinit(allocator);

    var tr_children = [_]ComposedValueRef{
        ComposedValueRef.init(&wp),
    };
    var tr: schema.Track = .{
        .children = &tr_children,
    };

    var tl_children = [_]ComposedValueRef{
        ComposedValueRef.init(&tr),
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
    const tl_ptr = ComposedValueRef.init(&tl);

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

    const track_to_media = (
        try temporal_hierarchy.build_projection_operator(
            allocator,
            map_tr,
            .{
                .source = try tr_ptr.space(.presentation),
                // does the discrete / continuous need to be disambiguated?
                .destination = try cl_ptr.space(.media),
            },
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

            const timeline_to_media = (
                try temporal_hierarchy.build_projection_operator(
                    allocator,
                    map_tl,
                    .{
                        .source = try tl_ptr.space(.presentation),
                        // does the discrete / continuous need to be disambiguated?
                        .destination = try cl_ptr.space(.media),
                    },
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

test "Clip: Animated Parameter example"
{
    const root_allocator = std.testing.allocator;

    var arena = std.heap.ArenaAllocator.init(root_allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    const media_source_range = T_INT_1_TO_9;
    const media_discrete_info = (
        sampling.SampleIndexGenerator{
            .sample_rate_hz = .{ .Int = 4 },
            .start_index = 0,
        }
    );

    var cl = try schema.Clip.init(
        allocator,
        .{ 
            .media = .{
                .bounds_s = media_source_range,
                .discrete_info = media_discrete_info 
            },
        }
    );
    defer cl.destroy(allocator);

    const focus_distance = (
        schema.Clip.ParameterVarying{
            .domain = .time,
            .mapping = try topology_m.Topology.init_from_linear(
                allocator,
                try curve.Linear.init(
                    allocator,
                    &.{ 
                        curve.ControlPoint.init(.{ .in = 0, .out = 1 }),
                        curve.ControlPoint.init(.{ .in = 1, .out = 1.25 }),
                        curve.ControlPoint.init(.{ .in = 5, .out = 8}),
                        curve.ControlPoint.init(.{ .in = 8, .out = 10}),
                    },
                )
            ),
        }
    ).parameter();

    var lens_data = schema.Clip.ParameterMap.init(allocator);
    try lens_data.put("focus_distance", focus_distance);

    const param = schema.Clip.to_param(&lens_data);
    try cl.parameters.?.put( "lens",param );
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
        .name = "Spaghetti.wav",
        .media = .{
            .bounds_s = .{},
            .discrete_info = .{
                .sample_rate_hz = .{ .Int = 24 },
                .start_index = 0,
            },
            .ref = .{ 
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
    const cl_ptr = ComposedValueRef.init(&cl1);

    // new for this test - add in an warp on the clip, which holds the frame
    var wp = schema.Warp {
        .child = cl_ptr,
        .interpolating = true,
        .transform = try topology_m.Topology.init_identity(
            allocator,
            T_INT_1_TO_9,
        ),
    };
    defer wp.transform.deinit(allocator);

    var tr_children = [_]ComposedValueRef{
        ComposedValueRef.init(&wp),
    };
    var tr: schema.Track = .{
        .name = "Example Parent schema.Track",
        .children = &tr_children,
    };

    var tl_children = [_]ComposedValueRef{
        ComposedValueRef.init(&tr),
    };
    var tl: schema.Timeline = .{
        .name = "test debug_print_time_hierarchy",
        .discrete_info = .{ 
            .presentation = .{
                // matches the media rate
                .sample_rate_hz = .{ .Int = 24 },
                .start_index = 0,
            },
        },
        .tracks = .{ .children = &tl_children },
    };
    const tl_ptr = ComposedValueRef{
        .timeline = &tl 
    };

    //////

    const tp = try temporal_hierarchy.build_temporal_map(
        allocator,
        tl_ptr
    );
    defer tp.deinit(allocator);

    //////

    // count the scopes
    var i: usize = 0;
    var values = tp.map_code_to_space.valueIterator();
    while (values.next())
        |_|
    {
        i += 1;
    }

    try std.testing.expectEqual(13, i);
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
    const cl_ptr = ComposedValueRef.init(&cl);

    const cl_media = try cl_ptr.space(SpaceLabel.media);

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

        const wp_ptr : ComposedValueRef = .{ .warp =  &warp };
        const wp_pres = try wp_ptr.space(SpaceLabel.presentation);

        const map = try temporal_hierarchy.build_temporal_map(
            allocator,
            wp_ptr,
        );
        defer map.deinit(allocator);

        // presentation->media (forward projection)
        {
            const warp_pres_to_media_topo = (
                try temporal_hierarchy.build_projection_operator(
                    allocator,
                    map,
                    .{
                        .source =  wp_pres,
                        .destination = cl_media,
                    }
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
            const clip_media_to_presentation = (
                try temporal_hierarchy.build_projection_operator(
                    allocator,
                    map,
                    .{
                        .source =  cl_media,
                        .destination = wp_pres,
                    }
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
    const cl_ptr = ComposedValueRef.init(&cl);

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
    const cl_ptr = ComposedValueRef{ 
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

