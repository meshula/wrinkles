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
const binary = @import("binary.zig");
const bundle = @import("bundle.zig");
const legacy_json = @import("legacy_json.zig");
const references = @import("../references.zig");

// ============================================================================
// Public Types
// ============================================================================

/// Describes the capabilities and properties of a file format.
/// Used as comptime struct fields to enable efficient format dispatch.
pub const FormatDescriptor = struct {
    /// Human-readable description of the format
    description: []const u8,

    /// True if this format represents a collection (multiple items)
    is_collection: bool,

    /// True if this format is a bundle (ZIP archive with media)
    is_bundle: bool,

    /// True if this format only supports reading (not writing)
    is_read_only: bool,

    /// The base format for bundles (e.g., .tlz uses .tla internally)
    bundle_content_format: ?FileFormat,

    /// The format adapter providing read/write functions
    adapter: SerializableFormat,
};

/// Supported file formats for read/write operations.
/// Format is auto-detected from file extension, or can be specified explicitly.
pub const FileFormat = enum {
    /// Timeline ASCII format (ziggy-based, human-readable)
    tla,
    /// Timeline Binary format (FlatBuffers, high performance)
    tlb,
    /// Timeline Bundle (ZIP archive with embedded media)
    tlz,
    /// Collection ASCII format
    tlca,
    /// Collection Binary format
    tlcb,
    /// Collection Bundle (ZIP archive with embedded media)
    tlcz,
    /// Legacy OpenTimelineIO v1 JSON format (read-only)
    otio,

    /// Comptime format descriptors for each format
    pub const descriptors = struct {
        pub const tla: FormatDescriptor = .{
            .description = "Timeline ASCII format (ziggy-based, human-readable)",
            .is_collection = false,
            .is_bundle = false,
            .is_read_only = false,
            .bundle_content_format = null,
            .adapter = TLA_Adapter,
        };

        pub const tlb: FormatDescriptor = .{
            .description = "Timeline Binary format (FlatBuffers, high performance)",
            .is_collection = false,
            .is_bundle = false,
            .is_read_only = false,
            .bundle_content_format = null,
            .adapter = TLB_Adapter,
        };

        pub const tlz: FormatDescriptor = .{
            .description = "Timeline Bundle (ZIP archive with embedded media)",
            .is_collection = false,
            .is_bundle = true,
            .is_read_only = false,
            .bundle_content_format = .tla,
            .adapter = TLA_Adapter,
        };

        pub const tlca: FormatDescriptor = .{
            .description = "Collection ASCII format",
            .is_collection = true,
            .is_bundle = false,
            .is_read_only = false,
            .bundle_content_format = null,
            .adapter = TLA_Adapter,
        };

        pub const tlcb: FormatDescriptor = .{
            .description = "Collection Binary format",
            .is_collection = true,
            .is_bundle = false,
            .is_read_only = false,
            .bundle_content_format = null,
            .adapter = TLB_Adapter,
        };

        pub const tlcz: FormatDescriptor = .{
            .description = "Collection Bundle (ZIP archive with embedded media)",
            .is_collection = true,
            .is_bundle = true,
            .is_read_only = false,
            .bundle_content_format = .tlca,
            .adapter = TLA_Adapter,
        };

        pub const otio: FormatDescriptor = .{
            .description = "Legacy OpenTimelineIO v1 JSON format (read-only)",
            .is_collection = false,
            .is_bundle = false,
            .is_read_only = true,
            .bundle_content_format = null,
            .adapter = OTIO_Adapter,
        };
    };

    /// Get the format descriptor for this format.
    pub fn descriptor(
        self: @This(),
    ) FormatDescriptor
    {
        return switch (self) {
            .tla => descriptors.tla,
            .tlb => descriptors.tlb,
            .tlz => descriptors.tlz,
            .tlca => descriptors.tlca,
            .tlcb => descriptors.tlcb,
            .tlcz => descriptors.tlcz,
            .otio => descriptors.otio,
        };
    }

    /// Detect file format from path extension.
    /// Returns error.NoFileExtension if path has no extension.
    /// Returns error.UnsupportedFileFormat if extension is not recognized.
    pub fn from_path(
        file_path: []const u8,
    ) !FileFormat
    {
        const ext_start = std.mem.lastIndexOfScalar(
            u8,
            file_path,
            '.',
        ) orelse return error.NoFileExtension;

        const extension = file_path[ext_start + 1 ..];

        return std.meta.stringToEnum(FileFormat, extension) orelse
            return error.UnsupportedFileFormat;
    }
};

