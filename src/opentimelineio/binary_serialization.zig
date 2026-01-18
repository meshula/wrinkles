//! Binary serialization for OTIO schema types using CBOR format.
//!
//! File format (version 2):
//!   Bytes 0-3:   Magic number "OTLB" (0x4F544C42)
//!   Bytes 4-7:   Format version (u32 big-endian) - now version 2
//!   Bytes 8-15:  Metadata offset (u64 big-endian) - byte offset where metadata_map starts
//!                Set to 0 if no metadata, or file size if metadata at end
//!   Bytes 16+:   CBOR data (with metadata_map as last field if present)
//!
//! The metadata offset allows readers to skip parsing metadata by truncating
//! the CBOR data at that position. This provides significant performance gains
//! for large files with extensive metadata (e.g., AAF imports).
//!
//! Metadata is stored as a map of Wyhash keys to nested CBOR values.
//! Clips reference their metadata by hash key.

const std = @import("std");
const zbor = @import("zbor");
const schema = @import("schema.zig");
const opentime = @import("opentime");
const otio_json = @import("opentimelineio_json.zig");
const sampling = @import("sampling");
const curve = @import("curve");
const domain_mod = @import("domain.zig");
const topology = @import("topology");
const serialization = @import("serialization.zig");

const Allocator = std.mem.Allocator;

pub const ReadOptions = otio_json.ReadOptions;

/// Error type for conversion operations
pub const ConvertError = error{OutOfMemory};

// ----------------------------------------------------------------------------
// File Format Constants
// ----------------------------------------------------------------------------

pub const TLB_MAGIC: [4]u8 = .{ 'O', 'T', 'L', 'B' };
pub const TLB_FORMAT_VERSION: u32 = 2;
pub const TLB_HEADER_SIZE: usize = 16; // Magic(4) + Version(4) + MetadataOffset(8)

// ----------------------------------------------------------------------------
// Binary-specific Types (zbor-compatible, no MetadataMap)
// ----------------------------------------------------------------------------

pub const BinaryRateSpecifier = union(enum) {
    Int: u32,
    Rational: struct { num: u32, den: u32 },
};

pub const BinarySampleIndexGenerator = struct {
    sample_rate_hz: BinaryRateSpecifier,
    start_index: usize = 0,
};

pub const BinaryDiscretePartitionDomainMap = struct {
    picture: ?BinarySampleIndexGenerator = null,
    audio: ?BinarySampleIndexGenerator = null,
};

/// Domain encoded as string for CBOR - avoids empty struct union ambiguity
pub const BinaryDomain = struct {
    kind: []const u8,
    /// Only used for "other" kind
    other_name: ?[]const u8 = null,
};

pub const BinaryMediaDataReference = union(enum) {
    uri: struct { target_uri: []const u8 },
    signal: struct { frequency_hz: f64 },
    image_sequence: struct {
        target_url_base: []const u8,
        name_prefix: []const u8,
        name_suffix: []const u8,
        start_frame: i32,
        frame_step: i32,
        frame_zero_padding: u8,
        rate: f64,
        missing_frame_policy: []const u8,
    },
    null: struct {},
};

/// Bounds can be continuous (f64 seconds) or discrete (i64 sample indices)
pub const BinaryBounds = union(enum) {
    continuous: [2]f64,
    discrete: [2]i64,
};

pub const BinaryMediaReference = struct {
    data_reference: BinaryMediaDataReference,
    bounds_s: ?BinaryBounds = null,
    domain: BinaryDomain,
    discrete_partition: ?BinarySampleIndexGenerator = null,
};

pub const BinaryMarker = struct {
    name: ?[]const u8 = null,
    marked_range: [2]f64,
    color: []const u8,
    comment: ?[]const u8 = null,
};

pub const BinaryClip = struct {
    name: ?[]const u8 = null,
    bounds_s: ?BinaryBounds = null,
    media: BinaryMediaReference,
    /// Wyhash key referencing an entry in the Timeline's metadata_map
    metadata_hash: ?[]const u8 = null,
    markers: []BinaryMarker = &.{},
};

pub const BinaryGap = struct {
    name: ?[]const u8 = null,
    bounds_s: [2]f64,
    markers: []BinaryMarker = &.{},
};

pub const BinaryMapping = union(enum) {
    affine: struct {
        input_bounds_val: [2]f64,
        offset: f64,
        scale: f64,
    },
    linear: struct {
        input_bounds_val: [2]f64,
        knots: [][2]f64,
    },
    empty: struct {},
};

pub const BinaryTopology = struct {
    mappings: []BinaryMapping,
};

pub const BinaryWarp = struct {
    name: ?[]const u8 = null,
    child: *BinaryComposable,
    transform: BinaryTopology,
};

pub const BinaryStack = struct {
    is_stack: bool, // Required unique field - must be present for parsing
    name: ?[]const u8 = null,
    bounds_s: ?BinaryBounds = null,
    children: []BinaryComposable,
    markers: []BinaryMarker = &.{},
};

pub const BinaryTrack = struct {
    is_track: bool, // Required unique field - must be present for parsing
    name: ?[]const u8 = null,
    bounds_s: ?BinaryBounds = null,
    children: []BinaryComposable,
    markers: []BinaryMarker = &.{},
};

pub const BinaryTransition = struct {
    name: ?[]const u8 = null,
    container: BinaryStack,
    kind: []const u8,
    /// Transition bounds_s is always continuous (SerializableContinuousInterval)
    bounds_s: ?[2]f64 = null,
};

pub const BinaryComposable = union(enum) {
    clip: BinaryClip,
    gap: BinaryGap,
    track: BinaryTrack,
    stack: BinaryStack,
    warp: BinaryWarp,
    transition: BinaryTransition,
};

/// Recursive metadata value type for CBOR serialization.
/// Mirrors ziggy.dynamic.Value but uses CBOR-compatible types.
pub const BinaryMetadataValue = union(enum) {
    kv: []BinaryMetadataEntry,
    array: []BinaryMetadataValue,
    bytes: []const u8,
    integer: i64,
    float: f64,
    bool: bool,
    null: struct {}, // Empty struct instead of void for zbor compatibility
};

/// Key-value entry for metadata maps
pub const BinaryMetadataEntry = struct {
    key: []const u8,
    value: BinaryMetadataValue,
};

/// Metadata map - array of key-value entries
pub const BinaryMetadataMap = []BinaryMetadataEntry;

pub const BinaryTimeline = struct {
    schema_version: u32 = 1,
    name: ?[]const u8 = null,
    children: []BinaryComposable,
    presentation_space_discrete_partitions: BinaryDiscretePartitionDomainMap,
    /// Maps metadata hash keys to their metadata dictionaries.
    /// Optional so empty maps can be omitted from serialization.
    metadata_map: ?BinaryMetadataMap = null,
    markers: []BinaryMarker = &.{},
};

/// Variant of BinaryTimeline that skips metadata_map during parsing.
/// Used when ReadOptions.file_contents_to_read == .all_except_metadata.
/// Since this type doesn't have metadata_map field, zbor will skip it
/// when ignore_unknown_fields is true.
pub const BinaryTimelineNoMetadata = struct {
    schema_version: u32 = 1,
    name: ?[]const u8 = null,
    children: []BinaryComposable,
    presentation_space_discrete_partitions: BinaryDiscretePartitionDomainMap,
    // No metadata_map field - zbor will skip it with ignore_unknown_fields
};

/// Free memory allocated by zbor.parse for BinaryTimeline.
/// Call this after converting to schema.Timeline to avoid leaks.
fn deinit_binary_timeline(
    allocator: std.mem.Allocator,
    bin_timeline: BinaryTimeline,
) void
{
    deinit_binary_composable_slice(allocator, bin_timeline.children);
}

/// Free memory allocated by zbor.parse for BinaryTimelineNoMetadata.
fn deinit_binary_timeline_no_metadata(
    allocator: std.mem.Allocator,
    bin_timeline: BinaryTimelineNoMetadata,
) void
{
    deinit_binary_composable_slice(allocator, bin_timeline.children);
}

/// Recursively free a single BinaryComposable item.
fn deinit_binary_composable(
    allocator: std.mem.Allocator,
    child: BinaryComposable,
) void
{
    switch (child) {
        .track => |t| deinit_binary_composable_slice(allocator, t.children),
        .stack => |s| deinit_binary_composable_slice(allocator, s.children),
        .transition => |tr| deinit_binary_composable_slice(allocator, tr.container.children),
        .warp => |w| {
            deinit_binary_composable(allocator, w.child.*);
            allocator.destroy(w.child);
        },
        .clip, .gap => {},
    }
}

