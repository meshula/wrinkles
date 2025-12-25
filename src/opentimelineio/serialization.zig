//! Serialization layer for OTIO schema types using Ziggy format.
//!
//! This module provides serializable variants of schema types that can be
//! used with the ziggy serialization library. The main challenges addressed:
//! - Converting pointer-based CompositionItemHandle to inline tagged unions
//! - Copying strings for arena-friendly memory management
//! - Serializing complex Topology structures
//!
//! Usage:
//!   serialize_timeline() - Write Timeline to Ziggy format
//!   deserialize_timeline() - Read Ziggy format back to Timeline

const std = @import("std");
const schema = @import("schema.zig");
const opentime = @import("opentime");
const sampling = @import("sampling");
const topology_m = @import("topology");
const curve = @import("curve");
const domain = @import("domain.zig");
const string = @import("string_stuff");
const ziggy = @import("ziggy");
const versioning = @import("versioning.zig");

const Allocator = std.mem.Allocator;

// Re-export curve control point for convenience
const CurveControlPoint = curve.ControlPoint;

// ----------------------------------------------------------------------------
// Serializable Type Definitions
// ----------------------------------------------------------------------------

/// Serializable variant of ContinuousInterval as [2]f64 = [start, end]
pub const SerializableContinuousInterval = [2]f64;

/// Bounds can be either continuous (time in seconds) or discrete (sample indices)
pub const SerializableBounds = union(enum) {
    continuous: [2]f64,  // [start_seconds, end_seconds]
    discrete: [2]i64,    // [start_index, end_index]
};

/// Serializable variant of AffineTransform1D
pub const SerializableAffineTransform1D = opentime.AffineTransform1D;

/// Serializable variant of SampleIndexGenerator
pub const SerializableSampleIndexGenerator = sampling.SampleIndexGenerator;

/// Serializable variant of Domain
pub const SerializableDomain = union(enum) {
    time: void,
    picture: void,
    audio: void,
    metadata: void,
    other: []const u8,
};

/// Serializable variant of MediaDataReference
pub const SerializableMediaDataReference = union(enum) {
    uri: SerializableURIReference,
    signal: SerializableSignalReference,
    null: void,
};

pub const SerializableURIReference = struct {
    target_uri: []const u8,
};

pub const SerializableSignalReference = struct {
    signal_generator: SerializableSignalGenerator,
};

pub const SerializableSignalGenerator = union(enum) {
    sine: struct {
        frequency_hz: f64,
    },
    linear_ramp: void,
};

/// Serializable variant of MediaReference
pub const SerializableMediaReference = struct {
    data_reference: SerializableMediaDataReference,
    bounds_s: ?SerializableBounds,
    domain: SerializableDomain,
    discrete_partition: ?SerializableSampleIndexGenerator,
    interpolating: ?schema.ResamplingBehavior,
};

/// Serializable variant of Clip
pub const SerializableClip = struct {
    pub const schema_name: []const u8 = "Clip";
    pub const schema_version: u32 = versioning.current_version("Clip");

    name: ?[]const u8,
    bounds_s: ?SerializableBounds,
    media: SerializableMediaReference,
};

/// Serializable variant of Gap
pub const SerializableGap = struct {
    pub const schema_name: []const u8 = "Gap";
    pub const schema_version: u32 = versioning.current_version("Gap");

    name: ?[]const u8,
    bounds_s: SerializableContinuousInterval,
};

/// Serializable variant of Mapping
pub const SerializableMapping = union(enum) {
    affine: SerializableMappingAffine,
    linear: SerializableMappingLinear,
    empty: void,
};

pub const SerializableMappingAffine = struct {
    input_bounds_val: SerializableContinuousInterval,
    input_to_output_xform: SerializableAffineTransform1D,
};

pub const SerializableMappingLinear = struct {
    input_bounds_val: SerializableContinuousInterval,
    knots: []curve.ControlPoint,
};

/// Serializable variant of Topology
pub const SerializableTopology = struct {
    mappings: []SerializableMapping,
};

/// Forward declarations for recursive types
pub const SerializableComposable = union(enum) {
    clip: SerializableClip,
    gap: SerializableGap,
    track: *SerializableTrack,
    stack: *SerializableStack,
    warp: *SerializableWarp,
    transition: *SerializableTransition,
};

/// Serializable variant of Warp
pub const SerializableWarp = struct {
    pub const schema_name: []const u8 = "Warp";
    pub const schema_version: u32 = versioning.current_version("Warp");

    name: ?[]const u8,
    child: SerializableComposable,
    transform: SerializableTopology,
};

/// Serializable variant of Stack
pub const SerializableStack = struct {
    pub const schema_name: []const u8 = "Stack";
    pub const schema_version: u32 = versioning.current_version("Stack");

    name: ?[]const u8,
    children: []SerializableComposable,
};

/// Serializable variant of Track
pub const SerializableTrack = struct {
    pub const schema_name: []const u8 = "Track";
    pub const schema_version: u32 = versioning.current_version("Track");

    name: ?[]const u8,
    children: []SerializableComposable,
};

/// Serializable variant of Transition
pub const SerializableTransition = struct {
    pub const schema_name: []const u8 = "Transition";
    pub const schema_version: u32 = versioning.current_version("Transition");

    name: ?[]const u8,
    container: SerializableStack,
    kind: []const u8,
    bounds_s: ?SerializableContinuousInterval,
};

