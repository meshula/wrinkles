//! Serialization layer for OTIO schema types using tla format.
//!
//! This module provides serializable variants of schema types that can be
//! used with the ziggy serialization library. The main challenges addressed:
//! - Converting pointer-based CompositionItemHandle to inline tagged unions
//! - Copying strings for arena-friendly memory management
//! - Serializing complex Topology structures
//!
//! Usage:
//!   serialize_timeline() - Write Timeline to tla format
//!   deserialize_timeline() - Read tla format back to Timeline

const std = @import("std");

const ziggy = @import("ziggy");

const opentime = @import("opentime");
const sampling = @import("sampling");
const topology_m = @import("topology");
const curve = @import("curve");
const string = @import("string_stuff");

const schema = @import("../schema.zig");
const domain_mod = @import("../domain.zig");

const versioning = @import("versioning.zig");
const legacy_json = @import("legacy_json.zig");
const bundle_utils = @import("bundle_utils.zig");
const binary = @import("binary.zig");
const bundle = @import("bundle.zig");
const adapter = @import("adapter.zig");

/// Write a Timeline to a writer in the specified format.
/// Converts to serializable format internally.
fn write_timeline_to_writer(
    allocator: std.mem.Allocator,
    timeline: *schema.Timeline,
    format: FileFormat,
    metadata_mode: adapter.WriteOptions.MetadataMode,
    writer: anytype,
) !void
{
    var ser_timeline: SerializableTimeline = try .from(allocator, timeline);
    defer ser_timeline.deinit(allocator);

    try write_serializable_to_writer(
        allocator,
        ser_timeline,
        format,
        metadata_mode,
        writer,
    );
}

// Re-export curve control point for convenience
const CurveControlPoint = curve.ControlPoint;

/// Marker for OTIO JSON source (version 0)
const OTIO_JSON_VERSION: u32 = 0;

// ----------------------------------------------------------------------------
// Serializable Type Definitions
// ----------------------------------------------------------------------------

/// Serializable variant of ContinuousInterval as [start, end]
pub const SerializableContinuousInterval = [2]f64;
pub const SerializableDiscreteInterval = [2]i64;

/// Bounds can be either continuous (time in seconds) or discrete (sample
/// indices)
pub const SerializableBounds = union(enum) {
    continuous: SerializableContinuousInterval,
    discrete: SerializableDiscreteInterval,

    /// Convert ContinuousInterval to Serializble form `BoundsWritePolicy`.
    /// Bounds can be serialized as either continuous or discrete, although the
    /// API expresses everything in continuous intervals.
    pub fn from(
        maybe_interval: ?opentime.ContinuousInterval,
        maybe_discrete_partition: ?sampling.SampleIndexGenerator,
        policy: schema.BoundsWritePolicy,
    ) error{DiscretePartitionRequired}!?SerializableBounds 
    {
        const interval = maybe_interval orelse return null;

        const use_discrete = switch (policy) {
            .automatic => maybe_discrete_partition != null,
            .discrete => true,
            .continuous => false,
        };

        if (use_discrete) 
        {
            const sig = (
                maybe_discrete_partition 
                orelse return error.DiscretePartitionRequired
            );
            const start_index = sampling.project_instantaneous_cd(
                sig,
                interval.start,
            );
            const end_index = sampling.project_instantaneous_cd(
                sig,
                interval.end,
            );
            return .{ .discrete = .{start_index, end_index} };
        } 
        else 
        {
            return .{
                .continuous = .{
                    interval.start.as(f64),
                    interval.end.as(f64),
                },
            };
        }
    }
};

/// Serializable variant of AffineTransform1D with unboxed ordinates
pub const SerializableAffineTransform1D = struct {
    offset: f64,
    scale: f64,
};

/// Serializable variant of ControlPoint as [in, out]
pub const SerializableControlPoint = [2]f64;

/// Serializable variant of RateSpecifier
/// Integer holds a single integer, Rational holds { .num, .den }
pub const SerializableRateSpecifier = union(enum) {
    Integer: u32,
    Rational: struct { num: u32, den: u32 },

    pub fn from(
        rate: sampling.RateSpecifier,
    ) SerializableRateSpecifier 
    {
        return switch (rate) {
            .Integer => |val| .{ .Integer = val },
            .Rational => |r| .{
                .Rational = .{
                    .num = r.num,
                    .den = r.den,
                },
            },
        };
    }
};

/// Serializable variant of SampleIndexGenerator
pub const SerializableSampleIndexGenerator = struct {
    sample_rate_hz: SerializableRateSpecifier,
    start_index: i64 = 0,

    pub fn from(
        maybe_sig: ?sampling.SampleIndexGenerator
    ) ?SerializableSampleIndexGenerator 
    {
        return (
            if (maybe_sig) 
                |sig| 
            .{
                .sample_rate_hz = .from(sig.sample_rate_hz),
                .start_index = sig.start_index,
            }
            else null
        );
    }
};

/// Serializable variant of Domain
pub const SerializableDomain = union(enum) {
    time: struct {},
    picture: struct {},
    audio: struct {},
    metadata: struct {},
    other: struct { name: []const u8 },

    pub fn from(
        allocator: std.mem.Allocator,
        domain: domain_mod.Domain
    ) !SerializableDomain 
    {
        return switch (domain) {
            .time => .{ .time = .{} },
            .picture => .{ .picture = .{} },
            .audio => .{ .audio = .{} },
            .metadata => .{ .metadata = .{} },
            .other => |s| .{
                .other = .{
                    .name = try allocator.dupe(u8, s),
                },
            },
        };
    }

    /// Free memory owned by the SerializableDomain.
    pub fn deinit(
        self: @This(),
        allocator: std.mem.Allocator,
    ) void
    {
        switch (self) {
            .other => |o| allocator.free(o.name),
            else => {},
        }
    }
};

/// Serializable variant of MediaDataReference
pub const SerializableMediaDataReference = union(enum) {
    uri: SerializableURIReference,
    signal: SerializableSignalReference,
    image_sequence: SerializableImageSequenceReference,
    null: struct {},

    pub fn from(
        allocator: std.mem.Allocator,
        ref: schema.MediaDataReference,
    ) !SerializableMediaDataReference
    {
        return switch (ref) {
            .uri => |uri_ref| .{
                .uri = .{
                    .target_uri = try allocator.dupe(
                        u8,
                        uri_ref.target_uri,
                    ),
                },
            },
            .signal => |sig_ref| .{
                .signal = .{
                    .signal_generator = SerializableSignalGenerator.from(
                        sig_ref.signal_generator,
                    ),
                },
            },
            .image_sequence => |img_seq| .{
                .image_sequence = .{
                    .target_url_base = try allocator.dupe(
                        u8,
                        img_seq.target_url_base,
                    ),
                    .name_prefix = try allocator.dupe(
                        u8,
                        img_seq.name_prefix,
                    ),
                    .name_suffix = try allocator.dupe(
                        u8,
                        img_seq.name_suffix,
                    ),
                    .frame_zero_padding = img_seq.frame_zero_padding,
                    .missing_frame_policy = try allocator.dupe(
                        u8,
                        @tagName(img_seq.missing_frame_policy)
                    ),
                },
            },
            .null => .null,
        };
    }

    /// Free memory owned by the SerializableMediaDataReference.
    pub fn deinit(
        self: @This(),
        allocator: std.mem.Allocator,
    ) void
    {
        switch (self) {
            .uri => |uri_ref| allocator.free(
                uri_ref.target_uri,
            ),
            .image_sequence => |img_seq| img_seq.deinit(
                allocator,
            ),
            .signal, .null => {},
        }
    }
};

pub const SerializableURIReference = struct {
    target_uri: []const u8,
};

pub const SerializableSignalReference = struct {
    signal_generator: SerializableSignalGenerator,
};

pub const SerializableImageSequenceReference = struct {
    target_url_base: []const u8,
    name_prefix: []const u8 = "",
    name_suffix: []const u8 = "",
    frame_zero_padding: u8 = 0,
    missing_frame_policy: []const u8 = "error",

    pub fn deinit(
        self: @This(),
        allocator: std.mem.Allocator,
    ) void
    {
        allocator.free(self.target_url_base);
        allocator.free(self.name_prefix);
        allocator.free(self.name_suffix);
        allocator.free(self.missing_frame_policy);
    }
};

pub const SerializableSignalGenerator = union(enum) {
    sine: struct { frequency_hz: f64 },
    linear_ramp: struct {},

    pub fn from(
        gen: sampling.SignalGenerator,
    ) SerializableSignalGenerator
    {
        return switch (gen.signal) {
            .sine => .{
                .sine = .{
                    .frequency_hz = @floatFromInt(gen.frequency_hz),
                }
            },
            .ramp => .{ .linear_ramp = .{} },
        };
    }
};

/// Serializable variant of MediaReference
pub const SerializableMediaReference = struct {
    data_reference: SerializableMediaDataReference,
    bounds_s: ?SerializableBounds = null,
    domain: SerializableDomain,
    discrete_partition: ?SerializableSampleIndexGenerator = null,
    interpolating: ?schema.ResamplingBehavior = null,

    pub fn from(
        allocator: std.mem.Allocator,
        ref: schema.MediaReference,
    ) !SerializableMediaReference
    {
        return .{
            .data_reference = try SerializableMediaDataReference.from(
                allocator,
                ref.data_reference,
            ),
            .bounds_s = try SerializableBounds.from(
                ref.maybe_bounds_s,
                ref.maybe_discrete_partition,
                ref.bounds_write_policy,
            ),
            .domain = try SerializableDomain.from(
                allocator,
                ref.domain,
            ),
            .discrete_partition = SerializableSampleIndexGenerator.from(
                ref.maybe_discrete_partition,
            ),
            .interpolating = (
                if (ref.interpolating == .default_from_domain) null 
                else ref.interpolating
            ),
        };
    }

    /// Free memory owned by the SerializableMediaReference.
    pub fn deinit(
        self: @This(),
        allocator: std.mem.Allocator,
    ) void
    {
        self.data_reference.deinit(allocator);
        self.domain.deinit(allocator);
    }
};

/// Serializable variant of Clip
pub const SerializableClip = struct {
    name: []const u8 = "",
    bounds_s: ?SerializableBounds = null,
    media: SerializableMediaReference,
    /// Wyhash key referencing an entry in the Timeline's metadata_map (16-char hex string)
    metadata_hash: ?[]const u8 = null,
    markers: []SerializableMarker = &.{},

    pub fn from(
        allocator: std.mem.Allocator,
        clip: schema.Clip,
        maybe_meta_ctx: ?*MetadataContext,
    ) !SerializableClip
    {
        // Handle metadata if present and context provided
        const metadata_hash: ?[]const u8 = (
            if (clip.maybe_metadata_json) |json_meta|
                if (maybe_meta_ctx) |meta_ctx|
                    try meta_ctx.add_metadata(json_meta)
                else null
            else null
        );

        return .{
            .name = try allocator.dupe(u8, clip.name),
            .bounds_s = try SerializableBounds.from(
                clip.maybe_bounds_s,
                clip.media.maybe_discrete_partition,
                clip.bounds_write_policy,
            ),
            .media = try SerializableMediaReference.from(
                allocator,
                clip.media,
            ),
            .metadata_hash = metadata_hash,
            .markers = try SerializableMarker.from_slice(
                allocator,
                clip.markers,
            ),
        };
    }

    pub fn deinit(
        self: @This(),
        allocator: std.mem.Allocator,
    ) void
    {
        allocator.free(self.name);
        if (self.metadata_hash) |hash| allocator.free(hash);
        self.media.deinit(allocator);
        SerializableMarker.deinit_slice(self.markers, allocator);
    }
};

/// Serializable variant of Clip with inline metadata (for --inline-metadata output)
pub const SerializableClipInlineMetadata = struct {
    name: []const u8 = "",
    bounds_s: ?SerializableBounds = null,
    media: SerializableMediaReference,
    /// Metadata stored inline instead of by hash reference
    metadata: ?MetadataValue = null,
};

/// Serializable variant of Clip with no metadata (for --no-metadata output)
pub const SerializableClipNoMetadata = struct {
    name: []const u8 = "",
    bounds_s: ?SerializableBounds = null,
    media: SerializableMediaReference,
};

/// Serializable variant of Gap
pub const SerializableGap = struct {
    name: []const u8 = "",
    bounds_s: SerializableContinuousInterval,
    markers: []SerializableMarker = &.{},

    pub fn from(
        allocator: std.mem.Allocator,
        gap: schema.Gap,
    ) !SerializableGap
    {
        return .{
            .name = try allocator.dupe(u8, gap.name),
            .bounds_s = .{
                gap.bounds_s.start.as(f64),
                gap.bounds_s.end.as(f64),
            },
            .markers = try SerializableMarker.from_slice(
                allocator,
                gap.markers,
            ),
        };
    }

    pub fn deinit(
        self: @This(),
        allocator: std.mem.Allocator,
    ) void
    {
        allocator.free(self.name);
        SerializableMarker.deinit_slice(self.markers, allocator);
    }
};

/// Serializable variant of Marker
pub const SerializableMarker = struct {
    name: []const u8 = "",
    marked_range: SerializableContinuousInterval,
    color: []const u8,
    comment: []const u8 = "",

    pub fn from(
        allocator: std.mem.Allocator,
        marker: schema.Marker,
    ) !SerializableMarker
    {
        return .{
            .name = try allocator.dupe(u8, marker.name),
            .marked_range = .{ marker.marked_range.start.as(f64), marker.marked_range.end.as(f64) },
            .color = try allocator.dupe(u8, @tagName(marker.color)),
            .comment = try allocator.dupe(u8, marker.comment),
        };
    }

    pub fn from_slice(
        allocator: std.mem.Allocator,
        markers: []schema.Marker,
    ) ![]SerializableMarker
    {
        if (markers.len == 0) return &.{};
        var ser_markers = try allocator.alloc(SerializableMarker, markers.len);
        for (markers, 0..)
            |marker, i|
        {
            ser_markers[i] = try .from(allocator, marker);
        }
        return ser_markers;
    }

    pub fn deinit(
        self: @This(),
        allocator: std.mem.Allocator,
    ) void
    {
        if (self.name.len > 0)
        {
            allocator.free(self.name);
        }
        allocator.free(self.color);
        if (self.comment.len > 0)
        {
            allocator.free(self.comment);
        }
    }

    /// Deinitialize a slice of markers and free the slice itself.
    pub fn deinit_slice(
        markers: []SerializableMarker,
        allocator: std.mem.Allocator,
    ) void
    {
        for (markers) 
            |marker| 
        {
            marker.deinit(allocator);
        }
        allocator.free(markers);
    }
};

