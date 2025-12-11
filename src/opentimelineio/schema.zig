//! # Schema Library
//!
//! Data types that encode the structure of an editorial document in a temporal
//! hierarchy.
//!
//! Objects typically have an optional `maybe_name` parameter and functions
//! that allow querying their temporal state.  Generally they refer to other
//! objects through the `references.CompositionItemHandle`.
//!
//! Deviates from OpenTimelineIO in order to present a rigorous temporal
//! hierarchy.
//!
//! Schema Iteration Notes
//! ----------------------
//!
//! To start with embededd spaces are explicit and fixed
//! * On everything but Clips, the spaces for parameters and bounds and so on
//!   is the presentation space
//! * On Clips the embedding space is the media space
//! * Clips need to have room for multiple media references
//! * Serialized bounds can be discrete or continuous - in-memory bounds are
//!   strictly continuous, but can be set either discrete or continuous
//! * Sequences have a singular domain.  This eliminates fuzzyness like things
//!   that don't have the domain are gaps, etc.  (hopefully)
//! * Stacks (eventually) probably want a compositing rule per domain, but for
//!   now lets not worry about that
//! * Discrete info is currently only present on the top level timeline and on
//!   root clips (is there a better name than "Discrete Info"?
//!   "DiscreteParameterization"?  The sampling library calls this a
//!   `SampleIndexGenerator`.  Maybe thats better?


const std = @import("std");

const opentime = @import("opentime");
const sampling = @import("sampling");
const string = @import("string_stuff");
const topology_m = @import("topology");
const curve = @import("curve");
const domain = @import("domain.zig");

const references = @import("references.zig");
const test_data = @import("test_structures.zig");


/// Indicates whether samples should be interpolated when the parameter space
/// (usually time) is warped.  Examples include audio (interpolated) vs picture
/// (snapped, typically)
const ResamplingBehavior = enum {
    interpolate,
    snap,
    default_from_domain,
};

/// A reference described by a URI that is interpreted by clients in some way.
pub const URIReference = struct {
    /// URI encoded in a string for locating the data for referenced media.
    target_uri : []const u8,
};

/// A procedurally described Signal.
pub const SignalReference = struct {
    /// Parameters for synthesizing a signal for this media.
    signal_generator: sampling.SignalGenerator,
};

/// Data that assists consumers of this library in finding the data for
/// referenced media.
pub const MediaDataReference = union(enum) {
    /// Usually a file or URI somewhere
    uri: URIReference,

    /// A Procedurally defined signal (A tone, a color, etc.)
    signal: SignalReference,

    /// No data to reference this media.
    null: void,
};

/// Refers to a piece of media or signal that is being cut into a composition.
///
/// Contains information about the media including bounds, discrete space
/// partition and domain.
pub const MediaReference = struct {
    /// Data used to find the media.
    data_reference: MediaDataReference,

    /// bounds of the media space continuous time, the interval of media time
    /// in which the media is defined.
    maybe_bounds_s: ?opentime.ContinuousInterval,

    /// Media domain for this reference.
    domain: domain.Domain,

    /// The discrete space partitioning for the media (if it is discrete and
    /// known).  Required to do a discrete projection into sample index space.
    maybe_discrete_partition: ?sampling.SampleIndexGenerator = null,

    /// Media that is interpolating can be resampled when under time warps.
    interpolating: ResamplingBehavior = .default_from_domain,

    /// Default Media Reference that is empty and specifies picture domain.
    ///
    /// Intended for unit testing.
    pub const null_picture: MediaReference = .{
        .data_reference = .null,
        .maybe_bounds_s = null,
        .domain = .picture,
    };
};

