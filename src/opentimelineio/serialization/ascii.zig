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

// ----------------------------------------------------------------------------
// TLA layouts
// ----------------------------------------------------------------------------
// TLA files use `serializable.Tree` with `TlaClip`, which stores metadata by
// hash reference (`metadata_hash`, the default) or inline (`metadata`, for
// `.inline_metadata` output).  `serializable.convert` maps between these
// trees and the in-memory `serializable.Core` tree; see the hooks below.

/// A clip as stored in TLA: the `SerializableClip` fields plus inline
/// `metadata` of type `Meta` (`?MetadataValue`, or `?SkippedValue` to
/// discard it while parsing).  At most one of `metadata_hash` and
/// `metadata` may be set.
fn TlaClip(
    comptime Meta: type,
) type
{
    return struct {
        name: []const u8 = "",
        bounds_s: ?SerializableBounds = null,
        media: SerializableMediaReference,
        /// Key of an entry in the enclosing timeline/collection metadata_map.
        metadata_hash: ?[]const u8 = null,
        /// Metadata stored inline instead of by hash reference.
        metadata: Meta = null,
        markers: []SerializableMarker = &.{},
    };
}

/// TLA tree: clips with hash references or inline metadata.
const TlaTree = serializable.Tree(TlaClip(?MetadataValue));

/// TLA tree that discards inline clip metadata while parsing.
const TlaTreeSkipMetadata = serializable.Tree(TlaClip(?SkippedValue));

/// File layout of a TLA timeline document: the `Tr.Timeline` fields plus
/// the document's (required) schema version, with a root `metadata_map` of
/// type `Map` (`?MetadataMap`, or `SkippedValue` to discard it while
/// parsing).  Timelines nested in collections are `Tr.Timeline`, which has
/// no version field (a nested version is an unknown-field error).
fn TimelineDocument(
    comptime Tr: type,
    comptime Map: type,
) type
{
    return struct {
        pub const schema_name: []const u8 = "Timeline";
        pub const Tree = Tr;

        /// The document's schema version (required).
        schema_version: u32,
        name: []const u8 = "",
        children: []Tr.Composable,
        presentation_space_discrete_partitions: SerializableDiscretePartitionDomainMap,
        metadata_map: Map = if (Map == SkippedValue) .{} else null,
        markers: []SerializableMarker = &.{},
    };
}

/// File layout of a TLCA collection document: the `Tr.Collection` fields
/// plus the document's (required) schema version.
fn CollectionDocument(
    comptime Tr: type,
) type
{
    return struct {
        pub const schema_name: []const u8 = "Collection";
        pub const Tree = Tr;

        /// The document's schema version (required).
        schema_version: u32,
        name: []const u8 = "",
        description: []const u8 = "",
        children: []Tr.CollectionItem,
        metadata_map: ?MetadataMap = null,
    };
}

/// Document layout of `content` (a `Tr.Timeline` or `Tr.Collection`) at
/// `schema_version`.  Borrows every field of `content`.
fn document_layout(
    comptime Tr: type,
    content: anytype,
    schema_version: u32,
) if (@TypeOf(content) == Tr.Timeline)
    TimelineDocument(Tr, ?MetadataMap)
else
    CollectionDocument(Tr)
{
    const Content = @TypeOf(content);
    const Layout = if (Content == Tr.Timeline)
        TimelineDocument(Tr, ?MetadataMap)
    else
        CollectionDocument(Tr);

    const content_fields = @typeInfo(Content).@"struct".field_names;
    comptime std.debug.assert(
        @typeInfo(Layout).@"struct".field_names.len == content_fields.len + 1
    );

    var result: Layout = undefined;
    result.schema_version = schema_version;
    inline for (content_fields)
        |name|
    {
        @field(result, name) = @field(content, name);
    }
    return result;
}

/// Write hooks for `.no_metadata`: clear clip hash references and drop the
/// timeline/collection metadata maps; everything else is shared.
const StripMetadata = struct {
    pub const mode: serializable.ConvertMode = .share;
    pub const Error = error{OutOfMemory};

    pub fn overrides(
        comptime T: type,
    ) bool
    {
        return (
            T == SerializableClip
            or T == SerializableTimeline
            or T == SerializableCollection
        );
    }

    pub fn override(
        self: *@This(),
        comptime Src: type,
        comptime Dst: type,
        allocator: std.mem.Allocator,
        value: Src,
    ) Error!Dst
    {
        var result = try serializable.convert_fields(
            Src,
            Dst,
            @This(),
            self,
            allocator,
            value,
        );
        if (Src == SerializableClip)
        {
            result.metadata_hash = null;
        }
        else
        {
            result.metadata_map = null;
        }
        return result;
    }
};

