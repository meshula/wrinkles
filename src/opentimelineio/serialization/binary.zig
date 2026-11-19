//! Binary serialization for OTIO schema types using FlatBuffers format.
//!
//! File format (version 1):
//!   Bytes 0-3:   Magic number "OTFB" (0x4F544642)
//!   Bytes 4-7:   Format version (u32 big-endian) - version 1
//!   Bytes 8-15:  Metadata offset (u64 big-endian) - byte offset where metadata starts
//!                Set to 0 if no metadata, or file size if metadata at end
//!   Bytes 16+:   FlatBuffers data
//!
//! The metadata offset allows readers to skip parsing metadata by truncating
//! the data at that position. This provides significant performance gains
//! for large files with extensive metadata (e.g., AAF imports).
//!
//! Codec interface (see adapter.zig):
//!   `TimelineCodec.read` / `.write`   - .tlb
//!   `CollectionCodec.read` / `.write` - .tlcb

const std = @import("std");
const build_options = @import("build_options");

const flatbuffers = @import("flatbuffers");

const tlb = @import("tlb_schema").tlb;

// local
const ascii = @import("ascii.zig");
const serializable = @import("serializable.zig");
const format_m = @import("format.zig");

/// Metadata types from serialization module
const MetadataValue = serializable.MetadataValue;
const MetadataMap = serializable.MetadataMap;

const Allocator = std.mem.Allocator;

/// Conditionally print test output based on build option
fn test_print(comptime fmt: []const u8, args: anytype) void
{
    if (build_options.test_output) {
        std.debug.print(fmt, args);
    }
}

/// Lap timer for optional performance timing (returns elapsed ms since last call).
fn lap(last_ts: *u64) f64
{
    const now = std.c.mach_absolute_time();
    const elapsed = now - last_ts.*;
    last_ts.* = now;
    return @as(f64, @floatFromInt(elapsed)) / 1_000_000.0;
}

// ----------------------------------------------------------------------------
// File Format Constants
// ----------------------------------------------------------------------------

pub const TLB_MAGIC: [4]u8 = .{ 'O', 'T', 'F', 'B' };
pub const TLB_FORMAT_VERSION: u32 = 1;
pub const TLB_HEADER_SIZE: usize = 16; // Magic(4) + Version(4) + MetadataOffset(8)

// ----------------------------------------------------------------------------
// Header Functions
// ----------------------------------------------------------------------------

