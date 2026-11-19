//! TLA / TLCA codec: the human-readable ziggy encoding of timelines and
//! collections.
//!
//! Reads and writes the intermediate representation defined in
//! serializable.zig.  Also defines the TLA-only output variants
//! (`*InlineMetadata`, `*NoMetadata`, `*StrippedMetadata`) used for the
//! metadata output modes and for skipping metadata while parsing.
//!
//! Codec interface (see adapter.zig):
//!   `TimelineCodec.read` / `.write`   - .tla
//!   `CollectionCodec.read` / `.write` - .tlca

const std = @import("std");

const ziggy = @import("ziggy");

const opentime = @import("opentime");
const sampling = @import("sampling");
const curve = @import("curve");

const schema = @import("../schema.zig");

const versioning = @import("versioning.zig");
const binary = @import("binary.zig");
const format_m = @import("format.zig");
const serializable = @import("serializable.zig");

// Intermediate representation types and helpers (see serializable.zig)
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
const linear_curve_to_serializable = serializable.linear_curve_to_serializable;
const serializable_to_bezier_curve = serializable.serializable_to_bezier_curve;
const serializable_to_linear_curve = serializable.serializable_to_linear_curve;
const serializable_to_timeline = serializable.serializable_to_timeline;


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

/// Test helper: encode `data` with a codec namespace into an owned buffer.
fn test_encode(
    comptime Codec: type,
    allocator: std.mem.Allocator,
    data: anytype,
    metadata_mode: format_m.WriteOptions.MetadataMode,
) ![]u8
{
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    try Codec.write(
        allocator,
        data,
        &out.writer,
        .{ .metadata_mode = metadata_mode },
    );
    return try out.toOwnedSlice();
}

/// The value type a codec namespace reads.
fn CodecData(
    comptime Codec: type,
) type
{
    const ret = @typeInfo(@TypeOf(Codec.read)).@"fn".return_type.?;
    return @typeInfo(ret).error_union.payload;
}

/// Test helper: decode `bytes` with a codec namespace.
fn test_decode(
    comptime Codec: type,
    allocator: std.mem.Allocator,
    bytes: []const u8,
) !CodecData(Codec)
{
    var reader: std.Io.Reader = .fixed(bytes);
    return try Codec.read(allocator, &reader, .{});
}