/// Serializable variant of Mapping
pub const SerializableMapping = union(enum) {
    affine: SerializableMappingAffine,
    linear: SerializableMappingLinear,
    empty: struct {},

    pub fn from(
        allocator: std.mem.Allocator,
        mapping: topology_m.mapping.Mapping,
    ) !SerializableMapping
    {
        return switch (mapping) {
            .affine => |aff| .{
                .affine = .{
                    .input_bounds_val = .{ aff.input_bounds_val.start.as(f64), aff.input_bounds_val.end.as(f64) },
                    .input_to_output_xform = .{
                        .offset = aff.input_to_output_xform.offset.as(f64),
                        .scale = aff.input_to_output_xform.scale.as(f64),
                    },
                },
            },
            .linear => |lin| blk: {
                const knots = try allocator.alloc(SerializableControlPoint, lin.input_to_output_curve.knots.len);
                for (lin.input_to_output_curve.knots, 0..)
                    |knot, i|
                {
                    knots[i] = .{ knot.in.as(f64), knot.out.as(f64) };
                }
                const input_extents = lin.input_to_output_curve.extents_input() orelse {
                    break :blk .{ .linear = .{ .input_bounds_val = .{ 0.0, 0.0 }, .knots = knots } };
                };
                break :blk .{
                    .linear = .{
                        .input_bounds_val = .{ input_extents.start.as(f64), input_extents.end.as(f64) },
                        .knots = knots,
                    },
                };
            },
            .empty => .{ .empty = .{} },
        };
    }

    pub fn deinit(self: @This(), allocator: std.mem.Allocator) void {
        switch (self) {
            .linear => |lin| {
                allocator.free(lin.knots);
            },
            .affine, .empty => {},
        }
    }
};

pub const SerializableMappingAffine = struct {
    input_bounds_val: SerializableContinuousInterval,
    input_to_output_xform: SerializableAffineTransform1D,
};

pub const SerializableMappingLinear = struct {
    input_bounds_val: SerializableContinuousInterval,
    knots: []SerializableControlPoint,
};

/// Serializable variant of Topology
pub const SerializableTopology = struct {
    mappings: []SerializableMapping,

    pub fn from(
        allocator: std.mem.Allocator,
        topo: topology_m.Topology,
    ) !SerializableTopology
    {
        const ser_mappings = try allocator.alloc(SerializableMapping, topo.mappings.len);
        for (topo.mappings, 0..)
            |mapping, i|
        {
            ser_mappings[i] = try SerializableMapping.from(allocator, mapping);
        }
        return .{ .mappings = ser_mappings };
    }

    pub fn deinit(self: @This(), allocator: std.mem.Allocator) void {
        for (self.mappings) 
            |mapping| 
        {
            mapping.deinit(allocator);
        }
        allocator.free(self.mappings);
    }
};

/// Forward declarations for recursive types
pub const SerializableComposable = union(enum) {
    clip: SerializableClip,
    gap: SerializableGap,
    track: SerializableTrack,
    stack: SerializableStack,
    warp: SerializableWarp,
    transition: SerializableTransition,

    pub fn from(
        allocator: std.mem.Allocator,
        handle: schema.references.CompositionItemHandle,
        maybe_meta_ctx: ?*MetadataContext,
    ) error{OutOfMemory, DiscretePartitionRequired}!*SerializableComposable
    {
        const result_ptr = try allocator.create(SerializableComposable);
        result_ptr.* = switch (handle) {
            .clip => |clip_ptr| .{ .clip = try SerializableClip.from(allocator, clip_ptr.*, maybe_meta_ctx) },
            .gap => |gap_ptr| .{ .gap = try SerializableGap.from(allocator, gap_ptr.*) },
            .track => |track_ptr| .{ .track = try SerializableTrack.from(allocator, track_ptr.*, maybe_meta_ctx) },
            .stack => |stack_ptr| .{ .stack = try SerializableStack.from(allocator, stack_ptr.*, maybe_meta_ctx) },
            .warp => |warp_ptr| .{ .warp = try SerializableWarp.from(allocator, warp_ptr.*, maybe_meta_ctx) },
            .transition => |trans_ptr| .{ .transition = try SerializableTransition.from(allocator, trans_ptr.*, maybe_meta_ctx) },
            .timeline, .collection => unreachable, // Timeline/Collection are not composable children
        };
        return result_ptr;
    }

    pub fn deinit(
        self: *const @This(),
        allocator: std.mem.Allocator,
    ) void
    {
        switch (self.*) {
            inline else => |thing| thing.deinit(allocator),
        }
    }
};

/// Serializable variant of Warp
pub const SerializableWarp = struct {
    name: []const u8 = "",
    child: *SerializableComposable,
    transform: SerializableTopology,

    pub fn from(
        allocator: std.mem.Allocator,
        warp: schema.Warp,
        maybe_meta_ctx: ?*MetadataContext,
    ) !SerializableWarp
    {
        return .{
            .name = try allocator.dupe(u8, warp.name),
            .child = try SerializableComposable.from(allocator, warp.child, maybe_meta_ctx),
            .transform = try SerializableTopology.from(allocator, warp.transform),
        };
    }

    pub fn deinit(
        self: @This(),
        allocator: std.mem.Allocator,
    ) void
    {
        allocator.free(self.name);
        self.child.deinit(allocator);
        allocator.destroy(self.child);
        self.transform.deinit(allocator);
    }
};

/// Serializable variant of Stack
pub const SerializableStack = struct {
    name: []const u8 = "",
    bounds_s: ?SerializableBounds = null,
    children: []SerializableComposable,
    markers: []SerializableMarker = &.{},

    pub fn from(
        allocator: std.mem.Allocator,
        stack: schema.Stack,
        maybe_meta_ctx: ?*MetadataContext,
    ) !SerializableStack
    {
        const ser_children = try allocator.alloc(
            SerializableComposable,
            stack.children.len,
        );
        for (stack.children, 0..)
            |child, i|
        {
            ser_children[i] = (
                try SerializableComposable.from(
                    allocator,
                    child,
                    maybe_meta_ctx
                )
            ).*;
        }
        return .{
            .name = try allocator.dupe(u8, stack.name),
            .children = ser_children,
            .markers = try SerializableMarker.from_slice(
                allocator,
                stack.markers,
            ),
        };
    }

    pub fn deinit(
        self: @This(),
        allocator: std.mem.Allocator,
    ) void
    {
        allocator.free(self.name);
        for (self.children)
            |*child|
        {
            child.deinit(allocator);
        }
        allocator.free(self.children);
        SerializableMarker.deinit_slice(self.markers, allocator);
    }
};

/// Serializable variant of Track
pub const SerializableTrack = struct {
    name: []const u8 = "",
    bounds_s: ?SerializableBounds = null,
    children: []SerializableComposable,
    markers: []SerializableMarker = &.{},

    pub fn from(
        allocator: std.mem.Allocator,
        track: schema.Track,
        maybe_meta_ctx: ?*MetadataContext,
    ) !SerializableTrack
    {
        const ser_children = try allocator.alloc(SerializableComposable, track.children.len);
        for (track.children, 0..)
            |child, i|
        {
            ser_children[i] = (try SerializableComposable.from(allocator, child, maybe_meta_ctx)).*;
        }
        return .{
            .name = try allocator.dupe(u8, track.name),
            .children = ser_children,
            .markers = try SerializableMarker.from_slice(allocator, track.markers),
        };
    }

    pub fn deinit(
        self: @This(),
        allocator: std.mem.Allocator,
    ) void
    {
        allocator.free(self.name);
        for (self.children)
            |*child|
        {
            child.deinit(allocator);
        }
        allocator.free(self.children);
        SerializableMarker.deinit_slice(self.markers, allocator);
    }
};

/// Serializable variant of Transition
pub const SerializableTransition = struct {
    name: []const u8 = "",
    container: SerializableStack,
    kind: []const u8,
    bounds_s: ?SerializableContinuousInterval = null,

    pub fn from(
        allocator: std.mem.Allocator,
        transition: schema.Transition,
        maybe_meta_ctx: ?*MetadataContext,
    ) !SerializableTransition
    {
        const bounds = if (transition.maybe_bounds_s)
            |b|
            [2]f64{ b.start.as(f64), b.end.as(f64) }
        else
            null;

        return .{
            .name = try allocator.dupe(u8, transition.name),
            .container = try SerializableStack.from(allocator, transition.container, maybe_meta_ctx),
            .kind = try allocator.dupe(u8, transition.kind),
            .bounds_s = bounds,
        };
    }

    pub fn deinit(
        self: @This(),
        allocator: std.mem.Allocator,
    ) void
    {
        allocator.free(self.name);
        allocator.free(self.kind);
        self.container.deinit(allocator);
    }
};

/// Serializable variant of DiscretePartitionDomainMap
pub const SerializableDiscretePartitionDomainMap = struct {
    picture: ?SerializableSampleIndexGenerator = null,
    audio: ?SerializableSampleIndexGenerator = null,
};

/// Metadata value type using ziggy's dynamic system for flexible nested data
pub const MetadataValue = ziggy.dynamic.Value;

/// Metadata map type - maps string keys to dynamic values
pub const MetadataMap = ziggy.dynamic.Map(MetadataValue);

/// Recursively free all strings and arrays in a MetadataValue.
/// ziggy's parser allocates strings during parsing, and this function
/// ensures they are properly freed.
fn deinit_metadata_value(
    allocator: std.mem.Allocator,
    value: MetadataValue,
) void
{
    switch (value) {
        .kv => |kv| {
            // Copy the kv to mutable to deinit its fields
            var mutable_kv = kv;
            deinit_metadata_map_contents(allocator, &mutable_kv);
        },
        .array => |arr| {
            for (arr)
                |item|
            {
                deinit_metadata_value(allocator, item);
            }
            allocator.free(arr);
        },
        .bytes => |b| allocator.free(b),
        .tag => |t| {
            // Tag name is not allocated (it's a slice into source), but bytes might be
            allocator.free(t.bytes);
        },
        .integer, .float, .bool, .null => {}, // No allocations
    }
}

/// Free contents of a MetadataMap (keys, values, and nested structures).
fn deinit_metadata_map_contents(
    allocator: std.mem.Allocator,
    mm: *MetadataMap,
) void
{
    var iter = mm.fields.iterator();
    while (iter.next())
        |entry|
    {
        // Free the key string
        allocator.free(entry.key_ptr.*);
        // Recursively free the value
        deinit_metadata_value(allocator, entry.value_ptr.*);
    }
    mm.fields.deinit(allocator);
}

/// Free a MetadataMap and all its contents.
fn deinit_metadata_map(
    allocator: std.mem.Allocator,
    mm: *MetadataMap,
) void
{
    deinit_metadata_map_contents(allocator, mm);
}

/// Serializable variant of Timeline (root type)
pub const SerializableTimeline = struct {
    pub const schema_name: []const u8 = "Timeline";

    schema_version: u32 = versioning.current_version("Timeline"),
    name: []const u8 = "",
    children: []SerializableComposable,
    presentation_space_discrete_partitions: SerializableDiscretePartitionDomainMap,
    /// Maps metadata hash keys to their metadata dictionaries.
    /// Optional so empty maps can be omitted from serialization.
    metadata_map: ?MetadataMap = null,
    markers: []SerializableMarker = &.{},

    pub fn from(
        allocator: std.mem.Allocator,
        timeline: *schema.Timeline,
    ) !SerializableTimeline
    {
        // Create metadata map and context for accumulating clip metadata
        var metadata_map: MetadataMap = .{};
        var meta_ctx = MetadataContext{
            .allocator = allocator,
            .metadata_map = &metadata_map,
        };

        // Convert tracks.children directly to timeline.children
        const ser_children = try allocator.alloc(SerializableComposable, timeline.tracks.children.len);
        for (timeline.tracks.children, 0..)
            |child, i|
        {
            ser_children[i] = (try SerializableComposable.from(allocator, child, &meta_ctx)).*;
        }

        // Merge timeline-level metadata_map (std.json.Value) into the
        // accumulated MetadataMap so it roundtrips through serialization.
        if (timeline.metadata_map)
            |json_val|
        {
            if (json_val == .object) {
                var obj_iter = json_val.object.iterator();
                while (obj_iter.next())
                    |entry|
                {
                    const meta_val = try meta_ctx.json_to_metadata_value(
                        entry.value_ptr.*,
                    );
                    const duped_key = try allocator.dupe(
                        u8,
                        entry.key_ptr.*,
                    );
                    try metadata_map.fields.put(
                        allocator,
                        duped_key,
                        meta_val,
                    );
                }
            }
        }

        return .{
            .name = try allocator.dupe(u8, timeline.name),
            .children = ser_children,
            .presentation_space_discrete_partitions = .{
                .picture = .from(
                    timeline.discrete_space_partitions.presentation.picture
                ),
                .audio = .from(
                    timeline.discrete_space_partitions.presentation.audio
                ),
            },
            .metadata_map = if (metadata_map.fields.count() > 0) metadata_map else null,
            .markers = try SerializableMarker.from_slice(allocator, timeline.markers),
        };
    }

    pub fn deinit(
        self: *@This(),
        allocator: std.mem.Allocator,
    ) void
    {
        allocator.free(self.name);

        for (self.children)
            |*child|
        {
            child.deinit(allocator);
        }
        allocator.free(self.children);

        // Free metadata map including all nested keys and values
        if (self.metadata_map)
            |*mm|
        {
            deinit_metadata_map(allocator, mm);
        }

        // Free markers
        SerializableMarker.deinit_slice(self.markers, allocator);
    }
};

/// Variant of SerializableTimeline that skips metadata_map during parsing.
/// Used when content_filter == .all_except_metadata.
/// This uses ziggy's skip_fields feature to completely skip parsing the
/// metadata_map field, providing significant performance gains for large files.
pub const SerializableTimelineNoMetadata = struct {
    pub const schema_name: []const u8 = "Timeline";

    /// Tell ziggy parser to skip the metadata_map field entirely
    pub const ziggy_options = .{
        .skip_fields = &[_]std.meta.FieldEnum(@This()){ .metadata_map },
    };

    schema_version: u32 = versioning.current_version("Timeline"),
    name: []const u8 = "",
    children: []SerializableComposable,
    presentation_space_discrete_partitions: SerializableDiscretePartitionDomainMap,
    /// This field will be skipped during parsing (always null when using this
    /// type)
    metadata_map: ?MetadataMap = null,
    markers: []SerializableMarker = &.{},

    pub fn deinit(
        self: *@This(),
        allocator: std.mem.Allocator,
    ) void
    {
        allocator.free(self.name);

        for (self.children)
            |*child|
        {
            child.deinit(allocator);
        }
        allocator.free(self.children);

        for (self.markers)
            |marker|
        {
            marker.deinit(allocator);
        }
        allocator.free(self.markers);

        // metadata_map is always null when using this type
    }

    /// Convert to SerializableTimeline for use with existing code
    pub fn to_serializable_timeline(
        self: @This(),
    ) SerializableTimeline
    {
        return .{
            .schema_version = self.schema_version,
            .name = self.name,
            .children = self.children,
            .presentation_space_discrete_partitions = (
                self.presentation_space_discrete_partitions
            ),
            .metadata_map = null, // Always null
            .markers = self.markers,
        };
    }
};

// ----------------------------------------------------------------------------
// Collection Types
// ----------------------------------------------------------------------------
// A Collection groups related items (timelines, clips, etc.) without implying
// any temporal relationship between them. Unlike a Timeline which arranges
// children with defined timing, a Collection is purely organizational.