fn write_header(
    writer: anytype,
    metadata_offset: u64,
) !void
{
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

fn read_header(
    data: []const u8,
) !HeaderInfo
{
    if (data.len < TLB_HEADER_SIZE) return error.InvalidData;
    if (!std.mem.eql(u8, data[0..4], &TLB_MAGIC)) return error.InvalidData;

    const version: u32 = (@as(u32, data[4]) << 24) |
        (@as(u32, data[5]) << 16) |
        (@as(u32, data[6]) << 8) |
        @as(u32, data[7]);

    if (version > TLB_FORMAT_VERSION) return error.UnsupportedVersion;

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
// Metadata Conversion: MetadataMap -> FlatBuffers (High-Performance Columnar Format)
// ----------------------------------------------------------------------------
//
// The columnar format stores metadata in parallel arrays:
// - keys: [string] - all keys in one vector
// - types: [byte] - type of each value
// - scalars: [PackedScalar] - packed bool/int/float values (inline, no vtable!)
// - string_values/indices: strings stored separately with index mapping
// - nested_blocks/indices: nested objects stored as sub-blocks
//
// This reduces tables from O(n) to O(1) for flat metadata objects!


/// Convert a KV metadata value to a columnar MetadataBlock
/// This is the high-performance path that batches all entries into vectors
fn metadata_kv_to_block(
    builder: *flatbuffers.Builder,
    allocator: Allocator,
    kv: MetadataMap,
) anyerror!tlb.MetadataBlock
{
    const count = kv.fields.count();
    if (count == 0) {
        return try builder.writeTable(tlb.MetadataBlock, .{});
    }

    // Pre-allocate all arrays
    const keys = try allocator.alloc([]const u8, count);
    const types = try allocator.alloc(i8, count);
    const scalars = try allocator.alloc(tlb.PackedScalar, count);

    // Track string, nested, and array values separately
    var string_values_list: std.ArrayList([]const u8) = .empty;
    var string_indices_list: std.ArrayList(u32) = .empty;
    var nested_blocks_list: std.ArrayList(tlb.MetadataBlock) = .empty;
    var nested_indices_list: std.ArrayList(u32) = .empty;
    var array_blocks_list: std.ArrayList(tlb.MetadataBlock) = .empty;
    var array_indices_list: std.ArrayList(u32) = .empty;

    var i: usize = 0;
    for (kv.fields.keys(), kv.fields.values()) |key, value| {
        keys[i] = key;

        switch (value) {
            .null => {
                types[i] = @intFromEnum(tlb.MetadataType.Null);
                scalars[i] = .{ .bool_val = false, .int_val = 0, .float_val = 0.0 };
            },
            .bool => |b| {
                types[i] = @intFromEnum(tlb.MetadataType.Bool);
                scalars[i] = .{ .bool_val = b, .int_val = 0, .float_val = 0.0 };
            },
            .integer => |v| {
                types[i] = @intFromEnum(tlb.MetadataType.Int);
                scalars[i] = .{ .bool_val = false, .int_val = v, .float_val = 0.0 };
            },
            .float => |f| {
                types[i] = @intFromEnum(tlb.MetadataType.Float);
                scalars[i] = .{ .bool_val = false, .int_val = 0, .float_val = f };
            },
            .bytes => |s| {
                types[i] = @intFromEnum(tlb.MetadataType.String);
                scalars[i] = .{ .bool_val = false, .int_val = 0, .float_val = 0.0 };
                try string_indices_list.append(allocator, @intCast(i));
                try string_values_list.append(allocator, s);
            },
            .@"enum" => |e| {
                types[i] = @intFromEnum(tlb.MetadataType.String);
                scalars[i] = .{ .bool_val = false, .int_val = 0, .float_val = 0.0 };
                try string_indices_list.append(allocator, @intCast(i));
                try string_values_list.append(allocator, e);
            },
            .@"union" => |u| {
                types[i] = @intFromEnum(tlb.MetadataType.String);
                scalars[i] = .{ .bool_val = false, .int_val = 0, .float_val = 0.0 };
                try string_indices_list.append(allocator, @intCast(i));
                try string_values_list.append(allocator, u.tag);
            },
            .kv => |nested_kv| {
                types[i] = @intFromEnum(tlb.MetadataType.KV);
                scalars[i] = .{ .bool_val = false, .int_val = 0, .float_val = 0.0 };
                try nested_indices_list.append(allocator, @intCast(i));
                const nested_block = try metadata_kv_to_block(builder, allocator, nested_kv);
                try nested_blocks_list.append(allocator, nested_block);
            },
            .array => |arr| {
                types[i] = @intFromEnum(tlb.MetadataType.Array);
                scalars[i] = .{ .bool_val = false, .int_val = 0, .float_val = 0.0 };
                try array_indices_list.append(allocator, @intCast(i));
                const array_block = try metadata_array_to_block(builder, allocator, arr);
                try array_blocks_list.append(allocator, array_block);
            },
        }
        i += 1;
    }

    return try builder.writeTable(tlb.MetadataBlock, .{
        .keys = keys,
        .types = types,
        .scalars = scalars,
        .string_values = if (string_values_list.items.len > 0) string_values_list.items else null,
        .string_indices = if (string_indices_list.items.len > 0) string_indices_list.items else null,
        .nested_blocks = if (nested_blocks_list.items.len > 0) nested_blocks_list.items else null,
        .nested_indices = if (nested_indices_list.items.len > 0) nested_indices_list.items else null,
        .array_blocks = if (array_blocks_list.items.len > 0) array_blocks_list.items else null,
        .array_indices = if (array_indices_list.items.len > 0) array_indices_list.items else null,
    });
}

/// Convert an array of MetadataValues to a columnar MetadataBlock
/// Array elements are stored with empty keys (position is implicit)
fn metadata_array_to_block(
    builder: *flatbuffers.Builder,
    allocator: Allocator,
    arr: []const MetadataValue,
) anyerror!tlb.MetadataBlock
{
    const count = arr.len;
    if (count == 0) {
        return try builder.writeTable(tlb.MetadataBlock, .{});
    }

    // Pre-allocate all arrays
    const keys = try allocator.alloc([]const u8, count);
    const types = try allocator.alloc(i8, count);
    const scalars = try allocator.alloc(tlb.PackedScalar, count);

    // Track string, nested, and array values separately
    var string_values_list: std.ArrayList([]const u8) = .empty;
    var string_indices_list: std.ArrayList(u32) = .empty;
    var nested_blocks_list: std.ArrayList(tlb.MetadataBlock) = .empty;
    var nested_indices_list: std.ArrayList(u32) = .empty;
    var array_blocks_list: std.ArrayList(tlb.MetadataBlock) = .empty;
    var array_indices_list: std.ArrayList(u32) = .empty;

    for (arr, 0..)
        |value, i|
    {
        keys[i] = ""; // Empty key for array elements

        switch (value) {
            .null => {
                types[i] = @intFromEnum(tlb.MetadataType.Null);
                scalars[i] = .{ .bool_val = false, .int_val = 0, .float_val = 0.0 };
            },
            .bool => |b| {
                types[i] = @intFromEnum(tlb.MetadataType.Bool);
                scalars[i] = .{ .bool_val = b, .int_val = 0, .float_val = 0.0 };
            },
            .integer => |v| {
                types[i] = @intFromEnum(tlb.MetadataType.Int);
                scalars[i] = .{ .bool_val = false, .int_val = v, .float_val = 0.0 };
            },
            .float => |f| {
                types[i] = @intFromEnum(tlb.MetadataType.Float);
                scalars[i] = .{ .bool_val = false, .int_val = 0, .float_val = f };
            },
            .bytes => |s| {
                types[i] = @intFromEnum(tlb.MetadataType.String);
                scalars[i] = .{ .bool_val = false, .int_val = 0, .float_val = 0.0 };
                try string_indices_list.append(allocator, @intCast(i));
                try string_values_list.append(allocator, s);
            },
            .@"enum" => |e| {
                types[i] = @intFromEnum(tlb.MetadataType.String);
                scalars[i] = .{ .bool_val = false, .int_val = 0, .float_val = 0.0 };
                try string_indices_list.append(allocator, @intCast(i));
                try string_values_list.append(allocator, e);
            },
            .@"union" => |u| {
                types[i] = @intFromEnum(tlb.MetadataType.String);
                scalars[i] = .{ .bool_val = false, .int_val = 0, .float_val = 0.0 };
                try string_indices_list.append(allocator, @intCast(i));
                try string_values_list.append(allocator, u.tag);
            },
            .kv => |nested_kv| {
                types[i] = @intFromEnum(tlb.MetadataType.KV);
                scalars[i] = .{ .bool_val = false, .int_val = 0, .float_val = 0.0 };
                try nested_indices_list.append(allocator, @intCast(i));
                const nested_block = try metadata_kv_to_block(builder, allocator, nested_kv);
                try nested_blocks_list.append(allocator, nested_block);
            },
            .array => |nested_arr| {
                types[i] = @intFromEnum(tlb.MetadataType.Array);
                scalars[i] = .{ .bool_val = false, .int_val = 0, .float_val = 0.0 };
                try array_indices_list.append(allocator, @intCast(i));
                const array_block = try metadata_array_to_block(builder, allocator, nested_arr);
                try array_blocks_list.append(allocator, array_block);
            },
        }
    }

    return try builder.writeTable(tlb.MetadataBlock, .{
        .keys = keys,
        .types = types,
        .scalars = scalars,
        .string_values = if (string_values_list.items.len > 0) string_values_list.items else null,
        .string_indices = if (string_indices_list.items.len > 0) string_indices_list.items else null,
        .nested_blocks = if (nested_blocks_list.items.len > 0) nested_blocks_list.items else null,
        .nested_indices = if (nested_indices_list.items.len > 0) nested_indices_list.items else null,
        .array_blocks = if (array_blocks_list.items.len > 0) array_blocks_list.items else null,
        .array_indices = if (array_indices_list.items.len > 0) array_indices_list.items else null,
    });
}

/// Convert a MetadataMap to single-table columnar format (MetadataMap)
/// This format eliminates vtable overhead by storing all metadata in one table
/// with parallel arrays, instead of one table per hash entry.
fn metadata_map_to_fb(
    builder: *flatbuffers.Builder,
    allocator: Allocator,
    metadata_map: MetadataMap,
) !?tlb.MetadataMap
{
    const hash_count = metadata_map.fields.count();
    if (hash_count == 0) {
        return null;
    }

    // First pass: count total entries across all hashes
    var total_entries: usize = 0;
    for (metadata_map.fields.values())
        |value|
    {
        switch (value) {
            .kv => |kv| total_entries += kv.fields.count(),
            else => {},
        }
    }

    // Allocate all parallel arrays
    const hashes = try allocator.alloc([]const u8, hash_count);
    const block_offsets = try allocator.alloc(u32, hash_count);
    const block_lengths = try allocator.alloc(u32, hash_count);

    const all_keys = try allocator.alloc([]const u8, total_entries);
    const all_types = try allocator.alloc(u8, total_entries);
    const all_scalars = try allocator.alloc(tlb.PackedScalar, total_entries);

    // Track string and nested values
    var string_values_list: std.ArrayList([]const u8) = .empty;
    var string_key_indices_list: std.ArrayList(u32) = .empty;
    var string_value_indices_list: std.ArrayList(u32) = .empty;
    var nested_blocks_list: std.ArrayList(tlb.MetadataBlock) = .empty;
    var nested_key_indices_list: std.ArrayList(u32) = .empty;
    var nested_block_indices_list: std.ArrayList(u32) = .empty;

    // Fill the arrays
    var hash_idx: usize = 0;
    var flat_idx: usize = 0;

    for (metadata_map.fields.keys(), metadata_map.fields.values())
        |hash, value|
    {
        hashes[hash_idx] = hash;
        block_offsets[hash_idx] = @intCast(flat_idx);

        const entry_count: usize = switch (value) {
            .kv => |kv| blk: {
                const count = kv.fields.count();

                for (kv.fields.keys(), kv.fields.values())
                    |key, val|
                {
                    all_keys[flat_idx] = key;

                    switch (val) {
                        .null => {
                            all_types[flat_idx] = @intFromEnum(tlb.MetadataType.Null);
                            all_scalars[flat_idx] = .{
                                .bool_val = false,
                                .int_val = 0,
                                .float_val = 0.0,
                            };
                        },
                        .bool => |b| {
                            all_types[flat_idx] = @intFromEnum(tlb.MetadataType.Bool);
                            all_scalars[flat_idx] = .{
                                .bool_val = b,
                                .int_val = 0,
                                .float_val = 0.0,
                            };
                        },
                        .integer => |v| {
                            all_types[flat_idx] = @intFromEnum(tlb.MetadataType.Int);
                            all_scalars[flat_idx] = .{
                                .bool_val = false,
                                .int_val = v,
                                .float_val = 0.0,
                            };
                        },
                        .float => |f| {
                            all_types[flat_idx] = @intFromEnum(tlb.MetadataType.Float);
                            all_scalars[flat_idx] = .{
                                .bool_val = false,
                                .int_val = 0,
                                .float_val = f,
                            };
                        },
                        .bytes => |s| {
                            all_types[flat_idx] = @intFromEnum(tlb.MetadataType.String);
                            all_scalars[flat_idx] = .{
                                .bool_val = false,
                                .int_val = 0,
                                .float_val = 0.0,
                            };
                            try string_key_indices_list.append(allocator, @intCast(flat_idx));
                            try string_value_indices_list.append(
                                allocator,
                                @intCast(string_values_list.items.len),
                            );
                            try string_values_list.append(allocator, s);
                        },
                        .@"enum" => |e| {
                            all_types[flat_idx] = @intFromEnum(tlb.MetadataType.String);
                            all_scalars[flat_idx] = .{
                                .bool_val = false,
                                .int_val = 0,
                                .float_val = 0.0,
                            };
                            try string_key_indices_list.append(allocator, @intCast(flat_idx));
                            try string_value_indices_list.append(
                                allocator,
                                @intCast(string_values_list.items.len),
                            );
                            try string_values_list.append(allocator, e);
                        },
                        .@"union" => |u| {
                            all_types[flat_idx] = @intFromEnum(tlb.MetadataType.String);
                            all_scalars[flat_idx] = .{
                                .bool_val = false,
                                .int_val = 0,
                                .float_val = 0.0,
                            };
                            try string_key_indices_list.append(allocator, @intCast(flat_idx));
                            try string_value_indices_list.append(
                                allocator,
                                @intCast(string_values_list.items.len),
                            );
                            try string_values_list.append(allocator, u.tag);
                        },
                        .kv => |nested_kv| {
                            all_types[flat_idx] = @intFromEnum(tlb.MetadataType.KV);
                            all_scalars[flat_idx] = .{
                                .bool_val = false,
                                .int_val = 0,
                                .float_val = 0.0,
                            };
                            try nested_key_indices_list.append(allocator, @intCast(flat_idx));
                            try nested_block_indices_list.append(
                                allocator,
                                @intCast(nested_blocks_list.items.len),
                            );
                            const nested_block = try metadata_kv_to_block(builder, allocator, nested_kv);
                            try nested_blocks_list.append(allocator, nested_block);
                        },
                        .array => |arr| {
                            all_types[flat_idx] = @intFromEnum(tlb.MetadataType.Array);
                            all_scalars[flat_idx] = .{
                                .bool_val = false,
                                .int_val = 0,
                                .float_val = 0.0,
                            };
                            // Store array as MetadataBlock using nested_blocks mechanism
                            try nested_key_indices_list.append(allocator, @intCast(flat_idx));
                            try nested_block_indices_list.append(
                                allocator,
                                @intCast(nested_blocks_list.items.len),
                            );
                            const array_block = try metadata_array_to_block(builder, allocator, arr);
                            try nested_blocks_list.append(allocator, array_block);
                        },
                    }
                    flat_idx += 1;
                }
                break :blk count;
            },
            else => 0,
        };

        block_lengths[hash_idx] = @intCast(entry_count);
        hash_idx += 1;
    }

    return try builder.writeTable(tlb.MetadataMap, .{
        .hashes = hashes,
        .block_offsets = block_offsets,
        .block_lengths = block_lengths,
        .all_keys = all_keys,
        .all_types = all_types,
        .all_scalars = all_scalars,
        .string_values = if (string_values_list.items.len > 0) string_values_list.items else null,
        .string_key_indices = if (string_key_indices_list.items.len > 0)
            string_key_indices_list.items
        else
            null,
        .string_value_indices = if (string_value_indices_list.items.len > 0)
            string_value_indices_list.items
        else
            null,
        .nested_blocks = if (nested_blocks_list.items.len > 0) nested_blocks_list.items else null,
        .nested_key_indices = if (nested_key_indices_list.items.len > 0)
            nested_key_indices_list.items
        else
            null,
        .nested_block_indices = if (nested_block_indices_list.items.len > 0)
            nested_block_indices_list.items
        else
            null,
    });
}


// ----------------------------------------------------------------------------
// SerializableComposable -> FlatBuffers Conversion
// ----------------------------------------------------------------------------

/// Alias for SerializableTimeline types
const SerializableTimeline = serializable.SerializableTimeline;
const SerializableComposable = serializable.SerializableComposable;
const SerializableBounds = serializable.SerializableBounds;

/// Convert SerializableBounds to FlatBuffers Bounds
fn serializable_bounds_to_fb(
    builder: *flatbuffers.Builder,
    bounds: SerializableBounds,
) !tlb.Bounds
{
    return switch (bounds) {
        .continuous => |c| try builder.writeTable(tlb.Bounds, .{
            .bounds_type = .Continuous,
            .continuous = .{ .start = c[0], .end = c[1] },
        }),
        .discrete => |d| try builder.writeTable(tlb.Bounds, .{
            .bounds_type = .Discrete,
            .discrete = .{ .start = d[0], .end = d[1] },
        }),
    };
}

/// Convert SerializableComposable to FlatBuffers ComposableWrapper
fn serializable_composable_to_fb(
    builder: *flatbuffers.Builder,
    allocator: Allocator,
    composable: SerializableComposable,
) anyerror!tlb.ComposableWrapper
{
    return switch (composable) {
        .clip => |clip| try builder.writeTable(tlb.ComposableWrapper, .{
            .comp_type = .Clip,
            .clip = try serializable_clip_to_fb(builder, allocator, clip),
        }),
        .gap => |gap| try builder.writeTable(tlb.ComposableWrapper, .{
            .comp_type = .Gap,
            .gap = try builder.writeTable(tlb.Gap, .{
                .name = gap.name,
                .bounds_start = gap.bounds_s[0],
                .bounds_end = gap.bounds_s[1],
                .markers = try serializable_markers_to_fb(builder, gap.markers),
            }),
        }),
        .track => |track| try builder.writeTable(tlb.ComposableWrapper, .{
            .comp_type = .Track,
            .track = try serializable_track_to_fb(builder, allocator, track),
        }),
        .stack => |stack| try builder.writeTable(tlb.ComposableWrapper, .{
            .comp_type = .Stack,
            .stack = try serializable_stack_to_fb(builder, allocator, stack),
        }),
        .warp => |warp| try builder.writeTable(tlb.ComposableWrapper, .{
            .comp_type = .Warp,
            .warp = try serializable_warp_to_fb(builder, allocator, warp),
        }),
        .transition => |trans| try builder.writeTable(tlb.ComposableWrapper, .{
            .comp_type = .Transition,
            .transition = try serializable_transition_to_fb(builder, allocator, trans),
        }),
    };
}

/// Convert SerializableMarker to FlatBuffers Marker
fn serializable_marker_to_fb(
    builder: *flatbuffers.Builder,
    marker: serializable.SerializableMarker,
) !tlb.Marker
{
    return try builder.writeTable(tlb.Marker, .{
        .name = marker.name,
        .marked_range_start = marker.marked_range[0],
        .marked_range_end = marker.marked_range[1],
        .color = marker.color,
        .comment = marker.comment,
    });
}

/// Convert array of SerializableMarker to FlatBuffers Marker vector
fn serializable_markers_to_fb(
    builder: *flatbuffers.Builder,
    markers: []serializable.SerializableMarker,
) !?[]tlb.Marker
{
    if (markers.len == 0) {
        return null;
    }
    var fb_markers = try builder.allocator.alloc(tlb.Marker, markers.len);
    // Don't defer free - ownership transferred to caller

    for (markers, 0..)
        |marker, i|
    {
        fb_markers[i] = try serializable_marker_to_fb(builder, marker);
    }
    return fb_markers;
}

/// Convert SerializableClip to FlatBuffers Clip
fn serializable_clip_to_fb(
    builder: *flatbuffers.Builder,
    allocator: Allocator,
    clip: serializable.SerializableClip,
) !tlb.Clip
{
    // Convert hex string to u64 for binary storage
    const hash_val: u64 = if (clip.metadata_hash) |h|
        serializable.hex_string_to_hash(h) orelse 0
    else
        0;

    return try builder.writeTable(tlb.Clip, .{
        .name = clip.name,
        .bounds = if (clip.bounds_s) |b| try serializable_bounds_to_fb(builder, b) else null,
        .media = try serializable_media_ref_to_fb(builder, allocator, clip.media),
        .metadata_hash = hash_val,
        .markers = try serializable_markers_to_fb(builder, clip.markers),
    });
}

/// Convert SerializableMediaReference to FlatBuffers MediaReference
fn serializable_media_ref_to_fb(
    builder: *flatbuffers.Builder,
    allocator: Allocator,
    ref: serializable.SerializableMediaReference,
) !tlb.MediaReference
{
    _ = allocator;
    return try builder.writeTable(tlb.MediaReference, .{
        .data_reference_type = try serializable_data_ref_to_fb(builder, ref.data_reference),
        .bounds = if (ref.bounds_s) |b| try serializable_bounds_to_fb(builder, b) else null,
        .domain = try builder.writeTable(tlb.Domain, .{
            .domain_type = switch (ref.domain) {
                .time => .Time,
                .picture => .Picture,
                .audio => .Audio,
                .metadata => .Metadata,
                .other => .Other,
            },
            .other_name = if (ref.domain == .other) ref.domain.other.name else null,
        }),
        .discrete_partition = if (ref.discrete_partition) |dp|
            try builder.writeTable(tlb.SampleIndexGenerator, .{
                .sample_rate_hz_type = switch (dp.sample_rate_hz) {
                    .Integer => |v| .{ .IntRate = try builder.writeTable(tlb.IntRate, .{ .value = v }) },
                    .Rational => |r| .{ .RationalRate = try builder.writeTable(tlb.RationalRate, .{ .num = r.num, .den = r.den }) },
                },
                .start_index = dp.start_index,
            })
        else
            null,
    });
}

/// Convert SerializableMediaDataReference to FlatBuffers
fn serializable_data_ref_to_fb(
    builder: *flatbuffers.Builder,
    ref: serializable.SerializableMediaDataReference,
) !tlb.MediaDataReference
{
    return switch (ref) {
        .uri => |u| .{ .URIReference = try builder.writeTable(tlb.URIReference, .{ .target_uri = u.target_uri }) },
        .signal => |s| blk: {
            const sig_gen = switch (s.signal_generator) {
                .sine => |sine| tlb.SignalGenerator{
                    .SineSignal = try builder.writeTable(tlb.SineSignal, .{
                        .frequency_hz = sine.frequency_hz,
                    }),
                },
                .linear_ramp => tlb.SignalGenerator{
                    .LinearRampSignal = try builder.writeTable(tlb.LinearRampSignal, .{}),
                },
            };
            break :blk .{
                .SignalReference = try builder.writeTable(tlb.SignalReference, .{
                    .signal_generator_type = sig_gen,
                }),
            };
        },
        .image_sequence => |img_seq| .{
            .ImageSequenceReference = try builder.writeTable(tlb.ImageSequenceReference, .{
                .target_url_base = img_seq.target_url_base,
                .name_prefix = if (img_seq.name_prefix.len > 0) img_seq.name_prefix else null,
                .name_suffix = if (img_seq.name_suffix.len > 0) img_seq.name_suffix else null,
                .frame_zero_padding = img_seq.frame_zero_padding,
                .missing_frame_policy = (
                    if (img_seq.missing_frame_policy.len > 0)
                        img_seq.missing_frame_policy
                    else null
                ),
            }),
        },
        .null => .{ .NullReference = try builder.writeTable(tlb.NullReference, .{}) },
    };
}

/// Convert SerializableTrack to FlatBuffers Track
fn serializable_track_to_fb(
    builder: *flatbuffers.Builder,
    allocator: Allocator,
    track: serializable.SerializableTrack,
) !tlb.Track
{
    if (track.children.len == 0) {
        return try builder.writeTable(tlb.Track, .{
            .name = track.name,
            .children = null,
            .markers = try serializable_markers_to_fb(builder, track.markers),
        });
    }

    // Pre-allocate exact capacity needed
    const children = try allocator.alloc(tlb.ComposableWrapper, track.children.len);
    defer allocator.free(children);

    for (track.children, 0..)
        |child, i|
    {
        children[i] = try serializable_composable_to_fb(builder, allocator, child);
    }

    return try builder.writeTable(tlb.Track, .{
        .name = track.name,
        .children = children,
        .markers = try serializable_markers_to_fb(builder, track.markers),
    });
}

/// Convert SerializableStack to FlatBuffers Stack
fn serializable_stack_to_fb(
    builder: *flatbuffers.Builder,
    allocator: Allocator,
    stack: serializable.SerializableStack,
) !tlb.Stack
{
    if (stack.children.len == 0) {
        return try builder.writeTable(tlb.Stack, .{
            .name = stack.name,
            .children = null,
            .markers = try serializable_markers_to_fb(builder, stack.markers),
        });
    }

    // Pre-allocate exact capacity needed
    const children = try allocator.alloc(tlb.ComposableWrapper, stack.children.len);
    defer allocator.free(children);

    for (stack.children, 0..)
        |child, i|
    {
        children[i] = try serializable_composable_to_fb(builder, allocator, child);
    }

    return try builder.writeTable(tlb.Stack, .{
        .name = stack.name,
        .children = children,
        .markers = try serializable_markers_to_fb(builder, stack.markers),
    });
}

/// Convert SerializableWarp to FlatBuffers Warp
fn serializable_warp_to_fb(
    builder: *flatbuffers.Builder,
    allocator: Allocator,
    warp: serializable.SerializableWarp,
) !tlb.Warp
{
    const child_wrapper = try serializable_composable_to_fb(builder, allocator, warp.child.*);
    const topology = try serializable_topology_to_fb(builder, allocator, warp.transform);
    return try builder.writeTable(tlb.Warp, .{
        .name = warp.name,
        .child = child_wrapper,
        .transform = topology,
    });
}

/// Convert SerializableTopology to FlatBuffers Topology
fn serializable_topology_to_fb(
    builder: *flatbuffers.Builder,
    allocator: Allocator,
    topo: serializable.SerializableTopology,
) !tlb.Topology
{
    var mapping_wrappers: std.ArrayList(tlb.MappingWrapper) = .empty;
    defer mapping_wrappers.deinit(allocator);

    for (topo.mappings)
        |mapping|
    {
        try mapping_wrappers.append(allocator, try serializable_mapping_to_fb(builder, mapping));
    }

    return try builder.writeTable(tlb.Topology, .{
        .mappings = mapping_wrappers.items,
    });
}

/// Convert SerializableMapping to FlatBuffers MappingWrapper
fn serializable_mapping_to_fb(
    builder: *flatbuffers.Builder,
    mapping: serializable.SerializableMapping,
) !tlb.MappingWrapper
{
    return switch (mapping) {
        .affine => |aff| try builder.writeTable(tlb.MappingWrapper, .{
            .mapping_type = .Affine,
            .affine = try builder.writeTable(tlb.MappingAffine, .{
                .input_bounds_start = aff.input_bounds_val[0],
                .input_bounds_end = aff.input_bounds_val[1],
                .transform = .{
                    .offset = aff.input_to_output_xform.offset,
                    .scale = aff.input_to_output_xform.scale,
                },
            }),
        }),
        .linear => |lin| blk: {
            var knots: std.ArrayList(tlb.ControlPoint) = .empty;
            defer knots.deinit(builder.allocator);
            for (lin.knots)
                |knot|
            {
                try knots.append(builder.allocator, .{ .in_val = knot[0], .out_val = knot[1] });
            }
            break :blk try builder.writeTable(tlb.MappingWrapper, .{
                .mapping_type = .Linear,
                .linear = try builder.writeTable(tlb.MappingLinear, .{
                    .input_bounds_start = lin.input_bounds_val[0],
                    .input_bounds_end = lin.input_bounds_val[1],
                    .knots = knots.items,
                }),
            });
        },
        .empty => try builder.writeTable(tlb.MappingWrapper, .{
            .mapping_type = .Empty,
        }),
    };
}

/// Convert SerializableTransition to FlatBuffers Transition
fn serializable_transition_to_fb(
    builder: *flatbuffers.Builder,
    allocator: Allocator,
    trans: serializable.SerializableTransition,
) !tlb.Transition
{
    const has_bounds = trans.bounds_s != null;

    // Serialize container children if present
    const container = try serializable_stack_to_fb(builder, allocator, trans.container);

    return try builder.writeTable(tlb.Transition, .{
        .name = trans.name,
        .kind = trans.kind,
        .has_bounds = has_bounds,
        .bounds_start = if (trans.bounds_s) |b| b[0] else 0.0,
        .bounds_end = if (trans.bounds_s) |b| b[1] else 0.0,
        .container = container,
    });
}

/// Convert SerializableRateSpecifier to FlatBuffers RateSpecifier
fn serializable_rate_to_fb(
    builder: *flatbuffers.Builder,
    rate: serializable.SerializableRateSpecifier,
) !tlb.RateSpecifier
{
    return switch (rate) {
        .Integer => |val| .{
            .IntRate = try builder.writeTable(tlb.IntRate, .{ .value = val }),
        },
        .Rational => |r| .{
            .RationalRate = try builder.writeTable(
                tlb.RationalRate,
                .{ .num = r.num, .den = r.den },
            ),
        },
    };
}

/// Convert SerializableSampleIndexGenerator to FlatBuffers SampleIndexGenerator
fn serializable_sig_to_fb(
    builder: *flatbuffers.Builder,
    sig: serializable.SerializableSampleIndexGenerator,
) !tlb.SampleIndexGenerator
{
    return try builder.writeTable(tlb.SampleIndexGenerator, .{
        .sample_rate_hz_type = try serializable_rate_to_fb(builder, sig.sample_rate_hz),
        .start_index = sig.start_index,
    });
}

/// Convert SerializableDiscretePartitionDomainMap to FlatBuffers DiscretePartitionDomainMap
fn serializable_discrete_partitions_to_fb(
    builder: *flatbuffers.Builder,
    partitions: serializable.SerializableDiscretePartitionDomainMap,
) !?tlb.DiscretePartitionDomainMap
{
    // Only create the table if at least one partition is set
    if (partitions.picture == null and partitions.audio == null) {
        return null;
    }

    return try builder.writeTable(tlb.DiscretePartitionDomainMap, .{
        .picture = if (partitions.picture) |p| try serializable_sig_to_fb(builder, p) else null,
        .audio = if (partitions.audio) |a| try serializable_sig_to_fb(builder, a) else null,
    });
}

// ----------------------------------------------------------------------------
// Metadata Conversion: FlatBuffers -> MetadataMap (High-Performance Columnar Format)
// ----------------------------------------------------------------------------

/// Error type for metadata block conversion
const MetadataBlockConvertError = error{OutOfMemory};

/// Convert a MetadataBlock representing an array back to MetadataValue slice
fn fb_block_to_metadata_array(
    allocator: Allocator,
    block: tlb.MetadataBlock,
) MetadataBlockConvertError![]MetadataValue
{
    const keys_vec = block.keys() orelse return &.{};
    const types_vec = block.types() orelse return &.{};
    const scalars_vec = block.scalars() orelse return &.{};

    const count = keys_vec.len();
    if (count == 0) return &.{};

    var result = try allocator.alloc(MetadataValue, count);

    // Build lookup tables for strings, nested blocks, and arrays
    var string_lookup = std.AutoHashMap(u32, u32).init(allocator);
    defer string_lookup.deinit();
    var nested_lookup = std.AutoHashMap(u32, u32).init(allocator);
    defer nested_lookup.deinit();
    var array_lookup = std.AutoHashMap(u32, u32).init(allocator);
    defer array_lookup.deinit();

    if (block.string_indices()) |si| {
        for (0..si.len()) |j| {
            try string_lookup.put(si.get(j), @intCast(j));
        }
    }
    if (block.nested_indices()) |ni| {
        for (0..ni.len()) |j| {
            try nested_lookup.put(ni.get(j), @intCast(j));
        }
    }
    if (block.array_indices()) |ai| {
        for (0..ai.len()) |j| {
            try array_lookup.put(ai.get(j), @intCast(j));
        }
    }

    for (0..count)
        |i|
    {
        const value_type: tlb.MetadataType = @enumFromInt(types_vec.get(i));
        const scalar = scalars_vec.get(i);

        result[i] = switch (value_type) {
            .Null => .null,
            .Bool => .{ .bool = scalar.bool_val },
            .Int => .{ .integer = scalar.int_val },
            .Float => .{ .float = scalar.float_val },
            .String => blk: {
                if (string_lookup.get(@intCast(i))) |str_list_idx| {
                    if (block.string_values()) |sv| {
                        if (str_list_idx < sv.len()) {
                            break :blk .{ .bytes = try allocator.dupe(u8, sv.get(str_list_idx)) };
                        }
                    }
                }
                break :blk .{ .bytes = "" };
            },
            .KV => blk: {
                if (nested_lookup.get(@intCast(i))) |blk_list_idx| {
                    if (block.nested_blocks()) |nb| {
                        if (blk_list_idx < nb.len()) {
                            break :blk .{ .kv = try fb_block_to_metadata_kv(allocator, nb.get(blk_list_idx)) };
                        }
                    }
                }
                break :blk .{ .kv = .{ .container_kind = .dict } };
            },
            .Array => blk: {
                if (array_lookup.get(@intCast(i))) |arr_list_idx| {
                    if (block.array_blocks()) |ab| {
                        if (arr_list_idx < ab.len()) {
                            break :blk .{ .array = try fb_block_to_metadata_array(allocator, ab.get(arr_list_idx)) };
                        }
                    }
                }
                break :blk .{ .array = &.{} };
            },
        };
    }

    return result;
}

/// Convert a columnar MetadataBlock back to a MetadataMap
fn fb_block_to_metadata_kv(
    allocator: Allocator,
    block: tlb.MetadataBlock,
) MetadataBlockConvertError!MetadataMap
{
    const keys_vec = block.keys() orelse return .{ .container_kind = .dict };
    const types_vec = block.types() orelse return .{ .container_kind = .dict };
    const scalars_vec = block.scalars() orelse return .{ .container_kind = .dict };

    const count = keys_vec.len();
    if (count == 0) return .{ .container_kind = .dict };

    var map: MetadataMap = .{ .container_kind = .dict };
    try map.fields.ensureTotalCapacity(allocator, count);

    // Build lookup tables for strings, nested blocks, and arrays
    var string_lookup = std.AutoHashMap(u32, u32).init(allocator);
    defer string_lookup.deinit();
    var nested_lookup = std.AutoHashMap(u32, u32).init(allocator);
    defer nested_lookup.deinit();
    var array_lookup = std.AutoHashMap(u32, u32).init(allocator);
    defer array_lookup.deinit();

    if (block.string_indices()) |si| {
        for (0..si.len()) |j| {
            try string_lookup.put(si.get(j), @intCast(j));
        }
    }
    if (block.nested_indices()) |ni| {
        for (0..ni.len()) |j| {
            try nested_lookup.put(ni.get(j), @intCast(j));
        }
    }
    if (block.array_indices()) |ai| {
        for (0..ai.len()) |j| {
            try array_lookup.put(ai.get(j), @intCast(j));
        }
    }

    for (0..count)
        |i|
    {
        const key = try allocator.dupe(u8, keys_vec.get(i));
        const value_type: tlb.MetadataType = @enumFromInt(types_vec.get(i));
        const scalar = scalars_vec.get(i);

        const value: MetadataValue = switch (value_type) {
            .Null => .null,
            .Bool => .{ .bool = scalar.bool_val },
            .Int => .{ .integer = scalar.int_val },
            .Float => .{ .float = scalar.float_val },
            .String => blk: {
                if (string_lookup.get(@intCast(i))) |str_list_idx| {
                    if (block.string_values()) |sv| {
                        if (str_list_idx < sv.len()) {
                            break :blk .{ .bytes = try allocator.dupe(u8, sv.get(str_list_idx)) };
                        }
                    }
                }
                break :blk .{ .bytes = "" };
            },
            .KV => blk: {
                if (nested_lookup.get(@intCast(i))) |blk_list_idx| {
                    if (block.nested_blocks()) |nb| {
                        if (blk_list_idx < nb.len()) {
                            break :blk .{ .kv = try fb_block_to_metadata_kv(allocator, nb.get(blk_list_idx)) };
                        }
                    }
                }
                break :blk .{ .kv = .{ .container_kind = .dict } };
            },
            .Array => blk: {
                if (array_lookup.get(@intCast(i))) |arr_list_idx| {
                    if (block.array_blocks()) |ab| {
                        if (arr_list_idx < ab.len()) {
                            break :blk .{ .array = try fb_block_to_metadata_array(allocator, ab.get(arr_list_idx)) };
                        }
                    }
                }
                break :blk .{ .array = &.{} };
            },
        };

        map.fields.putAssumeCapacity(key, value);
    }

    return map;
}

/// Convert single-table columnar MetadataMap to MetadataMap
fn fb_to_metadata_map_single_table(
    allocator: Allocator,
    fb_map: tlb.MetadataMap,
) !MetadataMap
{
    const hashes_vec = fb_map.hashes() orelse return .{ .container_kind = .dict };
    const offsets_vec = fb_map.block_offsets() orelse return .{ .container_kind = .dict };
    const lengths_vec = fb_map.block_lengths() orelse return .{ .container_kind = .dict };
    const all_keys_vec = fb_map.all_keys() orelse return .{ .container_kind = .dict };
    const all_types_vec = fb_map.all_types() orelse return .{ .container_kind = .dict };
    const all_scalars_vec = fb_map.all_scalars() orelse return .{ .container_kind = .dict };

    const hash_count = hashes_vec.len();
    if (hash_count == 0) return .{ .container_kind = .dict };

    // Get optional string and nested vectors
    const string_values_vec = fb_map.string_values();
    const string_key_indices_vec = fb_map.string_key_indices();
    const string_value_indices_vec = fb_map.string_value_indices();
    const nested_blocks_vec = fb_map.nested_blocks();
    const nested_key_indices_vec = fb_map.nested_key_indices();
    const nested_block_indices_vec = fb_map.nested_block_indices();

    // Build lookup tables for string and nested indices
    // These map flat_idx -> string_values index or nested_blocks index
    var string_lookup = std.AutoHashMap(u32, u32).init(allocator);
    defer string_lookup.deinit();

    if (string_key_indices_vec)
        |ski|
    {
        if (string_value_indices_vec)
            |svi|
        {
            const len = @min(ski.len(), svi.len());
            for (0..len)
                |i|
            {
                try string_lookup.put(ski.get(i), svi.get(i));
            }
        }
    }

    var nested_lookup = std.AutoHashMap(u32, u32).init(allocator);
    defer nested_lookup.deinit();

    if (nested_key_indices_vec)
        |nki|
    {
        if (nested_block_indices_vec)
            |nbi|
        {
            const len = @min(nki.len(), nbi.len());
            for (0..len)
                |i|
            {
                try nested_lookup.put(nki.get(i), nbi.get(i));
            }
        }
    }

    var map: MetadataMap = .{ .container_kind = .dict };
    try map.fields.ensureTotalCapacity(allocator, hash_count);

    for (0..hash_count)
        |hash_idx|
    {
        const hash = try allocator.dupe(u8, hashes_vec.get(hash_idx));
        const offset = offsets_vec.get(hash_idx);
        const length = lengths_vec.get(hash_idx);

        // Build the KV map for this hash
        var kv: MetadataMap = .{ .container_kind = .dict };
        try kv.fields.ensureTotalCapacity(allocator, length);

        for (0..length)
            |i|
        {
            const flat_idx = offset + @as(u32, @intCast(i));
            const key = try allocator.dupe(u8, all_keys_vec.get(flat_idx));
            const value_type: tlb.MetadataType = @enumFromInt(all_types_vec.get(flat_idx));
            const scalar = all_scalars_vec.get(flat_idx);

            const value: MetadataValue = switch (value_type) {
                .Null => .null,
                .Bool => .{ .bool = scalar.bool_val },
                .Int => .{ .integer = scalar.int_val },
                .Float => .{ .float = scalar.float_val },
                .String => blk: {
                    if (string_lookup.get(flat_idx))
                        |str_idx|
                    {
                        if (string_values_vec)
                            |sv|
                        {
                            if (str_idx < sv.len()) {
                                break :blk .{ .bytes = try allocator.dupe(u8, sv.get(str_idx)) };
                            }
                        }
                    }
                    break :blk .{ .bytes = "" };
                },
                .KV => blk: {
                    if (nested_lookup.get(flat_idx))
                        |blk_idx|
                    {
                        if (nested_blocks_vec)
                            |nb|
                        {
                            if (blk_idx < nb.len()) {
                                break :blk .{
                                    .kv = try fb_block_to_metadata_kv(allocator, nb.get(blk_idx)),
                                };
                            }
                        }
                    }
                    break :blk .{ .kv = .{ .container_kind = .dict } };
                },
                .Array => blk: {
                    // Arrays are stored as MetadataBlock in nested_blocks
                    if (nested_lookup.get(flat_idx))
                        |blk_idx|
                    {
                        if (nested_blocks_vec)
                            |nb|
                        {
                            if (blk_idx < nb.len()) {
                                break :blk .{
                                    .array = try fb_block_to_metadata_array(allocator, nb.get(blk_idx)),
                                };
                            }
                        }
                    }
                    break :blk .{ .array = &.{} };
                },
            };

            kv.fields.putAssumeCapacity(key, value);
        }

        map.fields.putAssumeCapacity(hash, .{ .kv = kv });
    }

    return map;
}


// ----------------------------------------------------------------------------
// FlatBuffers -> SerializableComposable Conversion
// ----------------------------------------------------------------------------

/// Convert FlatBuffers Bounds to SerializableBounds
fn fb_to_serializable_bounds(
    fb_bounds: tlb.Bounds,
) SerializableBounds
{
    return switch (fb_bounds.bounds_type()) {
        .Continuous => blk: {
            if (fb_bounds.continuous()) |c| {
                break :blk .{ .continuous = .{ c.start, c.end } };
            }
            break :blk .{ .continuous = .{ 0.0, 0.0 } };
        },
        .Discrete => blk: {
            if (fb_bounds.discrete()) |d| {
                break :blk .{ .discrete = .{ d.start, d.end } };
            }
            break :blk .{ .discrete = .{ 0, 0 } };
        },
    };
}

/// Convert FlatBuffers MediaDataReference to SerializableMediaDataReference
fn fb_to_serializable_data_ref(
    allocator: Allocator,
    fb_ref: tlb.MediaDataReference,
) !serializable.SerializableMediaDataReference
{
    return switch (fb_ref) {
        .URIReference => |uri_ref| .{
            .uri = .{
                // target_uri() returns non-optional flatbuffers.String
                .target_uri = try allocator.dupe(u8, uri_ref.target_uri()),
            },
        },
        .SignalReference => |sig_ref| blk: {
            const sg = sig_ref.signal_generator_type();
            const signal_gen: serializable.SerializableSignalGenerator = switch (sg) {
                .SineSignal => |sine| .{ .sine = .{ .frequency_hz = sine.frequency_hz() } },
                .LinearRampSignal => .linear_ramp,
                .NONE => .{ .sine = .{ .frequency_hz = 1000.0 } },
            };
            break :blk .{
                .signal = .{ .signal_generator = signal_gen },
            };
        },
        .ImageSequenceReference => |img_seq| .{
            .image_sequence = .{
                // target_url_base() returns non-optional flatbuffers.String
                .target_url_base = try allocator.dupe(u8, img_seq.target_url_base()),
                // name_prefix() returns optional ?flatbuffers.String
                .name_prefix = if (img_seq.name_prefix()) |p|
                    try allocator.dupe(u8, p)
                else
                    "",
                // name_suffix() returns optional ?flatbuffers.String
                .name_suffix = if (img_seq.name_suffix()) |s|
                    try allocator.dupe(u8, s)
                else
                    "",
                .frame_zero_padding = img_seq.frame_zero_padding(),
                // missing_frame_policy() returns optional ?flatbuffers.String
                .missing_frame_policy = if (img_seq.missing_frame_policy()) |p|
                    try allocator.dupe(u8, p)
                else
                    "error",
            },
        },
        .NullReference, .NONE => .null,
    };
}

/// Convert FlatBuffers Domain to serialization.SerializableDomain
fn fb_to_serializable_domain(
    allocator: Allocator,
    fb_dom: tlb.Domain,
) !serializable.SerializableDomain
{
    return switch (fb_dom.domain_type()) {
        .Time => .time,
        .Picture => .picture,
        .Audio => .audio,
        .Metadata => .metadata,
        .Other => .{ .other = .{ .name = try allocator.dupe(u8, fb_dom.other_name() orelse "") } },
    };
}

/// Convert FlatBuffers RateSpecifier to SerializableRateSpecifier
fn fb_to_serializable_rate(
    fb_rate: tlb.RateSpecifier,
) serializable.SerializableRateSpecifier
{
    return switch (fb_rate) {
        .IntRate => |rate| .{ .Integer = rate.value() },
        .RationalRate => |rate| .{ .Rational = .{ .num = rate.num(), .den = rate.den() } },
        .NONE => .{ .Integer = 1 },
    };
}

/// Convert FlatBuffers MediaReference to SerializableMediaReference
fn fb_to_serializable_media_ref(
    allocator: Allocator,
    fb_ref: tlb.MediaReference,
) !serializable.SerializableMediaReference
{
    return .{
        .data_reference = try fb_to_serializable_data_ref(allocator, fb_ref.data_reference_type()),
        .bounds_s = if (fb_ref.bounds()) |b| fb_to_serializable_bounds(b) else null,
        .domain = if (fb_ref.domain()) |d| try fb_to_serializable_domain(allocator, d) else .time,
        .discrete_partition = if (fb_ref.discrete_partition()) |dp|
            .{
                .sample_rate_hz = fb_to_serializable_rate(dp.sample_rate_hz_type()),
                .start_index = dp.start_index(),
            }
        else
            null,
    };
}

/// Convert FlatBuffers Marker to SerializableMarker
fn fb_to_serializable_marker(
    allocator: Allocator,
    fb_marker: tlb.Marker,
) !serializable.SerializableMarker
{
    return .{
        .name = if (fb_marker.name()) |n| try allocator.dupe(u8, n) else "",
        .marked_range = [2]f64{
            fb_marker.marked_range_start(),
            fb_marker.marked_range_end(),
        },
        .color = try allocator.dupe(u8, fb_marker.color()),
        .comment = if (fb_marker.comment()) |c| try allocator.dupe(u8, c) else "",
    };
}

/// Convert FlatBuffers Marker vector to SerializableMarker array
fn fb_to_serializable_markers(
    allocator: Allocator,
    fb_markers: ?flatbuffers.Vector(tlb.Marker),
) ![]serializable.SerializableMarker
{
    if (fb_markers)
        |markers|
    {
        const len = markers.len();
        if (len == 0) {
            return &.{};
        }
        var result = try allocator.alloc(serializable.SerializableMarker, len);
        for (0..len)
            |i|
        {
            result[i] = try fb_to_serializable_marker(allocator, markers.get(i));
        }
        return result;
    }
    return &.{};
}

/// Convert FlatBuffers Clip to SerializableClip
fn fb_to_serializable_clip(
    allocator: Allocator,
    fb_clip: tlb.Clip,
) !serializable.SerializableClip
{
    const hash_val = fb_clip.metadata_hash();
    // Convert u64 back to hex string for SerializableClip
    const hash_str: ?[]const u8 = if (hash_val != 0)
        try serializable.hash_to_hex_string(allocator, hash_val)
    else
        null;

    return .{
        .name = if (fb_clip.name()) |n| try allocator.dupe(u8, n) else "",
        .bounds_s = if (fb_clip.bounds()) |b| fb_to_serializable_bounds(b) else null,
        .media = if (fb_clip.media()) |m| try fb_to_serializable_media_ref(allocator, m) else .{
            .data_reference = .null,
            .bounds_s = null,
            .domain = .time,
            .discrete_partition = null,
        },
        .metadata_hash = hash_str,
        .markers = try fb_to_serializable_markers(allocator, fb_clip.markers()),
    };
}

/// Convert FlatBuffers Gap to SerializableGap
fn fb_to_serializable_gap(
    allocator: Allocator,
    fb_gap: tlb.Gap,
) !serializable.SerializableGap
{
    return .{
        .name = if (fb_gap.name()) |n| try allocator.dupe(u8, n) else "",
        .bounds_s = .{ fb_gap.bounds_start(), fb_gap.bounds_end() },
        .markers = try fb_to_serializable_markers(allocator, fb_gap.markers()),
    };
}

/// Convert FlatBuffers Track to SerializableTrack
fn fb_to_serializable_track(
    allocator: Allocator,
    fb_track: tlb.Track,
) !serializable.SerializableTrack
{
    var children: std.ArrayList(SerializableComposable) = .empty;
    if (fb_track.children()) |fb_children| {
        try children.ensureTotalCapacity(allocator, fb_children.len());
        for (0..fb_children.len()) |i| {
            children.appendAssumeCapacity(try fb_to_serializable_composable(allocator, fb_children.get(i)));
        }
    }
    return .{
        .name = if (fb_track.name()) |n| try allocator.dupe(u8, n) else "",
        .children = try children.toOwnedSlice(allocator),
        .markers = try fb_to_serializable_markers(allocator, fb_track.markers()),
    };
}

/// Convert FlatBuffers Stack to SerializableStack
fn fb_to_serializable_stack(
    allocator: Allocator,
    fb_stack: tlb.Stack,
) !serializable.SerializableStack
{
    var children: std.ArrayList(SerializableComposable) = .empty;
    if (fb_stack.children()) |fb_children| {
        try children.ensureTotalCapacity(allocator, fb_children.len());
        for (0..fb_children.len()) |i| {
            children.appendAssumeCapacity(try fb_to_serializable_composable(allocator, fb_children.get(i)));
        }
    }
    return .{
        .name = if (fb_stack.name()) |n| try allocator.dupe(u8, n) else "",
        .children = try children.toOwnedSlice(allocator),
        .markers = try fb_to_serializable_markers(allocator, fb_stack.markers()),
    };
}

/// Convert FlatBuffers Warp to SerializableWarp
fn fb_to_serializable_warp(
    allocator: Allocator,
    fb_warp: tlb.Warp,
) !serializable.SerializableWarp
{
    const child_ptr = try allocator.create(SerializableComposable);
    child_ptr.* = if (fb_warp.child()) |c|
        try fb_to_serializable_composable(allocator, c)
    else
        .{ .gap = .{ .name = "", .bounds_s = .{ 0.0, 0.0 } } };

    const transform = if (fb_warp.transform()) |t|
        try fb_to_serializable_topology(allocator, t)
    else
        serializable.SerializableTopology{ .mappings = &.{} };

    return .{
        .name = if (fb_warp.name()) |n| try allocator.dupe(u8, n) else "",
        .child = child_ptr,
        .transform = transform,
    };
}

/// Convert FlatBuffers Topology to SerializableTopology
fn fb_to_serializable_topology(
    allocator: Allocator,
    fb_topo: tlb.Topology,
) !serializable.SerializableTopology
{
    if (fb_topo.mappings()) |fb_mappings| {
        var mappings = try allocator.alloc(serializable.SerializableMapping, fb_mappings.len());
        for (0..fb_mappings.len()) |i| {
            mappings[i] = try fb_to_serializable_mapping(allocator, fb_mappings.get(i));
        }
        return .{ .mappings = mappings };
    }
    return .{ .mappings = &.{} };
}

/// Convert FlatBuffers MappingWrapper to SerializableMapping
fn fb_to_serializable_mapping(
    allocator: Allocator,
    fb_wrapper: tlb.MappingWrapper,
) !serializable.SerializableMapping
{
    return switch (fb_wrapper.mapping_type()) {
        .Affine => blk: {
            if (fb_wrapper.affine()) |aff| {
                if (aff.transform()) |xform| {
                    break :blk serializable.SerializableMapping{
                        .affine = .{
                            .input_bounds_val = .{ aff.input_bounds_start(), aff.input_bounds_end() },
                            .input_to_output_xform = .{
                                .offset = xform.offset,
                                .scale = xform.scale,
                            },
                        },
                    };
                }
            }
            break :blk .empty;
        },
        .Linear => blk: {
            if (fb_wrapper.linear()) |lin| {
                if (lin.knots()) |fb_knots| {
                    const knots = try allocator.alloc(serializable.SerializableControlPoint, fb_knots.len());
                    for (0..fb_knots.len()) |i| {
                        const k = fb_knots.get(i);
                        knots[i] = .{ k.in_val, k.out_val };
                    }
                    break :blk serializable.SerializableMapping{
                        .linear = .{
                            .input_bounds_val = .{ lin.input_bounds_start(), lin.input_bounds_end() },
                            .knots = knots,
                        },
                    };
                }
            }
            break :blk .empty;
        },
        .Empty => .empty,
    };
}

/// Convert FlatBuffers Transition to SerializableTransition
fn fb_to_serializable_transition(
    allocator: Allocator,
    fb_trans: tlb.Transition,
) !serializable.SerializableTransition
{
    // Deserialize container children if present
    const container = if (fb_trans.container()) |c|
        try fb_to_serializable_stack(allocator, c)
    else
        serializable.SerializableStack{ .name = "", .children = &.{} };

    return .{
        .name = if (fb_trans.name()) |n| try allocator.dupe(u8, n) else "",
        .container = container,
        .kind = try allocator.dupe(u8, fb_trans.kind()),
        .bounds_s = if (fb_trans.has_bounds())
            .{ fb_trans.bounds_start(), fb_trans.bounds_end() }
        else
            null,
    };
}

/// Convert FlatBuffers SampleIndexGenerator to SerializableSampleIndexGenerator
fn fb_to_serializable_sig(
    fb_sig: tlb.SampleIndexGenerator,
) serializable.SerializableSampleIndexGenerator
{
    return .{
        .sample_rate_hz = fb_to_serializable_rate(fb_sig.sample_rate_hz_type()),
        .start_index = fb_sig.start_index(),
    };
}

/// Convert FlatBuffers DiscretePartitionDomainMap to SerializableDiscretePartitionDomainMap
fn fb_to_serializable_discrete_partitions(
    fb_partitions: tlb.DiscretePartitionDomainMap,
) serializable.SerializableDiscretePartitionDomainMap
{
    return .{
        .picture = if (fb_partitions.picture()) |p| fb_to_serializable_sig(p) else null,
        .audio = if (fb_partitions.audio()) |a| fb_to_serializable_sig(a) else null,
    };
}

/// Convert FlatBuffers ComposableWrapper to SerializableComposable
fn fb_to_serializable_composable(
    allocator: Allocator,
    fb_wrapper: tlb.ComposableWrapper,
) anyerror!SerializableComposable
{
    return switch (fb_wrapper.comp_type()) {
        .Clip => .{ .clip = if (fb_wrapper.clip()) |c| try fb_to_serializable_clip(allocator, c) else .{
            .name = "",
            .bounds_s = null,
            .media = .{ .data_reference = .null, .bounds_s = null, .domain = .time, .discrete_partition = null },
            .metadata_hash = null,
        } },
        .Gap => .{ .gap = if (fb_wrapper.gap()) |g| try fb_to_serializable_gap(allocator, g) else .{
            .name = "",
            .bounds_s = .{ 0.0, 0.0 },
        } },
        .Track => .{ .track = if (fb_wrapper.track()) |t| try fb_to_serializable_track(allocator, t) else .{
            .name = "",
            .children = &.{},
        } },
        .Stack => .{ .stack = if (fb_wrapper.stack()) |s| try fb_to_serializable_stack(allocator, s) else .{
            .name = "",
            .children = &.{},
        } },
        .Warp => .{ .warp = if (fb_wrapper.warp()) |w| try fb_to_serializable_warp(allocator, w) else .{
            .name = "",
            .child = undefined,
            .transform = .{ .mappings = &.{} },
        } },
        .Transition => .{ .transition = if (fb_wrapper.transition()) |t| try fb_to_serializable_transition(allocator, t) else .{
            .name = "",
            .container = .{ .name = "", .children = &.{} },
            .kind = "",
            .bounds_s = null,
        } },
    };
}

// ----------------------------------------------------------------------------
// Timeline Serialization (SerializableTimeline -> FlatBuffers)
// ----------------------------------------------------------------------------

/// Serialize a SerializableTimeline to FlatBuffers format, preserving metadata.
/// This is the preferred method when you need to preserve metadata through
/// the binary format.
pub fn serialize_from_serializable_timeline(
    ser_timeline: SerializableTimeline,
    allocator: Allocator,
    writer: anytype,
) !void
{
    const enable_timing = build_options.enable_tlb_timing;
    var last_ts: u64 = if (enable_timing) std.c.mach_absolute_time() else 0;

    // Use arena allocator for all temporary allocations during serialization
    // This dramatically reduces allocation overhead
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    // Check if we have non-empty metadata
    const has_metadata = if (ser_timeline.metadata_map) |mm| mm.fields.count() > 0 else false;

    // ========================================================================
    // Phase 1: Build timeline structure FlatBuffer (without metadata_map)
    // ========================================================================
    var timeline_builder = try flatbuffers.Builder.init(arena_alloc);

    if (enable_timing) {
        std.debug.print("  [TLB] Builder init: {d:.3}ms\n", .{lap(&last_ts)});
    }

    // Convert children - pre-allocate exact capacity
    const children: ?[]tlb.ComposableWrapper = if (ser_timeline.children.len > 0) blk: {
        const c = try arena_alloc.alloc(tlb.ComposableWrapper, ser_timeline.children.len);
        for (ser_timeline.children, 0..)
            |child, i|
        {
            c[i] = try serializable_composable_to_fb(&timeline_builder, arena_alloc, child);
        }
        break :blk c;
    } else null;

    if (enable_timing) {
        std.debug.print("  [TLB] Children conversion: {d:.3}ms\n", .{lap(&last_ts)});
    }

    // Convert discrete partitions
    const discrete_partitions = try serializable_discrete_partitions_to_fb(
        &timeline_builder,
        ser_timeline.presentation_space_discrete_partitions,
    );

    // Build Timeline root WITHOUT metadata_map (it will be stored separately)
    const timeline_ref = try timeline_builder.writeTable(tlb.Timeline, .{
        .schema_version = ser_timeline.schema_version,
        .name = ser_timeline.name,
        .children = children,
        .presentation_space_discrete_partitions = discrete_partitions,
        .metadata_map = null, // Metadata stored separately for efficient skipping
    });

    try timeline_builder.writeRoot(tlb.Timeline, timeline_ref);
    const timeline_bytes = try timeline_builder.writeAlloc(arena_alloc);

    if (enable_timing) {
        std.debug.print("  [TLB] Timeline build: {d:.3}ms\n", .{lap(&last_ts)});
    }

    // ========================================================================
    // Phase 2: Build metadata FlatBuffer separately (if present)
    // ========================================================================
    var metadata_bytes: ?[]const u8 = null;
    if (has_metadata) {
        var metadata_builder = try flatbuffers.Builder.init(arena_alloc);
        const metadata_fb = try metadata_map_to_fb(&metadata_builder, arena_alloc, ser_timeline.metadata_map.?);
        if (metadata_fb)
            |mfb|
        {
            try metadata_builder.writeRoot(tlb.MetadataMap, mfb);
            metadata_bytes = try metadata_builder.writeAlloc(arena_alloc);
        }
    }

    if (enable_timing) {
        std.debug.print("  [TLB] Metadata conversion: {d:.3}ms\n", .{lap(&last_ts)});
    }

    // ========================================================================
    // Phase 3: Write header + timeline data + metadata data
    // ========================================================================
    // Calculate metadata_offset: position where metadata starts (after header + timeline)
    const metadata_offset: u64 = if (metadata_bytes != null)
        TLB_HEADER_SIZE + timeline_bytes.len
    else
        0; // No metadata

    // Write header with correct metadata_offset
    try write_header(writer, metadata_offset);

    // Write timeline structure
    try writer.writeAll(timeline_bytes);

    // Write metadata if present
    if (metadata_bytes)
        |mb|
    {
        try writer.writeAll(mb);
    }
}

// ----------------------------------------------------------------------------
// Timeline Deserialization (FlatBuffers -> SerializableTimeline)
// ----------------------------------------------------------------------------

/// Deserialize FlatBuffers data directly to SerializableTimeline, preserving
/// metadata. This is useful when you need to output to ziggy format while
/// preserving metadata.
///
/// When content_filter == .all_except_metadata, the metadata_map is not
/// parsed, providing significant performance gains for large files with
/// extensive metadata. The resulting SerializableTimeline will have
/// metadata_map = null.
///
/// The TLB format stores timeline structure and metadata in separate
/// FlatBuffer segments: - [0..16]: Header with metadata_offset -
/// [16..metadata_offset]: Timeline structure (without metadata_map) -
/// [metadata_offset..]: Metadata FlatBuffer (if metadata_offset > 0)
pub fn deserialize_to_serializable_timeline(
    allocator: Allocator,
    data: []const u8,
    content_filter: format_m.ReadOptions.ContentFilter,
) !SerializableTimeline
{
    const header = try read_header(data);

    const skip_metadata = content_filter == .all_except_metadata;

    // Determine timeline data range based on metadata_offset
    // If metadata_offset > TLB_HEADER_SIZE, metadata is stored separately
    const has_separate_metadata = header.metadata_offset > TLB_HEADER_SIZE and
        header.metadata_offset < data.len;

    // Timeline data: from header end to metadata start (or end of file)
    const timeline_end: usize = if (has_separate_metadata)
        @intCast(header.metadata_offset)
    else
        data.len;

    const fb_data = data[TLB_HEADER_SIZE..timeline_end];

    // FlatBuffers requires 8-byte alignment. Copy to aligned buffer if needed.
    const needs_timeline_copy = @intFromPtr(fb_data.ptr) % 8 != 0;
    const aligned_data: []align(8) const u8 = if (!needs_timeline_copy)
        @alignCast(fb_data)
    else blk: {
        const aligned_copy = try allocator.alignedAlloc(u8, .@"8", fb_data.len);
        @memcpy(aligned_copy, fb_data);
        break :blk aligned_copy;
    };
    defer if (needs_timeline_copy) allocator.free(@constCast(aligned_data));

    // Decode root Timeline
    const fb_timeline = try flatbuffers.decodeRoot(tlb.Timeline, aligned_data);

    // Convert children to SerializableComposable
    var children: std.ArrayList(SerializableComposable) = .empty;
    if (fb_timeline.children()) |fb_children| {
        try children.ensureTotalCapacity(allocator, fb_children.len());
        for (0..fb_children.len()) |i| {
            children.appendAssumeCapacity(try fb_to_serializable_composable(allocator, fb_children.get(i)));
        }
    }

    // Convert metadata if present and requested
    var metadata_map: ?MetadataMap = null;
    if (!skip_metadata) {
        // First check if metadata is embedded in timeline (legacy/inline format)
        if (fb_timeline.metadata_map()) |fb_metadata| {
            metadata_map = try fb_to_metadata_map_single_table(allocator, fb_metadata);
        }
        // Then check for separated metadata
        else if (has_separate_metadata) {
            const metadata_data = data[@intCast(header.metadata_offset)..];

            // FlatBuffers requires 8-byte alignment
            const needs_copy = @intFromPtr(metadata_data.ptr) % 8 != 0;
            const aligned_metadata: []align(8) const u8 = if (!needs_copy)
                @alignCast(metadata_data)
            else blk: {
                const aligned_copy = try allocator.alignedAlloc(u8, .@"8", metadata_data.len);
                @memcpy(aligned_copy, metadata_data);
                break :blk aligned_copy;
            };
            defer if (needs_copy) allocator.free(@constCast(aligned_metadata));

            const fb_metadata = try flatbuffers.decodeRoot(tlb.MetadataMap, aligned_metadata);
            metadata_map = try fb_to_metadata_map_single_table(allocator, fb_metadata);
        }
    }

    // Convert discrete partitions if present
    const discrete_partitions = if (fb_timeline.presentation_space_discrete_partitions()) |p|
        fb_to_serializable_discrete_partitions(p)
    else
        serializable.SerializableDiscretePartitionDomainMap{};

    return .{
        .schema_version = fb_timeline.schema_version(),
        .name = if (fb_timeline.name()) |n| try allocator.dupe(u8, n) else "",
        .children = try children.toOwnedSlice(allocator),
        .presentation_space_discrete_partitions = discrete_partitions,
        .metadata_map = metadata_map,
    };
}

// ----------------------------------------------------------------------------
// Collection Serialization/Deserialization
// ----------------------------------------------------------------------------

/// Collection file format constants - uses "TLCB" magic to distinguish from Timeline files
pub const TLCB_MAGIC: [4]u8 = .{ 'T', 'L', 'C', 'B' };

/// Write TLCB header (Collection binary format)
fn write_collection_header(
    writer: anytype,
    metadata_offset: u64,
) !void
{
    try writer.writeAll(&TLCB_MAGIC);
    try writer.writeInt(u32, TLB_FORMAT_VERSION, .big);
    try writer.writeInt(u64, metadata_offset, .big);
}

/// Read and validate TLCB header
fn read_collection_header(
    data: []const u8,
) !struct { version: u32, metadata_offset: u64 }
{
    if (data.len < TLB_HEADER_SIZE)
    {
        return error.InvalidData;
    }
    if (!std.mem.eql(u8, data[0..4], &TLCB_MAGIC))
    {
        return error.InvalidData;
    }
    const version = std.mem.readInt(u32, data[4..8], .big);
    const metadata_offset = std.mem.readInt(u64, data[8..16], .big);
    return .{ .version = version, .metadata_offset = metadata_offset };
}

/// Convert SerializableCollectionItem to FlatBuffers CollectionItemWrapper
fn serializable_collection_item_to_fb(
    builder: *flatbuffers.Builder,
    arena_alloc: Allocator,
    item: serializable.SerializableCollectionItem,
) !tlb.CollectionItemWrapper
{
    return switch (item) {
        .timeline => |tl| blk: {
            // Convert children
            const children: ?[]tlb.ComposableWrapper = if (tl.children.len > 0) child_blk: {
                const c = try arena_alloc.alloc(tlb.ComposableWrapper, tl.children.len);
                for (tl.children, 0..)
                    |child, i|
                {
                    c[i] = try serializable_composable_to_fb(builder, arena_alloc, child);
                }
                break :child_blk c;
            } else null;

            // Convert metadata
            var metadata_fb: ?tlb.MetadataMap = null;
            if (tl.metadata_map)
                |mm|
            {
                metadata_fb = try metadata_map_to_fb(builder, arena_alloc, mm);
            }

            // Convert discrete partitions
            const discrete_partitions = try serializable_discrete_partitions_to_fb(
                builder,
                tl.presentation_space_discrete_partitions,
            );

            // Convert markers
            const markers_fb = try serializable_markers_to_fb(builder, tl.markers);

            const timeline_ref = try builder.writeTable(tlb.Timeline, .{
                .schema_version = tl.schema_version,
                .name = tl.name,
                .children = children,
                .presentation_space_discrete_partitions = discrete_partitions,
                .metadata_map = metadata_fb,
                .markers = markers_fb,
            });

            break :blk try builder.writeTable(tlb.CollectionItemWrapper, .{
                .item_type = .TimelineItem,
                .timeline = timeline_ref,
            });
        },
        .track => |track| blk: {
            const children: ?[]tlb.ComposableWrapper = if (track.children.len > 0) child_blk: {
                const c = try arena_alloc.alloc(tlb.ComposableWrapper, track.children.len);
                for (track.children, 0..)
                    |child, i|
                {
                    c[i] = try serializable_composable_to_fb(builder, arena_alloc, child);
                }
                break :child_blk c;
            } else null;

            const markers_fb = try serializable_markers_to_fb(builder, track.markers);
            const bounds_fb = if (track.bounds_s) |b| try serializable_bounds_to_fb(builder, b) else null;

            const track_ref = try builder.writeTable(tlb.Track, .{
                .name = track.name,
                .bounds = bounds_fb,
                .children = children,
                .markers = markers_fb,
            });

            break :blk try builder.writeTable(tlb.CollectionItemWrapper, .{
                .item_type = .TrackItem,
                .track = track_ref,
            });
        },
        .stack => |stack| blk: {
            const children: ?[]tlb.ComposableWrapper = if (stack.children.len > 0) child_blk: {
                const c = try arena_alloc.alloc(tlb.ComposableWrapper, stack.children.len);
                for (stack.children, 0..)
                    |child, i|
                {
                    c[i] = try serializable_composable_to_fb(builder, arena_alloc, child);
                }
                break :child_blk c;
            } else null;

            const markers_fb = try serializable_markers_to_fb(builder, stack.markers);
            const bounds_fb = if (stack.bounds_s) |b| try serializable_bounds_to_fb(builder, b) else null;

            const stack_ref = try builder.writeTable(tlb.Stack, .{
                .name = stack.name,
                .bounds = bounds_fb,
                .children = children,
                .markers = markers_fb,
            });

            break :blk try builder.writeTable(tlb.CollectionItemWrapper, .{
                .item_type = .StackItem,
                .stack = stack_ref,
            });
        },
        .clip => |clip| blk: {
            const media_fb = try serializable_media_ref_to_fb(builder, arena_alloc, clip.media);
            const bounds_fb = if (clip.bounds_s) |b| try serializable_bounds_to_fb(builder, b) else null;
            const markers_fb = try serializable_markers_to_fb(builder, clip.markers);

            // Convert hex string to u64 for binary storage
            const hash_val: u64 = if (clip.metadata_hash) |h|
                serializable.hex_string_to_hash(h) orelse 0
            else
                0;

            const clip_ref = try builder.writeTable(tlb.Clip, .{
                .name = clip.name,
                .bounds = bounds_fb,
                .media = media_fb,
                .metadata_hash = hash_val,
                .markers = markers_fb,
            });

            break :blk try builder.writeTable(tlb.CollectionItemWrapper, .{
                .item_type = .ClipItem,
                .clip = clip_ref,
            });
        },
        .gap => |gap| blk: {
            const markers_fb = try serializable_markers_to_fb(builder, gap.markers);

            const gap_ref = try builder.writeTable(tlb.Gap, .{
                .name = gap.name,
                .bounds_start = gap.bounds_s[0],
                .bounds_end = gap.bounds_s[1],
                .markers = markers_fb,
            });

            break :blk try builder.writeTable(tlb.CollectionItemWrapper, .{
                .item_type = .GapItem,
                .gap = gap_ref,
            });
        },
        .warp => |warp| blk: {
            const child_wrapper = try serializable_composable_to_fb(builder, arena_alloc, warp.child.*);
            const topology_fb = try serializable_topology_to_fb(builder, arena_alloc, warp.transform);

            const warp_ref = try builder.writeTable(tlb.Warp, .{
                .name = warp.name,
                .child = child_wrapper,
                .transform = topology_fb,
            });

            break :blk try builder.writeTable(tlb.CollectionItemWrapper, .{
                .item_type = .WarpItem,
                .warp = warp_ref,
            });
        },
        .transition => |trans| blk: {
            // Convert container stack
            const container_children: ?[]tlb.ComposableWrapper = if (trans.container.children.len > 0) child_blk: {
                const c = try arena_alloc.alloc(tlb.ComposableWrapper, trans.container.children.len);
                for (trans.container.children, 0..)
                    |child, i|
                {
                    c[i] = try serializable_composable_to_fb(builder, arena_alloc, child);
                }
                break :child_blk c;
            } else null;

            const container_bounds_fb = if (trans.container.bounds_s) |b| try serializable_bounds_to_fb(builder, b) else null;
            const container_markers_fb = try serializable_markers_to_fb(builder, trans.container.markers);

            const container_ref = try builder.writeTable(tlb.Stack, .{
                .name = trans.container.name,
                .bounds = container_bounds_fb,
                .children = container_children,
                .markers = container_markers_fb,
            });

            const trans_ref = try builder.writeTable(tlb.Transition, .{
                .name = trans.name,
                .container = container_ref,
                .kind = trans.kind,
                .bounds_start = if (trans.bounds_s) |b| b[0] else 0.0,
                .bounds_end = if (trans.bounds_s) |b| b[1] else 0.0,
                .has_bounds = trans.bounds_s != null,
            });

            break :blk try builder.writeTable(tlb.CollectionItemWrapper, .{
                .item_type = .TransitionItem,
                .transition = trans_ref,
            });
        },
    };
}

/// Convert FlatBuffers CollectionItemWrapper to SerializableCollectionItem
fn fb_to_serializable_collection_item(
    allocator: Allocator,
    wrapper: tlb.CollectionItemWrapper,
) !serializable.SerializableCollectionItem
{
    return switch (wrapper.item_type()) {
        .TimelineItem => blk: {
            const fb_tl = wrapper.timeline() orelse return error.InvalidData;

            // Convert children
            var children: std.ArrayList(serializable.SerializableComposable) = .empty;
            if (fb_tl.children()) |fb_children| {
                try children.ensureTotalCapacity(allocator, fb_children.len());
                for (0..fb_children.len()) |i| {
                    children.appendAssumeCapacity(try fb_to_serializable_composable(allocator, fb_children.get(i)));
                }
            }

            // Convert metadata
            var metadata_map: ?MetadataMap = null;
            if (fb_tl.metadata_map()) |fb_metadata| {
                metadata_map = try fb_to_metadata_map_single_table(allocator, fb_metadata);
            }

            // Convert discrete partitions
            const discrete_partitions = if (fb_tl.presentation_space_discrete_partitions()) |p|
                fb_to_serializable_discrete_partitions(p)
            else
                serializable.SerializableDiscretePartitionDomainMap{};

            // Convert markers
            const markers = try fb_to_serializable_markers(allocator, fb_tl.markers());

            break :blk .{
                .timeline = .{
                    .schema_version = fb_tl.schema_version(),
                    .name = if (fb_tl.name()) |n| try allocator.dupe(u8, n) else "",
                    .children = try children.toOwnedSlice(allocator),
                    .presentation_space_discrete_partitions = discrete_partitions,
                    .metadata_map = metadata_map,
                    .markers = markers,
                },
            };
        },
        .TrackItem => blk: {
            const fb_track = wrapper.track() orelse return error.InvalidData;

            var children: std.ArrayList(serializable.SerializableComposable) = .empty;
            if (fb_track.children()) |fb_children| {
                try children.ensureTotalCapacity(allocator, fb_children.len());
                for (0..fb_children.len()) |i| {
                    children.appendAssumeCapacity(try fb_to_serializable_composable(allocator, fb_children.get(i)));
                }
            }

            const markers = try fb_to_serializable_markers(allocator, fb_track.markers());

            break :blk .{
                .track = .{
                    .name = if (fb_track.name()) |n| try allocator.dupe(u8, n) else "",
                    .bounds_s = if (fb_track.bounds()) |b| fb_to_serializable_bounds(b) else null,
                    .children = try children.toOwnedSlice(allocator),
                    .markers = markers,
                },
            };
        },
        .StackItem => blk: {
            const fb_stack = wrapper.stack() orelse return error.InvalidData;

            var children: std.ArrayList(serializable.SerializableComposable) = .empty;
            if (fb_stack.children()) |fb_children| {
                try children.ensureTotalCapacity(allocator, fb_children.len());
                for (0..fb_children.len()) |i| {
                    children.appendAssumeCapacity(try fb_to_serializable_composable(allocator, fb_children.get(i)));
                }
            }

            const markers = try fb_to_serializable_markers(allocator, fb_stack.markers());

            break :blk .{
                .stack = .{
                    .name = if (fb_stack.name()) |n| try allocator.dupe(u8, n) else "",
                    .bounds_s = if (fb_stack.bounds()) |b| fb_to_serializable_bounds(b) else null,
                    .children = try children.toOwnedSlice(allocator),
                    .markers = markers,
                },
            };
        },
        .ClipItem => blk: {
            const fb_clip = wrapper.clip() orelse return error.InvalidData;
            const markers = try fb_to_serializable_markers(allocator, fb_clip.markers());
            const fb_media = fb_clip.media() orelse return error.InvalidData;
            const hash_val = fb_clip.metadata_hash();
            // Convert u64 back to hex string
            const hash_str: ?[]const u8 = if (hash_val != 0)
                try serializable.hash_to_hex_string(allocator, hash_val)
            else
                null;

            break :blk .{
                .clip = .{
                    .name = if (fb_clip.name()) |n| try allocator.dupe(u8, n) else "",
                    .bounds_s = if (fb_clip.bounds()) |b| fb_to_serializable_bounds(b) else null,
                    .media = try fb_to_serializable_media_ref(allocator, fb_media),
                    .metadata_hash = hash_str,
                    .markers = markers,
                },
            };
        },
        .GapItem => blk: {
            const fb_gap = wrapper.gap() orelse return error.InvalidData;
            const markers = try fb_to_serializable_markers(allocator, fb_gap.markers());

            break :blk .{
                .gap = .{
                    .name = if (fb_gap.name()) |n| try allocator.dupe(u8, n) else "",
                    .bounds_s = .{ fb_gap.bounds_start(), fb_gap.bounds_end() },
                    .markers = markers,
                },
            };
        },
        .WarpItem => blk: {
            const fb_warp = wrapper.warp() orelse return error.InvalidData;

            // Convert child composable
            const child_wrapper = fb_warp.child() orelse return error.InvalidData;
            const child_composable = try allocator.create(serializable.SerializableComposable);
            child_composable.* = try fb_to_serializable_composable(allocator, child_wrapper);

            // Convert topology
            const fb_topo = fb_warp.transform() orelse return error.InvalidData;

            break :blk .{
                .warp = .{
                    .name = if (fb_warp.name()) |n| try allocator.dupe(u8, n) else "",
                    .child = child_composable,
                    .transform = try fb_to_serializable_topology(allocator, fb_topo),
                },
            };
        },
        .TransitionItem => blk: {
            const fb_trans = wrapper.transition() orelse return error.InvalidData;

            // Convert container
            const fb_container = fb_trans.container() orelse return error.InvalidData;

            var container_children: std.ArrayList(serializable.SerializableComposable) = .empty;
            if (fb_container.children()) |fb_children| {
                try container_children.ensureTotalCapacity(allocator, fb_children.len());
                for (0..fb_children.len()) |i| {
                    container_children.appendAssumeCapacity(try fb_to_serializable_composable(allocator, fb_children.get(i)));
                }
            }

            const container_markers = try fb_to_serializable_markers(allocator, fb_container.markers());

            break :blk .{
                .transition = .{
                    .name = if (fb_trans.name()) |n| try allocator.dupe(u8, n) else "",
                    .container = .{
                        .name = if (fb_container.name()) |n| try allocator.dupe(u8, n) else "",
                        .bounds_s = if (fb_container.bounds()) |b| fb_to_serializable_bounds(b) else null,
                        .children = try container_children.toOwnedSlice(allocator),
                        .markers = container_markers,
                    },
                    .kind = try allocator.dupe(u8, fb_trans.kind()),
                    .bounds_s = if (fb_trans.has_bounds())
                        .{ fb_trans.bounds_start(), fb_trans.bounds_end() }
                    else
                        null,
                },
            };
        },
    };
}

/// Serialize a SerializableCollection to FlatBuffers format (.tlcb).
pub fn serialize_collection(
    collection: serializable.SerializableCollection,
    allocator: Allocator,
    writer: anytype,
) !void
{
    // Use arena allocator for all temporary allocations during serialization
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    var builder = try flatbuffers.Builder.init(arena_alloc);

    // Convert children
    const children: ?[]tlb.CollectionItemWrapper = if (collection.children.len > 0) blk: {
        const c = try arena_alloc.alloc(tlb.CollectionItemWrapper, collection.children.len);
        for (collection.children, 0..)
            |child, i|
        {
            c[i] = try serializable_collection_item_to_fb(&builder, arena_alloc, child);
        }
        break :blk c;
    } else null;

    // Convert metadata if present
    var metadata_fb: ?tlb.MetadataMap = null;
    if (collection.metadata_map)
        |mm|
    {
        metadata_fb = try metadata_map_to_fb(&builder, arena_alloc, mm);
    }

    // Build Collection root
    const collection_ref = try builder.writeTable(tlb.Collection, .{
        .schema_version = collection.schema_version,
        .name = collection.name,
        .description = collection.description,
        .children = children,
        .metadata_map = metadata_fb,
    });

    try builder.writeRoot(tlb.Collection, collection_ref);

    // Write TLCB header
    try write_collection_header(writer, 0);

    // Get FlatBuffers data and write
    const fb_bytes = try builder.writeAlloc(arena_alloc);
    try writer.writeAll(fb_bytes);
}

/// Deserialize FlatBuffers data (.tlcb) to SerializableCollection.
pub fn deserialize_collection(
    allocator: Allocator,
    data: []const u8,
) !serializable.SerializableCollection
{
    _ = try read_collection_header(data);

    // Get FlatBuffers data after header
    const fb_data = data[TLB_HEADER_SIZE..];

    // FlatBuffers requires 8-byte alignment. Copy to aligned buffer if needed.
    const needs_copy = @intFromPtr(fb_data.ptr) % 8 != 0;
    const aligned_data: []align(8) const u8 = if (!needs_copy)
        @alignCast(fb_data)
    else blk: {
        const aligned_copy = try allocator.alignedAlloc(u8, .@"8", fb_data.len);
        @memcpy(aligned_copy, fb_data);
        break :blk aligned_copy;
    };
    defer if (needs_copy) allocator.free(@constCast(aligned_data));

    // Decode root Collection
    const fb_collection = try flatbuffers.decodeRoot(tlb.Collection, aligned_data);

    // Convert children to SerializableCollectionItem
    var children: std.ArrayList(serializable.SerializableCollectionItem) = .empty;
    if (fb_collection.children()) |fb_children| {
        try children.ensureTotalCapacity(allocator, fb_children.len());
        for (0..fb_children.len()) |i| {
            children.appendAssumeCapacity(try fb_to_serializable_collection_item(allocator, fb_children.get(i)));
        }
    }

    // Convert metadata if present
    var metadata_map: ?MetadataMap = null;
    if (fb_collection.metadata_map()) |fb_metadata| {
        metadata_map = try fb_to_metadata_map_single_table(allocator, fb_metadata);
    }

    return .{
        .schema_version = fb_collection.schema_version(),
        .name = if (fb_collection.name()) |n| try allocator.dupe(u8, n) else "",
        .description = if (fb_collection.description()) |d| try allocator.dupe(u8, d) else "",
        .children = try children.toOwnedSlice(allocator),
        .metadata_map = metadata_map,
    };
}

// ----------------------------------------------------------------------------
// Tests
// ----------------------------------------------------------------------------

test "header: write and read round-trip"
{
    var buffer: [TLB_HEADER_SIZE]u8 = undefined;
    var stream: std.Io.Writer = .fixed(&buffer);
    const test_offset: u64 = 12345;
    try write_header(&stream, test_offset);
    const header = try read_header(&buffer);
    try std.testing.expectEqual(TLB_FORMAT_VERSION, header.version);
    try std.testing.expectEqual(test_offset, header.metadata_offset);
}

test "header: invalid magic number"
{
    const bad_data = [_]u8{ 'B', 'A', 'D', '!', 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0 };
    try std.testing.expectError(error.InvalidData, read_header(&bad_data));
}

test "flatbufs: direct flatbuffers roundtrip"
{
    const allocator = std.testing.allocator;

    // Build FlatBuffers data directly
    var builder = try flatbuffers.Builder.init(allocator);
    defer builder.deinit();

    // Create a gap wrapper
    const gap_ref = try builder.writeTable(tlb.Gap, .{
        .name = "Test Gap",
        .bounds_start = 0.0,
        .bounds_end = 5.0,
    });

    const gap_wrapper = try builder.writeTable(tlb.ComposableWrapper, .{
        .comp_type = .Gap,
        .gap = gap_ref,
    });

    // Create timeline with the gap as a child
    const timeline_ref = try builder.writeTable(tlb.Timeline, .{
        .schema_version = 1,
        .name = "Test Timeline",
        .children = &[_]tlb.ComposableWrapper{gap_wrapper},
    });

    try builder.writeRoot(tlb.Timeline, timeline_ref);

    // Get FlatBuffers data
    const fb_bytes = try builder.writeAlloc(allocator);
    defer allocator.free(fb_bytes);

    // Write header + FlatBuffers data to buffer
    var buffer: std.Io.Writer.Allocating = .init(allocator);
    defer buffer.deinit();
    try write_header(&buffer.writer, 0);
    try buffer.writer.writeAll(fb_bytes);

    // Verify header
    const header = try read_header(buffer.written());
    try std.testing.expectEqual(TLB_FORMAT_VERSION, header.version);

    // Decode
    const fb_data = buffer.written()[TLB_HEADER_SIZE..];
    const aligned_data: []align(8) const u8 = @alignCast(fb_data);
    const fb_timeline = try flatbuffers.decodeRoot(tlb.Timeline, aligned_data);

    // Verify timeline
    try std.testing.expectEqualStrings("Test Timeline", fb_timeline.name().?);
    try std.testing.expectEqual(@as(u32, 1), fb_timeline.schema_version());

    // Verify children
    const children = fb_timeline.children().?;
    try std.testing.expectEqual(@as(usize, 1), children.len());

    // Verify gap
    const child = children.get(0);
    try std.testing.expectEqual(tlb.ComposableType.Gap, child.comp_type());
    const gap_val = child.gap().?;
    try std.testing.expectEqualStrings("Test Gap", gap_val.name().?);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), gap_val.bounds_start(), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 5.0), gap_val.bounds_end(), 0.001);
}