/// Recursively free a slice of BinaryComposable items.
fn deinit_binary_composable_slice(
    allocator: std.mem.Allocator,
    children: []BinaryComposable,
) void
{
    for (children) |child| {
        deinit_binary_composable(allocator, child);
    }
    allocator.free(children);
}

// ----------------------------------------------------------------------------
// Header Functions
// ----------------------------------------------------------------------------

pub fn write_header(
    writer: anytype,
    metadata_offset: u64,
) !void {
    try writer.writeAll(&TLB_MAGIC);
    // Version (u32 big-endian)
    try writer.writeByte(@intCast((TLB_FORMAT_VERSION >> 24) & 0xFF));
    try writer.writeByte(@intCast((TLB_FORMAT_VERSION >> 16) & 0xFF));
    try writer.writeByte(@intCast((TLB_FORMAT_VERSION >> 8) & 0xFF));
    try writer.writeByte(@intCast(TLB_FORMAT_VERSION & 0xFF));
    // Metadata offset (u64 big-endian)
    try writer.writeByte(@intCast((metadata_offset >> 56) & 0xFF));
    try writer.writeByte(@intCast((metadata_offset >> 48) & 0xFF));
    try writer.writeByte(@intCast((metadata_offset >> 40) & 0xFF));
    try writer.writeByte(@intCast((metadata_offset >> 32) & 0xFF));
    try writer.writeByte(@intCast((metadata_offset >> 24) & 0xFF));
    try writer.writeByte(@intCast((metadata_offset >> 16) & 0xFF));
    try writer.writeByte(@intCast((metadata_offset >> 8) & 0xFF));
    try writer.writeByte(@intCast(metadata_offset & 0xFF));
}

pub const HeaderInfo = struct {
    version: u32,
    metadata_offset: u64,
};

pub fn read_header(
    data: []const u8,
) !HeaderInfo {
    if (data.len < TLB_HEADER_SIZE) return error.MalformedData;
    if (!std.mem.eql(u8, data[0..4], &TLB_MAGIC)) return error.InvalidMagicNumber;

    const version: u32 = (@as(u32, data[4]) << 24) |
        (@as(u32, data[5]) << 16) |
        (@as(u32, data[6]) << 8) |
        @as(u32, data[7]);

    if (version > TLB_FORMAT_VERSION) return error.UnsupportedFormatVersion;

    // Read metadata offset (u64 big-endian)
    const metadata_offset: u64 = (@as(u64, data[8]) << 56) |
        (@as(u64, data[9]) << 48) |
        (@as(u64, data[10]) << 40) |
        (@as(u64, data[11]) << 32) |
        (@as(u64, data[12]) << 24) |
        (@as(u64, data[13]) << 16) |
        (@as(u64, data[14]) << 8) |
        @as(u64, data[15]);

    return .{ .version = version, .metadata_offset = metadata_offset };
}

// ----------------------------------------------------------------------------
// Conversion: schema.Timeline -> BinaryTimeline
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
    if (maybe_str)
        |str|
    {
        return try copy_string(allocator, str);
    }
    return null;
}

fn rate_to_binary(
    rate: anytype,
) BinaryRateSpecifier
{
    return switch (rate) {
        .Int => |val| .{ .Int = val },
        .Rat => |r| .{ .Rational = .{ .num = r.num, .den = r.den } },
    };
}

fn sig_to_binary(
    sig: anytype,
) BinarySampleIndexGenerator
{
    return .{
        .sample_rate_hz = rate_to_binary(sig.sample_rate_hz),
        .start_index = sig.start_index,
    };
}

fn interval_to_binary(
    interval: opentime.ContinuousInterval,
) BinaryBounds {
    return .{ .continuous = .{ interval.start.as(f64), interval.end.as(f64) } };
}

fn interval_to_binary_raw(
    interval: opentime.ContinuousInterval,
) [2]f64 {
    return .{ interval.start.as(f64), interval.end.as(f64) };
}

fn domain_to_binary(
    allocator: Allocator,
    dom: anytype,
) !BinaryDomain
{
    return switch (dom) {
        .time => .{ .kind = "time" },
        .picture => .{ .kind = "picture" },
        .audio => .{ .kind = "audio" },
        .metadata => .{ .kind = "metadata" },
        .other => |s| .{ .kind = "other", .other_name = try copy_string(allocator, s) },
    };
}

fn media_data_ref_to_binary(
    allocator: Allocator,
    ref: schema.MediaDataReference,
) !BinaryMediaDataReference
{
    return switch (ref) {
        .uri => |uri_ref| .{
            .uri = .{ .target_uri = try copy_string(allocator, uri_ref.target_uri) },
        },
        .signal => |sig_ref| .{
            .signal = .{ .frequency_hz = @floatFromInt(sig_ref.signal_generator.frequency_hz) },
        },
        .image_sequence => |img_seq| .{
            // For now, serialize image_sequence as a URI with the base path
            .uri = .{ .target_uri = try copy_string(allocator, img_seq.target_url_base) },
        },
        .null => .{ .null = .{} },
    };
}

fn media_ref_to_binary(
    allocator: Allocator,
    ref: schema.MediaReference,
) !BinaryMediaReference
{
    return .{
        .data_reference = try media_data_ref_to_binary(allocator, ref.data_reference),
        .bounds_s = if (ref.maybe_bounds_s) |b| interval_to_binary(b) else null,
        .domain = try domain_to_binary(allocator, ref.domain),
        .discrete_partition = if (ref.maybe_discrete_partition) |dp| sig_to_binary(dp) else null,
    };
}

fn clip_to_binary(
    allocator: Allocator,
    clip: schema.Clip,
) !BinaryClip
{
    return .{
        .name = try copy_optional_string(allocator, clip.maybe_name),
        .bounds_s = if (clip.maybe_bounds_s) |b| interval_to_binary(b) else null,
        .media = try media_ref_to_binary(allocator, clip.media),
    };
}

fn gap_to_binary(
    allocator: Allocator,
    gap: schema.Gap,
) !BinaryGap
{
    return .{
        .name = try copy_optional_string(allocator, gap.maybe_name),
        .bounds_s = interval_to_binary_raw(gap.bounds_s),
    };
}

fn composable_to_binary(
    allocator: Allocator,
    handle: schema.references.CompositionItemHandle,
) ConvertError!BinaryComposable
{
    return switch (handle) {
        .clip => |clip_ptr| .{ .clip = try clip_to_binary(allocator, clip_ptr.*) },
        .gap => |gap_ptr| .{ .gap = try gap_to_binary(allocator, gap_ptr.*) },
        .track => |track_ptr| .{ .track = try track_to_binary(allocator, track_ptr.*) },
        .stack => |stack_ptr| .{ .stack = try stack_to_binary(allocator, stack_ptr.*) },
        .warp => |warp_ptr| .{ .warp = try warp_to_binary(allocator, warp_ptr.*) },
        .transition => |trans_ptr| .{ .transition = try transition_to_binary(allocator, trans_ptr.*) },
        .timeline => unreachable,
    };
}

fn track_to_binary(
    allocator: Allocator,
    track: schema.Track,
) ConvertError!BinaryTrack
{
    const children = try allocator.alloc(BinaryComposable, track.children.len);
    for (track.children, 0..)
        |child, i|
    {
        children[i] = try composable_to_binary(allocator, child);
    }
    return .{
        .is_track = true,
        .name = try copy_optional_string(allocator, track.maybe_name),
        .bounds_s = if (track.maybe_bounds_s) |b| interval_to_binary(b) else null,
        .children = children,
    };
}

fn stack_to_binary(
    allocator: Allocator,
    stack: schema.Stack,
) ConvertError!BinaryStack
{
    const children = try allocator.alloc(BinaryComposable, stack.children.len);
    for (stack.children, 0..)
        |child, i|
    {
        children[i] = try composable_to_binary(allocator, child);
    }
    return .{
        .is_stack = true,
        .name = try copy_optional_string(allocator, stack.maybe_name),
        .bounds_s = if (stack.maybe_bounds_s) |b| interval_to_binary(b) else null,
        .children = children,
    };
}