/// Union of serializable root types (timeline or collection).
/// Used by the serializable submodule for preserving intermediate representations.
pub const SerializableRoot = union(enum) {
    timeline: ascii.SerializableTimeline,
    collection: ascii.SerializableCollection,

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

    /// Convert to CompositionItemHandle (schema type).
    /// Allocates memory; caller owns the result.
    pub fn to_schema_handle(
        self: @This(),
        allocator: std.mem.Allocator,
    ) !references.CompositionItemHandle
    {
        return switch (self) {
            .timeline => |t| .{
                .timeline = try ascii.serializable_to_timeline(allocator, t),
            },
            .collection => |_| {
                // Collection -> handle conversion not yet implemented
                return error.CollectionToHandleNotImplemented;
            },
        };
    }
};

/// Options for reading timeline/collection files.
pub const ReadOptions = struct {
    /// What content to include in the result.
    content_filter: ContentFilter = .all,

    /// Base directory for resolving relative media paths.
    /// If null, paths are resolved relative to the file being read.
    media_base_dir: ?[]const u8 = null,

    /// For bundles: extract media files to this directory.
    /// If null, media paths point into the bundle.
    extract_to_directory: ?[]const u8 = null,

    pub const ContentFilter = enum {
        /// Read everything including metadata
        all,
        /// Read structure but skip metadata_map (faster for large files)
        all_except_metadata,
        /// Read only metadata, skip timeline structure
        only_metadata,

        pub const default: ContentFilter = .all;
    };
};

/// Options for writing timeline/collection files.
pub const WriteOptions = struct {
    /// Override format detection from file extension.
    /// If null, format is detected from the output file path.
    format: ?FileFormat = null,

    /// How to output metadata (affects TLA/TLCA formats).
    metadata_mode: MetadataMode = .hash_reference,

    /// Bundle-specific options. Ignored for non-bundle formats.
    bundle_options: ?BundleOptions = null,

    /// Controls how metadata is output in TLA format
    pub const MetadataMode = enum {
        /// Default behavior: use hash references with metadata_map
        hash_reference,
        /// Omit all metadata from output
        no_metadata,
        /// Print metadata inline on each clip
        inline_metadata,

        pub const default: MetadataMode = .hash_reference;
    };

    pub const BundleOptions = struct {
        /// Format for the timeline/collection within the bundle
        content_format: enum { tla, tlb } = .tla,
        /// How to handle media file references
        media_policy: MediaPolicy = .MissingIfNotFile,
        /// Base directory for resolving media paths
        media_base_dir: ?[]const u8 = null,

        pub const MediaPolicy = enum {
            /// Error if a referenced file doesn't exist
            ErrorIfNotFile,
            /// Mark as missing if file doesn't exist, continue
            MissingIfNotFile,
            /// Treat all media references as missing (don't copy files)
            AllMissing,
        };
    };

};

// Alias for backward compatibility with existing code
pub const CompositionItemHandle = references.CompositionItemHandle;

// Interface function prototypes
///////////////////////////////////////////////////////////////////////////////

// Timeline Root

const fn_write_timeline_to_writer = fn (
    allocator: std.mem.Allocator,
    ser_timeline: ascii.SerializableTimeline,
    writer: *std.Io.Writer,
    metadata_mode: WriteOptions.MetadataMode,
) anyerror!void;

const fn_read_timeline_from_reader = fn (
    allocator: std.mem.Allocator,
    reader: *std.Io.Reader,
    metadata_mode: ReadOptions.ContentFilter,
) anyerror!ascii.SerializableTimeline;

// Collection

const fn_write_collection_to_writer = fn (
    allocator: std.mem.Allocator,
    collection: ascii.SerializableCollection,
    writer: *std.Io.Writer,
    metadata_mode: WriteOptions.MetadataMode,
) anyerror!void;

const fn_read_collection_from_reader = fn (
    allocator: std.mem.Allocator,
    reader: *std.Io.Reader,
    metadata_mode: ReadOptions.ContentFilter,
) anyerror!ascii.SerializableCollection;

// ----------------------------------------------------------------------------
// Format Definitions
// ----------------------------------------------------------------------------