// ============================================================================
// Metadata Separation Tests
// ============================================================================

test "tlb: metadata_offset written correctly when metadata present"
{
    const allocator = std.testing.allocator;

    // Create a simple metadata map
    var metadata: MetadataMap = .empty;
    defer metadata.fields.deinit(allocator);
    var inner: MetadataMap = .empty;
    defer inner.fields.deinit(allocator);
    try inner.fields.put(allocator, "test_key", .{ .bytes = "test_value" });
    try inner.fields.put(allocator, "number", .{ .integer = 42 });
    try metadata.fields.put(allocator, "test_hash", .{ .kv = inner });

    // Create timeline with metadata
    const timeline = SerializableTimeline{
        .schema_version = 1,
        .name = "Test Timeline",
        .children = &.{},
        .metadata_map = metadata,
        .presentation_space_discrete_partitions = .{},
    };

    // Serialize
    var buffer: std.Io.Writer.Allocating = .init(allocator);
    defer buffer.deinit();
    try serialize_from_serializable_timeline(timeline, allocator, &buffer.writer);

    // Read header and verify metadata_offset is non-zero
    const header = try read_header(buffer.written());
    try std.testing.expect(header.metadata_offset > TLB_HEADER_SIZE);
    try std.testing.expect(header.metadata_offset < buffer.written().len);
}

