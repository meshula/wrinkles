//! Format-neutral intermediate representation for timeline serialization.
//!
//! Every serialized format (TLA, TLB, bundles, legacy OTIO JSON) reads into
//! and writes from the types defined here.  This module provides:
//! - Serializable variants of schema types (pointer-based
//!   CompositionItemHandle trees become inline tagged unions)
//! - Conversion between schema types and serializable types
//! - Metadata map types and helpers
//! - Schema-version upgrades of serializable data
//!
//! It has no knowledge of any particular encoding; see ascii.zig, binary.zig,
//! legacy_json.zig and bundle.zig for those.

const std = @import("std");

const ziggy = @import("ziggy");

const opentime = @import("opentime");
const sampling = @import("sampling");
const topology_m = @import("topology");
const curve = @import("curve");

const schema = @import("../schema.zig");
const domain_mod = @import("../domain.zig");

const versioning = @import("versioning.zig");
const json_metadata = @import("../json_metadata.zig");


// Re-export curve control point for convenience
const CurveControlPoint = curve.ControlPoint;

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
    time,
    picture,
    audio,
    metadata,
    other: struct { name: []const u8 },

    pub fn from(
        allocator: std.mem.Allocator,
        domain: domain_mod.Domain
    ) !SerializableDomain 
    {
        return switch (domain) {
            .time => .time,
            .picture => .picture,
            .audio => .audio,
            .metadata => .metadata,
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
    null,

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
    linear_ramp,

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
            .ramp => .linear_ramp,
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
    empty,

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
            .empty => .empty,
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

/// Serializable variant of DiscretePartitionDomainMap
pub const SerializableDiscretePartitionDomainMap = struct {
    picture: ?SerializableSampleIndexGenerator = null,
    audio: ?SerializableSampleIndexGenerator = null,
};

/// Metadata value type using ziggy's dynamic system for flexible nested data
pub const MetadataValue = ziggy.Dynamic;

/// Metadata map type - maps string keys to dynamic values
pub const MetadataMap = ziggy.Dictionary(MetadataValue);

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
        .@"union" => |u| {
            allocator.free(u.tag);
            deinit_metadata_value(allocator, u.value.*);
            allocator.destroy(u.value);
        },
        .@"enum" => |e| allocator.free(e),
        .integer, .float, .bool, .null => {},
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


/// The serializable editorial tree (composables, timeline, collection),
/// generic over its clip type.  `Core` (clips reference metadata by hash) is
/// the in-memory representation; formats instantiate other clip types for
/// alternative on-disk layouts (see ascii.zig) and map between instances
/// with `convert`.
///
/// Methods that build from schema objects (`from`) only compile for `Core`.
pub fn Tree(
    comptime ClipT: type,
) type
{
    return struct {
        pub const Clip = ClipT;

        pub const Composable = union(enum) {
            clip: Clip,
            gap: SerializableGap,
            track: Track,
            stack: Stack,
            warp: Warp,
            transition: Transition,

            pub fn from(
                allocator: std.mem.Allocator,
                handle: schema.references.CompositionItemHandle,
                maybe_meta_ctx: ?*MetadataContext,
            ) error{OutOfMemory, DiscretePartitionRequired}!Composable
            {
                return switch (handle) {
                    .clip => |clip_ptr| .{ .clip = try Clip.from(allocator, clip_ptr.*, maybe_meta_ctx) },
                    .gap => |gap_ptr| .{ .gap = try SerializableGap.from(allocator, gap_ptr.*) },
                    .track => |track_ptr| .{ .track = try Track.from(allocator, track_ptr.*, maybe_meta_ctx) },
                    .stack => |stack_ptr| .{ .stack = try Stack.from(allocator, stack_ptr.*, maybe_meta_ctx) },
                    .warp => |warp_ptr| .{ .warp = try Warp.from(allocator, warp_ptr.*, maybe_meta_ctx) },
                    .transition => |trans_ptr| .{ .transition = try Transition.from(allocator, trans_ptr.*, maybe_meta_ctx) },
                    .timeline, .collection => unreachable, // Timeline/Collection are not composable children
                };
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
        pub const Warp = struct {
            name: []const u8 = "",
            child: *Composable,
            transform: SerializableTopology,

            pub fn from(
                allocator: std.mem.Allocator,
                warp: schema.Warp,
                maybe_meta_ctx: ?*MetadataContext,
            ) !Warp
            {
                const child = try allocator.create(Composable);
                errdefer allocator.destroy(child);
                child.* = try Composable.from(
                    allocator,
                    warp.child,
                    maybe_meta_ctx,
                );

                return .{
                    .name = try allocator.dupe(u8, warp.name),
                    .child = child,
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
        pub const Stack = struct {
            name: []const u8 = "",
            bounds_s: ?SerializableBounds = null,
            children: []Composable,
            markers: []SerializableMarker = &.{},

            pub fn from(
                allocator: std.mem.Allocator,
                stack: schema.Stack,
                maybe_meta_ctx: ?*MetadataContext,
            ) !Stack
            {
                const ser_children = try allocator.alloc(
                    Composable,
                    stack.children.len,
                );
                for (stack.children, 0..)
                    |child, i|
                {
                    ser_children[i] = try Composable.from(
                        allocator,
                        child,
                        maybe_meta_ctx,
                    );
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
        pub const Track = struct {
            name: []const u8 = "",
            bounds_s: ?SerializableBounds = null,
            children: []Composable,
            markers: []SerializableMarker = &.{},

            pub fn from(
                allocator: std.mem.Allocator,
                track: schema.Track,
                maybe_meta_ctx: ?*MetadataContext,
            ) !Track
            {
                const ser_children = try allocator.alloc(Composable, track.children.len);
                for (track.children, 0..)
                    |child, i|
                {
                    ser_children[i] = try Composable.from(
                        allocator,
                        child,
                        maybe_meta_ctx,
                    );
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
        pub const Transition = struct {
            name: []const u8 = "",
            container: Stack,
            kind: []const u8,
            bounds_s: ?SerializableContinuousInterval = null,

            pub fn from(
                allocator: std.mem.Allocator,
                transition: schema.Transition,
                maybe_meta_ctx: ?*MetadataContext,
            ) !Transition
            {
                const bounds = if (transition.maybe_bounds_s)
                    |b|
                    [2]f64{ b.start.as(f64), b.end.as(f64) }
                else
                    null;

                return .{
                    .name = try allocator.dupe(u8, transition.name),
                    .container = try Stack.from(allocator, transition.container, maybe_meta_ctx),
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

        /// Serializable variant of Timeline (root type)
        pub const Timeline = struct {
            pub const schema_name: []const u8 = "Timeline";

            name: []const u8 = "",
            children: []Composable,
            presentation_space_discrete_partitions: SerializableDiscretePartitionDomainMap,
            /// Maps metadata hash keys to their metadata dictionaries.
            /// Optional so empty maps can be omitted from serialization.
            metadata_map: ?MetadataMap = null,
            markers: []SerializableMarker = &.{},

            pub fn from(
                allocator: std.mem.Allocator,
                timeline: *schema.Timeline,
            ) !Timeline
            {
                // Create metadata map and context for accumulating clip metadata
                var metadata_map: MetadataMap = .empty;
                var meta_ctx = MetadataContext{
                    .allocator = allocator,
                    .metadata_map = &metadata_map,
                };

                // Convert tracks.children directly to timeline.children
                const ser_children = try allocator.alloc(Composable, timeline.tracks.children.len);
                for (timeline.tracks.children, 0..)
                    |child, i|
                {
                    ser_children[i] = try Composable.from(
                        allocator,
                        child,
                        &meta_ctx,
                    );
                }

                // Timeline-level entries no clip references.
                if (timeline.metadata_map)
                    |json_val|
                {
                    try meta_ctx.merge_json_object(json_val);
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

            /// Free and remove the root metadata map, if any.
            pub fn drop_metadata(
                self: *@This(),
                allocator: std.mem.Allocator,
            ) void
            {
                if (self.metadata_map)
                    |*mm|
                {
                    deinit_metadata_map(allocator, mm);
                }
                self.metadata_map = null;
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

        // ----------------------------------------------------------------------------
        // Collection Types
        // ----------------------------------------------------------------------------
        // A Collection groups related items (timelines, clips, etc.) without implying
        // any temporal relationship between them. Unlike a Timeline which arranges
        // children with defined timing, a Collection is purely organizational.

        /// Items that can be direct children of a Collection.
        /// Collections can contain timelines and other composables.
        pub const CollectionItem = union(enum) {
            timeline: Timeline,
            track: Track,
            stack: Stack,
            clip: Clip,
            gap: SerializableGap,
            warp: Warp,
            transition: Transition,

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
        pub const Collection = struct {
            pub const schema_name: []const u8 = "Collection";

            name: []const u8 = "",
            description: []const u8 = "",
            children: []CollectionItem,
            metadata_map: ?MetadataMap = null,

            /// Free and remove the root metadata map, if any.
            pub fn drop_metadata(
                self: *@This(),
                allocator: std.mem.Allocator,
            ) void
            {
                if (self.metadata_map)
                    |*mm|
                {
                    deinit_metadata_map(allocator, mm);
                }
                self.metadata_map = null;
            }

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
    };
}

/// The in-memory serializable tree.
pub const Core = Tree(SerializableClip);

pub const SerializableComposable = Core.Composable;
pub const SerializableWarp = Core.Warp;
pub const SerializableStack = Core.Stack;
pub const SerializableTrack = Core.Track;
pub const SerializableTransition = Core.Transition;
/// Serializable variant of Timeline (root type)
pub const SerializableTimeline = Core.Timeline;
pub const SerializableCollectionItem = Core.CollectionItem;
/// Serializable variant of Collection (root type for .tlca/.tlcb files)
pub const SerializableCollection = Core.Collection;

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
                var result_map: MetadataMap = .empty;
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
                    serialize_json_for_hash(
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
                    serialize_json_for_hash(
                        entry.value_ptr.*,
                        writer,
                    );
                }
                writer.writeAll("}") catch {};
            },
        }
    }

    /// Merge the entries of a JSON object into the map under their existing
    /// keys.  Keys already present (e.g. added by a clip) are left as-is.
    pub fn merge_json_object(
        self: *MetadataContext,
        json_val: std.json.Value,
    ) !void
    {
        if (json_val != .object)
        {
            return;
        }
        var iter = json_val.object.iterator();
        while (iter.next())
            |entry|
        {
            if (self.metadata_map.fields.contains(entry.key_ptr.*))
            {
                continue;
            }
            const meta_val = try self.json_to_metadata_value(
                entry.value_ptr.*,
            );
            const key = try self.allocator.dupe(u8, entry.key_ptr.*);
            try self.metadata_map.fields.put(self.allocator, key, meta_val);
        }
    }

    /// Content hash key of `json_val`: the first 8 bytes of the Blake3 hash
    /// of its JSON text, as 16 lowercase hex characters.
    pub fn hash_key(
        json_val: std.json.Value,
    ) [16]u8
    {
        // Serialize JSON to string for hashing
        var hash_buffer: [32 * 1024]u8 = undefined;
        var stream: std.Io.Writer = .fixed(&hash_buffer);
        serialize_json_for_hash(json_val, &stream);

        var hasher = std.crypto.hash.Blake3.init(.{});
        hasher.update(stream.buffered());
        var hash_bytes: [8]u8 = undefined;
        hasher.final(&hash_bytes);

        var result: [16]u8 = undefined;
        _ = std.fmt.bufPrint(
            &result,
            "{x:0>16}",
            .{ std.mem.readInt(u64, &hash_bytes, .big) },
        ) catch unreachable;
        return result;
    }

    /// Add metadata to the map and return its Blake3 hash key as a hex string.
    /// If metadata with the same hash already exists, just returns the
    /// existing key.
    pub fn add_metadata(
        self: *MetadataContext,
        json_val: std.json.Value,
    ) ![]const u8
    {
        const key = hash_key(json_val);

        // Already stored: return a copy of the key.
        if (self.metadata_map.fields.contains(&key))
        {
            return try self.allocator.dupe(u8, &key);
        }

        const hash_str = try self.allocator.dupe(u8, &key);
        errdefer self.allocator.free(hash_str);

        // Convert and store metadata
        const meta_val = try self.json_to_metadata_value(json_val);
        try self.metadata_map.fields.put(
            self.allocator,
            hash_str,
            meta_val,
        );

        // The map owns `hash_str` as its key; the caller gets its own copy.
        return try self.allocator.dupe(u8, hash_str);
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
        .@"union" => |u| try metadata_value_to_json(allocator, u.value.*),
        .@"enum" => |e| .{ .string = try allocator.dupe(u8, e) },
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
            var json_obj: std.json.ObjectMap = .empty;
            var iter = kv.fields.iterator();
            while (iter.next())
                |entry|
            {
                const key = try allocator.dupe(u8, entry.key_ptr.*);
                const val = try metadata_value_to_json(
                    allocator,
                    entry.value_ptr.*,
                );
                try json_obj.put(allocator, key, val);
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
    var json_obj: std.json.ObjectMap = .empty;
    var iter = mm.fields.iterator();
    while (iter.next())
        |entry|
    {
        const key = try allocator.dupe(u8, entry.key_ptr.*);
        const val = try metadata_value_to_json(
            allocator,
            entry.value_ptr.*,
        );
        try json_obj.put(allocator, key, val);
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
pub fn serializable_to_interval(
    ser: SerializableContinuousInterval,
) opentime.ContinuousInterval
{
    return .{
        .start = opentime.Ordinate.init(ser[0]),
        .end = opentime.Ordinate.init(ser[1]),
    };
}

/// Convert optional serializable interval to ContinuousInterval
pub fn serializable_to_optional_interval(
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

/// The v0 -> v1 change for timelines (v0 is OTIO-JSON-shaped data): fill in
/// transition containers and kinds.  Called from `versioning.DocumentUpgrades`,
/// which owns the version number.
pub fn fix_v0_transitions(
    allocator: std.mem.Allocator,
    timeline: *SerializableTimeline,
) !void
{
    for (timeline.children)
        |*child|
    {
        try fix_transitions_in_composable(allocator, child);
    }
}

/// A serialized document: one schema version for the whole file, and its
/// root content (a timeline or a collection).
pub const SerializableRoot = struct {
    schema_version: u32 = versioning.CURRENT_SCHEMA_VERSION,
    content: Content,

    pub const Content = union(enum) {
        timeline: SerializableTimeline,
        collection: SerializableCollection,
    };

    /// Free all memory associated with this root.
    pub fn deinit(
        self: *@This(),
        allocator: std.mem.Allocator,
    ) void
    {
        switch (self.content) {
            .timeline => |*t| t.deinit(allocator),
            .collection => |*c| c.deinit(allocator),
        }
    }

    pub fn is_timeline(
        self: @This(),
    ) bool
    {
        return self.content == .timeline;
    }

    pub fn is_collection(
        self: @This(),
    ) bool
    {
        return self.content == .collection;
    }

    /// Deep copy that owns all of its memory; free it with `deinit`.
    pub fn clone(
        self: @This(),
        allocator: std.mem.Allocator,
    ) !SerializableRoot
    {
        return try deep_clone(SerializableRoot, allocator, self);
    }

    /// Convert a schema handle (timeline or collection) to a root at the
    /// current schema version.  Allocates memory; caller owns the result.
    pub fn from_schema_handle(
        allocator: std.mem.Allocator,
        handle: schema.references.CompositionItemHandle,
    ) !SerializableRoot
    {
        return .{
            .content = switch (handle) {
                .timeline => |t| .{
                    .timeline = try SerializableTimeline.from(allocator, t),
                },
                .collection => |c| .{
                    .collection = try collection_to_serializable(
                        allocator,
                        c,
                    ),
                },
                else => return error.ExpectedTimelineOrCollection,
            },
        };
    }

    /// Convert the content to a schema handle.  Allocates memory; caller owns
    /// the result.
    pub fn to_schema_handle(
        self: @This(),
        allocator: std.mem.Allocator,
    ) !schema.references.CompositionItemHandle
    {
        return switch (self.content) {
            .timeline => |t| .{
                .timeline = try serializable_to_timeline(allocator, t),
            },
            .collection => |c| .{
                .collection = try serializable_to_collection(allocator, c),
            },
        };
    }

    /// Bring a freshly read root up to the current schema version, applying
    /// the steps in `versioning.DocumentUpgrades`.  Every read path calls
    /// this, so callers always receive current data regardless of source.
    ///
    /// `error.SchemaVersionNewerThanSupported` for data newer than this
    /// library (the newer library must downgrade it first);
    /// `error.UpgradeNotSupported` for data older than the oldest readable
    /// version of its root kind.
    pub fn finalize(
        self: *@This(),
        allocator: std.mem.Allocator,
    ) !void
    {
        const oldest: u32 = switch (self.content) {
            .timeline => versioning.OLDEST_TIMELINE_VERSION,
            .collection => versioning.OLDEST_COLLECTION_VERSION,
        };
        if (self.schema_version < oldest)
        {
            return error.UpgradeNotSupported;
        }
        try versioning.upgrade_with(
            versioning.DocumentUpgrades,
            allocator,
            self,
            versioning.CURRENT_SCHEMA_VERSION,
        );
    }
};

/// What a codec reads and writes: the document's schema version and one
/// kind of root content.
pub fn Document(
    comptime Content: type,
) type
{
    return struct {
        schema_version: u32,
        content: Content,
    };
}

/// How `convert` treats values whose type is the same in source and
/// destination and that contain nothing the hooks override.
pub const ConvertMode = enum {
    /// Return them as-is: the result borrows from the source.  For
    /// short-lived layouts (e.g. building a write in an arena).
    share,
    /// Deep-copy them (`deep_clone`): the result owns all of its memory.
    copy,
};

/// Map `value` from type `Src` to type `Dst`, typically between two
/// instances of `Tree` (or document layouts built from them).
///
/// Structs are rebuilt field by field (by `Dst`'s field names), unions by
/// tag name, slices, single-item pointers and optionals element by element.
/// Values the hooks override are converted by the hooks; other values whose
/// type is the same on both sides are shared or copied (see `ConvertMode`).
///
/// `Hooks` declares:
///
/// ```
/// pub const mode: ConvertMode;
/// pub const Error: type; // includes error.OutOfMemory
/// pub fn overrides(comptime T: type) bool;
/// pub fn override(self: *Hooks, comptime Src: type, comptime Dst: type,
///     allocator: std.mem.Allocator, value: Src) Error!Dst;
/// ```
///
/// An override may recurse with `convert_fields` (possibly with another
/// `Hooks` value, e.g. one bound to a nested timeline's metadata map).
pub fn convert(
    comptime Src: type,
    comptime Dst: type,
    comptime Hooks: type,
    hooks: *Hooks,
    allocator: std.mem.Allocator,
    value: Src,
) Hooks.Error!Dst
{
    if (comptime Hooks.overrides(Src))
    {
        return try hooks.override(Src, Dst, allocator, value);
    }

    if (comptime Src == Dst and !reaches_override(Hooks, Src))
    {
        return switch (Hooks.mode) {
            .share => value,
            .copy => try deep_clone(Src, allocator, value),
        };
    }

    switch (@typeInfo(Dst)) {
        .optional => |info| {
            const inner = value orelse return null;
            return try convert(
                @typeInfo(Src).optional.child,
                info.child,
                Hooks,
                hooks,
                allocator,
                inner,
            );
        },
        .pointer => |info| switch (info.size) {
            .one => {
                const result = try allocator.create(info.child);
                result.* = try convert(
                    @typeInfo(Src).pointer.child,
                    info.child,
                    Hooks,
                    hooks,
                    allocator,
                    value.*,
                );
                return result;
            },
            .slice => {
                const result = try allocator.alloc(info.child, value.len);
                for (value, result)
                    |item, *out|
                {
                    out.* = try convert(
                        @typeInfo(Src).pointer.child,
                        info.child,
                        Hooks,
                        hooks,
                        allocator,
                        item,
                    );
                }
                return result;
            },
            else => @compileError(
                "convert: unsupported pointer type " ++ @typeName(Dst)
            ),
        },
        .@"struct" => {
            return try convert_fields(
                Src,
                Dst,
                Hooks,
                hooks,
                allocator,
                value,
            );
        },
        .@"union" => {
            switch (value) {
                inline else => |payload, tag| {
                    const name = @tagName(tag);
                    return @unionInit(
                        Dst,
                        name,
                        try convert(
                            @TypeOf(payload),
                            @FieldType(Dst, name),
                            Hooks,
                            hooks,
                            allocator,
                            payload,
                        ),
                    );
                },
            }
        },
        else => @compileError(
            "convert: cannot map " ++ @typeName(Src) ++ " to "
            ++ @typeName(Dst)
        ),
    }
}

/// Build struct `Dst` from struct `value` field by field (by `Dst`'s field
/// names, each converted with `convert`), without checking whether `Src`
/// itself is overridden.  For overrides that convert most fields normally.
pub fn convert_fields(
    comptime Src: type,
    comptime Dst: type,
    comptime Hooks: type,
    hooks: *Hooks,
    allocator: std.mem.Allocator,
    value: Src,
) Hooks.Error!Dst
{
    const info = @typeInfo(Dst).@"struct";
    var result: Dst = undefined;
    inline for (info.field_names, info.field_types, info.field_attrs)
        |name, FieldType, attrs|
    {
        if (comptime attrs.@"comptime")
        {
            continue;
        }
        @field(result, name) = try convert(
            @FieldType(Src, name),
            FieldType,
            Hooks,
            hooks,
            allocator,
            @field(value, name),
        );
    }
    return result;
}

/// True if a value of type `T` can contain a value `Hooks` overrides.
fn reaches_override(
    comptime Hooks: type,
    comptime T: type,
) bool
{
    @setEvalBranchQuota(100_000);
    return comptime reaches_override_visiting(Hooks, T, &.{});
}

fn reaches_override_visiting(
    comptime Hooks: type,
    comptime T: type,
    comptime visited: []const type,
) bool
{
    if (Hooks.overrides(T))
    {
        return true;
    }
    // metadata values are leaves: hooks never override inside them
    if (T == MetadataMap or T == MetadataValue)
    {
        return false;
    }
    for (visited)
        |V|
    {
        if (V == T)
        {
            return false;
        }
    }
    const next = visited ++ [_]type{T};

    return switch (@typeInfo(T)) {
        .optional => |info| reaches_override_visiting(Hooks, info.child, next),
        .array => |info| reaches_override_visiting(Hooks, info.child, next),
        .pointer => |info| reaches_override_visiting(Hooks, info.child, next),
        .@"struct" => |info| for (info.field_types)
            |FieldType|
        {
            if (reaches_override_visiting(Hooks, FieldType, next))
            {
                break true;
            }
        } else false,
        .@"union" => |info| for (info.field_types)
            |FieldType|
        {
            if (reaches_override_visiting(Hooks, FieldType, next))
            {
                break true;
            }
        } else false,
        else => false,
    };
}

/// Deep-copy a serializable value of type `T` so the copy owns all of its
/// memory (every slice, string, pointer and metadata map is duplicated) and
/// can be freed with its `deinit` independently of `value`.
///
/// Works by reflection, so new fields on serializable types are copied
/// automatically.  On OutOfMemory the partial copy is leaked.
pub fn deep_clone(
    comptime T: type,
    allocator: std.mem.Allocator,
    value: T,
) error{OutOfMemory}!T
{
    if (T == MetadataMap)
    {
        var result: MetadataMap = .{ .container_kind = value.container_kind };
        try result.fields.ensureTotalCapacity(allocator, value.fields.count());
        var iter = value.fields.iterator();
        while (iter.next())
            |entry|
        {
            result.fields.putAssumeCapacity(
                try allocator.dupe(u8, entry.key_ptr.*),
                try deep_clone(MetadataValue, allocator, entry.value_ptr.*),
            );
        }
        return result;
    }

    switch (@typeInfo(T)) {
        .int, .float, .bool, .@"enum", .void, .comptime_int, .comptime_float => {
            return value;
        },
        .optional => |info| {
            const inner = value orelse return null;
            return try deep_clone(info.child, allocator, inner);
        },
        .array => |info| {
            var result: T = undefined;
            for (value, 0..)
                |item, i|
            {
                result[i] = try deep_clone(info.child, allocator, item);
            }
            return result;
        },
        .pointer => |info| switch (info.size) {
            .one => {
                const result = try allocator.create(info.child);
                result.* = try deep_clone(info.child, allocator, value.*);
                return result;
            },
            .slice => {
                const result = try allocator.alloc(info.child, value.len);
                for (value, 0..)
                    |item, i|
                {
                    result[i] = try deep_clone(info.child, allocator, item);
                }
                return result;
            },
            else => @compileError(
                "deep_clone: unsupported pointer type " ++ @typeName(T)
            ),
        },
        .@"struct" => |info| {
            var result: T = undefined;
            inline for (info.field_names, info.field_types, info.field_attrs)
                |name, FieldType, attrs|
            {
                if (comptime attrs.@"comptime")
                {
                    continue;
                }
                @field(result, name) = try deep_clone(
                    FieldType,
                    allocator,
                    @field(value, name),
                );
            }
            return result;
        },
        .@"union" => {
            switch (value) {
                inline else => |payload, tag| {
                    return @unionInit(
                        T,
                        @tagName(tag),
                        try deep_clone(@TypeOf(payload), allocator, payload),
                    );
                },
            }
        },
        else => @compileError("deep_clone: unsupported type " ++ @typeName(T)),
    }
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

/// Resolves clip metadata hashes against a root's metadata map while
/// converting serializable data to schema objects, and tracks which entries
/// clips referenced so the rest can stay on the timeline/collection.
const MetadataResolver = struct {
    allocator: std.mem.Allocator,
    maybe_map: ?*const MetadataMap,
    /// Keys referenced by clips (slices owned by the serializable data).
    referenced: std.StringHashMapUnmanaged(void) = .empty,

    fn init(
        allocator: std.mem.Allocator,
        maybe_map: ?*const MetadataMap,
    ) MetadataResolver
    {
        return .{ .allocator = allocator, .maybe_map = maybe_map };
    }

    fn deinit(
        self: *@This(),
    ) void
    {
        self.referenced.deinit(self.allocator);
    }

    /// The metadata for a clip's `metadata_hash`, as JSON owned by the
    /// caller, or null if the clip has none.
    fn clip_metadata(
        self: *@This(),
        maybe_hash: ?[]const u8,
    ) error{OutOfMemory}!?std.json.Value
    {
        const hash = maybe_hash orelse return null;
        const map = self.maybe_map orelse return null;
        const value = map.fields.get(hash) orelse return null;
        try self.referenced.put(self.allocator, hash, {});
        return try metadata_value_to_json(self.allocator, value);
    }

    /// The entries no clip referenced, as a JSON object owned by the caller,
    /// or null if there are none.
    fn unreferenced_json(
        self: *@This(),
    ) error{OutOfMemory}!?std.json.Value
    {
        const map = self.maybe_map orelse return null;
        var result: std.json.ObjectMap = .empty;
        errdefer json_metadata.deinit(self.allocator, .{ .object = result });

        var iter = map.fields.iterator();
        while (iter.next())
            |entry|
        {
            if (self.referenced.contains(entry.key_ptr.*))
            {
                continue;
            }
            const key = try self.allocator.dupe(u8, entry.key_ptr.*);
            errdefer self.allocator.free(key);
            const value = try metadata_value_to_json(
                self.allocator,
                entry.value_ptr.*,
            );
            try result.put(self.allocator, key, value);
        }

        if (result.count() == 0)
        {
            result.deinit(self.allocator);
            return null;
        }
        return .{ .object = result };
    }
};

fn serializable_to_clip(
    allocator: std.mem.Allocator,
    resolver: *MetadataResolver,
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
        .maybe_metadata_json = try resolver.clip_metadata(
            ser_clip.metadata_hash,
        ),
    };
    return clip_ptr;
}

pub fn serializable_to_gap(
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
    resolver: *MetadataResolver,
    ser_warp: SerializableWarp,
) !*schema.Warp
{
    const warp_ptr = try allocator.create(schema.Warp);
    warp_ptr.* = .{
        .name = try allocator.dupe(u8, ser_warp.name),
        .child = try serializable_to_composable(
            allocator,
            resolver,
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
    resolver: *MetadataResolver,
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
            resolver,
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
    resolver: *MetadataResolver,
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
            resolver,
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
    resolver: *MetadataResolver,
    ser_trans: SerializableTransition,
) !*schema.Transition
{
    const container_ptr = try serializable_to_stack(
        allocator,
        resolver,
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
    resolver: *MetadataResolver,
    ser_comp: SerializableComposable,
) error{ OutOfMemory, MissingDiscretePartition }!schema.references.CompositionItemHandle
{
    return switch (ser_comp) {
        .clip => |clip_val| .{
            .clip = try serializable_to_clip(allocator, resolver, clip_val),
        },
        .gap => |gap_val| .{
            .gap = try serializable_to_gap(allocator, gap_val),
        },
        .track => |track_val| .{
            .track = try serializable_to_track(allocator, resolver, track_val),
        },
        .stack => |stack_val| .{
            .stack = try serializable_to_stack(allocator, resolver, stack_val),
        },
        .warp => |warp_val| .{
            .warp = try serializable_to_warp(allocator, resolver, warp_val),
        },
        .transition => |trans_val| .{
            .transition = try serializable_to_transition(allocator, resolver, trans_val),
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

    var resolver: MetadataResolver = .init(
        allocator,
        if (intermediate_tl.metadata_map)
            |*mm|
            mm
        else
            null,
    );
    defer resolver.deinit();

    for (intermediate_tl.children, 0..)
        |ser_child, i|
    {
        children[i] = try serializable_to_composable(
            allocator,
            &resolver,
            ser_child,
        );
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
        // Entries clips reference now live on those clips.
        .metadata_map = try resolver.unreferenced_json(),
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

    var resolver: MetadataResolver = .init(
        allocator,
        if (ser_coll.metadata_map)
            |*mm|
            mm
        else
            null,
    );
    defer resolver.deinit();

    for (ser_coll.children, 0..)
        |ser_child, i|
    {
        children[i] = try serializable_collection_item_to_handle(
            allocator,
            &resolver,
            ser_child,
        );
    }

    const collection_ptr = try allocator.create(schema.Collection);
    collection_ptr.* = .{
        .name = try allocator.dupe(u8, ser_coll.name),
        .description = try allocator.dupe(u8, ser_coll.description),
        .children = children,
        // Entries clips reference now live on those clips.
        .maybe_metadata_json = try resolver.unreferenced_json(),
    };

    return collection_ptr;
}

/// Convert SerializableCollectionItem to schema.CompositionItemHandle
fn serializable_collection_item_to_handle(
    allocator: std.mem.Allocator,
    resolver: *MetadataResolver,
    ser_item: SerializableCollectionItem,
) !schema.references.CompositionItemHandle
{
    return switch (ser_item) {
        .timeline => |tl| .{
            .timeline = try serializable_to_timeline(allocator, tl),
        },
        .clip => |clip_val| .{
            .clip = try serializable_to_clip(allocator, resolver, clip_val),
        },
        .gap => |gap_val| .{
            .gap = try serializable_to_gap(allocator, gap_val),
        },
        .track => |track_val| .{
            .track = try serializable_to_track(allocator, resolver, track_val),
        },
        .stack => |stack_val| .{
            .stack = try serializable_to_stack(allocator, resolver, stack_val),
        },
        .warp => |warp_val| .{
            .warp = try serializable_to_warp(allocator, resolver, warp_val),
        },
        .transition => |trans_val| .{
            .transition = try serializable_to_transition(allocator, resolver, trans_val),
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
    var metadata_map: MetadataMap = .empty;
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

    // Collection-level entries no clip references.
    if (collection.maybe_metadata_json)
        |json_val|
    {
        try meta_ctx.merge_json_object(json_val);
    }

    return .{
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
pub fn bezier_curve_to_serializable(
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
pub fn serializable_to_bezier_curve(
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
pub fn linear_curve_to_serializable(
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
pub fn serializable_to_linear_curve(
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
// Tests
// ----------------------------------------------------------------------------

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
    var resolver: MetadataResolver = .init(allocator, null);
    defer resolver.deinit();
    const clip_ptr = try serializable_to_clip(allocator, &resolver, ser_clip);
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

test "serializable: SerializableRoot.finalize upgrades and enforces the oldest version"
{
    const allocator = std.testing.allocator;

    // A v0 timeline is upgraded to the current version.
    var v0: SerializableRoot = .{
        .schema_version = 0,
        .content = .{
            .timeline = .{
                .name = "",
                .children = &.{},
                .presentation_space_discrete_partitions = .{},
            },
        },
    };
    try v0.finalize(allocator);
    try std.testing.expectEqual(
        versioning.CURRENT_SCHEMA_VERSION,
        v0.schema_version,
    );

    // Current data is left untouched.
    var current: SerializableRoot = .{
        .content = .{ .collection = .{ .children = &.{} } },
    };
    try current.finalize(allocator);
    try std.testing.expectEqual(
        versioning.CURRENT_SCHEMA_VERSION,
        current.schema_version,
    );

    // Collections did not exist before OLDEST_COLLECTION_VERSION.
    if (versioning.OLDEST_COLLECTION_VERSION > 0)
    {
        var too_old: SerializableRoot = .{
            .schema_version = versioning.OLDEST_COLLECTION_VERSION - 1,
            .content = .{ .collection = .{ .children = &.{} } },
        };
        try std.testing.expectError(
            error.UpgradeNotSupported,
            too_old.finalize(allocator),
        );
    }

    // Newer than this library: unreadable.
    var newer: SerializableRoot = .{
        .schema_version = versioning.CURRENT_SCHEMA_VERSION + 1,
        .content = .{ .collection = .{ .children = &.{} } },
    };
    try std.testing.expectError(
        error.SchemaVersionNewerThanSupported,
        newer.finalize(allocator),
    );
}

/// Test hooks for `convert`: rename every clip.
fn RenameClips(
    comptime convert_mode: ConvertMode,
) type
{
    return struct {
        pub const mode = convert_mode;
        pub const Error = error{OutOfMemory};

        pub fn overrides(
            comptime T: type,
        ) bool
        {
            return T == SerializableClip;
        }

        pub fn override(
            self: *@This(),
            comptime Src: type,
            comptime Dst: type,
            allocator: std.mem.Allocator,
            value: Src,
        ) Error!Dst
        {
            var result = try convert_fields(
                Src,
                Dst,
                @This(),
                self,
                allocator,
                value,
            );
            if (mode == .copy)
            {
                allocator.free(result.name);
                result.name = try allocator.dupe(u8, "renamed");
            }
            else
            {
                result.name = "renamed";
            }
            return result;
        }
    };
}

test "serializable: convert overrides values and shares or copies the rest"
{
    const allocator = std.testing.allocator;

    var clip_children = [_]SerializableComposable{
        .{
            .clip = .{
                .name = "clip",
                .media = .{
                    .data_reference = .{
                        .uri = .{ .target_uri = "file:///a.mov" },
                    },
                    .domain = .picture,
                },
                .metadata_hash = "0123456789abcdef",
            },
        },
        .{ .gap = .{ .name = "gap", .bounds_s = .{ 0, 1 } } },
    };
    var markers = [_]SerializableMarker{
        .{ .name = "m", .marked_range = .{ 0, 1 }, .color = "red" },
    };
    var top = [_]SerializableComposable{
        .{
            .track = .{
                .name = "track",
                .children = &clip_children,
                .markers = &markers,
            },
        },
    };
    const literal: SerializableTimeline = .{
        .name = "timeline",
        .children = &top,
        .presentation_space_discrete_partitions = .{},
    };

    // .share: containers of clips are rebuilt, everything else is shared
    {
        var arena: std.heap.ArenaAllocator = .init(allocator);
        defer arena.deinit();
        var hooks: RenameClips(.share) = .{};
        const shared = try convert(
            SerializableTimeline,
            SerializableTimeline,
            RenameClips(.share),
            &hooks,
            arena.allocator(),
            literal,
        );
        const track = shared.children[0].track;
        try std.testing.expect(track.children.ptr != &clip_children);
        try std.testing.expectEqualStrings("renamed", track.children[0].clip.name);
        try std.testing.expectEqualStrings(
            "0123456789abcdef",
            track.children[0].clip.metadata_hash.?,
        );
        try std.testing.expect(track.markers.ptr == &markers);
        try std.testing.expect(
            track.children[1].gap.name.ptr == clip_children[1].gap.name.ptr
        );
        try std.testing.expectEqualStrings("clip", clip_children[0].clip.name);
    }

    // .copy: the result owns all of its memory
    {
        var source = try deep_clone(SerializableTimeline, allocator, literal);
        var hooks: RenameClips(.copy) = .{};
        var copied = try convert(
            SerializableTimeline,
            SerializableTimeline,
            RenameClips(.copy),
            &hooks,
            allocator,
            source,
        );
        defer copied.deinit(allocator);
        source.deinit(allocator);

        const track = copied.children[0].track;
        try std.testing.expectEqualStrings("renamed", track.children[0].clip.name);
        try std.testing.expectEqualStrings("gap", track.children[1].gap.name);
        try std.testing.expectEqualStrings("red", track.markers[0].color);
    }
}
