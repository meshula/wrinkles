//! High level adapter interface which interprets file types and dispatches to
//! format implementations.
//!
//! ## Overview
//!
//! There are four categories of files:
//! 
//! * Native wrinkles formats with a timeline root (TLA, TLB, TLZ)
//! * Native wrinkles formats with a collection root (TLCA, TLCB, TLCZ)
//! * Legacy support for OTIO v1 .otio json files.
//!
//! ## Formats
//!
//! * ASCII Format (TLA, TLCA)
//!     * Based on the `ziggy` library
//!     * Supports including or omitting metadata
//! * Binary Format (TLB, TLCB)
//!     * Based on `flatbuffers`
//! * Bundles Formats (TLZ, TLCZ)
//!     * Zipfile with referenced media included in the bundle.
//!     * see `bundle` for more information.
//! * Legacy OTIO v1 .otio files
//!     * Read-only
//!
//! ## Public interface
//!
//! ### Timeline Root (TLA, TLB, TLZ, OTIO*)
//!
//! `read_timeline_from_reader`
//! `read_timeline_from_file`
//! `read_timeline_from_bundle`
//! 
//! `write_timeline_to_writer`
//! `write_timeline_to_file`
//! `write_timeline_to_bundle`
//!
//! ### Collection Root (TLCA, TLCB, TLCZ, OTIO*)
//!
//! `read_collection_from_reader`
//! `read_collection_from_file`
//! `read_collection_from_bundle`
//!
//! `write_collection_to_writer`
//! `write_collection_to_file`
//! `write_collection_to_bundle`
//!
//! *OTIO is read only, and not supported by the write codepaths.

const std = @import("std");

const schema = @import("../schema.zig");
const ascii = @import("ascii.zig");
const binary = @import("binary.zig");
const bundle = @import("bundle.zig");
const legacy_json = @import("legacy_json.zig");

// Configuration Enums
///////////////////////////////////////////////////////////////////////////////

pub const MetadataOptions = struct {
    pub const Write = ascii.MetadataMode;
    // pub const Write = enum {
    //     hash_reference,
    //     no_metadata,
    //
    //     // only used for serializing to stdout
    //     inline_metadata,
    //
    //     pub const default = .hash_reference;
    // };

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
        self: *SerializableFormat,
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
        self: *SerializableFormat,
        allocator: std.mem.Allocator,
        reader: *std.Io.Reader,
        metadata_mode: MetadataOptions.Reader,
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
        self: *SerializableFormat,
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
        self: *SerializableFormat,
        allocator: std.mem.Allocator,
        reader: *std.Io.Reader,
        metadata_mode: MetadataOptions.Reader,
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
    .suffix = "tlb",
    .description = "Native binary format (FlatBuffers) with a timeline root",

    ._write_timeline_to_writer = binary.write_binary_serializable_to_writer,
    ._read_timeline_from_reader = binary.read_binary_timeline_from_reader,

._write_collection_to_writer = binary.write_binary_collection_to_writer,
    ._read_collection_from_reader = binary.read_binary_collection_from_reader,
};

pub const OTIO_Adapter: SerializableFormat = .{
    .suffix = "otio",
    .description = "OpenTimelineIO v1 JSON format (read-only)",

    // OTIO is read-only - writing is not supported
    ._write_timeline_to_writer = null,
    ._read_timeline_from_reader = legacy_json.read_otio_timeline_from_reader,
};

/// Mapping of Suffix to FormatAdapter
pub const FormatSuffix = struct {
    // TLA Formats
    pub const tla = TLA_Adapter;
    pub const tlac = TLA_Adapter;

    // TLB Formats
    pub const tlb = TLB_Adapter;
    pub const tlbc = TLB_Adapter;

    // bundle
    pub const tlz = TLA_Adapter;
    pub const tlcz = TLA_Adapter;

    // OTIO
    pub const otio = OTIO_Adapter;
};

// Utility
///////////////////////////////////////////////////////////////////////////////

/// Find the associated file format for a file
pub fn format_for_file(
    file_path: []const u8,
) !ascii.FileFormat
{
    // Check file extension to determine format
    const ext_start = std.mem.lastIndexOfScalar(
        u8,
        file_path,
        '.',
    ) orelse  return error.NoFileExtension;

    // Skip the leading dot
    const extension = file_path[ext_start + 1 ..];  

    return (
        std.meta.stringToEnum(ascii.FileFormat, extension) 
        orelse return error.UnsupportedFileFormat
    );

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
    format: ascii.FileFormat,
    options: MetadataOptions.Write,
    writer: *std.Io.Writer,
) !void
{
    const adapter = switch (format) {
        .tla => FormatSuffix.tla,
        else => return error.NotImplemented,
    };

    if (adapter._write_timeline_to_writer)
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
    format: ascii.FileFormat,
    metadata_mode: MetadataOptions.Read,
) !ascii.SerializableTimeline
{
    const adapter = switch (format) {
        .tla => FormatSuffix.tla,
        .tlb => FormatSuffix.tlb,
        .otio => FormatSuffix.otio,
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
    metadata_mode: MetadataOptions.Reader,
) ! ascii.SerializableTimeline
{
    const format = try format_for_file(file_path);

    // Handle .tlz separately since it manages its own file writing
    if (format == .tlz)
    {
        return error.UseBundleInterfaceForWritingBundles;
    }

    // For other formats, open file and write
    const file = try std.fs.cwd().createFile(file_path, .{});
    defer file.close();

    const file_reader_buffer: [16*1024]u8 = undefined;
    var file_reader = file.reader(file_reader_buffer);
    const reader = &file_reader.interface;

    try read_serializable_timeline_from_reader(
        allocator,
        format,
        metadata_mode,
        reader,
    );
}

pub fn read_timeline_from_file(
    allocator: std.mem.Allocator,
    file_path: []const u8,
    metadata_mode: MetadataOptions.Reader,
) !*schema.Timeline
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