pub const SerializableDiscretePartitionDomainMap = struct {
    picture: ?SerializableSampleIndexGenerator,
    audio: ?SerializableSampleIndexGenerator,
};

/// Serializable variant of Timeline (root type)
pub const SerializableTimeline = struct {
    pub const schema_name: []const u8 = "Timeline";
    pub const schema_version: u32 = versioning.current_version("Timeline");

    name: ?[]const u8,
    children: []SerializableComposable,
    presentation_space_discrete_partitions: SerializableDiscretePartitionDomainMap,
};

// ----------------------------------------------------------------------------
// Curve Library Serializable Types
// ----------------------------------------------------------------------------
// ControlPoint = [2]f64 = [in, out]
// BezierSegment = [4]ControlPoint = [p0, p1, p2, p3]

/// Serializable variant of curve.Bezier
/// Each segment is [4][2]f64 (4 control points of 2 floats each)
pub const SerializableBezierCurve = struct {
    pub const schema_name: []const u8 = "BezierCurve";
    pub const schema_version: u32 = 1;

    segments: [][4][2]f64,  // Array of segments, each with 4 control points
};

/// Serializable variant of curve.Linear
/// Knots are [][2]f64 (array of control points)
pub const SerializableLinearCurve = struct {
    pub const schema_name: []const u8 = "LinearCurve";
    pub const schema_version: u32 = 1;

    knots: [][2]f64,  // Array of control points
};

// ----------------------------------------------------------------------------
// Helper Functions: String Copying
// ----------------------------------------------------------------------------

fn copy_string(
    allocator: Allocator,
    str: []const u8,
) ![]const u8
{
    return try allocator.dupe(u8, str);
}

fn copy_optional_string(
    allocator: Allocator,
    maybe_str: ?[]const u8,
) !?[]const u8
{
    if (maybe_str) |str| {
        return try copy_string(allocator, str);
    }
    return null;
}

// ----------------------------------------------------------------------------
// Helper Functions: Bounds Conversion
// ----------------------------------------------------------------------------

/// Convert ContinuousInterval to SerializableBounds (discrete if partition exists)
fn bounds_to_serializable(
    interval: opentime.ContinuousInterval,
    maybe_discrete_partition: ?sampling.SampleIndexGenerator,
) SerializableBounds
{
    if (maybe_discrete_partition) |sig| {
        // Convert to discrete indices
        const start_index = sig.project_instantaneous_cd(interval.start);
        const end_index = sig.project_instantaneous_cd(interval.end);
        return .{ .discrete = .{ @intCast(start_index), @intCast(end_index) } };
    } else {
        // Keep as continuous
        return .{ .continuous = .{ interval.start.as(f64), interval.end.as(f64) } };
    }
}

/// Convert SerializableBounds to ContinuousInterval
fn serializable_to_bounds(
    ser_bounds: SerializableBounds,
    maybe_discrete_partition: ?sampling.SampleIndexGenerator,
) !opentime.ContinuousInterval
{
    return switch (ser_bounds) {
        .continuous => |cont| .{
            .start = opentime.Ordinate.init(cont[0]),
            .end = opentime.Ordinate.init(cont[1]),
        },
        .discrete => |disc| {
            // Must have discrete partition to convert
            const sig = maybe_discrete_partition orelse return error.MissingDiscretePartition;

            // Convert discrete indices to continuous interval
            const start_ord = sig.ordinate_at_index(@intCast(disc[0]));
            const end_ord = sig.ordinate_at_index(@intCast(disc[1]));

            return .{
                .start = start_ord,
                .end = end_ord,
            };
        },
    };
}

/// Convert optional ContinuousInterval to optional SerializableBounds
fn optional_bounds_to_serializable(
    maybe_interval: ?opentime.ContinuousInterval,
    maybe_discrete_partition: ?sampling.SampleIndexGenerator,
) ?SerializableBounds
{
    if (maybe_interval) |interval| {
        return bounds_to_serializable(interval, maybe_discrete_partition);
    }
    return null;
}

/// Convert optional SerializableBounds to optional ContinuousInterval
fn serializable_to_optional_bounds(
    maybe_ser: ?SerializableBounds,
    maybe_discrete_partition: ?sampling.SampleIndexGenerator,
) !?opentime.ContinuousInterval
{
    if (maybe_ser) |ser| {
        return try serializable_to_bounds(ser, maybe_discrete_partition);
    }
    return null;
}

// ----------------------------------------------------------------------------
// Helper Functions: ContinuousInterval Conversion
// ----------------------------------------------------------------------------

/// Convert ContinuousInterval to serializable [2]f64 format
fn interval_to_serializable(
    interval: opentime.ContinuousInterval,
) SerializableContinuousInterval
{
    return .{ interval.start.as(f64), interval.end.as(f64) };
}

/// Convert serializable [2]f64 to ContinuousInterval
fn serializable_to_interval(
    ser: SerializableContinuousInterval,
) opentime.ContinuousInterval
{
    return .{
        .start = opentime.Ordinate.init(ser[0]),
        .end = opentime.Ordinate.init(ser[1]),
    };
}

