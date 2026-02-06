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

    /// Returns true if this format represents a collection (multiple items)
    /// rather than a single timeline.
    pub fn is_collection(
        self: @This(),
    ) bool
    {
        return switch (self) {
            .tlca, .tlcb, .tlcz => true,
            .tla, .tlb, .tlz, .otio => false,
        };
    }

    /// Returns true if this format is a bundle (ZIP archive with media).
    pub fn is_bundle(
        self: @This(),
    ) bool
    {
        return switch (self) {
            .tlz, .tlcz => true,
            .tla, .tlb, .tlca, .tlcb, .otio => false,
        };
    }

    /// Returns true if this format only supports reading (not writing).
    pub fn is_read_only(
        self: @This(),
    ) bool
    {
        return switch (self) {
            .otio => true,
            .tla, .tlb, .tlz, .tlca, .tlcb, .tlcz => false,
        };
    }

    /// Get the base format for a bundle (e.g., .tlz -> .tla)
    pub fn bundle_content_format(
        self: @This(),
    ) ?FileFormat
    {
        return switch (self) {
            .tlz => .tla,
            .tlcz => .tlca,
            else => null,
        };
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

    /// Deprecated: Use content_filter instead. Kept for backward compatibility.
    file_contents_to_read: ContentFilter = .all,

    pub const ContentFilter = enum {
        /// Read everything including metadata
        all,
        /// Read structure but skip metadata_map (faster for large files)
        all_except_metadata,
        /// Read only metadata, skip timeline structure
        only_metadata,
    };

    /// Convert to legacy MetadataOptions.Read for backward compatibility
    pub fn to_metadata_read_mode(
        self: ReadOptions,
    ) MetadataOptions.Read
    {
        // Check both fields, preferring the new one if explicitly set
        const filter = if (self.content_filter != .all)
            self.content_filter
        else
            self.file_contents_to_read;

        return switch (filter) {
            .all => .all,
            .all_except_metadata => .no_metadata,
            .only_metadata => .only_metadata,
        };
    }
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

    /// Use same type as MetadataOptions.Write for compatibility
    pub const MetadataMode = MetadataOptions.Write;

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

    /// Convert to legacy MetadataOptions.Write for backward compatibility
    pub fn to_metadata_write_mode(
        self: WriteOptions,
    ) MetadataOptions.Write
    {
        return switch (self.metadata_mode) {
            .hash_reference => .hash_reference,
            .inline_metadata => .inline_metadata,
            .no_metadata => .no_metadata,
        };
    }
};

// Alias for backward compatibility with existing code
pub const CompositionItemHandle = references.CompositionItemHandle;

// ============================================================================
// Legacy Configuration Types (for backward compatibility)
// ============================================================================

pub const MetadataOptions = struct {
    /// Controls how metadata is output in TLA format
    pub const Write = enum {
        /// Default behavior: use hash references with metadata_map
        hash_reference,
        /// Omit all metadata from output
        no_metadata,
        /// Print metadata inline on each clip
        inline_metadata,

        pub const default: Write = .hash_reference;
    };

    pub const Read = enum {
        all,
        no_metadata,
        only_metadata,

        pub const default = .all;
    };
};

// Interface function prototypes
///////////////////////////////////////////////////////////////////////////////

// Timeline Root

const fn_write_timeline_to_writer = fn (
    allocator: std.mem.Allocator,
    ser_timeline: ascii.SerializableTimeline,
    writer: *std.Io.Writer,
    metadata_mode: MetadataOptions.Write,
) anyerror!void;

pub const fn_read_timeline_from_reader = fn (
    allocator: std.mem.Allocator,
    reader: *std.Io.Reader,
    metadata_mode: MetadataOptions.Read,
) anyerror!ascii.SerializableTimeline;

// Collection