test "tlb: metadata_offset is 0 when no metadata"
{
    const allocator = std.testing.allocator;

    // Create timeline without metadata
    const timeline = SerializableTimeline{
        .schema_version = 1,
        .name = "No Metadata Timeline",
        .children = &.{},
        .metadata_map = null,
        .presentation_space_discrete_partitions = .{},
    };

    // Serialize
    var buffer: std.Io.Writer.Allocating = .init(allocator);
    defer buffer.deinit();
    try serialize_from_serializable_timeline(timeline, allocator, &buffer.writer);

    // Read header and verify metadata_offset is 0
    const header = try read_header(buffer.written());
    try std.testing.expectEqual(@as(u64, 0), header.metadata_offset);
}

test "tlb: round-trip with metadata preserved"
{
    const allocator = std.testing.allocator;

    // Create metadata map with various types
    var metadata: MetadataMap = .empty;
    defer metadata.fields.deinit(allocator);
    var inner: MetadataMap = .empty;
    defer inner.fields.deinit(allocator);
    try inner.fields.put(allocator, "string_val", .{ .bytes = "test string" });
    try inner.fields.put(allocator, "int_val", .{ .integer = 42 });
    try inner.fields.put(allocator, "float_val", .{ .float = 3.14159 });
    try inner.fields.put(allocator, "bool_val", .{ .bool = true });
    try metadata.fields.put(allocator, "test_hash", .{ .kv = inner });

    // Create timeline with metadata
    const timeline = SerializableTimeline{
        .schema_version = 1,
        .name = "Test Timeline",
        .children = &.{},
        .metadata_map = metadata,
        .presentation_space_discrete_partitions = .{},
    };

    // Serialize
    var buffer: std.Io.Writer.Allocating = .init(allocator);
    defer buffer.deinit();
    try serialize_from_serializable_timeline(timeline, allocator, &buffer.writer);

    // Deserialize with metadata
    var deserialized = try deserialize_to_serializable_timeline(
        allocator,
        buffer.written(),
        .all,
    );
    defer deserialized.deinit(allocator);

    // Verify metadata preserved
    try std.testing.expect(deserialized.metadata_map != null);
    const result_meta = deserialized.metadata_map.?;
    const result_hash = result_meta.fields.get("test_hash").?;
    try std.testing.expect(result_hash == .kv);
    const result_kv = result_hash.kv;
    try std.testing.expectEqualStrings("test string", result_kv.fields.get("string_val").?.bytes);
    try std.testing.expectEqual(@as(i64, 42), result_kv.fields.get("int_val").?.integer);
    try std.testing.expectApproxEqAbs(@as(f64, 3.14159), result_kv.fields.get("float_val").?.float, 0.00001);
    try std.testing.expectEqual(true, result_kv.fields.get("bool_val").?.bool);
}