/// Clip places a media reference in a track.
///
/// Has a name and an  optional media space bound that can be imposed, intended
/// to make it easier to swap out references.
pub const Clip = struct {
    /// Optional name, for labelling and human readability.
    maybe_name: ?string.latin_s8 = null,

    /// A trim on the media space, in the media coordinate system.
    maybe_bounds_s: ?opentime.ContinuousInterval = null,

    /// Information about the media this clip cuts into the track.
    media: MediaReference,

    /// Clips provide a `media` space in addition to the `presentation` space.
    ///
    /// The media space is defined by the media reference.
    pub const internal_spaces: []const references.TemporalSpace = &.{
        .presentation,
        .media,
    };

    /// An empty clip with an infinite continuous picture media reference.
    pub const null_picture: Clip = .{
        .media = .null_picture,
    };

    /// Compute the bounds of `target_space` on this clip.
    pub fn bounds_of(
        self: @This(),
        target_space: references.TemporalSpace,
    ) !opentime.ContinuousInterval 
    {
        const maybe_bounds_s = (
            self.maybe_bounds_s orelse self.media.maybe_bounds_s
        );

        if (maybe_bounds_s)
            |bounds|
        {
            // @TODO: the bounds of the presentation space should be 0->duration
            return switch (target_space) {
                .presentation, .media => bounds,
                else => error.UnsupportedSpaceError,
            };
        }

        return error.NotImplementedFetchTopology;
    }

    /// Build a topology that maps from the presentation space to the media
    /// space of the clip.  Resulting memory is owned by the caller.
    pub fn topology(
        self: @This(),
        allocator: std.mem.Allocator,
    ) !topology_m.Topology 
    {
        const media_bounds = (
            self.maybe_bounds_s 
            orelse self.media.maybe_bounds_s 
            orelse return error.NotImplementedFetchTopology
        );

        const presentation_to_media_xform = (
            opentime.AffineTransform1D{
                .offset = media_bounds.start,
                .scale = opentime.Ordinate.one,
            }
        );

        const presentation_bounds = (
            opentime.ContinuousInterval{
                .start = opentime.Ordinate.zero,
                .end = media_bounds.duration()
            }
        );

        const presentation_to_media_topo = (
            try topology_m.Topology.init_affine(
                allocator,
                topology_m.MappingAffine {
                    .input_to_output_xform = presentation_to_media_xform,
                    .input_bounds_val = presentation_bounds,
                },
            )
        );

        return presentation_to_media_topo;
    }

    /// Free memory owned by the Clip.
    pub fn destroy(
        self: *@This(),
        allocator: std.mem.Allocator,
    ) void
    {
        if (self.maybe_name)
            |n|
        {
            allocator.free(n);
        }
    }

    /// Build a reference to this Clip.
    pub fn reference(
        self: *@This(),
    ) references.CompositionItemHandle
    {
        return .{ .clip = self };
    }
};

test "Clip: spaces list" 
{
    var cl: Clip = .null_picture;

    try std.testing.expectEqualSlices(
        references.TemporalSpace,
        &.{ .presentation, .media },
        cl.reference().spaces()
    );
}


/// A duration of the temporal space for which no media is mapped.  
///
/// Silent, Transparent.  Regions of the timeline for which there are no media
/// mapped, ie only gaps are undefined as far as pixels/audio is concerned.
pub const Gap = struct {
    /// Optional name, for labelling and human readability.
    maybe_name: ?string.latin_s8 = null,

    /// A Gaps coordinate system is always 0->duration_seconds
    duration_s: opentime.Ordinate,

    /// The internal temporal coordinate systems of the Gap.
    pub const internal_spaces: []const references.TemporalSpace = (
        &.{ .presentation, .intrinsic }
    );

    /// A Gap's topology is always an identity bounded by the duration of the
    /// gap.
    pub fn topology(
        self: @This(),
        allocator: std.mem.Allocator,
    ) !topology_m.Topology 
    {
        const result = try topology_m.Topology.init_identity(
            allocator,
            .{
                .start = opentime.Ordinate.zero,
                .end = self.duration_s 
            },
        );
        return result;
    }
};

/// A Transition between different objects held within the `container` stack.
///
/// The objects are listed in the stack in their transition order, IE a wipe
/// that goes from A to B will have container [A, B].
pub const Transition = struct {
    /// Objects to include in the transition.  Listed in their transition
    /// order.
    container: Stack,

    /// Optional name, for labelling and human readability.
    maybe_name: ?string.latin_s8,

    /// The "kind" of the transition to use.  IE "wipe" "dissolve" etc.
    kind: string.latin_s8,

    /// Optional bound of the presentation space of the Transition.
    maybe_bounds_s: ?opentime.ContinuousInterval,

    /// The internal temporal coordinate systems of the Timeline.
    pub const internal_spaces: []const references.TemporalSpace = (
        &.{ .presentation }
    );

    /// Build a reference to this Transition.
    pub fn reference(
        self: *@This(),
    ) references.CompositionItemHandle
    {
        return .{ .transition = self };
    }

    /// The topology of the Transition is just the topology of the container.
    pub fn topology(
        self: @This(),
        allocator: std.mem.Allocator,
    ) !topology_m.Topology
    {
        return self.container.topology(allocator);
    }

    /// Clear the memory of self and any child objects.
    pub fn recursively_deinit(
        self: *@This(),
        allocator: std.mem.Allocator,
    ) void 
    {
        self.container.recursively_deinit(allocator);
        if (self.maybe_name)
            |n|
        {
            allocator.free(n);
            self.maybe_name = null;
        }
        allocator.free(self.kind);
    }
};

