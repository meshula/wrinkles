//! Format dispatch for wrinkles timeline files.
//!
//! The public API is re-exported from root.zig; see there for an overview.
//! This module implements it:
//!
//! * `read_root` / `write_root` read and write a `SerializableRoot` on a
//!   stream, dispatching to the format's codec.
//! * `read_root_from_file` / `write_root_to_file` add file handling and
//!   bundles (.tlz/.tlcz), which are containers handled by bundle.zig.
//! * `read_from_*` / `write_to_*` and the `serializable` namespace are thin
//!   wrappers over those four.
//!
//! ## Supported File Formats
//!
//! | Extension | Description | Read | Write |
//! |-----------|-------------|------|-------|
//! | .tla      | Timeline ASCII (ziggy) | ✓ | ✓ |
//! | .tlb      | Timeline Binary (FlatBuffers) | ✓ | ✓ |
//! | .tlz      | Timeline Bundle (ZIP + media) | ✓ | ✓ |
//! | .tlca     | Collection ASCII | ✓ | ✓ |
//! | .tlcb     | Collection Binary | ✓ | ✓ |
//! | .tlcz     | Collection Bundle | ✓ | ✓ |
//! | .otio     | Legacy OTIO v1 JSON | ✓ | - |
//!
//! ## Codecs
//!
//! Each codec module (ascii.zig, binary.zig, legacy_json.zig) exposes an
//! optional `TimelineCodec` and/or `CollectionCodec`, each with `read`
//! and/or `write`.  Read-only formats simply have no `write`.  Signatures,
//! and agreement with the `FormatDescriptor` flags, are checked at compile
//! time (see "Codec dispatch" below).
//!
//! Every read applies `ReadOptions.content_filter` and upgrades the result
//! to `versioning.CURRENT_SCHEMA_VERSION` (`SerializableRoot.finalize`).
//!
//! ## Memory Ownership
//!
//! Every value returned by a read function owns all of its memory, including
//! strings.  Results shall not point into the source file, the reader's
//! buffer, or any buffer used internally while parsing. The source may be
//! discarded as soon as the read returns.
//!
//! Free a result with its `deinit(allocator)`, passing the same allocator that
//! was given to the read.
//!
//! Format implementations must uphold this (e.g. by parsing ziggy with
//! `.copy_strings = .always`). The "read results own their memory" tests
//! below enforce the memory ownership rules.
//!
//! ## Examples
//!
//! ```zig
//! // Read a timeline (format from the extension) and write it as binary
//! var handle = try read_from_file(allocator, io, "timeline.tla", .{});
//! defer handle.deinit(allocator);
//! try write_to_file(allocator, io, handle, "output.tlb", .{});
//!
//! // Skip metadata while reading
//! var fast = try read_from_file(
//!     allocator,
//!     io,
//!     "timeline.otio",
//!     .{ .content_filter = .all_except_metadata },
//! );
//! defer fast.deinit(allocator);
//!
//! // Override extension-based detection
//! try write_to_file(
//!     allocator,
//!     io,
//!     handle,
//!     "output.dat",
//!     .{ .format = .tla },
//! );
//!
//! // Keep the serializable form (metadata hash maps etc.)
//! var root = try serializable.read_from_file(allocator, io, "in.tlz", .{});
//! defer root.deinit(allocator);
//! try serializable.write_to_writer(allocator, root, writer, .tla, .{});
//! ```

const std = @import("std");

const schema = @import("../schema.zig");
const ascii = @import("ascii.zig");
const serializable_types = @import("serializable.zig");
const binary = @import("binary.zig");
const bundle = @import("bundle.zig");
const legacy_json = @import("legacy_json.zig");
const references = @import("../references.zig");
const format_m = @import("format.zig");
const versioning = @import("versioning.zig");
const test_output = @import("test_output");
const json_metadata = @import("../json_metadata.zig");

// ============================================================================
// Format descriptors
// ============================================================================

pub const FileFormat = format_m.FileFormat;
pub const ReadOptions = format_m.ReadOptions;
pub const WriteOptions = format_m.WriteOptions;

/// Errors raised by the serialization library itself.  Functions may also
/// return allocation, I/O and format-specific decoding errors (from ziggy,
/// FlatBuffers, std.json and ZIP parsing).
pub const Error = (
    format_m.FormatError
    || versioning.VersionError
    || bundle.TlzError
);

// Alias for backward compatibility with existing code
pub const CompositionItemHandle = references.CompositionItemHandle;

/// Static properties of a file format.  Read/write support comes from the
/// format's codec (see `codec_for`); `comptime` checks below keep these
/// flags consistent with what the codecs actually declare.
pub const FormatDescriptor = struct {
    /// Human-readable description of the format
    description: []const u8,

    /// True if this format stores a collection root
    is_collection: bool,

    /// True if this format is a bundle (ZIP archive with media)
    is_bundle: bool,

    /// True if this format only supports reading (not writing)
    is_read_only: bool,

    /// The format of the content inside a bundle (e.g., .tlz uses .tla)
    bundle_content_format: ?FileFormat,
};

/// Comptime format descriptors for each format
const descriptors = struct {
    pub const tla: FormatDescriptor = .{
        .description = (
            "Timeline ASCII format (ziggy-based, "
            ++ "human-readable)"
        ),
        .is_collection = false,
        .is_bundle = false,
        .is_read_only = false,
        .bundle_content_format = null,
    };

    pub const tlb: FormatDescriptor = .{
        .description = (
            "Timeline Binary format (FlatBuffers, high "
            ++ "performance)"
        ),
        .is_collection = false,
        .is_bundle = false,
        .is_read_only = false,
        .bundle_content_format = null,
    };

    pub const tlz: FormatDescriptor = .{
        .description = (
            "Timeline Bundle (ZIP archive with embedded "
            ++ "media)"
        ),
        .is_collection = false,
        .is_bundle = true,
        .is_read_only = false,
        .bundle_content_format = .tla,
    };

    pub const tlca: FormatDescriptor = .{
        .description = "Collection ASCII format",
        .is_collection = true,
        .is_bundle = false,
        .is_read_only = false,
        .bundle_content_format = null,
    };

    pub const tlcb: FormatDescriptor = .{
        .description = "Collection Binary format",
        .is_collection = true,
        .is_bundle = false,
        .is_read_only = false,
        .bundle_content_format = null,
    };

    pub const tlcz: FormatDescriptor = .{
        .description = (
            "Collection Bundle (ZIP archive with embedded "
            ++ "media)"
        ),
        .is_collection = true,
        .is_bundle = true,
        .is_read_only = false,
        .bundle_content_format = .tlca,
    };

    pub const otio: FormatDescriptor = .{
        .description = "Legacy OpenTimelineIO v1 JSON format (read-only)",
        .is_collection = false,
        .is_bundle = false,
        .is_read_only = true,
        .bundle_content_format = null,
    };
};