fn mapping_to_binary(
    allocator: Allocator,
    mapping: anytype,
) !BinaryMapping
{
    return switch (mapping) {
        .affine => |aff| .{
            .affine = .{
                .input_bounds_val = interval_to_binary_raw(aff.input_bounds_val),
                .offset = aff.input_to_output_xform.offset.as(f64),
                .scale = aff.input_to_output_xform.scale.as(f64),
            },
        },
        .linear => |lin| blk: {
            const knots = try allocator.alloc([2]f64, lin.input_to_output_curve.knots.len);
            for (lin.input_to_output_curve.knots, 0..)
                |knot, i|
            {
                knots[i] = .{ knot.in.as(f64), knot.out.as(f64) };
            }
            const input_extents = lin.input_to_output_curve.extents_input() orelse
                opentime.ContinuousInterval{ .start = .zero, .end = .zero };
            break :blk .{
                .linear = .{
                    .input_bounds_val = interval_to_binary_raw(input_extents),
                    .knots = knots,
                },
            };
        },
        .empty => .{ .empty = .{} },
    };
}

fn topology_to_binary(
    allocator: Allocator,
    topo: anytype,
) !BinaryTopology
{
    const mappings = try allocator.alloc(BinaryMapping, topo.mappings.len);
    for (topo.mappings, 0..)
        |mapping, i|
    {
        mappings[i] = try mapping_to_binary(allocator, mapping);
    }
    return .{ .mappings = mappings };
}

fn warp_to_binary(
    allocator: Allocator,
    warp: schema.Warp,
) ConvertError!BinaryWarp
{
    const child_ptr = try allocator.create(BinaryComposable);
    child_ptr.* = try composable_to_binary(allocator, warp.child);
    return .{
        .name = try copy_optional_string(allocator, warp.maybe_name),
        .child = child_ptr,
        .transform = try topology_to_binary(allocator, warp.transform),
    };
}

fn transition_to_binary(
    allocator: Allocator,
    trans: schema.Transition,
) ConvertError!BinaryTransition
{
    return .{
        .name = try copy_optional_string(allocator, trans.maybe_name),
        .container = try stack_to_binary(allocator, trans.container),
        .kind = try copy_string(allocator, trans.kind),
        .bounds_s = if (trans.maybe_bounds_s) |b| interval_to_binary_raw(b) else null,
    };
}

pub fn timeline_to_binary(
    allocator: Allocator,
    timeline: *schema.Timeline,
) !BinaryTimeline
{
    const children = try allocator.alloc(BinaryComposable, timeline.tracks.children.len);
    for (timeline.tracks.children, 0..)
        |child, i|
    {
        children[i] = try composable_to_binary(allocator, child);
    }
    return .{
        .schema_version = 1,
        .name = try copy_optional_string(allocator, timeline.maybe_name),
        .children = children,
        .presentation_space_discrete_partitions = .{
            .picture = if (timeline.discrete_space_partitions.presentation.picture) |p|
                sig_to_binary(p)
            else
                null,
            .audio = if (timeline.discrete_space_partitions.presentation.audio) |a|
                sig_to_binary(a)
            else
                null,
        },
    };
}

// ----------------------------------------------------------------------------
// Metadata Conversion: ziggy.dynamic.Value <-> BinaryMetadataValue
// ----------------------------------------------------------------------------

const ziggy = @import("ziggy");
const MetadataValue = ziggy.dynamic.Value;
const MetadataMap = serialization.MetadataMap;

/// Convert ziggy.dynamic.Value to BinaryMetadataValue
fn metadata_value_to_binary(
    allocator: Allocator,
    value: MetadataValue,
) !BinaryMetadataValue {
    return switch (value) {
        .kv => |map| blk: {
            const entries = try allocator.alloc(BinaryMetadataEntry, map.fields.count());
            var i: usize = 0;
            var iter = map.fields.iterator();
            while (iter.next()) |entry| {
                entries[i] = .{
                    .key = try allocator.dupe(u8, entry.key_ptr.*),
                    .value = try metadata_value_to_binary(allocator, entry.value_ptr.*),
                };
                i += 1;
            }
            break :blk .{ .kv = entries };
        },
        .array => |arr| blk: {
            const values = try allocator.alloc(BinaryMetadataValue, arr.len);
            for (arr, 0..) |item, i| {
                values[i] = try metadata_value_to_binary(allocator, item);
            }
            break :blk .{ .array = values };
        },
        .bytes => |b| .{ .bytes = try allocator.dupe(u8, b) },
        .integer => |i| .{ .integer = i },
        .float => |f| .{ .float = f },
        .bool => |b| .{ .bool = b },
        .null => .{ .null = .{} },
        .tag => |t| .{ .bytes = try allocator.dupe(u8, t.bytes) }, // Convert tag to bytes
    };
}

/// Convert MetadataMap to BinaryMetadataMap
fn metadata_map_to_binary(
    allocator: Allocator,
    map: MetadataMap,
) !BinaryMetadataMap {
    const entries = try allocator.alloc(BinaryMetadataEntry, map.fields.count());
    var i: usize = 0;
    var iter = map.fields.iterator();
    while (iter.next()) |entry| {
        entries[i] = .{
            .key = try allocator.dupe(u8, entry.key_ptr.*),
            .value = try metadata_value_to_binary(allocator, entry.value_ptr.*),
        };
        i += 1;
    }
    return entries;
}

/// Convert BinaryMetadataValue to ziggy.dynamic.Value
fn binary_to_metadata_value(
    allocator: Allocator,
    value: BinaryMetadataValue,
) !MetadataValue {
    return switch (value) {
        .kv => |entries| blk: {
            var map: MetadataMap = .{};
            for (entries) |entry| {
                const key = try allocator.dupe(u8, entry.key);
                const val = try binary_to_metadata_value(allocator, entry.value);
                try map.fields.put(allocator, key, val);
            }
            break :blk .{ .kv = map };
        },
        .array => |arr| blk: {
            const values = try allocator.alloc(MetadataValue, arr.len);
            for (arr, 0..) |item, i| {
                values[i] = try binary_to_metadata_value(allocator, item);
            }
            break :blk .{ .array = values };
        },
        .bytes => |b| .{ .bytes = try allocator.dupe(u8, b) },
        .integer => |i| .{ .integer = i },
        .float => |f| .{ .float = f },
        .bool => |b| .{ .bool = b },
        .null => .null,
    };
}

/// Convert BinaryMetadataMap to MetadataMap
fn binary_to_metadata_map(
    allocator: Allocator,
    entries: BinaryMetadataMap,
) !MetadataMap {
    var map: MetadataMap = .{};
    for (entries) |entry| {
        const key = try allocator.dupe(u8, entry.key);
        const val = try binary_to_metadata_value(allocator, entry.value);
        try map.fields.put(allocator, key, val);
    }
    return map;
}

// ----------------------------------------------------------------------------
// Conversion: SerializableTimeline -> BinaryTimeline (preserves metadata)
// ----------------------------------------------------------------------------

const SerializableTimeline = serialization.SerializableTimeline;
const SerializableComposable = serialization.SerializableComposable;
const SerializableClip = serialization.SerializableClip;
const SerializableGap = serialization.SerializableGap;
const SerializableTrack = serialization.SerializableTrack;
const SerializableStack = serialization.SerializableStack;
const SerializableWarp = serialization.SerializableWarp;
const SerializableTransition = serialization.SerializableTransition;
const SerializableMediaReference = serialization.SerializableMediaReference;
const SerializableMediaDataReference = serialization.SerializableMediaDataReference;
const SerializableDomain = serialization.SerializableDomain;
const SerializableBounds = serialization.SerializableBounds;
const SerializableMarker = serialization.SerializableMarker;

fn ser_domain_to_binary(
    allocator: Allocator,
    dom: SerializableDomain,
) !BinaryDomain {
    return switch (dom) {
        .time => .{ .kind = "time" },
        .picture => .{ .kind = "picture" },
        .audio => .{ .kind = "audio" },
        .metadata => .{ .kind = "metadata" },
        .other => |o| .{ .kind = "other", .other_name = try copy_string(allocator, o.name) },
    };
}

fn ser_bounds_to_binary(bounds: SerializableBounds) BinaryBounds {
    return switch (bounds) {
        .continuous => |c| .{ .continuous = c },
        .discrete => |d| .{ .discrete = d },
    };
}

