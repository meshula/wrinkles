const std = @import("std");

const schema = @import("../schema.zig");
const ascii = @import("ascii.zig");
const binary = @import("binary.zig");
const bundle = @import("bundle.zig");
const legacy_json = @import("legacy_json.zig");

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

pub const SerializableFormat = struct {
    suffix: []const u8,
    description: []const u8,

    // Timeline functions
    _write_timeline_to_writer: ?*const write_timeline_to_writer_fn = null,
    _read_timeline_from_reader: ?*const read_timeline_from_reader_fn = null,

    // Collection functions
    _write_collection_to_writer: ?*const write_collection_to_writer_fn = null,
    _read_collection_from_reader: ?*const read_collection_from_reader_fn = null,
};

// ----------------------------------------------------------------------------
// Bridging Functions
// ----------------------------------------------------------------------------

/// Bridge function for writing binary (TLB) format to a writer.
pub fn write_binary_serializable_to_writer(
    allocator: std.mem.Allocator,
    intermediate_tl: ascii.SerializableTimeline,
    writer: *std.Io.Writer,
    options: anytype,
) anyerror!void
{
    _ = options;
    return binary.serialize_from_serializable_timeline(
        intermediate_tl,
        allocator,
        writer,
    );
}

/// Bridge function for reading binary (TLB) format from a reader.
pub fn read_binary_timeline_from_reader(
    allocator: std.mem.Allocator,
    reader: *std.Io.Reader,
) anyerror!ascii.SerializableTimeline
{
    const buffer = try reader.readAlloc(
        allocator,
        std.math.maxInt(u32),
    );
    defer allocator.free(buffer);

    return try binary.deserialize_to_serializable_timeline(
        allocator,
        buffer,
        .{},
    );
}

/// Bridge function for reading OTIO JSON format from a reader.
/// Note: OTIO format is read-only; writing is not supported.
pub fn read_otio_timeline_from_reader(
    allocator: std.mem.Allocator,
    reader: *std.Io.Reader,
) anyerror!ascii.SerializableTimeline
{
    const buffer = try reader.readAlloc(
        allocator,
        std.math.maxInt(u32),
    );
    defer allocator.free(buffer);

    // Parse OTIO JSON to get a CompositionItemHandle
    const item = try legacy_json.read_from_string(
        allocator,
        buffer,
        .{},
    );

    // Convert the timeline to SerializableTimeline
    const timeline = item.timeline;
    return try ascii.SerializableTimeline.from(allocator, timeline);
}

// ----------------------------------------------------------------------------
// Collection Bridging Functions
// ----------------------------------------------------------------------------

/// Bridge function for writing ASCII collection (TLAC) format to a writer.
pub fn write_ascii_collection_to_writer(
    allocator: std.mem.Allocator,
    collection: ascii.SerializableCollection,
    writer: *std.Io.Writer,
    options: anytype,
) anyerror!void
{
    return ascii.write_collection_to_writer(
        allocator,
        collection,
        .tlca,
        .{ .metadata_mode = options.metadata_mode },
        writer,
    );
}

/// Bridge function for reading ASCII collection (TLAC) format from a reader.
pub fn read_ascii_collection_from_reader(
    allocator: std.mem.Allocator,
    reader: *std.Io.Reader,
) anyerror!ascii.SerializableCollection
{
    const buffer = try reader.readAlloc(
        allocator,
        std.math.maxInt(u32),
    );
    defer allocator.free(buffer);

    return try ascii.read_collection_from_buffer(
        allocator,
        buffer,
        .tlca,
    );
}

/// Bridge function for writing binary collection (TLCB) format to a writer.
pub fn write_binary_collection_to_writer(
    allocator: std.mem.Allocator,
    collection: ascii.SerializableCollection,
    writer: *std.Io.Writer,
    options: anytype,
) anyerror!void
{
    _ = options;
    return binary.serialize_collection(
        collection,
        allocator,
        writer,
    );
}

/// Bridge function for reading binary collection (TLCB) format from a reader.
pub fn read_binary_collection_from_reader(
    allocator: std.mem.Allocator,
    reader: *std.Io.Reader,
) anyerror!ascii.SerializableCollection
{
    const buffer = try reader.readAlloc(
        allocator,
        std.math.maxInt(u32),
    );
    defer allocator.free(buffer);

    return try binary.deserialize_collection(
        allocator,
        buffer,
    );
}

// ----------------------------------------------------------------------------
// Format Adapters
// ----------------------------------------------------------------------------

pub const TLA_Adapter: SerializableFormat = .{
    .suffix = "tla",
    .description = "Native ascii format with a timeline root",

    ._write_timeline_to_writer = ascii.write_ascii_serializable_to_writer,
    ._read_timeline_from_reader = ascii.read_timeline_from_reader,
};

pub const TLAC_Adapter: SerializableFormat = .{
    .suffix = "tlac",
    .description = "Native ascii format with a collection root",

    // Collection format - no timeline functions
    ._write_timeline_to_writer = null,
    ._read_timeline_from_reader = null,

    ._write_collection_to_writer = write_ascii_collection_to_writer,
    ._read_collection_from_reader = read_ascii_collection_from_reader,
};

pub const TLB_Adapter: SerializableFormat = .{
    .suffix = "tlb",
    .description = "Native binary format (FlatBuffers) with a timeline root",

    ._write_timeline_to_writer = write_binary_serializable_to_writer,
    ._read_timeline_from_reader = read_binary_timeline_from_reader,
};

pub const TLBC_Adapter: SerializableFormat = .{
    .suffix = "tlbc",
    .description = "Native binary format (FlatBuffers) with a collection root",

    // Collection format - no timeline functions
    ._write_timeline_to_writer = null,
    ._read_timeline_from_reader = null,

    ._write_collection_to_writer = write_binary_collection_to_writer,
    ._read_collection_from_reader = read_binary_collection_from_reader,
};

pub const OTIO_Adapter: SerializableFormat = .{
    .suffix = "otio",
    .description = "OpenTimelineIO v1 JSON format (read-only)",

    // OTIO is read-only - writing is not supported
    ._write_timeline_to_writer = null,
    ._read_timeline_from_reader = read_otio_timeline_from_reader,
};

pub const SerializableRoot = enum {
    timeline,
    collection,
};

// Mapping of Suffix to FormatAdapter
pub const FormatSuffix = struct {
    pub const tla = TLA_Adapter;
    pub const tlac = TLAC_Adapter;
    pub const tlb = TLB_Adapter;
    pub const tlbc = TLBC_Adapter;
    pub const otio = OTIO_Adapter;
};

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


    // switch (format) {
    //     .tla => {
    //         try write_tla_with_metadata_mode(
    //             allocator,
    //             intermediate_tl,
    //             options.metadata_mode,
    //             writer,
    //         );
    //     },
    //     .tlb => {
    //         try binary.serialize_from_serializable_timeline(
    //             intermediate_tl,
    //             allocator,
    //             writer,
    //         );
    //     },
    //     .otio => {
    //         return error.OtioJsonWriteNotSupported;
    //     },
    //     .tlz => {
    //         return error.TlzRequiresFileAccess;
    //     },
    //     .tlca, .tlcb => {
    //         // Collection formats are not timelines - use write_collection_to_writer instead
    //         return error.NotATimelineFormat;
    //     },
    // }
}