/// Get the format descriptor for `format`.
pub fn descriptor(
    format: FileFormat,
) FormatDescriptor
{
    return switch (format) {
        inline else => |fmt| @field(descriptors, @tagName(fmt)),
    };
}

// ============================================================================
// Serializable root
// ============================================================================

/// A serialized document: schema version plus timeline or collection
/// content (see serializable.zig).
pub const SerializableRoot = serializable_types.SerializableRoot;

/// Apply the read-side content filter and bring `root` up to the current
/// schema version.  Every read path calls this.
fn finish_read(
    root: *SerializableRoot,
    allocator: std.mem.Allocator,
    options: ReadOptions,
) !void
{
    if (options.content_filter == .all_except_metadata)
    {
        switch (root.content) {
            .timeline => |*t| t.drop_metadata(allocator),
            .collection => |*c| c.drop_metadata(allocator),
        }
    }
    try root.finalize(allocator);
}

// ============================================================================
// Codec dispatch
// ============================================================================
//
// Each codec module (ascii.zig, binary.zig, legacy_json.zig) exposes an
// optional `TimelineCodec` and/or `CollectionCodec` namespace, each with an
// optional `read` and `write`:
//
//     pub fn read(allocator, *std.Io.Reader, ReadOptions) !SerializableT
//     pub fn write(allocator, SerializableT, *std.Io.Writer, WriteOptions)
// !void
//
// A format is read-only if its codec has no `write`; it has no collection
// root if there is no `CollectionCodec`.  Bundles (.tlz/.tlcz) have no codec:
// they are containers handled by the file-level functions.

/// The codec module for a non-bundle format, or null for bundles.
fn codec_for(
    comptime format: FileFormat,
) ?type
{
    return switch (format) {
        .tla, .tlca => ascii,
        .tlb, .tlcb => binary,
        .otio => legacy_json,
        .tlz, .tlcz => null,
    };
}

/// The codec namespace for the root type stored by `format`, or null if the
/// format is a bundle or its codec does not support that root type.
fn codec_namespace(
    comptime format: FileFormat,
) ?type
{
    const Codec = codec_for(format) orelse return null;
    const name = if (descriptor(format).is_collection) "CollectionCodec"
    else "TimelineCodec";
    return (
        if (@hasDecl(Codec, name)) @field(Codec, name)
        else null
    );
}

fn has_read(
    comptime format: FileFormat,
) bool
{
    const ns = codec_namespace(format) orelse return false;
    return @hasDecl(ns, "read");
}

fn has_write(
    comptime format: FileFormat,
) bool
{
    const ns = codec_namespace(format) orelse return false;
    return @hasDecl(ns, "write");
}

/// Check that a codec function has the expected parameter types and returns
/// an error union of `Payload`.
fn validate_codec_fn(
    comptime label: []const u8,
    comptime func: anytype,
    comptime params: []const type,
    comptime Payload: type,
) void
{
    const info = @typeInfo(@TypeOf(func)).@"fn";
    if (info.param_types.len != params.len)
    {
        @compileError(label ++ ": wrong number of parameters");
    }
    for (info.param_types, params, 0..)
        |param_type, expected, i|
    {
        if (param_type != expected)
        {
            @compileError(
                std.fmt.comptimePrint(
                    "{s}: parameter {d} must be {s}",
                    .{ label, i, @typeName(expected) },
                ),
            );
        }
    }
    const ret = @typeInfo(info.return_type.?);
    if (
        ret != .error_union
        or ret.error_union.payload != Payload
    )
    {
        @compileError(label ++ ": must return !" ++ @typeName(Payload));
    }
}

comptime {
    for (std.enums.values(FileFormat))
        |fmt|
    {
        const desc = descriptor(fmt);
        const tag = @tagName(fmt);

        if (desc.is_bundle)
        {
            if (codec_for(fmt) != null)
            {
                @compileError(tag ++ ": bundles must not have a codec");
            }
            continue;
        }

        const ns = codec_namespace(fmt) orelse @compileError(
            tag ++ ": codec has no namespace for its root type",
        );
        const Data = serializable_types.Document(
            if (desc.is_collection) serializable_types.SerializableCollection
            else serializable_types.SerializableTimeline,
        );

        if (!@hasDecl(ns, "read"))
        {
            @compileError(tag ++ ": codec must support reading");
        }
        validate_codec_fn(
            tag ++ ".read",
            ns.read,
            &.{ std.mem.Allocator, *std.Io.Reader, ReadOptions },
            Data,
        );

        if (@hasDecl(ns, "write"))
        {
            validate_codec_fn(
                tag ++ ".write",
                ns.write,
                &.{ std.mem.Allocator, Data, *std.Io.Writer, WriteOptions },
                void,
            );
        }

        if (desc.is_read_only == @hasDecl(ns, "write"))
        {
            @compileError(
                tag ++ ": is_read_only disagrees with the codec's `write`",
            );
        }
    }
}

/// Read a serializable root in `format` from `reader`.  The result owns all
/// of its memory and is at the current schema version.
pub fn read_root(
    allocator: std.mem.Allocator,
    reader: *std.Io.Reader,
    format: FileFormat,
    options: ReadOptions,
) !SerializableRoot
{
    switch (format) {
        inline else => |fmt| {
            if (comptime descriptor(fmt).is_bundle)
            {
                return error.BundleRequiresFileAccess;
            }
            else
            {
                const ns = comptime codec_namespace(fmt).?;
                const doc = try ns.read(allocator, reader, options);
                var root: SerializableRoot = .{
                    .schema_version = doc.schema_version,
                    .content = if (comptime descriptor(fmt).is_collection) .{
                        .collection = doc.content,
                    }
                    else .{ .timeline = doc.content },
                };
                errdefer root.deinit(allocator);

                try finish_read(&root, allocator, options);
                return root;
            }
        },
    }
}

/// A root ready to encode: either the caller's root, or an owned downgraded
/// copy of it.
const PreparedRoot = struct {
    root: SerializableRoot,
    owned: bool,

    fn deinit(
        self: *@This(),
        allocator: std.mem.Allocator,
    ) void
    {
        if (self.owned)
        {
            self.root.deinit(allocator);
        }
    }
};