/// Convert optional ContinuousInterval to serializable format
fn optional_interval_to_serializable(
    maybe_interval: ?opentime.ContinuousInterval,
) ?SerializableContinuousInterval
{
    if (maybe_interval) |interval| {
        return interval_to_serializable(interval);
    }
    return null;
}

/// Convert optional serializable interval to ContinuousInterval
fn serializable_to_optional_interval(
    maybe_ser: ?SerializableContinuousInterval,
) ?opentime.ContinuousInterval
{
    if (maybe_ser) |ser| {
        return serializable_to_interval(ser);
    }
    return null;
}

// ----------------------------------------------------------------------------
// Conversion Functions: Schema → Serializable
// ----------------------------------------------------------------------------

pub fn domain_to_serializable(
    allocator: Allocator,
    dom: domain.Domain,
) !SerializableDomain
{
    return switch (dom) {
        .time => .time,
        .picture => .picture,
        .audio => .audio,
        .metadata => .metadata,
        .other => |s| .{ .other = try copy_string(allocator, s) },
    };
}

pub fn media_data_reference_to_serializable(
    allocator: Allocator,
    ref: schema.MediaDataReference,
) !SerializableMediaDataReference {
    return switch (ref) {
        .uri => |uri_ref| .{
            .uri = .{
                .target_uri = try copy_string(allocator, uri_ref.target_uri),
            },
        },
        .signal => |sig_ref| .{
            .signal = .{
                .signal_generator = try signal_generator_to_serializable(
                    allocator,
                    sig_ref.signal_generator,
                ),
            },
        },
        .null => .null,
    };
}

pub fn signal_generator_to_serializable(
    allocator: Allocator,
    gen: sampling.SignalGenerator,
) !SerializableSignalGenerator {
    _ = allocator;
    return switch (gen) {
        .sine => |sine| .{ .sine = .{ .frequency_hz = sine.frequency_hz } },
        .linear_ramp => .linear_ramp,
    };
}

pub fn media_reference_to_serializable(
    allocator: Allocator,
    ref: schema.MediaReference,
) !SerializableMediaReference {
    return .{
        .data_reference = try media_data_reference_to_serializable(
            allocator,
            ref.data_reference,
        ),
        .bounds_s = optional_bounds_to_serializable(
            ref.maybe_bounds_s,
            ref.maybe_discrete_partition,
        ),
        .domain = try domain_to_serializable(allocator, ref.domain),
        .discrete_partition = ref.maybe_discrete_partition,
        .interpolating = if (ref.interpolating == .default_from_domain)
            null
        else
            ref.interpolating,
    };
}

pub fn topology_to_serializable(
    allocator: Allocator,
    topo: topology_m.Topology,
) !SerializableTopology {
    const ser_mappings = try allocator.alloc(SerializableMapping, topo.mappings.len);

    for (topo.mappings, 0..) |mapping, i| {
        ser_mappings[i] = try mapping_to_serializable(allocator, mapping);
    }

    return .{ .mappings = ser_mappings };
}

pub fn mapping_to_serializable(
    allocator: Allocator,
    mapping: topology_m.mapping.Mapping,
) !SerializableMapping {
    return switch (mapping) {
        .affine => |aff| .{
            .affine = .{
                .input_bounds_val = interval_to_serializable(aff.input_bounds_val),
                .input_to_output_xform = aff.input_to_output_xform,
            },
        },
        .linear_monotonic => |lin| {
            const knots = try allocator.dupe(
                curve.ControlPoint,
                lin.input_to_output_curve.knots,
            );
            return .{
                .linear = .{
                    .input_bounds_val = interval_to_serializable(lin.input_to_output_curve.extents()),
                    .knots = knots,
                },
            };
        },
        .empty => .empty,
    };
}

pub fn clip_to_serializable(
    allocator: Allocator,
    clip: schema.Clip,
) !SerializableClip {
    return .{
        .name = try copy_optional_string(allocator, clip.maybe_name),
        .bounds_s = optional_bounds_to_serializable(
            clip.maybe_bounds_s,
            clip.media.maybe_discrete_partition,
        ),
        .media = try media_reference_to_serializable(allocator, clip.media),
    };
}

pub fn gap_to_serializable(
    allocator: Allocator,
    gap: schema.Gap,
) !SerializableGap
{
    return .{
        .name = try copy_optional_string(allocator, gap.maybe_name),
        .bounds_s = interval_to_serializable(gap.bounds_s),
    };
}

pub fn warp_to_serializable(
    allocator: Allocator,
    warp: schema.Warp,
) !SerializableWarp {
    const ser_warp_ptr = try allocator.create(SerializableWarp);
    ser_warp_ptr.* = .{
        .name = try copy_optional_string(allocator, warp.maybe_name),
        .child = try composable_to_serializable(allocator, warp.child),
        .transform = try topology_to_serializable(allocator, warp.transform),
    };
    return ser_warp_ptr.*;
}

pub fn track_to_serializable(
    allocator: Allocator,
    track: schema.Track,
) !SerializableTrack {
    const ser_children = try allocator.alloc(SerializableComposable, track.children.len);

    for (track.children, 0..) |child, i| {
        ser_children[i] = try composable_to_serializable(allocator, child);
    }

    return .{
        .name = try copy_optional_string(allocator, track.maybe_name),
        .children = ser_children,
    };
}