/// Write hooks for `.inline_metadata`: store each clip's metadata inline,
/// looked up in the metadata map of its enclosing timeline or collection,
/// and drop the maps; everything else is shared.
const InlineMetadata = struct {
    /// Metadata map of the enclosing timeline or collection.
    maybe_map: ?MetadataMap = null,

    pub const mode: serializable.ConvertMode = .share;
    pub const Error = error{OutOfMemory};

    pub fn overrides(
        comptime T: type,
    ) bool
    {
        return StripMetadata.overrides(T);
    }

    pub fn override(
        self: *@This(),
        comptime Src: type,
        comptime Dst: type,
        allocator: std.mem.Allocator,
        value: Src,
    ) Error!Dst
    {
        if (Src == SerializableClip)
        {
            var result: Dst = undefined;
            inline for (@typeInfo(Src).@"struct".field_names)
                |name|
            {
                @field(result, name) = @field(value, name);
            }
            result.metadata_hash = null;
            result.metadata = (
                if (value.metadata_hash)
                    |hash|
                    if (self.maybe_map)
                        |mm|
                        mm.fields.get(hash)
                    else
                        null
                else
                    null
            );
            return result;
        }

        // a timeline or collection: its clips use its own map
        var inner: @This() = .{ .maybe_map = value.metadata_map };
        var result = try serializable.convert_fields(
            Src,
            Dst,
            @This(),
            &inner,
            allocator,
            value,
        );
        result.metadata_map = null;
        return result;
    }
};

/// Read hooks for a parsed TLA tree `Tr`: convert it to the in-memory
/// tree, moving inline clip metadata into the metadata map of the enclosing
/// timeline or collection under its content hash (the key
/// `MetadataContext` would give it), so in memory clips always reference
/// metadata by hash.  A clip with both a hash and inline metadata is
/// `error.ConflictingClipMetadata`.
///
/// Shares the parsed values (`.share`); `parse_ziggy` copies the result.
fn FoldInlineMetadata(
    comptime Tr: type,
) type
{
    return struct {
        /// Metadata map of the enclosing timeline or collection.
        map: *?MetadataMap,

        pub const mode: serializable.ConvertMode = .share;
        pub const Error = error{
            OutOfMemory,
            ConflictingClipMetadata,
        };

        pub fn overrides(
            comptime T: type,
        ) bool
        {
            return T == Tr.Clip or T == Tr.Timeline or T == Tr.Collection;
        }

        pub fn override(
            self: *@This(),
            comptime Src: type,
            comptime Dst: type,
            allocator: std.mem.Allocator,
            value: Src,
        ) Error!Dst
        {
            if (Src == Tr.Clip)
            {
                return try self.fold_clip(allocator, value);
            }
            return try convert_with_own_map(Src, Dst, allocator, value);
        }

        /// Convert a struct with its own `metadata_map` (a timeline, a
        /// collection or a document layout): its clips fold into that map.
        pub fn convert_with_own_map(
            comptime Src: type,
            comptime Dst: type,
            allocator: std.mem.Allocator,
            value: Src,
        ) Error!Dst
        {
            var result: Dst = undefined;
            result.metadata_map = (
                if (@FieldType(Src, "metadata_map") == ?MetadataMap)
                    value.metadata_map
                else
                    null
            );

            var inner: @This() = .{ .map = &result.metadata_map };
            const info = @typeInfo(Dst).@"struct";
            inline for (info.field_names, info.field_types)
                |name, FieldType|
            {
                if (comptime std.mem.eql(u8, name, "metadata_map"))
                {
                    continue;
                }
                @field(result, name) = try serializable.convert(
                    @FieldType(Src, name),
                    FieldType,
                    @This(),
                    &inner,
                    allocator,
                    @field(value, name),
                );
            }
            return result;
        }

        fn fold_clip(
            self: *@This(),
            allocator: std.mem.Allocator,
            clip: Tr.Clip,
        ) Error!SerializableClip
        {
            var result: SerializableClip = undefined;
            inline for (@typeInfo(SerializableClip).@"struct".field_names)
                |name|
            {
                @field(result, name) = @field(clip, name);
            }

            const inline_value = clip.metadata orelse return result;
            if (clip.metadata_hash != null)
            {
                return error.ConflictingClipMetadata;
            }
            if (@TypeOf(inline_value) == MetadataValue)
            {
                result.metadata_hash = try self.add(allocator, inline_value);
            }
            return result;
        }

        /// Store `value` in the map under its content hash; return the key.
        fn add(
            self: *@This(),
            allocator: std.mem.Allocator,
            value: MetadataValue,
        ) error{OutOfMemory}![]const u8
        {
            const json = serializable.metadata_value_to_json(
                allocator,
                value,
            ) catch
                |err|
                switch (err) {
                    error.OutOfMemory => return error.OutOfMemory,
                };
            const key = serializable.MetadataContext.hash_key(json);

            if (self.map.* == null)
            {
                self.map.* = .empty;
            }
            const entry = try self.map.*.?.fields.getOrPut(allocator, &key);
            if (!entry.found_existing)
            {
                entry.key_ptr.* = try allocator.dupe(u8, &key);
                entry.value_ptr.* = value;
            }
            return entry.key_ptr.*;
        }
    };
}


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
        .{ .schema_version = versioning.CURRENT_SCHEMA_VERSION, .content = data },
        &out.writer,
        .{ .metadata_mode = metadata_mode },
    );
    return try out.toOwnedSlice();
}