/// Bring `root` to `target_version` for writing, using the given downgrade
/// tables.  `root` itself is never modified.
fn prepare_for_write_with(
    comptime DocumentDowngrades: type,
    allocator: std.mem.Allocator,
    root: SerializableRoot,
    maybe_target_version: ?u32,
) !PreparedRoot
{
    const target = maybe_target_version orelse return .{
        .root = root,
        .owned = false,
    };
    const current = root.schema_version;
    if (target == current)
    {
        return .{ .root = root, .owned = false };
    }
    if (target > current)
    {
        return error.DowngradeTargetIsNewer;
    }

    // Check the whole chain (and that the root kind existed at `target`)
    // before paying for a copy.
    const oldest: u32 = switch (root.content) {
        .timeline => versioning.OLDEST_TIMELINE_VERSION,
        .collection => versioning.OLDEST_COLLECTION_VERSION,
    };
    if (
        target < oldest
        or !versioning.downgrade_supported(
            DocumentDowngrades,
            current,
            target,
        )
    )
    {
        return error.DowngradeNotSupported;
    }

    var copy = try root.clone(allocator);
    errdefer copy.deinit(allocator);
    try versioning.downgrade_with(
        DocumentDowngrades,
        allocator,
        &copy,
        target,
    );
    return .{ .root = copy, .owned = true };
}

fn prepare_for_write(
    allocator: std.mem.Allocator,
    root: SerializableRoot,
    maybe_target_version: ?u32,
) !PreparedRoot
{
    return try prepare_for_write_with(
        versioning.DocumentDowngrades,
        allocator,
        root,
        maybe_target_version,
    );
}

/// Write a serializable root to `writer` in `format`, at
/// `options.target_version` if set.
pub fn write_root(
    allocator: std.mem.Allocator,
    root: SerializableRoot,
    writer: *std.Io.Writer,
    format: FileFormat,
    options: WriteOptions,
) !void
{
    switch (format) {
        inline else => |fmt| {
            const desc = comptime descriptor(fmt);
            if (comptime desc.is_bundle)
            {
                return error.BundleRequiresFileAccess;
            }
            else if (comptime !has_write(fmt))
            {
                return error.FormatIsReadOnly;
            }
            else
            {
                const ns = comptime codec_namespace(fmt).?;
                if (comptime desc.is_collection)
                {
                    if (root.content != .collection)
                    {
                        return error.NotATimelineFormat;
                    }
                }
                else if (root.content != .timeline)
                {
                    return error.NotACollectionFormat;
                }

                var prepared = try prepare_for_write(
                    allocator,
                    root,
                    options.target_version,
                );
                defer prepared.deinit(allocator);

                const content = if (comptime desc.is_collection) (
                    prepared.root.content.collection
                )
                else prepared.root.content.timeline;
                try ns.write(
                    allocator,
                    .{
                        .schema_version = prepared.root.schema_version,
                        .content = content,
                    },
                    writer,
                    options,
                );
            }
        },
    }
}

/// Read a serializable root from the file at `file_path` in `format`.
pub fn read_root_from_file(
    allocator: std.mem.Allocator,
    io: std.Io,
    file_path: []const u8,
    format: FileFormat,
    options: ReadOptions,
) !SerializableRoot
{
    if (descriptor(format).is_bundle)
    {
        return try bundle.read_root_from_file(
            allocator,
            io,
            file_path,
            format,
            options,
        );
    }

    const file = try std.Io.Dir.cwd().openFile(io, file_path, .{});
    defer file.close(io);

    var read_buffer: [16 * 1024]u8 = undefined;
    var file_reader = file.reader(io, &read_buffer);

    return try read_root(
        allocator,
        &file_reader.interface,
        format,
        options,
    );
}

/// Write a serializable root to the file at `file_path` in `format`.
/// Unsupported formats are rejected before the file is created.
pub fn write_root_to_file(
    allocator: std.mem.Allocator,
    io: std.Io,
    root: SerializableRoot,
    file_path: []const u8,
    format: FileFormat,
    options: WriteOptions,
) !void
{
    const desc = descriptor(format);

    if (desc.is_read_only)
    {
        return error.FormatIsReadOnly;
    }
    if (
        desc.is_collection
        and root.content != .collection
    )
    {
        return error.NotATimelineFormat;
    }
    if (
        !desc.is_collection
        and root.content != .timeline
    )
    {
        return error.NotACollectionFormat;
    }

    if (desc.is_bundle)
    {
        try bundle.write_root_to_file(
            allocator,
            io,
            root,
            file_path,
            format,
            options,
        );
        return;
    }

    // Downgrade before creating the file, so a failure leaves nothing behind.
    var prepared = try prepare_for_write(
        allocator,
        root,
        options.target_version,
    );
    defer prepared.deinit(allocator);
    var prepared_options = options;
    prepared_options.target_version = null;

    const file = try std.Io.Dir.cwd().createFile(io, file_path, .{});
    defer file.close(io);

    var write_buffer: [16 * 1024]u8 = undefined;
    var file_writer = file.writer(io, &write_buffer);
    const writer = &file_writer.interface;

    try write_root(allocator, prepared.root, writer, format, prepared_options);
    try writer.flush();
}

// ============================================================================
// Unified Public API
// ============================================================================

/// Read timeline or collection from file, returning a schema handle.
/// Format is auto-detected from the file extension.
pub fn read_from_file(
    allocator: std.mem.Allocator,
    io: std.Io,
    file_path: []const u8,
    options: ReadOptions,
) !CompositionItemHandle
{
    var root = try read_root_from_file(
        allocator,
        io,
        file_path,
        options.format orelse try FileFormat.from_path(file_path),
        options,
    );
    defer root.deinit(allocator);

    return try root.to_schema_handle(allocator);
}

/// Write timeline or collection to file.
/// Format is auto-detected from extension, or use options.format to override.
pub fn write_to_file(
    allocator: std.mem.Allocator,
    io: std.Io,
    handle: CompositionItemHandle,
    file_path: []const u8,
    options: WriteOptions,
) !void
{
    const format = options.format orelse try FileFormat.from_path(file_path);

    var root = try SerializableRoot.from_schema_handle(allocator, handle);
    defer root.deinit(allocator);

    try write_root_to_file(allocator, io, root, file_path, format, options);
}

/// Read from a reader with explicit format.
pub fn read_from_reader(
    allocator: std.mem.Allocator,
    reader: *std.Io.Reader,
    format: FileFormat,
    options: ReadOptions,
) !CompositionItemHandle
{
    var root = try read_root(allocator, reader, format, options);
    defer root.deinit(allocator);

    return try root.to_schema_handle(allocator);
}

/// Write to a writer with explicit format.
pub fn write_to_writer(
    allocator: std.mem.Allocator,
    handle: CompositionItemHandle,
    writer: *std.Io.Writer,
    format: FileFormat,
    options: WriteOptions,
) !void
{
    var root = try SerializableRoot.from_schema_handle(allocator, handle);
    defer root.deinit(allocator);

    try write_root(allocator, root, writer, format, options);
}