/// An explicit temporal transformation from the parent space of the warp to
/// the child space of the warp.
pub const Warp = struct {
    /// Optional name, for labelling and human readability.
    maybe_name: ?string.latin_s8 = null,

    /// The child object of the warp.  Effectively warping the presentation
    /// space of the child.
    child: references.CompositionItemHandle,

    /// The Transformation (topology) to use to warp the child space.
    transform: topology_m.Topology,

    /// The internal temporal coordinate systems of the Warp.
    pub const internal_spaces: []const references.TemporalSpace = (
        &.{ .presentation }
    );

    /// Build a reference to this Warp.
    pub fn reference(
        self: *@This(),
    ) references.CompositionItemHandle
    {
        return .{ .warp = self };
    }

    /// Presentation space of warp -> presentation space of child
    pub fn topology(
        self: @This(),
        allocator: std.mem.Allocator,
    ) !topology_m.Topology
    {
        const child_bounds = try self.child.bounds_of(
            allocator,
            .presentation,
        );

        const child_bounds_topo = try topology_m.Topology.init_affine(
            allocator,
            .{
                .input_bounds_val = .{
                    .start = .zero,
                    .end = child_bounds.duration(),
                },
                .input_to_output_xform = .{
                    .offset = child_bounds.start,
                    .scale = .one,
                },
            },
        );
        defer child_bounds_topo.deinit(allocator);

        const warped_to_child = try topology_m.join(
            allocator,
            .{
                .a2b = self.transform,
                .b2c = child_bounds_topo,
            }
        );
        defer warped_to_child.deinit(allocator);

        const warped_range = (
            warped_to_child.input_bounds()
            orelse return .empty
        );

        const presentation_to_warped = try topology_m.Topology.init_affine(
            allocator,
            .{ 
                .input_bounds_val = .{
                    .start = .zero,
                    .end = warped_range.duration(),
                },
                .input_to_output_xform = .{
                    .offset = warped_range.start,
                    .scale = .one,
                },
            }
        );
        defer presentation_to_warped.deinit(allocator);

        return topology_m.join(
            allocator,
            .{
                .a2b = presentation_to_warped,
                .b2c = warped_to_child,
            },
        );
    }
};

/// a container in which each contained item is right-met over time
pub const Track = struct {
    /// Optional name, for labelling and human readability.
    maybe_name: ?string.latin_s8 = null,

    /// Child objects of the track, listed from first to last in temporal
    /// order. A sequence of right met segments.
    children: []references.CompositionItemHandle,

    /// The internal temporal coordinate systems of the Track.
    pub const internal_spaces: []const references.TemporalSpace = (
        &.{ .presentation, .intrinsic }
    );

    /// An empty track.
    pub const empty = Track{
        .maybe_name = null,
        .children = &.{},
    };

    /// Clear the memory of self and any child objects.
    pub fn recursively_deinit(
        self: *@This(),
        allocator: std.mem.Allocator,
    ) void 
    {
        for (self.children)
            |*c|
        {
            c.recursively_deinit(allocator);
        }

        self.deinit(allocator);
    }

    /// Clear the memory of this object but not of children.
    pub fn deinit(
        self: *@This(),
        allocator: std.mem.Allocator,
    ) void 
    {
        if (self.maybe_name)
            |n|
        {
            allocator.free(n);
            self.maybe_name = null;
        }
        allocator.free(self.children);
    }

    /// construct the topology mapping the output to the intrinsic space
    pub fn topology(
        self: @This(),
        allocator: std.mem.Allocator,
    ) !topology_m.Topology 
    {
        // build the maybe_bounds
        var maybe_bounds: ?opentime.ContinuousInterval = null;
        for (self.children) 
            |it| 
        {
            const topo = try it.topology(allocator);
            defer topo.deinit(allocator);
            const it_bound = (
                topo.input_bounds()
                orelse return error.InvalidChildTopology
            );
            if (maybe_bounds) 
                |b| 
            {
                maybe_bounds = opentime.interval.extend(b, it_bound);
            } else {
                maybe_bounds = it_bound;
            }
        }

        // unpack the optional
        const result_bound:opentime.ContinuousInterval = (
            maybe_bounds 
            orelse return .empty
        );

        return try topology_m.Topology.init_identity(
            allocator,
            result_bound,
        );
    }

    /// builds a transform from the previous child spce to the one passed in the
    /// child_space_reference
    ///
    /// because graphs are constructed:
    ///         track
    ///           |
    ///           track_child 0
    ///           |     \
    /// child 0.presentation   track_child 1
    ///                   |   \
    ///       child.1.presentation   track_child 2
    ///                         ...
    ///
    ///  if called on child space child 1, will make a transform to child
    ///  space 1 from child space 0
    /// 
    pub fn transform_to_next_child(
        self: @This(),
        allocator: std.mem.Allocator,
        current_child_index: usize,
    ) !topology_m.Topology 
    {
        // offset the next child by the duration of the previous child
        // presentation space (everything has a presentation space)
        const current_child_pres_range = (
            try self.children[current_child_index].bounds_of(
                allocator,
                .presentation,
            )
        );

        std.debug.assert(current_child_pres_range.is_infinite() == false);
        const current_child_duration = (
            current_child_pres_range.duration()
        );

        // the transform to the next child space, compensates for this duration
        return try topology_m.Topology.init_affine(
            allocator,
            .{
                .input_bounds_val = .{
                    .start = current_child_duration,
                    .end = opentime.Ordinate.inf,
                },
                .input_to_output_xform = .{
                    .offset = current_child_duration.neg(),
                    .scale = opentime.Ordinate.one,
                }
            }
        );
    }

    /// Build a reference to this Track.
    pub fn reference(
        self: *@This(),
    ) references.CompositionItemHandle
    {
        return .{ .track = self };
    }
};

