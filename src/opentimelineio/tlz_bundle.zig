//! TLZ Bundle - ZIP-based timeline archive format
//!
//! TLZ files are ZIP archives containing:
//! - version.txt: Format version string
//! - content.ziggy or content.tlfb: Timeline data
//! - media/: Directory containing media files (optional)

const std = @import("std");
const zip = std.zip;
const flate = std.compress.flate;

const utils = @import("tlz_bundle_utils.zig");
const serialization = @import("serialization.zig");
const binary_serialization_flatbufs = @import("binary_serialization_flatbufs.zig");
const ziggy = @import("ziggy");

// ----------------------------------------------------------------------------
// Public Types
// ----------------------------------------------------------------------------

/// Options for reading TLZ files
pub const ReadOptions = struct {
    /// If set, extract all files to this directory
    extract_to_directory: ?[]const u8 = null,
};

/// Options for writing TLZ files
pub const WriteOptions = struct {
    /// Format for the timeline content inside the bundle
    bundle_format: utils.BundleFormat = .ziggy,

    /// Policy for handling media references
    media_policy: utils.MediaReferencePolicy = .ErrorIfNotFile,

    /// If true, calculate sizes but don't write the file
    dryrun: bool = false,
};

// ----------------------------------------------------------------------------
// Error Types
// ----------------------------------------------------------------------------

pub const TlzError = error{
    /// No timeline content file found in archive
    NoContentFile,
    /// Invalid or missing version file
    InvalidVersion,
    /// Unsupported TLZ format version
    UnsupportedVersion,
    /// ZIP archive is corrupted or invalid
    InvalidArchive,
    /// Media file not found on disk (ErrorIfNotFile policy)
    MediaFileNotFound,
    /// Duplicate media basenames detected
    DuplicateBasename,
};

// ----------------------------------------------------------------------------
// Internal Types
// ----------------------------------------------------------------------------

/// Represents a file entry to be written to the ZIP archive
const ZipEntry = struct {
    /// Path within the archive (Unix-style)
    name: []const u8,
    /// Uncompressed file data
    data: []const u8,
    /// Whether to compress this entry
    compress: bool,
    /// CRC32 of uncompressed data
    crc32: u32,
    /// Size after compression (same as data.len if not compressed)
    compressed_size: u32,
    /// Offset of local file header in archive
    local_header_offset: u32,
};

// ----------------------------------------------------------------------------
// Public API
// ----------------------------------------------------------------------------

/// Read a TLZ file and return the timeline as SerializableTimeline
pub fn readFromFile(
    allocator: std.mem.Allocator,
    filepath: []const u8,
    options: ReadOptions,
) !serialization.SerializableTimeline
{
    // Open the ZIP file
    const file = try std.fs.cwd().openFile(filepath, .{});
    defer file.close();

    // Read entire file into memory for ZIP parsing
    const file_data = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(file_data);

    // Use std.zip.Iterator to find entries
    var file_reader = file.reader(null);
    var iterator = try zip.Iterator.init(&file_reader);

    var content_data: ?[]const u8 = null;
    var content_format: ?utils.BundleFormat = null;
    var version_found = false;

    // Iterate through ZIP entries
    while (try iterator.next())
        |entry|
    {
        const filename = entry.filename;

        if (std.mem.eql(u8, filename, utils.BUNDLE_VERSION_FILE))
        {
            version_found = true;
            // Optionally validate version here
        }
        else if (std.mem.eql(u8, filename, utils.BUNDLE_CONTENT_ZIGGY))
        {
            content_format = .ziggy;
            // Read the entry data
            var decompressed = std.ArrayList(u8).init(allocator);
            defer decompressed.deinit();

            try entry.extract(decompressed.writer());
            content_data = try decompressed.toOwnedSlice();
        }
        else if (std.mem.eql(u8, filename, utils.BUNDLE_CONTENT_TLFB))
        {
            content_format = .tlfb;
            // Read the entry data
            var decompressed = std.ArrayList(u8).init(allocator);
            defer decompressed.deinit();

            try entry.extract(decompressed.writer());
            content_data = try decompressed.toOwnedSlice();
        }

        // Handle extraction to directory if requested
        if (options.extract_to_directory)
            |extract_dir|
        {
            // Create directory if needed
            var dir = try std.fs.cwd().openDir(extract_dir, .{});
            defer dir.close();

            // Extract file
            try entry.extractToDir(dir);
        }
    }

    if (!version_found)
    {
        return TlzError.InvalidVersion;
    }

    if (content_data == null or content_format == null)
    {
        return TlzError.NoContentFile;
    }

    // Parse the content based on format
    const data = content_data.?;
    defer allocator.free(data);

    switch (content_format.?) {
        .ziggy => {
            return try ziggy.parseLeaky(
                serialization.SerializableTimeline,
                allocator,
                data,
                .{},
            );
        },
        .tlfb => {
            return try binary_serialization_flatbufs.deserialize_to_serializable_timeline(
                allocator,
                data,
                .{},
            );
        },
    }
}