/// Serializable API: read and write the intermediate representation
/// directly (preserves metadata hash maps, etc.).  Same shape as the
/// schema-level API, with `SerializableRoot` in place of a schema handle.
pub const serializable = struct {
    pub const Root = SerializableRoot;
    pub const Timeline = serializable_types.SerializableTimeline;
    pub const Collection = serializable_types.SerializableCollection;
    pub const CollectionItem = serializable_types.SerializableCollectionItem;
    pub const Composable = serializable_types.SerializableComposable;
    pub const Bounds = serializable_types.SerializableBounds;
    pub const MetadataMap = serializable_types.MetadataMap;
    pub const MetadataValue = serializable_types.MetadataValue;

    /// Every serializable type and conversion helper.
    pub const types = serializable_types;

    /// Read a root from a file.  Format is detected from the extension, or
    /// use `options.format` to override.
    pub fn read_from_file(
        allocator: std.mem.Allocator,
        io: std.Io,
        file_path: []const u8,
        options: ReadOptions,
    ) !SerializableRoot
    {
        return try read_root_from_file(
            allocator,
            io,
            file_path,
            options.format orelse try FileFormat.from_path(file_path),
            options,
        );
    }

    /// Write a root to a file.  Format is detected from the extension, or
    /// use `options.format` to override.
    pub fn write_to_file(
        allocator: std.mem.Allocator,
        io: std.Io,
        root: SerializableRoot,
        file_path: []const u8,
        options: WriteOptions,
    ) !void
    {
        try write_root_to_file(
            allocator,
            io,
            root,
            file_path,
            options.format orelse try FileFormat.from_path(file_path),
            options,
        );
    }

    /// Read a root from a reader in `format`.
    pub fn read_from_reader(
        allocator: std.mem.Allocator,
        reader: *std.Io.Reader,
        format: FileFormat,
        options: ReadOptions,
    ) !SerializableRoot
    {
        return try read_root(allocator, reader, format, options);
    }

    /// Write a root to a writer in `format`.
    pub fn write_to_writer(
        allocator: std.mem.Allocator,
        root: SerializableRoot,
        writer: *std.Io.Writer,
        format: FileFormat,
        options: WriteOptions,
    ) !void
    {
        try write_root(allocator, root, writer, format, options);
    }
};

// ============================================================================
// Tests
// ============================================================================
//
// These tests pin the behaviour of the public API across every format.  They
// deliberately reference each public entry point so that Zig's lazy analysis
// cannot hide compile errors in unreferenced code paths.

const TEST_TIMELINE_PATH = "otio_sample_data/simple_cut.tla";
const TEST_TIMELINE_METADATA_PATH = "test_files/simple_cut_with_metadata.tla";
const TEST_COLLECTION_PATH = "test_files/sample_collection.tlca";
const TEST_COLLECTION_METADATA_PATH = (
    "test_files/collection_with_metadata.tlca"
);

/// Build a path inside a testing TmpDir, relative to the cwd.
fn tmp_path(
    allocator: std.mem.Allocator,
    tmp: std.testing.TmpDir,
    file_name: []const u8,
) ![]u8
{
    var path_buf: [test_output.MAX_PATH_BYTES]u8 = undefined;
    return allocator.dupe(
        u8,
        try test_output.tmp_file_path(&tmp, &path_buf, file_name),
    );
}

/// Write `handle` to memory in `format`, read it back, and check the root
/// name survived.
fn expect_schema_stream_roundtrip(
    allocator: std.mem.Allocator,
    handle: CompositionItemHandle,
    format: FileFormat,
) !void
{
    var buffer: std.Io.Writer.Allocating = .init(allocator);
    defer buffer.deinit();

    try write_to_writer(
        allocator,
        handle,
        &buffer.writer,
        format,
        .{},
    );

    var reader: std.Io.Reader = .fixed(buffer.written());
    var result = try read_from_reader(
        allocator,
        &reader,
        format,
        .{},
    );
    defer result.deinit(allocator);

    try std.testing.expectEqualStrings(
        handle.name() orelse "",
        result.name() orelse "",
    );
}

test "adapter: schema timeline stream roundtrip (tla, tlb)"
{
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var handle = try read_from_file(
        allocator,
        io,
        TEST_TIMELINE_PATH,
        .{},
    );
    defer handle.deinit(allocator);

    try expect_schema_stream_roundtrip(allocator, handle, .tla);
    try expect_schema_stream_roundtrip(allocator, handle, .tlb);
}

test "adapter: schema collection stream roundtrip (tlca, tlcb)"
{
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var handle = try read_from_file(
        allocator,
        io,
        TEST_COLLECTION_PATH,
        .{},
    );
    defer handle.deinit(allocator);

    try expect_schema_stream_roundtrip(allocator, handle, .tlca);
    try expect_schema_stream_roundtrip(allocator, handle, .tlcb);
}

test "adapter: schema read_from_file + write_to_file every writable format"
{
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var handle = try read_from_file(
        allocator,
        io,
        TEST_TIMELINE_PATH,
        .{},
    );
    defer handle.deinit(allocator);

    inline for (.{ "out.tla", "out.tlb", "out.tlz" })
        |file_name|
    {
        errdefer std.debug.print("failed for: {s}\n", .{file_name});

        const path = try tmp_path(allocator, tmp, file_name);
        defer allocator.free(path);

        try write_to_file(allocator, io, handle, path, .{});

        var result = try read_from_file(allocator, io, path, .{});
        defer result.deinit(allocator);

        try std.testing.expectEqualStrings(
            handle.name() orelse "",
            result.name() orelse "",
        );
    }
}

test "adapter: schema read_from_file + write_to_file collection formats"
{
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var handle = try read_from_file(
        allocator,
        io,
        TEST_COLLECTION_PATH,
        .{},
    );
    defer handle.deinit(allocator);

    inline for (.{ "out.tlca", "out.tlcb", "out.tlcz" })
        |file_name|
    {
        errdefer std.debug.print("failed for: {s}\n", .{file_name});

        const path = try tmp_path(allocator, tmp, file_name);
        defer allocator.free(path);

        try write_to_file(allocator, io, handle, path, .{});

        var result = try read_from_file(allocator, io, path, .{});
        defer result.deinit(allocator);

        try std.testing.expectEqualStrings(
            handle.name() orelse "",
            result.name() orelse "",
        );
    }
}