/// Items that can be direct children of a Collection.
/// Collections can contain timelines and other composables.
pub const SerializableCollectionItem = union(enum) {
    timeline: SerializableTimeline,
    track: SerializableTrack,
    stack: SerializableStack,
    clip: SerializableClip,
    gap: SerializableGap,
    warp: SerializableWarp,
    transition: SerializableTransition,

    pub fn deinit(
        self: *const @This(),
        allocator: std.mem.Allocator,
    ) void
    {
        switch (self.*) {
            .timeline => |*tl| {
                var mutable_tl = @constCast(tl);
                mutable_tl.deinit(allocator);
            },
            inline else => |thing| thing.deinit(allocator),
        }
    }
};

/// Serializable variant of Collection (root type for .tlca/.tlcb files)
pub const SerializableCollection = struct {
    pub const schema_name: []const u8 = "Collection";

    schema_version: u32 = 1,
    name: []const u8 = "",
    description: []const u8 = "",
    children: []SerializableCollectionItem,
    metadata_map: ?MetadataMap = null,

    pub fn deinit(
        self: *@This(),
        allocator: std.mem.Allocator,
    ) void
    {
        allocator.free(self.name);
        allocator.free(self.description);

        for (self.children)
            |*child|
        {
            child.deinit(allocator);
        }
        allocator.free(self.children);

        if (self.metadata_map)
            |*mm|
        {
            deinit_metadata_map(allocator, mm);
        }
    }
};

// ----------------------------------------------------------------------------
// Output-only types for metadata mode variants
// ----------------------------------------------------------------------------
// These types are used only for serialization output with --no-metadata
// and --inline-metadata options. They are NOT used for parsing.

/// Composable union for inline metadata output
pub const SerializableComposableInlineMetadata = union(enum) {
    clip: SerializableClipInlineMetadata,
    gap: SerializableGap,
    track: SerializableTrackInlineMetadata,
    stack: SerializableStackInlineMetadata,
    warp: SerializableWarpInlineMetadata,
    transition: SerializableTransitionInlineMetadata,
};

/// Composable union for no metadata output
pub const SerializableComposableNoMetadata = union(enum) {
    clip: SerializableClipNoMetadata,
    gap: SerializableGap,
    track: SerializableTrackNoMetadata,
    stack: SerializableStackNoMetadata,
    warp: SerializableWarpNoMetadata,
    transition: SerializableTransitionNoMetadata,
};

/// Track variant for inline metadata output
pub const SerializableTrackInlineMetadata = struct {
    name: []const u8 = "",
    bounds_s: ?SerializableBounds = null,
    children: []SerializableComposableInlineMetadata,
};

/// Track variant for no metadata output
pub const SerializableTrackNoMetadata = struct {
    name: []const u8 = "",
    bounds_s: ?SerializableBounds = null,
    children: []SerializableComposableNoMetadata,
};

/// Stack variant for inline metadata output
pub const SerializableStackInlineMetadata = struct {
    name: []const u8 = "",
    bounds_s: ?SerializableBounds = null,
    children: []SerializableComposableInlineMetadata,
};

/// Stack variant for no metadata output
pub const SerializableStackNoMetadata = struct {
    name: []const u8 = "",
    bounds_s: ?SerializableBounds = null,
    children: []SerializableComposableNoMetadata,
};

/// Warp variant for inline metadata output
pub const SerializableWarpInlineMetadata = struct {
    name: []const u8 = "",
    child: *SerializableComposableInlineMetadata,
    transform: SerializableTopology,
};

/// Warp variant for no metadata output
pub const SerializableWarpNoMetadata = struct {
    name: []const u8 = "",
    child: *SerializableComposableNoMetadata,
    transform: SerializableTopology,
};

/// Transition variant for inline metadata output
pub const SerializableTransitionInlineMetadata = struct {
    name: []const u8 = "",
    container: SerializableStackInlineMetadata,
    kind: []const u8,
    bounds_s: ?SerializableContinuousInterval = null,
};

/// Transition variant for no metadata output
pub const SerializableTransitionNoMetadata = struct {
    name: []const u8 = "",
    container: SerializableStackNoMetadata,
    kind: []const u8,
    bounds_s: ?SerializableContinuousInterval = null,
};

/// Timeline variant for inline metadata output (no metadata_map, metadata
/// inline on clips)
pub const SerializableTimelineInlineMetadata = struct {
    pub const schema_name: []const u8 = "Timeline";

    schema_version: u32 = versioning.current_version("Timeline"),
    name: []const u8 = "",
    children: []SerializableComposableInlineMetadata,
    presentation_space_discrete_partitions: SerializableDiscretePartitionDomainMap,
    // No metadata_map field - metadata is inline on clips
};

/// Timeline variant for output without any metadata
pub const SerializableTimelineStrippedMetadata = struct {
    pub const schema_name: []const u8 = "Timeline";

    schema_version: u32 = versioning.current_version("Timeline"),
    name: []const u8 = "",
    children: []SerializableComposableNoMetadata,
    presentation_space_discrete_partitions: SerializableDiscretePartitionDomainMap,
    // No metadata_map field
};

/// Collection variant for inline metadata output (no metadata_map, metadata
/// inline on clips)
pub const SerializableCollectionInlineMetadata = struct {
    pub const schema_name: []const u8 = "Collection";

    schema_version: u32 = 1,
    name: []const u8 = "",
    description: []const u8 = "",
    children: []SerializableCollectionItemInlineMetadata,
    // No metadata_map field - metadata is inline on clips
};

/// Collection variant for output without any metadata
pub const SerializableCollectionStrippedMetadata = struct {
    pub const schema_name: []const u8 = "Collection";

    schema_version: u32 = 1,
    name: []const u8 = "",
    description: []const u8 = "",
    children: []SerializableCollectionItemNoMetadata,
    // No metadata_map field
};

/// Collection item variant for inline metadata output
pub const SerializableCollectionItemInlineMetadata = union(enum) {
    timeline: SerializableTimelineInlineMetadata,
    track: SerializableTrackInlineMetadata,
    stack: SerializableStackInlineMetadata,
    clip: SerializableClipInlineMetadata,
    gap: SerializableGap,
    warp: SerializableWarpInlineMetadata,
    transition: SerializableTransitionInlineMetadata,
};

/// Collection item variant for stripped metadata output
pub const SerializableCollectionItemNoMetadata = union(enum) {
    timeline: SerializableTimelineStrippedMetadata,
    track: SerializableTrackNoMetadata,
    stack: SerializableStackNoMetadata,
    clip: SerializableClipNoMetadata,
    gap: SerializableGap,
    warp: SerializableWarpNoMetadata,
    transition: SerializableTransitionNoMetadata,
};

// ----------------------------------------------------------------------------
// Curve Library Serializable Types
// ----------------------------------------------------------------------------
// ControlPoint = [2]f64 = [in, out]
// BezierSegment = [4]ControlPoint = [p0, p1, p2, p3]

/// Serializable variant of curve.Bezier
/// Each segment is [4][2]f64 (4 control points of 2 floats each)
pub const SerializableBezierCurve = struct {
    // Array of segments, each with 4 control points
    segments: [][4]SerializableControlPoint,  
};

/// Serializable variant of curve.Linear
/// Knots are [][2]f64 (array of control points)
pub const SerializableLinearCurve = struct {
    // Array of control points
    knots: [][2]f64,  
};

// ----------------------------------------------------------------------------
// Metadata Conversion Context
// ----------------------------------------------------------------------------

/// Context for accumulating metadata during serialization.
/// Clips reference their metadata by Wyhash key, and the actual data is stored
/// in the Timeline's metadata_map.
pub const MetadataContext = struct {
    allocator: std.mem.Allocator,
    metadata_map: *MetadataMap,

    /// Convert std.json.Value to MetadataValue (ziggy dynamic value)
    pub fn json_to_metadata_value(
        self: *MetadataContext,
        json_val: std.json.Value,
    ) !MetadataValue
    {
        return switch (json_val) {
            .null => .null,
            .bool => |b| .{ .bool = b },
            .integer => |i| .{ .integer = i },
            .float => |f| .{ .float = f },
            .string => |s| .{
                .bytes = try self.allocator.dupe(u8, s) 
            },
            .array => |arr| {
                var result = try self.allocator.alloc(
                    MetadataValue,
                    arr.items.len,
                );
                for (arr.items, 0..) 
                    |item, i| 
                {
                    result[i] = try self.json_to_metadata_value(item);
                }
                return .{ .array = result };
            },
            .object => |obj| {
                var result_map: MetadataMap = .{};
                var iter = obj.iterator();
                while (iter.next()) 
                    |entry| 
                {
                    const key = try self.allocator.dupe(
                        u8,
                        entry.key_ptr.*,
                    );
                    const val = try self.json_to_metadata_value(
                        entry.value_ptr.*,
                    );
                    try result_map.fields.put(
                        self.allocator,
                        key,
                        val,
                    );
                }
                return .{ .kv = result_map };
            },
            .number_string => |s| .{ 
                .bytes = try self.allocator.dupe(u8, s) 
            },
        };
    }

    /// Recursively serialize JSON to bytes for hashing
    fn serialize_json_for_hash(
        self: *MetadataContext,
        json_val: std.json.Value,
        writer: anytype,
    ) void
    {
        switch (json_val) {
            .null => writer.writeAll("null") catch {},
            .bool => |b| writer.print("{}", .{b}) catch {},
            .integer => |i| writer.print("{}", .{i}) catch {},
            .float => |f| writer.print("{d}", .{f}) catch {},
            .string => |s| {
                writer.writeAll("\"") catch {};
                writer.writeAll(s) catch {};
                writer.writeAll("\"") catch {};
            },
            .number_string => |s| writer.writeAll(s) catch {},
            .array => |arr| {
                writer.writeAll("[") catch {};
                for (arr.items, 0..) 
                    |item, i| 
                {
                    if (i > 0) 
                    {
                        writer.writeAll(",") catch {};
                    }
                    self.serialize_json_for_hash(
                        item,
                        writer,
                    );
                }
                writer.writeAll("]") catch {};
            },
            .object => |obj| {
                writer.writeAll("{") catch {};
                var iter = obj.iterator();
                var first = true;
                while (iter.next()) 
                    |entry| 
                {
                    if (!first) 
                    {
                        writer.writeAll(",") catch {};
                    }
                    first = false;
                    writer.writeAll("\"") catch {};
                    writer.writeAll(entry.key_ptr.*) catch {};
                    writer.writeAll("\":") catch {};
                    self.serialize_json_for_hash(
                        entry.value_ptr.*,
                        writer,
                    );
                }
                writer.writeAll("}") catch {};
            },
        }
    }

    /// Add metadata to the map and return its Blake3 hash key as a hex string.
    /// If metadata with the same hash already exists, just returns the
    /// existing key.
    pub fn add_metadata(
        self: *MetadataContext,
        json_val: std.json.Value,
    ) ![]const u8
    {
        // Serialize JSON to string for hashing
        var hash_buffer: [32 * 1024]u8 = undefined;
        var stream = std.io.fixedBufferStream(
            &hash_buffer,
        );
        self.serialize_json_for_hash(
            json_val,
            stream.writer(),
        );
        const json_bytes = stream.getWritten();

        // Compute hash using Blake3 (first 8 bytes = u64)
        var hasher = std.crypto.hash.Blake3.init(.{});
        hasher.update(json_bytes);
        var hash_bytes: [8]u8 = undefined;
        hasher.final(hash_bytes[0..8]);

        // Convert first 8 bytes to u64 for consistent representation
        const hash: u64 = std.mem.readInt(u64, &hash_bytes, .big);

        // Convert to hex string (16 chars for u64)
        const hash_str = try self.allocator.alloc(u8, 16);
        const hex_chars = "0123456789abcdef";
        inline for (0..8) |i|
        {
            const byte: u8 = @truncate(hash >> @intCast((7 - i) * 8));
            hash_str[i * 2] = hex_chars[byte >> 4];
            hash_str[i * 2 + 1] = hex_chars[byte & 0x0f];
        }

        // Check if this metadata already exists
        if (self.metadata_map.fields.getKey(hash_str)) |existing_key|
        {
            // Already exists, free the duplicate key and return existing
            self.allocator.free(hash_str);
            return try self.allocator.dupe(u8, existing_key);
        }

        // Convert and store metadata
        const meta_val = try self.json_to_metadata_value(json_val);
        try self.metadata_map.fields.put(
            self.allocator,
            hash_str,
            meta_val,
        );

        return hash_str;
    }
};

/// Convert a MetadataValue (ziggy dynamic value) to std.json.Value.
/// This is the reverse of MetadataContext.json_to_metadata_value.
pub fn metadata_value_to_json(
    allocator: std.mem.Allocator,
    value: MetadataValue,
) !std.json.Value
{
    return switch (value) {
        .null => .null,
        .bool => |b| .{ .bool = b },
        .integer => |i| .{ .integer = i },
        .float => |f| .{ .float = f },
        .bytes => |s| .{ .string = try allocator.dupe(u8, s) },
        .tag => |t| .{ .string = try allocator.dupe(u8, t.bytes) },
        .array => |arr| {
            var json_arr = std.json.Array.initCapacity(
                allocator,
                arr.len,
            ) catch return error.OutOfMemory;
            for (arr)
                |item|
            {
                json_arr.appendAssumeCapacity(
                    try metadata_value_to_json(allocator, item),
                );
            }
            return .{ .array = json_arr };
        },
        .kv => |kv| {
            var json_obj = std.json.ObjectMap.init(allocator);
            var iter = kv.fields.iterator();
            while (iter.next())
                |entry|
            {
                const key = try allocator.dupe(u8, entry.key_ptr.*);
                const val = try metadata_value_to_json(
                    allocator,
                    entry.value_ptr.*,
                );
                try json_obj.put(key, val);
            }
            return .{ .object = json_obj };
        },
    };
}

/// Convert a MetadataMap to std.json.Value (object).
/// Wraps the top-level map as a JSON object.
pub fn metadata_map_to_json(
    allocator: std.mem.Allocator,
    mm: MetadataMap,
) !std.json.Value
{
    var json_obj = std.json.ObjectMap.init(allocator);
    var iter = mm.fields.iterator();
    while (iter.next())
        |entry|
    {
        const key = try allocator.dupe(u8, entry.key_ptr.*);
        const val = try metadata_value_to_json(
            allocator,
            entry.value_ptr.*,
        );
        try json_obj.put(key, val);
    }
    return .{ .object = json_obj };
}

// ----------------------------------------------------------------------------
// Hash Conversion Utilities
// ----------------------------------------------------------------------------

/// Convert a u64 hash value to a 16-character hex string.
/// Used when deserializing from TLB binary format (which stores u64) back to
/// the SerializableClip (which uses string for TLA compatibility).
pub fn hash_to_hex_string(
    allocator: std.mem.Allocator,
    hash: u64,
) ![]const u8
{
    const hex_chars = "0123456789abcdef";
    const result = try allocator.alloc(u8, 16);
    inline for (0..8) |i|
    {
        const byte: u8 = @truncate(hash >> @intCast((7 - i) * 8));
        result[i * 2] = hex_chars[byte >> 4];
        result[i * 2 + 1] = hex_chars[byte & 0x0f];
    }
    return result;
}