fn ser_media_data_ref_to_binary(
    allocator: Allocator,
    ref: SerializableMediaDataReference,
) !BinaryMediaDataReference {
    return switch (ref) {
        .uri => |uri_ref| .{
            .uri = .{ .target_uri = try copy_string(allocator, uri_ref.target_uri) },
        },
        .signal => |sig_ref| .{
            .signal = .{
                .frequency_hz = switch (sig_ref.signal_generator) {
                    .sine => |s| s.frequency_hz,
                    .linear_ramp => 0.0,
                },
            },
        },
        .image_sequence => |img_seq| .{
            .image_sequence = .{
                .target_url_base = try copy_string(allocator, img_seq.target_url_base),
                .name_prefix = try copy_string(allocator, img_seq.name_prefix),
                .name_suffix = try copy_string(allocator, img_seq.name_suffix),
                .start_frame = img_seq.start_frame,
                .frame_step = img_seq.frame_step,
                .frame_zero_padding = img_seq.frame_zero_padding,
                .rate = img_seq.rate,
                .missing_frame_policy = try copy_string(allocator, img_seq.missing_frame_policy),
            },
        },
        .null => .{ .null = .{} },
    };
}

fn ser_media_ref_to_binary(
    allocator: Allocator,
    ref: SerializableMediaReference,
) !BinaryMediaReference {
    return .{
        .data_reference = try ser_media_data_ref_to_binary(allocator, ref.data_reference),
        .bounds_s = if (ref.bounds_s) |b| ser_bounds_to_binary(b) else null,
        .domain = try ser_domain_to_binary(allocator, ref.domain),
        .discrete_partition = if (ref.discrete_partition) |dp| .{
            .sample_rate_hz = switch (dp.sample_rate_hz) {
                .Int => |i| .{ .Int = i },
                .Rational => |r| .{ .Rational = .{ .num = r.num, .den = r.den } },
            },
            .start_index = dp.start_index,
        } else null,
    };
}

fn ser_marker_to_binary(
    allocator: Allocator,
    marker: SerializableMarker,
) !BinaryMarker {
    return .{
        .name = try copy_optional_string(allocator, marker.name),
        .marked_range = marker.marked_range,
        .color = try copy_string(allocator, marker.color),
        .comment = try copy_optional_string(allocator, marker.comment),
    };
}

fn ser_markers_to_binary(
    allocator: Allocator,
    markers: []SerializableMarker,
) ![]BinaryMarker {
    if (markers.len == 0) {
        return &.{};
    }
    var bin_markers = try allocator.alloc(BinaryMarker, markers.len);
    for (markers, 0..) |marker, i| {
        bin_markers[i] = try ser_marker_to_binary(allocator, marker);
    }
    return bin_markers;
}

fn ser_clip_to_binary(
    allocator: Allocator,
    clip: SerializableClip,
) !BinaryClip {
    return .{
        .name = try copy_optional_string(allocator, clip.name),
        .bounds_s = if (clip.bounds_s) |b| ser_bounds_to_binary(b) else null,
        .media = try ser_media_ref_to_binary(allocator, clip.media),
        .metadata_hash = try copy_optional_string(allocator, clip.metadata_hash),
        .markers = try ser_markers_to_binary(allocator, clip.markers),
    };
}

fn ser_gap_to_binary(
    allocator: Allocator,
    gap: SerializableGap,
) !BinaryGap {
    return .{
        .name = try copy_optional_string(allocator, gap.name),
        .bounds_s = gap.bounds_s,
        .markers = try ser_markers_to_binary(allocator, gap.markers),
    };
}

fn ser_composable_to_binary(
    allocator: Allocator,
    comp: SerializableComposable,
) ConvertError!BinaryComposable {
    return switch (comp) {
        .clip => |clip| .{ .clip = try ser_clip_to_binary(allocator, clip) },
        .gap => |gap| .{ .gap = try ser_gap_to_binary(allocator, gap) },
        .track => |track| .{ .track = try ser_track_to_binary(allocator, track) },
        .stack => |stack| .{ .stack = try ser_stack_to_binary(allocator, stack) },
        .warp => |warp| .{ .warp = try ser_warp_to_binary(allocator, warp) },
        .transition => |trans| .{ .transition = try ser_transition_to_binary(allocator, trans) },
    };
}

fn ser_track_to_binary(
    allocator: Allocator,
    track: SerializableTrack,
) ConvertError!BinaryTrack {
    const children = try allocator.alloc(BinaryComposable, track.children.len);
    for (track.children, 0..) |child, i| {
        children[i] = try ser_composable_to_binary(allocator, child);
    }
    return .{
        .is_track = true,
        .name = try copy_optional_string(allocator, track.name),
        .bounds_s = if (track.bounds_s) |b| ser_bounds_to_binary(b) else null,
        .children = children,
        .markers = try ser_markers_to_binary(allocator, track.markers),
    };
}

fn ser_stack_to_binary(
    allocator: Allocator,
    stack: SerializableStack,
) ConvertError!BinaryStack {
    const children = try allocator.alloc(BinaryComposable, stack.children.len);
    for (stack.children, 0..) |child, i| {
        children[i] = try ser_composable_to_binary(allocator, child);
    }
    return .{
        .is_stack = true,
        .name = try copy_optional_string(allocator, stack.name),
        .bounds_s = if (stack.bounds_s) |b| ser_bounds_to_binary(b) else null,
        .children = children,
        .markers = try ser_markers_to_binary(allocator, stack.markers),
    };
}

fn ser_mapping_to_binary(
    allocator: Allocator,
    mapping: serialization.SerializableMapping,
) !BinaryMapping {
    return switch (mapping) {
        .affine => |aff| .{
            .affine = .{
                .input_bounds_val = aff.input_bounds_val,
                .offset = aff.input_to_output_xform.offset,
                .scale = aff.input_to_output_xform.scale,
            },
        },
        .linear => |lin| blk: {
            const knots = try allocator.alloc([2]f64, lin.knots.len);
            for (lin.knots, 0..) |knot, i| {
                knots[i] = knot;
            }
            break :blk .{
                .linear = .{
                    .input_bounds_val = lin.input_bounds_val,
                    .knots = knots,
                },
            };
        },
        .empty => .{ .empty = .{} },
    };
}

fn ser_topology_to_binary(
    allocator: Allocator,
    topo: serialization.SerializableTopology,
) !BinaryTopology {
    const mappings = try allocator.alloc(BinaryMapping, topo.mappings.len);
    for (topo.mappings, 0..) |mapping, i| {
        mappings[i] = try ser_mapping_to_binary(allocator, mapping);
    }
    return .{ .mappings = mappings };
}

fn ser_warp_to_binary(
    allocator: Allocator,
    warp: SerializableWarp,
) ConvertError!BinaryWarp {
    const child_ptr = try allocator.create(BinaryComposable);
    child_ptr.* = try ser_composable_to_binary(allocator, warp.child.*);
    return .{
        .name = try copy_optional_string(allocator, warp.name),
        .child = child_ptr,
        .transform = try ser_topology_to_binary(allocator, warp.transform),
    };
}

fn ser_transition_to_binary(
    allocator: Allocator,
    trans: SerializableTransition,
) ConvertError!BinaryTransition {
    return .{
        .name = try copy_optional_string(allocator, trans.name),
        .container = try ser_stack_to_binary(allocator, trans.container),
        .kind = try copy_string(allocator, trans.kind),
        // Transition bounds_s is SerializableContinuousInterval ([2]f64), not SerializableBounds
        .bounds_s = trans.bounds_s,
    };
}

/// Convert SerializableTimeline to BinaryTimeline, preserving metadata
pub fn serializable_timeline_to_binary(
    allocator: Allocator,
    ser_timeline: SerializableTimeline,
) !BinaryTimeline {
    const children = try allocator.alloc(BinaryComposable, ser_timeline.children.len);
    for (ser_timeline.children, 0..) |child, i| {
        children[i] = try ser_composable_to_binary(allocator, child);
    }

    // Convert metadata map if present
    const metadata_map: ?BinaryMetadataMap = if (ser_timeline.metadata_map) |mm|
        try metadata_map_to_binary(allocator, mm)
    else
        null;

    return .{
        .schema_version = ser_timeline.schema_version,
        .name = try copy_optional_string(allocator, ser_timeline.name),
        .children = children,
        .presentation_space_discrete_partitions = .{
            .picture = if (ser_timeline.presentation_space_discrete_partitions.picture) |p| .{
                .sample_rate_hz = switch (p.sample_rate_hz) {
                    .Int => |i| .{ .Int = i },
                    .Rational => |r| .{ .Rational = .{ .num = r.num, .den = r.den } },
                },
                .start_index = p.start_index,
            } else null,
            .audio = if (ser_timeline.presentation_space_discrete_partitions.audio) |a| .{
                .sample_rate_hz = switch (a.sample_rate_hz) {
                    .Int => |i| .{ .Int = i },
                    .Rational => |r| .{ .Rational = .{ .num = r.num, .den = r.den } },
                },
                .start_index = a.start_index,
            } else null,
        },
        .metadata_map = metadata_map,
        .markers = try ser_markers_to_binary(allocator, ser_timeline.markers),
    };
}