pub fn stack_to_serializable(
    allocator: Allocator,
    stack: schema.Stack,
) !SerializableStack {
    const ser_children = try allocator.alloc(SerializableComposable, stack.children.len);

    for (stack.children, 0..) |child, i| {
        ser_children[i] = try composable_to_serializable(allocator, child);
    }

    return .{
        .name = try copy_optional_string(allocator, stack.maybe_name),
        .children = ser_children,
    };
}

pub fn transition_to_serializable(
    allocator: Allocator,
    transition: schema.Transition,
) !SerializableTransition {
    return .{
        .name = try copy_optional_string(allocator, transition.maybe_name),
        .container = try stack_to_serializable(allocator, transition.container),
        .kind = try copy_string(allocator, transition.kind),
        .bounds_s = optional_interval_to_serializable(transition.maybe_bounds_s),
    };
}

pub fn composable_to_serializable(
    allocator: Allocator,
    handle: schema.references.CompositionItemHandle,
) error{OutOfMemory}!SerializableComposable {
    return switch (handle) {
        .clip => |clip_ptr| .{
            .clip = try clip_to_serializable(allocator, clip_ptr.*),
        },
        .gap => |gap_ptr| .{
            .gap = try gap_to_serializable(allocator, gap_ptr.*),
        },
        .track => |track_ptr| blk: {
            const ser_track_ptr = try allocator.create(SerializableTrack);
            ser_track_ptr.* = try track_to_serializable(allocator, track_ptr.*);
            break :blk .{ .track = ser_track_ptr };
        },
        .stack => |stack_ptr| blk: {
            const ser_stack_ptr = try allocator.create(SerializableStack);
            ser_stack_ptr.* = try stack_to_serializable(allocator, stack_ptr.*);
            break :blk .{ .stack = ser_stack_ptr };
        },
        .warp => |warp_ptr| blk: {
            const ser_warp_ptr = try allocator.create(SerializableWarp);
            ser_warp_ptr.* = try warp_to_serializable(allocator, warp_ptr.*);
            break :blk .{ .warp = ser_warp_ptr };
        },
        .transition => |trans_ptr| blk: {
            const ser_trans_ptr = try allocator.create(SerializableTransition);
            ser_trans_ptr.* = try transition_to_serializable(allocator, trans_ptr.*);
            break :blk .{ .transition = ser_trans_ptr };
        },
        .timeline => unreachable, // Timeline is not a composable child
    };
}

pub fn timeline_to_serializable(
    allocator: Allocator,
    timeline: *schema.Timeline,
) !SerializableTimeline {
    // Convert tracks.children directly to timeline.children
    const ser_children = try allocator.alloc(SerializableComposable, timeline.tracks.children.len);

    for (timeline.tracks.children, 0..) |child, i| {
        ser_children[i] = try composable_to_serializable(allocator, child);
    }

    return .{
        .name = try copy_optional_string(allocator, timeline.maybe_name),
        .children = ser_children,
        .presentation_space_discrete_partitions = .{
            .picture = timeline.discrete_space_partitions.presentation.picture,
            .audio = timeline.discrete_space_partitions.presentation.audio,
        },
    };
}

// ----------------------------------------------------------------------------
// Conversion Functions: Serializable → Schema
// ----------------------------------------------------------------------------

pub fn serializable_to_domain(
    allocator: Allocator,
    ser_dom: SerializableDomain,
) !domain.Domain {
    return switch (ser_dom) {
        .time => .time,
        .picture => .picture,
        .audio => .audio,
        .metadata => .metadata,
        .other => |s| .{ .other = try copy_string(allocator, s) },
    };
}

pub fn serializable_to_media_data_reference(
    allocator: Allocator,
    ser_ref: SerializableMediaDataReference,
) !schema.MediaDataReference {
    return switch (ser_ref) {
        .uri => |uri_ref| .{
            .uri = .{
                .target_uri = try copy_string(allocator, uri_ref.target_uri),
            },
        },
        .signal => |sig_ref| .{
            .signal = .{
                .signal_generator = try serializable_to_signal_generator(
                    allocator,
                    sig_ref.signal_generator,
                ),
            },
        },
        .null => .null,
    };
}

pub fn serializable_to_signal_generator(
    allocator: Allocator,
    ser_gen: SerializableSignalGenerator,
) !sampling.SignalGenerator {
    _ = allocator;
    return switch (ser_gen) {
        .sine => |sine| .{ .sine = .{ .frequency_hz = sine.frequency_hz } },
        .linear_ramp => .linear_ramp,
    };
}

pub fn serializable_to_media_reference(
    allocator: Allocator,
    ser_ref: SerializableMediaReference,
) !schema.MediaReference {
    return .{
        .data_reference = try serializable_to_media_data_reference(
            allocator,
            ser_ref.data_reference,
        ),
        .maybe_bounds_s = try serializable_to_optional_bounds(
            ser_ref.bounds_s,
            ser_ref.discrete_partition,
        ),
        .domain = try serializable_to_domain(allocator, ser_ref.domain),
        .maybe_discrete_partition = ser_ref.discrete_partition,
        .interpolating = ser_ref.interpolating orelse .default_from_domain,
    };
}