test "adapter: read results own their memory (schema API)"
{
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    // { file to load, format to feed through read_from_reader }
    inline for (
        .{
            .{ "otio_sample_data/simple_cut.tla", FileFormat.tla },
            .{ "otio_sample_data/simple_cut.tlb", FileFormat.tlb },
            .{ "otio_sample_data/simple_cut.otio", FileFormat.otio },
            .{ TEST_COLLECTION_PATH, FileFormat.tlca },
            .{ TEST_COLLECTION_PATH, FileFormat.tlcb },
        },
    ) |case|
    {
        const path = case[0];
        const format = case[1];
        errdefer std.debug.print(
            "failed for: {s} as .{t}\n",
            .{ path, format },
        );

        var expected = try read_from_file(allocator, io, path, .{});
        defer expected.deinit(allocator);

        // Source bytes in `format`: the file itself if it already is that
        // format, otherwise the expected value re-encoded.
        const source = if (try FileFormat.from_path(path) == format) (
            try std.Io.Dir.cwd().readFileAlloc(
                io,
                path,
                allocator,
                .unlimited,
            )
        )
        else
        src: {
            var encoded: std.Io.Writer.Allocating = .init(allocator);
            errdefer encoded.deinit();
            try write_to_writer(
                allocator,
                expected,
                &encoded.writer,
                format,
                .{},
            );
            break :src try encoded.toOwnedSlice();
        };
        var source_freed = false;
        defer if (!source_freed)
        {
            allocator.free(source);
        };

        var reader: std.Io.Reader = .fixed(source);
        var result = try read_from_reader(allocator, &reader, format, .{});
        defer result.deinit(allocator);

        // Scribble over and free the source; nothing in the result may
        // point into it.
        @memset(source, 0xAA);
        allocator.free(source);
        source_freed = true;

        try std.testing.expectEqualStrings(
            expected.name() orelse "",
            result.name() orelse "",
        );
    }
}

test "adapter: read results own their memory (serializable API)"
{
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    inline for (
        .{
            "otio_sample_data/simple_cut.tla",
            "otio_sample_data/simple_cut.tlb",
            "otio_sample_data/simple_cut.otio",
            TEST_COLLECTION_PATH,
        },
    ) |path|
    {
        var root = try serializable.read_from_file(
            allocator,
            io,
            path,
            .{},
        );
        root.deinit(allocator);
    }
}

test "adapter: serializable.write_to_file every writable format"
{
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const io = std.testing.io;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const timeline_root = try serializable.read_from_file(
        allocator,
        io,
        TEST_TIMELINE_PATH,
        .{},
    );
    const collection_root = try serializable.read_from_file(
        allocator,
        io,
        TEST_COLLECTION_PATH,
        .{},
    );

    inline for (
        .{
            .{ timeline_root, "out.tla" },
            .{ timeline_root, "out.tlb" },
            .{ timeline_root, "out.tlz" },
            .{ collection_root, "out.tlca" },
            .{ collection_root, "out.tlcb" },
            .{ collection_root, "out.tlcz" },
        },
    ) |case|
    {
        const root = case[0];
        const file_name = case[1];
        errdefer std.debug.print("failed for: {s}\n", .{file_name});

        const path = try tmp_path(allocator, tmp, file_name);
        try serializable.write_to_file(allocator, io, root, path, .{});

        const result = try serializable.read_from_file(
            allocator,
            io,
            path,
            .{},
        );
        try std.testing.expectEqual(
            std.meta.activeTag(root.content),
            std.meta.activeTag(result.content),
        );
    }
}

/// Encode `root` as text (.tla or .tlca) for comparisons.
fn root_as_text(
    allocator: std.mem.Allocator,
    root: SerializableRoot,
) ![]u8
{
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    try write_root(
        allocator,
        root,
        &out.writer,
        if (root.content == .collection) .tlca else .tla,
        .{},
    );
    return try out.toOwnedSlice();
}

test "adapter: read results own their metadata strings"
{
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    // { file with metadata, format to feed through read_root }
    inline for (
        .{
            .{ TEST_TIMELINE_METADATA_PATH, FileFormat.tla },
            .{ TEST_TIMELINE_METADATA_PATH, FileFormat.tlb },
            .{ TEST_COLLECTION_METADATA_PATH, FileFormat.tlca },
            .{ TEST_COLLECTION_METADATA_PATH, FileFormat.tlcb },
        },
    ) |case|
    {
        const path = case[0];
        const format = case[1];
        errdefer std.debug.print(
            "failed for: {s} as .{t}\n",
            .{ path, format },
        );

        // Source bytes in `format`.
        var loaded = (
            try serializable.read_from_file(allocator, io, path, .{})
        );
        defer loaded.deinit(allocator);
        try std.testing.expect(
            switch (loaded.content) {
                .timeline => |t| t.metadata_map != null,
                .collection => |c| c.metadata_map != null,
            },
        );

        var encoded: std.Io.Writer.Allocating = .init(allocator);
        defer encoded.deinit();
        try write_root(allocator, loaded, &encoded.writer, format, .{});

        // Reference: read and re-encode while the source is still alive.
        var ref_reader: std.Io.Reader = .fixed(encoded.written());
        var reference = try read_root(allocator, &ref_reader, format, .{});
        defer reference.deinit(allocator);
        const expected = try root_as_text(allocator, reference);
        defer allocator.free(expected);

        // Read from a private copy, then destroy the copy before encoding.
        const source = try allocator.dupe(u8, encoded.written());
        var source_freed = false;
        defer if (!source_freed)
        {
            allocator.free(source);
        };

        var reader: std.Io.Reader = .fixed(source);
        var result = try read_root(allocator, &reader, format, .{});
        defer result.deinit(allocator);

        @memset(source, 0xAA);
        allocator.free(source);
        source_freed = true;

        const actual = try root_as_text(allocator, result);
        defer allocator.free(actual);

        try std.testing.expectEqualStrings(expected, actual);
    }
}