const fn_write_collection_to_writer = fn (
    allocator: std.mem.Allocator,
    collection: ascii.SerializableCollection,
    writer: *std.Io.Writer,
    metadata_mode: MetadataOptions.Write,
) anyerror!void;

pub const fn_read_collection_from_reader = fn (
    allocator: std.mem.Allocator,
    reader: *std.Io.Reader,
    metadata_mode: MetadataOptions.Read,
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
        metadata_mode: MetadataOptions.Write,
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
        metadata_mode: MetadataOptions.Read,
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
        metadata_mode: MetadataOptions.Write,
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
        metadata_mode: MetadataOptions.Read,
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

pub const TLA_Adapter: SerializableFormat = .{
    .description = "Native ascii format with a timeline root",

    ._write_timeline_to_writer = ascii.write_ascii_serializable_to_writer,
    ._read_timeline_from_reader = ascii.read_timeline_from_reader,

    ._write_collection_to_writer = ascii.write_ascii_collection_to_writer,
    ._read_collection_from_reader = ascii.read_ascii_collection_from_reader,
};

pub const TLB_Adapter: SerializableFormat = .{
    .description = "Native binary format (FlatBuffers) with a timeline root",

    ._write_timeline_to_writer = binary.write_binary_serializable_to_writer,
    ._read_timeline_from_reader = binary.read_binary_timeline_from_reader,

    ._write_collection_to_writer = binary.write_binary_collection_to_writer,
    ._read_collection_from_reader = binary.read_binary_collection_from_reader,
};

// pub const OTIO_Adapter: SerializableFormat = .{
//     .description = "OpenTimelineIO v1 JSON format (read-only)",
//
//     // OTIO is read-only - writing is not supported
//     ._write_timeline_to_writer = null,
//     ._read_timeline_from_reader = legacy_json.read_otio_timeline_from_reader,
// };

/// Mapping of Suffix to FormatAdapter
pub const FormatSuffix = struct {
    // TLA Formats
    pub const tla = TLA_Adapter;
    pub const tlca = TLA_Adapter;

    // TLB Formats
    pub const tlb = TLB_Adapter;
    pub const tlcb = TLB_Adapter;

    // bundle
    pub const tlz = TLA_Adapter;
    pub const tlcz = TLA_Adapter;

    // OTIO
    // pub const otio = OTIO_Adapter;
};

// Utility
///////////////////////////////////////////////////////////////////////////////

/// Find the associated file format for a file.
/// Deprecated: Use FileFormat.from_path() instead.
pub fn format_for_file(
    file_path: []const u8,
) !FileFormat
{
    return FileFormat.from_path(file_path);
}

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
    metadata_mode: MetadataOptions.Write,
) !void
{
    const format = try format_for_file(file_path);

    // Handle .tlz separately since it manages its own file writing
    if (format == .tlz)
    {
        return error.UseBundleInterfaceForWritingBundles;

        // // @TODO: clean up bundle naming and whatnot
        // try bundle.writeToFile(
        //     allocator,
        //     intermediate_tl,
        //     file_path,
        //     bundle_options.? orelse .{
        //         .bundle_format = .tla,
        //         .media_policy = .ErrorIfNotFile,
        //     },
        // );
        // return;
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
    options: MetadataOptions.Write,
    writer: *std.Io.Writer,
) !void
{
    const fmt_adapter = switch (format) {
        .tla => FormatSuffix.tla,
        .tlb => FormatSuffix.tlb,
        else => return error.NotImplemented,
    };

    if (fmt_adapter._write_timeline_to_writer)
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
    metadata_mode: MetadataOptions.Write,
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
    metadata_mode: MetadataOptions.Read,
) !ascii.SerializableTimeline
{
    const adapter = switch (format) {
        .tla => FormatSuffix.tla,
        .tlb => FormatSuffix.tlb,
        // .otio => FormatSuffix.otio,
        else => return error.NotImplemented,
    };

    return try adapter.read_timeline_from_reader(
        allocator, 
        reader, 
        metadata_mode
    );
}

pub fn read_serializable_timeline_from_file(
    allocator: std.mem.Allocator,
    file_path: []const u8,
    metadata_mode: MetadataOptions.Read,
) !ascii.SerializableTimeline
{
    _ = metadata_mode;

    const format = try format_for_file(file_path);

    // Handle .tlz separately since it manages its own file reading
    if (format == .tlz)
    {
        return try bundle.readFromFile(allocator, file_path, .{});
    }

    // For other formats, use the ascii.read_from_file which handles
    // file reading and format dispatch correctly
    return try ascii.read_from_file(allocator, file_path);
}

pub fn read_timeline_from_file(
    allocator: std.mem.Allocator,
    file_path: []const u8,
    metadata_mode: MetadataOptions.Read,
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

// Bundle Formats
///////////////////////////////////////////////////////////////////////////////

pub fn write_timeline_to_bundle(
) !void
{
    // implement this
}

pub fn read_timeline_from_bundle(
) !void
{
    // implement this
}

pub fn write_collection_to_bundle(
) !void
{
    // implement this
}

pub fn read_collection_from_bundle(
) !void
{
    // implement this
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
    const metadata_mode = options.to_metadata_read_mode();

    if (format.is_bundle()) {
        return error.BundleReadNotYetImplemented;
    }

    if (format.is_collection()) {
        return error.CollectionReadNotYetImplemented;
    }

    // Timeline formats
    var ser_timeline = try read_serializable_timeline_from_file(
        allocator,
        file_path,
        metadata_mode,
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

    if (format.is_read_only()) {
        return error.FormatIsReadOnly;
    }

    if (format.is_bundle()) {
        return error.BundleWriteNotYetImplemented;
    }

    if (format.is_collection()) {
        return error.CollectionWriteNotYetImplemented;
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
        options.to_metadata_write_mode(),
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
    if (format.is_bundle()) {
        return error.BundleRequiresFileAccess;
    }

    if (format.is_collection()) {
        return error.CollectionReadNotYetImplemented;
    }

    var ser_timeline = try read_serializable_timeline_from_reader(
        allocator,
        reader,
        format,
        options.to_metadata_read_mode(),
    );
    defer ser_timeline.deinit(allocator);

    const timeline = try ascii.serializable_to_timeline(allocator, ser_timeline);
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
    if (format.is_read_only()) {
        return error.FormatIsReadOnly;
    }

    if (format.is_bundle()) {
        return error.BundleRequiresFileAccess;
    }

    if (format.is_collection()) {
        return error.CollectionWriteNotYetImplemented;
    }

    const timeline = switch (handle) {
        .timeline => |t| t,
        else => return error.ExpectedTimeline,
    };

    var ser_timeline = try ascii.SerializableTimeline.from(allocator, timeline);
    defer ser_timeline.deinit(allocator);

    try write_serializable_to_writer(
        allocator,
        ser_timeline,
        format,
        options.to_metadata_write_mode(),
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
        const metadata_mode = options.to_metadata_read_mode();

        if (format.is_bundle()) {
            return error.BundleReadNotYetImplemented;
        }

        if (format.is_collection()) {
            return error.CollectionReadNotYetImplemented;
        }

        const ser_timeline = try read_serializable_timeline_from_file(
            allocator,
            file_path,
            metadata_mode,
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
        const format = options.format orelse try FileFormat.from_path(file_path);

        if (format.is_read_only()) {
            return error.FormatIsReadOnly;
        }

        if (format.is_bundle()) {
            return error.BundleWriteNotYetImplemented;
        }

        switch (root) {
            .timeline => |t| {
                try write_serializable_timeline_to_file(
                    allocator,
                    t,
                    file_path,
                    options.to_metadata_write_mode(),
                );
            },
            .collection => {
                return error.CollectionWriteNotYetImplemented;
            },
        }
    }
};