test "tlb: round-trip without metadata (skip on read)"
{
    const allocator = std.testing.allocator;

    // Create metadata map
    var metadata: MetadataMap = .empty;
    defer metadata.fields.deinit(allocator);
    var inner: MetadataMap = .empty;
    defer inner.fields.deinit(allocator);
    try inner.fields.put(allocator, "key", .{ .bytes = "value" });
    try metadata.fields.put(allocator, "test_hash", .{ .kv = inner });

    // Create timeline with metadata
    const timeline = SerializableTimeline{
        .schema_version = 1,
        .name = "Test Timeline",
        .children = &.{},
        .metadata_map = metadata,
        .presentation_space_discrete_partitions = .{},
    };

    // Serialize with metadata
    var buffer: std.Io.Writer.Allocating = .init(allocator);
    defer buffer.deinit();
    try serialize_from_serializable_timeline(timeline, allocator, &buffer.writer);

    // Deserialize WITHOUT metadata
    var deserialized = try deserialize_to_serializable_timeline(
        allocator,
        buffer.written(),
        .all_except_metadata,
    );
    defer deserialized.deinit(allocator);

    // Verify metadata is null but structure preserved
    try std.testing.expect(deserialized.metadata_map == null);
    try std.testing.expectEqualStrings("Test Timeline", deserialized.name);
    try std.testing.expectEqual(@as(usize, 0), deserialized.children.len);
}