/// Test helper: decode the file at `path` with a codec namespace.
fn test_read_file(
    comptime Codec: type,
    allocator: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
) !CodecData(Codec)
{
    const bytes = try std.Io.Dir.cwd().readFileAlloc(
        io,
        path,
        allocator,
        .unlimited,
    );
    defer allocator.free(bytes);
    return try test_decode(Codec, allocator, bytes);
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
    var ser_timeline = try SerializableTimeline.from(allocator, &timeline);
    defer ser_timeline.deinit(allocator);
    const buffer = try test_encode(
        TimelineCodec,
        allocator,
        ser_timeline,
        .hash_reference,
    );
    defer allocator.free(buffer);

    // Deserialize back
    var loaded_ser = try test_decode(TimelineCodec, allocator, buffer);
    defer loaded_ser.deinit(allocator);
    const loaded_timeline = try serializable_to_timeline(
        allocator,
        loaded_ser,
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
        const Codec = if (is_collection) CollectionCodec else TimelineCodec;
        try Codec.write(
            allocator,
            value,
            &buf.writer,
            .{ .metadata_mode = mode },
        );
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

        const tl = test_read_file(TimelineCodec, allocator, io, path) catch |err| {
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

        const collection = test_read_file(
            CollectionCodec,
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
// TLA / TLCA writers (metadata output modes)
// ----------------------------------------------------------------------------


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
    const buffer = try test_encode(
        CollectionCodec,
        allocator,
        original,
        .hash_reference,
    );
    defer allocator.free(buffer);

    // Deserialize back
    var roundtrip = try test_decode(CollectionCodec, allocator, buffer);
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
    const buffer = try test_encode(
        binary.CollectionCodec,
        allocator,
        original,
        .hash_reference,
    );
    defer allocator.free(buffer);

    // Deserialize back
    var roundtrip = try test_decode(binary.CollectionCodec, allocator, buffer);
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
    const tlca_buffer = try test_encode(
        CollectionCodec,
        allocator,
        original,
        .hash_reference,
    );
    defer allocator.free(tlca_buffer);

    // Read TLCA back
    var from_tlca = try test_decode(CollectionCodec, allocator, tlca_buffer);
    defer from_tlca.deinit(allocator);

    // Convert to TLCB
    const tlcb_buffer = try test_encode(
        binary.CollectionCodec,
        allocator,
        from_tlca,
        .hash_reference,
    );
    defer allocator.free(tlcb_buffer);

    // Read TLCB back
    var from_tlcb = try test_decode(binary.CollectionCodec, allocator, tlcb_buffer);
    defer from_tlcb.deinit(allocator);

    // Verify
    try std.testing.expectEqualStrings("Cross-Format Collection", from_tlcb.name);
    try std.testing.expectEqual(@as(usize, 1), from_tlcb.children.len);
    try std.testing.expectEqualStrings("Embedded Timeline", from_tlcb.children[0].timeline.name);
}

// ----------------------------------------------------------------------------
// Codec interface (see adapter.zig)
// ----------------------------------------------------------------------------

/// Parse a ziggy document of type `T` from `reader`.  Strings are copied, so
/// the result owns all of its memory and is freed with its `deinit`.
///
/// On error (including OutOfMemory) the partially parsed result is leaked,
/// as with any `ziggy.deserializeLeaky` failure.
fn parse_ziggy(
    comptime T: type,
    allocator: std.mem.Allocator,
    reader: *std.Io.Reader,
) !T
{
    const source = try reader.allocRemainingAlignedSentinel(
        allocator,
        .unlimited,
        .@"1",
        0,
    );
    defer allocator.free(source);

    var meta: ziggy.Deserializer.Meta = .init;
    var result = try ziggy.deserializeLeaky(
        T,
        allocator,
        source,
        &meta,
        .{ .copy_strings = .always },
    );

    // Must run before `source` is freed.
    try own_metadata_strings(allocator, &result);
    return result;
}

/// ziggy's dynamic values keep dictionary keys, union tags and enum names as
/// slices into the parse source, even with `.copy_strings = .always`.
/// Replace them with owned copies throughout every metadata map in `data`.
fn own_metadata_strings(
    allocator: std.mem.Allocator,
    data: anytype,
) !void
{
    const T = @TypeOf(data.*);
    if (@hasField(T, "metadata_map")
        and @FieldType(T, "metadata_map") == ?MetadataMap)
    {
        if (data.metadata_map)
            |*mm|
        {
            try own_metadata_map_strings(allocator, mm);
        }
    }
    if (T == SerializableCollection)
    {
        for (data.children)
            |*child|
        {
            switch (child.*) {
                .timeline => |*tl| try own_metadata_strings(allocator, tl),
                else => {},
            }
        }
    }
}

fn own_metadata_map_strings(
    allocator: std.mem.Allocator,
    mm: *MetadataMap,
) error{OutOfMemory}!void
{
    // Replacing a key with an equal copy keeps the hash map valid.
    for (mm.fields.keys())
        |*key|
    {
        key.* = try allocator.dupe(u8, key.*);
    }
    for (mm.fields.values())
        |*value|
    {
        try own_metadata_value_strings(allocator, value);
    }
}

fn own_metadata_value_strings(
    allocator: std.mem.Allocator,
    value: *MetadataValue,
) error{OutOfMemory}!void
{
    switch (value.*) {
        .kv => |*kv| try own_metadata_map_strings(allocator, kv),
        .array => |arr| {
            for (@constCast(arr))
                |*item|
            {
                try own_metadata_value_strings(allocator, item);
            }
        },
        .@"union" => |*u| {
            u.tag = try allocator.dupe(u8, u.tag);
            try own_metadata_value_strings(allocator, u.value);
        },
        .@"enum" => |*e| e.* = try allocator.dupe(u8, e.*),
        .bytes, .integer, .float, .bool, .null => {},
    }
}

/// TLA: timeline root in ziggy text.
pub const TimelineCodec = struct {
    pub fn read(
        allocator: std.mem.Allocator,
        reader: *std.Io.Reader,
        options: format_m.ReadOptions,
    ) !SerializableTimeline
    {
        return switch (options.content_filter) {
            .all => try parse_ziggy(SerializableTimeline, allocator, reader),
            // Skips the metadata_map tokens without building values.
            .all_except_metadata => (
                try parse_ziggy(
                    SerializableTimelineNoMetadata,
                    allocator,
                    reader,
                )
            ).to_serializable_timeline(),
        };
    }

    pub fn write(
        allocator: std.mem.Allocator,
        data: SerializableTimeline,
        writer: *std.Io.Writer,
        options: format_m.WriteOptions,
    ) !void
    {
        try write_tla_with_metadata_mode(
            allocator,
            data,
            options.metadata_mode,
            writer,
        );
    }
};

/// TLCA: collection root in ziggy text.
pub const CollectionCodec = struct {
    pub fn read(
        allocator: std.mem.Allocator,
        reader: *std.Io.Reader,
        options: format_m.ReadOptions,
    ) !SerializableCollection
    {
        // all_except_metadata is applied by the adapter after parsing.
        _ = options;
        return try parse_ziggy(SerializableCollection, allocator, reader);
    }

    pub fn write(
        allocator: std.mem.Allocator,
        data: SerializableCollection,
        writer: *std.Io.Writer,
        options: format_m.WriteOptions,
    ) !void
    {
        try write_tlca_with_metadata_mode(
            allocator,
            data,
            options.metadata_mode,
            writer,
        );
    }
};