pub fn serializable_to_topology(
    allocator: Allocator,
    ser_topo: SerializableTopology,
) !topology_m.Topology {
    const mappings = try allocator.alloc(
        topology_m.mapping.Mapping,
        ser_topo.mappings.len,
    );

    for (ser_topo.mappings, 0..) |ser_mapping, i| {
        mappings[i] = try serializable_to_mapping(allocator, ser_mapping);
    }

    return .{ .mappings = mappings };
}

pub fn serializable_to_mapping(
    allocator: Allocator,
    ser_mapping: SerializableMapping,
) !topology_m.mapping.Mapping {
    return switch (ser_mapping) {
        .affine => |aff| (topology_m.mapping.MappingAffine{
            .input_bounds_val = serializable_to_interval(aff.input_bounds_val),
            .input_to_output_xform = aff.input_to_output_xform,
        }).mapping(),
        .linear => |lin| {
            const knots = try allocator.dupe(curve.ControlPoint, lin.knots);
            return (topology_m.mapping.MappingCurveLinearMonotonic{
                .input_to_output_curve = .{ .knots = knots },
            }).mapping();
        },
        .empty => topology_m.mapping.empty.mapping(),
    };
}

pub fn serializable_to_clip(
    allocator: Allocator,
    ser_clip: SerializableClip,
) !*schema.Clip {
    const clip_ptr = try allocator.create(schema.Clip);
    const media = try serializable_to_media_reference(allocator, ser_clip.media);
    clip_ptr.* = .{
        .maybe_name = try copy_optional_string(allocator, ser_clip.name),
        .maybe_bounds_s = try serializable_to_optional_bounds(
            ser_clip.bounds_s,
            media.maybe_discrete_partition,
        ),
        .media = media,
    };
    return clip_ptr;
}

pub fn serializable_to_gap(
    allocator: Allocator,
    ser_gap: SerializableGap,
) !*schema.Gap
{
    const gap_ptr = try allocator.create(schema.Gap);
    gap_ptr.* = .{
        .maybe_name = try copy_optional_string(allocator, ser_gap.name),
        .bounds_s = serializable_to_interval(ser_gap.bounds_s),
    };
    return gap_ptr;
}

pub fn serializable_to_warp(
    allocator: Allocator,
    ser_warp: SerializableWarp,
) !*schema.Warp {
    const warp_ptr = try allocator.create(schema.Warp);
    warp_ptr.* = .{
        .maybe_name = try copy_optional_string(allocator, ser_warp.name),
        .child = try serializable_to_composable(allocator, ser_warp.child),
        .transform = try serializable_to_topology(allocator, ser_warp.transform),
    };
    return warp_ptr;
}

pub fn serializable_to_track(
    allocator: Allocator,
    ser_track: SerializableTrack,
) !*schema.Track {
    const children = try allocator.alloc(
        schema.references.CompositionItemHandle,
        ser_track.children.len,
    );

    for (ser_track.children, 0..) |ser_child, i| {
        children[i] = try serializable_to_composable(allocator, ser_child);
    }

    const track_ptr = try allocator.create(schema.Track);
    track_ptr.* = .{
        .maybe_name = try copy_optional_string(allocator, ser_track.name),
        .children = children,
    };
    return track_ptr;
}

pub fn serializable_to_stack(
    allocator: Allocator,
    ser_stack: SerializableStack,
) !*schema.Stack {
    const children = try allocator.alloc(
        schema.references.CompositionItemHandle,
        ser_stack.children.len,
    );

    for (ser_stack.children, 0..) |ser_child, i| {
        children[i] = try serializable_to_composable(allocator, ser_child);
    }

    const stack_ptr = try allocator.create(schema.Stack);
    stack_ptr.* = .{
        .maybe_name = try copy_optional_string(allocator, ser_stack.name),
        .children = children,
    };
    return stack_ptr;
}

pub fn serializable_to_transition(
    allocator: Allocator,
    ser_trans: SerializableTransition,
) !*schema.Transition {
    const container_ptr = try serializable_to_stack(allocator, ser_trans.container);

    const trans_ptr = try allocator.create(schema.Transition);
    trans_ptr.* = .{
        .maybe_name = try copy_optional_string(allocator, ser_trans.name),
        .container = container_ptr.*,
        .kind = try copy_string(allocator, ser_trans.kind),
        .maybe_bounds_s = serializable_to_optional_interval(ser_trans.bounds_s),
    };

    // Free the temporary stack pointer (contents are moved)
    allocator.destroy(container_ptr);

    return trans_ptr;
}

pub fn serializable_to_composable(
    allocator: Allocator,
    ser_comp: SerializableComposable,
) error{OutOfMemory}!schema.references.CompositionItemHandle {
    return switch (ser_comp) {
        .clip => |ser_clip| .{
            .clip = try serializable_to_clip(allocator, ser_clip),
        },
        .gap => |ser_gap| .{
            .gap = try serializable_to_gap(allocator, ser_gap),
        },
        .track => |ser_track_ptr| .{
            .track = try serializable_to_track(allocator, ser_track_ptr.*),
        },
        .stack => |ser_stack_ptr| .{
            .stack = try serializable_to_stack(allocator, ser_stack_ptr.*),
        },
        .warp => |ser_warp_ptr| .{
            .warp = try serializable_to_warp(allocator, ser_warp_ptr.*),
        },
        .transition => |ser_trans_ptr| .{
            .transition = try serializable_to_transition(allocator, ser_trans_ptr.*),
        },
    };
}