/// Write a SerializableTimeline to a TLZ file
pub fn writeToFile(
    allocator: std.mem.Allocator,
    timeline: serialization.SerializableTimeline,
    filepath: []const u8,
    options: WriteOptions,
) !void
{
    // Use arena for temporary allocations
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    // Serialize timeline to bytes based on format using std.Io.Writer.Allocating
    var content_writer: std.Io.Writer.Allocating = .init(arena_alloc);
    defer content_writer.deinit();

    const content_name = switch (options.bundle_format) {
        .ziggy => utils.BUNDLE_CONTENT_ZIGGY,
        .tlfb => utils.BUNDLE_CONTENT_TLFB,
    };

    switch (options.bundle_format) {
        .ziggy => {
            try ziggy.stringify(
                timeline,
                .{
                    .whitespace = .space_4,
                    .emit_null_fields = false,
                },
                &content_writer.writer,
            );
        },
        .tlfb => {
            try binary_serialization_flatbufs.serialize_from_serializable_timeline(
                timeline,
                arena_alloc,
                &content_writer.writer,
            );
        },
    }

    const content_bytes = content_writer.writer.buffer[0..content_writer.writer.end];

    // Prepare version.txt content
    const version_data = utils.BUNDLE_VERSION;

    // Calculate CRC32 for each entry
    const version_crc = calculateCrc32(version_data);
    const content_crc = calculateCrc32(content_bytes);

    // For now, store uncompressed (simpler implementation)
    // TODO: Add deflate compression for content

    // If dryrun, just return without writing
    if (options.dryrun)
    {
        return;
    }

    // Create output file
    const file = try std.fs.cwd().createFile(filepath, .{});
    defer file.close();

    var buf: [16 * 1024]u8 = undefined;
    var buffered = file.writer(&buf);
    const writer = &buffered.interface;

    // Build entries list
    var entries: [2]ZipEntry = undefined;
    var current_offset: u32 = 0;

    // Entry 0: version.txt (uncompressed)
    entries[0] = .{
        .name = utils.BUNDLE_VERSION_FILE,
        .data = version_data,
        .compress = false,
        .crc32 = version_crc,
        .compressed_size = @intCast(version_data.len),
        .local_header_offset = current_offset,
    };
    current_offset += 30 + @as(u32, @intCast(entries[0].name.len)) +
        @as(u32, @intCast(version_data.len));

    // Entry 1: content.ziggy or content.tlfb (uncompressed for now)
    entries[1] = .{
        .name = content_name,
        .data = content_bytes,
        .compress = false,
        .crc32 = content_crc,
        .compressed_size = @intCast(content_bytes.len),
        .local_header_offset = current_offset,
    };
    current_offset += 30 + @as(u32, @intCast(entries[1].name.len)) +
        @as(u32, @intCast(content_bytes.len));

    // Write local file headers and data
    for (entries)
        |entry|
    {
        try writeLocalFileHeader(writer, entry);
        try writer.writeAll(entry.data);
    }

    // Record central directory start offset
    const cd_offset = current_offset;

    // Write central directory
    var cd_size: u32 = 0;
    for (entries)
        |entry|
    {
        try writeCentralDirectoryHeader(writer, entry);
        cd_size += 46 + @as(u32, @intCast(entry.name.len));
    }

    // Write end of central directory
    try writeEndRecord(writer, 2, cd_size, cd_offset);

    // Flush buffered writer - use end() to finalize
    try buffered.end();
}

// ----------------------------------------------------------------------------
// ZIP Writing Helpers
// ----------------------------------------------------------------------------

/// Calculate CRC32 checksum for data (ZIP uses CRC-32/ISO-HDLC)
fn calculateCrc32(
    data: []const u8,
) u32
{
    return std.hash.crc.Crc32IsoHdlc.hash(data);
}

/// Write a local file header to the output
fn writeLocalFileHeader(
    writer: anytype,
    entry: ZipEntry,
) !void
{
    // Local file header signature
    try writer.writeAll(&zip.local_file_header_sig);

    // Version needed to extract (2.0 for deflate)
    try writer.writeInt(u16, 20, .little);

    // General purpose bit flag (no flags)
    try writer.writeInt(u16, 0, .little);

    // Compression method
    const method: u16 = if (entry.compress) 8 else 0; // 8 = deflate, 0 = store
    try writer.writeInt(u16, method, .little);

    // Last mod file time (use fixed value for reproducibility)
    try writer.writeInt(u16, 0, .little);

    // Last mod file date (use fixed value for reproducibility)
    try writer.writeInt(u16, 0, .little);

    // CRC-32
    try writer.writeInt(u32, entry.crc32, .little);

    // Compressed size
    try writer.writeInt(u32, entry.compressed_size, .little);

    // Uncompressed size
    const uncompressed_size: u32 = @intCast(entry.data.len);
    try writer.writeInt(u32, uncompressed_size, .little);

    // File name length
    const name_len: u16 = @intCast(entry.name.len);
    try writer.writeInt(u16, name_len, .little);

    // Extra field length (none)
    try writer.writeInt(u16, 0, .little);

    // File name
    try writer.writeAll(entry.name);
}

