//! Reference Container Objects
//!
//! `ComposedValueRef`: Points at an object in an OTIO composition.
//! `SpaceReference`: References a temporal space on a particular object in an
//!                   OTIO composition.
//! `SpaceLabel`: Name of spaces on otio object.

const std = @import("std");
const build_options = @import("build_options");

const opentime = @import("opentime");
const topology_m = @import("topology");
const treecode = @import("treecode");
const sampling = @import("sampling");

const schema = @import("schema.zig");
const projection = @import("projection.zig");

const GRAPH_CONSTRUCTION_TRACE_MESSAGES = (
    build_options.debug_graph_construction_trace_messages
);

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
    child_index: ?projection.ProjectionTopology.NodeIndex = null,

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
        var result: std.ArrayList(SpaceReference) = .empty;
        defer result.deinit(allocator);

        try result.ensureTotalCapacity(allocator, 2);

        switch (self) {
            .clip, => {
                result.appendAssumeCapacity(
                    .{
                        .ref = self,
                        .label = SpaceLabel.presentation,
                    },
                );
                result.appendAssumeCapacity(
                    .{
                        .ref = self,
                        .label = SpaceLabel.media,
                    },
                );
            },
            .track, .timeline, .stack => {
                result.appendAssumeCapacity(
                    .{
                        .ref = self,
                        .label = SpaceLabel.presentation,
                    },
                );
                result.appendAssumeCapacity(
                    .{
                        .ref = self,
                        .label = SpaceLabel.intrinsic,
                    },
                );
            },
            .gap, .warp => {
                result.appendAssumeCapacity(
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
        var children_ptrs: std.ArrayList(ComposedValueRef) = .empty;
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