test "tlb: empty metadata_map serialization"
{
    const allocator = std.testing.allocator;

    // Create timeline with empty metadata map
    const empty_map: MetadataMap = .empty;

    const timeline = SerializableTimeline{
        .schema_version = 1,
        .name = "Empty Metadata",
        .children = &.{},
        .metadata_map = empty_map,
        .presentation_space_discrete_partitions = .{},
    };

    // Serialize
    var buffer: std.Io.Writer.Allocating = .init(allocator);
    defer buffer.deinit();
    try serialize_from_serializable_timeline(timeline, allocator, &buffer.writer);

    // Empty metadata map should result in metadata_offset = 0 (treated as no metadata)
    const header = try read_header(buffer.written());
    try std.testing.expectEqual(@as(u64, 0), header.metadata_offset);
}

test "tlb: large metadata handling"
{
    const allocator = std.testing.allocator;

    // Create metadata map with many entries
    var metadata: MetadataMap = .empty;
    defer metadata.fields.deinit(allocator);
    var inner: MetadataMap = .empty;
    // Note: We need to free the dynamically allocated keys as well as the hashmap
    defer {
        var iter = inner.fields.iterator();
        while (iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
        }
        inner.fields.deinit(allocator);
    }

    // Add 100 entries
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        var key_buf: [32]u8 = undefined;
        const key_slice = std.fmt.bufPrint(&key_buf, "key_{d}", .{i}) catch unreachable;
        const key = try allocator.dupe(u8, key_slice);
        try inner.fields.put(allocator, key, .{ .integer = @intCast(i) });
    }
    try metadata.fields.put(allocator, "large_hash", .{ .kv = inner });

    const timeline = SerializableTimeline{
        .schema_version = 1,
        .name = "Large Metadata",
        .children = &.{},
        .metadata_map = metadata,
        .presentation_space_discrete_partitions = .{},
    };

    // Serialize
    var buffer: std.Io.Writer.Allocating = .init(allocator);
    defer buffer.deinit();
    try serialize_from_serializable_timeline(timeline, allocator, &buffer.writer);

    // Round-trip verification
    var result = try deserialize_to_serializable_timeline(allocator, buffer.written(), .all);
    defer result.deinit(allocator);

    try std.testing.expect(result.metadata_map != null);
    const result_hash = result.metadata_map.?.fields.get("large_hash").?;
    try std.testing.expectEqual(@as(usize, 100), result_hash.kv.fields.count());
}