pub fn serializable_to_timeline(
    allocator: Allocator,
    ser_timeline: SerializableTimeline,
) !*schema.Timeline {
    // Convert children back to tracks.children
    const children = try allocator.alloc(
        schema.references.CompositionItemHandle,
        ser_timeline.children.len,
    );

    for (ser_timeline.children, 0..) |ser_child, i| {
        children[i] = try serializable_to_composable(allocator, ser_child);
    }

    const timeline_ptr = try allocator.create(schema.Timeline);
    timeline_ptr.* = .{
        .maybe_name = try copy_optional_string(allocator, ser_timeline.name),
        .tracks = .{
            .maybe_name = null,  // Timeline's implicit tracks Stack has no name
            .children = children,
        },
        .discrete_space_partitions = .{
            .presentation = ser_timeline.presentation_space_discrete_partitions,
        },
    };

    return timeline_ptr;
}

// ----------------------------------------------------------------------------
// Curve Conversion Functions
// ----------------------------------------------------------------------------

/// Convert curve.Bezier to serializable format
pub fn bezier_curve_to_serializable(
    allocator: Allocator,
    bezier: curve.Bezier,
) !SerializableBezierCurve
{
    const ser_segments = try allocator.alloc([4][2]f64, bezier.segments.len);

    for (bezier.segments, 0..)
        |segment, i|
    {
        // Each segment becomes [4][2]f64 (4 control points)
        ser_segments[i] = .{
            .{ segment.p0.in.as(f64), segment.p0.out.as(f64) },
            .{ segment.p1.in.as(f64), segment.p1.out.as(f64) },
            .{ segment.p2.in.as(f64), segment.p2.out.as(f64) },
            .{ segment.p3.in.as(f64), segment.p3.out.as(f64) },
        };
    }

    return .{
        .segments = ser_segments,
    };
}

/// Convert serializable format to curve.Bezier
pub fn serializable_to_bezier_curve(
    allocator: Allocator,
    ser_bezier: SerializableBezierCurve,
) !curve.Bezier
{
    const segments = try allocator.alloc(
        curve.bezier_curve.Segment,
        ser_bezier.segments.len
    );

    for (ser_bezier.segments, 0..)
        |seg, i|
    {
        segments[i] = .{
            .p0 = .{
                .in = opentime.Ordinate.init(seg[0][0]),
                .out = opentime.Ordinate.init(seg[0][1]),
            },
            .p1 = .{
                .in = opentime.Ordinate.init(seg[1][0]),
                .out = opentime.Ordinate.init(seg[1][1]),
            },
            .p2 = .{
                .in = opentime.Ordinate.init(seg[2][0]),
                .out = opentime.Ordinate.init(seg[2][1]),
            },
            .p3 = .{
                .in = opentime.Ordinate.init(seg[3][0]),
                .out = opentime.Ordinate.init(seg[3][1]),
            },
        };
    }

    return curve.Bezier.init(allocator, segments);
}

/// Convert curve.Linear to serializable format
pub fn linear_curve_to_serializable(
    allocator: Allocator,
    linear: curve.Linear,
) !SerializableLinearCurve
{
    const ser_knots = try allocator.alloc([2]f64, linear.knots.len);

    for (linear.knots, 0..)
        |knot, i|
    {
        ser_knots[i] = .{
            knot.in.as(f64),
            knot.out.as(f64),
        };
    }

    return .{
        .knots = ser_knots,
    };
}

/// Convert serializable format to curve.Linear
pub fn serializable_to_linear_curve(
    allocator: Allocator,
    ser_linear: SerializableLinearCurve,
) !curve.Linear
{
    const knots = try allocator.alloc(CurveControlPoint, ser_linear.knots.len);

    for (ser_linear.knots, 0..)
        |ser_knot, i|
    {
        knots[i] = .{
            .in = opentime.Ordinate.init(ser_knot[0]),
            .out = opentime.Ordinate.init(ser_knot[1]),
        };
    }

    return curve.Linear.init(allocator, knots);
}

// ----------------------------------------------------------------------------
// Main Serialization Entry Points (using Ziggy)
// ----------------------------------------------------------------------------

/// Serialize a Timeline to Ziggy format and write to the provided writer.
///
/// If target_version is provided, the timeline will be downgraded to that
/// version before serialization (requires registered downgrade functions).
pub fn serialize_timeline(
    timeline: *schema.Timeline,
    allocator: Allocator,
    writer: anytype,
    maybe_target_version: ?u32,
) !void
{
    // Convert to serializable format
    var ser_timeline = try timeline_to_serializable(allocator, timeline);

    // Downgrade if target version specified
    if (maybe_target_version)
        |target_version|
    {
        const current_ver = versioning.current_version("Timeline");
        if (target_version < current_ver)
        {
            // Try to get global registry and downgrade
            const registry = versioning.get_global_registry(allocator) catch |err| {
                // If registry doesn't exist or fails, log and continue with current version
                std.log.warn(
                    "Failed to get version registry for downgrade: {}. " ++
                    "Serializing Timeline at version {} instead of {}.",
                    .{ err, current_ver, target_version }
                );
                try ziggy.serialize(
                    ser_timeline,
                    .{
                        .whitespace = .space_4,
                        .emit_null_fields = false,
                    },
                    writer
                );
                return;
            };

            // Attempt downgrade
            registry.downgrade(
                allocator,
                "Timeline",
                &ser_timeline,
                current_ver,
                target_version,
            ) catch |err| {
                // If downgrade fails, log warning and serialize at current version
                std.log.warn(
                    "Failed to downgrade Timeline from version {} to {}: {}. " ++
                    "Serializing at current version.",
                    .{ current_ver, target_version, err }
                );
            };
        }
    }

    // Use ziggy to serialize
    try ziggy.serialize(
        ser_timeline,
        .{
            .whitespace = .space_4,
            .emit_null_fields = false,
        },
        writer
    );
}

