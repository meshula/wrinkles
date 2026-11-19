//! High level adapter interface which interprets file types and dispatches to
//! format implementations.
//!
//! ## Overview
//!
//! This module provides a unified serialization API for wrinkles timeline files.
//! The main entry points are:
//!
//! * `read_from_file()` / `write_to_file()` - File-based operations with auto-detection
//! * `read_from_reader()` / `write_to_writer()` - Stream-based operations with explicit format
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
//! ## API Layers
//!
//! **Top-level API** (this module):
//! Returns `CompositionItemHandle` (schema types) for direct use with projection builders.
//!
//! **Serializable submodule** (`serializable`):
//! Returns `SerializableRoot` for cases where you need to preserve/manipulate
//! the serializable representation (e.g., metadata hash maps).
//!
//! ## Memory Ownership
//!
//! Every value returned by a read function owns all of its memory, including
//! strings.  Nothing in the result points into the source file, the reader's
//! buffer, or any buffer used internally while parsing, so the source can be
//! discarded as soon as the read returns.
//!
//! Free a result with its `deinit(allocator)`, passing the same allocator that
//! was given to the read.  Callers never need to supply an arena.
//!
//! Format implementations must uphold this (e.g. by parsing ziggy with
//! `.copy_strings = .always`); the "read results own their memory" tests
//! below enforce it.
//!
//! ## Examples
//!
//! ```zig
//! // Simple read/write with auto-detection
//! const handle = try read_from_file(allocator, "timeline.tla", .{});
//! defer handle.deinit(allocator);
//! try write_to_file(allocator, handle, "output.tlb", .{});
//!
//! // Reading with options
//! const handle = try read_from_file(allocator, "timeline.otio", .{
//!     .content_filter = .all_except_metadata,
//! });
//!
//! // Writing with format override
//! try write_to_file(allocator, handle, "output.dat", .{
//!     .format = .tla,  // Override extension-based detection
//! });
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

// ============================================================================
// Format descriptors
// ============================================================================

pub const FileFormat = format_m.FileFormat;
pub const ReadOptions = format_m.ReadOptions;
pub const WriteOptions = format_m.WriteOptions;

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

/// Union of serializable root types (timeline or collection).
pub const SerializableRoot = union(enum) {
    timeline: serializable_types.SerializableTimeline,
    collection: serializable_types.SerializableCollection,

    /// Free all memory associated with this root.
    pub fn deinit(
        self: *@This(),
        allocator: std.mem.Allocator,
    ) void
    {
        switch (self.*) {
            .timeline => |*t| t.deinit(allocator),
            .collection => |*c| c.deinit(allocator),
        }
    }

    pub fn is_timeline(
        self: @This(),
    ) bool
    {
        return self == .timeline;
    }

    pub fn is_collection(
        self: @This(),
    ) bool
    {
        return self == .collection;
    }

    /// Convert a schema handle (timeline or collection) to a serializable
    /// root.  Allocates memory; caller owns the result.
    pub fn from_schema_handle(
        allocator: std.mem.Allocator,
        handle: CompositionItemHandle,
    ) !SerializableRoot
    {
        return switch (handle) {
            .timeline => |t| .{
                .timeline = try serializable_types.SerializableTimeline.from(
                    allocator,
                    t,
                ),
            },
            .collection => |c| .{
                .collection = try serializable_types.collection_to_serializable(
                    allocator,
                    c,
                ),
            },
            else => error.ExpectedTimelineOrCollection,
        };
    }

    /// Convert to CompositionItemHandle (schema type).
    /// Allocates memory; caller owns the result.
    pub fn to_schema_handle(
        self: @This(),
        allocator: std.mem.Allocator,
    ) !references.CompositionItemHandle
    {
        return switch (self) {
            .timeline => |t| .{
                .timeline = try serializable_types.serializable_to_timeline(
                    allocator,
                    t,
                ),
            },
            .collection => |c| .{
                .collection = try serializable_types.serializable_to_collection(
                    allocator,
                    c,
                ),
            },
        };
    }

    /// Apply the read-side content filter and bring the root up to the
    /// current schema version.  Every read path calls this.
    fn finalize(
        self: *@This(),
        allocator: std.mem.Allocator,
        options: ReadOptions,
    ) !void
    {
        switch (self.*) {
            .timeline => |*t| {
                if (options.content_filter == .all_except_metadata)
                {
                    t.drop_metadata(allocator);
                }
                try serializable_types.finalize_timeline(allocator, t);
            },
            .collection => |*c| {
                if (options.content_filter == .all_except_metadata)
                {
                    c.drop_metadata(allocator);
                }
                try serializable_types.finalize_collection(allocator, c);
            },
        }
    }
};