test "tlb: complex nested metadata round-trip"
{
    const allocator = std.testing.allocator;

    // Create metadata with nested structures
    var metadata: MetadataMap = .empty;
    defer metadata.fields.deinit(allocator);
    var inner: MetadataMap = .empty;
    defer inner.fields.deinit(allocator);

    // Add nested KV
    var nested_kv: MetadataMap = .empty;
    defer nested_kv.fields.deinit(allocator);
    try nested_kv.fields.put(allocator, "inner_key", .{ .bytes = "inner_value" });
    try inner.fields.put(allocator, "nested_val", .{ .kv = nested_kv });

    // Add array
    const array_items = try allocator.alloc(MetadataValue, 3);
    defer allocator.free(array_items);
    array_items[0] = .{ .integer = 1 };
    array_items[1] = .{ .integer = 2 };
    array_items[2] = .{ .integer = 3 };
    try inner.fields.put(allocator, "array_val", .{ .array = array_items });

    try metadata.fields.put(allocator, "complex_hash", .{ .kv = inner });

    const timeline = SerializableTimeline{
        .schema_version = 1,
        .name = "Complex Metadata",
        .children = &.{},
        .metadata_map = metadata,
        .presentation_space_discrete_partitions = .{},
    };

    // Serialize and round-trip
    var buffer: std.Io.Writer.Allocating = .init(allocator);
    defer buffer.deinit();
    try serialize_from_serializable_timeline(timeline, allocator, &buffer.writer);

    var result = try deserialize_to_serializable_timeline(allocator, buffer.written(), .all);
    defer result.deinit(allocator);

    // Verify nested structure
    const rm = result.metadata_map.?;
    const result_hash = rm.fields.get("complex_hash").?.kv;

    // Check nested KV
    const nested = result_hash.fields.get("nested_val").?.kv;
    try std.testing.expectEqualStrings("inner_value", nested.fields.get("inner_key").?.bytes);

    // Check array
    const arr = result_hash.fields.get("array_val").?.array;
    try std.testing.expectEqual(@as(usize, 3), arr.len);
    try std.testing.expectEqual(@as(i64, 1), arr[0].integer);
    try std.testing.expectEqual(@as(i64, 2), arr[1].integer);
    try std.testing.expectEqual(@as(i64, 3), arr[2].integer);
}

