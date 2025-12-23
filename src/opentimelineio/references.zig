//! Reference Container Objects
//!
//! - `CompositionItemHandle`: Points at an object in an OTIO composition.
//! - `TemporalSpace`: Name of spaces on otio object.
//! - `TemporalSpaceNode`: A `TemporalSpace` on a `CompositionItemHandle`.

const std = @import("std");
const build_options = @import("build_options");

const opentime = @import("opentime");
const topology_m = @import("topology");
const treecode = @import("treecode");
const sampling = @import("sampling");

const domain_mod = @import("domain.zig");
const schema = @import("schema.zig");
const projection = @import("projection.zig");

const string_stuff = @import("string_stuff");

const GRAPH_CONSTRUCTION_TRACE_MESSAGES = (
    build_options.debug_graph_construction_trace_messages
);


/// Scans haystack of enum tags for needle tag.  This is used by this library
/// to determine if a space is in a given list of spaces.
fn is_in_tag_list(
    comptime enum_type: type,
    haystack: []const enum_type,
    needle: std.meta.Tag(enum_type),
) bool
{
    for (haystack) 
        |v| 
    {
        if (v == needle) 
        {
            return true;
        }
    } else return false;
}


/// A Temporal Space on a `CompositionItemHandle`.
pub const TemporalSpace = union (enum) {
    /// The presentation space is the "output" (from a rendering perspective)
    /// space, but the "input (from a projection/functional
    /// composition/mathematical perspective) space of a given object in an
    /// OTIO composition.
    ///
    /// Every object in an `schema` CompositionItemHandle has a `presentation`
    /// space, and it always starts at time 0 and goes for the duration of the
    /// object.
    presentation: void,

    /// The intrinsic space is an internal space that is used by some objects
    /// between the `presentation` and `child` spaces for example.
    intrinsic: void,

    /// The `media` space is present on `schema.Clip` and describes the
    /// coordinate space of a piece of media being cut into the timeline.
    media: void,

    /// The index of the child space in the parent.  IE track.children[i].
    child: treecode.binary_tree.NodeIndex,

    /// Formatter function for `std.Io.Writer`.
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

/// Joins a specific `TemporalSpace` on a specific `CompositionItemHandle`
/// in the composition.
pub const TemporalSpaceNode = struct {
    /// The item in the composition.
    item: CompositionItemHandle,

    /// The specific temporal space on the `item`.
    space: TemporalSpace,

    /// Formatter function for `std.Io.Writer`.
    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) !void 
    {
        try writer.print(
            "{f}.{s}",
            .{
                self.item,
                @tagName(self.space),
            }
        );

        if (self.space == .child)
        {
            try writer.print(
                ".{d}",
                .{ self.space.child },
            );
        }
    }

    /// Return the discrete partition for this space (if it exists).
    pub fn discrete_partition(
        self: @This(),
        /// The domain to query
        domain: domain_mod.Domain,
    ) ?sampling.SampleIndexGenerator
    {
        return self.item.discrete_partition_for_space(
            self.space,
            domain,
        );
    }
};