// ----------------------------------------------------------------------------
// Serialization
// ----------------------------------------------------------------------------

pub fn serialize_timeline_binary(
    timeline: *schema.Timeline,
    allocator: Allocator,
    writer: anytype,
) !void {
    // Convert to binary format (no metadata in this path)
    const bin_timeline = try timeline_to_binary(allocator, timeline);
    defer deinit_binary_timeline(allocator, bin_timeline);

    // Serialize with zbor - use Allocating writer
    var zbor_writer = std.Io.Writer.Allocating.init(allocator);
    defer zbor_writer.deinit();

    try zbor.stringify(bin_timeline, .{ .allocator = allocator }, &zbor_writer.writer);

    // No metadata in this path, so metadata_offset = 0 (or file size)
    const cbor_data = zbor_writer.written();
    try write_header(writer, cbor_data.len);

    // Write CBOR data to output
    try writer.writeAll(cbor_data);
}

/// Serialize a SerializableTimeline to binary format, preserving metadata.
/// This is the preferred method when you need to preserve metadata through
/// the binary format.
pub fn serialize_from_serializable_timeline(
    ser_timeline: SerializableTimeline,
    allocator: Allocator,
    writer: anytype,
) !void {
    // Convert to binary format preserving metadata
    const bin_timeline = try serializable_timeline_to_binary(allocator, ser_timeline);
    defer deinit_binary_timeline(allocator, bin_timeline);

    // Serialize with zbor
    var zbor_writer = std.Io.Writer.Allocating.init(allocator);
    defer zbor_writer.deinit();

    try zbor.stringify(bin_timeline, .{ .allocator = allocator }, &zbor_writer.writer);

    const cbor_data = zbor_writer.written();

    // Find metadata_map offset in CBOR data
    // CBOR text string "metadata_map" is encoded as 0x6c followed by the string
    const metadata_key = "\x6cmetadata_map";
    const metadata_offset: u64 = if (std.mem.indexOf(u8, cbor_data, metadata_key)) |pos|
        pos
    else
        cbor_data.len; // No metadata, point to end of file

    try write_header(writer, metadata_offset);

    // Write CBOR data to output
    try writer.writeAll(cbor_data);
}

/// Deserialize binary data directly to SerializableTimeline, preserving metadata.
/// This is useful when you need to output to ziggy format while preserving metadata.
pub fn deserialize_to_serializable_timeline(
    allocator: Allocator,
    data: []const u8,
) !SerializableTimeline {
    // Validate header (but we don't use metadata_offset here since we want full metadata)
    _ = try read_header(data);

    // Get CBOR data after header
    const cbor_data = data[TLB_HEADER_SIZE..];

    // Parse CBOR into DataItem
    const data_item = try zbor.DataItem.new(cbor_data);

    // Parse into BinaryTimeline
    const bin_timeline = try zbor.parse(BinaryTimeline, data_item, .{
        .allocator = allocator,
        .ignore_unknown_fields = true,
        .duplicate_field_behavior = .UseFirst,
    });

    // Convert to SerializableTimeline preserving metadata
    return try binary_to_serializable_timeline(allocator, bin_timeline);
}

// ----------------------------------------------------------------------------
// Conversion: BinaryTimeline -> schema.Timeline
// ----------------------------------------------------------------------------

fn binary_to_rate(
    rate: BinaryRateSpecifier,
) sampling.RateSpecifier
{
    return switch (rate) {
        .Int => |val| .{ .Int = val },
        .Rational => |r| .{ .Rat = .{ .num = r.num, .den = r.den } },
    };
}

fn binary_to_sig(
    sig: BinarySampleIndexGenerator,
) sampling.SampleIndexGenerator
{
    return .{
        .sample_rate_hz = binary_to_rate(sig.sample_rate_hz),
        .start_index = sig.start_index,
    };
}

fn binary_to_interval(
    bounds: BinaryBounds,
    maybe_discrete_partition: ?sampling.SampleIndexGenerator,
) opentime.ContinuousInterval {
    return switch (bounds) {
        .continuous => |c| .{
            .start = opentime.Ordinate.init(c[0]),
            .end = opentime.Ordinate.init(c[1]),
        },
        .discrete => |d| blk: {
            // Discrete bounds require a discrete partition to convert to continuous
            if (maybe_discrete_partition) |sig| {
                // Convert discrete indices to continuous ordinates using the sample rate
                break :blk .{
                    .start = sig.ordinate_at_index(@intCast(d[0])),
                    .end = sig.ordinate_at_index(@intCast(d[1])),
                };
            } else {
                // Fallback: treat as raw values (this shouldn't happen with well-formed data)
                break :blk .{
                    .start = opentime.Ordinate.init(@as(f64, @floatFromInt(d[0]))),
                    .end = opentime.Ordinate.init(@as(f64, @floatFromInt(d[1]))),
                };
            }
        },
    };
}

fn binary_to_interval_raw(
    bounds: [2]f64,
) opentime.ContinuousInterval {
    return .{
        .start = opentime.Ordinate.init(bounds[0]),
        .end = opentime.Ordinate.init(bounds[1]),
    };
}

fn binary_to_domain(
    allocator: Allocator,
    dom: BinaryDomain,
) !domain_mod.Domain
{
    if (std.mem.eql(u8, dom.kind, "time")) return .time;
    if (std.mem.eql(u8, dom.kind, "picture")) return .picture;
    if (std.mem.eql(u8, dom.kind, "audio")) return .audio;
    if (std.mem.eql(u8, dom.kind, "metadata")) return .metadata;
    if (std.mem.eql(u8, dom.kind, "other")) {
        return .{ .other = try allocator.dupe(u8, dom.other_name orelse "") };
    }
    return .time; // Default fallback
}

fn binary_to_media_data_ref(
    allocator: Allocator,
    ref: BinaryMediaDataReference,
) !schema.MediaDataReference
{
    return switch (ref) {
        .uri => |uri_ref| .{
            .uri = .{ .target_uri = try allocator.dupe(u8, uri_ref.target_uri) },
        },
        .signal => |sig_ref| .{
            .signal = .{
                .signal_generator = .{
                    .frequency_hz = @intFromFloat(sig_ref.frequency_hz),
                    .duration_s = sampling.sample_ordinate_t.init(1.0), // Default duration
                    .signal = .sine, // Default signal type
                },
            },
        },
        .image_sequence => |img_seq| .{
            .image_sequence = .{
                .target_url_base = try allocator.dupe(u8, img_seq.target_url_base),
                .name_prefix = try allocator.dupe(u8, img_seq.name_prefix),
                .name_suffix = try allocator.dupe(u8, img_seq.name_suffix),
                .start_frame = img_seq.start_frame,
                .frame_step = img_seq.frame_step,
                .frame_zero_padding = img_seq.frame_zero_padding,
                .rate = img_seq.rate,
                .missing_frame_policy = (
                    schema.MissingFramePolicy.from_maybe_string(
                        img_seq.missing_frame_policy
                    )
                ),
            },
        },
        .null => .{ .null = {} },
    };
}

fn binary_to_media_ref(
    allocator: Allocator,
    ref: BinaryMediaReference,
) !schema.MediaReference
{
    const maybe_discrete_partition = if (ref.discrete_partition) |dp| binary_to_sig(dp) else null;
    return .{
        .data_reference = try binary_to_media_data_ref(allocator, ref.data_reference),
        .maybe_bounds_s = if (ref.bounds_s) |b| binary_to_interval(b, maybe_discrete_partition) else null,
        .domain = try binary_to_domain(allocator, ref.domain),
        .maybe_discrete_partition = maybe_discrete_partition,
    };
}

fn binary_to_clip(
    allocator: Allocator,
    clip: BinaryClip,
) !*schema.Clip
{
    const clip_ptr = try allocator.create(schema.Clip);
    // Convert media first to get the discrete partition
    const media = try binary_to_media_ref(allocator, clip.media);
    clip_ptr.* = .{
        .maybe_name = if (clip.name) |n| try allocator.dupe(u8, n) else null,
        .maybe_bounds_s = if (clip.bounds_s) |b| binary_to_interval(b, media.maybe_discrete_partition) else null,
        .media = media,
    };
    return clip_ptr;
}

