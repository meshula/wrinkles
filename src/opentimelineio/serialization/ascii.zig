//! TLA / TLCA codec: the human-readable ziggy encoding of timelines and
//! collections.
//!
//! Reads and writes the intermediate representation defined in
//! serializable.zig.  Also defines the TLA-only output variants
//! (`*InlineMetadata`, `*NoMetadata`, `*StrippedMetadata`) used for the
//! metadata output modes and for skipping metadata while parsing.
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
const format_m = @import("format.zig");
const serializable = @import("serializable.zig");

// Intermediate representation types and helpers (see serializable.zig)
const MetadataContext = serializable.MetadataContext;
const MetadataMap = serializable.MetadataMap;
const MetadataValue = serializable.MetadataValue;
const SerializableAffineTransform1D = serializable.SerializableAffineTransform1D;
const SerializableBezierCurve = serializable.SerializableBezierCurve;
const SerializableBounds = serializable.SerializableBounds;
const SerializableClip = serializable.SerializableClip;
const SerializableCollection = serializable.SerializableCollection;
const SerializableCollectionItem = serializable.SerializableCollectionItem;
const SerializableComposable = serializable.SerializableComposable;
const SerializableContinuousInterval = serializable.SerializableContinuousInterval;
const SerializableControlPoint = serializable.SerializableControlPoint;
const SerializableDiscretePartitionDomainMap = serializable.SerializableDiscretePartitionDomainMap;
const SerializableDomain = serializable.SerializableDomain;
const SerializableGap = serializable.SerializableGap;
const SerializableImageSequenceReference = serializable.SerializableImageSequenceReference;
const SerializableLinearCurve = serializable.SerializableLinearCurve;
const SerializableMapping = serializable.SerializableMapping;
const SerializableMappingAffine = serializable.SerializableMappingAffine;
const SerializableMappingLinear = serializable.SerializableMappingLinear;
const SerializableMarker = serializable.SerializableMarker;
const SerializableMediaDataReference = serializable.SerializableMediaDataReference;
const SerializableMediaReference = serializable.SerializableMediaReference;
const SerializableRateSpecifier = serializable.SerializableRateSpecifier;
const SerializableSampleIndexGenerator = serializable.SerializableSampleIndexGenerator;
const SerializableSignalGenerator = serializable.SerializableSignalGenerator;
const SerializableSignalReference = serializable.SerializableSignalReference;
const SerializableStack = serializable.SerializableStack;
const SerializableTimeline = serializable.SerializableTimeline;
const SerializableTopology = serializable.SerializableTopology;
const SerializableTrack = serializable.SerializableTrack;
const SerializableTransition = serializable.SerializableTransition;
const SerializableURIReference = serializable.SerializableURIReference;
const SerializableWarp = serializable.SerializableWarp;
const bezier_curve_to_serializable = serializable.bezier_curve_to_serializable;
const hash_to_hex_string = serializable.hash_to_hex_string;
const hex_string_to_hash = serializable.hex_string_to_hash;
const linear_curve_to_serializable = serializable.linear_curve_to_serializable;
const serializable_to_bezier_curve = serializable.serializable_to_bezier_curve;
const serializable_to_gap = serializable.serializable_to_gap;
const serializable_to_interval = serializable.serializable_to_interval;
const serializable_to_linear_curve = serializable.serializable_to_linear_curve;
const serializable_to_optional_interval = serializable.serializable_to_optional_interval;
const serializable_to_timeline = serializable.serializable_to_timeline;

