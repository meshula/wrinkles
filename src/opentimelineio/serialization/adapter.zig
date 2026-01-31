//! High level adapter interface which interprets file types and dispatches to
//! format implementations.
//!
//! Public interface:
//!
//! // Timeline Root
//!
//! adapters.read_timeline_from_file
//! adapters.read_timeline_from_reader
//!
//! adapters.write_timeline_to_file
//! adapters.write_timeline_to_writer
//!
//! // Collection Root
//!
//! adapters.read_collection_from_file
//! adapters.read_collection_from_reader
//!
//! adapters.write_collection_to_file
//! adapters.write_collection_to_writer
//!
//! Supports TLA, TLAC, TLB, TLBC, TLZ, TLCZ, and (read only) .otio.

const std = @import("std");

const schema = @import("../schema.zig");
const ascii = @import("ascii.zig");
const binary = @import("binary.zig");
const bundle = @import("bundle.zig");
const legacy_json = @import("legacy_json.zig");

// Interface function prototypes
///////////////////////////////////////////////////////////////////////////////

const write_timeline_to_writer_fn = fn (
        allocator: std.mem.Allocator,
        ser_timeline: ascii.SerializableTimeline,
        writer: *std.Io.Writer,
        options: anytype,
) anyerror!void;

pub const read_timeline_from_reader_fn = fn (
    allocator: std.mem.Allocator,
    reader: *std.Io.Reader,
) anyerror!ascii.SerializableTimeline;

const write_collection_to_writer_fn = fn (
        allocator: std.mem.Allocator,
        collection: ascii.SerializableCollection,
        writer: *std.Io.Writer,
        options: anytype,
) anyerror!void;

pub const read_collection_from_reader_fn = fn (
    allocator: std.mem.Allocator,
    reader: *std.Io.Reader,
) anyerror!ascii.SerializableCollection;

/// Bundles up interface functions to a given file format
pub const SerializableFormat = struct {
    description: []const u8,

    // Timeline functions
    _write_timeline_to_writer: ?*const write_timeline_to_writer_fn = null,
    _read_timeline_from_reader: ?*const read_timeline_from_reader_fn = null,

    // Collection functions
    _write_collection_to_writer: ?*const write_collection_to_writer_fn = null,
    _read_collection_from_reader: ?*const read_collection_from_reader_fn = null,
};

// ----------------------------------------------------------------------------
// Format Definitions
// ----------------------------------------------------------------------------

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

    // OTIO
    pub const otio = OTIO_Adapter;
};

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
    options: ascii.WriteOptions,
) !void
{
    // Check file extension to determine format
    const ext_start = std.mem.lastIndexOfScalar(
        u8,
        file_path,
        '.',
    ) orelse  return error.NoFileExtension;

    // Skip the leading dot
    const extension = file_path[ext_start + 1 ..];  

    const format = (
        std.meta.stringToEnum(ascii.FileFormat, extension) 
        orelse return error.UnsupportedFileFormat
    );

    // Handle .tlz separately since it manages its own file writing
    if (format == .tlz)
    {
        // @TODO: clean up bundle
        try bundle.writeToFile(
            allocator,
            intermediate_tl,
            file_path,
            .{
                .bundle_format = options.bundle_format,
                .media_policy = options.media_policy,
                .media_base_dir = options.media_base_dir,
            },
        );
        return;
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
        options,
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
    options: ascii.WriteOptions,
    writer: anytype,
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
    options: ascii.WriteOptions,
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
        options,
    );
}