/// Write a central directory file header
fn writeCentralDirectoryHeader(
    writer: anytype,
    entry: ZipEntry,
) !void
{
    // Central directory file header signature
    try writer.writeAll(&zip.central_file_header_sig);

    // Version made by (2.0, Unix)
    try writer.writeInt(u16, 0x0314, .little);

    // Version needed to extract (2.0)
    try writer.writeInt(u16, 20, .little);

    // General purpose bit flag
    try writer.writeInt(u16, 0, .little);

    // Compression method
    const method: u16 = if (entry.compress) 8 else 0;
    try writer.writeInt(u16, method, .little);

    // Last mod file time
    try writer.writeInt(u16, 0, .little);

    // Last mod file date
    try writer.writeInt(u16, 0, .little);

    // CRC-32
    try writer.writeInt(u32, entry.crc32, .little);

    // Compressed size
    try writer.writeInt(u32, entry.compressed_size, .little);

    // Uncompressed size
    const uncompressed_size: u32 = @intCast(entry.data.len);
    try writer.writeInt(u32, uncompressed_size, .little);

    // File name length
    const name_len: u16 = @intCast(entry.name.len);
    try writer.writeInt(u16, name_len, .little);

    // Extra field length
    try writer.writeInt(u16, 0, .little);

    // File comment length
    try writer.writeInt(u16, 0, .little);

    // Disk number start
    try writer.writeInt(u16, 0, .little);

    // Internal file attributes
    try writer.writeInt(u16, 0, .little);

    // External file attributes (Unix regular file with 644 permissions)
    try writer.writeInt(u32, 0x81A40000, .little);

    // Relative offset of local header
    try writer.writeInt(u32, entry.local_header_offset, .little);

    // File name
    try writer.writeAll(entry.name);
}

/// Write the end of central directory record
fn writeEndRecord(
    writer: anytype,
    entry_count: u16,
    cd_size: u32,
    cd_offset: u32,
) !void
{
    // End of central directory signature
    try writer.writeAll(&zip.end_record_sig);

    // Number of this disk
    try writer.writeInt(u16, 0, .little);

    // Disk where central directory starts
    try writer.writeInt(u16, 0, .little);

    // Number of central directory records on this disk
    try writer.writeInt(u16, entry_count, .little);

    // Total number of central directory records
    try writer.writeInt(u16, entry_count, .little);

    // Size of central directory
    try writer.writeInt(u32, cd_size, .little);

    // Offset of start of central directory
    try writer.writeInt(u32, cd_offset, .little);

    // Comment length
    try writer.writeInt(u16, 0, .little);
}

// ----------------------------------------------------------------------------
// Tests
// ----------------------------------------------------------------------------

test "tlz_bundle: module compiles"
{
    // Basic compilation test
    _ = ReadOptions{};
    _ = WriteOptions{};
    _ = ZipEntry{
        .name = "test.txt",
        .data = "hello",
        .compress = false,
        .crc32 = 0,
        .compressed_size = 5,
        .local_header_offset = 0,
    };
}

test "tlz_bundle: CRC32 calculation"
{
    // Test CRC32 with known value
    const data = "hello world";
    const crc = calculateCrc32(data);

    // CRC32 of "hello world" should be 0x0D4A1185
    try std.testing.expectEqual(@as(u32, 0x0D4A1185), crc);
}

test "tlz_bundle: write and verify ZIP structure"
{
    const allocator = std.testing.allocator;

    // Create a minimal SerializableTimeline
    const timeline = serialization.SerializableTimeline{
        .schema_version = 1,
        .name = "Test Timeline",
        .children = &.{},
        .presentation_space_discrete_partitions = .{},
        .metadata_map = null,
    };

    // Write to temp file
    const test_path = "/tmp/test_tlz_write.tlz";
    try writeToFile(allocator, timeline, test_path, .{});

    defer std.fs.cwd().deleteFile(test_path) catch {};

    // Verify file exists and has valid ZIP structure
    const file = try std.fs.cwd().openFile(test_path, .{});
    defer file.close();

    // Check first 4 bytes are ZIP local file header signature
    var sig: [4]u8 = undefined;
    _ = try file.read(&sig);
    try std.testing.expectEqualSlices(u8, &zip.local_file_header_sig, &sig);

    // Verify file size is reasonable (should have version.txt + content.ziggy)
    const stat = try file.stat();
    try std.testing.expect(stat.size > 100); // Should be more than just headers
}