test "tlb: metadata offset points to correct boundary"
{
    const allocator = std.testing.allocator;

    // Create timeline with metadata
    var metadata: MetadataMap = .empty;
    defer metadata.fields.deinit(allocator);
    var inner: MetadataMap = .empty;
    defer inner.fields.deinit(allocator);
    try inner.fields.put(allocator, "key", .{ .bytes = "value" });
    try metadata.fields.put(allocator, "hash", .{ .kv = inner });

    const timeline = SerializableTimeline{
        .schema_version = 1,
        .name = "Test",
        .children = &.{},
        .metadata_map = metadata,
        .presentation_space_discrete_partitions = .{},
    };

    // Serialize
    var buffer: std.Io.Writer.Allocating = .init(allocator);
    defer buffer.deinit();
    try serialize_from_serializable_timeline(timeline, allocator, &buffer.writer);

    const header = try read_header(buffer.written());

    // Verify: timeline data ends at metadata_offset, metadata starts there
    // metadata_offset should be > TLB_HEADER_SIZE (16) and < total buffer length
    try std.testing.expect(header.metadata_offset > TLB_HEADER_SIZE);
    try std.testing.expect(header.metadata_offset < buffer.written().len);

    // The data at metadata_offset should be valid FlatBuffers metadata
    // We can verify by attempting to decode the timeline portion only
    const timeline_data = buffer.written()[TLB_HEADER_SIZE..header.metadata_offset];
    const aligned_timeline: []align(8) const u8 = if (@intFromPtr(timeline_data.ptr) % 8 == 0)
        @alignCast(timeline_data)
    else blk: {
        const aligned_copy = try allocator.alignedAlloc(u8, .@"8", timeline_data.len);
        @memcpy(aligned_copy, timeline_data);
        break :blk aligned_copy;
    };
    defer if (@intFromPtr(timeline_data.ptr) % 8 != 0) allocator.free(@constCast(aligned_timeline));

    // Should be able to decode timeline without metadata
    const fb_timeline = try flatbuffers.decodeRoot(tlb.Timeline, aligned_timeline);
    try std.testing.expectEqualStrings("Test", fb_timeline.name().?);
    // Timeline portion should have null metadata_map (it's stored separately)
    try std.testing.expect(fb_timeline.metadata_map() == null);
}

// ============================================================================
// Roundtrip Tests - verify TLA -> TLB -> TLA preserves all data
// ============================================================================

/// Test helper: encode a SerializableTimeline as TLA text (owned).
fn test_tla_text(
    allocator: Allocator,
    timeline: serializable.SerializableTimeline,
) ![]u8
{
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    try ascii.TimelineCodec.write(allocator, timeline, &out.writer, .{});
    return try out.toOwnedSlice();
}

/// Test helper: read a TLA file as a SerializableTimeline.
fn test_read_tla_file(
    allocator: Allocator,
    io: std.Io,
    path: []const u8,
) !serializable.SerializableTimeline
{
    const bytes = try std.Io.Dir.cwd().readFileAlloc(
        io,
        path,
        allocator,
        .unlimited,
    );
    defer allocator.free(bytes);
    var reader: std.Io.Reader = .fixed(bytes);
    return try ascii.TimelineCodec.read(allocator, &reader, .{});
}

/// Helper to run a single roundtrip test given file paths
fn run_roundtrip_test_from_paths(
    allocator: Allocator,
    io: std.Io,
    tla_path: []const u8,
    tlb_path: []const u8,
) !bool
{
    // Read and parse the TLA file
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const timeline_from_tla = try test_read_tla_file(
        arena.allocator(),
        io,
        tla_path,
    );

    // Serialize TLA timeline to TLA string (normalized)
    const tla_output = try test_tla_text(
        allocator,
        timeline_from_tla,
    );
    defer allocator.free(tla_output);

    // Read the TLB file and deserialize to SerializableTimeline
    const tlb_content = std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        tlb_path,
        allocator,
        .unlimited,
    ) catch |err| {
        test_print("Failed to read {s}: {}\n", .{ tlb_path, err });
        return err;
    };
    defer allocator.free(tlb_content);

    var timeline_from_tlb = try deserialize_to_serializable_timeline(
        allocator,
        tlb_content,
        .all,
    );
    defer timeline_from_tlb.deinit(allocator);

    // Serialize TLB timeline to TLA string
    const tlb_output = try test_tla_text(
        allocator,
        timeline_from_tlb,
    );
    defer allocator.free(tlb_output);

    // Compare the outputs
    return std.mem.eql(u8, tla_output, tlb_output);
}

/// Collect and run all roundtrip tests from a directory
fn run_roundtrip_tests_from_dir(
    allocator: Allocator,
    io: std.Io,
    dir_path: []const u8,
    passed: *usize,
    failed: *usize,
) !void
{
    var dir = std.Io.Dir.cwd().openDir(
        std.testing.io,
        dir_path,
        .{ .iterate = true },
    ) catch |err|
    {
        if (err == error.FileNotFound)
        {
            test_print("  Directory not found: {s}\n", .{dir_path});
            return;
        }
        return err;
    };
    defer dir.close(std.testing.io);

    // Collect .tla files
    var tla_files: std.ArrayList([]const u8) = .empty;
    defer {
        for (tla_files.items) |f| allocator.free(f);
        tla_files.deinit(allocator);
    }

    var iter = dir.iterate();
    while (try iter.next(std.testing.io))
        |entry|
    {
        if (entry.kind != .file) 
        {
            continue;
        }

        if (std.mem.endsWith(u8, entry.name, ".tla")) 
        {
            try tla_files.append(
                allocator,
                try allocator.dupe(u8, entry.name),
            );
        }
    }

    // Sort for consistent ordering
    std.mem.sort(
        []const u8,
        tla_files.items,
        {},
        struct {
            fn less_than(
                _: void,
                a: []const u8,
                b: []const u8,
            ) bool
            {
                return std.mem.lessThan(u8, a, b);
            }
        }.less_than,
    );

    // Run tests
    for (tla_files.items) 
        |tla_name| 
    {
        errdefer std.log.err("Error with file: {s}", .{tla_name});
        const basename = tla_name[0 .. tla_name.len - 4];
        const tlb_name = try std.fmt.allocPrint(
            allocator,
            "{s}.tlb",
            .{basename},
        );
        defer allocator.free(tlb_name);

        // Check if corresponding .tlb exists
        dir.access(io, tlb_name, .{}) catch continue;

        // Build full paths
        const tla_path = try std.fs.path.join(
            allocator,
            &.{ dir_path, tla_name },
        );
        defer allocator.free(tla_path);
        const tlb_path = try std.fs.path.join(
            allocator,
            &.{ dir_path, tlb_name },
        );
        defer allocator.free(tlb_path);

        // Run the test
        const test_passed = run_roundtrip_test_from_paths(
            allocator,
            io,
            tla_path,
            tlb_path,
        ) catch |err| {
            test_print("  {s}... ERROR: {}\n", .{ basename, err });
            failed.* += 1;
            continue;
        };

        if (test_passed) {
            test_print("  {s}... OK\n", .{basename});
            passed.* += 1;
        } else {
            test_print("  {s}... MISMATCH\n", .{basename});
            failed.* += 1;
        }
    }
}

test "ascii: parse just_clip.tla and deinit (leak test)"
{
    const io = std.testing.io;

    // Skip if file doesn't exist
    std.Io.Dir.cwd().access(std.testing.io, "test_files/just_clip.tla", .{}) catch {
        test_print("Skipping: test_files/just_clip.tla not found\n", .{});
        return;
    };

    // Use arena because ziggy.deserializeLeaky returns data referencing the source buffer
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    // Read and parse TLA file
    const timeline = try test_read_tla_file(
        arena.allocator(),
        io,
        "test_files/just_clip.tla",
    );

    // Basic sanity check
    try std.testing.expectEqualStrings("Clip-001", timeline.name);
}

test "binary: deserialize just_warp.tlb and deinit (leak test)"
{
    const allocator = std.testing.allocator;

    // Skip if file doesn't exist
    std.Io.Dir.cwd().access(std.testing.io, "test_files/just_warp.tlb", .{}) catch {
        test_print("Skipping: test_files/just_warp.tlb not found\n", .{});
        return;
    };

    // Read TLB file
    const tlb_content = try std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        "test_files/just_warp.tlb",
        allocator,
        .unlimited,
    );
    defer allocator.free(tlb_content);

    // Deserialize to SerializableTimeline
    var timeline = try deserialize_to_serializable_timeline(
        allocator,
        tlb_content,
        .all,
    );
    defer timeline.deinit(allocator);

    // Basic sanity check
    try std.testing.expectEqualStrings("Linear Accel", timeline.name);
}

test "roundtrip: warp with affine transform"
{
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    // Skip if files don't exist
    std.Io.Dir.cwd().access(std.testing.io, "test_files/just_warp.tla", .{}) catch {
        test_print("Skipping: test_files/just_warp.tla not found\n", .{});
        return;
    };
    std.Io.Dir.cwd().access(std.testing.io, "test_files/just_warp.tlb", .{}) catch {
        test_print("Skipping: test_files/just_warp.tlb not found\n", .{});
        return;
    };

    const passed = try run_roundtrip_test_from_paths(
        allocator,
        io,
        "test_files/just_warp.tla",
        "test_files/just_warp.tlb",
    );
    try std.testing.expect(passed);
}

test "roundtrip: warp with bezier transform (linearized)"
{
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    // Skip if files don't exist
    std.Io.Dir.cwd().access(io, "test_files/just_warp_bez.tla", .{}) catch {
        test_print("Skipping: test_files/just_warp_bez.tla not found\n", .{});
        return;
    };
    std.Io.Dir.cwd().access(io, "test_files/just_warp_bez.tlb", .{}) catch {
        test_print("Skipping: test_files/just_warp_bez.tlb not found\n", .{});
        return;
    };

    const passed = try run_roundtrip_test_from_paths(
        allocator,
        io,
        "test_files/just_warp_bez.tla",
        "test_files/just_warp_bez.tlb",
    );
    try std.testing.expect(passed);
}

test "roundtrip: transition with container children"
{
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    // Skip if files don't exist
    std.Io.Dir.cwd().access(io, "test_files/just_transition.tla", .{}) catch {
        test_print("Skipping: test_files/just_transition.tla not found\n", .{});
        return;
    };
    std.Io.Dir.cwd().access(io, "test_files/just_transition.tlb", .{}) catch {
        test_print("Skipping: test_files/just_transition.tlb not found\n", .{});
        return;
    };

    const passed = try run_roundtrip_test_from_paths(
        allocator,
        io,
        "test_files/just_transition.tla",
        "test_files/just_transition.tlb",
    );
    try std.testing.expect(passed);
}

test "roundtrip: all test_files"
{
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    test_print("\nRunning roundtrip tests from test_files/...\n", .{});

    var passed: usize = 0;
    var failed: usize = 0;

    try run_roundtrip_tests_from_dir(allocator, io, "test_files", &passed, &failed);

    test_print("test_files: {d} passed, {d} failed\n", .{ passed, failed });
    try std.testing.expect(failed == 0);
}

test "roundtrip: all otio_sample_data"
{
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    test_print("\nRunning roundtrip tests from otio_sample_data/...\n", .{});

    var passed: usize = 0;
    var failed: usize = 0;

    try run_roundtrip_tests_from_dir(
        allocator,
        io,
        "otio_sample_data",
        &passed,
        &failed,
    );

    test_print("otio_sample_data: {d} passed, {d} failed\n", .{ passed, failed });
    try std.testing.expect(failed == 0);
}

test "roundtrip: production_test_files (optional)"
{
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    // Only run if build option is enabled
    if (!build_options.include_production_tests) {
        test_print(
            "\nSkipping production_test_files (use -Dinclude_production_tests=true to enable)\n",
            .{},
        );
        return error.SkipZigTest;
    }

    test_print("\nRunning roundtrip tests from production_test_files/...\n", .{});

    var passed: usize = 0;
    var failed: usize = 0;

    try run_roundtrip_tests_from_dir(allocator, io, "production_test_files", &passed, &failed);

    test_print("production_test_files: {d} passed, {d} failed\n", .{ passed, failed });
    try std.testing.expect(failed == 0);
}


// ----------------------------------------------------------------------------
// Codec interface (see adapter.zig)
// ----------------------------------------------------------------------------

/// TLB: timeline root in FlatBuffers.
pub const TimelineCodec = struct {
    pub fn read(
        allocator: Allocator,
        reader: *std.Io.Reader,
        options: format_m.ReadOptions,
    ) !serializable.SerializableTimeline
    {
        const buffer = try reader.allocRemaining(allocator, .unlimited);
        defer allocator.free(buffer);

        return try deserialize_to_serializable_timeline(
            allocator,
            buffer,
            options.content_filter,
        );
    }

    pub fn write(
        allocator: Allocator,
        data: serializable.SerializableTimeline,
        writer: *std.Io.Writer,
        options: format_m.WriteOptions,
    ) !void
    {
        // TLB always stores metadata by hash reference.
        _ = options;
        try serialize_from_serializable_timeline(data, allocator, writer);
    }
};

/// TLCB: collection root in FlatBuffers.
pub const CollectionCodec = struct {
    pub fn read(
        allocator: Allocator,
        reader: *std.Io.Reader,
        options: format_m.ReadOptions,
    ) !serializable.SerializableCollection
    {
        // all_except_metadata is applied by the adapter after decoding.
        _ = options;
        const buffer = try reader.allocRemaining(allocator, .unlimited);
        defer allocator.free(buffer);

        return try deserialize_collection(allocator, buffer);
    }

    pub fn write(
        allocator: Allocator,
        data: serializable.SerializableCollection,
        writer: *std.Io.Writer,
        options: format_m.WriteOptions,
    ) !void
    {
        // TLCB always stores metadata by hash reference.
        _ = options;
        try serialize_collection(data, allocator, writer);
    }
};