test "adapter: bundles round-trip metadata and honor read options"
{
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // { source with metadata, bundle format, inner encoding }
    inline for (
        .{
            .{ TEST_TIMELINE_METADATA_PATH, FileFormat.tlz, .tla },
            .{ TEST_TIMELINE_METADATA_PATH, FileFormat.tlz, .tlb },
            .{ TEST_COLLECTION_METADATA_PATH, FileFormat.tlcz, .tla },
            .{ TEST_COLLECTION_METADATA_PATH, FileFormat.tlcz, .tlb },
        },
    ) |case|
    {
        const path = case[0];
        const bundle_format = case[1];
        const content_format = case[2];
        errdefer std.debug.print(
            "failed for: {s} as .{t} with {t} content\n",
            .{ path, bundle_format, content_format },
        );

        var original = try serializable.read_from_file(
            allocator,
            io,
            path,
            .{},
        );
        defer original.deinit(allocator);
        const expected = try root_as_text(allocator, original);
        defer allocator.free(expected);

        const bundle_path = try tmp_path(
            allocator,
            tmp,
            "out." ++ @tagName(bundle_format),
        );
        defer allocator.free(bundle_path);

        try serializable.write_to_file(
            allocator,
            io,
            original,
            bundle_path,
            .{ .bundle_options = .{ .content_format = content_format } },
        );

        // Full read matches the original.
        var result = try serializable.read_from_file(
            allocator,
            io,
            bundle_path,
            .{},
        );
        defer result.deinit(allocator);
        const actual = try root_as_text(allocator, result);
        defer allocator.free(actual);
        try std.testing.expectEqualStrings(expected, actual);

        // Content filter applies inside bundles.
        var no_md = try serializable.read_from_file(
            allocator,
            io,
            bundle_path,
            .{ .content_filter = .all_except_metadata },
        );
        defer no_md.deinit(allocator);
        try std.testing.expect(
            switch (no_md.content) {
                .timeline => |t| t.metadata_map == null,
                .collection => |c| c.metadata_map == null,
            },
        );
    }

    // extract_to_directory writes every entry out.
    {
        const bundle_path = try tmp_path(allocator, tmp, "out.tlz");
        defer allocator.free(bundle_path);

        try tmp.dir.createDirPath(io, "extracted");
        const extract_path = try tmp_path(allocator, tmp, "extracted");
        defer allocator.free(extract_path);

        var root = try serializable.read_from_file(
            allocator,
            io,
            bundle_path,
            .{ .extract_to_directory = extract_path },
        );
        defer root.deinit(allocator);

        try tmp.dir.access(io, "extracted/version.txt", .{});
        // The last write above used tlb content.
        try tmp.dir.access(io, "extracted/content.tlb", .{});
    }
}

/// Test helper: one "clip name => metadata JSON" line per clip in `root`, in
/// document order, resolving each clip's `metadata_hash` in the map of the
/// root (or nested timeline) it belongs to.  Independent of key strings.
fn clip_metadata_summary(
    allocator: std.mem.Allocator,
    root: SerializableRoot,
) ![]u8
{
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    const w = &out.writer;

    switch (root.content) {
        .timeline => |tl|
            try summarize_children(
                allocator,
                w,
                tl.children,
                tl.metadata_map,
            ),
        .collection => |coll|
            for (coll.children)
                |item|
            {
                switch (item) {
                    .timeline => |tl|
                        try summarize_children(
                            allocator,
                            w,
                            tl.children,
                            tl.metadata_map,
                        ),
                    .clip => |cl|
                        try summarize_clip(
                            allocator,
                            w,
                            cl,
                            coll.metadata_map,
                        ),
                    .track => |tr|
                        try summarize_children(
                            allocator,
                            w,
                            tr.children,
                            coll.metadata_map,
                        ),
                    .stack => |st|
                        try summarize_children(
                            allocator,
                            w,
                            st.children,
                            coll.metadata_map,
                        ),
                    .warp => |wp|
                        try summarize_children(
                            allocator,
                            w,
                            wp.child[0..1],
                            coll.metadata_map,
                        ),
                    .transition => |tx|
                        try summarize_children(
                            allocator,
                            w,
                            tx.container.children,
                            coll.metadata_map,
                        ),
                    .gap => {},
                }
            },
    }
    return try out.toOwnedSlice();
}

fn summarize_children(
    allocator: std.mem.Allocator,
    w: *std.Io.Writer,
    children: []const serializable_types.SerializableComposable,
    maybe_map: ?serializable_types.MetadataMap,
) !void
{
    for (children)
        |child|
    {
        switch (child) {
            .clip => |cl| try summarize_clip(allocator, w, cl, maybe_map),
            .track => |tr|
                try summarize_children(
                    allocator,
                    w,
                    tr.children,
                    maybe_map,
                ),
            .stack => |st|
                try summarize_children(
                    allocator,
                    w,
                    st.children,
                    maybe_map,
                ),
            .warp => |wp|
                try summarize_children(
                    allocator,
                    w,
                    wp.child[0..1],
                    maybe_map,
                ),
            .transition => |tx|
                try summarize_children(
                    allocator,
                    w,
                    tx.container.children,
                    maybe_map,
                ),
            .gap => {},
        }
    }
}

fn summarize_clip(
    allocator: std.mem.Allocator,
    w: *std.Io.Writer,
    clip: serializable_types.SerializableClip,
    maybe_map: ?serializable_types.MetadataMap,
) !void
{
    try w.print("{s} => ", .{clip.name});
    const maybe_value = blk: {
        const hash = clip.metadata_hash orelse break :blk null;
        const map = maybe_map orelse break :blk null;
        break :blk map.fields.get(hash);
    };
    if (maybe_value)
        |value|
    {
        const json = try serializable_types.metadata_value_to_json(
            allocator,
            value,
        );
        defer json_metadata.deinit(allocator, json);
        try std.json.Stringify.value(json, .{}, w);
    }
    else
    {
        try w.writeAll("(none)");
    }
    try w.writeByte('\n');
}

test "adapter: schema handle round trip preserves metadata"
{
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    // { fixture, keys are content hashes so text must match exactly }
    inline for (
        .{
            .{ TEST_TIMELINE_METADATA_PATH, true },
            .{ TEST_COLLECTION_METADATA_PATH, false },
        },
    ) |case|
    {
        const path = case[0];
        const exact = case[1];
        errdefer std.debug.print("failed for: {s}\n", .{path});

        // Reference: the serializable form.
        var direct = (
            try serializable.read_from_file(allocator, io, path, .{})
        );
        defer direct.deinit(allocator);
        const format: FileFormat = if (direct.content == .collection) .tlca
        else .tla;

        // Through schema handles and back.
        var handle = try read_from_file(allocator, io, path, .{});
        defer handle.deinit(allocator);

        var out: std.Io.Writer.Allocating = .init(allocator);
        defer out.deinit();
        try write_to_writer(allocator, handle, &out.writer, format, .{});

        var reader: std.Io.Reader = .fixed(out.written());
        var result = try read_root(allocator, &reader, format, .{});
        defer result.deinit(allocator);

        // Every clip keeps exactly its own metadata.
        const expected_summary = try clip_metadata_summary(allocator, direct);
        defer allocator.free(expected_summary);
        const actual_summary = try clip_metadata_summary(allocator, result);
        defer allocator.free(actual_summary);
        try std.testing.expect(
            std.mem.indexOf(u8, expected_summary, "=> {") != null,
        );
        try std.testing.expectEqualStrings(expected_summary, actual_summary);

        // Files whose keys are content hashes round-trip byte for byte.
        if (exact)
        {
            const expected = try root_as_text(allocator, direct);
            defer allocator.free(expected);
            try std.testing.expectEqualStrings(expected, out.written());
        }
    }
}