/// Convert a 16-character hex string to a u64 hash value.
/// Used when serializing to TLB binary format.
/// Returns null if the string is not a valid 16-character hex string.
pub fn hex_string_to_hash(hex_str: []const u8) ?u64
{
    if (hex_str.len != 16) return null;

    var result: u64 = 0;
    for (hex_str) |c|
    {
        const digit: u64 = switch (c) {
            '0'...'9' => c - '0',
            'a'...'f' => c - 'a' + 10,
            'A'...'F' => c - 'A' + 10,
            else => return null,
        };
        result = (result << 4) | digit;
    }
    return result;
}

// ----------------------------------------------------------------------------
// Helper Functions: Deserialization Conversion
// ----------------------------------------------------------------------------

fn serializable_to_rate(
    ser_rate: SerializableRateSpecifier,
) sampling.RateSpecifier
{
    return switch (ser_rate) {
        .Integer => |val| .{ .Integer = val },
        .Rational => |r| .{ .Rational = .{ .num = r.num, .den = r.den } },
    };
}

fn serializable_to_sample_index_generator(
    ser_sig: SerializableSampleIndexGenerator,
) sampling.SampleIndexGenerator
{
    return .{
        .sample_rate_hz = serializable_to_rate(ser_sig.sample_rate_hz),
        .start_index = ser_sig.start_index,
    };
}

fn serializable_to_optional_sig(
    maybe_ser: ?SerializableSampleIndexGenerator,
) ?sampling.SampleIndexGenerator
{
    return if (maybe_ser)
        |ser|
        serializable_to_sample_index_generator(ser)
    else
        null;
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
            const sig = (
                maybe_discrete_partition
                orelse return error.MissingDiscretePartition
            );

            // Convert discrete indices to continuous interval
            const start_ord = sig.ordinate_at_index(disc[0]);
            const end_ord = sig.ordinate_at_index(disc[1]);

            return .{
                .start = start_ord,
                .end = end_ord,
            };
        },
    };
}

