//! Slim OpenTimelineIO Reimplementation for testing high level API
//! Uses the rest of the wrinkles library to implement high level functions
//! that might eventually get ported to 'real' OTIO.
//!

const std = @import("std");

const build_options = @import("build_options");

const opentime = @import("opentime");
const curve = @import("curve");
const topology_m = @import("topology");
const string = @import("string_stuff");

const treecode = @import("treecode");
const sampling = @import("sampling");

const schema = @import("schema.zig");

/// annotate the graph algorithms
// const GRAPH_CONSTRUCTION_TRACE_MESSAGES = true;
const GRAPH_CONSTRUCTION_TRACE_MESSAGES = (
    build_options.debug_graph_construction_trace_messages
);

/// for VERY LARGE files, turn this off so that dot can process the graphs
const LABEL_HAS_BINARY_TREECODE = true;

/// anything that can be composed in a track or stack
pub const ComposableValue = union(enum) {
    clip: schema.Clip,
    gap: schema.Gap,
    track: schema.Track,
    stack: schema.Stack,
    warp: schema.Warp,

    pub fn init(
        val: anytype,
    ) ComposableValue
    {
        if (@TypeOf(val) == ComposableValue) {
            return val;
        }

        return switch (@TypeOf(val)) {
            schema.Clip => return .{ .clip = val },
            schema.Gap => return .{ .gap = val },
            schema.Track => return .{ .track = val },
            schema.Stack => return .{ .stack = val },
            schema.Warp => return .{ .warp = val },
            inline else => {
                @compileError(
                    "Cannot compose value of type: "
                    ++ @typeName(@TypeOf(val))
                );
            }
        };
    }

    /// build a topology for the ComposableValue
    pub fn topology(
        self: @This(),
        allocator: std.mem.Allocator,
    ) error{
        NotImplementedFetchTopology,
        OutOfMemory,
        OutOfBounds,
        MoreThanOneCurveIsNotImplemented,
        NoSplitForLinearization,
        NotInRangeError,
        NoProjectionResult,
        NoProjectionResultError,
    }!topology_m.Topology 
    {
        return switch (self) {
            .warp => |wp| wp.transform,
            inline else => |it| try it.topology(allocator),
        };
    }

    pub fn recursively_deinit(
        self: @This(),
        allocator: std.mem.Allocator,
    ) void
    {
        switch (self) 
        {
            .track => |tr| {
                tr.recursively_deinit();
            },
            .stack => |st| {
                st.recursively_deinit();
            },
            .clip => |cl| {
                cl.destroy(allocator);
            },
            inline else => |o| {
                if (o.name)
                    |n|
                {
                    allocator.free(n);
                }
            },
        }
    }
};