/// Bundles up interface functions to a given file format
const SerializableFormat = struct {
    description: []const u8,

    // Timeline functions
    _write_timeline_to_writer: ?*const fn_write_timeline_to_writer = null,
    _read_timeline_from_reader: ?*const fn_read_timeline_from_reader = null,

    // Collection functions
    _write_collection_to_writer: ?*const fn_write_collection_to_writer = null,
    _read_collection_from_reader: ?*const fn_read_collection_from_reader = null,

    pub fn write_timeline_to_writer(
        self: *const SerializableFormat,
        allocator: std.mem.Allocator,
        ser_timeline: ascii.SerializableTimeline,
        writer: *std.Io.Writer,
        metadata_mode: WriteOptions.MetadataMode,
    ) anyerror ! void
    {
        if (self._write_timeline_to_writer)
            |fn_writer|
        {
            return fn_writer(
                allocator,
                ser_timeline,
                writer,
                metadata_mode,
            );
        }

        return error.UnsupportedByFormat;
    }

    pub fn read_timeline_from_reader(
        self: *const SerializableFormat,
        allocator: std.mem.Allocator,
        reader: *std.Io.Reader,
        metadata_mode: ReadOptions.ContentFilter,
    ) anyerror ! ascii.SerializableTimeline
    {
        if (self._read_timeline_from_reader)
            |fn_reader|
        {
            return fn_reader(
                allocator,
                reader,
                metadata_mode,
            );
        }

        return error.UnsupportedByFormat;
    }

    pub fn write_collection_to_writer(
        self: *const SerializableFormat,
        allocator: std.mem.Allocator,
        ser_collection: ascii.SerializableCollection,
        writer: *std.Io.Writer,
        metadata_mode: WriteOptions.MetadataMode,
    ) anyerror ! void
    {
        if (self._write_collection_to_writer)
            |fn_writer|
        {
            return fn_writer(
                allocator,
                ser_collection,
                writer,
                metadata_mode,
            );
        }

        return error.UnsupportedByFormat;
    }

    pub fn read_collection_from_reader(
        self: *const SerializableFormat,
        allocator: std.mem.Allocator,
        reader: *std.Io.Reader,
        metadata_mode: ReadOptions.ContentFilter,
    ) anyerror ! ascii.SerializableCollection
    {
        if (self._read_collection_from_reader)
            |fn_reader|
        {
            return fn_reader(
                allocator,
                reader,
                metadata_mode,
            );
        }

        return error.UnsupportedByFormat;
    }
};

/// Format adapter for Timeline ASCII (.tla) format.
/// Human-readable ziggy syntax for timeline serialization.
pub const TLA_Adapter: SerializableFormat = .{
    .description = "Native ascii format with a timeline root",

    ._write_timeline_to_writer = ascii.write_ascii_serializable_to_writer,
    ._read_timeline_from_reader = ascii.read_timeline_from_reader,

    ._write_collection_to_writer = ascii.write_ascii_collection_to_writer,
    ._read_collection_from_reader = ascii.read_ascii_collection_from_reader,
};

/// Format adapter for Timeline Binary (.tlb) format.
/// FlatBuffers-based binary format for efficient timeline serialization.
pub const TLB_Adapter: SerializableFormat = .{
    .description = "Native binary format (FlatBuffers) with a timeline root",

    ._write_timeline_to_writer = binary.write_binary_serializable_to_writer,
    ._read_timeline_from_reader = binary.read_binary_timeline_from_reader,

    ._write_collection_to_writer = binary.write_binary_collection_to_writer,
    ._read_collection_from_reader = binary.read_binary_collection_from_reader,
};

/// Format adapter for Legacy OpenTimelineIO v1 JSON (.otio) format.
/// Read-only adapter for importing OTIO v1 files.
pub const OTIO_Adapter: SerializableFormat = .{
    .description = "Legacy OpenTimelineIO v1 JSON format (read-only)",

    ._write_timeline_to_writer = null, // OTIO is read-only
    ._read_timeline_from_reader = legacy_json.read_otio_timeline_from_reader,

    ._write_collection_to_writer = null, // OTIO is read-only
    ._read_collection_from_reader = null, // OTIO doesn't have collections
};

// Write Timeline
///////////////////////////////////////////////////////////////////////////////