/// Write a Timeline to a writer in the specified format.
/// Converts to serializable format internally.
fn write_timeline_to_writer(
    allocator: std.mem.Allocator,
    timeline: *schema.Timeline,
    format: FileFormat,
    metadata_mode: format_m.WriteOptions.MetadataMode,
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

/// Marker for OTIO JSON source (version 0)
const OTIO_JSON_VERSION: u32 = 0;

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

/// A placeholder that consumes one complete ziggy value from the token stream
/// and discards it without allocating or building any data.
///
/// Used in place of fields that should be ignored during deserialization
/// (for example `metadata_map` when reading with `.all_except_metadata`).
/// Brackets are counted rather than matched, so a malformed document inside
/// the skipped value is not detected.
pub const SkippedValue = struct {
    pub const ziggy_options: ziggy.Options(@This()) = .{
        .deserialize = skip,
        .roles = .any,
    };

    fn skip(
        d: *const ziggy.Deserializer,
        first: ziggy.Tokenizer.Token,
        _: bool,
    ) ziggy.Deserializer.Error!SkippedValue
    {
        var depth: usize = 0;
        var tok = first;
        while (true)
        {
            switch (tok.tag) {
                .dotlb, .lb, .lsb, .union_case => depth += 1,
                .rb, .rsb, .rp => {
                    if (depth == 0)
                    {
                        return d.unexpected(tok);
                    }
                    depth -= 1;
                },
                .eof, .eod, .invalid, .invalid_control => {
                    return d.unexpected(tok);
                },
                else => {},
            }

            if (depth == 0)
            {
                // a multiline string is a run of consecutive `\\` lines
                if (tok.tag == .bytes_line)
                {
                    while (d.peek() == .bytes_line)
                    {
                        _ = try d.next();
                    }
                }
                return .{};
            }

            tok = try d.next();
        }
    }
};

/// Variant of SerializableTimeline that skips metadata_map during parsing.
/// Used when content_filter == .all_except_metadata.
///
/// `metadata_map` is a `SkippedValue`, which consumes the value's tokens
/// without building it, providing significant performance gains for large
/// files.  (ziggy's `skip_fields` is not used: it rejects documents that
/// contain the skipped field.)
pub const SerializableTimelineNoMetadata = struct {
    pub const schema_name: []const u8 = "Timeline";

    schema_version: u32 = versioning.CURRENT_SCHEMA_VERSION,
    name: []const u8 = "",
    children: []SerializableComposable,
    presentation_space_discrete_partitions: SerializableDiscretePartitionDomainMap,
    /// Consumed and discarded during parsing.
    metadata_map: SkippedValue = .{},
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

        // metadata_map is a SkippedValue and owns no memory
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

    schema_version: u32 = versioning.CURRENT_SCHEMA_VERSION,
    name: []const u8 = "",
    children: []SerializableComposableInlineMetadata,
    presentation_space_discrete_partitions: SerializableDiscretePartitionDomainMap,
    // No metadata_map field - metadata is inline on clips
};

/// Timeline variant for output without any metadata
pub const SerializableTimelineStrippedMetadata = struct {
    pub const schema_name: []const u8 = "Timeline";

    schema_version: u32 = versioning.CURRENT_SCHEMA_VERSION,
    name: []const u8 = "",
    children: []SerializableComposableNoMetadata,
    presentation_space_discrete_partitions: SerializableDiscretePartitionDomainMap,
    // No metadata_map field
};

/// Collection variant for inline metadata output (no metadata_map, metadata
/// inline on clips)
pub const SerializableCollectionInlineMetadata = struct {
    pub const schema_name: []const u8 = "Collection";

    schema_version: u32 = versioning.CURRENT_SCHEMA_VERSION,
    name: []const u8 = "",
    description: []const u8 = "",
    children: []SerializableCollectionItemInlineMetadata,
    // No metadata_map field - metadata is inline on clips
};

/// Collection variant for output without any metadata
pub const SerializableCollectionStrippedMetadata = struct {
    pub const schema_name: []const u8 = "Collection";

    schema_version: u32 = versioning.CURRENT_SCHEMA_VERSION,
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
// Main Serialization Entry Points (using tla)
// ----------------------------------------------------------------------------

/// Serialize a Timeline to tla format and write to the provided writer.
fn serialize_timeline(
    timeline: *schema.Timeline,
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
) !void
{
    // Convert to serializable format
    var intermediate_tl = try SerializableTimeline.from(
        allocator,
        timeline,
    );
    defer intermediate_tl.deinit(allocator);

    // Serialize directly - ziggy 0.1.0 CAN parse unions in arrays!
    try ziggy.serialize(
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
/// field's tokens are consumed without being parsed (see `SkippedValue`).
/// This provides significant performance gains for large files with
/// extensive metadata.
pub fn deserialize_timeline(
    allocator: std.mem.Allocator,
    source: [:0]const u8,
    content_filter: format_m.ReadOptions.ContentFilter,
) !*schema.Timeline
{
    var meta: ziggy.Deserializer.Meta = .init;
    var serializable_tl = switch (content_filter) {
        .all => try ziggy.deserializeLeaky(
            SerializableTimeline,
            allocator,
            source,
            &meta,
            .{ .copy_strings = .always },
        ),
        .all_except_metadata => s_t: {
            // Use the no-metadata variant that skips parsing metadata_map entirely
            var serializable_tl_no_md = try ziggy.deserializeLeaky(
                SerializableTimelineNoMetadata,
                allocator,
                source,
                &meta,
                .{ .copy_strings = .always },
            );

            // convert back to regular SerializableTimeline
            break :s_t  serializable_tl_no_md.to_serializable_timeline();
        },
        .only_metadata => return error.OnlyMetadataNotSupportedForDeserialization,
    };
    defer serializable_tl.deinit(allocator);

    try serializable.finalize_timeline(allocator, &serializable_tl);

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
    var metadata_map: MetadataMap = .empty;
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
    try serializable.finalize_timeline(allocator, &intermediate_tl);

    return intermediate_tl;
}

// @TODO: collapse these serialize functions that recursively call components
//        down

/// Serialize a Bezier curve to tla format and write to the provided writer.
fn serialize_bezier_curve(
    bezier: curve.Bezier,
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
) !void
{
    // Convert to serializable format
    const ser_bezier = try bezier_curve_to_serializable(
        allocator,
        bezier,
    );

    // Use ziggy to serialize
    try ziggy.serialize(ser_bezier, .{
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
    var meta: ziggy.Deserializer.Meta = .init;
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

/// Serialize a Linear curve to tla format and write to the provided writer.
fn serialize_linear_curve(
    linear: curve.Linear,
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
) !void
{
    // Convert to serializable format
    const ser_linear = try linear_curve_to_serializable(allocator, linear);

    // Use ziggy to serialize
    try ziggy.serialize(ser_linear, .{
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
    var meta: ziggy.Deserializer.Meta = .init;
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
    var buffer: std.Io.Writer.Allocating = .init(allocator);
    defer buffer.deinit();

    try serialize_timeline(
        &timeline,
        allocator,
        &buffer.writer,
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

test "timeline serialization: all_except_metadata skips metadata_map"
{
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // metadata_map exercises every kind of nesting SkippedValue has to
    // balance, and `markers` comes after it (in the document and in the type)
    const source: [:0]const u8 =
        \\.schema_version = 1,
        \\.name = "WithMetadata",
        \\.children = [],
        \\.presentation_space_discrete_partitions = .{},
        \\.metadata_map = {
        \\    "46ce2bb4fbd1c246": {
        \\        "nested": { "a": [1, 2.5, inf, -inf, nan, null, true] },
        \\        "struct_like": .{ .x = "y", .z = [] },
        \\        "tagged": .some_tag(.{ .v = [{}, [], .x(1)] }),
        \\        "enum": .plain_enum,
        \\        "text": "brackets in strings: } ] ) {",
        \\        "lines":
        \\            \\line one }
        \\            \\line two
        \\        ,
        \\    },
        \\},
        \\.markers = [
        \\    .{
        \\        .name = "m1",
        \\        .marked_range = [0, 1],
        \\        .color = "red",
        \\    },
        \\],
        \\
    ;

    var meta: ziggy.Deserializer.Meta = .init;
    const no_md = try ziggy.deserializeLeaky(
        SerializableTimelineNoMetadata,
        allocator,
        source,
        &meta,
        .{},
    );
    try std.testing.expectEqualStrings("WithMetadata", no_md.name);
    try std.testing.expectEqual(@as(usize, 1), no_md.markers.len);
    try std.testing.expectEqualStrings("m1", no_md.markers[0].name);
    try std.testing.expect(
        no_md.to_serializable_timeline().metadata_map == null
    );

    // the full parse of the same document still sees the metadata
    const full = try ziggy.deserializeLeaky(
        SerializableTimeline,
        allocator,
        source,
        &meta,
        .{},
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        full.metadata_map.?.fields.count(),
    );
    try std.testing.expectEqual(@as(usize, 1), full.markers.len);
}

/// Ziggy schema describing the TLA format (see `tla_schema/`).
const TLA_SCHEMA: [:0]const u8 = @embedFile("tla_schema/tla.ziggy-schema");

/// Checked-in TLCA schema, generated from `TLA_SCHEMA`.
const TLCA_SCHEMA: [:0]const u8 = @embedFile("tla_schema/tlca.ziggy-schema");

/// Validate a document against a ziggy schema, printing every mismatch.
fn expect_matches_schema(
    allocator: std.mem.Allocator,
    schema_name: []const u8,
    schema_src: [:0]const u8,
    source: [:0]const u8,
) !void
{
    const schema_ast = try ziggy.schema.Ast.init(allocator, schema_src);
    defer schema_ast.deinit(allocator);
    for (schema_ast.errors)
        |err|
    {
        std.debug.print(
            "{s}: offset {d}: {f}\n",
            .{ schema_name, err.main_location.start, err.tag },
        );
    }
    if (schema_ast.errors.len > 0)
    {
        return error.InvalidSchema;
    }

    const doc_ast = try ziggy.Ast.init(allocator, source, .{});
    defer doc_ast.deinit(allocator);
    if (doc_ast.errors.len > 0)
    {
        return error.DocumentSyntaxError;
    }

    const mismatches = try schema_ast.validate(
        allocator,
        schema_src,
        doc_ast,
        source,
    );
    defer allocator.free(mismatches);
    for (mismatches)
        |mismatch|
    {
        const start = mismatch.main_location.start;
        const line = std.mem.count(u8, source[0..start], "\n") + 1;
        const line_start = (
            if (std.mem.lastIndexOfScalar(u8, source[0..start], '\n'))
                |nl| nl + 1
            else 0
        );
        const line_end = (
            std.mem.indexOfScalarPos(u8, source, start, '\n')
            orelse source.len
        );
        std.debug.print(
            "{s} mismatch at line {d}: {f}\n    {s}\n",
            .{
                schema_name,
                line,
                mismatch.tag,
                source[line_start..line_end],
            },
        );
    }
    if (mismatches.len > 0)
    {
        return error.SchemaMismatch;
    }
}

/// Serialize `value` (a `SerializableTimeline` or `SerializableCollection`)
/// in every metadata mode and validate each against the matching schema.
/// Returns the hash_reference and inline_metadata outputs concatenated, for
/// coverage checks.
fn expect_all_modes_match_schema(
    allocator: std.mem.Allocator,
    value: anytype,
) ![]const u8
{
    const is_collection = @TypeOf(value) == SerializableCollection;
    const schema_name = (
        if (is_collection) "tlca.ziggy-schema" else "tla.ziggy-schema"
    );
    const schema_src = if (is_collection) TLCA_SCHEMA else TLA_SCHEMA;

    var all: std.Io.Writer.Allocating = .init(allocator);
    errdefer all.deinit();

    for (std.meta.tags(format_m.WriteOptions.MetadataMode))
        |mode|
    {
        var buf: std.Io.Writer.Allocating = .init(allocator);
        defer buf.deinit();
        if (is_collection)
        {
            try write_collection_to_writer(
                allocator,
                value,
                .tlca,
                mode,
                &buf.writer,
            );
        }
        else
        {
            try write_serializable_to_writer(
                allocator,
                value,
                .tla,
                mode,
                &buf.writer,
            );
        }
        try buf.writer.writeByte(0);
        const written = buf.written();
        const source: [:0]const u8 = written[0 .. written.len - 1 :0];

        expect_matches_schema(
            allocator,
            schema_name,
            schema_src,
            source,
        ) catch |err| {
            std.debug.print("(metadata mode: {t})\n", .{ mode });
            return err;
        };

        if (mode != .no_metadata)
        {
            try all.writer.writeAll(source);
        }
    }

    return try all.toOwnedSlice();
}

/// True if `text` contains `name` not followed by an identifier character.
fn contains_ident(
    text: []const u8,
    name: []const u8,
) bool
{
    var pos: usize = 0;
    while (std.mem.indexOfPos(u8, text, pos, name))
        |idx|
    {
        const end = idx + name.len;
        if (end == text.len)
        {
            return true;
        }
        switch (text[end]) {
            'a'...'z', 'A'...'Z', '0'...'9', '_' => {},
            else => return true,
        }
        pos = end;
    }
    return false;
}

/// Expect every field (struct) or tag (union) of `T` to appear in `text`,
/// so the schema coverage sample can't silently miss new fields/variants.
fn expect_all_names_serialized(
    comptime T: type,
    text: []const u8,
) !void
{
    const is_struct = @typeInfo(T) == .@"struct";
    const field_names = switch (@typeInfo(T)) {
        .@"struct" => |info| info.field_names,
        .@"union" => |info| info.field_names,
        else => @compileError("expected a struct or union"),
    };
    inline for (field_names)
        |field_name|
    {
        const needle = (
            if (is_struct) "." ++ field_name ++ " =" else "." ++ field_name
        );
        if (!contains_ident(text, needle))
        {
            std.debug.print(
                "{s}.{s} is not covered by the schema coverage sample\n",
                .{ @typeName(T), field_name },
            );
            return error.SchemaSampleIncomplete;
        }
    }
}

/// A timeline that uses every serializable type, field and union variant,
/// for validating the schemas.  Allocate with an arena.
fn schema_coverage_timeline(
    allocator: std.mem.Allocator,
) !SerializableTimeline
{
    const markers = try allocator.dupe(
        SerializableMarker,
        &.{
            .{
                .name = "m",
                .marked_range = .{ 0, 1 },
                .color = "red",
                .comment = "note",
            },
        },
    );
    const rate_24: SerializableSampleIndexGenerator = .{
        .sample_rate_hz = .{ .Integer = 24 },
        .start_index = 1,
    };
    const rate_ntsc: SerializableSampleIndexGenerator = .{
        .sample_rate_hz = .{ .Rational = .{ .num = 24000, .den = 1001 } },
        .start_index = 0,
    };

    // one clip per media data reference / domain variant
    const media_variants = [_]SerializableMediaReference{
        .{
            .data_reference = .{ .uri = .{ .target_uri = "file:///a.mov" } },
            .bounds_s = .{ .continuous = .{ 0, 10 } },
            .domain = .picture,
            .discrete_partition = rate_24,
            .interpolating = .snap,
        },
        .{
            .data_reference = .{
                .signal = .{
                    .signal_generator = .{ .sine = .{ .frequency_hz = 440 } },
                },
            },
            .bounds_s = .{ .discrete = .{ 0, 48000 } },
            .domain = .audio,
        },
        .{
            .data_reference = .{
                .signal = .{ .signal_generator = .linear_ramp },
            },
            .domain = .time,
        },
        .{
            .data_reference = .{
                .image_sequence = .{
                    .target_url_base = "file:///seq/",
                    .name_prefix = "shot.",
                    .name_suffix = ".exr",
                    .frame_zero_padding = 4,
                    .missing_frame_policy = "hold",
                },
            },
            .domain = .metadata,
        },
        .{
            .data_reference = .null,
            .domain = .{ .other = .{ .name = "custom" } },
        },
    };

    var metadata_map: MetadataMap = .empty;
    var clip_metadata: MetadataMap = .empty;
    try clip_metadata.fields.put(allocator, "scene", .{ .bytes = "001" });
    try metadata_map.fields.put(allocator, "0123456789abcdef", .{ .kv = clip_metadata });

    var clips: std.ArrayList(SerializableComposable) = .empty;
    for (media_variants, 0..)
        |media, i|
    {
        try clips.append(
            allocator,
            .{
                .clip = .{
                    .name = "clip",
                    .bounds_s = .{ .discrete = .{ 0, 24 } },
                    .media = media,
                    .metadata_hash = (
                        if (i == 0) "0123456789abcdef" else null
                    ),
                    .markers = markers,
                },
            },
        );
    }

    try clips.append(
        allocator,
        .{
            .gap = .{
                .name = "gap",
                .bounds_s = .{ 0, std.math.inf(f64) },
                .markers = markers,
            },
        },
    );

    const warp_children = [_]SerializableMapping{
        .{
            .affine = .{
                .input_bounds_val = .{ 0, 1 },
                .input_to_output_xform = .{ .offset = 0.5, .scale = 2 },
            },
        },
        .{
            .linear = .{
                .input_bounds_val = .{ 1, 2 },
                .knots = try allocator.dupe(
                    SerializableControlPoint,
                    &.{ .{ 1, 3 }, .{ 2, 4 } },
                ),
            },
        },
        .empty,
    };
    const warped = try allocator.create(SerializableComposable);
    warped.* = clips.items[0];
    try clips.append(
        allocator,
        .{
            .warp = .{
                .name = "warp",
                .child = warped,
                .transform = .{
                    .mappings = try allocator.dupe(
                        SerializableMapping,
                        &warp_children,
                    ),
                },
            },
        },
    );

    try clips.append(
        allocator,
        .{
            .transition = .{
                .name = "transition",
                .container = .{
                    .name = "transition container",
                    .bounds_s = .{ .continuous = .{ 0, 1 } },
                    .children = try allocator.dupe(
                        SerializableComposable,
                        clips.items[0..1],
                    ),
                    .markers = markers,
                },
                .kind = "dissolve",
                .bounds_s = .{ 0, 1 },
            },
        },
    );

    const track: SerializableComposable = .{
        .track = .{
            .name = "track",
            .bounds_s = .{ .continuous = .{ 0, 100 } },
            .children = clips.items,
            .markers = markers,
        },
    };
    const stack: SerializableComposable = .{
        .stack = .{
            .name = "stack",
            .bounds_s = .{ .discrete = .{ 0, 100 } },
            .children = try allocator.dupe(SerializableComposable, &.{ track }),
            .markers = markers,
        },
    };

    return .{
        .name = "schema coverage",
        .children = try allocator.dupe(SerializableComposable, &.{ stack }),
        .presentation_space_discrete_partitions = .{
            .picture = rate_ntsc,
            .audio = rate_24,
        },
        .metadata_map = metadata_map,
        .markers = markers,
    };
}

test "tla schema: every serializable type and variant matches the schema"
{
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const tl = try schema_coverage_timeline(allocator);
    const text = try expect_all_modes_match_schema(allocator, tl);

    // the sample above has to keep exercising everything the serializer
    // can write
    inline for (.{
        SerializableTimeline,
        SerializableDiscretePartitionDomainMap,
        SerializableMarker,
        SerializableComposable,
        SerializableClip,
        SerializableGap,
        SerializableTrack,
        SerializableStack,
        SerializableWarp,
        SerializableTransition,
        SerializableTopology,
        SerializableMapping,
        SerializableMappingAffine,
        SerializableMappingLinear,
        SerializableAffineTransform1D,
        SerializableBounds,
        SerializableMediaReference,
        SerializableMediaDataReference,
        SerializableURIReference,
        SerializableSignalReference,
        SerializableSignalGenerator,
        SerializableImageSequenceReference,
        SerializableDomain,
        SerializableSampleIndexGenerator,
        SerializableRateSpecifier,
        SerializableClipInlineMetadata,
    })
        |T|
    {
        try expect_all_names_serialized(T, text);
    }
}

test "tla schema: fixtures match the schema when re-serialized"
{
    const io = std.testing.io;

    const fixtures = [_][]const u8{
        "test_files/just_clip_ntsc.tla",
        "test_files/just_clip_with_metadata.tla",
        "test_files/just_transition.tla",
        "test_files/just_warp.tla",
        "test_files/just_warp_bez.tla",
        "test_files/just_warp_linear.tla",
        "test_files/simple_cut_with_markers.tla",
        "test_files/simple_cut_with_media.tla",
        "test_files/simple_cut_with_metadata.tla",
        "test_files/simple_image_sequence.tla",
        "test_files/single_discrete_clip.tla",
        "test_files/warp_on_warp.tla",
        "otio_sample_data/generator_reference_test.tla",
        "otio_sample_data/mixed_tracks.tla",
        "otio_sample_data/nested_example.tla",
        "otio_sample_data/transition.tla",
    };

    for (fixtures)
        |path|
    {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const allocator = arena.allocator();

        const tl = read_from_file(allocator, io, path) catch |err| {
            std.debug.print("unable to read {s}: {t}\n", .{ path, err });
            return err;
        };
        _ = expect_all_modes_match_schema(allocator, tl) catch |err| {
            std.debug.print("(fixture: {s})\n", .{ path });
            return err;
        };
    }
}

test "tlca schema: checked-in file is up to date with the generator"
{
    const generator = @import("tla_schema/generate_tlca_schema.zig");
    std.testing.expectEqualStrings(
        generator.TLCA_SCHEMA,
        TLCA_SCHEMA,
    ) catch |err| {
        std.debug.print(
            "tlca.ziggy-schema is stale: run `zig build update_tlca_schema`\n",
            .{},
        );
        return err;
    };
}

test "tlca schema: every collection item kind matches the schema"
{
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const tl = try schema_coverage_timeline(allocator);

    // timeline -> stack -> track -> {clips, gap, warp, transition}
    const stack = tl.children[0].stack;
    const track = stack.children[0].track;

    var items: std.ArrayList(SerializableCollectionItem) = .empty;
    try items.append(allocator, .{ .timeline = tl });
    try items.append(allocator, .{ .stack = stack });
    try items.append(allocator, .{ .track = track });
    var seen_clip = false;
    for (track.children)
        |child|
    {
        switch (child) {
            .clip => |clip| {
                if (seen_clip)
                {
                    continue;
                }
                seen_clip = true;
                try items.append(allocator, .{ .clip = clip });
            },
            .gap => |gap| try items.append(allocator, .{ .gap = gap }),
            .warp => |warp| try items.append(allocator, .{ .warp = warp }),
            .transition => |tr| try items.append(
                allocator,
                .{ .transition = tr },
            ),
            .track, .stack => {},
        }
    }

    const collection: SerializableCollection = .{
        .name = "schema coverage",
        .description = "every collection item kind",
        .children = items.items,
        .metadata_map = tl.metadata_map,
    };

    const text = try expect_all_modes_match_schema(allocator, collection);
    try expect_all_names_serialized(SerializableCollection, text);
    try expect_all_names_serialized(SerializableCollectionItem, text);
}

test "tlca schema: fixtures match the schema when re-serialized"
{
    const io = std.testing.io;

    const fixtures = [_][]const u8{
        "test_files/collection_with_metadata.tlca",
        "test_files/sample_collection.tlca",
    };

    for (fixtures)
        |path|
    {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const allocator = arena.allocator();

        const collection = read_collection_from_file(
            allocator,
            io,
            path,
        ) catch |err| {
            std.debug.print("unable to read {s}: {t}\n", .{ path, err });
            return err;
        };
        _ = expect_all_modes_match_schema(allocator, collection) catch |err| {
            std.debug.print("(fixture: {s})\n", .{ path });
            return err;
        };
    }
}

// ----------------------------------------------------------------------------
// Universal File Reading
// ----------------------------------------------------------------------------


/// Supported file format types for read/write operations.
/// Re-exported from format.zig for backward compatibility.
pub const FileFormat = format_m.FileFormat;

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
    var meta: ziggy.Deserializer.Meta = .init;
    switch (format) {
        .tla => {
            // Ziggy requires null-terminated source
            // Check if already null-terminated
            if (buffer.len > 0 and buffer[buffer.len - 1] == 0) {
                return try ziggy.deserializeLeaky(
                    SerializableTimeline,
                    allocator,
                    buffer[0 .. buffer.len - 1 :0],
                    &meta,
                    .{},
                );
            }
            // Need to add null terminator
            // Note: source_with_null must NOT be freed here because
            // deserializeLeaky returns data containing slices into this buffer.
            // The caller is responsible for managing this memory (typically via
            // an ArenaAllocator).
            const source_with_null = try allocator.alloc(u8, buffer.len + 1);
            @memcpy(source_with_null[0..buffer.len], buffer);
            source_with_null[buffer.len] = 0;
            return try ziggy.deserializeLeaky(
                SerializableTimeline,
                allocator,
                source_with_null[0..buffer.len :0],
                &meta,
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
    io: std.Io,
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
        return try bundle.read_from_file(allocator, io, file_path, .{});
    }

    // For other formats, read the file contents first
    const file = try std.Io.Dir.cwd().openFile(io, file_path, .{});
    defer file.close(io);

    var read_buf: [4096]u8 = undefined;
    var file_reader = file.reader(io, &read_buf);

    if (format == .tla) {
        // Read with null sentinel so ziggy can use the buffer directly.
        // deserializeLeaky stores slices into the source buffer, so this
        // buffer must outlive the returned SerializableTimeline.
        // Callers should use an ArenaAllocator to manage this lifetime.
        const source = try file_reader.interface.allocRemainingAlignedSentinel(
            allocator,
            .unlimited,
            .@"1",
            0,
        );
        var meta: ziggy.Deserializer.Meta = .init;
        return try ziggy.deserializeLeaky(
            SerializableTimeline,
            allocator,
            source,
            &meta,
            .{},
        );
    }

    // For non-TLA formats, read normally
    const source = try file_reader.interface.allocRemaining(
        allocator,
        .unlimited,
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
    metadata_mode: format_m.WriteOptions.MetadataMode = .hash_reference,

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
    metadata_mode: format_m.WriteOptions.MetadataMode,
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
    metadata_mode: format_m.WriteOptions.MetadataMode,
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
    metadata_mode: format_m.WriteOptions.MetadataMode,
    writer: anytype,
) !void
{
    switch (metadata_mode) {
        .hash_reference => {
            // Default behavior - output SerializableTimeline directly
            try ziggy.serialize(
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
            try ziggy.serialize(
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
            try ziggy.serialize(
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
    var meta: ziggy.Deserializer.Meta = .init;
    switch (format) {
        .tlca => {
            // Ziggy requires null-terminated source
            if (buffer.len > 0 and buffer[buffer.len - 1] == 0) {
                return try ziggy.deserializeLeaky(
                    SerializableCollection,
                    allocator,
                    buffer[0 .. buffer.len - 1 :0],
                    &meta,
                    .{},
                );
            }
            // Need to add null terminator
            // Note: source_with_null must NOT be freed here because
            // deserializeLeaky returns data containing slices into this buffer.
            const source_with_null = try allocator.alloc(u8, buffer.len + 1);
            @memcpy(source_with_null[0..buffer.len], buffer);
            source_with_null[buffer.len] = 0;
            return try ziggy.deserializeLeaky(
                SerializableCollection,
                allocator,
                source_with_null[0..buffer.len :0],
                &meta,
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
    io: std.Io,
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
    const file = try std.Io.Dir.cwd().openFile(io, file_path, .{});
    defer file.close(io);

    var read_buf: [4096]u8 = undefined;
    var file_reader = file.reader(io, &read_buf);

    if (format == .tlca) {
        // Read with null sentinel so ziggy can use the buffer directly.
        // deserializeLeaky stores slices into the source buffer, so this
        // buffer must outlive the returned SerializableCollection.
        const source = try file_reader.interface.allocRemainingAlignedSentinel(
            allocator,
            .unlimited,
            .@"1",
            0,
        );
        var meta: ziggy.Deserializer.Meta = .init;
        return try ziggy.deserializeLeaky(
            SerializableCollection,
            allocator,
            source,
            &meta,
            .{},
        );
    }

    // For non-TLCA formats, read normally
    const source = try file_reader.interface.allocRemaining(
        allocator,
        .unlimited,
    );
    defer allocator.free(source);

    return try read_collection_from_buffer(allocator, source, format);
}

/// Options for writing collection files (subset of WriteOptions relevant to collections)
pub const CollectionWriteOptions = struct {
    /// Controls how metadata is output in TLCA format
    metadata_mode: format_m.WriteOptions.MetadataMode = .hash_reference,
};

/// Write a SerializableCollection to a buffer.
/// Supports: .tlca (ASCII Ziggy), .tlcb (FlatBuffers binary)
/// Returns an allocated buffer that the caller must free.
pub fn write_collection_to_buffer(
    allocator: std.mem.Allocator,
    collection: SerializableCollection,
    format: FileFormat,
    metadata_mode: format_m.WriteOptions.MetadataMode,
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
    io: std.Io,
    collection: SerializableCollection,
    file_path: []const u8,
    options: format_m.WriteOptions.MetadataMode,
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
    const file = try std.Io.Dir.cwd().createFile(io,file_path, .{});
    defer file.close(io);

    var file_writer_buffer: [16 * 1024]u8 = undefined;
    var file_writer = file.writer(io, &file_writer_buffer);
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
    metadata_mode: format_m.WriteOptions.MetadataMode,
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
    metadata_mode: format_m.WriteOptions.MetadataMode,
    writer: anytype,
) !void
{
    switch (metadata_mode) {
        .hash_reference => {
            // Default behavior - output SerializableCollection directly
            try ziggy.serialize(
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
            try ziggy.serialize(
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
            try ziggy.serialize(
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

    // Deserialize back using arena (deserializeLeaky stores slices into source)
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const roundtrip = try read_collection_from_buffer(
        arena.allocator(),
        buffer,
        .tlca,
    );

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

    // Read TLCA back using arena (deserializeLeaky stores slices into source)
    var tlca_arena = std.heap.ArenaAllocator.init(allocator);
    defer tlca_arena.deinit();
    const from_tlca = try read_collection_from_buffer(tlca_arena.allocator(), tlca_buffer, .tlca);

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
    metadata_mode: format_m.ReadOptions.ContentFilter,
) anyerror!SerializableTimeline
{
    _ = metadata_mode;

    const buffer = try reader.allocRemaining(
        allocator,
        .unlimited,
    );
    defer allocator.free(buffer);

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
    metadata_mode: format_m.WriteOptions.MetadataMode,
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
    metadata_mode: format_m.ReadOptions.ContentFilter,
) anyerror!SerializableCollection
{
    _ = metadata_mode;

    const buffer = try reader.allocRemaining(
        allocator,
        .unlimited,
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
    metadata_mode: format_m.WriteOptions.MetadataMode,
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