fn binary_to_gap(
    allocator: Allocator,
    gap: BinaryGap,
) !*schema.Gap
{
    const gap_ptr = try allocator.create(schema.Gap);
    gap_ptr.* = .{
        .maybe_name = if (gap.name) |n| try allocator.dupe(u8, n) else null,
        .bounds_s = binary_to_interval_raw(gap.bounds_s),
    };
    return gap_ptr;
}

fn binary_to_composable(
    allocator: Allocator,
    comp: BinaryComposable,
) ConvertError!schema.references.CompositionItemHandle
{
    return switch (comp) {
        .clip => |clip| .{ .clip = try binary_to_clip(allocator, clip) },
        .gap => |gap| .{ .gap = try binary_to_gap(allocator, gap) },
        .track => |track| .{ .track = try binary_to_track(allocator, track) },
        .stack => |stack| .{ .stack = try binary_to_stack(allocator, stack) },
        .warp => |warp| .{ .warp = try binary_to_warp(allocator, warp) },
        .transition => |trans| .{ .transition = try binary_to_transition(allocator, trans) },
    };
}

fn binary_to_track(
    allocator: Allocator,
    track: BinaryTrack,
) ConvertError!*schema.Track
{
    const track_ptr = try allocator.create(schema.Track);
    const children = try allocator.alloc(
        schema.references.CompositionItemHandle,
        track.children.len,
    );
    for (track.children, 0..) |child, i| {
        children[i] = try binary_to_composable(allocator, child);
    }
    track_ptr.* = .{
        .maybe_name = if (track.name) |n| try allocator.dupe(u8, n) else null,
        // Tracks don't have discrete partitions, so pass null
        .maybe_bounds_s = if (track.bounds_s) |b| binary_to_interval(b, null) else null,
        .children = children,
    };
    return track_ptr;
}

fn binary_to_stack(
    allocator: Allocator,
    stack: BinaryStack,
) ConvertError!*schema.Stack
{
    const stack_ptr = try allocator.create(schema.Stack);
    const children = try allocator.alloc(
        schema.references.CompositionItemHandle,
        stack.children.len,
    );
    for (stack.children, 0..) |child, i| {
        children[i] = try binary_to_composable(allocator, child);
    }
    stack_ptr.* = .{
        .maybe_name = if (stack.name) |n| try allocator.dupe(u8, n) else null,
        // Stacks don't have discrete partitions, so pass null
        .maybe_bounds_s = if (stack.bounds_s) |b| binary_to_interval(b, null) else null,
        .children = children,
    };
    return stack_ptr;
}

fn binary_to_mapping(
    allocator: Allocator,
    mapping: BinaryMapping,
) !topology.Mapping
{
    return switch (mapping) {
        .affine => |aff| .{
            .affine = .{
                .input_bounds_val = binary_to_interval_raw(aff.input_bounds_val),
                .input_to_output_xform = .{
                    .offset = opentime.Ordinate.init(aff.offset),
                    .scale = opentime.Ordinate.init(aff.scale),
                },
            },
        },
        .linear => |lin| blk: {
            const knots = try allocator.alloc(curve.ControlPoint, lin.knots.len);
            for (lin.knots, 0..) |knot, i| {
                knots[i] = .{
                    .in = opentime.Ordinate.init(knot[0]),
                    .out = opentime.Ordinate.init(knot[1]),
                };
            }
            break :blk .{
                .linear = .{
                    .input_to_output_curve = .{ .knots = knots },
                },
            };
        },
        .empty => .{ .empty = .{ .defined_range = .inf_neg_to_pos } },
    };
}

fn binary_to_topology(
    allocator: Allocator,
    topo: BinaryTopology,
) !topology.Topology
{
    const mappings = try allocator.alloc(topology.Mapping, topo.mappings.len);
    for (topo.mappings, 0..) |mapping, i| {
        mappings[i] = try binary_to_mapping(allocator, mapping);
    }
    return .{ .mappings = mappings };
}

fn binary_to_warp(
    allocator: Allocator,
    warp: BinaryWarp,
) ConvertError!*schema.Warp
{
    const warp_ptr = try allocator.create(schema.Warp);
    warp_ptr.* = .{
        .maybe_name = if (warp.name) |n| try allocator.dupe(u8, n) else null,
        .child = try binary_to_composable(allocator, warp.child.*),
        .transform = try binary_to_topology(allocator, warp.transform),
    };
    return warp_ptr;
}

fn binary_to_transition(
    allocator: Allocator,
    trans: BinaryTransition,
) ConvertError!*schema.Transition
{
    const trans_ptr = try allocator.create(schema.Transition);
    const container_ptr = try binary_to_stack(allocator, trans.container);
    trans_ptr.* = .{
        .maybe_name = if (trans.name) |n| try allocator.dupe(u8, n) else null,
        .container = container_ptr.*,
        .kind = try allocator.dupe(u8, trans.kind),
        .maybe_bounds_s = if (trans.bounds_s) |b| binary_to_interval_raw(b) else null,
    };
    allocator.destroy(container_ptr);
    return trans_ptr;
}

pub fn binary_to_timeline(
    allocator: Allocator,
    bin_timeline: BinaryTimeline,
) !*schema.Timeline
{
    const timeline_ptr = try allocator.create(schema.Timeline);

    // Create stack for tracks
    const tracks_stack = try allocator.create(schema.Stack);
    const children = try allocator.alloc(
        schema.references.CompositionItemHandle,
        bin_timeline.children.len,
    );
    for (bin_timeline.children, 0..) |child, i| {
        children[i] = try binary_to_composable(allocator, child);
    }
    tracks_stack.* = .{
        .maybe_name = null,
        .children = children,
    };

    timeline_ptr.* = .{
        .maybe_name = if (bin_timeline.name) |n| try allocator.dupe(u8, n) else null,
        .tracks = tracks_stack.*,
        .discrete_space_partitions = .{
            .presentation = .{
                .picture = if (bin_timeline.presentation_space_discrete_partitions.picture) |p|
                    binary_to_sig(p)
                else
                    null,
                .audio = if (bin_timeline.presentation_space_discrete_partitions.audio) |a|
                    binary_to_sig(a)
                else
                    null,
            },
        },
    };
    allocator.destroy(tracks_stack);

    return timeline_ptr;
}

/// Convert BinaryTimelineNoMetadata to schema.Timeline (no metadata)
pub fn binary_to_timeline_no_metadata(
    allocator: Allocator,
    bin_timeline: BinaryTimelineNoMetadata,
) !*schema.Timeline {
    const timeline_ptr = try allocator.create(schema.Timeline);

    // Create stack for tracks
    const tracks_stack = try allocator.create(schema.Stack);
    const children = try allocator.alloc(
        schema.references.CompositionItemHandle,
        bin_timeline.children.len,
    );
    for (bin_timeline.children, 0..) |child, i| {
        children[i] = try binary_to_composable(allocator, child);
    }
    tracks_stack.* = .{
        .maybe_name = null,
        .children = children,
    };

    timeline_ptr.* = .{
        .maybe_name = if (bin_timeline.name) |n| try allocator.dupe(u8, n) else null,
        .tracks = tracks_stack.*,
        .discrete_space_partitions = .{
            .presentation = .{
                .picture = if (bin_timeline.presentation_space_discrete_partitions.picture) |p|
                    binary_to_sig(p)
                else
                    null,
                .audio = if (bin_timeline.presentation_space_discrete_partitions.audio) |a|
                    binary_to_sig(a)
                else
                    null,
            },
        },
    };
    allocator.destroy(tracks_stack);

    return timeline_ptr;
}

// ----------------------------------------------------------------------------
// Conversion: BinaryTimeline -> SerializableTimeline (preserves metadata)
// ----------------------------------------------------------------------------

fn binary_to_ser_rate(rate: BinaryRateSpecifier) serialization.SerializableRateSpecifier {
    return switch (rate) {
        .Int => |i| .{ .Int = i },
        .Rational => |r| .{ .Rational = .{ .num = r.num, .den = r.den } },
    };
}

fn binary_to_ser_sig(sig: BinarySampleIndexGenerator) serialization.SerializableSampleIndexGenerator {
    return .{
        .sample_rate_hz = binary_to_ser_rate(sig.sample_rate_hz),
        .start_index = sig.start_index,
    };
}