// ============================================================================
// Codec dispatch
// ============================================================================
//
// Each codec module (ascii.zig, binary.zig, legacy_json.zig) exposes an
// optional `TimelineCodec` and/or `CollectionCodec` namespace, each with an
// optional `read` and `write`:
//
//     pub fn read(allocator, *std.Io.Reader, ReadOptions) !SerializableT
//     pub fn write(allocator, SerializableT, *std.Io.Writer, WriteOptions) !void
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
    const name = if (descriptor(format).is_collection) "CollectionCodec" else "TimelineCodec";
    return if (@hasDecl(Codec, name)) @field(Codec, name) else null;
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
            @compileError(std.fmt.comptimePrint(
                "{s}: parameter {d} must be {s}",
                .{ label, i, @typeName(expected) },
            ));
        }
    }
    const ret = @typeInfo(info.return_type.?);
    if (ret != .error_union or ret.error_union.payload != Payload)
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
            tag ++ ": codec has no namespace for its root type"
        );
        const Data = if (desc.is_collection)
            serializable_types.SerializableCollection
        else
            serializable_types.SerializableTimeline;

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
                tag ++ ": is_read_only disagrees with the codec's `write`"
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
                var root: SerializableRoot = if (comptime descriptor(fmt).is_collection)
                    .{ .collection = try ns.read(allocator, reader, options) }
                else
                    .{ .timeline = try ns.read(allocator, reader, options) };
                errdefer root.deinit(allocator);

                try root.finalize(allocator, options);
                return root;
            }
        },
    }
}

/// Write a serializable root to `writer` in `format`.
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
                    switch (root) {
                        .collection => |c| try ns.write(allocator, c, writer, options),
                        .timeline => return error.NotATimelineFormat,
                    }
                }
                else
                {
                    switch (root) {
                        .timeline => |t| try ns.write(allocator, t, writer, options),
                        .collection => return error.NotACollectionFormat,
                    }
                }
            }
        },
    }
}