/// Deserialize a Timeline from Ziggy format source string.
///
/// Automatically detects the version in the file and upgrades to the current
/// version if needed (requires registered upgrade functions).
pub fn deserialize_timeline(
    allocator: Allocator,
    source: [:0]const u8,
) !*schema.Timeline
{
    // Use ziggy to deserialize
    var meta: ziggy.Deserializer.Meta = undefined;
    var ser_timeline = try ziggy.deserializeLeaky(
        SerializableTimeline,
        allocator,
        source,
        &meta,
        .{},
    );

    // Check version and upgrade if needed
    const current_ver = versioning.current_version("Timeline");
    if (ser_timeline.schema_version < current_ver)
    {
        // Try to get global registry and upgrade
        const registry = versioning.get_global_registry(allocator) catch |err| {
            // If registry doesn't exist or fails, log and continue with current version
            std.log.warn(
                "Failed to get version registry for upgrade: {}. " ++
                "Loading Timeline at version {} without upgrading to {}.",
                .{ err, ser_timeline.schema_version, current_ver }
            );
            return try serializable_to_timeline(allocator, ser_timeline);
        };

        // Attempt upgrade
        registry.upgrade(
            allocator,
            "Timeline",
            &ser_timeline,
            ser_timeline.schema_version,
            current_ver,
        ) catch |err| {
            // If upgrade fails, log warning and continue
            std.log.warn(
                "Failed to upgrade Timeline from version {} to {}: {}. " ++
                "Loading at original version.",
                .{ ser_timeline.schema_version, current_ver, err }
            );
        };
    }

    // Convert to schema format
    return try serializable_to_timeline(allocator, ser_timeline);
}

/// Serialize a Bezier curve to Ziggy format and write to the provided writer.
pub fn serialize_bezier_curve(
    bezier: curve.Bezier,
    allocator: Allocator,
    writer: anytype,
) !void {
    // Convert to serializable format
    const ser_bezier = try bezier_curve_to_serializable(allocator, bezier);

    // Use ziggy to serialize
    try ziggy.serialize(ser_bezier, .{
        .whitespace = .space_4,
        .emit_null_fields = false,
    }, writer);
}

/// Deserialize a Bezier curve from Ziggy format source string.
pub fn deserialize_bezier_curve(
    allocator: Allocator,
    source: [:0]const u8,
) !curve.Bezier {
    // Use ziggy to deserialize
    var meta: ziggy.Deserializer.Meta = undefined;
    const ser_bezier = try ziggy.deserializeLeaky(
        SerializableBezierCurve,
        allocator,
        source,
        &meta,
        .{},
    );

    // Convert to curve format
    return try serializable_to_bezier_curve(allocator, ser_bezier);
}

/// Serialize a Linear curve to Ziggy format and write to the provided writer.
pub fn serialize_linear_curve(
    linear: curve.Linear,
    allocator: Allocator,
    writer: anytype,
) !void {
    // Convert to serializable format
    const ser_linear = try linear_curve_to_serializable(allocator, linear);

    // Use ziggy to serialize
    try ziggy.serialize(ser_linear, .{
        .whitespace = .space_4,
        .emit_null_fields = false,
    }, writer);
}

/// Deserialize a Linear curve from Ziggy format source string.
pub fn deserialize_linear_curve(
    allocator: Allocator,
    source: [:0]const u8,
) !curve.Linear {
    // Use ziggy to deserialize
    var meta: ziggy.Deserializer.Meta = undefined;
    const ser_linear = try ziggy.deserializeLeaky(
        SerializableLinearCurve,
        allocator,
        source,
        &meta,
        .{},
    );

    // Convert to curve format
    return try serializable_to_linear_curve(allocator, ser_linear);
}

// ----------------------------------------------------------------------------
// Tests
// ----------------------------------------------------------------------------

test "interval conversion: ContinuousInterval to [2]f64"
{
    const interval = opentime.ContinuousInterval{
        .start = opentime.Ordinate.init(1.5),
        .end = opentime.Ordinate.init(3.75),
    };

    const ser = interval_to_serializable(interval);

    try std.testing.expectEqual(@as(f64, 1.5), ser[0]);
    try std.testing.expectEqual(@as(f64, 3.75), ser[1]);
}

test "interval conversion: [2]f64 to ContinuousInterval"
{
    const ser: SerializableContinuousInterval = .{ 2.0, 5.5 };

    const interval = serializable_to_interval(ser);

    try std.testing.expectEqual(@as(f64, 2.0), interval.start.as(f64));
    try std.testing.expectEqual(@as(f64, 5.5), interval.end.as(f64));
}