fn binary_to_ser_domain(
    allocator: Allocator,
    dom: BinaryDomain,
) !SerializableDomain {
    if (std.mem.eql(u8, dom.kind, "time")) return .{ .time = .{} };
    if (std.mem.eql(u8, dom.kind, "picture")) return .{ .picture = .{} };
    if (std.mem.eql(u8, dom.kind, "audio")) return .{ .audio = .{} };
    if (std.mem.eql(u8, dom.kind, "metadata")) return .{ .metadata = .{} };
    if (std.mem.eql(u8, dom.kind, "other")) {
        return .{ .other = .{ .name = try allocator.dupe(u8, dom.other_name orelse "") } };
    }
    return .{ .time = .{} }; // Default fallback
}

fn binary_to_ser_media_data_ref(
    allocator: Allocator,
    ref: BinaryMediaDataReference,
) !SerializableMediaDataReference {
    return switch (ref) {
        .uri => |uri_ref| .{
            .uri = .{ .target_uri = try allocator.dupe(u8, uri_ref.target_uri) },
        },
        .signal => |sig_ref| .{
            .signal = .{
                .signal_generator = .{ .sine = .{ .frequency_hz = sig_ref.frequency_hz } },
            },
        },
        .image_sequence => |img_seq| .{
            .image_sequence = .{
                .target_url_base = try allocator.dupe(u8, img_seq.target_url_base),
                .name_prefix = try allocator.dupe(u8, img_seq.name_prefix),
                .name_suffix = try allocator.dupe(u8, img_seq.name_suffix),
                .start_frame = img_seq.start_frame,
                .frame_step = img_seq.frame_step,
                .frame_zero_padding = img_seq.frame_zero_padding,
                .rate = img_seq.rate,
                .missing_frame_policy = try allocator.dupe(u8, img_seq.missing_frame_policy),
            },
        },
        .null => .{ .null = .{} },
    };
}

fn binary_to_ser_bounds(bounds: BinaryBounds) SerializableBounds {
    return switch (bounds) {
        .continuous => |c| .{ .continuous = c },
        .discrete => |d| .{ .discrete = d },
    };
}

fn binary_to_ser_media_ref(
    allocator: Allocator,
    ref: BinaryMediaReference,
) !SerializableMediaReference {
    return .{
        .data_reference = try binary_to_ser_media_data_ref(allocator, ref.data_reference),
        .bounds_s = if (ref.bounds_s) |b| binary_to_ser_bounds(b) else null,
        .domain = try binary_to_ser_domain(allocator, ref.domain),
        .discrete_partition = if (ref.discrete_partition) |dp| binary_to_ser_sig(dp) else null,
    };
}

fn binary_to_ser_marker(
    allocator: Allocator,
    marker: BinaryMarker,
) !SerializableMarker {
    return .{
        .name = if (marker.name) |n| try allocator.dupe(u8, n) else null,
        .marked_range = marker.marked_range,
        .color = try allocator.dupe(u8, marker.color),
        .comment = if (marker.comment) |c| try allocator.dupe(u8, c) else null,
    };
}

fn binary_to_ser_markers(
    allocator: Allocator,
    markers: []BinaryMarker,
) ![]SerializableMarker {
    if (markers.len == 0) {
        return &.{};
    }
    var ser_markers = try allocator.alloc(SerializableMarker, markers.len);
    for (markers, 0..) |marker, i| {
        ser_markers[i] = try binary_to_ser_marker(allocator, marker);
    }
    return ser_markers;
}

fn binary_to_ser_clip(
    allocator: Allocator,
    clip: BinaryClip,
) !SerializableClip {
    return .{
        .name = if (clip.name) |n| try allocator.dupe(u8, n) else null,
        .bounds_s = if (clip.bounds_s) |b| binary_to_ser_bounds(b) else null,
        .media = try binary_to_ser_media_ref(allocator, clip.media),
        .metadata_hash = if (clip.metadata_hash) |h| try allocator.dupe(u8, h) else null,
        .markers = try binary_to_ser_markers(allocator, clip.markers),
    };
}

fn binary_to_ser_gap(
    allocator: Allocator,
    gap: BinaryGap,
) !SerializableGap {
    return .{
        .name = if (gap.name) |n| try allocator.dupe(u8, n) else null,
        .bounds_s = gap.bounds_s,
        .markers = try binary_to_ser_markers(allocator, gap.markers),
    };
}

fn binary_to_ser_composable(
    allocator: Allocator,
    comp: BinaryComposable,
) ConvertError!SerializableComposable {
    return switch (comp) {
        .clip => |clip| .{ .clip = try binary_to_ser_clip(allocator, clip) },
        .gap => |gap| .{ .gap = try binary_to_ser_gap(allocator, gap) },
        .track => |track| .{ .track = try binary_to_ser_track(allocator, track) },
        .stack => |stack| .{ .stack = try binary_to_ser_stack(allocator, stack) },
        .warp => |warp| .{ .warp = try binary_to_ser_warp(allocator, warp) },
        .transition => |trans| .{ .transition = try binary_to_ser_transition(allocator, trans) },
    };
}

fn binary_to_ser_track(
    allocator: Allocator,
    track: BinaryTrack,
) ConvertError!SerializableTrack {
    const children = try allocator.alloc(SerializableComposable, track.children.len);
    for (track.children, 0..) |child, i| {
        children[i] = try binary_to_ser_composable(allocator, child);
    }
    return .{
        .name = if (track.name) |n| try allocator.dupe(u8, n) else null,
        .bounds_s = if (track.bounds_s) |b| binary_to_ser_bounds(b) else null,
        .children = children,
        .markers = try binary_to_ser_markers(allocator, track.markers),
    };
}

fn binary_to_ser_stack(
    allocator: Allocator,
    stack: BinaryStack,
) ConvertError!SerializableStack {
    const children = try allocator.alloc(SerializableComposable, stack.children.len);
    for (stack.children, 0..) |child, i| {
        children[i] = try binary_to_ser_composable(allocator, child);
    }
    return .{
        .name = if (stack.name) |n| try allocator.dupe(u8, n) else null,
        .bounds_s = if (stack.bounds_s) |b| binary_to_ser_bounds(b) else null,
        .children = children,
        .markers = try binary_to_ser_markers(allocator, stack.markers),
    };
}

fn binary_to_ser_mapping(
    allocator: Allocator,
    mapping: BinaryMapping,
) !serialization.SerializableMapping {
    return switch (mapping) {
        .affine => |aff| .{
            .affine = .{
                .input_bounds_val = aff.input_bounds_val,
                .input_to_output_xform = .{
                    .offset = aff.offset,
                    .scale = aff.scale,
                },
            },
        },
        .linear => |lin| blk: {
            const knots = try allocator.alloc(serialization.SerializableControlPoint, lin.knots.len);
            for (lin.knots, 0..) |knot, i| {
                knots[i] = knot;
            }
            break :blk .{
                .linear = .{
                    .input_bounds_val = lin.input_bounds_val,
                    .knots = knots,
                },
            };
        },
        .empty => .{ .empty = .{} },
    };
}

fn binary_to_ser_topology(
    allocator: Allocator,
    topo: BinaryTopology,
) !serialization.SerializableTopology {
    const mappings = try allocator.alloc(serialization.SerializableMapping, topo.mappings.len);
    for (topo.mappings, 0..) |mapping, i| {
        mappings[i] = try binary_to_ser_mapping(allocator, mapping);
    }
    return .{ .mappings = mappings };
}

fn binary_to_ser_warp(
    allocator: Allocator,
    warp: BinaryWarp,
) ConvertError!SerializableWarp {
    const child_ptr = try allocator.create(SerializableComposable);
    child_ptr.* = try binary_to_ser_composable(allocator, warp.child.*);
    return .{
        .name = if (warp.name) |n| try allocator.dupe(u8, n) else null,
        .child = child_ptr,
        .transform = try binary_to_ser_topology(allocator, warp.transform),
    };
}

fn binary_to_ser_transition(
    allocator: Allocator,
    trans: BinaryTransition,
) ConvertError!SerializableTransition {
    return .{
        .name = if (trans.name) |n| try allocator.dupe(u8, n) else null,
        .container = try binary_to_ser_stack(allocator, trans.container),
        .kind = try allocator.dupe(u8, trans.kind),
        // Transition bounds_s is SerializableContinuousInterval ([2]f64), not SerializableBounds
        .bounds_s = trans.bounds_s,
    };
}