/// Write a SerializableTimeline to any supported file format.
/// Supports: .tla, .tlb (FlatBuffers), .tlz (bundle), based on the file
/// extension.
///
/// Use this function when you have a SerializableTimeline and want to
/// preserve all fields including metadata_hash and metadata_map.
pub fn write_serializable_timeline_to_file(
    allocator: std.mem.Allocator,
    intermediate_tl: ascii.SerializableTimeline,
    file_path: []const u8,
    metadata_mode: WriteOptions.MetadataMode,
) !void
{
    const format = try FileFormat.from_path(file_path);

    // Handle .tlz separately since it manages its own file writing
    if (format == .tlz)
    {
        return try bundle.write_to_file(
            allocator,
            intermediate_tl,
            file_path,
            .{},
        );
    }

    // For other formats, open file and write
    const file = try std.fs.cwd().createFile(file_path, .{});
    defer file.close();

    var file_writer_buffer: [16 * 1024]u8 = undefined;
    var file_writer = file.writer(&file_writer_buffer);
    const writer = &file_writer.interface;

    try write_serializable_to_writer(
        allocator,
        intermediate_tl,
        format,
        metadata_mode,
        writer,
    );

    try writer.flush();
}

/// Write a SerializableTimeline to a writer in the specified format.
///
/// Use this function when you have a SerializableTimeline and want to
/// preserve all fields including metadata_hash and metadata_map.
pub fn write_serializable_to_writer(
    allocator: std.mem.Allocator,
    intermediate_tl: ascii.SerializableTimeline,
    format: FileFormat,
    options: WriteOptions.MetadataMode,
    writer: *std.Io.Writer,
) !void
{
    const desc = format.descriptor();

    if (desc.is_read_only) 
    {
        return error.FormatIsReadOnly;
    }

    if (desc.adapter._write_timeline_to_writer)
        |write_fn|
    {
        return write_fn(
            allocator,
            intermediate_tl,
            writer,
            options,
        );
    }
    else
    {
        return error.AdapterDoesNotSupportSerializationToWriter;
    }
}

/// Write a Timeline to any supported file format.
/// Supports: .tla (ascii), .tlb (binary), .tlz (bundle)
/// The file format is determined by the file extension.
pub fn write_timeline_to_file(
    allocator: std.mem.Allocator,
    timeline: *schema.Timeline,
    file_path: []const u8,
    metadata_mode: WriteOptions.MetadataMode,
) !void
{
    var ser_timeline = try ascii.SerializableTimeline.from(
        allocator,
        timeline,
    );
    defer ser_timeline.deinit(allocator);

    try write_serializable_timeline_to_file(
        allocator,
        ser_timeline,
        file_path,
        metadata_mode,
    );
}

// Read Timeline
///////////////////////////////////////////////////////////////////////////////

pub fn read_serializable_timeline_from_reader(
    allocator: std.mem.Allocator,
    reader: *std.Io.Reader,
    format: FileFormat,
    metadata_mode: ReadOptions.ContentFilter,
) !ascii.SerializableTimeline
{
    const desc = format.descriptor();

    if (desc.is_collection) 
    {
        return error.NotATimelineFormat;
    }

    return try desc.adapter.read_timeline_from_reader(
        allocator,
        reader,
        metadata_mode,
    );
}

pub fn read_serializable_timeline_from_file(
    allocator: std.mem.Allocator,
    file_path: []const u8,
    metadata_mode: ReadOptions.ContentFilter,
) !ascii.SerializableTimeline
{
    _ = metadata_mode;

    const format = try FileFormat.from_path(file_path);

    // Handle .tlz separately since it manages its own file reading
    if (format == .tlz)
    {
        return try bundle.read_from_file(allocator, file_path, .{});
    }

    // For other formats, use the ascii.read_from_file which handles
    // file reading and format dispatch correctly
    return try ascii.read_from_file(allocator, file_path);
}

pub fn read_timeline_from_file(
    allocator: std.mem.Allocator,
    file_path: []const u8,
    metadata_mode: ReadOptions.ContentFilter,
) !*schema.timeline
{
    const ser_timeline = try read_serializable_timeline_from_file(
        allocator,
        file_path,
        metadata_mode,
    );

    return try ascii.serializable_to_timeline(
        allocator,
        ser_timeline
    );
}

/// Read a serializable collection from a file (TLCA, TLCB, or TLCZ format).
pub fn read_serializable_collection_from_file(
    allocator: std.mem.Allocator,
    file_path: []const u8,
) !ascii.SerializableCollection
{
    const format = try FileFormat.from_path(file_path);

    // Handle .tlcz separately since it manages its own file reading
    if (format == .tlcz)
    {
        return try bundle.read_collection_from_file(allocator, file_path, .{});
    }

    return try ascii.read_collection_from_file(allocator, file_path);
}