/// The content type (timeline or collection) a codec namespace reads.
fn CodecData(
    comptime Codec: type,
) type
{
    const ret = @typeInfo(@TypeOf(Codec.read)).@"fn".return_type.?;
    return @FieldType(@typeInfo(ret).error_union.payload, "content");
}

/// Test helper: decode `bytes` with a codec namespace.
fn test_decode(
    comptime Codec: type,
    allocator: std.mem.Allocator,
    bytes: []const u8,
) !CodecData(Codec)
{
    var reader: std.Io.Reader = .fixed(bytes);
    return (try Codec.read(allocator, &reader, .{})).content;
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
        TimelineDocument(TlaTreeSkipMetadata, SkippedValue),
        allocator,
        source,
        &meta,
        .{},
    );
    try std.testing.expectEqualStrings("WithMetadata", no_md.name);
    try std.testing.expectEqual(@as(usize, 1), no_md.markers.len);
    try std.testing.expectEqualStrings("m1", no_md.markers[0].name);

    var reader: std.Io.Reader = .fixed(source);
    const read_no_md = try TimelineCodec.read(
        allocator,
        &reader,
        .{ .content_filter = .all_except_metadata },
    );
    try std.testing.expect(read_no_md.content.metadata_map == null);
    try std.testing.expectEqual(@as(usize, 1), read_no_md.content.markers.len);

    // the full parse of the same document still sees the metadata
    const full = try ziggy.deserializeLeaky(
        TimelineDocument(TlaTree, ?MetadataMap),
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
            .{
                .schema_version = versioning.CURRENT_SCHEMA_VERSION,
                .content = value,
            },
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
        TlaClip(?MetadataValue),
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


/// Write `doc` (a `SerializableTimeline` or `SerializableCollection`
/// document) as TLA/TLCA with the given metadata mode.
fn write_document(
    comptime Content: type,
    allocator: std.mem.Allocator,
    doc: serializable.Document(Content),
    metadata_mode: format_m.WriteOptions.MetadataMode,
    writer: *std.Io.Writer,
) !void
{
    // the layouts below share the document's values; only their containers
    // are allocated
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const scratch = arena.allocator();

    const Core = serializable.Core;
    const version = doc.schema_version;
    switch (metadata_mode) {
        .hash_reference => {
            try write_ziggy(
                document_layout(Core, doc.content, version),
                writer,
            );
        },
        .no_metadata => {
            var hooks: StripMetadata = .{};
            const stripped = try serializable.convert(
                Content,
                Content,
                StripMetadata,
                &hooks,
                scratch,
                doc.content,
            );
            try write_ziggy(
                document_layout(Core, stripped, version),
                writer,
            );
        },
        .inline_metadata => {
            const InlineContent = (
                if (Content == SerializableTimeline)
                    TlaTree.Timeline
                else
                    TlaTree.Collection
            );
            var hooks: InlineMetadata = .{};
            const inlined = try serializable.convert(
                Content,
                InlineContent,
                InlineMetadata,
                &hooks,
                scratch,
                doc.content,
            );
            try write_ziggy(
                document_layout(TlaTree, inlined, version),
                writer,
            );
        },
    }
}

/// Serialize `value` as a ziggy document followed by a newline.
fn write_ziggy(
    value: anytype,
    writer: *std.Io.Writer,
) !void
{
    try ziggy.serialize(
        value,
        .{
            .whitespace = .space_4,
            .emit_null_fields = false,
        },
        writer,
    );
    try writer.writeAll("\n");
}

/// Number of non-overlapping occurrences of `needle` in `haystack`.
fn count_of(
    haystack: []const u8,
    needle: []const u8,
) usize
{
    return std.mem.count(u8, haystack, needle);
}

test "tla: every metadata mode keeps markers"
{
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const io = std.testing.io;

    const timelines = [_]SerializableTimeline{
        try schema_coverage_timeline(allocator),
        try test_read_file(
            TimelineCodec,
            allocator,
            io,
            "test_files/simple_cut_with_markers.tla",
        ),
    };

    for (timelines)
        |timeline|
    {
        const hashed = try test_encode(
            TimelineCodec,
            allocator,
            timeline,
            .hash_reference,
        );
        const expected = count_of(hashed, ".marked_range");
        try std.testing.expect(expected > 0);

        const other_modes = [_]format_m.WriteOptions.MetadataMode{
            .inline_metadata,
            .no_metadata,
        };
        for (other_modes)
            |mode|
        {
            const written = try test_encode(
                TimelineCodec,
                allocator,
                timeline,
                mode,
            );
            try std.testing.expectEqual(
                expected,
                count_of(written, ".marked_range"),
            );
        }
    }
}

test "tla: inline metadata reads back into the metadata map"
{
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    // { codec, path, keys are this library's content hashes }
    // (stress_heavy_metadata.tla's key predates the current hash)
    const cases = .{
        .{ TimelineCodec, "test_files/simple_cut_with_metadata.tla", true },
        .{ TimelineCodec, "test_files/just_clip_with_metadata.tla", true },
        .{ TimelineCodec, "test_files/stress_heavy_metadata.tla", false },
        .{ CollectionCodec, "test_files/collection_with_metadata.tlca", false },
    };
    inline for (cases)
        |case|
    {
        const Codec = case[0];
        var original = try test_read_file(Codec, allocator, io, case[1]);
        defer original.deinit(allocator);

        const hashed = try test_encode(
            Codec,
            allocator,
            original,
            .hash_reference,
        );
        defer allocator.free(hashed);
        const inlined = try test_encode(
            Codec,
            allocator,
            original,
            .inline_metadata,
        );
        defer allocator.free(inlined);
        try std.testing.expectEqual(0, count_of(inlined, "metadata_hash"));
        try std.testing.expectEqual(0, count_of(inlined, "metadata_map"));
        try std.testing.expect(count_of(inlined, ".metadata = ") > 0);

        // reading inline metadata stores it by hash in the map again
        var folded = try test_decode(Codec, allocator, inlined);
        defer folded.deinit(allocator);
        try std.testing.expect(folded.metadata_map != null);

        const folded_inlined = try test_encode(
            Codec,
            allocator,
            folded,
            .inline_metadata,
        );
        defer allocator.free(folded_inlined);
        try std.testing.expectEqualStrings(inlined, folded_inlined);

        if (case[2])
        {
            const folded_hashed = try test_encode(
                Codec,
                allocator,
                folded,
                .hash_reference,
            );
            defer allocator.free(folded_hashed);
            try std.testing.expectEqualStrings(hashed, folded_hashed);
        }
    }
}

test "tla: inline clip metadata with content filters and conflicts"
{
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    const original = try std.Io.Dir.cwd().readFileAlloc(
        io,
        "test_files/just_clip_with_metadata.tla",
        allocator,
        .unlimited,
    );
    defer allocator.free(original);

    const hash_line = ".metadata_hash = \"4eda2567c141183c\",";
    const inline_line = ".metadata = { \"note\": \"inline\" },";
    const inline_source = try std.mem.replaceOwned(
        u8,
        allocator,
        original,
        hash_line,
        inline_line,
    );
    defer allocator.free(inline_source);
    const both_source = try std.mem.replaceOwned(
        u8,
        allocator,
        original,
        hash_line,
        hash_line ++ inline_line,
    );
    defer allocator.free(both_source);

    // .all: the inline value joins the existing map entry
    {
        var reader: std.Io.Reader = .fixed(inline_source);
        var doc = try TimelineCodec.read(allocator, &reader, .{});
        defer doc.content.deinit(allocator);

        const mm = doc.content.metadata_map.?;
        try std.testing.expectEqual(2, mm.fields.count());
        const clip = doc.content.children[0].track.children[0].clip;
        const value = mm.fields.get(clip.metadata_hash.?).?;
        try std.testing.expectEqualStrings(
            "inline",
            value.kv.fields.get("note").?.bytes,
        );
    }

    // .all_except_metadata: neither the map nor the inline value is kept
    {
        var reader: std.Io.Reader = .fixed(inline_source);
        var doc = try TimelineCodec.read(
            allocator,
            &reader,
            .{ .content_filter = .all_except_metadata },
        );
        defer doc.content.deinit(allocator);

        try std.testing.expect(doc.content.metadata_map == null);
        const clip = doc.content.children[0].track.children[0].clip;
        try std.testing.expect(clip.metadata_hash == null);
    }

    // a hash and an inline value on one clip is rejected, leaking nothing
    inline for (.{ .all, .all_except_metadata })
        |filter|
    {
        var reader: std.Io.Reader = .fixed(both_source);
        try std.testing.expectError(
            error.ConflictingClipMetadata,
            TimelineCodec.read(
                allocator,
                &reader,
                .{ .content_filter = filter },
            ),
        );
    }
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
                .name = "Embedded Timeline",
                .children = &[_]SerializableComposable{},
                .presentation_space_discrete_partitions = .{},
                .markers = &[_]SerializableMarker{},
                .metadata_map = null,
            },
        },
    };
    const original = SerializableCollection{
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

/// Parse a TLA document with layout `Layout` from `reader` and convert it
/// to a `Document(Content)`.  The result owns all of its memory and is
/// freed with its `deinit`.
///
/// Parsing and conversion happen in a scratch arena, so a rejected document
/// (e.g. one missing a required field) leaks nothing; the result is then
/// deep-copied into `allocator`.  The copy also takes ownership of the
/// strings ziggy leaves pointing into the source, even with
/// `.copy_strings = .always` (dictionary keys, union tags and enum names in
/// metadata).
fn parse_ziggy(
    comptime Layout: type,
    comptime Content: type,
    allocator: std.mem.Allocator,
    reader: *std.Io.Reader,
) !serializable.Document(Content)
{
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const scratch = arena.allocator();

    const source = try reader.allocRemainingAlignedSentinel(
        scratch,
        .unlimited,
        .@"1",
        0,
    );

    var meta: ziggy.Deserializer.Meta = .init;
    const parsed = try ziggy.deserializeLeaky(
        Layout,
        scratch,
        source,
        &meta,
        .{},
    );
    const content = try FoldInlineMetadata(
        Layout.Tree
    ).convert_with_own_map(Layout, Content, scratch, parsed);

    return .{
        .schema_version = parsed.schema_version,
        .content = try serializable.deep_clone(Content, allocator, content),
    };
}

/// TLA: timeline document in ziggy text.
pub const TimelineCodec = struct {
    pub fn read(
        allocator: std.mem.Allocator,
        reader: *std.Io.Reader,
        options: format_m.ReadOptions,
    ) !serializable.Document(SerializableTimeline)
    {
        return switch (options.content_filter) {
            .all => try parse_ziggy(
                TimelineDocument(TlaTree, ?MetadataMap),
                SerializableTimeline,
                allocator,
                reader,
            ),
            // Skips the metadata tokens without building values.
            .all_except_metadata => try parse_ziggy(
                TimelineDocument(TlaTreeSkipMetadata, SkippedValue),
                SerializableTimeline,
                allocator,
                reader,
            ),
        };
    }

    pub fn write(
        allocator: std.mem.Allocator,
        doc: serializable.Document(SerializableTimeline),
        writer: *std.Io.Writer,
        options: format_m.WriteOptions,
    ) !void
    {
        try write_document(
            SerializableTimeline,
            allocator,
            doc,
            options.metadata_mode,
            writer,
        );
    }
};

/// TLCA: collection document in ziggy text.
pub const CollectionCodec = struct {
    pub fn read(
        allocator: std.mem.Allocator,
        reader: *std.Io.Reader,
        options: format_m.ReadOptions,
    ) !serializable.Document(SerializableCollection)
    {
        // all_except_metadata is applied by the adapter after parsing.
        _ = options;
        return try parse_ziggy(
            CollectionDocument(TlaTree),
            SerializableCollection,
            allocator,
            reader,
        );
    }

    pub fn write(
        allocator: std.mem.Allocator,
        doc: serializable.Document(SerializableCollection),
        writer: *std.Io.Writer,
        options: format_m.WriteOptions,
    ) !void
    {
        try write_document(
            SerializableCollection,
            allocator,
            doc,
            options.metadata_mode,
            writer,
        );
    }
};