/// Convert optional SerializableBounds to optional ContinuousInterval
fn serializable_to_optional_bounds(
    maybe_ser: ?SerializableBounds,
    maybe_discrete_partition: ?sampling.SampleIndexGenerator,
) !?opentime.ContinuousInterval
{
    if (maybe_ser)
        |ser|
    {
        return try serializable_to_bounds(
            ser,
            maybe_discrete_partition,
        );
    }
    return null;
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

/// Convert optional serializable interval to ContinuousInterval
fn serializable_to_optional_interval(
    maybe_ser: ?SerializableContinuousInterval,
) ?opentime.ContinuousInterval
{
    if (maybe_ser)
        |ser|
    {
        return serializable_to_interval(ser);
    }
    return null;
}

/// Convert SerializableMarker to schema.Marker
fn serializable_to_marker(
    allocator: std.mem.Allocator,
    ser_marker: SerializableMarker,
) !schema.Marker
{
    return .{
        .name = try allocator.dupe(u8, ser_marker.name),
        .marked_range = serializable_to_interval(
            ser_marker.marked_range,
        ),
        .color = (
            schema.MarkerColor.from_string(ser_marker.color)
            orelse .red
        ),
        .comment = try allocator.dupe(u8, ser_marker.comment),
    };
}

/// Convert array of SerializableMarker to schema.Marker
fn serializable_to_markers(
    allocator: std.mem.Allocator,
    ser_markers: []SerializableMarker,
) ![]schema.Marker
{
    if (ser_markers.len == 0) 
    {
        return try allocator.alloc(schema.Marker, 0);
    }
    var markers = try allocator.alloc(
        schema.Marker,
        ser_markers.len,
    );
    for (ser_markers, 0..) 
        |ser_marker, i| 
    {
        markers[i] = try serializable_to_marker(
            allocator,
            ser_marker,
        );
    }
    return markers;
}

// ----------------------------------------------------------------------------
// Version Upgrade Functions
// ----------------------------------------------------------------------------

/// Recursively fix transitions in a composable (add containers and kind fields)
fn fix_transitions_in_composable(
    allocator: std.mem.Allocator,
    composable: *SerializableComposable,
) !void
{
    switch (composable.*) {
        .transition => |*trans| {
            // Ensure kind field is not empty (default to "SMPTE_Dissolve")
            if (trans.kind.len == 0)
            {
                trans.kind = try allocator.dupe(u8, "SMPTE_Dissolve");
            }

            // Fix transitions in container children recursively
            for (trans.container.children)
                |*child|
            {
                try fix_transitions_in_composable(allocator, child);
            }
        },
        .track => |*track| {
            // Recursively fix transitions in track children
            for (track.children)
                |*child|
            {
                try fix_transitions_in_composable(allocator, child);
            }
        },
        .stack => |*stack| {
            // Recursively fix transitions in stack children
            for (stack.children)
                |*child|
            {
                try fix_transitions_in_composable(allocator, child);
            }
        },
        .warp => |*warp| {
            // Recursively fix transitions in warp child
            try fix_transitions_in_composable(allocator, warp.child);
        },
        .clip, .gap => {
            // Clips and gaps have no children to recurse into
        },
    }
}

/// Upgrade SerializableTimeline from version 0 (OTIO JSON source) to version 1
///
/// Changes from v0 to v1:
/// - Set schema_version field to 1
/// - Fix transitions: ensure container and kind fields are present
fn upgrade_timeline_v0_to_v1(
    allocator: std.mem.Allocator,
    timeline: *SerializableTimeline,
) !void
{
    if (timeline.schema_version != 0)
    {
        return error.InvalidVersionForUpgrade;
    }

    // Fix all transitions in the timeline recursively
    for (timeline.children) 
        |*child| 
    {
        try fix_transitions_in_composable(allocator, child);
    }

    // Update version number
    timeline.schema_version = 1;
}

// ----------------------------------------------------------------------------
// Conversion Functions: Serializable → Schema
// ----------------------------------------------------------------------------

fn serializable_to_domain(
    allocator: std.mem.Allocator,
    ser_dom: SerializableDomain,
) !domain_mod.Domain
{
    return switch (ser_dom) {
        .time => .time,
        .picture => .picture,
        .audio => .audio,
        .metadata => .metadata,
        .other => |o| .{
            .other = try allocator.dupe(u8, o.name),
        },
    };
}

fn serializable_to_media_data_reference(
    allocator: std.mem.Allocator,
    ser_ref: SerializableMediaDataReference,
) !schema.MediaDataReference
{
    return switch (ser_ref) {
        .uri => |uri_ref| .{
            .uri = .{
                .target_uri = try allocator.dupe(
                    u8,
                    uri_ref.target_uri,
                ),
            },
        },
        .signal => |sig_ref| .{
            .signal = .{
                .signal_generator = (
                    try serializable_to_signal_generator(
                        allocator,
                        sig_ref.signal_generator,
                    )
                ),
            },
        },
        .image_sequence => |img_seq| .{
            .image_sequence = .{
                .target_url_base = try allocator.dupe(
                    u8,
                    img_seq.target_url_base,
                ),
                .name_prefix = try allocator.dupe(
                    u8,
                    img_seq.name_prefix,
                ),
                .name_suffix = try allocator.dupe(
                    u8,
                    img_seq.name_suffix,
                ),
                .frame_zero_padding = img_seq.frame_zero_padding,
                .missing_frame_policy = .from_maybe_string(
                    img_seq.missing_frame_policy,
                ),
            },
        },
        .null => .null,
    };
}

fn serializable_to_signal_generator(
    allocator: std.mem.Allocator,
    ser_gen: SerializableSignalGenerator,
) !sampling.SignalGenerator
{
    _ = allocator;
    return switch (ser_gen) {
        .sine => |sine| .{
            .frequency_hz = @intFromFloat(sine.frequency_hz),
            .amplitude = 1.0,
            .duration_s = opentime.Ordinate.init(1.0),
            .signal = .sine,
        },
        .linear_ramp => .{
            .frequency_hz = 1,
            .amplitude = 1.0,
            .duration_s = opentime.Ordinate.init(1.0),
            .signal = .ramp,
        },
    };
}

fn serializable_to_media_reference(
    allocator: std.mem.Allocator,
    ser_ref: SerializableMediaReference,
) !schema.MediaReference
{
    // Determine bounds_write_policy based on what was in the file
    const bounds_write_policy: schema.BoundsWritePolicy = if (ser_ref.bounds_s)
        |bounds|
        (if (bounds == .discrete) schema.BoundsWritePolicy.discrete else .continuous)
    else
        .automatic;

    return .{
        .data_reference = try serializable_to_media_data_reference(
            allocator,
            ser_ref.data_reference,
        ),
        .maybe_bounds_s = try serializable_to_optional_bounds(
            ser_ref.bounds_s,
            serializable_to_optional_sig(ser_ref.discrete_partition),
        ),
        .domain = try serializable_to_domain(
            allocator,
            ser_ref.domain,
        ),
        .maybe_discrete_partition = (
            serializable_to_optional_sig(ser_ref.discrete_partition)
        ),
        .interpolating = (
            ser_ref.interpolating
            orelse .default_from_domain
        ),
        .bounds_write_policy = bounds_write_policy,
    };
}

fn serializable_to_topology(
    allocator: std.mem.Allocator,
    ser_topo: SerializableTopology,
) !topology_m.Topology
{
    const mappings = try allocator.alloc(
        topology_m.mapping.Mapping,
        ser_topo.mappings.len,
    );

    for (ser_topo.mappings, 0..)
        |ser_mapping, i|
    {
        mappings[i] = try serializable_to_mapping(
            allocator,
            ser_mapping,
        );
    }

    return .{ .mappings = mappings };
}

fn serializable_to_mapping(
    allocator: std.mem.Allocator,
    ser_mapping: SerializableMapping,
) !topology_m.mapping.Mapping
{
    return switch (ser_mapping) {
        .affine => |aff| (
            topology_m.mapping.MappingAffine{
                .input_bounds_val = (
                    serializable_to_interval(aff.input_bounds_val)
                ),
                .input_to_output_xform = .{
                    .offset = opentime.Ordinate.init(
                        aff.input_to_output_xform.offset,
                    ),
                    .scale = opentime.Ordinate.init(
                        aff.input_to_output_xform.scale,
                    ),
                },
            }
        ).mapping(),
        .linear => |lin| {
            const knots = (
                try allocator.alloc(curve.ControlPoint, lin.knots.len)
            );
            for (lin.knots, 0..)
                |ser_knot, i|
            {
                knots[i] = .{
                    .in = opentime.Ordinate.init(ser_knot[0]),
                    .out = opentime.Ordinate.init(ser_knot[1]),
                };
            }
            return (
                topology_m.mapping.MappingCurveLinearMonotonic{
                    .input_to_output_curve = .{
                        .knots = knots,
                    },
                }
            ).mapping();
        },
        .empty => topology_m.mapping.MappingEmpty.empty_infinite.mapping(),
    };
}

fn serializable_to_clip(
    allocator: std.mem.Allocator,
    ser_clip: SerializableClip,
) !*schema.Clip
{
    const clip_ptr = try allocator.create(schema.Clip);
    const media = try serializable_to_media_reference(
        allocator,
        ser_clip.media,
    );

    // Determine bounds_write_policy based on what was in the file
    const bounds_write_policy: schema.BoundsWritePolicy = (
        if (ser_clip.bounds_s) |bounds| if (bounds == .discrete) .discrete 
        else .continuous
    else
        .automatic
    );

    clip_ptr.* = .{
        .name = try allocator.dupe(u8, ser_clip.name),
        .maybe_bounds_s = (
            try serializable_to_optional_bounds(
                ser_clip.bounds_s,
                media.maybe_discrete_partition,
            )
        ),
        .bounds_write_policy = bounds_write_policy,
        .media = media,
        .markers = try serializable_to_markers(
            allocator,
            ser_clip.markers,
        ),
    };
    return clip_ptr;
}

fn serializable_to_gap(
    allocator: std.mem.Allocator,
    ser_gap: SerializableGap,
) !*schema.Gap
{
    const gap_ptr = try allocator.create(schema.Gap);
    gap_ptr.* = .{
        .name = try allocator.dupe(u8, ser_gap.name),
        .bounds_s = serializable_to_interval(
            ser_gap.bounds_s,
        ),
        .markers = try serializable_to_markers(
            allocator,
            ser_gap.markers,
        ),
    };
    return gap_ptr;
}

fn serializable_to_warp(
    allocator: std.mem.Allocator,
    ser_warp: SerializableWarp,
) !*schema.Warp
{
    const warp_ptr = try allocator.create(schema.Warp);
    warp_ptr.* = .{
        .name = try allocator.dupe(u8, ser_warp.name),
        .child = try serializable_to_composable(
            allocator,
            ser_warp.child.*,
        ),
        .transform = try serializable_to_topology(
            allocator,
            ser_warp.transform,
        ),
    };
    return warp_ptr;
}

fn serializable_to_track(
    allocator: std.mem.Allocator,
    ser_track: SerializableTrack,
) !*schema.Track
{
    const children = try allocator.alloc(
        schema.references.CompositionItemHandle,
        ser_track.children.len,
    );

    for (ser_track.children, 0..)
        |ser_child, i|
    {
        children[i] = try serializable_to_composable(
            allocator,
            ser_child,
        );
    }

    const track_ptr = try allocator.create(schema.Track);
    track_ptr.* = .{
        .name = try allocator.dupe(u8, ser_track.name),
        .maybe_bounds_s = try serializable_to_optional_bounds(
            ser_track.bounds_s,
            null,
        ),
        .children = children,
        .markers = try serializable_to_markers(
            allocator,
            ser_track.markers,
        ),
    };
    return track_ptr;
}

fn serializable_to_stack(
    allocator: std.mem.Allocator,
    ser_stack: SerializableStack,
) !*schema.Stack
{
    const children = try allocator.alloc(
        schema.references.CompositionItemHandle,
        ser_stack.children.len,
    );

    for (ser_stack.children, 0..)
        |ser_child, i|
    {
        children[i] = try serializable_to_composable(
            allocator,
            ser_child,
        );
    }

    const stack_ptr = try allocator.create(schema.Stack);
    stack_ptr.* = .{
        .name = try allocator.dupe(u8, ser_stack.name),
        .maybe_bounds_s = try serializable_to_optional_bounds(
            ser_stack.bounds_s,
            null,
        ),
        .children = children,
        .markers = try serializable_to_markers(
            allocator,
            ser_stack.markers,
        ),
    };
    return stack_ptr;
}

fn serializable_to_transition(
    allocator: std.mem.Allocator,
    ser_trans: SerializableTransition,
) !*schema.Transition
{
    const container_ptr = try serializable_to_stack(
        allocator,
        ser_trans.container,
    );

    const trans_ptr = try allocator.create(schema.Transition);
    trans_ptr.* = .{
        .name = try allocator.dupe(u8, ser_trans.name),
        .container = container_ptr.*,
        .kind = try allocator.dupe(u8, ser_trans.kind),
        .maybe_bounds_s = serializable_to_optional_interval(
            ser_trans.bounds_s,
        ),
    };

    // Free the temporary stack pointer (contents are moved)
    allocator.destroy(container_ptr);

    return trans_ptr;
}

fn serializable_to_composable(
    allocator: std.mem.Allocator,
    ser_comp: SerializableComposable,
) error{ OutOfMemory, MissingDiscretePartition }!schema.references.CompositionItemHandle
{
    return switch (ser_comp) {
        .clip => |clip_val| .{
            .clip = try serializable_to_clip(allocator, clip_val),
        },
        .gap => |gap_val| .{
            .gap = try serializable_to_gap(allocator, gap_val),
        },
        .track => |track_val| .{
            .track = try serializable_to_track(allocator, track_val),
        },
        .stack => |stack_val| .{
            .stack = try serializable_to_stack(allocator, stack_val),
        },
        .warp => |warp_val| .{
            .warp = try serializable_to_warp(allocator, warp_val),
        },
        .transition => |trans_val| .{
            .transition = try serializable_to_transition(allocator, trans_val),
        },
    };
}

pub fn serializable_to_timeline(
    allocator: std.mem.Allocator,
    intermediate_tl: SerializableTimeline,
) !*schema.Timeline
{
    // Convert children back to tracks.children
    const children = try allocator.alloc(
        schema.references.CompositionItemHandle,
        intermediate_tl.children.len,
    );

    for (intermediate_tl.children, 0..)
        |ser_child, i|
    {
        children[i] = try serializable_to_composable(allocator, ser_child);
    }

    const timeline_ptr = try allocator.create(schema.Timeline);
    timeline_ptr.* = .{
        .name = try allocator.dupe(u8, intermediate_tl.name),
        .tracks = .{
            .name = "",  // Timeline's implicit tracks Stack has no name
            .children = children,
        },
        .discrete_space_partitions = .{
            .presentation = .{
                .picture = serializable_to_optional_sig(intermediate_tl.presentation_space_discrete_partitions.picture),
                .audio = serializable_to_optional_sig(intermediate_tl.presentation_space_discrete_partitions.audio),
            },
        },
        .metadata_map = if (intermediate_tl.metadata_map)
            |mm|
            try metadata_map_to_json(allocator, mm)
        else
            null,
    };

    return timeline_ptr;
}

/// Convert SerializableCollection to schema.Collection
pub fn serializable_to_collection(
    allocator: std.mem.Allocator,
    ser_coll: SerializableCollection,
) !*schema.Collection
{
    // Convert collection children to composition handles
    const children = try allocator.alloc(
        schema.references.CompositionItemHandle,
        ser_coll.children.len,
    );

    for (ser_coll.children, 0..)
        |ser_child, i|
    {
        children[i] = try serializable_collection_item_to_handle(allocator, ser_child);
    }

    const collection_ptr = try allocator.create(schema.Collection);
    collection_ptr.* = .{
        .name = try allocator.dupe(u8, ser_coll.name),
        .description = try allocator.dupe(u8, ser_coll.description),
        .children = children,
    };

    return collection_ptr;
}

/// Convert SerializableCollectionItem to schema.CompositionItemHandle
fn serializable_collection_item_to_handle(
    allocator: std.mem.Allocator,
    ser_item: SerializableCollectionItem,
) !schema.references.CompositionItemHandle
{
    return switch (ser_item) {
        .timeline => |tl| .{
            .timeline = try serializable_to_timeline(allocator, tl),
        },
        .clip => |clip_val| .{
            .clip = try serializable_to_clip(allocator, clip_val),
        },
        .gap => |gap_val| .{
            .gap = try serializable_to_gap(allocator, gap_val),
        },
        .track => |track_val| .{
            .track = try serializable_to_track(allocator, track_val),
        },
        .stack => |stack_val| .{
            .stack = try serializable_to_stack(allocator, stack_val),
        },
        .warp => |warp_val| .{
            .warp = try serializable_to_warp(allocator, warp_val),
        },
        .transition => |trans_val| .{
            .transition = try serializable_to_transition(allocator, trans_val),
        },
    };
}

/// Convert schema.Collection to SerializableCollection
pub fn collection_to_serializable(
    allocator: std.mem.Allocator,
    collection: *schema.Collection,
) !SerializableCollection
{
    // Create metadata context for accumulating clip metadata
    var metadata_map: MetadataMap = .{};
    var meta_ctx = MetadataContext{
        .allocator = allocator,
        .metadata_map = &metadata_map,
    };

    // Convert children
    const ser_children = try allocator.alloc(SerializableCollectionItem, collection.children.len);
    for (collection.children, 0..)
        |child, i|
    {
        ser_children[i] = try handle_to_serializable_collection_item(allocator, child, &meta_ctx);
    }

    return .{
        .schema_version = 1,
        .name = try allocator.dupe(u8, collection.name),
        .description = try allocator.dupe(u8, collection.description),
        .children = ser_children,
        .metadata_map = if (metadata_map.fields.count() > 0) metadata_map else null,
    };
}

/// Convert schema.CompositionItemHandle to SerializableCollectionItem
fn handle_to_serializable_collection_item(
    allocator: std.mem.Allocator,
    handle: schema.references.CompositionItemHandle,
    meta_ctx: *MetadataContext,
) !SerializableCollectionItem
{
    return switch (handle) {
        .timeline => |tl| .{
            .timeline = try SerializableTimeline.from(allocator, tl),
        },
        .clip => |clip_ptr| .{
            .clip = try SerializableClip.from(allocator, clip_ptr.*, meta_ctx),
        },
        .gap => |gap_ptr| .{
            .gap = try SerializableGap.from(allocator, gap_ptr.*),
        },
        .track => |track_ptr| .{
            .track = try SerializableTrack.from(allocator, track_ptr.*, meta_ctx),
        },
        .stack => |stack_ptr| .{
            .stack = try SerializableStack.from(allocator, stack_ptr.*, meta_ctx),
        },
        .warp => |warp_ptr| .{
            .warp = try SerializableWarp.from(allocator, warp_ptr.*, meta_ctx),
        },
        .transition => |trans_ptr| .{
            .transition = try SerializableTransition.from(allocator, trans_ptr.*, meta_ctx),
        },
        // Collections cannot be nested (would need a different design)
        .collection => unreachable,
    };
}

// ----------------------------------------------------------------------------
// Curve Conversion Functions
// ----------------------------------------------------------------------------

/// Convert curve.Bezier to serializable format
fn bezier_curve_to_serializable(
    allocator: std.mem.Allocator,
    bezier: curve.Bezier,
) !SerializableBezierCurve
{
    const ser_segments = try allocator.alloc(
        [4]SerializableControlPoint,
        bezier.segments.len
    );

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
fn serializable_to_bezier_curve(
    allocator: std.mem.Allocator,
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
fn linear_curve_to_serializable(
    allocator: std.mem.Allocator,
    linear: curve.Linear,
) !SerializableLinearCurve
{
    const ser_knots = try allocator.alloc(
        SerializableControlPoint,
        linear.knots.len,
    );

    for (linear.knots, 0..)
        |knot, i|
    {
        ser_knots[i] = .{ knot.in.as(f64), knot.out.as(f64), };
    }

    return .{
        .knots = ser_knots,
    };
}

/// Convert serializable format to curve.Linear
fn serializable_to_linear_curve(
    allocator: std.mem.Allocator,
    ser_linear: SerializableLinearCurve,
) !curve.Linear
{
    const knots = try allocator.alloc(
        CurveControlPoint,
        ser_linear.knots.len,
    );

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
// Main Serialization Entry Points (using tla)
// ----------------------------------------------------------------------------

/// Serialize a Timeline to tla format and write to the provided writer.
///
/// If target_version is provided, the timeline will be downgraded to that
/// version before serialization (requires registered downgrade functions).
fn serialize_timeline(
    timeline: *schema.Timeline,
    allocator: std.mem.Allocator,
    writer: *std.io.Writer,
    maybe_target_version: ?u32,
) !void
{

    // Convert to serializable format
    var intermediate_tl = try SerializableTimeline.from(
        allocator,
        timeline,
    );
    defer intermediate_tl.deinit(allocator);

    // Downgrade if target version specified
    if (maybe_target_version)
        |target_version|
    {
        const current_ver = versioning.current_version("Timeline");
        if (target_version < current_ver)
        {
            // Try to get global registry and downgrade
            const registry = (
                versioning.get_global_registry(allocator) catch |err| 
                {
                    // If registry doesn't exist or fails, log and continue
                    // with current version
                    std.log.warn(
                        (
                                 "Failed to get version registry for downgrade:"
                                 ++ " {}. Serializing Timeline at version {} "
                                 ++ "instead of {}."
                        ),
                        .{ err, current_ver, target_version }
                    );

                    try ziggy.stringify(
                        intermediate_tl,
                        .{
                            .whitespace = .space_4,
                            .emit_null_fields = false,
                        },
                        writer
                    );
                    return;
                }
            );

            // Attempt downgrade
            registry.downgrade(
                allocator,
                "Timeline",
                &intermediate_tl,
                current_ver,
                target_version,
            ) catch |err| {
                // If downgrade fails, log warning and serialize at current
                // version
                std.log.warn(
                    "Failed to downgrade Timeline from version {} to"
                    ++ " {}: {}. Serializing at current version.",
                    .{ current_ver, target_version, err }
                );
            };
        }
    }

    // Serialize directly - ziggy 0.1.0 CAN parse unions in arrays!
    try ziggy.stringify(
        intermediate_tl,
        .{
            .whitespace = .space_4,
            .emit_null_fields = false,
        },
        writer
    );
}

/// Deserialize a Timeline from tla format source string.
///
/// Automatically detects the version in the file and upgrades to the current
/// version if needed (requires registered upgrade functions).
///
/// If content_filter is .all_except_metadata, the metadata_map
/// field will be completely skipped during parsing using ziggy's skip_fields
/// feature. This provides significant performance gains for large files with
/// extensive metadata.
pub fn deserialize_timeline(
    allocator: std.mem.Allocator,
    source: [:0]const u8,
    content_filter: adapter.ReadOptions.ContentFilter,
) !*schema.Timeline
{
    var serializable_tl = switch (content_filter) {
        .all => try ziggy.parseLeaky(
            SerializableTimeline,
            allocator,
            source,
            .{},
        ),
        .all_except_metadata => s_t: {
            // Use the no-metadata variant that skips parsing metadata_map entirely
            var serializable_tl_no_md = try ziggy.parseLeaky(
                SerializableTimelineNoMetadata,
                allocator,
                source,
                .{},
            );

            // convert back to regular SerializableTimeline
            break :s_t  serializable_tl_no_md.to_serializable_timeline();
        },
        .only_metadata => return error.OnlyMetadataNotSupportedForDeserialization,
    };
    defer serializable_tl.deinit(allocator);

    // Check version and upgrade if needed
    const current_ver = versioning.current_version("Timeline");
    if (serializable_tl.schema_version < current_ver)
    {
        const registry = (
            versioning.get_global_registry(allocator) catch |err| {
                std.log.warn(
                    "Failed to get version registry for upgrade: {}. " 
                    ++ "Loading Timeline at version {} without upgrading to {}.",
                    .{ err, serializable_tl.schema_version, current_ver }
                );
                return try serializable_to_timeline(
                    allocator,
                    serializable_tl,
                );
            }
        );

        registry.upgrade(
            allocator,
            "Timeline",
            &serializable_tl,
            serializable_tl.schema_version,
            current_ver,
        ) catch |err| {
            std.log.warn(
                "Failed to upgrade Timeline from version {} to {}: {}." 
                ++ " Loading at original version.",
                .{ serializable_tl.schema_version, current_ver, err }
            );
        };
    }

    return try serializable_to_timeline(
        allocator,
        serializable_tl,
    );
}

fn wrap_in_timeline(
    allocator: std.mem.Allocator,
    composable: SerializableComposable,
    timeline_name: []const u8,
    meta_map: *MetadataMap,
) !SerializableTimeline
{
    const track_children = try allocator.alloc(
        SerializableComposable,
        1,
    );

    track_children[0] = composable;

    const ser_track = SerializableTrack{
        .name = try allocator.dupe(u8, "Wrapper Track for "),
        .children = track_children,
    };

    const timeline_children = try allocator.alloc(SerializableComposable, 1);
    timeline_children[0] = .{ .track = ser_track };

    return SerializableTimeline{
        .name = try allocator.dupe(u8, timeline_name),
        .children = timeline_children,
        .presentation_space_discrete_partitions = .{},
        .metadata_map = (
            if (meta_map.fields.count() > 0) meta_map.*
            else null
        ),
    };
}

/// Convert OTIO JSON to SerializableTimeline, preserving metadata.
///
/// This function converts OTIO JSON to SerializableTimeline without going through
/// the runtime Schema, which would lose metadata. Use this for file conversion
/// tio
/// tools that need to preserve metadata (e.g., otiocat).
///
/// Non-Timeline root objects (Clip, Track, Warp, etc.) are automatically
/// wrapped in a synthetic Timeline/Track structure for a complete schema.
fn otio_json_to_serializable_timeline(
    allocator: std.mem.Allocator,
    json_source: []const u8,
) !SerializableTimeline 
{
    // Parse OTIO JSON to runtime Schema (clips contain metadata)
    var composition_handle = try legacy_json.read_from_string(
        allocator,
        json_source,
        .all,
    );
    defer composition_handle.deinit(allocator);

    // Create metadata map and context for accumulating clip metadata
    var metadata_map: MetadataMap = .{};
    var meta_ctx = MetadataContext{
        .allocator = allocator,
        .metadata_map = &metadata_map,
    };

    // Convert to SerializableTimeline based on root object type
    var intermediate_tl: SerializableTimeline = switch (composition_handle) {
        .timeline => |tl| try SerializableTimeline.from(
            allocator,
            tl,
        ),

        .clip => |clip_ptr| try wrap_in_timeline(
            allocator,
            .{ .clip = try SerializableClip.from(allocator, clip_ptr.*, &meta_ctx) },
            clip_ptr.name,
            &metadata_map,
        ),

        .gap => |gap_ptr| try wrap_in_timeline(
            allocator,
            .{ .gap = try SerializableGap.from(allocator, gap_ptr.*) },
            gap_ptr.name,
            &metadata_map,
        ),

        .track => |track_ptr| blk: {
            // Track goes directly into timeline children (no wrapper track)
            const ser_track = try SerializableTrack.from(allocator, track_ptr.*, &meta_ctx);
            const timeline_children = try allocator.alloc(SerializableComposable, 1);
            timeline_children[0] = .{ .track = ser_track };

            break :blk SerializableTimeline{
                .name = try allocator.dupe(u8, track_ptr.name),
                .children = timeline_children,
                .presentation_space_discrete_partitions = .{},
                .metadata_map = if (metadata_map.fields.count() > 0) metadata_map else null,
            };
        },

        .stack => |stack_ptr| blk: {
            // Stack children become timeline children directly
            const ser_stack = try SerializableStack.from(allocator, stack_ptr.*, &meta_ctx);

            break :blk SerializableTimeline{
                .name = try allocator.dupe(u8, stack_ptr.name),
                .children = ser_stack.children,
                .presentation_space_discrete_partitions = .{},
                .metadata_map = if (metadata_map.fields.count() > 0) metadata_map else null,
            };
        },

        .warp => |warp_ptr| try wrap_in_timeline(
            allocator,
            .{ .warp = try SerializableWarp.from(allocator, warp_ptr.*, &meta_ctx) },
            warp_ptr.name,
            &metadata_map,
        ),

        .transition => |trans_ptr| try wrap_in_timeline(
            allocator,
            .{ .transition = try SerializableTransition.from(allocator, trans_ptr.*, &meta_ctx) },
            trans_ptr.name,
            &metadata_map,
        ),

        // Collections cannot be converted to timeline - use serialize_collection instead
        .collection => return error.UseSerializeCollectionInstead,
    };

    // Mark as version 0 (OTIO JSON source) then upgrade
    intermediate_tl.schema_version = OTIO_JSON_VERSION;
    try upgrade_timeline_v0_to_v1(allocator, &intermediate_tl);

    return intermediate_tl;
}

// @TODO: collapse these serialize functions that recursively call components
//        down

/// Serialize a Bezier curve to tla format and write to the provided writer.
fn serialize_bezier_curve(
    bezier: curve.Bezier,
    allocator: std.mem.Allocator,
    writer: *std.io.Writer,
) !void
{
    // Convert to serializable format
    const ser_bezier = try bezier_curve_to_serializable(
        allocator,
        bezier,
    );

    // Use ziggy to serialize
    try ziggy.stringify(ser_bezier, .{
        .whitespace = .space_4,
        .emit_null_fields = false,
    }, writer);
}

/// Deserialize a Bezier curve from tla format source string.
fn deserialize_bezier_curve(
    allocator: std.mem.Allocator,
    source: [:0]const u8,
) !curve.Bezier
{
    // Use tla to deserialize
    const ser_bezier = try ziggy.parseLeaky(
        SerializableBezierCurve,
        allocator,
        source,
        .{},
    );

    // Convert to curve format
    return try serializable_to_bezier_curve(allocator, ser_bezier);
}

/// Serialize a Linear curve to tla format and write to the provided writer.
fn serialize_linear_curve(
    linear: curve.Linear,
    allocator: std.mem.Allocator,
    writer: *std.io.Writer,
) !void
{
    // Convert to serializable format
    const ser_linear = try linear_curve_to_serializable(allocator, linear);

    // Use ziggy to serialize
    try ziggy.stringify(ser_linear, .{
        .whitespace = .space_4,
        .emit_null_fields = false,
    }, writer);
}

/// Deserialize a Linear curve from tla format source string.
fn deserialize_linear_curve(
    allocator: std.mem.Allocator,
    source: [:0]const u8,
) !curve.Linear
{
    // Use ziggy to deserialize
    const ser_linear = try ziggy.parseLeaky(
        SerializableLinearCurve,
        allocator,
        source,
        .{},
    );

    // Convert to curve format
    return try serializable_to_linear_curve(allocator, ser_linear);
}

// ----------------------------------------------------------------------------
// Metadata Mode Conversion Functions
// ----------------------------------------------------------------------------

/// Convert a SerializableTimeline to inline metadata format.
/// Looks up metadata_hash values in metadata_map and stores them inline on clips.
fn convert_to_inline_metadata(
    allocator: std.mem.Allocator,
    timeline: SerializableTimeline,
) !SerializableTimelineInlineMetadata
{
    const inline_children = try allocator.alloc(
        SerializableComposableInlineMetadata,
        timeline.children.len,
    );

    for (timeline.children, 0..)
        |child, i|
    {
        inline_children[i] = try convert_composable_to_inline_metadata(
            allocator,
            child,
            timeline.metadata_map,
        );
    }

    return .{
        .schema_version = timeline.schema_version,
        .name = timeline.name,
        .children = inline_children,
        .presentation_space_discrete_partitions = timeline.presentation_space_discrete_partitions,
    };
}

/// Convert a SerializableComposable to inline metadata format.
fn convert_composable_to_inline_metadata(
    allocator: std.mem.Allocator,
    composable: SerializableComposable,
    metadata_map: ?MetadataMap,
) !SerializableComposableInlineMetadata
{
    return switch (composable) {
        .clip => |clip| .{
            .clip = .{
                .name = clip.name,
                .bounds_s = clip.bounds_s,
                .media = clip.media,
                .metadata = if (clip.metadata_hash) |hash|
                    if (metadata_map) |mm|
                        mm.fields.get(hash)
                    else
                        null
                else
                    null,
            },
        },
        .gap => |gap| .{ .gap = gap },
        .track => |track| blk: {
            const inline_children = try allocator.alloc(
                SerializableComposableInlineMetadata,
                track.children.len,
            );
            for (track.children, 0..)
                |child, i|
            {
                inline_children[i] = try convert_composable_to_inline_metadata(
                    allocator,
                    child,
                    metadata_map,
                );
            }
            break :blk .{
                .track = .{
                    .name = track.name,
                    .bounds_s = track.bounds_s,
                    .children = inline_children,
                },
            };
        },
        .stack => |stack| blk: {
            const inline_children = try allocator.alloc(
                SerializableComposableInlineMetadata,
                stack.children.len,
            );
            for (stack.children, 0..) 
                |child, i| 
            {
                inline_children[i] = try convert_composable_to_inline_metadata(
                    allocator,
                    child,
                    metadata_map,
                );
            }
            break :blk .{
                .stack = .{
                    .name = stack.name,
                    .bounds_s = stack.bounds_s,
                    .children = inline_children,
                },
            };
        },
        .warp => |warp| blk: {
            const inline_child = try allocator.create(SerializableComposableInlineMetadata);
            inline_child.* = try convert_composable_to_inline_metadata(
                allocator,
                warp.child.*,
                metadata_map,
            );
            break :blk .{
                .warp = .{
                    .name = warp.name,
                    .child = inline_child,
                    .transform = warp.transform,
                },
            };
        },
        .transition => |trans| blk: {
            const inline_container_children = try allocator.alloc(
                SerializableComposableInlineMetadata,
                trans.container.children.len,
            );
            for (trans.container.children, 0..) 
                |child, i| 
            {
                inline_container_children[i] = try convert_composable_to_inline_metadata(
                    allocator,
                    child,
                    metadata_map,
                );
            }
            break :blk .{
                .transition = .{
                    .name = trans.name,
                    .container = .{
                        .name = trans.container.name,
                        .bounds_s = trans.container.bounds_s,
                        .children = inline_container_children,
                    },
                    .kind = trans.kind,
                    .bounds_s = trans.bounds_s,
                },
            };
        },
    };
}

/// Strip all metadata from a SerializableTimeline.
/// Removes metadata_hash from clips and metadata_map from timeline.
fn strip_metadata(
    allocator: std.mem.Allocator,
    timeline: SerializableTimeline,
) !SerializableTimelineStrippedMetadata
{
    const stripped_children = try allocator.alloc(
        SerializableComposableNoMetadata,
        timeline.children.len,
    );

    for (timeline.children, 0..)
        |child, i|
    {
        stripped_children[i] = try convert_composable_to_no_metadata(
            allocator,
            child,
        );
    }

    return .{
        .schema_version = timeline.schema_version,
        .name = timeline.name,
        .children = stripped_children,
        .presentation_space_discrete_partitions = timeline.presentation_space_discrete_partitions,
    };
}

/// Convert a SerializableComposable to no metadata format.
fn convert_composable_to_no_metadata(
    allocator: std.mem.Allocator,
    composable: SerializableComposable,
) !SerializableComposableNoMetadata
{
    return switch (composable) {
        .clip => |clip| .{
            .clip = .{
                .name = clip.name,
                .bounds_s = clip.bounds_s,
                .media = clip.media,
                // No metadata_hash field
            },
        },
        .gap => |gap| .{ .gap = gap },
        .track => |track| blk: {
            const stripped_children = try allocator.alloc(
                SerializableComposableNoMetadata,
                track.children.len,
            );
            for (track.children, 0..) 
                |child, i| 
            {
                stripped_children[i] = try convert_composable_to_no_metadata(
                    allocator,
                    child,
                );
            }
            break :blk .{
                .track = .{
                    .name = track.name,
                    .bounds_s = track.bounds_s,
                    .children = stripped_children,
                },
            };
        },
        .stack => |stack| blk: {
            const stripped_children = try allocator.alloc(
                SerializableComposableNoMetadata,
                stack.children.len,
            );
            for (stack.children, 0..)
                |child, i|
            {
                stripped_children[i] = try convert_composable_to_no_metadata(
                    allocator,
                    child,
                );
            }
            break :blk .{
                .stack = .{
                    .name = stack.name,
                    .bounds_s = stack.bounds_s,
                    .children = stripped_children,
                },
            };
        },
        .warp => |warp| blk: {
            const stripped_child = try allocator.create(
                SerializableComposableNoMetadata
            );
            stripped_child.* = try convert_composable_to_no_metadata(
                allocator,
                warp.child.*,
            );
            break :blk .{
                .warp = .{
                    .name = warp.name,
                    .child = stripped_child,
                    .transform = warp.transform,
                },
            };
        },
        .transition => |trans| blk: {
            const stripped_container_children = try allocator.alloc(
                SerializableComposableNoMetadata,
                trans.container.children.len,
            );
            for (trans.container.children, 0..)
                |child, i|
            {
                stripped_container_children[i] = try convert_composable_to_no_metadata(
                    allocator,
                    child,
                );
            }
            break :blk .{
                .transition = .{
                    .name = trans.name,
                    .container = .{
                        .name = trans.container.name,
                        .bounds_s = trans.container.bounds_s,
                        .children = stripped_container_children,
                    },
                    .kind = trans.kind,
                    .bounds_s = trans.bounds_s,
                },
            };
        },
    };
}

// ----------------------------------------------------------------------------
// Tests
// ----------------------------------------------------------------------------

test "hash conversion: u64 to hex string round-trip"
{
    const allocator = std.testing.allocator;

    // Test with the hash value from just_clip_with_metadata.tla
    // "46ce2bb4fbd1c246" corresponds to u64: 0x46ce2bb4fbd1c246
    const expected_hash: u64 = 0x46ce2bb4fbd1c246;
    const expected_str = "46ce2bb4fbd1c246";

    // Test hex_string_to_hash
    const parsed_hash = hex_string_to_hash(expected_str);
    try std.testing.expect(parsed_hash != null);
    try std.testing.expectEqual(expected_hash, parsed_hash.?);

    // Test hash_to_hex_string
    const generated_str = try hash_to_hex_string(allocator, expected_hash);
    defer allocator.free(generated_str);
    try std.testing.expectEqualStrings(expected_str, generated_str);

    // Test round-trip
    const round_trip_hash = hex_string_to_hash(generated_str);
    try std.testing.expect(round_trip_hash != null);
    try std.testing.expectEqual(expected_hash, round_trip_hash.?);
}

test "hash conversion: invalid hex strings"
{
    // Wrong length
    try std.testing.expect(hex_string_to_hash("abc") == null);
    try std.testing.expect(hex_string_to_hash("abcdef0123456789ab") == null);

    // Invalid characters
    try std.testing.expect(hex_string_to_hash("46ce2bb4fbd1c24g") == null);
    try std.testing.expect(hex_string_to_hash("46ce2bb4fbd1c24!") == null);
}

test "hash conversion: edge cases"
{
    const allocator = std.testing.allocator;

    // Zero hash
    const zero_str = try hash_to_hex_string(allocator, 0);
    defer allocator.free(zero_str);
    try std.testing.expectEqualStrings("0000000000000000", zero_str);

    const zero_hash = hex_string_to_hash("0000000000000000");
    try std.testing.expect(zero_hash != null);
    try std.testing.expectEqual(@as(u64, 0), zero_hash.?);

    // Max u64
    const max_str = try hash_to_hex_string(allocator, std.math.maxInt(u64));
    defer allocator.free(max_str);
    try std.testing.expectEqualStrings("ffffffffffffffff", max_str);

    const max_hash = hex_string_to_hash("ffffffffffffffff");
    try std.testing.expect(max_hash != null);
    try std.testing.expectEqual(std.math.maxInt(u64), max_hash.?);

    // Uppercase should also work
    const upper_hash = hex_string_to_hash("FFFFFFFFFFFFFFFF");
    try std.testing.expect(upper_hash != null);
    try std.testing.expectEqual(std.math.maxInt(u64), upper_hash.?);
}

test "interval conversion: ContinuousInterval to [2]f64"
{
    const interval = opentime.ContinuousInterval{
        .start = opentime.Ordinate.init(1.5),
        .end = opentime.Ordinate.init(3.75),
    };

    const ser: SerializableContinuousInterval = .{
        interval.start.as(f64),
        interval.end.as(f64),
    };

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

    const ser: ?SerializableContinuousInterval = if (maybe_interval) |i|
        .{ i.start.as(f64), i.end.as(f64) }
    else
        null;
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
    const ser: ?SerializableContinuousInterval = if (maybe_interval) |i|
        .{ i.start.as(f64), i.end.as(f64) }
    else
        null;
    try std.testing.expect(ser == null);

    const back = serializable_to_optional_interval(null);
    try std.testing.expect(back == null);
}

test "clip serialization: round-trip"
{
    const allocator = std.testing.allocator;

    // Create a test clip
    const clip = schema.Clip{
        .name = "TestClip",
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

    // Convert to serializable (no metadata context for this test)
    const ser_clip: SerializableClip = try .from(allocator, clip, null);
    defer allocator.free(ser_clip.name);
    defer allocator.free(ser_clip.media.data_reference.uri.target_uri);

    // Verify serialized values
    try std.testing.expectEqualStrings("TestClip", ser_clip.name);
    try std.testing.expect(ser_clip.bounds_s.? == .continuous);
    try std.testing.expectEqual(@as(f64, 1.0), ser_clip.bounds_s.?.continuous[0]);
    try std.testing.expectEqual(@as(f64, 5.0), ser_clip.bounds_s.?.continuous[1]);

    // Convert back
    const clip_ptr = try serializable_to_clip(allocator, ser_clip);
    defer allocator.destroy(clip_ptr);
    defer allocator.free(clip_ptr.name);
    defer allocator.free(clip_ptr.media.data_reference.uri.target_uri);

    // Verify round-trip
    try std.testing.expectEqualStrings("TestClip", clip_ptr.name);
    try std.testing.expectEqual(@as(f64, 1.0), clip_ptr.maybe_bounds_s.?.start.as(f64));
    try std.testing.expectEqual(@as(f64, 5.0), clip_ptr.maybe_bounds_s.?.end.as(f64));
}

test "gap serialization: round-trip"
{
    const allocator = std.testing.allocator;

    // Create a test gap
    const gap = schema.Gap{
        .name = "TestGap",
        .bounds_s = .{
            .start = opentime.Ordinate.init(2.5),
            .end = opentime.Ordinate.init(7.5),
        },
    };

    // Convert to serializable
    const ser_gap: SerializableGap = try .from(allocator, gap);
    defer allocator.free(ser_gap.name);

    // Verify serialized values
    try std.testing.expectEqualStrings("TestGap", ser_gap.name);
    try std.testing.expectEqual(2.5, ser_gap.bounds_s[0]);
    try std.testing.expectEqual(7.5, ser_gap.bounds_s[1]);

    // Convert back
    const gap_ptr = try serializable_to_gap(allocator, ser_gap);
    defer allocator.destroy(gap_ptr);
    defer allocator.free(gap_ptr.name);

    // Verify round-trip
    try std.testing.expectEqualStrings("TestGap", gap_ptr.name);
    try std.testing.expectEqual(2.5, gap_ptr.bounds_s.start.as(f64));
    try std.testing.expectEqual(7.5, gap_ptr.bounds_s.end.as(f64));
}

test "timeline serialization: tla round-trip"
{
    const allocator = std.testing.allocator;

    // Create test timeline with children
    var timeline = schema.Timeline{
        .name = "TestTimeline",
        .tracks = .{
            .name = "",
            .children = &.{},
        },
        .discrete_space_partitions = .{
            .presentation = .{
                .picture = null,
                .audio = null,
            },
        },
    };

    // Serialize to tla format
    var buffer: std.io.Writer.Allocating = .init(allocator);
    defer buffer.deinit();

    try serialize_timeline(
        &timeline,
        allocator,
        &buffer.writer,
        null,
    );

    // Add null terminator for ziggy
    const written = buffer.written();
    const source_with_null = try allocator.alloc(u8, written.len + 1);
    defer allocator.free(source_with_null);
    @memcpy(source_with_null[0..written.len], written);
    source_with_null[written.len] = 0;
    const source: [:0]const u8 = source_with_null[0..written.len :0];

    // Deserialize back
    const loaded_timeline = try deserialize_timeline(
        allocator,
        source,
        .all,
    );
    defer allocator.destroy(loaded_timeline);
    defer loaded_timeline.deinit(allocator);

    // Verify
    try std.testing.expectEqualStrings(
        "TestTimeline",
        loaded_timeline.name,
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        loaded_timeline.tracks.children.len,
    );
}

// ----------------------------------------------------------------------------
// Universal File Reading
// ----------------------------------------------------------------------------


/// Supported file format types for read/write operations.
/// Re-exported from adapter for backward compatibility.
pub const FileFormat = adapter.FileFormat;

/// Read a timeline from a buffer into SerializableTimeline.
/// Supports: .otio (JSON), .tla, .tlb (FlatBuffers)
/// Note: .tlz format is not supported for buffer reading as it requires
/// file system access for the ZIP archive. Use read_from_file for .tlz.
///
/// This is useful for cases where data is already in memory, such as
/// from sokol_fetch callbacks or network transfers.
pub fn read_from_buffer(
    allocator: std.mem.Allocator,
    buffer: []const u8,
    format: FileFormat,
) !SerializableTimeline
{
    switch (format) {
        .tla => {
            // Ziggy requires null-terminated source
            // Check if already null-terminated
            if (buffer.len > 0 and buffer[buffer.len - 1] == 0) {
                return try ziggy.parseLeaky(
                    SerializableTimeline,
                    allocator,
                    buffer[0 .. buffer.len - 1 :0],
                    .{},
                );
            }
            // Need to add null terminator
            const source_with_null = try allocator.alloc(u8, buffer.len + 1);
            defer allocator.free(source_with_null);
            @memcpy(source_with_null[0..buffer.len], buffer);
            source_with_null[buffer.len] = 0;
            return try ziggy.parseLeaky(
                SerializableTimeline,
                allocator,
                source_with_null[0..buffer.len :0],
                .{},
            );
        },
        .tlb => {
            return try binary.deserialize_to_serializable_timeline(
                allocator,
                buffer,
                .all,
            );
        },
        .otio => {
            return try otio_json_to_serializable_timeline(allocator, buffer);
        },
        .tlz => {
            // TLZ is a ZIP archive that requires file system access
            return error.TlzRequiresFileAccess;
        },
        .tlca, .tlcb, .tlcz => {
            // Collection formats are not timelines
            return error.NotATimelineFormat;
        },
    }
}

/// Read a timeline from any supported file format into SerializableTimeline.
/// Supports: .otio (JSON), .tla, .tlb (FlatBuffers), .tlz (bundle)
/// The file format is determined by the file extension.
pub fn read_from_file(
    allocator: std.mem.Allocator,
    file_path: []const u8,
) !SerializableTimeline
{
    // Check file extension to determine format
    const ext_start = std.mem.lastIndexOfScalar(u8, file_path, '.') orelse {
        return error.NoFileExtension;
    };
    const extension = file_path[ext_start + 1 ..];  // Skip the leading dot

    const format = std.meta.stringToEnum(FileFormat, extension) orelse {
        return error.UnsupportedFileFormat;
    };

    // Handle .tlz separately since it manages its own file reading
    if (format == .tlz)
    {
        return try bundle.read_from_file(allocator, file_path, .{});
    }

    // For other formats, read the file contents first
    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    const source = try file.readToEndAllocOptions(
        allocator,
        std.math.maxInt(u32),
        null,
        .@"1",
        0,
    );
    defer allocator.free(source);

    return try read_from_buffer(allocator, source, format);
}

// ----------------------------------------------------------------------------
// Universal File Writing
// ----------------------------------------------------------------------------


/// Options for writing timeline files
pub const WriteOptions = struct {
    /// Controls how metadata is output in TLA format
    metadata_mode: adapter.WriteOptions.MetadataMode = .hash_reference,

    /// TLZ bundle format (tla or tlb inside the bundle)
    bundle_format: bundle_utils.BundleFormat = .tla,

    /// TLZ media handling policy
    media_policy: bundle_utils.MediaReferencePolicy = .MissingIfNotFile,

    /// Base directory for resolving media paths (for TLZ bundles)
    media_base_dir: ?[]const u8 = null,
};

/// Write a SerializableTimeline to an allocated buffer.
/// Supports: .tla, .tlb (FlatBuffers)
/// Note: .tlz format is not supported for buffer writing as it requires
/// file system access for the ZIP archive. Use write_to_file for .tlz.
///
/// Returns an allocated buffer that the caller must free.
/// This is useful for cases where you need the serialized data in memory,
/// such as for network transfers or in-memory processing.
pub fn write_to_buffer(
    allocator: std.mem.Allocator,
    intermediate_tl: SerializableTimeline,
    format: FileFormat,
    metadata_mode: adapter.WriteOptions.MetadataMode,
) ![]u8
{
    switch (format)
    {
        // TLZ is a ZIP archive that requires file system access
        .tlz => return error.TlzRequiresFileAccess,

        // OTIO JSON output is not currently supported
        .otio => return error.OtioJsonWriteNotSupported,
        else => {},
    }

    // Use an allocating writer to build the buffer
    var buffer = std.Io.Writer.Allocating.init(allocator);
    errdefer buffer.deinit();

    try write_serializable_to_writer(
        allocator,
        intermediate_tl,
        format,
        metadata_mode,
        &buffer.writer,
    );

    return try buffer.toOwnedSlice();
}

/// Write a SerializableTimeline to a writer in the specified format.
///
/// Use this function when you have a SerializableTimeline and want to
/// preserve all fields including metadata_hash and metadata_map.
pub fn write_serializable_to_writer(
    allocator: std.mem.Allocator,
    intermediate_tl: SerializableTimeline,
    format: FileFormat,
    metadata_mode: adapter.WriteOptions.MetadataMode,
    writer: anytype,
) anyerror!void
{
    switch (format) {
        .tla => {
            try write_tla_with_metadata_mode(
                allocator,
                intermediate_tl,
                metadata_mode,
                writer,
            );
        },
        .tlb => {
            try binary.serialize_from_serializable_timeline(
                intermediate_tl,
                allocator,
                writer,
            );
        },
        .otio => {
            return error.OtioJsonWriteNotSupported;
        },
        .tlz => {
            return error.TlzRequiresFileAccess;
        },
        .tlca, .tlcb, .tlcz => {
            // Collection formats are not timelines - use write_collection_to_writer instead
            return error.NotATimelineFormat;
        },
    }
}

/// Write SerializableTimeline to TLA format with the specified metadata mode.
fn write_tla_with_metadata_mode(
    allocator: std.mem.Allocator,
    intermediate_tl: SerializableTimeline,
    metadata_mode: adapter.WriteOptions.MetadataMode,
    writer: anytype,
) !void
{
    switch (metadata_mode) {
        .hash_reference => {
            // Default behavior - output SerializableTimeline directly
            try ziggy.stringify(
                intermediate_tl,
                .{
                    .whitespace = .space_4,
                    .emit_null_fields = false,
                },
                writer,
            );
        },
        .no_metadata => {
            // Strip all metadata
            const stripped = try strip_metadata(allocator, intermediate_tl);
            try ziggy.stringify(
                stripped,
                .{
                    .whitespace = .space_4,
                    .emit_null_fields = false,
                },
                writer,
            );
        },
        .inline_metadata => {
            // Convert to inline metadata format
            const inline_timeline = try convert_to_inline_metadata(
                allocator,
                intermediate_tl,
            );
            try ziggy.stringify(
                inline_timeline,
                .{
                    .whitespace = .space_4,
                    .emit_null_fields = false,
                },
                writer,
            );
        },
    }
    _ = try writer.write("\n");
}

// ----------------------------------------------------------------------------
// Collection File Reading/Writing
// ----------------------------------------------------------------------------

/// Read a collection from a buffer into SerializableCollection.
/// Supports: .tlca (ASCII tla)
/// Note: .tlcb (FlatBuffers) requires binary_serialization_flatbufs support.
pub fn read_collection_from_buffer(
    allocator: std.mem.Allocator,
    buffer: []const u8,
    format: FileFormat,
) !SerializableCollection
{
    switch (format) {
        .tlca => {
            // Ziggy requires null-terminated source
            if (buffer.len > 0 and buffer[buffer.len - 1] == 0) {
                return try ziggy.parseLeaky(
                    SerializableCollection,
                    allocator,
                    buffer[0 .. buffer.len - 1 :0],
                    .{},
                );
            }
            // Need to add null terminator
            const source_with_null = try allocator.alloc(u8, buffer.len + 1);
            defer allocator.free(source_with_null);
            @memcpy(source_with_null[0..buffer.len], buffer);
            source_with_null[buffer.len] = 0;
            return try ziggy.parseLeaky(
                SerializableCollection,
                allocator,
                source_with_null[0..buffer.len :0],
                .{},
            );
        },
        .tlcb => {
            return try binary.deserialize_collection(
                allocator,
                buffer,
            );
        },
        else => return error.NotACollectionFormat,
    }
}

/// Read a collection from any supported file format into SerializableCollection.
/// Supports: .tlca (ASCII Ziggy), .tlcb (FlatBuffers binary)
/// The file format is determined by the file extension.
pub fn read_collection_from_file(
    allocator: std.mem.Allocator,
    file_path: []const u8,
) !SerializableCollection
{
    // Check file extension to determine format
    const ext_start = std.mem.lastIndexOfScalar(u8, file_path, '.') orelse {
        return error.NoFileExtension;
    };
    const extension = file_path[ext_start + 1 ..];  // Skip the leading dot

    const format = std.meta.stringToEnum(FileFormat, extension) orelse {
        return error.UnsupportedFileFormat;
    };

    // Read the file contents
    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    const source = try file.readToEndAllocOptions(
        allocator,
        std.math.maxInt(u32),
        null,
        .@"1",
        0,
    );
    defer allocator.free(source);

    return try read_collection_from_buffer(allocator, source, format);
}

/// Options for writing collection files (subset of WriteOptions relevant to collections)
pub const CollectionWriteOptions = struct {
    /// Controls how metadata is output in TLCA format
    metadata_mode: adapter.WriteOptions.MetadataMode = .hash_reference,
};

/// Write a SerializableCollection to a buffer.
/// Supports: .tlca (ASCII Ziggy), .tlcb (FlatBuffers binary)
/// Returns an allocated buffer that the caller must free.
pub fn write_collection_to_buffer(
    allocator: std.mem.Allocator,
    collection: SerializableCollection,
    format: FileFormat,
    metadata_mode: adapter.WriteOptions.MetadataMode,
) ![]u8
{
    // Use an allocating writer to build the buffer
    var buffer = std.Io.Writer.Allocating.init(allocator);
    errdefer buffer.deinit();

    try write_collection_to_writer(
        allocator,
        collection,
        format,
        metadata_mode,
        &buffer.writer,
    );

    return try buffer.toOwnedSlice();
}

/// Write a SerializableCollection to a file.
/// Supports: .tlca (ASCII Ziggy), .tlcb (FlatBuffers binary)
/// The file format is determined by the file extension.
pub fn write_collection_to_file(
    allocator: std.mem.Allocator,
    collection: SerializableCollection,
    file_path: []const u8,
    options: adapter.WriteOptions.MetadataMode,
) !void
{
    // Check file extension to determine format
    const ext_start = std.mem.lastIndexOfScalar(u8, file_path, '.') orelse {
        return error.NoFileExtension;
    };
    const extension = file_path[ext_start + 1 ..];  // Skip the leading dot

    const format = std.meta.stringToEnum(FileFormat, extension) orelse {
        return error.UnsupportedFileFormat;
    };

    // Open file and write
    const file = try std.fs.cwd().createFile(file_path, .{});
    defer file.close();

    var file_writer_buffer: [16 * 1024]u8 = undefined;
    var file_writer = file.writer(&file_writer_buffer);
    const writer = &file_writer.interface;

    try write_collection_to_writer(
        allocator,
        collection,
        format,
        options,
        writer,
    );

    try writer.flush();
}

/// Write a SerializableCollection to a writer in the specified format.
pub fn write_collection_to_writer(
    allocator: std.mem.Allocator,
    collection: SerializableCollection,
    format: FileFormat,
    metadata_mode: adapter.WriteOptions.MetadataMode,
    writer: anytype,
) !void
{
    switch (format) {
        .tlca => {
            try write_tlca_with_metadata_mode(
                allocator,
                collection,
                metadata_mode,
                writer,
            );
        },
        .tlcb => {
            // Binary format doesn't support inline metadata - always use hash references
            try binary.serialize_collection(
                collection,
                allocator,
                writer,
            );
        },
        else => return error.NotACollectionFormat,
    }
}

/// Write SerializableCollection to TLCA format with the specified metadata mode.
fn write_tlca_with_metadata_mode(
    allocator: std.mem.Allocator,
    collection: SerializableCollection,
    metadata_mode: adapter.WriteOptions.MetadataMode,
    writer: anytype,
) !void
{
    switch (metadata_mode) {
        .hash_reference => {
            // Default behavior - output SerializableCollection directly
            try ziggy.stringify(
                collection,
                .{
                    .whitespace = .space_4,
                    .emit_null_fields = false,
                },
                writer,
            );
        },
        .no_metadata => {
            // Strip all metadata from collection
            const stripped = try strip_collection_metadata(allocator, collection);
            try ziggy.stringify(
                stripped,
                .{
                    .whitespace = .space_4,
                    .emit_null_fields = false,
                },
                writer,
            );
        },
        .inline_metadata => {
            // Convert to inline metadata format
            const inline_collection = try convert_collection_to_inline_metadata(
                allocator,
                collection,
            );
            try ziggy.stringify(
                inline_collection,
                .{
                    .whitespace = .space_4,
                    .emit_null_fields = false,
                },
                writer,
            );
        },
    }
    _ = try writer.write("\n");
}

/// Strip all metadata from a SerializableCollection.
/// Removes metadata_hash from clips and metadata_map from collection and embedded timelines.
fn strip_collection_metadata(
    allocator: std.mem.Allocator,
    collection: SerializableCollection,
) !SerializableCollectionStrippedMetadata
{
    const stripped_children = try allocator.alloc(
        SerializableCollectionItemNoMetadata,
        collection.children.len,
    );

    for (collection.children, 0..)
        |child, i|
    {
        stripped_children[i] = try convert_collection_item_to_no_metadata(allocator, child);
    }

    return .{
        .schema_version = collection.schema_version,
        .name = collection.name,
        .description = collection.description,
        .children = stripped_children,
        // No metadata_map field
    };
}

/// Convert a SerializableCollectionItem to no metadata format.
fn convert_collection_item_to_no_metadata(
    allocator: std.mem.Allocator,
    item: SerializableCollectionItem,
) !SerializableCollectionItemNoMetadata
{
    return switch (item) {
        .timeline => |tl| blk: {
            const stripped_children = try allocator.alloc(
                SerializableComposableNoMetadata,
                tl.children.len,
            );
            for (tl.children, 0..)
                |child, i|
            {
                stripped_children[i] = try convert_composable_to_no_metadata(allocator, child);
            }
            break :blk .{
                .timeline = .{
                    .schema_version = tl.schema_version,
                    .name = tl.name,
                    .children = stripped_children,
                    .presentation_space_discrete_partitions = tl.presentation_space_discrete_partitions,
                    // No metadata_map field
                },
            };
        },
        .track => |track| blk: {
            const stripped_children = try allocator.alloc(
                SerializableComposableNoMetadata,
                track.children.len,
            );
            for (track.children, 0..)
                |child, i|
            {
                stripped_children[i] = try convert_composable_to_no_metadata(allocator, child);
            }
            break :blk .{
                .track = .{
                    .name = track.name,
                    .bounds_s = track.bounds_s,
                    .children = stripped_children,
                },
            };
        },
        .stack => |stack| blk: {
            const stripped_children = try allocator.alloc(
                SerializableComposableNoMetadata,
                stack.children.len,
            );
            for (stack.children, 0..)
                |child, i|
            {
                stripped_children[i] = try convert_composable_to_no_metadata(allocator, child);
            }
            break :blk .{
                .stack = .{
                    .name = stack.name,
                    .bounds_s = stack.bounds_s,
                    .children = stripped_children,
                },
            };
        },
        .clip => |clip| .{
            .clip = .{
                .name = clip.name,
                .bounds_s = clip.bounds_s,
                .media = clip.media,
                // No metadata_hash field
            },
        },
        .gap => |gap| .{ .gap = gap },
        .warp => |warp| blk: {
            const stripped_child = try allocator.create(SerializableComposableNoMetadata);
            stripped_child.* = try convert_composable_to_no_metadata(allocator, warp.child.*);
            break :blk .{
                .warp = .{
                    .name = warp.name,
                    .child = stripped_child,
                    .transform = warp.transform,
                },
            };
        },
        .transition => |trans| blk: {
            const stripped_container_children = try allocator.alloc(
                SerializableComposableNoMetadata,
                trans.container.children.len,
            );
            for (trans.container.children, 0..)
                |child, i|
            {
                stripped_container_children[i] = try convert_composable_to_no_metadata(
                    allocator,
                    child,
                );
            }
            break :blk .{
                .transition = .{
                    .name = trans.name,
                    .container = .{
                        .name = trans.container.name,
                        .bounds_s = trans.container.bounds_s,
                        .children = stripped_container_children,
                    },
                    .bounds_s = trans.bounds_s,
                    .kind = trans.kind,
                },
            };
        },
    };
}

/// Convert a SerializableCollection to inline metadata format.
fn convert_collection_to_inline_metadata(
    allocator: std.mem.Allocator,
    collection: SerializableCollection,
) !SerializableCollectionInlineMetadata
{
    const inline_children = try allocator.alloc(
        SerializableCollectionItemInlineMetadata,
        collection.children.len,
    );

    for (collection.children, 0..)
        |child, i|
    {
        inline_children[i] = try convert_collection_item_to_inline_metadata(
            allocator,
            child,
            collection.metadata_map,
        );
    }

    return .{
        .schema_version = collection.schema_version,
        .name = collection.name,
        .description = collection.description,
        .children = inline_children,
        // No metadata_map field - metadata is inline
    };
}

/// Convert a SerializableCollectionItem to inline metadata format.
fn convert_collection_item_to_inline_metadata(
    allocator: std.mem.Allocator,
    item: SerializableCollectionItem,
    collection_metadata_map: ?MetadataMap,
) !SerializableCollectionItemInlineMetadata
{
    return switch (item) {
        .timeline => |tl| blk: {
            // Timeline has its own metadata_map, use it for its children
            const inline_children = try allocator.alloc(
                SerializableComposableInlineMetadata,
                tl.children.len,
            );
            for (tl.children, 0..)
                |child, i|
            {
                inline_children[i] = try convert_composable_to_inline_metadata(
                    allocator,
                    child,
                    tl.metadata_map,
                );
            }
            break :blk .{
                .timeline = .{
                    .schema_version = tl.schema_version,
                    .name = tl.name,
                    .children = inline_children,
                    .presentation_space_discrete_partitions = tl.presentation_space_discrete_partitions,
                    // No metadata_map field - metadata is inline
                },
            };
        },
        .track => |track| blk: {
            const inline_children = try allocator.alloc(
                SerializableComposableInlineMetadata,
                track.children.len,
            );
            for (track.children, 0..)
                |child, i|
            {
                inline_children[i] = try convert_composable_to_inline_metadata(
                    allocator,
                    child,
                    collection_metadata_map,
                );
            }
            break :blk .{
                .track = .{
                    .name = track.name,
                    .bounds_s = track.bounds_s,
                    .children = inline_children,
                },
            };
        },
        .stack => |stack| blk: {
            const inline_children = try allocator.alloc(
                SerializableComposableInlineMetadata,
                stack.children.len,
            );
            for (stack.children, 0..)
                |child, i|
            {
                inline_children[i] = try convert_composable_to_inline_metadata(
                    allocator,
                    child,
                    collection_metadata_map,
                );
            }
            break :blk .{
                .stack = .{
                    .name = stack.name,
                    .bounds_s = stack.bounds_s,
                    .children = inline_children,
                },
            };
        },
        .clip => |clip| .{
            .clip = .{
                .name = clip.name,
                .bounds_s = clip.bounds_s,
                .media = clip.media,
                .metadata = if (clip.metadata_hash)
                    |hash|
                    if (collection_metadata_map)
                        |mm|
                        mm.fields.get(hash)
                    else
                        null
                else
                    null,
            },
        },
        .gap => |gap| .{ .gap = gap },
        .warp => |warp| blk: {
            const inline_child = try allocator.create(SerializableComposableInlineMetadata);
            inline_child.* = try convert_composable_to_inline_metadata(
                allocator,
                warp.child.*,
                collection_metadata_map,
            );
            break :blk .{
                .warp = .{
                    .name = warp.name,
                    .child = inline_child,
                    .transform = warp.transform,
                },
            };
        },
        .transition => |trans| blk: {
            const inline_container_children = try allocator.alloc(
                SerializableComposableInlineMetadata,
                trans.container.children.len,
            );
            for (trans.container.children, 0..)
                |child, i|
            {
                inline_container_children[i] = try convert_composable_to_inline_metadata(
                    allocator,
                    child,
                    collection_metadata_map,
                );
            }
            break :blk .{
                .transition = .{
                    .name = trans.name,
                    .container = .{
                        .name = trans.container.name,
                        .bounds_s = trans.container.bounds_s,
                        .children = inline_container_children,
                    },
                    .bounds_s = trans.bounds_s,
                    .kind = trans.kind,
                },
            };
        },
    };
}

test "collection serialization: tlca round-trip"
{
    const allocator = std.testing.allocator;

    // Create a test collection
    var children = [_]SerializableCollectionItem{
        .{
            .clip = .{
                .name = "Test Clip",
                .bounds_s = .{ .continuous = .{ 0.0, 5.0 } },
                .media = .{
                    .data_reference = .{ .uri = .{ .target_uri = "file:///test.mov" } },
                    .bounds_s = .{ .continuous = .{ 0.0, 10.0 } },
                    .domain = .picture,
                },
                .markers = &[_]SerializableMarker{},
            },
        },
    };
    const original = SerializableCollection{
        .schema_version = 1,
        .name = "Test Collection",
        .description = "A test collection",
        .children = &children,
        .metadata_map = null,
    };

    // Serialize to TLCA
    const buffer = try write_collection_to_buffer(
        allocator,
        original,
        .tlca,
        .hash_reference
    );
    defer allocator.free(buffer);

    // Deserialize back
    var roundtrip = try read_collection_from_buffer(
        allocator,
        buffer,
        .tlca,
    );
    defer roundtrip.deinit(allocator);

    // Verify
    try std.testing.expectEqualStrings("Test Collection", roundtrip.name);
    try std.testing.expectEqualStrings("A test collection", roundtrip.description);
    try std.testing.expectEqual(@as(usize, 1), roundtrip.children.len);
    try std.testing.expectEqualStrings("Test Clip", roundtrip.children[0].clip.name);
}

test "collection serialization: tlcb round-trip"
{
    const allocator = std.testing.allocator;

    // Create a test collection
    var children = [_]SerializableCollectionItem{
        .{
            .gap = .{
                .name = "Test Gap",
                .bounds_s = .{ 0.0, 2.0 },
                .markers = &[_]SerializableMarker{},
            },
        },
    };
    const original = SerializableCollection{
        .schema_version = 1,
        .name = "Binary Test Collection",
        .description = "A binary test collection",
        .children = &children,
        .metadata_map = null,
    };

    // Serialize to TLCB
    const buffer = try write_collection_to_buffer(
        allocator,
        original,
        .tlcb,
        .hash_reference,
    );
    defer allocator.free(buffer);

    // Deserialize back
    var roundtrip = try read_collection_from_buffer(allocator, buffer, .tlcb);
    defer roundtrip.deinit(allocator);

    // Verify
    try std.testing.expectEqualStrings("Binary Test Collection", roundtrip.name);
    try std.testing.expectEqualStrings("A binary test collection", roundtrip.description);
    try std.testing.expectEqual(@as(usize, 1), roundtrip.children.len);
    try std.testing.expectEqualStrings("Test Gap", roundtrip.children[0].gap.name);
}

test "collection serialization: tlca to tlcb cross-format"
{
    const allocator = std.testing.allocator;

    // Create a test collection with timeline
    var children = [_]SerializableCollectionItem{
        .{
            .timeline = .{
                .schema_version = 1,
                .name = "Embedded Timeline",
                .children = &[_]SerializableComposable{},
                .presentation_space_discrete_partitions = .{},
                .markers = &[_]SerializableMarker{},
                .metadata_map = null,
            },
        },
    };
    const original = SerializableCollection{
        .schema_version = 1,
        .name = "Cross-Format Collection",
        .description = "",
        .children = &children,
        .metadata_map = null,
    };

    // Serialize to TLCA first
    const tlca_buffer = try write_collection_to_buffer(
        allocator,
        original,
        .tlca,
        .hash_reference,
    );
    defer allocator.free(tlca_buffer);

    // Read TLCA back
    var from_tlca = try read_collection_from_buffer(allocator, tlca_buffer, .tlca);
    defer from_tlca.deinit(allocator);

    // Convert to TLCB
    const tlcb_buffer = try write_collection_to_buffer(
        allocator,
        from_tlca,
        .tlcb,
        .hash_reference,
    );
    defer allocator.free(tlcb_buffer);

    // Read TLCB back
    var from_tlcb = try read_collection_from_buffer(allocator, tlcb_buffer, .tlcb);
    defer from_tlcb.deinit(allocator);

    // Verify
    try std.testing.expectEqualStrings("Cross-Format Collection", from_tlcb.name);
    try std.testing.expectEqual(@as(usize, 1), from_tlcb.children.len);
    try std.testing.expectEqualStrings("Embedded Timeline", from_tlcb.children[0].timeline.name);
}

/// Bridge function for adapter interface - reads TLA format from reader.
/// Used by the unified SerializableFormat interface for format-agnostic I/O.
pub fn read_timeline_from_reader(
    allocator: std.mem.Allocator,
    reader: *std.Io.Reader,
    metadata_mode: adapter.ReadOptions.ContentFilter,
) anyerror!SerializableTimeline
{
    _ = metadata_mode;

    const buffer = try reader.readAlloc(
        allocator,
        std.math.maxInt(u32),
    );

    return try read_from_buffer(
        allocator,
        buffer,
        .tla,
    );
}

/// Bridge function for adapter interface - writes TLA format to writer.
/// Used by the unified SerializableFormat interface for format-agnostic I/O.
pub fn write_ascii_serializable_to_writer(
    allocator: std.mem.Allocator,
    intermediate_tl: SerializableTimeline,
    writer: *std.Io.Writer,
    metadata_mode: adapter.WriteOptions.MetadataMode,
) anyerror!void
{
    return write_serializable_to_writer(
        allocator,
        intermediate_tl,
        .tla,
        metadata_mode,
        writer,
    );
}

/// Bridge function for reading ASCII collection (TLAC) format from a reader.
pub fn read_ascii_collection_from_reader(
    allocator: std.mem.Allocator,
    reader: *std.Io.Reader,
    metadata_mode: adapter.ReadOptions.ContentFilter,
) anyerror!SerializableCollection
{
    _ = metadata_mode;

    const buffer = try reader.readAlloc(
        allocator,
        std.math.maxInt(u32),
    );
    defer allocator.free(buffer);

    return try read_collection_from_buffer(
        allocator,
        buffer,
        .tlca,
    );
}

/// Bridge function for writing ASCII collection (TLAC) format to a writer.
pub fn write_ascii_collection_to_writer(
    allocator: std.mem.Allocator,
    collection: SerializableCollection,
    writer: *std.Io.Writer,
    metadata_mode: adapter.WriteOptions.MetadataMode,
) anyerror!void
{
    return write_collection_to_writer(
        allocator,
        collection,
        .tlca,
        metadata_mode,
        writer,
    );
}

