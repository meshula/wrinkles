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
const string_stuff = @import("string_stuff");

pub const references = @import("references.zig");
const test_data = @import("test_structures.zig");
pub const marker = @import("marker.zig");
pub const Marker = marker.Marker;
pub const MarkerColor = marker.MarkerColor;


/// Indicates whether samples should be interpolated when the parameter space
/// (usually time) is warped.  Examples include audio (interpolated) vs picture
/// (snapped, typically)
pub const ResamplingBehavior = enum {
    interpolate,
    snap,
    default_from_domain,
};

/// Policy for handling missing frames in an image sequence.
pub const MissingFramePolicy = enum {
    @"error",  // Raise error (quoted because 'error' is Zig keyword)
    hold,      // Hold last frame
    black,     // Show black/transparent
    
    pub fn from_maybe_string(
        maybe_str: ?[]const u8,
    ) MissingFramePolicy
    {
        return (
            if (maybe_str)
            |str|
            std.meta.stringToEnum(
                MissingFramePolicy,
                str
            ) orelse .@"error"
            else .@"error" 
        );
    }
};

/// A reference described by a URI that is interpreted by clients in some way.
pub const URIReference = struct {
    /// URI encoded in a string for locating the data for referenced media.
    target_uri : string_stuff.latin_s8,
};

/// A procedurally described Signal.
pub const SignalReference = struct {
    /// Parameters for synthesizing a signal for this media.
    signal_generator: sampling.SignalGenerator,
};

/// A reference to an image sequence represented by a URL pattern with frame
/// numbering.
pub const ImageSequenceReference = struct {
    /// Base URL or file path before the frame number.
    target_url_base: string_stuff.latin_s8,

    /// Prefix to insert before the frame number (e.g., "frame_").
    name_prefix: string_stuff.latin_s8 = "",

    /// Suffix to insert after the frame number (e.g., ".exr").
    name_suffix: string_stuff.latin_s8 = "",

    /// First frame number in the sequence.
    start_frame: i32 = 1,

    /// Frame increment (e.g., 2 for every other frame).
    frame_step: i32 = 1,

    /// Zero padding width for frame numbers (e.g., 4 for "0001").
    frame_zero_padding: u8 = 0,

    /// Frame rate of the sequence in frames per second.
    rate: f64 = 24.0,

    /// Policy for handling missing frames.
    missing_frame_policy: MissingFramePolicy = .@"error",

    /// Generate the URL for a specific image number in the sequence.
    pub fn target_url_for_image_number(
        self: @This(),
        allocator: std.mem.Allocator,
        image_number: i32,
    ) ![]const u8
    {
        return try std.fmt.allocPrint(
            allocator,
            "{[url]s}{[prefix]s}{[sign]s}{[value]d:0>[width]}{[suffix]s}",
            .{
                .url = self.target_url_base,
                .prefix = self.name_prefix,
                .sign = if (image_number < 0) "-" else "",
                .value = @abs(image_number),
                .width = self.frame_zero_padding,
                .suffix = self.name_suffix,
            },
        );
    }

    /// Get the frame number for a given time ordinate.
    pub fn frame_for_time(
        self: @This(),
        time: opentime.Ordinate,
    ) i32
    {
        const frame_offset = @as(
            i32,
            @intFromFloat(@floor(time.v * self.rate))
        );
        return self.start_frame + (frame_offset * self.frame_step);
    }

    /// Calculate the total number of images in the sequence given an
    /// available range.
    pub fn number_of_images_in_sequence(
        self: @This(),
        available_range: opentime.ContinuousInterval,
    ) i32
    {
        const duration_seconds = available_range.duration().v;
        const total_frames = @as(
            i32,
            @intFromFloat(@ceil(duration_seconds * self.rate))
        );
        return @divFloor(total_frames, self.frame_step);
    }

    /// Get the last frame number in the sequence given an available range.
    pub fn end_frame(
        self: @This(),
        available_range: opentime.ContinuousInterval,
    ) i32
    {
        const num_images = self.number_of_images_in_sequence(
            available_range
        );
        return self.start_frame + ((num_images - 1) * self.frame_step);
    }

    /// Free memory owned by the ImageSequenceReference.
    pub fn deinit(
        self: @This(),
        allocator: std.mem.Allocator,
    ) void
    {
        allocator.free(self.target_url_base);
        allocator.free(self.name_prefix);
        allocator.free(self.name_suffix);
    }
};

