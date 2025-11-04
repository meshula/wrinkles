//! Reference Container Objects
//!
//! - `ComposedValueRef`: Points at an object in an OTIO composition.
//! - `SpaceReference`: References a temporal space on a particular object in
//!                     an OTIO composition.
//! - `SpaceLabel`: Name of spaces on otio object.

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
pub const SpaceLabel = union (enum) {
    // internal spaces
    presentation: void,
    intrinsic: void,
    media: void,

    // The NodeIndex of the child in the Space Map
    child: treecode.binary_tree.NodeIndex,

    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) !void 
    {
        try switch (self) {
            .child => |ind| (
                writer.print("child.{d}",.{ind})
            ),
            else => |s| (
                writer.print("{s}",.{ @tagName(s)})
            ),
        };
    }
};

/// references a specific space on a specific object
pub const SpaceReference = struct {
    ref: ComposedValueRef,
    label: SpaceLabel,

    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) !void 
    {
        try writer.print(
            "{f}.{s}",
            .{
                self.ref,
                @tagName(self.label),
            }
        );

        if (self.label == .child)
        {
            try writer.print(
                ".{d}",
                .{ self.label.child },
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

    /// Fetches the `internal_spaces` field of the referenced object.  See
    /// `schema.Clip.internal_spaces` for example.  
    ///
    /// Note that this memory is static and does not need to be freed.
    pub fn spaces(
        self: @This(),
    ) []const SpaceLabel 
    {
        return switch (self) {
            inline else => |thing| @TypeOf(thing.*).internal_spaces,
        };
    }

    /// build a space reference to the specified space on this CV
    pub fn space(
        self: @This(),
        label: SpaceLabel
    ) SpaceReference 
    {
        return .{ .ref = self, .label = label };
    }

    /// build a topology that projections a value from_space to_space
    /// @TODO clarify that this function is used to take one step along the
    /// path and not do all the steps - need to use other functions for that.
    pub fn build_transform(
        self: @This(),
        allocator: std.mem.Allocator,
        from_space_label: SpaceLabel,
        to_space: SpaceReference,
        step: treecode.l_or_r,
    ) !topology_m.Topology 
    {
        if (GRAPH_CONSTRUCTION_TRACE_MESSAGES) {
            std.debug.print(
                "[{s}:{s}:{d}]    transform from space: {s}.{s} to space: {s}.{s}",
                .{
                    @src().file, 
                    @src().fn_name, 
                    @src().line, 
                    @tagName(self),
                    @tagName(from_space_label),
                    @tagName(to_space.ref),
                    @tagName(to_space.label),
                },
            );

            if (to_space.label == .child)
            {
                std.debug.print(
                    ".child.{d}",
                    .{to_space.label.child}
                );
            }
            std.debug.print("\n", .{});
        }

        return switch (self) {
            .track => |*tr| {
                switch (from_space_label) {
                    // presentation -> intrinsic
                    .presentation => return .INFINITE_IDENTITY,
                    // intrinsic -> first child space
                    .intrinsic => return .INFINITE_IDENTITY,
                    // child space to either the presentation space of that
                    // child (left step)  or to the next child
                    .child => |child_index| {
                        if (GRAPH_CONSTRUCTION_TRACE_MESSAGES) {
                            opentime.dbg_print(
                                @src(),
                                "     CHILD STEP: {b} to index: {d}\n",
                                .{ step, child_index }
                            );
                        }

                        // from this child space down into the presentation
                        // space of the child (identity)
                        if (step == .left) {
                            return .INFINITE_IDENTITY;
                        } 
                        else 
                        {
                            // from this child space to the next child space
                            // - account for the offset from previous child
                            // spaces
                            return try tr.*.transform_to_next_child(
                                allocator,
                                // the next child space is the current one + 1
                                child_index,
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

                return switch (from_space_label) {
                    .presentation => {
                        // goes to media

                        // implied, but inf identity
                        // const pres_to_intrinsic_topo:topology_m.Topology = (
                        //     .INFINITE_IDENTITY
                        // );

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

                        const intrinsic_to_media_mapping = (
                            topology_m.MappingAffine {
                                .input_to_output_xform = intrinsic_to_media_xform,
                                .input_bounds_val = intrinsic_bounds,
                            }
                        );

                        const intrinsic_to_media_topo = (
                            try topology_m.Topology.init_affine(
                                allocator,
                                intrinsic_to_media_mapping,
                            )
                        );

                        // implied
                        // const pres_to_media = try topology_m.join(
                        //     allocator,
                        //     .{ 
                        //         .a2b = pres_to_intrinsic_topo,
                        //         .b2c = intrinsic_to_media,
                        //     },
                        // );
                        // return pres_to_media;

                        const pres_to_media = intrinsic_to_media_topo;

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
            .warp => |wp_ptr| switch(from_space_label) {
                .presentation => wp_ptr.transform,
                else => .INFINITE_IDENTITY,
            },
            .gap => |gap_ptr| switch (from_space_label) {
                .presentation => gap_ptr.topology(allocator),
                else => .INFINITE_IDENTITY,
            },
            // wrapped as identity
            .timeline, .stack => .INFINITE_IDENTITY,
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
            self.discrete_info_for_space(in_space)
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
            self.discrete_info_for_space(in_space)
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
   
    /// Continuous to discrete transformation for the given space on the
    /// referred object .
    ///
    /// EG: given in_space .presentation, builds the continuous-to-discrete
    /// topology for transforming from the continuous presentation space to the
    /// discrete presentation space.  This would, for example,give the sample
    /// indices for ordinates and intervals in this space.
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
    ) ?sampling.SampleIndexGenerator
    {
        return switch (self) {
            .timeline => |tl| switch (in_space) {
                .presentation => tl.discrete_info.presentation,
                inline else => null,
            },
            .clip => |cl| switch (in_space) {
                .media => cl.media.discrete_info,
                inline else => null,
            },
            inline else => null,
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