/// A handle to an item that could be present in a composition.
pub const CompositionItemHandle = union(enum) {
    clip: *schema.Clip,
    gap: *schema.Gap,
    track: *schema.Track,
    timeline: *schema.Timeline,
    stack: *schema.Stack,
    warp: *schema.Warp,
    transition: *schema.Transition,

    /// construct a CompositionItemHandle from a ComposableValue or value type
    pub fn init(
        input: anytype,
    ) CompositionItemHandle
    {
        comptime {
            const ti= @typeInfo(@TypeOf(input));
            if (std.meta.activeTag(ti) != .pointer) 
            {
                @compileError(
                    "CompositionItemHandle can only be constructed from "
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
            schema.Transition => .{ .transition = input },
            inline else => @compileError(
                "CompositionItemHandle cannot reference to type: "
                ++ @typeName(@TypeOf(input))
            ),
        };
    }

    /// Clear the memory of the item this is a handle of and any children.
    pub fn deinit(
        self: *@This(),
        allocator: std.mem.Allocator,
    ) void
    {
        switch (self.*) 
        {
            inline else => |ob| {
                ob.deinit(allocator);
                allocator.destroy(ob);
            },
        }
    }

    /// The (optional) name of the referred item.
    pub fn maybe_name(
        self: @This(),
    ) ?string_stuff.latin_s8
    {
        return switch (self) {
            inline else => |t| t.maybe_name
        };
    }

    /// Fetch the "spanning" topology of the referred item.  The "spanning"
    /// topology is the topology that transforms from the presentation space to
    /// the leaf-most space (for clips, the media space, for everything else,
    /// media space).
    ///
    /// Note that this does not transform into child spaces.
    pub fn spanning_topology(
        self: @This(),
        allocator: std.mem.Allocator,
    ) error{
        NotAnOrdinateResult,
        NoOverlap,
        OutOfBounds,
        OutOfMemory,
        NotImplementedFetchTopology,
        UnsupportedSpaceError,
        InvalidChildTopology,
        InvalidTransformationNoBounds,
        InvalidMapping,
    }!topology_m.Topology 
    {
        return  switch (self) {
            .clip => |cl| try cl.topology_pres_to_media(allocator),
            inline else => |thing| try thing.topology_pres_to_intrinsic(allocator),
        };
    }

    /// Compute the bounds of space `target_space` on the referred item.
    pub fn bounds_of(
        self: @This(),
        allocator: std.mem.Allocator,
        target_space: TemporalSpace,
    ) !opentime.ContinuousInterval 
    {
        const presentation_to_intrinsic_topo = (
            try self.spanning_topology(allocator)
        );
        defer presentation_to_intrinsic_topo.deinit(allocator);

        std.debug.assert(self.has_available_local_space(target_space));

        return switch (target_space) {
            .media, .intrinsic => (
                presentation_to_intrinsic_topo.output_bounds()
                orelse return error.InvalidTransformationNoBounds
            ),
            .presentation => (
                presentation_to_intrinsic_topo.input_bounds()
                orelse return error.InvalidTransformationNoBounds
            ),
            else => error.UnsupportedSpaceError,
        };
    }

    /// Fetches the `available_local_spaces` field of the referenced item.  See
    /// `schema.Clip.available_local_spaces` for example.  
    ///
    /// Note that this memory is static and does not need to be freed.
    pub fn available_local_spaces(
        self: @This(),
    ) []const TemporalSpace 
    {
        return switch (self) {
            inline else => |thing| @TypeOf(thing.*).available_local_spaces,
        };
    }

    /// Return true if `target_space` is in self.spaces()
    pub fn has_available_local_space(
        self: @This(),
        target_space: std.meta.Tag(TemporalSpace),
    ) bool
    {
        return is_in_tag_list(
            TemporalSpace,
            self.available_local_spaces(),
            target_space,
        );
    }

    /// Build a TemporalSpaceReference from a space on the referred item.
    pub fn space_node(
        self: @This(),
        /// Target space
        target_space: TemporalSpace
    ) TemporalSpaceNode 
    {
        std.debug.assert(self.has_available_local_space(target_space));

        return .{
            .item = self,
            .space = target_space,
        };
    }

    /// Build the next topology that transforms `from_space_label` on `self`
    /// towards `to_space`.
    ///
    /// Returnend memory is owned by the caller.
    pub fn transform_step_toward(
        self: @This(),
        allocator: std.mem.Allocator,
        /// Label of the starting space on the referred item.
        from_space_label: TemporalSpace,
        to_space: TemporalSpaceNode,
        /// Step taken from previous node.
        step: treecode.l_or_r,
    ) !topology_m.Topology 
    {
        if (GRAPH_CONSTRUCTION_TRACE_MESSAGES) 
        {
            std.debug.print(
                "[{s}:{s}:{d}]    transform from space: {s}.{s}"
                ++ " to space: {s}.{s}",
                .{
                    @src().file, 
                    @src().fn_name, 
                    @src().line, 
                    @tagName(self),
                    @tagName(from_space_label),
                    @tagName(to_space.item),
                    @tagName(to_space.space),
                },
            );

            if (to_space.space == .child)
            {
                std.debug.print(
                    ".child.{d}",
                    .{to_space.space.child}
                );
            }
            std.debug.print("\n", .{});
        }

        return switch (self) 
        {
            .track => |*tr| {
                switch (from_space_label) 
                {
                    // presentation -> intrinsic
                    .presentation => return .identity_infinite,
                    // intrinsic -> first child space
                    .intrinsic => return .identity_infinite,
                    // child space to either the presentation space of that
                    // child (left step)  or to the next child
                    .child => |child_index| {
                        if (GRAPH_CONSTRUCTION_TRACE_MESSAGES) 
                        {
                            opentime.dbg_print(
                                @src(),
                                "     CHILD STEP: {b} to index: {d}\n",
                                .{ step, child_index }
                            );
                        }

                        // from this child space down into the presentation
                        // space of the child (identity)
                        if (step == .left) 
                        {
                            return .identity_infinite;
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
                            try cl.*.bounds_of(.media)
                        );
                        const intrinsic_to_media_xform = (
                            opentime.AffineTransform1D{
                                .offset = media_bounds.start,
                                .scale = .one,
                            }
                        );
                        const intrinsic_bounds = (
                            opentime.ContinuousInterval{
                                .start = .zero,
                                .end = media_bounds.duration(),
                            }
                        );

                        const intrinsic_to_media_mapping = (
                            topology_m.MappingAffine {
                                .input_to_output_xform = intrinsic_to_media_xform,
                                .input_bounds_val = intrinsic_bounds,
                            }
                        );

                        const intrinsic_to_media_topo = (
                            // allocating memory here to make sure that the
                            // mapping slice leaves the function scope
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
                    else => {
                        // the only further transfomartion from media space is 
                        // to bound (should have already been bounded in the 
                        // presentation->media transformation)
                        const result = (
                            try topology_m.Topology.init_identity(
                                allocator,
                                try cl.*.bounds_of(.media,)
                            )
                        );

                        return result;
                    }
                };
            },
            .warp => |wp_ptr| switch(from_space_label) 
            {
                .presentation => {
                    const intrinsic_to_warp_unbounded = wp_ptr.transform;

                    std.debug.assert(
                        (
                         wp_ptr.transform.input_bounds() 
                         orelse return error.InvalidBounds
                        ).is_instant() == false
                    );

                    const child_bounds = (
                        try wp_ptr.child.bounds_of(
                            allocator,
                            .presentation,
                        )
                    );

                    // needs the boundaries from the child
                    const warp_unbounded_to_child = (
                        try topology_m.Topology.init_identity(
                            allocator, 
                            child_bounds,
                        )
                    );

                    const intrinsic_to_child = try topology_m.join(
                        allocator,
                        .{
                            .a2b = intrinsic_to_warp_unbounded,
                            .b2c = warp_unbounded_to_child,
                        }
                    );

                    std.debug.assert(
                        (
                         intrinsic_to_child.input_bounds()
                         orelse return error.InvalidBounds
                        ).is_instant() == false
                    );

                    const intrinsic_bounds = (
                        intrinsic_to_child.input_bounds()
                        orelse return error.InvalidBounds
                    );

                    const presentation_to_intrinsic = (
                        try topology_m.Topology.init_affine(
                            allocator,
                            .{
                                .input_to_output_xform = .{
                                    .offset = intrinsic_bounds.start,
                                    .scale = .one,
                                },
                                .input_bounds_val = .inf_neg_to_pos,
                            },
                        )
                    );

                    const result = try topology_m.join(
                        allocator,
                        .{
                            .a2b = presentation_to_intrinsic,
                            .b2c = intrinsic_to_child,
                        }
                    );

                    std.debug.assert(
                        (
                         result.input_bounds()
                         orelse return error.InvalidBounds
                        ).is_instant() == false
                    );

                    return result;
                },
                else => .identity_infinite,
            },
            .gap => |gap_ptr| switch (from_space_label) 
            {
                .presentation => gap_ptr.topology_pres_to_intrinsic(allocator),
                else => .identity_infinite,
            },
            // wrapped as identity
            .timeline, .stack, .transition => .identity_infinite,
            // else => |case| { 
            //     std.log.err("Not Implemented: {any}\n", .{ case });
            //
            //     // return error.NotImplemented;
            //     return topology_m.Topology.init_identity_infinite();
            // },
        };
    }

    /// If the referred item has a discrete_partition, transform the discrete
    /// index into a continuous interval in the target `in_space`.
    pub fn discrete_index_to_continuous_range(
        self: @This(),
        ind_discrete: sampling.sample_index_t,
        in_space: TemporalSpace,
        domain: domain_mod.Domain,
    ) !opentime.ContinuousInterval
    {
        const maybe_di = (
            self.discrete_partition_for_space(in_space, domain)
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

    /// Transform the continuous ordinate to a discrete ordinate `in_space`.,
    /// if that space has a discrete space partition.
    pub fn continuous_ordinate_to_discrete_index(
        self: @This(),
        ord_continuous: opentime.Ordinate,
        in_space: TemporalSpace,
        domain: domain_mod.Domain,
    ) !sampling.sample_index_t
    {
        const maybe_di = (
            self.discrete_partition_for_space(in_space, domain)
        );

        if (maybe_di) 
            |di|
        {
            return sampling.project_instantaneous_cd(
                di,
                ord_continuous
            );
        }

        // @TODO: should this be an error?  or a null (no projection).

        return error.NoDiscreteInfoForSpace;
    }
   
    /// Continuous to discrete transformation for the given space on the
    /// referred item.
    ///
    /// EG: given in_space .presentation, builds the continuous-to-discrete
    /// topology for transforming from the continuous presentation space to the
    /// discrete presentation space.  This would, for example,give the sample
    /// indices for ordinates and intervals in this space.
    pub fn continuous_to_discrete_topology(
        self: @This(),
        allocator: std.mem.Allocator,
        in_space: TemporalSpace,
    ) !topology_m.Topology
    {
        const maybe_discrete_info = (
            try self.discrete_partition_for_space(in_space)
        );
        if (maybe_discrete_info == null)
        {
            return error.SpaceOnObjectHasNoDiscreteSpecification;
        }

        const discrete_info = maybe_discrete_info.?;

        const target_topo = try self.spanning_topology(allocator);
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

    /// Return the discrete partition for the specified space label on the
    /// referred item in the specified domain.  Return null if no discrete
    /// partition exists.
    pub fn discrete_partition_for_space(
        self: @This(),
        in_space: TemporalSpace,
        domain: domain_mod.Domain,
    ) ?sampling.SampleIndexGenerator
    {
        return switch (self) {
            .timeline => |tl| switch (in_space) {
                .presentation => switch (domain) {
                    .picture => tl.discrete_space_partitions.presentation.picture,
                    .audio => tl.discrete_space_partitions.presentation.audio,
                    inline else => null,
                },
                inline else => null,
            },
            .clip => |cl| switch (in_space) {
                .media => if (
                    std.meta.activeTag(domain) 
                    == std.meta.activeTag(cl.media.domain)
                ) cl.media.maybe_discrete_partition else null,
                inline else => null,
            },
            inline else => null,
        };
    }

    /// Formatter for `std.Io.Writer`.
    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) !void 
    {
        try writer.print(
            "{s}.{s}",
            .{
                self.maybe_name() orelse "null",
                @tagName(self),
            }
        );
    }

    /// return a caller-owned slice of the children of this composed value ref
    pub fn children_refs(
        self: @This(),
        allocator: std.mem.Allocator,
    ) ![]CompositionItemHandle
    {
        var children_ptrs: std.ArrayList(CompositionItemHandle) = .empty;
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
                CompositionItemHandle.init(&tl.tracks)
            ),
            .transition => |tl| try children_ptrs.append(
                allocator,
                CompositionItemHandle.init(&tl.container)
            ),
            .warp => |wp| {
                try children_ptrs.append(allocator,wp.child);
            },
            inline else => {},
        }

        return try children_ptrs.toOwnedSlice(allocator);
    }
};

test "CompositionItemHandle init test"
{
    var clip: schema.Clip = .null_picture;
    clip.maybe_name = "pasta";

    const cvr_clip = CompositionItemHandle.init(&clip);

    try std.testing.expectEqualStrings(
        clip.maybe_name.?,
        cvr_clip.clip.maybe_name.?,
    );
    try std.testing.expectEqual(&clip, cvr_clip.clip);
}

test "is_in_tag_list"
{
    const haystack: []const TemporalSpace = &.{
        .presentation,
        .intrinsic,
    };

    try std.testing.expectEqual(
        true, 
        is_in_tag_list(
            TemporalSpace,
            haystack,
            .presentation,
        )
    );

    try std.testing.expectEqual(
        false, 
        is_in_tag_list(
            TemporalSpace,
            haystack,
            .media,
        )
    );
}

test "CompositionItemHandle: has_space"
{
    var cl = schema.Clip.null_picture;
    const cl_h = cl.handle();

    try std.testing.expectEqual(
        true, 
        cl_h.has_available_local_space(.media),
    );

    try std.testing.expectEqual(
        false, 
        cl_h.has_available_local_space(.intrinsic),
    );
}