fn bundle_write_options(
    options: WriteOptions,
) bundle.WriteOptions
{
    const bundle_opts = (
        options.bundle_options orelse WriteOptions.BundleOptions{}
    );
    return .{
        .bundle_format = switch (bundle_opts.content_format) {
            .tla => .tla,
            .tlb => .tlb,
        },
        .media_policy = switch (bundle_opts.media_policy) {
            .ErrorIfNotFile => .ErrorIfNotFile,
            .MissingIfNotFile => .MissingIfNotFile,
            .AllMissing => .AllMissing,
        },
        .media_base_dir = bundle_opts.media_base_dir,
    };
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
    const desc = descriptor(format);

    if (desc.is_bundle)
    {
        // TODO(serialization stage 4): bundles should read their content
        // through read_root and honor ReadOptions.extract_to_directory.
        var root: SerializableRoot = if (desc.is_collection)
            .{
                .collection = try bundle.read_collection_from_file(
                    allocator,
                    io,
                    file_path,
                    .{},
                ),
            }
        else
            .{
                .timeline = try bundle.read_from_file(
                    allocator,
                    io,
                    file_path,
                    .{},
                ),
            };
        errdefer root.deinit(allocator);

        try root.finalize(allocator, options);
        return root;
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
    if (desc.is_collection and root != .collection)
    {
        return error.NotATimelineFormat;
    }
    if (!desc.is_collection and root != .timeline)
    {
        return error.NotACollectionFormat;
    }

    if (desc.is_bundle)
    {
        // TODO(serialization stage 4): bundles should encode their content
        // through write_root.
        const bundle_opts = bundle_write_options(options);
        switch (root) {
            .timeline => |t| try bundle.write_to_file(
                allocator,
                io,
                t,
                file_path,
                bundle_opts,
            ),
            .collection => |c| try bundle.write_collection_to_file(
                allocator,
                io,
                c,
                file_path,
                bundle_opts,
            ),
        }
        return;
    }

    const file = try std.Io.Dir.cwd().createFile(io, file_path, .{});
    defer file.close(io);

    var write_buffer: [16 * 1024]u8 = undefined;
    var file_writer = file.writer(io, &write_buffer);
    const writer = &file_writer.interface;

    try write_root(allocator, root, writer, format, options);
    try writer.flush();
}

// ============================================================================
// Serializable-level helpers (TODO(serialization stage 5): fold into the
// `serializable` namespace and remove)
// ============================================================================

/// Write a SerializableTimeline to a file; format from the extension.
pub fn write_serializable_timeline_to_file(
    allocator: std.mem.Allocator,
    io: std.Io,
    intermediate_tl: serializable_types.SerializableTimeline,
    file_path: []const u8,
    metadata_mode: WriteOptions.MetadataMode,
) !void
{
    try write_root_to_file(
        allocator,
        io,
        .{ .timeline = intermediate_tl },
        file_path,
        try FileFormat.from_path(file_path),
        .{
            .metadata_mode = metadata_mode,
            // Preserves this function's previous bundle default.
            // TODO(serialization stage 4): settle on one default policy.
            .bundle_options = .{ .media_policy = .ErrorIfNotFile },
        },
    );
}

/// Write a SerializableTimeline to a writer in the specified format.
pub fn write_serializable_to_writer(
    allocator: std.mem.Allocator,
    intermediate_tl: serializable_types.SerializableTimeline,
    format: FileFormat,
    metadata_mode: WriteOptions.MetadataMode,
    writer: *std.Io.Writer,
) !void
{
    try write_root(
        allocator,
        .{ .timeline = intermediate_tl },
        writer,
        format,
        .{ .metadata_mode = metadata_mode },
    );
}

/// Read a SerializableTimeline from a reader in the specified format.
pub fn read_serializable_timeline_from_reader(
    allocator: std.mem.Allocator,
    reader: *std.Io.Reader,
    format: FileFormat,
    content_filter: ReadOptions.ContentFilter,
) !serializable_types.SerializableTimeline
{
    if (descriptor(format).is_collection)
    {
        return error.NotATimelineFormat;
    }
    const root = try read_root(
        allocator,
        reader,
        format,
        .{ .content_filter = content_filter },
    );
    return root.timeline;
}

/// Read a SerializableTimeline from a file; format from the extension.
pub fn read_serializable_timeline_from_file(
    allocator: std.mem.Allocator,
    io: std.Io,
    file_path: []const u8,
    content_filter: ReadOptions.ContentFilter,
) !serializable_types.SerializableTimeline
{
    const format = try FileFormat.from_path(file_path);
    if (descriptor(format).is_collection)
    {
        return error.NotATimelineFormat;
    }
    const root = try read_root_from_file(
        allocator,
        io,
        file_path,
        format,
        .{ .content_filter = content_filter },
    );
    return root.timeline;
}

/// Read a SerializableCollection from a file; format from the extension.
pub fn read_serializable_collection_from_file(
    allocator: std.mem.Allocator,
    io: std.Io,
    file_path: []const u8,
) !serializable_types.SerializableCollection
{
    const format = try FileFormat.from_path(file_path);
    if (!descriptor(format).is_collection)
    {
        return error.NotACollectionFormat;
    }
    const root = try read_root_from_file(
        allocator,
        io,
        file_path,
        format,
        .{},
    );
    return root.collection;
}

/// Write a SerializableCollection to a file; format from the extension.
pub fn write_serializable_collection_to_file(
    allocator: std.mem.Allocator,
    io: std.Io,
    collection: serializable_types.SerializableCollection,
    file_path: []const u8,
    metadata_mode: WriteOptions.MetadataMode,
) !void
{
    try write_root_to_file(
        allocator,
        io,
        .{ .collection = collection },
        file_path,
        try FileFormat.from_path(file_path),
        .{ .metadata_mode = metadata_mode },
    );
}

/// Write a SerializableCollection to a writer in the specified format.
pub fn write_serializable_collection_to_writer(
    allocator: std.mem.Allocator,
    collection: serializable_types.SerializableCollection,
    format: FileFormat,
    metadata_mode: WriteOptions.MetadataMode,
    writer: *std.Io.Writer,
) !void
{
    try write_root(
        allocator,
        .{ .collection = collection },
        writer,
        format,
        .{ .metadata_mode = metadata_mode },
    );
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
        try FileFormat.from_path(file_path),
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

/// Serializable submodule - for working with SerializableRoot directly
pub const serializable = struct {
    pub const Root = SerializableRoot;
    pub const Timeline = serializable_types.SerializableTimeline;
    pub const Collection = serializable_types.SerializableCollection;

    /// Read to SerializableRoot (preserves metadata hash maps, etc.)
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
            try FileFormat.from_path(file_path),
            options,
        );
    }

    /// Write from SerializableRoot
    pub fn write_to_file(
        allocator: std.mem.Allocator,
        io: std.Io,
        root: SerializableRoot,
        file_path: []const u8,
        options: WriteOptions,
    ) !void
    {
        const format = (
            options.format orelse try FileFormat.from_path(file_path)
        );
        try write_root_to_file(allocator, io, root, file_path, format, options);
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
const TEST_COLLECTION_METADATA_PATH = "test_files/collection_with_metadata.tlca";


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
    inline for (.{
        .{ "otio_sample_data/simple_cut.tla", FileFormat.tla },
        .{ "otio_sample_data/simple_cut.tlb", FileFormat.tlb },
        .{ "otio_sample_data/simple_cut.otio", FileFormat.otio },
        .{ TEST_COLLECTION_PATH, FileFormat.tlca },
        .{ TEST_COLLECTION_PATH, FileFormat.tlcb },
    })
        |case|
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
        const source = if (try FileFormat.from_path(path) == format)
            try std.Io.Dir.cwd().readFileAlloc(
                io,
                path,
                allocator,
                .unlimited,
            )
        else src: {
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
        defer if (!source_freed) allocator.free(source);

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

    inline for (.{
        "otio_sample_data/simple_cut.tla",
        "otio_sample_data/simple_cut.tlb",
        "otio_sample_data/simple_cut.otio",
        TEST_COLLECTION_PATH,
    })
        |path|
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

    inline for (.{
        .{ timeline_root, "out.tla" },
        .{ timeline_root, "out.tlb" },
        .{ timeline_root, "out.tlz" },
        .{ collection_root, "out.tlca" },
        .{ collection_root, "out.tlcb" },
        .{ collection_root, "out.tlcz" },
    })
        |case|
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
            std.meta.activeTag(root),
            std.meta.activeTag(result),
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
        if (root == .collection) .tlca else .tla,
        .{},
    );
    return try out.toOwnedSlice();
}

test "adapter: read results own their metadata strings"
{
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    // { file with metadata, format to feed through read_root }
    inline for (.{
        .{ TEST_TIMELINE_METADATA_PATH, FileFormat.tla },
        .{ TEST_TIMELINE_METADATA_PATH, FileFormat.tlb },
        .{ TEST_COLLECTION_METADATA_PATH, FileFormat.tlca },
        .{ TEST_COLLECTION_METADATA_PATH, FileFormat.tlcb },
    })
        |case|
    {
        const path = case[0];
        const format = case[1];
        errdefer std.debug.print(
            "failed for: {s} as .{t}\n",
            .{ path, format },
        );

        // Source bytes in `format`.
        var loaded = try serializable.read_from_file(allocator, io, path, .{});
        defer loaded.deinit(allocator);
        try std.testing.expect(switch (loaded) {
            .timeline => |t| t.metadata_map != null,
            .collection => |c| c.metadata_map != null,
        });

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
        defer if (!source_freed) allocator.free(source);

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
    try std.testing.expect(with_md.timeline.metadata_map != null);

    const without_md = try serializable.read_from_file(
        allocator,
        io,
        TEST_TIMELINE_METADATA_PATH,
        .{ .content_filter = .all_except_metadata },
    );
    try std.testing.expect(without_md.timeline.metadata_map == null);
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
        root.timeline.schema_version,
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