/// Data that assists consumers of this library in finding the data for
/// referenced media.
pub const MediaDataReference = union(enum) {
    /// Usually a file or URI somewhere
    uri: URIReference,

    /// A Procedurally defined signal (A tone, a color, etc.)
    signal: SignalReference,

    /// An image sequence with frame numbering
    image_sequence: ImageSequenceReference,

    /// No data to reference this media.
    null: void,

    /// Free memory owned by the MediaDataReference.
    pub fn deinit(
        self: @This(),
        allocator: std.mem.Allocator,
    ) void
    {
        switch (self) {
            .uri => |uri_ref| allocator.free(uri_ref.target_uri),
            .image_sequence => |img_seq| img_seq.deinit(allocator),
            .signal, .null => {},
        }
    }
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

    /// Free memory owned by the MediaReference.
    pub fn deinit(
        self: @This(),
        allocator: std.mem.Allocator,
    ) void
    {
        self.data_reference.deinit(allocator);
        // Free domain.other string if present
        switch (self.domain) {
            .other => |s| allocator.free(s),
            else => {},
        }
    }
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

    /// Optional metadata as raw JSON value (from OTIO JSON parsing).
    /// Will be serialized to ziggy format and stored in Timeline's metadata_map.
    maybe_metadata_json: ?std.json.Value = null,

    /// Markers attached to this clip.
    markers: []Marker = &.{},

    /// Clips provide a `media` space in addition to the `presentation` space.
    ///
    /// The media space is defined by the media reference.
    pub const available_local_spaces: []const references.TemporalSpace = &.{
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
        if (
            self.maybe_bounds_s 
            orelse self.media.maybe_bounds_s
        ) |bounds|
        {
            return switch (target_space) {
                .presentation => .{
                    .start = .zero,
                    .end = bounds.duration(),
                },
                .media => bounds,
                else => error.UnsupportedSpaceError,
            };
        }

        return error.NotImplementedFetchTopology;
    }

    /// Build a topology that maps from the presentation space to the media
    /// space of the clip.  Resulting memory is owned by the caller.
    pub fn topology_pres_to_media(
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
    pub fn deinit(
        self: *@This(),
        allocator: std.mem.Allocator,
    ) void
    {
        if (self.maybe_name)
            |n|
        {
            allocator.free(n);
        }
        self.media.deinit(allocator);
        if (self.markers.len > 0) 
        {
            for (self.markers) 
                |*m| 
            {
                m.deinit(allocator);
            }
            allocator.free(self.markers);
        }
    }

    /// Build a handle to this Clip.
    pub fn handle(
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
        cl.handle().available_local_spaces()
    );
}

test "Clip: presentation space/media space bounds"
{
    const allocator = std.testing.allocator;

    var cl: Clip = .{
        .media = .{
            .maybe_bounds_s = .init(
                .{.start = 5, .end = 15},
            ), 
            .data_reference = .null,
            .domain = .picture,
        },
    };

    const cl_topo = try cl.topology_pres_to_media(allocator);
    defer cl_topo.deinit(allocator);

    try std.testing.expectEqual(
        // should 0->duration
        opentime.ContinuousInterval{
                .start = .zero,
                .end = cl.media.maybe_bounds_s.?.duration(),
        },
        cl_topo.input_bounds(),
    );
    try std.testing.expectEqual(
        // should 0->duration
        opentime.ContinuousInterval{
            .start = .zero,
            .end = cl.media.maybe_bounds_s.?.duration(),
        },
        cl.bounds_of(.presentation),
    );
    try std.testing.expectEqual(
        cl.media.maybe_bounds_s.?,
        cl_topo.output_bounds(),
    );
    try std.testing.expectEqual(
        // should 0->duration
        cl.media.maybe_bounds_s.?,
        cl.bounds_of(.media),
    );
}


/// A duration of the temporal space for which no media is mapped.  
///
/// Silent, Transparent.  Regions of the timeline for which there are no media
/// mapped, ie only gaps are undefined as far as pixels/audio is concerned.
pub const Gap = struct {
    /// Optional name, for labelling and human readability.
    maybe_name: ?string.latin_s8 = null,

    /// Define the bounds for gap.
    ///
    /// NOTES:
    ///
    /// * Unlike the other schema objects, the bounds for a gap is required and
    ///   not optional.
    /// * The bounds are present so that folks can "cut in" on the intrinsic
    ///   space without shifting markers
    bounds_s: opentime.ContinuousInterval,

    /// Markers attached to this gap.
    markers: []Marker = &.{},

    /// The internal temporal coordinate systems of the Gap.
    pub const available_local_spaces: []const references.TemporalSpace = (
        &.{ .presentation, .intrinsic }
    );

    pub fn deinit(
        self: @This(),
        allocator: std.mem.Allocator,
    ) void
    {
        if (self.maybe_name)
            |name|
        {
            allocator.free(name);
        }
        if (self.markers.len > 0) 
        {
            for (self.markers) 
                |*m| 
            {
                @constCast(m).deinit(allocator);
            }
            allocator.free(self.markers);
        }
    }

    /// A Gap's topology is always an identity bounded by the duration of the
    /// gap.
    pub fn topology_pres_to_intrinsic(
        self: @This(),
        allocator: std.mem.Allocator,
    ) !topology_m.Topology
    {
        const result = try topology_m.Topology.init_identity(
            allocator,
            self.bounds_s,
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

    /// The internal temporal coordinate systems Timelines.
    pub const available_local_spaces: []const references.TemporalSpace = (
        &.{ .presentation }
    );

    /// Build a handle to this Transition.
    pub fn handle(
        self: *@This(),
    ) references.CompositionItemHandle
    {
        return .{ .transition = self };
    }

    /// The topology of the Transition is just the topology of the container.
    pub fn topology_pres_to_intrinsic(
        self: @This(),
        allocator: std.mem.Allocator,
    ) !topology_m.Topology
    {
        // If explicit bounds are provided, use them
        if (self.maybe_bounds_s)
            |explicit_bounds|
        {
            return try topology_m.Topology.init_affine(
                allocator,
                .{
                    .input_bounds_val = explicit_bounds,
                    .input_to_output_xform = .identity,
                }
            );
        }
        // Try to get topology from container
        const container_topo = try self.container.topology_pres_to_intrinsic(allocator);
        // If container topology is empty (no children and no bounds),
        // return a zero-duration identity topology
        if (container_topo.input_bounds() == null) 
        {
            return try topology_m.Topology.init_identity(
                allocator,
                opentime.ContinuousInterval.from_start_duration(
                    .zero,
                    .zero,
                ),
            );
        }
        return container_topo;
    }

    /// Clear the memory of self and any child objects.
    pub fn deinit(
        self: *@This(),
        allocator: std.mem.Allocator,
    ) void
    {
        self.container.deinit(allocator);
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
    pub const available_local_spaces: []const references.TemporalSpace = (
        &.{ .presentation }
    );

    pub fn deinit(
        self: *@This(),
        allocator: std.mem.Allocator,
    ) void
    {
        self.child.deinit(allocator);
        self.transform.deinit(allocator);

        if (self.maybe_name)
            |n|
        {
            allocator.free(n);
            self.maybe_name = null;
        }
    }

    /// Build a handle to this Warp.
    pub fn handle(
        self: *@This(),
    ) references.CompositionItemHandle
    {
        return .{ .warp = self };
    }

    /// Presentation space of warp -> presentation space of child
    pub fn topology_pres_to_intrinsic(
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

    /// Optional bounds in seconds. If present, overrides bounds computed from children.
    maybe_bounds_s: ?opentime.ContinuousInterval = null,

    /// Child objects of the track, listed from first to last in temporal
    /// order. A sequence of right met segments.
    children: []references.CompositionItemHandle,

    /// Markers attached to this track.
    markers: []Marker = &.{},

    /// The internal temporal coordinate systems of the Track.
    pub const available_local_spaces: []const references.TemporalSpace = (
        &.{ .presentation, .intrinsic }
    );

    /// An empty track.
    pub const empty = Track{
        .maybe_name = null,
        .children = &.{},
    };

    /// Clear the memory of self and any child objects.
    pub fn deinit(
        self: *@This(),
        allocator: std.mem.Allocator,
    ) void
    {
        for (self.children)
            |*c|
        {
            c.deinit(allocator);
        }

        if (self.maybe_name)
            |n|
        {
            allocator.free(n);
            self.maybe_name = null;
        }
        allocator.free(self.children);
        if (self.markers.len > 0) 
        {
            for (self.markers) 
                |*m| 
            {
                m.deinit(allocator);
            }
            allocator.free(self.markers);
        }
    }

    /// construct the topology mapping the output to the intrinsic space
    pub fn topology_pres_to_intrinsic(
        self: @This(),
        allocator: std.mem.Allocator,
    ) !topology_m.Topology
    {
        // If explicit bounds are provided, use them
        if (self.maybe_bounds_s)
            |explicit_bounds|
        {
            return try topology_m.Topology.init_identity(
                allocator,
                explicit_bounds,
            );
        }

        // Otherwise, build the maybe_bounds from children
        var maybe_bounds: ?opentime.ContinuousInterval = null;
        for (self.children)
            |it|
        {
            const topo = try it.spanning_topology(allocator);
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
                    .end = .inf,
                },
                .input_to_output_xform = .{
                    .offset = current_child_duration.neg(),
                    .scale = .one,
                }
            }
        );
    }

    /// Build a handle to this Track.
    pub fn handle(
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

    /// Optional bounds in seconds. If present, overrides bounds computed from
    /// children.
    maybe_bounds_s: ?opentime.ContinuousInterval = null,

    /// Child objects of the Stack (for example, tracks).  Children are listed
    /// in compositing order, with later children coming "above" earlier
    /// entries.
    children: []references.CompositionItemHandle,

    /// Markers attached to this stack.
    markers: []Marker = &.{},

    /// The internal temporal coordinate systems of the Track.
    pub const available_local_spaces: []const references.TemporalSpace = (
        &.{ .presentation, .intrinsic }
    );

    pub const empty: Stack = .{
        .maybe_name = null,
        .children = &.{},
    };

    /// Clear the memory of self and any child objects.
    pub fn deinit(
        self: *@This(),
        allocator: std.mem.Allocator,
    ) void
    {
        for (self.children)
            |*c|
        {
            c.deinit(allocator);
        }

        if (self.maybe_name)
            |n|
        {
            allocator.free(n);
            self.maybe_name = null;
        }
        allocator.free(self.children);
        if (self.markers.len > 0) 
        {
            for (self.markers) 
                |*m| 
            {
                m.deinit(allocator);
            }
            allocator.free(self.markers);
        }
    }

    /// construct the topology mapping the output to the intrinsic space
    pub fn topology_pres_to_intrinsic(
        self: @This(),
        allocator: std.mem.Allocator,
    ) !topology_m.Topology
    {
        // If explicit bounds are provided, use them
        if (self.maybe_bounds_s)
            |explicit_bounds|
        {
            return try topology_m.Topology.init_affine(
                allocator,
                .{
                    .input_bounds_val = explicit_bounds,
                    .input_to_output_xform = .identity,
                }
            );
        }

        // Otherwise, build the bounds from children
        var bounds: ?opentime.ContinuousInterval = null;
        for (self.children)
            |it|
        {
            const it_bound = (
                (try it.spanning_topology(allocator)).input_bounds()
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
            // No children and no explicit bounds - return zero-duration identity
            // instead of empty topology to avoid InvalidChildTopology errors
            // when this stack is used as a child of another container
            return try topology_m.Topology.init_identity(
                allocator,
                opentime.ContinuousInterval.from_start_duration(
                    .zero,
                    .zero,
                ),
            );
        }
    }

    /// Build a handle to this Stack.
    pub fn handle(
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
    // other: ?std.StringHashMapUnmanaged(sampling.SampleIndexGenerator) = null,

    /// no discrete partitions for any domains
    pub const no_discretizations : DiscretePartitionDomainMap = .{
        .picture = null,
        .audio = null,
        // .other = null,
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
    tracks: Stack = .empty,

    /// Discrete space descriptions for the presentation space of the timeline.
    discrete_space_partitions: struct {
        presentation: DiscretePartitionDomainMap,

        pub const no_discretizations: @This() = .{
            .presentation = .no_discretizations,
        };
    } = .no_discretizations,

    /// Markers attached to this timeline.
    markers: []Marker = &.{},

    /// The internal temporal coordinate systems of the Timeline.
    pub const available_local_spaces: []const references.TemporalSpace = &.{
        .presentation,
        .intrinsic,
    };

    /// Clear the memory of self and any child objects.
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
        self.tracks.deinit(allocator);
        if (self.markers.len > 0) 
        {
            for (self.markers) 
                |*m| 
            {
                m.deinit(allocator);
            }
            allocator.free(self.markers);
        }
    }

    /// Presentation space of Timeline -> presentation space of `Tracks` stack.
    pub fn topology_pres_to_intrinsic(
        self: @This(),
        allocator: std.mem.Allocator,
    ) !topology_m.Topology
    {
        return try self.tracks.topology_pres_to_intrinsic(allocator);
    }

    /// Build a handle to this Timeline.
    pub fn handle(
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

        const topo = try cl.topology_pres_to_media(allocator);
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

        const topo = try cl.topology_pres_to_media(allocator);
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
        cl.handle()
    };
    var tr: Track = .{
        .children = &tr_children,
    };

    const topo = try tr.topology_pres_to_intrinsic(allocator);
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
            .child = cl.handle(),
            .transform = try topology_m.Topology.init_affine(
                allocator, 
                .{
                    .input_to_output_xform = xform,
                    .input_bounds_val = .inf_neg_to_pos,
                },
            ),
        };
        defer wp.transform.deinit(allocator);

        const topo = try wp.topology_pres_to_intrinsic(allocator);
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
            .child = cl.handle(),
            .transform = try topology_m.Topology.init_affine(
                allocator, 
                .{
                    .input_to_output_xform = xform,
                    .input_bounds_val = .inf_neg_to_pos,
                },
            ),
        };
        defer wp.transform.deinit(allocator);

        const topo = try wp.topology_pres_to_intrinsic(allocator);
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
            .child = cl.handle(),
            .transform = try topology_m.Topology.init_affine(
                allocator, 
                .{
                    .input_to_output_xform = xform,
                    .input_bounds_val = .inf_neg_to_pos,
                },
            ),
        };
        defer wp.transform.deinit(allocator);

        const wp_pres_to_child = try wp.topology_pres_to_intrinsic(allocator);
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

test "MissingFramePolicy: string conversions"
{
    // Test from_maybe_string
    try std.testing.expectEqual(
        MissingFramePolicy.@"error",
        MissingFramePolicy.from_maybe_string("error"),
    );
    try std.testing.expectEqual(
        MissingFramePolicy.hold,
        MissingFramePolicy.from_maybe_string("hold"),
    );
    try std.testing.expectEqual(
        MissingFramePolicy.black,
        MissingFramePolicy.from_maybe_string("black"),
    );

    // Test invalid string
    try std.testing.expectEqual(
        MissingFramePolicy.@"error",
        MissingFramePolicy.from_maybe_string("invalid"),
    );
}

test "ImageSequenceReference: URL generation with no padding"
{
    const allocator = std.testing.allocator;

    const img_seq = ImageSequenceReference{
        .target_url_base = "/path/to/frames/",
        .name_prefix = "frame_",
        .name_suffix = ".exr",
        .start_frame = 1,
        .frame_zero_padding = 0,
    };

    const url = try img_seq.target_url_for_image_number(allocator, 42);
    defer allocator.free(url);

    try std.testing.expectEqualStrings(
        "/path/to/frames/frame_42.exr",
        url
    );
}

test "ImageSequenceReference: URL generation with 4-digit padding"
{
    const allocator = std.testing.allocator;

    const img_seq = ImageSequenceReference{
        .target_url_base = "/render/",
        .name_prefix = "img_",
        .name_suffix = ".png",
        .start_frame = 1,
        .frame_zero_padding = 4,
    };

    const url1 = try img_seq.target_url_for_image_number(allocator, 1);
    defer allocator.free(url1);
    try std.testing.expectEqualStrings("/render/img_0001.png", url1);

    const url42 = try img_seq.target_url_for_image_number(allocator, 42);
    defer allocator.free(url42);
    try std.testing.expectEqualStrings("/render/img_0042.png", url42);

    const url1000 = try img_seq.target_url_for_image_number(allocator, 1000);
    defer allocator.free(url1000);
    try std.testing.expectEqualStrings("/render/img_1000.png", url1000);
}

test "ImageSequenceReference: URL generation with 6-digit padding"
{
    const allocator = std.testing.allocator;

    const img_seq = ImageSequenceReference{
        .target_url_base = "/vfx/",
        .name_prefix = "",
        .name_suffix = ".dpx",
        .start_frame = 1,
        .frame_zero_padding = 6,
    };

    const url = try img_seq.target_url_for_image_number(allocator, 123);
    defer allocator.free(url);
    try std.testing.expectEqualStrings("/vfx/000123.dpx", url);
}

test "ImageSequenceReference: negative start frame"
{
    const allocator = std.testing.allocator;

    const img_seq = ImageSequenceReference{
        .target_url_base = "/frames/",
        .name_prefix = "frame.",
        .name_suffix = ".jpg",
        .start_frame = -10,
        .frame_zero_padding = 0,
    };

    const url = try img_seq.target_url_for_image_number(allocator, -5);
    defer allocator.free(url);
    try std.testing.expectEqualStrings("/frames/frame.-5.jpg", url);
}

test "ImageSequenceReference: frame stepping"
{
    const allocator = std.testing.allocator;

    const img_seq = ImageSequenceReference{
        .target_url_base = "/seq/",
        .name_prefix = "f",
        .name_suffix = ".tif",
        .start_frame = 10,
        .frame_step = 2,  // Every other frame
        .frame_zero_padding = 3,
    };

    // Frame at time 0
    const url1 = try img_seq.target_url_for_image_number(allocator, 10);
    defer allocator.free(url1);
    try std.testing.expectEqualStrings("/seq/f010.tif", url1);

    // Frame at time that would be frame 2 (step of 2)
    const url2 = try img_seq.target_url_for_image_number(allocator, 12);
    defer allocator.free(url2);
    try std.testing.expectEqualStrings("/seq/f012.tif", url2);
}

test "ImageSequenceReference: frame_for_time calculations"
{
    const img_seq = ImageSequenceReference{
        .target_url_base = "/frames/",
        .start_frame = 100,
        .frame_step = 1,
        .rate = 24.0,
    };

    // At time 0, should be start_frame
    try std.testing.expectEqual(
        @as(i32, 100),
        img_seq.frame_for_time(opentime.Ordinate.init(0.0))
    );

    // At 1 second (24 frames at 24fps)
    try std.testing.expectEqual(
        @as(i32, 124),
        img_seq.frame_for_time(opentime.Ordinate.init(1.0))
    );

    // At 0.5 seconds (12 frames at 24fps)
    try std.testing.expectEqual(
        @as(i32, 112),
        img_seq.frame_for_time(opentime.Ordinate.init(0.5))
    );
}

test "ImageSequenceReference: frame_for_time with step"
{
    const img_seq = ImageSequenceReference{
        .target_url_base = "/frames/",
        .start_frame = 1,
        .frame_step = 2,
        .rate = 24.0,
    };

    // At time 0
    try std.testing.expectEqual(
        @as(i32, 1),
        img_seq.frame_for_time(opentime.Ordinate.init(0.0))
    );

    // At 1 second (24 frames, but stepping by 2)
    try std.testing.expectEqual(
        @as(i32, 49),  // 1 + (24 * 2)
        img_seq.frame_for_time(opentime.Ordinate.init(1.0))
    );
}

test "ImageSequenceReference: number_of_images_in_sequence"
{
    const img_seq = ImageSequenceReference{
        .target_url_base = "/frames/",
        .start_frame = 1,
        .frame_step = 1,
        .rate = 24.0,
    };

    const range = opentime.ContinuousInterval.init(
        .{ .start = 0.0, .end = 1.0 }
    );

    // 1 second at 24fps = 24 frames
    try std.testing.expectEqual(
        @as(i32, 24),
        img_seq.number_of_images_in_sequence(range)
    );
}

test "ImageSequenceReference: number_of_images with step"
{
    const img_seq = ImageSequenceReference{
        .target_url_base = "/frames/",
        .start_frame = 1,
        .frame_step = 2,
        .rate = 24.0,
    };

    const range = opentime.ContinuousInterval.init(
        .{ .start = 0.0, .end = 1.0 }
    );

    // 1 second at 24fps, stepping by 2 = 12 images
    try std.testing.expectEqual(
        @as(i32, 12),
        img_seq.number_of_images_in_sequence(range)
    );
}

test "ImageSequenceReference: end_frame calculation"
{
    const img_seq = ImageSequenceReference{
        .target_url_base = "/frames/",
        .start_frame = 100,
        .frame_step = 1,
        .rate = 24.0,
    };

    const range = opentime.ContinuousInterval.init(
        .{ .start = 0.0, .end = 1.0 }
    );

    // Start at 100, 24 frames, so end at 123
    try std.testing.expectEqual(
        @as(i32, 123),
        img_seq.end_frame(range)
    );
}

test "ImageSequenceReference: end_frame with step"
{
    const img_seq = ImageSequenceReference{
        .target_url_base = "/frames/",
        .start_frame = 1,
        .frame_step = 5,
        .rate = 30.0,
    };

    const range = opentime.ContinuousInterval.init(
        .{ .start = 0.0, .end = 2.0 }
    );

    // 2 seconds at 30fps = 60 frames
    // Stepping by 5 = 12 images
    // Start at 1, so end at 1 + (11 * 5) = 56
    try std.testing.expectEqual(
        @as(i32, 56),
        img_seq.end_frame(range)
    );
}

test "ImageSequenceReference: complete workflow"
{
    const allocator = std.testing.allocator;

    const img_seq = ImageSequenceReference{
        .target_url_base = "/project/renders/",
        .name_prefix = "shot_010_",
        .name_suffix = ".exr",
        .start_frame = 1001,
        .frame_step = 1,
        .frame_zero_padding = 4,
        .rate = 24.0,
        .missing_frame_policy = .hold,
    };

    // Test policy
    try std.testing.expectEqual(
        MissingFramePolicy.hold,
        img_seq.missing_frame_policy
    );

    // Test frame at specific time
    const frame_at_1sec = img_seq.frame_for_time(
        opentime.Ordinate.init(1.0)
    );
    try std.testing.expectEqual(@as(i32, 1025), frame_at_1sec);

    // Test URL generation for that frame
    const url = try img_seq.target_url_for_image_number(
        allocator,
        frame_at_1sec
    );
    defer allocator.free(url);
    try std.testing.expectEqualStrings(
        "/project/renders/shot_010_1025.exr",
        url
    );

    // Test sequence calculations
    const range = opentime.ContinuousInterval.init(
        .{ .start = 0.0, .end = 5.0 }
    );
    const num_images = img_seq.number_of_images_in_sequence(range);
    try std.testing.expectEqual(@as(i32, 120), num_images);

    const last_frame = img_seq.end_frame(range);
    try std.testing.expectEqual(@as(i32, 1120), last_frame);
}