/// children of a stack are simultaneous in time
pub const Stack = struct {
    /// Optional name, for labelling and human readability.
    maybe_name: ?string.latin_s8 = null,

    /// Child objects of the Stack (for example, tracks).  Children are listed
    /// in compositing order, with later children coming "above" earlier
    /// entries.
    children: []references.CompositionItemHandle,

    /// The internal temporal coordinate systems of the Track.
    pub const internal_spaces: []const references.TemporalSpace = (
        &.{ .presentation, .intrinsic }
    );

    pub const empty: Stack = .{
        .maybe_name = null,
        .children = &.{},
    };

    /// Clear the memory of this object but not of children.
    pub fn deinit(
        self: *@This(),
        allocator: std.mem.Allocator,
    ) void 
    {
        if (self.maybe_name)
            |n|
        {
            allocator.free(n);
            self.maybe_name = null;
        }
        allocator.free(self.children);
    }

    /// Clear the memory of self and any child objects.
    pub fn recursively_deinit(
        self: *@This(),
        allocator: std.mem.Allocator,
    ) void 
    {
        for (self.children)
            |*c|
        {
            c.recursively_deinit(allocator);
        }

        self.deinit(allocator);
    }

    /// construct the topology mapping the output to the intrinsic space
    pub fn topology(
        self: @This(),
        allocator: std.mem.Allocator,
    ) !topology_m.Topology 
    {
        // build the bounds
        var bounds: ?opentime.ContinuousInterval = null;
        for (self.children) 
            |it| 
        {
            const it_bound = (
                (try it.topology(allocator)).input_bounds()
                orelse return error.InvalidChildTopology
            );
            if (bounds) 
                |b| 
            {
                bounds = opentime.interval.extend(b, it_bound);
            } else {
                bounds = it_bound;
            }
        }

        if (bounds) 
            |b| 
        {
            return try topology_m.Topology.init_affine(
                allocator,
                .{ 
                    .input_bounds_val = b,
                    .input_to_output_xform = .identity,
                }
            );
        } else {
            return .empty;
        }
    }

    /// Build a reference to this Stack.
    pub fn reference(
        self: *@This(),
    ) references.CompositionItemHandle
    {
        return .{ .stack = self };
    }
};

/// A mapping of domain to a corresponding discrete partition for that domain
pub const DiscretePartitionDomainMap = struct {
    /// Discrete Partition for the "picture" domain.
    picture: ?sampling.SampleIndexGenerator,

    /// Discrete Partition for the "audio" domain.
    audio: ?sampling.SampleIndexGenerator,

    /// Non-picture/audio domain discretizations can be stored here, ie:
    ///   "Gyroscope"
    ///   "Fireworks"
    other: ?std.StringHashMapUnmanaged(sampling.SampleIndexGenerator) = null,

    /// no discrete partitions for any domains
    pub const no_discretizations : DiscretePartitionDomainMap = .{
        .picture = null,
        .audio = null,
        .other = null,
    };
};