/// Write a schema.Collection to a file (TLCA or TLCB format).
fn write_collection_to_file(
    allocator: std.mem.Allocator,
    collection: *schema.Collection,
    file_path: []const u8,
    metadata_mode: WriteOptions.MetadataMode,
) !void
{
    // Convert schema.Collection to SerializableCollection
    var ser_collection = try ascii.collection_to_serializable(allocator, collection);
    defer ser_collection.deinit(allocator);

    // Write to file
    try ascii.write_collection_to_file(allocator, ser_collection, file_path, metadata_mode);
}

// ============================================================================
// Unified Public API
// ============================================================================

/// Read timeline or collection from file, returning a schema handle.
/// Format is auto-detected from the file extension.
pub fn read_from_file(
    allocator: std.mem.Allocator,
    file_path: []const u8,
    options: ReadOptions,
) !CompositionItemHandle
{
    const format = try FileFormat.from_path(file_path);
    const desc = format.descriptor();

    if (desc.is_collection)
    {
        // Collection formats (including .tlcz bundles)
        var ser_collection = try read_serializable_collection_from_file(
            allocator,
            file_path,
        );
        defer ser_collection.deinit(allocator);

        const collection = try ascii.serializable_to_collection(allocator, ser_collection);
        return .{ .collection = collection };
    }

    // Timeline formats (including .tlz bundles)
    var ser_timeline = try read_serializable_timeline_from_file(
        allocator,
        file_path,
        options.content_filter,
    );
    defer ser_timeline.deinit(allocator);

    const timeline = try ascii.serializable_to_timeline(allocator, ser_timeline);
    return .{ .timeline = timeline };
}