test "adapter: OTIO metadata is owned by the result"
{
    const allocator = std.testing.allocator;
    const io = std.testing.io;
    const path = "otio_sample_data/premiere_example.otio";

    // Serializable API: metadata survives the importer's parse arena.
    var root = try serializable.read_from_file(allocator, io, path, .{});
    defer root.deinit(allocator);
    const summary = try clip_metadata_summary(allocator, root);
    defer allocator.free(summary);
    try std.testing.expect(std.mem.indexOf(u8, summary, "=> {") != null);

    // Schema API: clips own their metadata JSON and deinit frees it.
    var handle = try read_from_file(allocator, io, path, .{});
    defer handle.deinit(allocator);
}

test "adapter: SerializableRoot.clone is a deep copy"
{
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    inline for (
        .{
            TEST_TIMELINE_METADATA_PATH,
            TEST_COLLECTION_METADATA_PATH,
            "test_files/simple_cut_with_media.tla",
        },
    ) |path|
    {
        errdefer std.debug.print("failed for: {s}\n", .{path});

        var original = try serializable.read_from_file(
            allocator,
            io,
            path,
            .{},
        );
        const expected = try root_as_text(allocator, original);
        defer allocator.free(expected);

        var copy = try original.clone(allocator);
        defer copy.deinit(allocator);

        // The copy must not depend on the original's memory.
        original.deinit(allocator);

        const actual = try root_as_text(allocator, copy);
        defer allocator.free(actual);
        try std.testing.expectEqualStrings(expected, actual);
    }
}

test "adapter: target_version"
{
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var root = try serializable.read_from_file(
        allocator,
        io,
        TEST_TIMELINE_METADATA_PATH,
        .{},
    );
    defer root.deinit(allocator);
    const before = try root_as_text(allocator, root);
    defer allocator.free(before);

    // The current version is the same as not asking for one.
    {
        var out: std.Io.Writer.Allocating = .init(allocator);
        defer out.deinit();
        try write_root(
            allocator,
            root,
            &out.writer,
            .tla,
            .{ .target_version = versioning.CURRENT_SCHEMA_VERSION },
        );
        try std.testing.expectEqualStrings(before, out.written());
    }

    // Unwritable targets fail before a file is created, input unchanged.
    inline for (
        .{
            .{
                versioning.CURRENT_SCHEMA_VERSION + 1,
                error.DowngradeTargetIsNewer,
            },
            .{ 0, error.DowngradeNotSupported },
        },
    ) |case|
    {
        const path = try tmp_path(allocator, tmp, "out.tla");
        defer allocator.free(path);

        try std.testing.expectError(
            case[1],
            serializable.write_to_file(
                allocator,
                io,
                root,
                path,
                .{ .target_version = case[0] },
            ),
        );
        try std.testing.expectError(
            error.FileNotFound,
            tmp.dir.access(io, "out.tla", .{}),
        );

        var out: std.Io.Writer.Allocating = .init(allocator);
        defer out.deinit();
        try std.testing.expectError(
            case[1],
            write_root(
                allocator,
                root,
                &out.writer,
                .tlb,
                .{ .target_version = case[0] },
            ),
        );
    }

    const after = try root_as_text(allocator, root);
    defer allocator.free(after);
    try std.testing.expectEqualStrings(before, after);
}

/// A made-up timeline downgrade from the current version to the one before
/// it, which renames the timeline.
fn fake_downgrade_rename(
    allocator: std.mem.Allocator,
    root: *SerializableRoot,
) anyerror!void
{
    const timeline = &root.content.timeline;
    const renamed = try std.fmt.allocPrint(
        allocator,
        "{s} (v{d})",
        .{ timeline.name, root.schema_version - 1 },
    );
    allocator.free(timeline.name);
    timeline.name = renamed;
}

test "adapter: writing an older version downgrades a copy"
{
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    const current = versioning.CURRENT_SCHEMA_VERSION;
    const FakeDocumentDowngrades = versioning.TransformTable(
        SerializableRoot,
        .downgrade,
        &.{
            .{
                .from = current,
                .to = current - 1,
                .change = .{ .transform = fake_downgrade_rename },
            },
        },
    );

    var root = try serializable.read_from_file(
        allocator,
        io,
        TEST_TIMELINE_METADATA_PATH,
        .{},
    );
    defer root.deinit(allocator);
    const before = try root_as_text(allocator, root);
    defer allocator.free(before);
    const original_name = try allocator.dupe(u8, root.content.timeline.name);
    defer allocator.free(original_name);

    var prepared = try prepare_for_write_with(
        FakeDocumentDowngrades,
        allocator,
        root,
        current - 1,
    );
    defer prepared.deinit(allocator);

    try std.testing.expect(prepared.owned);
    try std.testing.expectEqual(current - 1, prepared.root.schema_version);
    const expected_name = try std.fmt.allocPrint(
        allocator,
        "{s} (v{d})",
        .{ original_name, current - 1 },
    );
    defer allocator.free(expected_name);
    try std.testing.expectEqualStrings(
        expected_name,
        prepared.root.content.timeline.name,
    );

    // The downgraded copy encodes with the older version number.
    const text = try root_as_text(allocator, prepared.root);
    defer allocator.free(text);
    const header = try std.fmt.allocPrint(
        allocator,
        ".schema_version = {d},",
        .{current - 1},
    );
    defer allocator.free(header);
    try std.testing.expect(std.mem.startsWith(u8, text, header));

    // The caller's data is untouched.
    const after = try root_as_text(allocator, root);
    defer allocator.free(after);
    try std.testing.expectEqualStrings(before, after);
}

/// Test helper: a TLCA document with one nested timeline.  `root_version`
/// and `nested_version` are inserted verbatim (e.g. ".schema_version = 1,"
/// or "").
fn tlca_source(
    allocator: std.mem.Allocator,
    root_version: []const u8,
    nested_version: []const u8,
) ![]u8
{
    return try std.fmt.allocPrint(
        allocator,
        \\{s}
        \\.name = "Collection",
        \\.description = "",
        \\.children = [
        \\    .timeline(.{{
        \\        {s}
        \\        .name = "Nested",
        \\        .children = [],
        \\        .presentation_space_discrete_partitions = .{{}},
        \\    }}),
        \\],
        \\
        ,
        .{ root_version, nested_version },
    );
}