/// Root temporal object of a temporal hierarchy.
///
/// Contains a `Stack` called `tracks` which contains the top children of the
/// timeline document.
///
/// Also allows for a discretization of the presentation space for your
/// timeline, IE if it is intended for 24fps picture and 192khz audio, that is
/// configured on the timeline so that regardless of what the discretizations
/// for the various child objects might be, the output is fixed at that
/// description.
pub const Timeline = struct {

    /// Optional name, for labelling and human readability.
    maybe_name: ?string.latin_s8 = null,

    /// Container for children of the Timeline.
    tracks:Stack = .empty,

    /// Discrete space descriptions for the presentation space of the timeline.
    discrete_space_partitions: struct {
        presentation: DiscretePartitionDomainMap = .no_discretizations,
    } = .{},

    /// The internal temporal coordinate systems of the Timeline.
    pub const internal_spaces: []const references.TemporalSpace = &.{
        .presentation,
        .intrinsic,
    };

    /// Clear the memory of self and any child objects.
    pub fn recursively_deinit(
        self: *@This(),
        allocator: std.mem.Allocator,
    ) void 
    {
        if (self.maybe_name)
            |n|
        {
            allocator.free(n);
            self.maybe_name = null;
        }
        self.tracks.recursively_deinit(allocator);
    }

    /// Presentation space of Timeline -> presentation space of `Tracks` stack.
    pub fn topology(
        self: @This(),
        allocator: std.mem.Allocator,
    ) !topology_m.Topology
    {
        return try self.tracks.topology(allocator);
    }

    /// Build a reference to this Timeline.
    pub fn reference(
        self: *@This(),
    ) references.CompositionItemHandle
    {
        return .{ .timeline = self };
    }
};

test "clip topology construction" 
{
    const allocator = std.testing.allocator;

    // setting the bounds on the clip
    {
        var cl = Clip {
            .media = .null_picture,
            .maybe_bounds_s = test_data.T_INT_1_TO_9,
        };

        const topo = try cl.topology(allocator);
        defer topo.deinit(allocator);

        const expected_input_bounds = (
            opentime.ContinuousInterval{
                .start = .zero,
                .end = test_data.T_INT_1_TO_9.duration(),
            }
        );

        try std.testing.expectEqual(
            expected_input_bounds,
            topo.input_bounds(),
        );

        try std.testing.expectEqual(
            test_data.T_INT_1_TO_9,
            topo.output_bounds(),
        );
    }

    // setting the bounds on the media
    {
        var cl = Clip {
            .media = .{
                .data_reference = .null,
                .maybe_bounds_s = test_data.T_INT_1_TO_9,
                .domain = .picture,
                .interpolating = .snap,
            },
        };

        const topo = try cl.topology(allocator);
        defer topo.deinit(allocator);

        const expected_input_bounds = (
            opentime.ContinuousInterval{
                .start = .zero,
                .end = test_data.T_INT_1_TO_9.duration(),
            }
        );

        try std.testing.expectEqual(
            expected_input_bounds,
            topo.input_bounds(),
        );

        try std.testing.expectEqual(
            test_data.T_INT_1_TO_9,
            topo.output_bounds(),
        );
    }
}

test "track topology construction" 
{
    const allocator = std.testing.allocator;

    var cl = Clip {
        .media = .null_picture,
        .maybe_bounds_s = test_data.T_INT_1_TO_9, 
    };

    var tr_children = [_]references.CompositionItemHandle{
        cl.reference()
    };
    var tr: Track = .{
        .children = &tr_children,
    };

    const topo = try tr.topology(allocator);
    defer topo.deinit(allocator);

    const expected_clip_input_bounds = (
        opentime.ContinuousInterval{
            .start = .zero,
            .end = test_data.T_INT_1_TO_9.duration(),
        }
    );

        try std.testing.expectEqual(
            expected_clip_input_bounds,
            topo.input_bounds(),
        );

        try std.testing.expectEqual(
            expected_clip_input_bounds,
            topo.output_bounds(),
        );
}