/// Convert BinaryTimeline to SerializableTimeline, preserving metadata
pub fn binary_to_serializable_timeline(
    allocator: Allocator,
    bin_timeline: BinaryTimeline,
) !SerializableTimeline {
    const children = try allocator.alloc(SerializableComposable, bin_timeline.children.len);
    for (bin_timeline.children, 0..) |child, i| {
        children[i] = try binary_to_ser_composable(allocator, child);
    }

    // Convert metadata map if present
    const metadata_map: ?MetadataMap = if (bin_timeline.metadata_map) |mm|
        try binary_to_metadata_map(allocator, mm)
    else
        null;

    return .{
        .schema_version = bin_timeline.schema_version,
        .name = if (bin_timeline.name) |n| try allocator.dupe(u8, n) else null,
        .children = children,
        .presentation_space_discrete_partitions = .{
            .picture = if (bin_timeline.presentation_space_discrete_partitions.picture) |p|
                binary_to_ser_sig(p)
            else
                null,
            .audio = if (bin_timeline.presentation_space_discrete_partitions.audio) |a|
                binary_to_ser_sig(a)
            else
                null,
        },
        .metadata_map = metadata_map,
        .markers = try binary_to_ser_markers(allocator, bin_timeline.markers),
    };
}

// ----------------------------------------------------------------------------
// Deserialization
// ----------------------------------------------------------------------------

pub fn deserialize_timeline_binary(
    allocator: Allocator,
    data: []const u8,
    options: ReadOptions,
) !*schema.Timeline {
    const header = try read_header(data);

    // Get CBOR data after header
    const cbor_data = data[TLB_HEADER_SIZE..];

    // Use different types based on whether we want metadata
    if (options.file_contents_to_read == .all_except_metadata) {
        // Use metadata offset to truncate CBOR data, skipping expensive metadata parsing
        const has_metadata = header.metadata_offset > 0 and header.metadata_offset < cbor_data.len;
        const effective_len = if (has_metadata)
            header.metadata_offset
        else
            cbor_data.len;

        const truncated_cbor = cbor_data[0..effective_len];
        return try deserialize_timeline_skip_metadata(allocator, truncated_cbor, has_metadata);
    } else {
        // Parse CBOR into DataItem
        const data_item = try zbor.DataItem.new(cbor_data);

        // Parse with full metadata
        const bin_timeline = try zbor.parse(BinaryTimeline, data_item, .{
            .allocator = allocator,
            .ignore_unknown_fields = true,
            .duplicate_field_behavior = .UseFirst,
        });
        defer deinit_binary_timeline(allocator, bin_timeline);

        // Convert to schema.Timeline
        return try binary_to_timeline(allocator, bin_timeline);
    }
}

/// Deserialize timeline from truncated CBOR data (metadata already stripped).
/// Uses BinaryTimelineNoMetadata to skip any remaining metadata references.
/// The truncation may leave an incomplete CBOR map, so we patch the header.
/// @param has_metadata: if true, the original data had metadata that was truncated,
///                      so we need to decrement the map count in the header.
fn deserialize_timeline_skip_metadata(
    allocator: Allocator,
    cbor_data: []const u8,
    has_metadata: bool,
) !*schema.Timeline {
    if (cbor_data.len == 0) return error.MalformedData;

    // The top-level CBOR structure is a map. If we truncated before metadata_map,
    // the map header still says it has N entries but we've cut off the last one.
    // We need to patch the map count to be N-1.
    // However, if there was no metadata to truncate, the count is already correct.
    //
    // CBOR map header format:
    //   0xa0-0xb7: map with 0-23 entries (count in lower 5 bits)
    //   0xb8: map with 1-byte count following
    //   0xb9: map with 2-byte count following
    //   0xba: map with 4-byte count following
    //   0xbb: map with 8-byte count following

    var patched = try allocator.dupe(u8, cbor_data);
    errdefer allocator.free(patched);

    const header_byte = patched[0];
    const major_type = header_byte >> 5;
    if (major_type != 5) return error.MalformedData; // Not a map

    // Only patch the map count if we truncated metadata
    if (has_metadata) {
        const additional = header_byte & 0x1f;

        if (additional <= 23) {
            // Small map - decrement count in lower 5 bits
            if (additional > 0) {
                patched[0] = (5 << 5) | (additional - 1);
            }
        } else if (additional == 24 and patched.len >= 2) {
            // 1-byte count
            if (patched[1] > 0) {
                patched[1] -= 1;
            }
        }
        // For larger counts (2+ bytes), the original count is likely already
        // correct because metadata_map would have been the last field
    }

    // Create DataItem from patched CBOR data
    const data_item = try zbor.DataItem.new(patched);

    // Parse without metadata
    const bin_timeline = try zbor.parse(BinaryTimelineNoMetadata, data_item, .{
        .allocator = allocator,
        .ignore_unknown_fields = true,
        .duplicate_field_behavior = .UseFirst,
    });
    defer deinit_binary_timeline_no_metadata(allocator, bin_timeline);

    allocator.free(patched);

    return try binary_to_timeline_no_metadata(allocator, bin_timeline);
}

/// Find the "metadata_map" key in CBOR data and return truncated slice ending before it.
/// Returns null if metadata_map not found (file has no metadata).
fn findAndTruncateAtMetadataMap(data: []const u8) ?[]const u8 {
    // Search for the CBOR text string "metadata_map" (0x6c followed by "metadata_map")
    // CBOR text string of length 12: 0x6c (major type 3, additional info 12)
    const metadata_key = "\x6cmetadata_map";

    // Find the key in the data
    const key_pos = std.mem.indexOf(u8, data, metadata_key) orelse return null;

    // We need to patch the map header to reduce its count by 1
    // First, find the map header (should be at the beginning)
    if (data.len < 1) return null;

    // Get map count from header
    const header_byte = data[0];
    const major_type = header_byte >> 5;
    if (major_type != 5) return null; // Not a map

    // For small maps (0-23 items), the count is in lower 5 bits
    // For larger maps, we'd need more complex handling
    const additional = header_byte & 0x1f;

    if (additional <= 23) {
        // Small map - we can create modified data with count-1
        // But this requires copying, which defeats the purpose
        // For now, just truncate and let zbor handle incomplete map gracefully
        _ = key_pos;
        return null; // Fall back to full parse
    }

    // For larger files, the optimization is more complex
    // Fall back to regular parsing
    return null;
}

// ----------------------------------------------------------------------------
// Tests
// ----------------------------------------------------------------------------

test "header: write and read round-trip" {
    var buffer: [TLB_HEADER_SIZE]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);
    const test_offset: u64 = 12345;
    try write_header(stream.writer(), test_offset);
    const header = try read_header(&buffer);
    try std.testing.expectEqual(TLB_FORMAT_VERSION, header.version);
    try std.testing.expectEqual(test_offset, header.metadata_offset);
}

test "header: invalid magic number" {
    // Pad to 16 bytes for v2 header
    const bad_data = [_]u8{ 'B', 'A', 'D', '!', 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0 };
    try std.testing.expectError(error.InvalidMagicNumber, read_header(&bad_data));
}

test "binary serialization: simple timeline round-trip"
{
    const allocator = std.testing.allocator;

    // Create a minimal timeline
    const gap_child = schema.Gap{
        .maybe_name = null,
        .bounds_s = .{ .start = opentime.Ordinate.init(0.0), .end = opentime.Ordinate.init(1.0) },
    };
    const gap_ptr = try allocator.create(schema.Gap);
    gap_ptr.* = gap_child;

    const children = try allocator.alloc(schema.references.CompositionItemHandle, 1);
    children[0] = .{ .gap = gap_ptr };

    const tracks_stack = try allocator.create(schema.Stack);
    tracks_stack.* = .{ .maybe_name = null, .children = children };

    var timeline = schema.Timeline{
        .maybe_name = null,
        .tracks = tracks_stack.*,
        .discrete_space_partitions = .{
            .presentation = .{ .picture = null, .audio = null },
        },
    };
    defer {
        allocator.free(children);
        allocator.destroy(gap_ptr);
        allocator.destroy(tracks_stack);
    }

    // Serialize to binary
    var output = std.ArrayListUnmanaged(u8){};
    defer output.deinit(allocator);

    try serialize_timeline_binary(&timeline, allocator, output.writer(allocator));

    // Check header
    try std.testing.expect(output.items.len > TLB_HEADER_SIZE);
    try std.testing.expectEqualSlices(u8, &TLB_MAGIC, output.items[0..4]);

    // Deserialize back
    const loaded = try deserialize_timeline_binary(
        allocator,
        output.items,
        .{},
    );
    defer allocator.destroy(loaded);
    defer loaded.deinit(allocator);

    // Verify structure
    try std.testing.expectEqual(@as(usize, 1), loaded.tracks.children.len);
}