/// a pointer to something in the composition hierarchy
pub const ComposedValueRef = union(enum) {
    clip_ptr: *const schema.Clip,
    gap_ptr: *const schema.Gap,
    track_ptr: *const schema.Track,
    timeline_ptr: *const schema.Timeline,
    stack_ptr: *const schema.Stack,
    warp_ptr: *const schema.Warp,

    /// construct a ComposedValueRef from a ComposableValue or value type
    pub fn init(
        input: anytype,
    ) ComposedValueRef
    {
        comptime {
            const t= @typeInfo(@TypeOf(input));
            if (std.meta.activeTag(t) != .Pointer) 
            {
                @compileError(
                    "ComposedValueRef can only be constructed from pointers "
                    ++ "or ComposableValues, not: "
                    ++ @typeName(@TypeOf(input))
                );
            }
        }

        if (
            @TypeOf(input) == (*const ComposableValue)
            or @TypeOf(input) == (*ComposableValue)
        ) 
        {
            return switch (input.*) 
            {
                .clip  => |*cp| .{ .clip_ptr = cp  },
                .gap   => |*gp| .{ .gap_ptr= gp    },
                .track => |*tr| .{ .track_ptr = tr },
                .stack => |*st| .{ .stack_ptr = st },
                .warp  => |*wp| .{ .warp_ptr = wp },
            };
        }
        else 
        {
            return switch (@TypeOf(input.*)) 
            {
                schema.Clip => .{ .clip_ptr = input },
                schema.Gap   => .{ .gap_ptr = input },
                schema.Track => .{ .track_ptr = input },
                schema.Stack => .{ .stack_ptr = input },
                schema.Warp => .{ .warp_ptr = input },
                schema.Timeline => .{ .timeline_ptr = input },
                inline else => @compileError(
                    "ComposedValueRef cannot reference to type: "
                    ++ @typeName(@TypeOf(input))
                ),
            };
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
    ) !topology_m.Topology 
    {
        return switch (self) {
            .warp_ptr => |wp_ptr| wp_ptr.transform,
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

    /// pointer equivalence
    pub fn equivalent_to(
        self: @This(),
        other: ComposedValueRef
    ) bool 
    {
        return switch(self) {
            .clip_ptr => |cl| cl == other.clip_ptr,
            .gap_ptr => |gp| gp == other.gap_ptr,
            .track_ptr => |tr| tr == other.track_ptr,
            .stack_ptr => |st| st == other.stack_ptr,
            .timeline_ptr => |tl| tl == other.timeline_ptr,
            .warp_ptr => |wp| wp == other.warp_ptr,
        };
    }

    /// return list of SpaceReference for this object
    pub fn spaces(
        self: @This(),
        allocator: std.mem.Allocator,
    ) ![]const SpaceReference 
    {
        var result = std.ArrayList(SpaceReference).init(allocator);

        switch (self) {
            .clip_ptr, => {
                try result.append( .{ .ref = self, .label = SpaceLabel.presentation});
                try result.append( .{ .ref = self, .label = SpaceLabel.media});
            },
            .track_ptr, .timeline_ptr, .stack_ptr => {
                try result.append( .{ .ref = self, .label = SpaceLabel.presentation});
                try result.append( .{ .ref = self, .label = SpaceLabel.intrinsic});
            },
            .gap_ptr, .warp_ptr => {
                try result.append( .{ .ref = self, .label = SpaceLabel.presentation});
            },
            // else => { return error.NotImplemented; }
        }

        return result.toOwnedSlice();

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
        step: u1,
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
            .track_ptr => |*tr| {
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
                        if (step == 0) {
                            return (
                                try topology_m.Topology.init_identity_infinite(
                                    allocator
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
            .clip_ptr => |*cl| {
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
                                .scale = 1,
                            }
                        );
                        const intrinsic_bounds = .{
                            .start = 0,
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
            .warp_ptr => |wp_ptr| switch(from_space) {
                // @TODO: maybe we should make the child spaces unreachable?
                //        ie - if they're always identity, is there anything
                //        interesting about exposing them in this function?
                .presentation => wp_ptr.transform.clone(allocator),
                else => try topology_m.Topology.init_identity_infinite(
                    allocator
                ),
            },
            // wrapped as identity
            .gap_ptr, .timeline_ptr, .stack_ptr => (
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
            1.0 / @as(opentime.Ordinate, @floatFromInt(discrete_info.sample_rate_hz)),
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
            .timeline_ptr => |tl| switch (in_space) {
                .presentation => tl.discrete_info.presentation,
                inline else => error.SpaceOnObjectCannotBeDiscrete,
            },
            .clip_ptr => |cl| switch (in_space) {
                .media => cl.media.discrete_info,
                inline else => error.SpaceOnObjectCannotBeDiscrete,
            },
            inline else => error.ObjectDoesNotSupportDiscretespaces,
        };
    }

    pub fn format(
        self: @This(),
        // fmt
        comptime _: []const u8,
        // options
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void 
    {
        const str = switch (self) {
            .clip_ptr => "clip",
            .gap_ptr => "gap",
            .track_ptr => "track",
            .stack_ptr => "stack",
            .warp_ptr => "warp",
            .timeline_ptr => "timeline",
        };
        // const n = self.name() orelse "null";
        const n = "null";
        try writer.print(
            "{s}.{s}",
            .{
                n,
                str,
            }
        );
    }
};

test "ComposedValueRef init test"
{
    const cl = schema.Clip{};

    const cl_cv = ComposableValue.init(cl);
    const cl_ref_init_cv = ComposedValueRef.init(&cl_cv);

    const cl_ref_init_ptr = ComposedValueRef.init(&cl);

    try std.testing.expectEqual(
        &(cl_cv.clip),
        cl_ref_init_cv.clip_ptr
    );
    try std.testing.expectEqual(&cl, cl_ref_init_ptr.clip_ptr);
}


/// used to identify spaces on objects in the hierarchy
pub const SpaceLabel = enum(i8) {
    presentation = 0,
    intrinsic,
    media,
    child,

    pub fn format(
        self: @This(),
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void 
    {
        try writer.print(
            "{s}",
            .{
                switch (self) {
                    .presentation => "presentation",
                    .intrinsic => "intrinsic",
                    .media => "media",
                    .child => "child",
                }
            }
        );
    }
};

/// references a specific space on a specific object
pub const SpaceReference = struct {
    ref: ComposedValueRef,
    label: SpaceLabel,
    child_index: ?usize = null,

    pub fn format(
        self: @This(),
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void 
    {
        try writer.print(
            "{s}.{s}",
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

/// endpoints for a projection
const ProjectionOperatorArgs = struct {
    source: SpaceReference,
    destination: SpaceReference,
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
                in_to_src_topo
            )
        );
        defer in_to_dst_topo_c.deinit(allocator);

        const discrete_info = (
            try self.destination.ref.discrete_info_for_space(
                self.destination.label
            )
        ).?;

        var index_buffer_destination_discrete = (
            std.ArrayList(sampling.sample_index_t).init(allocator)
        );
        defer index_buffer_destination_discrete.deinit();

        const in_c_bounds = in_to_dst_topo_c.input_bounds();

        // const bounds_to_walk = dst_c_bounds;
        const bounds_to_walk = in_c_bounds;

        const duration:opentime.Ordinate = (
            1.0 / @as(opentime.Ordinate, @floatFromInt(discrete_info.sample_rate_hz))
        );

        const increasing = bounds_to_walk.end > bounds_to_walk.start;
        const sign:opentime.Ordinate = if (increasing) 1 else -1;

        // walk across the continuous space at the sampling rate
        var t = bounds_to_walk.start;
        while (
            (increasing and t < bounds_to_walk.end)
            or (increasing == false and t > bounds_to_walk.end)
        ) : (t += sign*duration)
        {
            const out_ord = try in_to_dst_topo_c.project_instantaneous_cc(t).ordinate();

            // ...project the continuous coordinate into the discrete space
            try index_buffer_destination_discrete.append(
                try self.destination.ref.continuous_ordinate_to_discrete_index(
                    out_ord,
                    self.destination.label,
                )
            );
        }

        return index_buffer_destination_discrete.toOwnedSlice();
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
                        .scale = 1.0,
                    },
                    .input_bounds_val = .{
                        .start = 0,
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
            in_to_source_topo
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

/// Topological Map of a schema.Timeline.  Can be used to build projection operators
/// to transform between various coordinate spaces within the map.
pub const TopologicalMap = struct {
    map_space_to_code:std.AutoHashMap(
          SpaceReference,
          treecode.Treecode,
    ),
    map_code_to_space:treecode.TreecodeHashMap(SpaceReference),

    pub fn init(
        allocator: std.mem.Allocator,
    ) !TopologicalMap 
    {
        return .{ 
            .map_space_to_code = std.AutoHashMap(
                SpaceReference,
                treecode.Treecode,
            ).init(allocator),
            .map_code_to_space = treecode.TreecodeHashMap(
                SpaceReference,
            ).init(allocator),
        };
    }

    pub fn deinit(
        self: @This()
    ) void 
    {
        // build a mutable alias of self
        var mutable_self = self;

        var keyIter = (
            mutable_self.map_code_to_space.keyIterator()
        );
        while (keyIter.next())
            |code|
        {
            code.deinit();
        }

        var valueIter = (
            mutable_self.map_space_to_code.valueIterator()
        );
        while (valueIter.next())
            |code|
        {
            code.deinit();
        }

        // free the guts
        mutable_self.map_space_to_code.deinit();
        mutable_self.map_code_to_space.deinit();
    }

    pub const ROOT_TREECODE:treecode.TreecodeWord = 0b1;

    /// return the root space of this topological map
    pub fn root(
        self: @This(),
    ) SpaceReference 
    {
        const tree_word = treecode.Treecode{
            .sz = 1,
            .treecode_array = blk: {
                var output = [_]treecode.TreecodeWord{ ROOT_TREECODE };
                break :blk &output;
            },
            .allocator = undefined,
        };

        // should always have a root object
        return self.map_code_to_space.get(tree_word) orelse unreachable;
    }

    /// build a projection operator that projects from the endpoints.source to
    /// endpoints.destination spaces
    pub fn build_projection_operator(
        self: @This(),
        allocator: std.mem.Allocator,
        endpoints_arg: ProjectionOperatorArgs,
    ) !ProjectionOperator 
    {
        const path_info_ = try self.path_info( endpoints_arg);
        const endpoints = path_info_.endpoints;

        var root_to_current = (
            try topology_m.Topology.init_identity_infinite(allocator)
        );

        if (GRAPH_CONSTRUCTION_TRACE_MESSAGES) {
            opentime.dbg_print(@src(), 
                "[START] root_to_current: {s}\n",
                .{ root_to_current }
            );
        }

        var iter = (
            try TreenodeWalkingIterator.init_from_to(
                allocator,
                &self,
                endpoints,
            )
        );
        defer iter.deinit();

        _ = try iter.next();

        var current = iter.maybe_current.?;

        if (GRAPH_CONSTRUCTION_TRACE_MESSAGES) {
            opentime.dbg_print(@src(), 
                "starting walk from: {s} to: {s}\n"
                ++ "starting projection: {s}\n"
                ,
                .{
                    current,
                    endpoints.destination,
                    root_to_current,
                }
            );
        }

        // walk from current_code towards destination_code
        while (try iter.next()) 
        {
            const next = (
                iter.maybe_current orelse return error.TreeCodeNotInMap
            );

            const next_step = try current.code.next_step_towards(next.code);

            if (GRAPH_CONSTRUCTION_TRACE_MESSAGES) { 
                opentime.dbg_print(@src(), 
                    "  next step {b} towards next node: {s}\n"
                    ,
                    .{ next_step, next }
                );
            }

            // in case build_transform errors
            errdefer root_to_current.deinit(allocator);

            var current_to_next = try current.space.ref.build_transform(
                allocator,
                current.space.label,
                next.space,
                next_step
            );
            defer current_to_next.deinit(allocator);

            if (GRAPH_CONSTRUCTION_TRACE_MESSAGES) 
            {
                opentime.dbg_print(@src(), 
                    "    joining!\n"
                    ++ "    a2b/root_to_current: {s}\n"
                    ++ "    b2c/current_to_next: {s}\n"
                    ,
                    .{
                        root_to_current,
                        current_to_next,
                    },
                );
            }

            const root_to_next = try topology_m.join(
                allocator,
                .{
                    .a2b = root_to_current,
                    .b2c = current_to_next,
                },
            );

            if (GRAPH_CONSTRUCTION_TRACE_MESSAGES) 
            {
                opentime.dbg_print(@src(), 
                    "    root_to_next: {s}\n",
                    .{root_to_next}
                );
                const i_b = root_to_next.input_bounds();
                const o_b = root_to_next.output_bounds();

                opentime.dbg_print(@src(), 
                    "    root_to_next (next root to current!): {s}\n"
                    ++ "    composed transform ranges {s}: {s},"
                    ++ " {s}: {s}\n"
                    ,
                    .{
                        root_to_next,
                        iter.maybe_source.?.space,
                        i_b,
                        next.space,
                        o_b,
                    },
                );
            }
            root_to_current.deinit(allocator);

            current = next;
            root_to_current = root_to_next;
        }

        // check to see if end points were inverted
        if (path_info_.inverted and root_to_current.mappings.len > 0) 
        {
            // const old_proj = root_to_current;
            const inverted_topologies = (
                try root_to_current.inverted(allocator)
            );
            defer allocator.free(inverted_topologies);
            root_to_current.deinit(allocator);
            errdefer opentime.deinit_slice(
                allocator,
                topology_m.Topology,
                inverted_topologies
            );
            if (inverted_topologies.len > 1)
            {
                return error.MoreThanOneCurveIsNotImplemented;
            }
            if (inverted_topologies.len > 0) {
                root_to_current = inverted_topologies[0];
            }
            else {
                return error.NoInvertedTopologies;
            }
        }

        return .{
            .source = endpoints.source,
            .destination = endpoints.destination,
            .src_to_dst_topo = root_to_current,
        };
    }

    fn label_for_node_leaky(
        allocator: std.mem.Allocator,
        ref: SpaceReference,
        code: treecode.Treecode,
    ) !string.latin_s8 
    {
        const item_kind = switch(ref.ref) {
            .track_ptr => "track",
            .clip_ptr => "clip",
            .gap_ptr => "gap",
            .timeline_ptr => "timeline",
            .stack_ptr => "stack",
            .warp_ptr => "warp",
        };

        if (LABEL_HAS_BINARY_TREECODE) 
        {
            return std.fmt.allocPrint(
                allocator,
                "{s}_{s}_{s}",
                .{
                    item_kind,
                    @tagName(ref.label),
                    code,
                }
            );
        } 
        else 
        {
            const args = .{ 
                item_kind,
                @tagName(ref.label), code.hash(), 
            };

            return std.fmt.allocPrint(
                allocator,
                "{s}_{s}_{any}",
                args
            );
        }
    }

    /// write a graphviz (dot) format serialization of this TopologicalMap
    pub fn write_dot_graph(
        self:@This(),
        parent_allocator: std.mem.Allocator,
        filepath: string.latin_s8,
    ) !void 
    {
        if (build_options.graphviz_dot_path == null) {
            return;
        }

        const root_space = self.root(); 
        
        // note that this function is pretty sloppy with allocations.  it
        // doesn't do any cleanup until the function ends, when the entire var
        // arena is cleared in one shot.
        var arena = std.heap.ArenaAllocator.init(
            parent_allocator
        );
        defer arena.deinit();
        const allocator = arena.allocator();

        var buf = std.ArrayList(u8).init(allocator);

        // open the file
        const file = try std.fs.createFileAbsolute(
            filepath,
            .{}
        );
        defer file.close();

        try file.writeAll("digraph OTIO_TopologicalMap {\n");

        const Node = struct {
            space: SpaceReference,
            code: treecode.Treecode,
        };

        var stack = std.ArrayList(Node).init(allocator);

        try stack.append(
            .{
                .space = root_space,
                .code = try treecode.Treecode.init_word(
                    allocator,
                    0b1
                )
            }
        );

        while (stack.items.len > 0) 
        {
            const current = stack.pop();
            const current_label = try label_for_node_leaky(
                allocator,
                current.space,
                current.code
            );

            // left
            {
                var left = try current.code.clone();
                try left.append(0);

                if (self.map_code_to_space.get(left)) 
                    |next| 
                {
                    const next_label = try label_for_node_leaky(
                        allocator,
                        next,
                        left
                    );
                    try file.writeAll(
                        try std.fmt.allocPrint(
                            allocator,
                            "  {s} -> {s}\n",
                            .{current_label, next_label}
                        )
                    );
                    try stack.append(
                        .{
                            .space = next,
                            .code = left
                        }
                    );
                } 
                else 
                {
                    buf.clearAndFree();
                    try left.to_str(&buf);

                    try file.writeAll(
                        try std.fmt.allocPrint(
                            allocator,
                            "  {s} \n  [shape=point]{s} -> {s}\n",
                            .{buf.items, current_label, buf.items }
                        )
                    );
                }
            }

            // right
            {
                var right = try current.code.clone();
                try right.append(1);

                if (self.map_code_to_space.get(right)) 
                    |next| 
                {
                    const next_label = try label_for_node_leaky(
                        allocator,
                        next,
                        right
                    );
                    try file.writeAll(
                        try std.fmt.allocPrint(
                            allocator,
                            "  {s} -> {s}\n",
                            .{current_label, next_label}
                        )
                    );
                    try stack.append(
                        .{
                            .space = next,
                            .code = right
                        }
                    );
                } 
                else 
                {
                    buf.clearAndFree();
                    try right.to_str(&buf);
                    try file.writeAll(
                        try std.fmt.allocPrint(
                            allocator,
                            "  {s} [shape=point]\n  {s} -> {s}\n",
                            .{buf.items, current_label, buf.items}
                        )
                    );
                }
            }
        }

        try file.writeAll("}\n");

        const pngfilepath = try std.fmt.allocPrint(
            allocator,
            "{s}.png",
            .{ filepath }
        );
        defer allocator.free(pngfilepath);

        const arg = &[_][]const u8{
            // fetched from build configuration
            build_options.graphviz_dot_path.?,
            "-Tpng",
            filepath,
            "-o",
            pngfilepath,
        };

        // render to png
        const result = try std.process.Child.run(
            .{
                .allocator = allocator,
                .argv = arg,
            }
        );
        _ = result;
    }

    pub fn path_info(
        self: @This(),
        endpoints: ProjectionOperatorArgs,
    ) !struct {
        endpoints: ProjectionOperatorArgs,
        inverted: bool,
    }
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

        if (treecode.path_exists(source_code, destination_code) == false) 
        {
            errdefer opentime.dbg_print(@src(), 
                "\nERROR\nsource: {s} dest: {s}\n",
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
            return .{
                .inverted = true,
                .endpoints = .{
                    .source = endpoints.destination,
                    .destination = endpoints.source,
                },
            };
        }
        else 
        {
            return .{
                .inverted = false,
                .endpoints = .{
                    .source = endpoints.source,
                    .destination = endpoints.destination,
                },
            };
        }


    }

    /// build a projection operator that projects from the args.source to
    /// args.destination spaces
    pub fn debug_print_time_hierarchy(
        self: @This(),
        allocator: std.mem.Allocator,
        endpoints_arg: ProjectionOperatorArgs,
    ) !void 
    {
        const path_info_ = try self.path_info(endpoints_arg);
        const endpoints = path_info_.endpoints;

        var iter = try TreenodeWalkingIterator.init_from_to(
            allocator,
            &self,
            endpoints,
        );
        defer iter.deinit();

        if (GRAPH_CONSTRUCTION_TRACE_MESSAGES) {
            opentime.dbg_print(@src(), 
                "starting walk from: {s} to: {s}\n",
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
            const dest_to_current = try self.build_projection_operator(
                allocator,
                .{
                    .source = iter.maybe_destination.?.space,
                    .destination = iter.maybe_current.?.space,
                },
            );

            opentime.dbg_print(@src(), 
                "space: {s}\n"
                ++ "      local:  {s}\n",
                .{ 
                    iter.maybe_current.?.space,
                    dest_to_current.src_to_dst_topo.output_bounds(),
                },
            );
        }

        opentime.dbg_print(@src(), 
            "space: {s}\n"
            ++ "      destination:  {s}\n",
            .{ 
                iter.maybe_current.?.space,
                try iter.maybe_destination.?.space.ref.bounds_of(
                    allocator,
                    iter.maybe_destination.?.space.label
                ),
            },
        );
    }
};

/// maps projections to clip.media spaces to regions of whatever space is
/// the source space
pub fn projection_map_to_media_from(
    allocator: std.mem.Allocator,
    topological_map: TopologicalMap,
    source: SpaceReference,
) !ProjectionOperatorMap
{
    var iter = (
        try TreenodeWalkingIterator.init_from(
            allocator,
            &topological_map, 
            source,
        )
    );
    defer iter.deinit();

    var result = ProjectionOperatorMap{
        .allocator = allocator,
        .source = source,
    };

    var proj_args = ProjectionOperatorArgs{
        .source = source,
        .destination = source,
    };
    while (try iter.next())
    {
        const current = iter.maybe_current.?;

        // skip all spaces that are not media spaces
        if (current.space.label != .media) {
            continue;
        }

        proj_args.destination = current.space;

        const child_op = (
            try topological_map.build_projection_operator(
                allocator,
                proj_args,
            )
        );

        const child_op_map = (
            try ProjectionOperatorMap.init_operator(
                allocator,
                child_op,
            )
        );
        defer child_op_map.deinit();

        const last = result;
        defer last.deinit();

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
    const cl = schema.Clip{};
    const cl_ptr = ComposedValueRef{ 
        .clip_ptr = &cl 
    };
    const child_op_map = (
        try ProjectionOperatorMap.init_operator(
            std.testing.allocator,
            .{
                .source = try cl_ptr.space(.presentation),
                .destination = try cl_ptr.space(.media),
                .src_to_dst_topo = topology_m.EMPTY,
            },
        )
    );
    defer child_op_map.deinit();

    const clone = try child_op_map.clone();
    defer clone.deinit();
}

test "ProjectionOperatorMap: projection_map_to_media_from leak test"
{
    const allocator = std.testing.allocator;

    const cl = schema.Clip {
        .bounds_s = .{
            .start = 1,
            .end = 9 
        }
    };
    const cl_ptr = ComposedValueRef.init(&cl);

    const map = try build_topological_map(
        allocator,
        cl_ptr,
    );
    defer map.deinit();

    const m = try projection_map_to_media_from(
        allocator,
        map,
        try cl_ptr.space(.presentation),
    );
    defer m.deinit();

    const mapp = m.operators[0][0].src_to_dst_topo.mappings[0];
    try std.testing.expectEqual(
        4,
        mapp.project_instantaneous_cc(3).ordinate()
    );

    try std.testing.expectEqual(
       4,
       try m.operators[0][0].project_instantaneous_cc(3).ordinate(),
    );
}

/// maps a timeline to sets of projection operators, one set per temporal slice
pub const ProjectionOperatorMap = struct {
    allocator: std.mem.Allocator,

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
            []ProjectionOperator,
            1
        );
        operators[0] = try allocator.dupe(ProjectionOperator, &.{ op });
        
        return .{
            .allocator = allocator,
            .end_points = end_points,
            .operators = operators,
            .source = op.source,
        };
    }

    pub fn deinit(
        self: @This()
    ) void
    {
        self.allocator.free(self.end_points);
        for (self.operators)
            |segment_ops|
        {
            for (segment_ops)
                |op|
            {
                op.deinit(self.allocator);
            }
            self.allocator.free(segment_ops);
        }
        self.allocator.free(self.operators);
    }

    const OverlayArgs = struct{
        over: ProjectionOperatorMap,
        under: ProjectionOperatorMap,
    };
    pub fn merge_composite(
        parent_allocator: std.mem.Allocator,
        args: OverlayArgs
    ) !ProjectionOperatorMap
    {
        if (args.over.is_empty() and args.under.is_empty())
        {
            return .{
                .allocator = parent_allocator,
                .source = args.over.source };
        }
        if (args.over.is_empty())
        {
            return try args.under.clone();
        }
        if (args.under.is_empty())
        {
            return try args.over.clone();
        }

        var arena = std.heap.ArenaAllocator.init(
            parent_allocator
        );
        defer arena.deinit();
        const arena_allocator = arena.allocator();

        const over = args.over;
        const undr = args.under;

        const full_range = opentime.ContinuousInterval{
            .start = @min(over.end_points[0], undr.end_points[0]),
            .end = @max(
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

        var end_points = std.ArrayList(opentime.Ordinate).init(
            parent_allocator,
        );
        var operators = std.ArrayList(
            []ProjectionOperator
        ).init(parent_allocator);

        var current_segment = (
            std.ArrayList(ProjectionOperator).init(parent_allocator)
        );

        // both end point arrays are the same
        for (over_conformed.end_points[0..over_conformed.end_points.len - 1], 0..)
            |p, ind|
        {
            try end_points.append(p);
            for (over_conformed.operators[ind])
                |op|
            {
                try current_segment.append(try op.clone(parent_allocator));
            }
            for (undr_conformed.operators[ind])
                |op|
            {
                try current_segment.append(try op.clone(parent_allocator));
            }
            try operators.append(
                try current_segment.toOwnedSlice(),
            );

            current_segment.clearAndFree();
        }

        try end_points.append(
            over_conformed.end_points[over_conformed.end_points.len - 1]
        );

        return .{
            .allocator = parent_allocator,
            .end_points  = try end_points.toOwnedSlice(),
            .operators  = try operators.toOwnedSlice(),
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
    ) !ProjectionOperatorMap
    {
        var cloned_projection_operators = (
            std.ArrayList(ProjectionOperator).init(self.allocator)
        );

        return .{
            .allocator = self.allocator,
            .source = self.source,
            .end_points = try self.allocator.dupe(
                opentime.Ordinate,
                self.end_points
            ),
            .operators = ops: {
                const outer = (
                    try self.allocator.alloc(
                        []ProjectionOperator,
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
                            try s_mapping.clone(self.allocator)
                        );
                    }

                    inner.* = try cloned_projection_operators.toOwnedSlice();
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
        var tmp_pts = std.ArrayList(opentime.Ordinate).init(allocator);
        defer tmp_pts.deinit();
        var tmp_ops = std.ArrayList([]const ProjectionOperator).init(allocator);
        defer tmp_ops.deinit();

        if (self.end_points[0] > range.start) {
            try tmp_pts.append(range.start);
            try tmp_ops.append(
                &.{}
            );
        }

        try tmp_pts.appendSlice(self.end_points);

        for (self.operators) 
            |self_ops|
        {
            try tmp_ops.append(
                try opentime.slice_with_cloned_contents_allocator(
                    allocator,
                    ProjectionOperator,
                    self_ops,
                )
            );
        }

        if (range.end > self.end_points[self.end_points.len - 1]) 
        {
            try tmp_pts.append(range.end);
            try tmp_ops.append(
                &.{}
            );
        }

        return .{
            .allocator = allocator,
            .end_points = try tmp_pts.toOwnedSlice(),
            .operators = try tmp_ops.toOwnedSlice(),
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
        var tmp_pts = std.ArrayList(opentime.Ordinate).init(allocator);
        var tmp_ops = std.ArrayList([]const ProjectionOperator).init(allocator);

        var ind_self:usize = 0;
        var ind_other:usize = 0;

        var t_next_self = self.end_points[1];
        var t_next_other = pts[1];

        // append origin
        try tmp_pts.append(self.end_points[0]);

        while (
            ind_self < self.end_points.len - 1
            and ind_other < pts.len - 1 
        )
        {
            try tmp_ops.append(
                try opentime.slice_with_cloned_contents_allocator(
                    allocator,
                    ProjectionOperator,
                    self.operators[ind_self],
                )
            );

            t_next_self = self.end_points[ind_self+1];
            t_next_other = pts[ind_other+1];

            if (
                std.math.approxEqAbs(
                    opentime.Ordinate,
                    t_next_self,
                    t_next_other,
                    opentime.EPSILON_ORD
                )
            )
            {
                try tmp_pts.append(t_next_self);
                if (ind_self < self.end_points.len - 1) {
                    ind_self += 1;
                }
                if (ind_other < pts.len - 1) {
                    ind_other += 1;
                }
            }
            else if (t_next_self < t_next_other)
            {
                try tmp_pts.append(t_next_self);
                ind_self += 1;
            }
            else 
            {
                try tmp_pts.append(t_next_other);
                ind_other += 1;
            }
        }

        return .{
            .allocator = allocator,
            .end_points = try tmp_pts.toOwnedSlice(),
            .operators = try tmp_ops.toOwnedSlice(),
            .source = self.source,
        };
    }

};

test "ProjectionOperatorMap: extend_to"
{
    const cl = schema.Clip {
        .bounds_s = .{
            .start = 1,
            .end = 9 
        }
    };
    const cl_ptr = ComposedValueRef{ .clip_ptr = &cl };

    const map = try build_topological_map(
        std.testing.allocator,
        cl_ptr,
    );
    defer map.deinit();

    const cl_presentation_pmap = (
        try projection_map_to_media_from(
            std.testing.allocator,
            map,
            try cl_ptr.space(.presentation),
        )
    );
    defer cl_presentation_pmap.deinit();

    // extend_to no change
    {
        const result = try cl_presentation_pmap.extend_to(
            std.testing.allocator,
            .{
                .start = cl_presentation_pmap.end_points[0],
                .end = cl_presentation_pmap.end_points[1],
            },
        );
        defer result.deinit();

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
            std.testing.allocator,
            .{
                .start = -10,
                .end = 8,
            },
        );
        defer result.deinit();

        try std.testing.expectEqualSlices(
            opentime.Ordinate,
            &.{-10, 0, 8},
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
            std.testing.allocator,
            .{
                .start = 0,
                .end = 18,
            },
        );
        defer result.deinit();

        try std.testing.expectEqualSlices(
            opentime.Ordinate,
            &.{0, 8, 18},
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
    const cl = schema.Clip {
        .bounds_s = .{
            .start = 1,
            .end = 9 
        }
    };
    const cl_ptr = ComposedValueRef{ .clip_ptr = &cl };

    const map = try build_topological_map(
        std.testing.allocator,
        cl_ptr,
    );
    defer map.deinit();

    const cl_presentation_pmap = (
        try projection_map_to_media_from(
            std.testing.allocator,
            map,
            try cl_ptr.space(.presentation),
        )
    );
    defer cl_presentation_pmap.deinit();

    // split_at_each -- no change
    {
        const result = try cl_presentation_pmap.split_at_each(
            std.testing.allocator,
            cl_presentation_pmap.end_points,
        );
        defer result.deinit();

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
        const pts = [_]opentime.Ordinate{ 0, 4, 8 };

        const result = try cl_presentation_pmap.split_at_each(
            std.testing.allocator,
            &pts,
        );
        defer result.deinit();

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
        const pts = [_]opentime.Ordinate{ 0, 1, 4, 8 };

        const result = try cl_presentation_pmap.split_at_each(
            std.testing.allocator,
            &pts,
        );
        defer result.deinit();

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
        const pts1 = [_]opentime.Ordinate{ 0, 4, 8 };
        const pts2 = [_]opentime.Ordinate{ 0, 4, 8 };

        const inter = try cl_presentation_pmap.split_at_each(
            std.testing.allocator,
            &pts1,
        );
        defer inter.deinit();

        const result = try inter.split_at_each(
            std.testing.allocator,
            &pts2,
        );
        defer result.deinit();

        try std.testing.expectEqualSlices(
            opentime.Ordinate,
            &.{0,4,8},
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
    const cl = schema.Clip {
        .bounds_s = .{
            .start = 1,
            .end = 9 
        }
    };
    const cl_ptr = ComposedValueRef{ .clip_ptr = &cl };

    const map = try build_topological_map(
        std.testing.allocator,
        cl_ptr,
    );
    defer map.deinit();

    const cl_presentation_pmap = (
        try projection_map_to_media_from(
            std.testing.allocator,
            map,
            try cl_ptr.space(.presentation),
        )
    );
    defer cl_presentation_pmap.deinit();

    {
        const result = (
            try ProjectionOperatorMap.merge_composite(
                std.testing.allocator,
                .{
                    .over = cl_presentation_pmap,
                    .under = cl_presentation_pmap,
                }
            )
        );
        defer result.deinit();

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

    const cl = schema.Clip {
        .bounds_s = .{
            .start = 1,
            .end = 9 
        }
    };
    const cl_ptr = ComposedValueRef{ .clip_ptr = &cl };

    const map = try build_topological_map(
        std.testing.allocator,
        cl_ptr,
    );
    defer map.deinit();

    const cl_presentation_pmap = (
        try projection_map_to_media_from(
            std.testing.allocator,
            map,
            try cl_ptr.space(.presentation),
        )
    );
    defer cl_presentation_pmap.deinit();

    try std.testing.expectEqual(1, cl_presentation_pmap.operators.len);
    try std.testing.expectEqual(2, cl_presentation_pmap.end_points.len);

    const known_presentation_to_media = (
        try map.build_projection_operator(
            std.testing.allocator,
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
    try std.testing.expectApproxEqAbs(
        known_input_bounds.start,
        guess_input_bounds.start,
        opentime.EPSILON_ORD
    );
    try std.testing.expectApproxEqAbs(
        known_input_bounds.end,
        guess_input_bounds.end,
        opentime.EPSILON_ORD
    );

    // end points match topology
    try std.testing.expectApproxEqAbs(
        cl_presentation_pmap.end_points[0],
        guess_input_bounds.start,
        opentime.EPSILON_ORD
    );
    try std.testing.expectApproxEqAbs(
        cl_presentation_pmap.end_points[1],
        guess_input_bounds.end,
        opentime.EPSILON_ORD
    );

    // known input bounds matches end point
    try std.testing.expectApproxEqAbs(
        known_input_bounds.start,
        cl_presentation_pmap.end_points[0],
        opentime.EPSILON_ORD
    );
    try std.testing.expectApproxEqAbs(
        known_input_bounds.end,
        cl_presentation_pmap.end_points[1],
        opentime.EPSILON_ORD
    );
}

test "ProjectionOperatorMap: track with single clip"
{
    const allocator = std.testing.allocator;

    var tr = schema.Track.init(std.testing.allocator);
    defer tr.deinit();
    const tr_ptr = ComposedValueRef.init(&tr);

    const cl = schema.Clip {
        .bounds_s = .{
            .start = 1,
            .end = 9 
        }
    };
    const cl_ptr = try tr.append_fetch_ref(cl);

    const map = try build_topological_map(
        std.testing.allocator,
        tr_ptr,
    );
    defer map.deinit();

    const source_space = try tr_ptr.space(.presentation);

    const test_maps = &[_]ProjectionOperatorMap{
        // try build_projection_operator_map(
        //     std.testing.allocator,
        //     map,
        //     try cl_ptr.space(.presentation),
        // ),
        try projection_map_to_media_from(
            std.testing.allocator,
            map,
            source_space,
        ),
    };

    for (test_maps)
        |projection_operator_map|
    {
        defer projection_operator_map.deinit();

        try std.testing.expectEqual(1, projection_operator_map.operators.len);
        try std.testing.expectEqual(2, projection_operator_map.end_points.len);

        const known_presentation_to_media = try map.build_projection_operator(
            std.testing.allocator,
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
        try std.testing.expectApproxEqAbs(
            known_input_bounds.start,
            guess_input_bounds.start,
            opentime.EPSILON_ORD
        );
        try std.testing.expectApproxEqAbs(
            known_input_bounds.end,
            guess_input_bounds.end,
            opentime.EPSILON_ORD
        );

        // end points match topology
        try std.testing.expectApproxEqAbs(
            projection_operator_map.end_points[0],
            guess_input_bounds.start,
            opentime.EPSILON_ORD
        );
        try std.testing.expectApproxEqAbs(
            projection_operator_map.end_points[1],
            guess_input_bounds.end,
            opentime.EPSILON_ORD
        );

        // known input bounds matches end point
        try std.testing.expectApproxEqAbs(
            known_input_bounds.start,
            projection_operator_map.end_points[0],
            opentime.EPSILON_ORD
        );
        try std.testing.expectApproxEqAbs(
            known_input_bounds.end,
            projection_operator_map.end_points[1],
            opentime.EPSILON_ORD
        );
    }
}

test "transform: track with two clips"
{
    const allocator = std.testing.allocator;

    var tr = schema.Track.init(allocator);
    defer tr.deinit();

    const cl1 = schema.Clip {
        .bounds_s = .{
            .start = 1,
            .end = 9 
        }
    };
    const cl2 = schema.Clip {
        .bounds_s = .{
            .start = 1,
            .end = 4 
        }
    };
    try tr.append(cl1);

    const cl2_ref = try tr.append_fetch_ref(cl2);
    const tr_ptr = ComposedValueRef.init(&tr);

    const map = try build_topological_map(
        allocator,
        tr_ptr,
    );
    defer map.deinit();

    const track_presentation_space = try tr_ptr.space(.presentation);

    {
        const child_code = (
            try treecode.Treecode.init_word(allocator, 0b1110)
        );
        defer child_code.deinit();

        const child_space = map.map_code_to_space.get(child_code).?;

        const xform = try tr.transform_to_child(
            allocator,
            child_space
        );
        defer xform.deinit(allocator);

        const b = xform.input_bounds();

        try std.testing.expectEqualSlices(
            opentime.Ordinate,
            &.{8},
            &.{b.start},
        );
    }

    {
        const xform = try topology_m.Topology.init_affine(
            allocator,
            .{
                .input_bounds_val = .{
                    .start = 8,
                },
                .input_to_output_xform = .{
                    .offset = -8,
                },
            }
        );
        defer xform.deinit(allocator);
        const po = try map.build_projection_operator(
            allocator,
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
        const xform = try map.build_projection_operator(
            allocator,
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
                cl1_range.duration() + cl2_range.duration() 
            },
            &.{b.start, b.end},
        );
    }
}

test "ProjectionOperatorMap: track with two clips"
{
    const allocator = std.testing.allocator;

    var tr = schema.Track.init(std.testing.allocator);
    defer tr.deinit();

    const cl = schema.Clip {
        .bounds_s = .{
            .start = 1,
            .end = 9 
        }
    };
    try tr.append(cl);
    const cl_ptr = try tr.append_fetch_ref(cl);
    const tr_ptr = ComposedValueRef.init(&tr);

    const map = try build_topological_map(
        std.testing.allocator,
        tr_ptr,
    );
    defer map.deinit();

    const source_space = try tr_ptr.space(.presentation);

    const p_o_map = (
        try projection_map_to_media_from(
            std.testing.allocator,
            map,
            source_space,
        )
    );

    defer p_o_map.deinit();

    try std.testing.expectEqualSlices(
        opentime.Ordinate,
        &.{0,8,16},
        p_o_map.end_points,
    );
    try std.testing.expectEqual(2, p_o_map.operators.len);

    const known_presentation_to_media = (
        try map.build_projection_operator(
            std.testing.allocator,
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
    try std.testing.expectApproxEqAbs(
        known_input_bounds.start,
        guess_input_bounds.start,
        opentime.EPSILON_ORD
    );
    try std.testing.expectApproxEqAbs(
        known_input_bounds.end,
        guess_input_bounds.end,
        opentime.EPSILON_ORD
    );

    // end points match topology
    try std.testing.expectApproxEqAbs(
        8.0,
        guess_input_bounds.start,
        opentime.EPSILON_ORD
    );
    try std.testing.expectApproxEqAbs(
        16,
        guess_input_bounds.end,
        opentime.EPSILON_ORD
    );
}

test "ProjectionOperatorMap: track [c1][gap][c2]"
{
    const allocator = std.testing.allocator;

    var tr = schema.Track.init(std.testing.allocator);
    defer tr.deinit();
    const tr_ptr = ComposedValueRef.init(&tr);

    const cl = schema.Clip {
        .bounds_s = .{
            .start = 1,
            .end = 9 
        }
    };
    try tr.append(cl);
    try tr.append(
        schema.Gap{
            .duration_seconds = 5,
        }
    );
    const cl_ptr = try tr.append_fetch_ref(cl);


    const map = try build_topological_map(
        std.testing.allocator,
        tr_ptr,
    );
    defer map.deinit();

    const source_space = try tr_ptr.space(.presentation);

    const p_o_map = (
        try projection_map_to_media_from(
            std.testing.allocator,
            map,
            source_space,
        )
    );

    defer p_o_map.deinit();

    try std.testing.expectEqualSlices(
        opentime.Ordinate,
        &.{0,8,13, 21},
        p_o_map.end_points,
    );
    try std.testing.expectEqual(3, p_o_map.operators.len);

    const known_presentation_to_media = (
        try map.build_projection_operator(
            std.testing.allocator,
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
    try std.testing.expectApproxEqAbs(
        known_input_bounds.start,
        guess_input_bounds.start,
        opentime.EPSILON_ORD
    );
    try std.testing.expectApproxEqAbs(
        known_input_bounds.end,
        guess_input_bounds.end,
        opentime.EPSILON_ORD
    );

    // end points match topology
    try std.testing.expectApproxEqAbs(
        13,
        guess_input_bounds.start,
        opentime.EPSILON_ORD
    );
    try std.testing.expectApproxEqAbs(
        21,
        guess_input_bounds.end,
        opentime.EPSILON_ORD
    );
}

pub fn depth_child_code_leaky(
    parent_code:treecode.Treecode,
    index: usize
) !treecode.Treecode 
{
    var result = try parent_code.clone();
    var i:usize = 0;
    while (i < index):(i+=1) {
        try result.append(0);
    }
    return result;
}

test "depth_child_hash: math" 
{
    var root = try treecode.Treecode.init_word(
        std.testing.allocator,
        0b1000
    );
    defer root.deinit();

    var i:usize = 0;

    const expected_root:treecode.TreecodeWord = 0b1000;

    while (i<4) 
        : (i+=1) 
    {
        var result = try depth_child_code_leaky(root, i);
        defer result.deinit();

        const expected = std.math.shl(treecode.TreecodeWord, expected_root, i); 

        errdefer opentime.dbg_print(@src(), 
            "iteration: {d}, expected: {b} got: {s}\n",
            .{ i, expected, result }
        );

        try std.testing.expectEqual(expected, result.treecode_array[0]);
    }
}

/// builds a TopologicalMap, which can then construct projection operators
/// across the spaces in the map.  A root item is provided, and the map is
/// built from the presentation space of the root object down towards the
/// leaves.  See TopologicalMap for more details.
pub fn build_topological_map(
    allocator: std.mem.Allocator,
    root_item: ComposedValueRef
) !TopologicalMap 
{
    var tmp_topo_map = try TopologicalMap.init(allocator);
    errdefer tmp_topo_map.deinit();

    const Node = struct {
        path_code: treecode.Treecode,
        object: ComposedValueRef,
    };

    var stack = std.ArrayList(Node).init(allocator);
    defer {
        for (stack.items)
            |n|
        {
            n.path_code.deinit();
        }
        stack.deinit();
    }

    // 1a
    const start_code = try treecode.Treecode.init_word(
        allocator,
        TopologicalMap.ROOT_TREECODE,
    );

    // root node
    try stack.append(
        .{
            .object = root_item,
            .path_code = start_code
        }
    );

    if (GRAPH_CONSTRUCTION_TRACE_MESSAGES) {
        opentime.dbg_print(@src(), "\nstarting graph...\n", .{});
    }

    while (stack.items.len > 0) 
    {
        const current = stack.pop();

        const code_from_stack = current.path_code;
        defer code_from_stack.deinit();

        var current_code = try current.path_code.clone();
        errdefer current_code.deinit();

        // push the spaces for the current object into the map/stack
        {
            const spaces = try current.object.spaces(
                allocator
            );
            defer allocator.free(spaces);

            for (0.., spaces) 
                |index, space_ref| 
            {
                const child_code = try depth_child_code_leaky(
                    current_code,
                    index
                );
                defer child_code.deinit();

                if (GRAPH_CONSTRUCTION_TRACE_MESSAGES) {
                    std.debug.assert(
                        tmp_topo_map.map_code_to_space.get(child_code) == null
                    );
                    std.debug.assert(
                        tmp_topo_map.map_space_to_code.get(space_ref) == null
                    );
                    opentime.dbg_print(@src(), 
                        (
                         "[{d}] code: {s} hash: {d} adding local space: "
                         ++ "'{s}.{s}'\n"
                        ),
                        .{
                            index,
                            child_code,
                            child_code.hash(), 
                            @tagName(space_ref.ref),
                            @tagName(space_ref.label)
                        }
                    );
                }
                try tmp_topo_map.map_space_to_code.put(
                    space_ref,
                    try child_code.clone(),
                );
                try tmp_topo_map.map_code_to_space.put(
                    try child_code.clone(),
                    space_ref
                );

                if (index == (spaces.len - 1)) {
                    current_code.deinit();
                    current_code = try child_code.clone();
                }
            }
        }

        // transforms to children
        const children = switch (current.object) 
        {
            inline .track_ptr, .stack_ptr => |st_or_tr| (
                st_or_tr.children.items
            ),
            // when a pointer is taken from this later, it doesn't persist
            // (I think)
            // @TODO: make the timeline hold a CV instead of a schema.Stack directly
            //        ...then the lifetime of the CVR should be 
            .timeline_ptr => |tl| &[_]ComposableValue{
                    ComposableValue.init(tl.tracks),
            },
            else => &[_]ComposableValue{},
        };

        var children_ptrs = (
            std.ArrayList(ComposedValueRef).init(allocator)
        );
        defer children_ptrs.deinit();
        for (children) 
            |*child| 
        {
            const item_ptr = ComposedValueRef.init(child);
            try children_ptrs.append(item_ptr);
        }

        // for things that already are ComposedValueRef containers
        switch (current.object) {
            .warp_ptr => |wp| {
                try children_ptrs.append(wp.child);
            },
            inline else => {},
        }

        for (children_ptrs.items, 0..) 
            |item_ptr, index| 
        {
            const child_space_code = try sequential_child_code_leaky(
                current_code,
                index
            );
            defer child_space_code.deinit();

            // insert the child scope
            const space_ref = SpaceReference{
                .ref = current.object,
                .label = SpaceLabel.child,
                .child_index = index,
            };

            if (GRAPH_CONSTRUCTION_TRACE_MESSAGES) 
            {
                std.debug.assert(
                    tmp_topo_map.map_code_to_space.get(child_space_code) == null
                );

                if (tmp_topo_map.map_space_to_code.get(space_ref)) 
                    |other_code| 
                {
                    opentime.dbg_print(@src(), 
                        "\n ERROR SPACE ALREADY PRESENT[{d}] code: {s} "
                        ++ "other_code: {s} "
                        ++ "adding child space: '{s}.{s}.{d}'\n",
                        .{
                            index,
                            child_space_code,
                            other_code,
                            @tagName(space_ref.ref),
                            @tagName(space_ref.label),
                            space_ref.child_index.?,
                        }
                    );

                    std.debug.assert(false);
                }
                opentime.dbg_print(@src(), 
                    "[{d}] code: {s} hash: {d} adding child space: '{s}.{s}.{d}'\n",
                    .{
                        index,
                        child_space_code,
                        child_space_code.hash(),
                        @tagName(space_ref.ref),
                        @tagName(space_ref.label),
                        space_ref.child_index.?,
                    }
                );
            }
            try tmp_topo_map.map_space_to_code.put(
                space_ref,
                try child_space_code.clone()
            );
            try tmp_topo_map.map_code_to_space.put(
                try child_space_code.clone(),
                space_ref
            );

            // creates a cone of the child_space_code
            const child_code = try depth_child_code_leaky(
                child_space_code,
                1
            );
            defer child_code.deinit();

            try stack.insert(
                0,
                .{ 
                    .object= item_ptr,
                    .path_code = try child_code.clone()
                }
            );
        }

        current_code.deinit();
    }

    // return result;
    return tmp_topo_map;
}

test "clip topology construction" 
{
    const allocator = std.testing.allocator;

    const start:opentime.Ordinate = 1;
    const end:opentime.Ordinate = 10;
    const cl = schema.Clip {
        .bounds_s = .{
            .start = start,
            .end = end 
        }
    };

    const topo = try cl.topology(allocator);
    defer topo.deinit(allocator);

    try std.testing.expectApproxEqAbs(
        start,
        topo.input_bounds().start,
        opentime.EPSILON_ORD,
    );

    try std.testing.expectApproxEqAbs(
        end,
        topo.input_bounds().end,
        opentime.EPSILON_ORD,
    );
}

test "track topology construction" 
{
    const allocator = std.testing.allocator;

    var tr = schema.Track.init(allocator);
    defer tr.deinit();

    const start:opentime.Ordinate = 1;
    const end:opentime.Ordinate = 10;
    try tr.append(
        schema.Clip {
            .bounds_s = .{
                .start = start,
                .end = end 
            }
        }
    );

    const topo =  try tr.topology(allocator);
    defer topo.deinit(allocator);

    try std.testing.expectApproxEqAbs(
        start,
        topo.input_bounds().start,
        opentime.EPSILON_ORD,
    );

    try std.testing.expectApproxEqAbs(
        end,
        topo.input_bounds().end,
        opentime.EPSILON_ORD,
    );
}

test "build_topological_map: leak sentinel test - single clip"
{
    const cl = schema.Clip {};

    const map = try build_topological_map(
        std.testing.allocator,
        ComposedValueRef.init(&cl)
    );
    defer map.deinit();
}

test "build_topological_map: leak sentinel test track w/ clip"
{
    var tr = schema.Track.init(std.testing.allocator);
    defer tr.deinit();
    const tr_ref = ComposedValueRef.init(&tr);

    try tr.append(schema.Clip{});

    const map = try build_topological_map(
        std.testing.allocator,
        tr_ref,
    );
    defer map.deinit();
}

test "build_topological_map check root node" 
{
    var tr = schema.Track.init(std.testing.allocator);
    defer tr.deinit();
    const tr_ref = ComposedValueRef.init(&tr);

    const start:opentime.Ordinate = 1;
    const end:opentime.Ordinate = 10;
    const cti = opentime.ContinuousInterval{
        .start = start,
        .end = end 
    };

    try tr.append(
        schema.Clip { 
            .bounds_s = cti, 
        }
    );

    var i:i32 = 0;
    while (i < 10) 
        : (i += 1)
    {
        try tr.append(
            schema.Clip {
                .bounds_s = cti,
            }
        );
    }

    try std.testing.expectEqual(
        11,
        tr.children.items.len
    );

    const map = try build_topological_map(
        std.testing.allocator,
        tr_ref,
    );
    defer map.deinit();

    try std.testing.expectEqual(
        tr_ref.space(.presentation),
        map.root(),
    );
}

test "path_code: graph test" 
{
    var tr = schema.Track.init(std.testing.allocator);
    defer tr.deinit();
    const tr_ref = ComposedValueRef.init(&tr);

    const start:opentime.Ordinate = 1;
    const end:opentime.Ordinate = 10;

    const cl = schema.Clip {
        .bounds_s = .{
            .start = start,
            .end = end 
        }
    };
    try tr.append(cl);

    var i:i32 = 0;
    while (i < 10) 
        : (i+=1)
    {
        try tr.append(
            schema.Clip {
                .bounds_s = .{
                    .start = start,
                    .end = end 
                }
            }
        );
    }

    try std.testing.expectEqual(11, tr.children.items.len);

    const map = try build_topological_map(
        std.testing.allocator,
        tr_ref,
    );
    defer map.deinit();

    try std.testing.expectEqual(
        tr_ref.space(.presentation),
        map.root(),
    );

    try map.write_dot_graph(
        std.testing.allocator,
        "/var/tmp/graph_test_output.dot"
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
        std.testing.allocator,
        "/var/tmp/current.dot",
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
            try tr.child_ptr_from_index(t.ind).space(SpaceLabel.presentation)
        );
        const result = (
            map.map_space_to_code.get(space) 
            orelse return error.NoSpaceForCode
        );

        errdefer std.log.err(
            "\n[iteration: {d}] index: {d} expected: {b} result: {s} \n",
            .{t_i, t.ind, t.expect, result}
        );

        const expect = try treecode.Treecode.init_word(
            std.testing.allocator,
            t.expect
        );
        defer expect.deinit();

        try std.testing.expect(expect.eql(result));
    }
}

test "schema.Track with clip with identity transform projection" 
{
    var tr = schema.Track.init(std.testing.allocator);
    defer tr.deinit();
    const tr_ref = ComposedValueRef.init(&tr);

    const start:opentime.Ordinate = 1;
    const end:opentime.Ordinate = 10;
    const range = opentime.ContinuousInterval{
        .start = start,
        .end = end,
    };
    
    const cl_template = schema.Clip{
        .bounds_s = range
    };

    // reserve capcacity so that the reference isn't invalidated
    try tr.children.ensureTotalCapacity(11);
    const cl_ref = try tr.append_fetch_ref(cl_template);
    try std.testing.expectEqual(cl_ref, tr.child_ptr_from_index(0));

    var i:i32 = 0;
    while (i < 10) 
        : (i+=1)
    {
        try tr.append(cl_template);
    }

    const map = try build_topological_map(
        std.testing.allocator,
        tr_ref,
    );
    defer map.deinit();

    try std.testing.expectEqual(11, tr_ref.track_ptr.children.items.len);

    const track_to_clip = try map.build_projection_operator(
        std.testing.allocator,
        .{
            .source = try tr_ref.space(SpaceLabel.presentation),
            .destination =  try cl_ref.space(SpaceLabel.media)
        }
    );
    defer track_to_clip.deinit(std.testing.allocator);

    // check the bounds
    try std.testing.expectApproxEqAbs(
        0,
        track_to_clip.src_to_dst_topo.input_bounds().start,
        opentime.EPSILON_ORD,
    );

    try std.testing.expectApproxEqAbs(
        end - start,
        track_to_clip.src_to_dst_topo.input_bounds().end,
        opentime.EPSILON_ORD,
    );

    // check the projection
    try std.testing.expectApproxEqAbs(
        4,
        try track_to_clip.project_instantaneous_cc(3).ordinate(),
        opentime.EPSILON_ORD,
    );
}


test "TopologicalMap: schema.Track with clip with identity transform topological" 
{
    const allocator = std.testing.allocator;

    var tr = schema.Track.init(std.testing.allocator);
    defer tr.deinit();

    const cl_ref = try tr.append_fetch_ref(
        schema.Clip {
            .bounds_s = .{
                .start = 0,
                .end = 2 
            } 
        }
    );

    const root = ComposedValueRef.init(&tr);

    const map = try build_topological_map(
        std.testing.allocator,
        root,
    );
    defer map.deinit();

    try std.testing.expectEqual(5, map.map_code_to_space.count());
    try std.testing.expectEqual(5, map.map_space_to_code.count());

    try std.testing.expectEqual(root, map.root().ref);

    const maybe_root_code = map.map_space_to_code.get(map.root());
    try std.testing.expect(maybe_root_code != null);
    const root_code = maybe_root_code.?;

    // root object code
    {
        var tc = try treecode.Treecode.init_word(
            std.testing.allocator,
            0b1
        );
        defer tc.deinit();
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
            std.testing.allocator,
            0b10010
        );
        defer tc.deinit();
        errdefer opentime.dbg_print(@src(), 
            "\ntc: {s}, clip_code: {s}\n",
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
        try map.build_projection_operator(
            std.testing.allocator,
            .{
                .source = try root.space(SpaceLabel.presentation),
                .destination = try cl_ref.space(SpaceLabel.media)
            }
        )
    );
    defer root_presentation_to_clip_media.deinit(allocator);

    try std.testing.expectError(
        topology_m.mapping.Mapping.ProjectionError.OutOfBounds,
        root_presentation_to_clip_media.project_instantaneous_cc(3).ordinate()
    );

    try std.testing.expectApproxEqAbs(
        1,
        try root_presentation_to_clip_media.project_instantaneous_cc(1).ordinate(),
        opentime.EPSILON_ORD,
    );
}

test "Projection: schema.Track with single clip with identity transform and bounds" 
{
    const allocator = std.testing.allocator;

    var tr = schema.Track.init(std.testing.allocator);
    defer tr.deinit();

    const root = ComposedValueRef{ .track_ptr = &tr };

    const cl = schema.Clip {
        .bounds_s = .{
            .start = 0,
            .end = 2 
        }
    };
    const clip = try tr.append_fetch_ref(cl);

    const map = try build_topological_map(
        std.testing.allocator,
        root,
    );
    defer map.deinit();

    try std.testing.expectEqual(
        5,
        map.map_code_to_space.count()
    );
    try std.testing.expectEqual(
        5,
        map.map_space_to_code.count()
    );

    const root_presentation_to_clip_media = try map.build_projection_operator(
        std.testing.allocator,
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
    try std.testing.expectApproxEqAbs(
        expected_media_temporal_bounds.start,
        actual_media_temporal_bounds.start,
        opentime.EPSILON_ORD,
    );

    try std.testing.expectApproxEqAbs(
        expected_media_temporal_bounds.end,
        actual_media_temporal_bounds.end,
        opentime.EPSILON_ORD,
    );

    try std.testing.expectError(
        topology_m.mapping.Mapping.ProjectionError.OutOfBounds,
        root_presentation_to_clip_media.project_instantaneous_cc(3).ordinate()
    );
}

test "Projection: schema.Track with multiple clips with identity transform and bounds" 
{
    const allocator = std.testing.allocator;

    //
    //                          0               3             6
    // track.presentation space       [---------------*-------------)
    // track.intrinsic space    [---------------*-------------)
    // child.clip presentation space  [--------)[-----*---)[-*------)
    //                          0        2 0    1   2 0       2 
    //
    var tr = schema.Track.init(std.testing.allocator);
    defer tr.deinit();
    const track_ptr = ComposedValueRef{ .track_ptr = &tr };

    const cl = schema.Clip { .bounds_s = .{ .start = 0, .end = 2 } };

    // add three copies
    try tr.append(cl);
    try tr.append(cl);
    const cl2_ref = try tr.append_fetch_ref(cl);

    const TestData = struct {
        index: usize,
        track_ord: opentime.Ordinate,
        expected_ord: opentime.Ordinate,
        err: bool
    };

    const map = try build_topological_map(
        std.testing.allocator,
        track_ptr,
    );
    defer map.deinit();

    const tests = [_]TestData{
        .{ .index = 1, .track_ord = 3, .expected_ord = 1, .err = false},
        .{ .index = 0, .track_ord = 1, .expected_ord = 1, .err = false },
        .{ .index = 2, .track_ord = 5, .expected_ord = 1, .err = false },
        .{ .index = 0, .track_ord = 7, .expected_ord = 1, .err = true },
    };


    // check that the child transform is correctly built
    {
        const po = try map.build_projection_operator(
            std.testing.allocator,
            .{
                .source = try track_ptr.space(.presentation),
                .destination = (
                    try cl2_ref.space(.media)
                ),
            }
        );
        defer po.deinit(std.testing.allocator);

        const b = po.src_to_dst_topo.input_bounds();

        try std.testing.expectEqualSlices(
            opentime.Ordinate,
            &.{ 4, 6 },
            &.{ b.start, b.end },
        );
    }

    const po_map = try projection_map_to_media_from(
        std.testing.allocator,
        map,
        try track_ptr.space(.presentation),
    );
    defer po_map.deinit();

    try std.testing.expectEqual(
        3,
        po_map.operators.len,
    );

    // 1
    for (po_map.operators, &[_][2]opentime.Ordinate{ .{ 0, 2}, .{ 2, 4 }, .{ 4, 6 } })
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
        &.{ 0, 2, 4, 6},
        po_map.end_points,
    );


    for (tests, 0..) 
        |t, t_i| 
    {
        const child = tr.child_ptr_from_index(t.index);

        const tr_presentation_to_clip_media = try map.build_projection_operator(
        std.testing.allocator,
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
                tr_presentation_to_clip_media.project_instantaneous_cc(t.track_ord).ordinate()
            );
        }
        else{
            const result = try tr_presentation_to_clip_media.project_instantaneous_cc(t.track_ord).ordinate();

            try std.testing.expectApproxEqAbs(result, t.expected_ord, opentime.EPSILON_ORD);
        }
    }

    const clip = tr.child_ptr_from_index(0);

    const root_presentation_to_clip_media = try map.build_projection_operator(
        std.testing.allocator,
        .{ 
            .source = try track_ptr.space(SpaceLabel.presentation),
            .destination = try clip.space(SpaceLabel.media),
        }
    );
    defer root_presentation_to_clip_media.deinit(allocator);

    const expected_range = (
        cl.bounds_s orelse opentime.ContinuousInterval{}
    );
    const actual_range = (
        root_presentation_to_clip_media.src_to_dst_topo.input_bounds()
    );

    // check the bounds
    try std.testing.expectApproxEqAbs(
        expected_range.start,
        actual_range.start,
        opentime.EPSILON_ORD,
    );

    try std.testing.expectApproxEqAbs(
        expected_range.end,
        actual_range.end,
        opentime.EPSILON_ORD,
    );

    try std.testing.expectError(
        opentime.ProjectionResult.Errors.OutOfBounds,
        root_presentation_to_clip_media.project_instantaneous_cc(3).ordinate(),
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
            .{ .in = 0, .out = 0, },
            .{ .in = 10, .out = 10, },
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
    try std.testing.expectApproxEqAbs(
        0,
        curve_bounds_input.start, opentime.EPSILON_ORD
    );
    try std.testing.expectApproxEqAbs(
        10,
        curve_bounds_input.end, opentime.EPSILON_ORD
    );

    // test the output space range (the media space of the clip)
    const curve_bounds_output = (
        xform_curve.extents_output()
    );
    try std.testing.expectApproxEqAbs(
        0,
        curve_bounds_output.start, opentime.EPSILON_ORD
    );
    try std.testing.expectApproxEqAbs(
        10,
        curve_bounds_output.end, opentime.EPSILON_ORD
    );

    try std.testing.expect(curve_topo.mappings.len > 0);

    const media_temporal_bounds:opentime.ContinuousInterval = .{
        .start = 100,
        .end = 110,
    };
    const cl = schema.Clip {
        .bounds_s = media_temporal_bounds,
    };
    const cl_ptr:ComposedValueRef = .{ .clip_ptr = &cl };

    const wp: schema.Warp = .{
        .child = cl_ptr,
        .transform = curve_topo,
    };

    const wp_ptr : ComposedValueRef = .{ .warp_ptr = &wp };

    const map = try build_topological_map(
        allocator,
        wp_ptr,
    );
    defer map.deinit();

    // presentation->media (forward projection)
    {
        const clip_presentation_to_media_proj = (
            try map.build_projection_operator(
                allocator,
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
        try std.testing.expectApproxEqAbs(
            curve_bounds_output.start, 
            input_bounds.start,
            opentime.EPSILON_ORD
        );
        try std.testing.expectApproxEqAbs(
            curve_bounds_output.end, 
            input_bounds.end,
            opentime.EPSILON_ORD
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
            try std.testing.expectApproxEqAbs(
                100,
                clip_media_to_presentation_input_bounds.start,
                opentime.EPSILON_ORD
            );
            try std.testing.expectApproxEqAbs(
                110,
                clip_media_to_presentation_input_bounds.end,
                opentime.EPSILON_ORD
            );

            try std.testing.expect(
                clip_presentation_to_media_proj.src_to_dst_topo.mappings.len > 0
            );

            // walk over the presentation space of the curve
            const o_s_time = input_bounds.start;
            const o_e_time = input_bounds.end;
            var output_time = o_s_time;
            while (output_time < o_e_time) 
                : (output_time += 0.01) 
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

                try std.testing.expectApproxEqAbs(
                    computed_output_time,
                    output_time,
                    opentime.EPSILON_ORD
                );
            }
        }
    }

    // media->presentation (reverse projection)
    {
        const clip_media_to_presentation = (
            try map.build_projection_operator(
                allocator,
                .{
                    .source =  try cl_ptr.space(SpaceLabel.media),
                    .destination = try wp_ptr.space(SpaceLabel.presentation),
                }
            )
        );
        defer clip_media_to_presentation.deinit(allocator);

        try std.testing.expectApproxEqAbs(
            6.5745,
            try clip_media_to_presentation.project_instantaneous_cc(
                107
            ).ordinate(),
            opentime.EPSILON_ORD,
        );
    }
}

fn sequential_child_code_leaky(
    src: treecode.Treecode,
    index: usize
) !treecode.Treecode 
{
    var result = try src.clone();
    var i:usize = 0;
    while (i <= index)
        :(i+=1) 
    {
        try result.append(1);
    }
    return result;
}

test "sequential_child_hash: math" 
{
    var root = try treecode.Treecode.init_word(
        std.testing.allocator,
        0b1000
    );
    defer root.deinit();

    var test_code = try root.clone();
    defer test_code.deinit();

    var i:usize = 0;
    while (i<4) 
        : (i+=1) 
    {
        var result = try sequential_child_code_leaky(root, i);
        defer result.deinit();

        try test_code.append(1);

        errdefer opentime.dbg_print(@src(), 
            "iteration: {d}, expected: {s} got: {s}\n",
            .{ i, test_code, result }
        );

        try std.testing.expect(test_code.eql(result));
    }
}

test "label_for_node_leaky" 
{
    var tr = schema.Track.init(std.testing.allocator);
    const sr = SpaceReference{
        .label = SpaceLabel.presentation,
        .ref = .{ .track_ptr = &tr } 
    };

    var tc = try treecode.Treecode.init_word(
        std.testing.allocator,
        0b1101001
    );
    defer tc.deinit();

    const result = try TopologicalMap.label_for_node_leaky(
        std.testing.allocator,
        sr,
        tc
    );
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("track_presentation_1101001", result);
}

test "test spaces list" 
{
    const cl = schema.Clip{};
    const it = ComposedValueRef{ .clip_ptr = &cl };
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

    var tr = schema.Track.init(allocator);
    defer tr.deinit();

    // media is 9 seconds long and runs at 4 hz.
    const media_source_range = (
        opentime.ContinuousInterval{
            .start = 1,
            .end = 10,
        }
    );
    const media_discrete_info = (
        sampling.SampleIndexGenerator{
            .sample_rate_hz = 4,
            .start_index = 0,
        }
    );

    // construct the clip and add it to the track
    const cl = schema.Clip {
        .media = .{
            .bounds_s = media_source_range,
            .discrete_info = media_discrete_info,
        },
    };
    const cl_ptr = try tr.append_fetch_ref(cl);
    const tr_ptr = ComposedValueRef.init(&tr);

    const map = try build_topological_map(
        allocator,
        tr_ptr
    );
    defer map.deinit();

    try map.write_dot_graph(
        allocator,
        "/var/tmp/sampling_test.dot"
    );

    const track_to_media = (
        try map.build_projection_operator(
            allocator,
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
        try std.testing.expectApproxEqAbs(
            4.5,
            try track_to_media.project_instantaneous_cc(3.5).ordinate(),
            opentime.EPSILON_ORD,
        );

        // for discrete non-interpolated data sources, allow projection to a
        // discrete index space
        try std.testing.expectEqual(
            // ??? - can't be prescriptive about how data sources are indexed, ie
            // paths to EXR frames or something
            (3 + 1) * 4,
            try track_to_media.project_instantaneous_cd(3),
        );
    }

    // range projection tests
    {
        const test_range_in_track:opentime.ContinuousInterval = .{
            .start = 3.5,
            .end = 4.5,
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

            try std.testing.expectApproxEqAbs(
                4.5,
                b.start,
                opentime.EPSILON_ORD,
            );

            try std.testing.expectApproxEqAbs(
                5.5,
                b.end,
                opentime.EPSILON_ORD,
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

    var tl = try schema.Timeline.init(allocator);
    tl.discrete_info.presentation = .{
        .sample_rate_hz = 24,
        .start_index = 12
    };


    var tr = schema.Track.init(allocator);
    defer tr.deinit();

    // media is 9 seconds long and runs at 4 hz.
    const media_source_range = opentime.ContinuousInterval{
        .start = 1,
        .end = 10,
    };
    const media_discrete_info = (
        sampling.SampleIndexGenerator{
            .sample_rate_hz = 4,
            .start_index = 0,
        }
    );

    // construct the clip and add it to the track
    const cl = schema.Clip {
        .media = .{
            .bounds_s = media_source_range,
            .discrete_info = media_discrete_info,
        },
    };
    defer cl.destroy(allocator);

    const wp : schema.Warp = .{
        .child = .{ .clip_ptr = &cl },
        .transform = try topology_m.Topology.init_affine(
            allocator,
            .{
                .input_to_output_xform = .{
                    .scale = 2,
                },
            },
        ),
    };
    defer wp.transform.deinit(allocator);

    try tr.append(wp);
    try tl.tracks.append(tr);
    const tl_ptr = ComposedValueRef{
        .timeline_ptr = &tl 
    };
    defer tl.tracks.deinit();

    const tr_ptr : ComposedValueRef = tl.tracks.child_ptr_from_index(0);
    const cl_ptr = wp.child;

    const map_tr = try build_topological_map(
        allocator,
        tr_ptr
    );
    defer map_tr.deinit();

    const map_tl = try build_topological_map(
        allocator,
        tl_ptr
    );
    defer map_tl.deinit();

    try map_tr.write_dot_graph(
        allocator,
        "/var/tmp/sampling_test.dot"
    );

    const track_to_media = (
        try map_tr.build_projection_operator(
            allocator,
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
        try std.testing.expectApproxEqAbs(
            // (3.5*2 + 1),
            8,
            try track_to_media.project_instantaneous_cc(3.5).ordinate(),
            opentime.EPSILON_ORD,
        );

        // for discrete non-interpolated data sources, allow projection to a
        // discrete index space
        try std.testing.expectEqual(
            // ??? - can't be prescriptive about how data sources are indexed, ie
            // paths to EXR frames or something
            (3*2 + 1) * 4,
            try track_to_media.project_instantaneous_cd(3),
        );
    }

    // range projection tests
    {
        const test_range_in_track:opentime.ContinuousInterval = .{
            .start = 3.5,
            .end = 4.5,
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

            try std.testing.expectApproxEqAbs(
                8,
                b.start,
                opentime.EPSILON_ORD,
            );

            try std.testing.expectApproxEqAbs(
                // (4.5 * 2 + 1)
                10,
                b.end,
                opentime.EPSILON_ORD,
            );
        }

        // continuous -> discrete
        {
            //                                   (3.5s*2 + 1s)*4
            const expected = [_]sampling.sample_index_t{ 
                32, 34, 36, 38, 
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
                "/var/tmp/discrete_to_continuous_test.dot"
            );

            const timeline_to_media = (
                try map_tl.build_projection_operator(
                    allocator,
                    .{
                        .source = try tl_ptr.space(SpaceLabel.presentation),
                        // does the discrete / continuous need to be disambiguated?
                        .destination = try cl_ptr.space(SpaceLabel.media),
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

            try std.testing.expectEqual(
                (
               // should  v this be a 1.0?
                 start + 2.0/@as(
                     opentime.Ordinate,
                     @floatFromInt(
                         tl.discrete_info.presentation.?.sample_rate_hz
                     )
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

/// iterator that walks over each node in the graph, returning the node at each
/// step
const TreenodeWalkingIterator = struct{
    const Node = struct {
        space: SpaceReference,
        code: treecode.Treecode,
 
        pub fn format(
            self: @This(),
            // fmt
            comptime _: []const u8,
            // options
            _: std.fmt.FormatOptions,
            writer: anytype,
        ) !void 
        {
            try writer.print(
                "Node(.space: {s}, .code: {s})",
                .{
                    self.space,
                    self.code,
                }
            );
        }
    };

    stack: std.ArrayList(Node),
    maybe_current: ?Node,
    maybe_previous: ?Node,
    map: *const TopologicalMap,
    allocator: std.mem.Allocator,
    maybe_source: ?Node = null,
    maybe_destination: ?Node = null,

    pub fn init(
        allocator: std.mem.Allocator,
        map: *const TopologicalMap,
    ) !TreenodeWalkingIterator
    {
        return TreenodeWalkingIterator.init_from(
            allocator,
            map, 
            map.root()
        );
    }

    pub fn init_from(
        allocator: std.mem.Allocator,
        map: *const TopologicalMap,
        /// a source in the map to start the map from
        source: SpaceReference,
    ) !TreenodeWalkingIterator
    {
        const start_code = (
            map.map_space_to_code.get(source) 
            orelse return error.NotInMapError
        );

        var result = TreenodeWalkingIterator{
            .stack = std.ArrayList(Node).init(allocator),
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
            .{
                .space = source,
                .code = try start_code.clone(),
            }
        );

        return result;
    }

    /// an iterator that walks from the source node to the destination node
    pub fn init_from_to(
        allocator: std.mem.Allocator,
        map: *const TopologicalMap,
        endpoints: ProjectionOperatorArgs,
    ) !TreenodeWalkingIterator
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

        if (treecode.path_exists(source_code, destination_code) == false) 
        {
            errdefer opentime.dbg_print(@src(), 
                "\nERROR\nsource: {s} dest: {s}\n",
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
            try TreenodeWalkingIterator.init_from(
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
        self: *@This()
    ) void
    {
        if (self.maybe_previous)
            |n|
        {
            n.code.deinit();
        }
        if (self.maybe_current)
            |n|
        {
            n.code.deinit();
        }
        for (self.stack.items)
            |n|
        {
            n.code.deinit();
        }
        self.stack.deinit();
    }

    pub fn next(
        self: *@This()
    ) !bool
    {
        if (self.stack.items.len == 0) {
            return false;
        }

        if (self.maybe_previous)
            |prev|
        {
            prev.code.deinit();
        }
        self.maybe_previous = self.maybe_current;

        self.maybe_current = self.stack.pop();
        const current = self.maybe_current.?;

        // if there is a destination, walk in that direction. Otherwise, walk
        // exhaustively
        const next_steps : []const u1 = (
            if (self.maybe_destination) |dest| &[_]u1{ 
                try current.code.next_step_towards(dest.code)
            }
            else &.{
                0, 1
            }
        );

        for (next_steps)
            |next_step|
        {
            var next_code = try current.code.clone();
            try next_code.append(@intCast(next_step));

            if (self.map.map_code_to_space.get(next_code))
                |next_node|
            {
                try self.stack.append(
                    .{
                        .space = next_node,
                        .code = next_code,
                    }
                );
            }
            else {
                next_code.deinit();
            }
        }

        return self.maybe_current != null;
    }
};

test "TestWalkingIterator: clip"
{
    // media is 9 seconds long and runs at 4 hz.
    const media_source_range = opentime.ContinuousInterval{
        .start = 1,
        .end = 10,
    };

    const cl = schema.Clip {
        .bounds_s = media_source_range,
    };
    const cl_ptr = ComposedValueRef.init(&cl);

    const map = try build_topological_map(
        std.testing.allocator,
        cl_ptr,
    );
    defer map.deinit();

    try map.write_dot_graph(std.testing.allocator, "/var/tmp/walk.dot");

    var node_iter = try TreenodeWalkingIterator.init(
        std.testing.allocator,
        &map,
    );
    defer node_iter.deinit();

    var count:usize = 0;
    while (try node_iter.next())
    {
        count += 1;
    }

    // 5: clip presentation, clip media
    try std.testing.expectEqual(2, count);
}

test "TestWalkingIterator: track with clip"
{
    var tr = schema.Track.init(std.testing.allocator);
    defer tr.deinit();

    // media is 9 seconds long and runs at 4 hz.
    const media_source_range = opentime.ContinuousInterval{
        .start = 1,
        .end = 10,
    };

    // construct the clip and add it to the track
    const cl = schema.Clip {
        .bounds_s = media_source_range,
    };
    const cl_ptr = try tr.append_fetch_ref(cl);
    const tr_ptr = ComposedValueRef.init(&tr);

    const map = try build_topological_map(
        std.testing.allocator,
        tr_ptr
    );
    defer map.deinit();

    try map.write_dot_graph(std.testing.allocator, "/var/tmp/walk.dot");

    var count:usize = 0;

    // from the top
    {
        var node_iter = try TreenodeWalkingIterator.init(
            std.testing.allocator,
            &map,
        );
        defer node_iter.deinit();

        while (try node_iter.next())
        {
            count += 1;
        }

        // 5: track presentation, input, child, clip presentation, clip media
        try std.testing.expectEqual(5, count);
    }

    // from the clip
    {
        var node_iter = (
            try TreenodeWalkingIterator.init_from(
                std.testing.allocator,
                &map,
                try cl_ptr.space(.presentation),
            )
        );
        defer node_iter.deinit();

        count = 0;
        while (try node_iter.next())
        {
            count += 1;
        }

        // 2: clip presentation, clip media
        try std.testing.expectEqual(2, count);
    }
}

test "TestWalkingIterator: track with clip w/ destination"
{
    var tr = schema.Track.init(std.testing.allocator);
    defer tr.deinit();

    // media is 9 seconds long and runs at 4 hz.
    const media_source_range = opentime.ContinuousInterval{
        .start = 1,
        .end = 10,
    };

    // construct the clip and add it to the track
    const cl = schema.Clip {
        .bounds_s = media_source_range,
    };
    try tr.append(cl);

    const cl2 = schema.Clip {
        .bounds_s = media_source_range,
    };
    const cl_ptr = try tr.append_fetch_ref(cl2);
    const tr_ptr = ComposedValueRef.init(&tr);

    const map = try build_topological_map(
        std.testing.allocator,
        tr_ptr
    );
    defer map.deinit();

    try map.write_dot_graph(
        std.testing.allocator,
        "/var/tmp/walk.dot"
    );

    var count:usize = 0;

    // from the top to the second clip
    {
        var node_iter = (
            try TreenodeWalkingIterator.init_from_to(
                std.testing.allocator,
                &map,
                .{
                    .source = try tr_ptr.space(.presentation),
                    .destination = try cl_ptr.space(.media),
                },
            )
        );
        defer node_iter.deinit();

        count = 0;
        while (try node_iter.next())
            : (count += 1)
        {
        }

        // 2: clip presentation, clip media
        try std.testing.expectEqual(6, count);
    }
}

test "schema.Clip: Animated Parameter example"
{
    const root_allocator = std.testing.allocator;

    var arena = std.heap.ArenaAllocator.init(root_allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    const media_source_range = opentime.ContinuousInterval{
        .start = 1,
        .end = 10,
    };
    const media_discrete_info = (
        sampling.SampleIndexGenerator{
            .sample_rate_hz = 4,
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
                        .{ .in = 0, .out = 1 },
                        .{ .in = 1, .out = 1.25 },
                        .{ .in = 5, .out = 8},
                        .{ .in = 8, .out = 10},
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
    var tl = try schema.Timeline.init(allocator);
    // tl.name = try allocator.dupe(u8, "Example schema.Timeline");
    tl.name = try allocator.dupe(u8, "Example schema.Timeline");

    tl.discrete_info.presentation = .{
        // matches the media rate
        .sample_rate_hz = 24,
        .start_index = 0,
    };

    defer tl.recursively_deinit();
    const tl_ptr = ComposedValueRef{
        .timeline_ptr = &tl 
    };

    // track
    var tr = schema.Track.init(allocator);
    tr.name = try allocator.dupe(u8, "Example Parent schema.Track");

    // clips
    const cl1 = schema.Clip {
        .name = try allocator.dupe(
            u8,
            "Spaghetti.wav",
        ),
        .media = .{
            .bounds_s = .{
                .start = 1,
                .end = 6,
            },
            .discrete_info = .{
                .sample_rate_hz = 24,
                .start_index = 0,
            },
            .ref = .{ 
                .signal = .{
                    .signal_generator = .{
                        .signal = .sine,
                        .duration_s = 6.0,
                        .frequency_hz = 24,
                    },
                },
            },
        }
    };
    defer cl1.destroy(allocator);
    const cl_ptr = ComposedValueRef.init(&cl1);

    // new for this test - add in an warp on the clip, which holds the frame
    const wp = schema.Warp {
        .child = cl_ptr,
        .interpolating = true,
        .transform = try topology_m.Topology.init_affine(
            allocator,
            .{
                .input_bounds_val = .{
                    .start = 0,
                    .end = 5,
                },
                .input_to_output_xform = .{
                    .offset = 10.0/24.0,
                    .scale = 2,
                },
            },
        )
    };
    defer wp.transform.deinit(allocator);
    try tr.append(wp);

    _ = try tl.tracks.append_fetch_ref(tr);

    const tp = try build_topological_map(
        allocator,
        tl_ptr
    );
    defer tp.deinit();

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
        .start = 100,
        .end = 110,
    };

    const cl = schema.Clip {
        .bounds_s = media_temporal_bounds,
    };
    defer cl.destroy(allocator);
    const cl_ptr = ComposedValueRef.init(&cl);

    const cl_media = try cl_ptr.space(SpaceLabel.media);

    const TestCase = struct {
        label: []const u8,
        presentation_range : [2]opentime.Ordinate, 
        warp_child_range : [2]opentime.Ordinate,
        presentation_test : opentime.Ordinate,
        clip_media_test : opentime.Ordinate,
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
            .in = t.presentation_range[0],
            .out = t.warp_child_range[0],
        };
        const end:curve.ControlPoint = .{
            .in = t.presentation_range[1],
            .out = t.warp_child_range[1],
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
                "produced transform: {s}\n",
                .{ xform }
            );
        }

        const warp : schema.Warp = .{
            .child = cl_ptr,
            .transform = xform,
        };

        const wp_ptr : ComposedValueRef = .{ .warp_ptr =  &warp };
        const wp_pres = try wp_ptr.space(SpaceLabel.presentation);

        const map = try build_topological_map(
            allocator,
            wp_ptr,
        );
        defer map.deinit();

        // presentation->media (forward projection)
        {
            const warp_pres_to_media_topo = (
                try map.build_projection_operator(
                    allocator,
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
                "test data:\nprovided: {s}\n"
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

            try std.testing.expectApproxEqAbs(
                start.in,
                input_bounds.start,
                opentime.EPSILON_ORD,
            );

            try std.testing.expectApproxEqAbs(
                end.in,
                input_bounds.end,
                opentime.EPSILON_ORD,
            );

            try std.testing.expectApproxEqAbs(
                t.clip_media_test,
                try warp_pres_to_media_topo.project_instantaneous_cc(
                    t.presentation_test,
                ).ordinate(),
                opentime.EPSILON_ORD,
            );
        }

        // media->presentation (reverse projection)
        {
            const clip_media_to_presentation = (
                try map.build_projection_operator(
                    allocator,
                    .{
                        .source =  cl_media,
                        .destination = wp_pres,
                    }
                )
            );
            defer clip_media_to_presentation.deinit(allocator);

            // @TODO: XXX deal with this check
            if (t.project_to_finite) {
                try std.testing.expectApproxEqAbs(
                    t.presentation_test,
                    try clip_media_to_presentation.project_instantaneous_cc(
                        t.clip_media_test,
                    ).ordinate(),
                    opentime.EPSILON_ORD,
                );
            }
            else 
            {
                const r = clip_media_to_presentation.project_instantaneous_cc(
                    t.clip_media_test,
                );
                try std.testing.expectEqual(
                    0,
                    r.SuccessInterval.start
                );
                try std.testing.expectEqual(
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
                .start = 0,
                .end = 8,
            },
            .input_to_output_xform = .{
                .offset = 1,
            },
        },
    );
    defer aff1.deinit(allocator);

    const cl = schema.Clip{};
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

    try std.testing.expectEqual(
        4,
        try po_cloned_again.project_instantaneous_cc(3).ordinate(),
    );
}

test "ProjectionOperatorMap: clone"
{
    const allocator = std.testing.allocator;
    const cl = schema.Clip{};
    const cl_ptr = ComposedValueRef{ 
        .clip_ptr = &cl 
    };
    const aff1 = try topology_m.Topology.init_affine(
        allocator,
        .{
            .input_bounds_val = .{
                .start = 0,
                .end = 8,
            },
            .input_to_output_xform = .{
                .offset = 1,
            },
        },
    );
    const child_op_map = (
        try ProjectionOperatorMap.init_operator(
            std.testing.allocator,
            .{
                .source = try cl_ptr.space(.presentation),
                .destination = try cl_ptr.space(.media),
                .src_to_dst_topo = aff1,
            },
        )
    );

    const clone = try child_op_map.clone();
    defer clone.deinit();

    child_op_map.deinit();

    const topo = clone.operators[0][0].src_to_dst_topo;

    try std.testing.expectEqual(
        4,
        try topo.project_instantaneous_cc(3).ordinate()
    );
}