test "warp topology"
{
    const allocator = std.testing.allocator;

    // setting the bounds on the clip
    {
        var cl = Clip {
            .media = .null_picture,
            .maybe_bounds_s = test_data.T_INT_1_TO_9,
        };

        const xform = opentime.AffineTransform1D {
            .offset = .zero,
            .scale = .{ .v = 2 },
        };

        const wp = Warp {
            .child = cl.reference(),
            .transform = try topology_m.Topology.init_affine(
                allocator, 
                .{
                    .input_to_output_xform = xform,
                    .input_bounds_val = .inf_neg_to_pos,
                },
            ),
        };
        defer wp.transform.deinit(allocator);

        const topo = try wp.topology(allocator);
        defer topo.deinit(allocator);

        const range = opentime.ContinuousInterval {
            .start = .one,
            .end = .{ .v = 5 },
        };

        const expected_input_bounds = (
            opentime.ContinuousInterval{
                .start = .zero,
                .end = range.duration(),
            }
        );

        try std.testing.expectEqual(
            expected_input_bounds,
            topo.input_bounds(),
        );

        try std.testing.expectEqual(
            opentime.ContinuousInterval{
                .start = .zero,
                .end = test_data.T_INT_1_TO_9.duration(),
        },
            topo.output_bounds(),
        );
    }

    // with an offset (no change)
    {
        var cl = Clip {
            .media = .null_picture,
            .maybe_bounds_s = test_data.T_INT_1_TO_9,
        };

        const xform = opentime.AffineTransform1D {
            .offset = .one,
            .scale = .{ .v = 2 },
        };

        const wp = Warp {
            .child = cl.reference(),
            .transform = try topology_m.Topology.init_affine(
                allocator, 
                .{
                    .input_to_output_xform = xform,
                    .input_bounds_val = .inf_neg_to_pos,
                },
            ),
        };
        defer wp.transform.deinit(allocator);

        const topo = try wp.topology(allocator);
        defer topo.deinit(allocator);

        const range = opentime.ContinuousInterval {
            .start = .one,
            .end = .{ .v = 5 },
        };

        const expected_input_bounds = (
            opentime.ContinuousInterval{
                .start = .zero,
                .end = range.duration(),
            }
        );

        try std.testing.expectEqual(
            expected_input_bounds,
            topo.input_bounds(),
        );

        try std.testing.expectEqual(
            opentime.ContinuousInterval{
                .start = .zero,
                .end = test_data.T_INT_1_TO_9.duration(),
        },
            topo.output_bounds(),
        );
    }

    // negative scale
    {
        var cl = Clip {
            .media = .null_picture,
            .maybe_bounds_s = test_data.T_INT_1_TO_9,
        };

        const xform = opentime.AffineTransform1D {
            .offset = .zero,
            .scale = opentime.Ordinate.init(-2),
        };

        const wp = Warp {
            .child = cl.reference(),
            .transform = try topology_m.Topology.init_affine(
                allocator, 
                .{
                    .input_to_output_xform = xform,
                    .input_bounds_val = .inf_neg_to_pos,
                },
            ),
        };
        defer wp.transform.deinit(allocator);

        const wp_pres_to_child = try wp.topology(allocator);
        defer wp_pres_to_child.deinit(allocator);

        const range = opentime.ContinuousInterval {
            .start = .one,
            .end = .{ .v = 5 },
        };

        const expected_input_bounds = (
            opentime.ContinuousInterval{
                .start = .zero,
                .end = range.duration(),
            }
        );

        try std.testing.expectEqual(
            expected_input_bounds,
            wp_pres_to_child.input_bounds(),
        );

        const child_bounds = (
            opentime.ContinuousInterval{
                .start = .zero,
                .end = test_data.T_INT_1_TO_9.duration(),
            }
        );

        try std.testing.expectEqual(
            child_bounds,
            wp_pres_to_child.output_bounds(),
        );

        // project the start and end points to see where they land
        try std.testing.expectEqual(
            child_bounds.end,
            wp_pres_to_child.project_instantaneous_cc(
                expected_input_bounds.start
            ).ordinate(),
        );

        const inverted = try wp_pres_to_child.inverted(
            allocator
        );
        const wp_child_to_pres = inverted[0];
        defer {
            wp_child_to_pres.deinit(allocator);
            allocator.free(inverted);
        }

        try std.testing.expectEqual(
            expected_input_bounds.end,
            wp_child_to_pres.project_instantaneous_cc(
                child_bounds.start
            ).ordinate(),
        );
    }
}