/// Test helper: ".schema_version = N," for `version`.
fn version_line(
    allocator: std.mem.Allocator,
    version: u32,
) ![]u8
{
    return try std.fmt.allocPrint(
        allocator,
        ".schema_version = {d},",
        .{version},
    );
}

test "adapter: the schema version lives on the document root"
{
    const allocator = std.testing.allocator;
    const current = versioning.CURRENT_SCHEMA_VERSION;

    const root_line = try version_line(allocator, current);
    defer allocator.free(root_line);

    // Nested timelines have no version; one is an unknown field.
    {
        const source = try tlca_source(allocator, root_line, root_line);
        defer allocator.free(source);
        var reader: std.Io.Reader = .fixed(source);
        try std.testing.expectError(
            error.UnknownField,
            read_root(allocator, &reader, .tlca, .{}),
        );
    }

    const source = try tlca_source(allocator, root_line, "");
    defer allocator.free(source);

    var reader: std.Io.Reader = .fixed(source);
    var root = try read_root(allocator, &reader, .tlca, .{});
    defer root.deinit(allocator);
    try std.testing.expectEqual(current, root.schema_version);
    try std.testing.expectEqualStrings(
        "Nested",
        root.content.collection.children[0].timeline.name,
    );

    // Written back, only the root carries a version.
    const text = try root_as_text(allocator, root);
    defer allocator.free(text);
    try std.testing.expectEqual(
        @as(usize, 1),
        std.mem.count(u8, text, ".schema_version"),
    );
    try std.testing.expect(std.mem.startsWith(u8, text, root_line));

    // The same holds through TLCB.
    var tlcb: std.Io.Writer.Allocating = .init(allocator);
    defer tlcb.deinit();
    try write_root(allocator, root, &tlcb.writer, .tlcb, .{});
    var tlcb_reader: std.Io.Reader = .fixed(tlcb.written());
    var from_tlcb = try read_root(allocator, &tlcb_reader, .tlcb, .{});
    defer from_tlcb.deinit(allocator);
    try std.testing.expectEqual(current, from_tlcb.schema_version);
    const tlcb_text = try root_as_text(allocator, from_tlcb);
    defer allocator.free(tlcb_text);
    try std.testing.expectEqualStrings(text, tlcb_text);
}

test "adapter: document versions are required and checked per root kind"
{
    const allocator = std.testing.allocator;

    // A collection older than collections themselves is unreadable.
    if (versioning.OLDEST_COLLECTION_VERSION > 0)
    {
        const old_line = try version_line(
            allocator,
            versioning.OLDEST_COLLECTION_VERSION - 1,
        );
        defer allocator.free(old_line);
        const source = try tlca_source(allocator, old_line, "");
        defer allocator.free(source);

        var reader: std.Io.Reader = .fixed(source);
        try std.testing.expectError(
            error.UpgradeNotSupported,
            read_root(allocator, &reader, .tlca, .{}),
        );
    }

    // A collection document must state its version.
    {
        const source = try tlca_source(allocator, "", "");
        defer allocator.free(source);

        var reader: std.Io.Reader = .fixed(source);
        try std.testing.expectError(
            error.MissingField,
            read_root(allocator, &reader, .tlca, .{}),
        );
    }

    // So must a timeline document.
    {
        const source =
            \\.name = "No Version",
            \\.children = [],
            \\.presentation_space_discrete_partitions = .{},
            \\
        ;

        inline for (
            .{
                ReadOptions{},
                ReadOptions{ .content_filter = .all_except_metadata },
            },
        ) |options|
        {
            var reader: std.Io.Reader = .fixed(source);
            try std.testing.expectError(
                error.MissingField,
                read_root(allocator, &reader, .tla, options),
            );
        }
    }
}

test "adapter: writing a read-only format errors without creating a file"
{
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var handle = try read_from_file(
        allocator,
        io,
        TEST_TIMELINE_PATH,
        .{},
    );
    defer handle.deinit(allocator);

    const path = try tmp_path(allocator, tmp, "out.otio");
    defer allocator.free(path);

    try std.testing.expectError(
        error.FormatIsReadOnly,
        write_to_file(allocator, io, handle, path, .{}),
    );

    try std.testing.expectError(
        error.FileNotFound,
        tmp.dir.access(io, "out.otio", .{}),
    );
}

test "adapter: content_filter all_except_metadata drops metadata"
{
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const io = std.testing.io;

    const with_md = try serializable.read_from_file(
        allocator,
        io,
        TEST_TIMELINE_METADATA_PATH,
        .{},
    );
    try std.testing.expect(with_md.content.timeline.metadata_map != null);

    const without_md = try serializable.read_from_file(
        allocator,
        io,
        TEST_TIMELINE_METADATA_PATH,
        .{ .content_filter = .all_except_metadata },
    );
    try std.testing.expect(without_md.content.timeline.metadata_map == null);
}

test "adapter: older schema versions are upgraded on read"
{
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const io = std.testing.io;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Rewrite a known-good file as schema_version 0.
    const source = try std.Io.Dir.cwd().readFileAlloc(
        io,
        TEST_TIMELINE_PATH,
        allocator,
        .unlimited,
    );
    const v1_header = ".schema_version = 1,";
    try std.testing.expect(std.mem.startsWith(u8, source, v1_header));
    const v0_source = try std.mem.concat(
        allocator,
        u8,
        &.{ ".schema_version = 0,", source[v1_header.len..] },
    );

    try tmp.dir.writeFile(
        io,
        .{ .sub_path = "v0.tla", .data = v0_source },
    );
    const path = try tmp_path(allocator, tmp, "v0.tla");

    const root = try serializable.read_from_file(allocator, io, path, .{});
    try std.testing.expectEqual(
        versioning.CURRENT_SCHEMA_VERSION,
        root.schema_version,
    );
}

test "adapter: FileFormat.from_path"
{
    try std.testing.expectEqual(
        FileFormat.tla,
        try FileFormat.from_path("a/b/c.tla"),
    );
    try std.testing.expectEqual(
        FileFormat.tlcz,
        try FileFormat.from_path("c.tlcz"),
    );
    try std.testing.expectError(
        error.NoFileExtension,
        FileFormat.from_path("no_extension"),
    );
    try std.testing.expectError(
        error.UnsupportedFileFormat,
        FileFormat.from_path("file.txt"),
    );

    // Extensions are case-insensitive.
    try std.testing.expectEqual(
        FileFormat.tlb,
        try FileFormat.from_path("SHOT_010.TLB"),
    );

    // A dot in a directory name is not an extension.
    try std.testing.expectError(
        error.NoFileExtension,
        FileFormat.from_path("renders.v2/timeline"),
    );
    try std.testing.expectError(
        error.NoFileExtension,
        FileFormat.from_path("trailing_dot."),
    );
}