/// Write timeline or collection to file.
/// Format is auto-detected from extension, or use options.format to override.
pub fn write_to_file(
    allocator: std.mem.Allocator,
    handle: CompositionItemHandle,
    file_path: []const u8,
    options: WriteOptions,
) !void
{
    const format = options.format orelse try FileFormat.from_path(file_path);
    const desc = format.descriptor();

    if (desc.is_read_only) 
    {
        return error.FormatIsReadOnly;
    }

    if (desc.is_bundle)
    {
        const bundle_opts = options.bundle_options orelse WriteOptions.BundleOptions{};
        const bundle_write_opts = bundle.WriteOptions{
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

        if (desc.is_collection)
        {
            // .tlcz bundle
            const collection = switch (handle) {
                .collection => |c| c,
                else => return error.ExpectedCollection,
            };

            var ser_collection = try ascii.collection_to_serializable(
                allocator,
                collection,
            );
            defer ser_collection.deinit(allocator);

            try bundle.write_collection_to_file(
                allocator,
                ser_collection,
                file_path,
                bundle_write_opts,
            );
        }
        else
        {
            // .tlz bundle
            const timeline = switch (handle) {
                .timeline => |t| t,
                else => return error.ExpectedTimeline,
            };

            var ser_timeline = try ascii.SerializableTimeline.from(
                allocator,
                timeline,
            );
            defer ser_timeline.deinit(allocator);

            try bundle.write_to_file(
                allocator,
                ser_timeline,
                file_path,
                bundle_write_opts,
            );
        }
        return;
    }

    if (desc.is_collection)
    {
        // Collection formats
        const collection = switch (handle) {
            .collection => |c| c,
            else => return error.ExpectedCollection,
        };

        try write_collection_to_file(
            allocator,
            collection,
            file_path,
            options.metadata_mode,
        );
        return;
    }

    // Timeline formats
    const timeline = switch (handle) {
        .timeline => |t| t,
        else => return error.ExpectedTimeline,
    };

    try write_timeline_to_file(
        allocator,
        timeline,
        file_path,
        options.metadata_mode,
    );
}

/// Read from a reader with explicit format.
pub fn read_from_reader(
    allocator: std.mem.Allocator,
    reader: *std.Io.Reader,
    format: FileFormat,
    options: ReadOptions,
) !CompositionItemHandle
{
    const desc = format.descriptor();

    if (desc.is_bundle) 
    {
        return error.BundleRequiresFileAccess;
    }

    if (desc.is_collection) 
    {
        // Read collection from reader
        const buffer = try reader.readAlloc(
            allocator,
            std.math.maxInt(u32),
        );
        defer allocator.free(buffer);

        var ser_collection = (
            try ascii.read_collection_from_buffer(
                allocator,
                buffer,
                format,
            )
        );
        defer ser_collection.deinit(allocator);

        const collection = try ascii.serializable_to_collection(
            allocator,
            ser_collection,
        );
        return .{ .collection = collection };
    }

    var ser_timeline = (
        try read_serializable_timeline_from_reader(
            allocator,
            reader,
            format,
            options.content_filter,
        )
    );
    defer ser_timeline.deinit(allocator);

    const timeline = try ascii.serializable_to_timeline(
        allocator,
        ser_timeline,
    );
    return .{ .timeline = timeline };
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
    const desc = format.descriptor();

    if (desc.is_read_only) 
    {
        return error.FormatIsReadOnly;
    }

    if (desc.is_bundle) 
    {
        return error.BundleRequiresFileAccess;
    }

    if (desc.is_collection) 
    {
        // Write collection to writer
        const collection = switch (handle) {
            .collection => |c| c,
            else => return error.ExpectedCollection,
        };

        var ser_collection = (
            try ascii.collection_to_serializable(
                allocator,
                collection,
            )
        );
        defer ser_collection.deinit(allocator);

        // Dispatch to the appropriate collection writer based on format
        switch (format) {
            .tlca => try ascii.write_collection_to_writer(
                allocator,
                ser_collection,
                .tlca,
                options.metadata_mode,
                writer,
            ),
            .tlcb => try ascii.write_collection_to_writer(
                allocator,
                ser_collection,
                .tlcb,
                options.metadata_mode,
                writer,
            ),
            else => return error.NotACollectionFormat,
        }
        return;
    }

    const timeline = switch (handle) {
        .timeline => |t| t,
        else => return error.ExpectedTimeline,
    };

    var ser_timeline = try ascii.SerializableTimeline.from(
        allocator,
        timeline,
    );
    defer ser_timeline.deinit(allocator);

    try write_serializable_to_writer(
        allocator,
        ser_timeline,
        format,
        options.metadata_mode,
        writer,
    );
}

/// Serializable submodule - for working with SerializableRoot directly
pub const serializable = struct {
    pub const Root = SerializableRoot;
    pub const Timeline = ascii.SerializableTimeline;
    pub const Collection = ascii.SerializableCollection;

    /// Read to SerializableRoot (preserves metadata hash maps, etc.)
    pub fn read_from_file(
        allocator: std.mem.Allocator,
        file_path: []const u8,
        options: ReadOptions,
    ) !SerializableRoot
    {
        const format = try FileFormat.from_path(file_path);
        const desc = format.descriptor();

        if (desc.is_collection)
        {
            const ser_collection = (
                try read_serializable_collection_from_file(
                    allocator,
                    file_path,
                )
            );
            return .{ .collection = ser_collection };
        }

        const ser_timeline = (
            try read_serializable_timeline_from_file(
                allocator,
                file_path,
                options.content_filter,
            )
        );

        return .{ .timeline = ser_timeline };
    }

    /// Write from SerializableRoot
    pub fn write_to_file(
        allocator: std.mem.Allocator,
        root: SerializableRoot,
        file_path: []const u8,
        options: WriteOptions,
    ) !void
    {
        const format = (
            options.format orelse try FileFormat.from_path(file_path)
        );
        const desc = format.descriptor();

        if (desc.is_read_only) 
        {
            return error.FormatIsReadOnly;
        }

        if (desc.is_bundle)
        {
            const bundle_opts = options.bundle_options orelse WriteOptions.BundleOptions{};
            const bundle_write_opts = bundle.WriteOptions{
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

            switch (root) {
                .timeline => |t| {
                    try bundle.write_to_file(
                        allocator,
                        t,
                        file_path,
                        bundle_write_opts,
                    );
                },
                .collection => |c| {
                    try bundle.write_collection_to_file(
                        allocator,
                        c,
                        file_path,
                        bundle_write_opts,
                    );
                },
            }
            return;
        }

        switch (root) {
            .timeline => |t| {
                try write_serializable_timeline_to_file(
                    allocator,
                    t,
                    file_path,
                    options.metadata_mode,
                );
            },
            .collection => |c| {
                try ascii.write_collection_to_file(
                    allocator,
                    c,
                    file_path,
                    options.metadata_mode,
                );
            },
        }
    }
};