test "interval conversion: optional round-trip"
{
    const maybe_interval: ?opentime.ContinuousInterval = .{
        .start = opentime.Ordinate.init(0.0),
        .end = opentime.Ordinate.init(1.0),
    };

    const ser = optional_interval_to_serializable(maybe_interval);
    try std.testing.expect(ser != null);
    try std.testing.expectEqual(@as(f64, 0.0), ser.?[0]);
    try std.testing.expectEqual(@as(f64, 1.0), ser.?[1]);

    const back = serializable_to_optional_interval(ser);
    try std.testing.expect(back != null);
    try std.testing.expectEqual(@as(f64, 0.0), back.?.start.as(f64));
    try std.testing.expectEqual(@as(f64, 1.0), back.?.end.as(f64));
}

test "interval conversion: null optional"
{
    const maybe_interval: ?opentime.ContinuousInterval = null;
    const ser = optional_interval_to_serializable(maybe_interval);
    try std.testing.expect(ser == null);

    const back = serializable_to_optional_interval(null);
    try std.testing.expect(back == null);
}

test "clip serialization: round-trip"
{
    const allocator = std.testing.allocator;

    // Create a test clip
    const clip = schema.Clip{
        .maybe_name = "TestClip",
        .maybe_bounds_s = .{
            .start = opentime.Ordinate.init(1.0),
            .end = opentime.Ordinate.init(5.0),
        },
        .media = .{
            .data_reference = .{
                .uri = .{ .target_uri = "file:///test.mov" },
            },
            .maybe_bounds_s = .{
                .start = opentime.Ordinate.init(0.0),
                .end = opentime.Ordinate.init(10.0),
            },
            .domain = .picture,
            .maybe_discrete_partition = null,
            .interpolating = .snap,
        },
    };

    // Convert to serializable
    const ser_clip = try clip_to_serializable(allocator, clip);
    defer allocator.free(ser_clip.name.?);
    defer allocator.free(ser_clip.media.data_reference.uri.target_uri);

    // Verify serialized values
    try std.testing.expectEqualStrings("TestClip", ser_clip.name.?);
    try std.testing.expectEqual(@as(f64, 1.0), ser_clip.bounds_s.?[0]);
    try std.testing.expectEqual(@as(f64, 5.0), ser_clip.bounds_s.?[1]);

    // Convert back
    const clip_ptr = try serializable_to_clip(allocator, ser_clip);
    defer allocator.destroy(clip_ptr);
    defer allocator.free(clip_ptr.maybe_name.?);
    defer allocator.free(clip_ptr.media.data_reference.uri.target_uri);

    // Verify round-trip
    try std.testing.expectEqualStrings("TestClip", clip_ptr.maybe_name.?);
    try std.testing.expectEqual(@as(f64, 1.0), clip_ptr.maybe_bounds_s.?.start.as(f64));
    try std.testing.expectEqual(@as(f64, 5.0), clip_ptr.maybe_bounds_s.?.end.as(f64));
}

test "gap serialization: round-trip"
{
    const allocator = std.testing.allocator;

    // Create a test gap
    const gap = schema.Gap{
        .maybe_name = "TestGap",
        .bounds_s = .{
            .start = opentime.Ordinate.init(2.5),
            .end = opentime.Ordinate.init(7.5),
        },
    };

    // Convert to serializable
    const ser_gap = try gap_to_serializable(allocator, gap);
    defer allocator.free(ser_gap.name.?);

    // Verify serialized values
    try std.testing.expectEqualStrings("TestGap", ser_gap.name.?);
    try std.testing.expectEqual(2.5, ser_gap.bounds_s[0]);
    try std.testing.expectEqual(7.5, ser_gap.bounds_s[1]);

    // Convert back
    const gap_ptr = try serializable_to_gap(allocator, ser_gap);
    defer allocator.destroy(gap_ptr);
    defer allocator.free(gap_ptr.maybe_name.?);

    // Verify round-trip
    try std.testing.expectEqualStrings("TestGap", gap_ptr.maybe_name.?);
    try std.testing.expectEqual(2.5, gap_ptr.bounds_s.start.as(f64));
    try std.testing.expectEqual(7.5, gap_ptr.bounds_s.end.as(f64));
}

test "timeline serialization: ziggy round-trip"
{
    const allocator = std.testing.allocator;

    // Create test timeline with children
    var timeline = schema.Timeline{
        .maybe_name = "TestTimeline",
        .tracks = .{
            .maybe_name = null,
            .children = &.{},
        },
        .discrete_space_partitions = .{
            .presentation = .{
                .picture = null,
                .audio = null,
            },
        },
    };

    // Serialize to ziggy format
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    try serialize_timeline(
        &timeline,
        allocator,
        buffer.writer(),
        null,
    );

    // Add null terminator for ziggy
    try buffer.append(0);
    const source: [:0]const u8 = buffer.items[0 .. buffer.items.len - 1 :0];

    // Deserialize back
    const loaded_timeline = try deserialize_timeline(
        allocator,
        source,
    );
    defer loaded_timeline.deinit(allocator);

    // Verify
    try std.testing.expectEqualStrings(
        "TestTimeline",
        loaded_timeline.maybe_name.?,
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        loaded_timeline.tracks.children.len,
    );
}
