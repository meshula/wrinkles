//! TLZ Bundle - ZIP-based timeline archive format
//!
//! TLZ files are ZIP archives containing:
//! - version.txt: Format version string
//! - content.tla or content.tlfb: Timeline data
//! - media/: Directory containing media files (optional)

const std = @import("std");
const zip = std.zip;

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
    bundle_format: utils.BundleFormat = .tla,

    /// Policy for handling media references
    media_policy: utils.MediaReferencePolicy = .ErrorIfNotFile,

    /// If true, calculate sizes but don't write the file
    dryrun: bool = false,

    /// Base directory for resolving relative media paths
    media_base_dir: ?[]const u8 = null,
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

    var content_data: ?[]const u8 = null;
    var content_format: ?utils.BundleFormat = null;
    var version_found = false;

    // Find end record to get central directory info
    // Note: We implement our own finder because std.zip.EndRecord.findBuffer has a bug
    // in Zig 0.15.2 where it returns error.EndOfStream which is not in FindBufferError
    const end_record = find_end_record(file_data) orelse
        return TlzError.InvalidArchive;

    // Iterate through central directory entries
    var cd_offset: u64 = end_record.central_directory_offset;

    for (0..end_record.record_count_total)
        |_|
    {
        // Parse central directory file header
        if (cd_offset + @sizeOf(zip.CentralDirectoryFileHeader) > file_data.len)
        {
            return TlzError.InvalidArchive;
        }

        // Check signature
        if (!std.mem.eql(u8, file_data[cd_offset..][0..4], &zip.central_file_header_sig))
        {
            return TlzError.InvalidArchive;
        }

        // Parse header (skip signature which is 4 bytes)
        const header_ptr: *align(1) const zip.CentralDirectoryFileHeader =
            @ptrCast(file_data[cd_offset..][0..@sizeOf(zip.CentralDirectoryFileHeader)]);
        const header = header_ptr.*;

        // Get filename
        const filename_start = cd_offset + @sizeOf(zip.CentralDirectoryFileHeader);
        const filename_end = filename_start + header.filename_len;
        if (filename_end > file_data.len)
        {
            return TlzError.InvalidArchive;
        }
        const filename = file_data[filename_start..filename_end];

        // Process entry
        if (std.mem.eql(u8, filename, utils.BUNDLE_VERSION_FILE))
        {
            version_found = true;
        }
        else if (std.mem.eql(u8, filename, utils.BUNDLE_CONTENT_TLA))
        {
            content_format = .tla;
            content_data = try readEntryDataFromBuffer(
                allocator,
                file_data,
                header.local_file_header_offset,
            );
        }
        else if (std.mem.eql(u8, filename, utils.BUNDLE_CONTENT_TLFB))
        {
            content_format = .tlfb;
            content_data = try readEntryDataFromBuffer(
                allocator,
                file_data,
                header.local_file_header_offset,
            );
        }

        // Handle extraction to directory if requested
        if (options.extract_to_directory)
            |extract_dir|
        {
            var dir = try std.fs.cwd().openDir(extract_dir, .{});
            defer dir.close();

            const data = try readEntryDataFromBuffer(
                allocator,
                file_data,
                header.local_file_header_offset,
            );
            defer allocator.free(data);

            // Create parent directories if needed
            if (std.fs.path.dirname(filename))
                |parent|
            {
                try dir.makePath(parent);
            }

            // Write file
            const out_file = try dir.createFile(filename, .{});
            defer out_file.close();
            try out_file.writeAll(data);
        }

        // Move to next central directory entry
        cd_offset += @sizeOf(zip.CentralDirectoryFileHeader) +
            header.filename_len +
            header.extra_len +
            header.comment_len;
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
        .tla => {
            // ziggy.parseLeaky needs sentinel-terminated string
            const data_z = try allocator.dupeZ(u8, data);
            defer allocator.free(data_z);
            return try ziggy.parseLeaky(
                serialization.SerializableTimeline,
                allocator,
                data_z,
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

/// Find ZIP end record in buffer (workaround for std.zip bug in Zig 0.15.2)
fn find_end_record(buffer: []const u8) ?zip.EndRecord
{
    const pos = std.mem.lastIndexOf(u8, buffer, &zip.end_record_sig) orelse return null;
    if (pos + @sizeOf(zip.EndRecord) > buffer.len) return null;
    const record_ptr: *align(1) const zip.EndRecord = @ptrCast(buffer[pos..][0..@sizeOf(zip.EndRecord)]);
    return record_ptr.*;
}

/// Read entry data from ZIP archive buffer using local file header offset
fn readEntryDataFromBuffer(
    allocator: std.mem.Allocator,
    archive_data: []const u8,
    local_header_offset: u32,
) ![]const u8
{
    // Check signature
    if (!std.mem.eql(u8, archive_data[local_header_offset..][0..4], &zip.local_file_header_sig))
    {
        return TlzError.InvalidArchive;
    }

    // Parse local file header
    const header_ptr: *align(1) const zip.LocalFileHeader =
        @ptrCast(archive_data[local_header_offset..][0..@sizeOf(zip.LocalFileHeader)]);
    const header = header_ptr.*;

    // Calculate data offset
    const data_offset = local_header_offset +
        @sizeOf(zip.LocalFileHeader) +
        header.filename_len +
        header.extra_len;

    const compressed_data = archive_data[data_offset..][0..header.compressed_size];

    // Handle decompression based on compression method
    // TLZ files are written with store method (no compression) for simplicity
    switch (header.compression_method) {
        .store => {
            // No compression - just copy data
            return try allocator.dupe(u8, compressed_data);
        },
        else => {
            // We don't support compressed entries in TLZ files
            return error.UnsupportedCompressionMethod;
        },
    }
}

/// Media file entry for bundling
const MediaFile = struct {
    /// Original URI from the timeline
    source_uri: []const u8,
    /// Path on disk to the actual file
    disk_path: []const u8,
    /// Basename for the media/ directory
    basename: []const u8,
    /// File contents (loaded when bundling)
    data: []const u8,
};

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

    // Collect media files if not AllMissing policy
    var media_files: std.ArrayList(MediaFile) = .empty;
    var modified_timeline = timeline;

    if (options.media_policy != .AllMissing)
    {
        // Collect media references from timeline
        try collectMediaFiles(
            arena_alloc,
            &modified_timeline,
            &media_files,
            options.media_policy,
            options.media_base_dir,
        );
    }

    // Serialize timeline to bytes based on format using std.Io.Writer.Allocating
    var content_writer: std.Io.Writer.Allocating = .init(arena_alloc);
    defer content_writer.deinit();

    const content_name = switch (options.bundle_format) {
        .tla => utils.BUNDLE_CONTENT_TLA,
        .tlfb => utils.BUNDLE_CONTENT_TLFB,
    };

    switch (options.bundle_format) {
        .tla => {
            try ziggy.stringify(
                modified_timeline,
                .{
                    .whitespace = .space_4,
                    .emit_null_fields = false,
                },
                &content_writer.writer,
            );
        },
        .tlfb => {
            try binary_serialization_flatbufs.serialize_from_serializable_timeline(
                modified_timeline,
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

    // Calculate total number of entries (version + content + media files)
    const total_entries: u16 = @intCast(2 + media_files.items.len);

    // Build entries list dynamically
    var entries: std.ArrayList(ZipEntry) = .empty;

    var current_offset: u32 = 0;

    // Entry 0: version.txt (uncompressed)
    try entries.append(arena_alloc, .{
        .name = utils.BUNDLE_VERSION_FILE,
        .data = version_data,
        .compress = false,
        .crc32 = version_crc,
        .compressed_size = @intCast(version_data.len),
        .local_header_offset = current_offset,
    });
    current_offset += 30 + @as(u32, @intCast(utils.BUNDLE_VERSION_FILE.len)) +
        @as(u32, @intCast(version_data.len));

    // Entry 1: content.tla or content.tlfb (uncompressed for now)
    try entries.append(arena_alloc, .{
        .name = content_name,
        .data = content_bytes,
        .compress = false,
        .crc32 = content_crc,
        .compressed_size = @intCast(content_bytes.len),
        .local_header_offset = current_offset,
    });
    current_offset += 30 + @as(u32, @intCast(content_name.len)) +
        @as(u32, @intCast(content_bytes.len));

    // Add media file entries
    for (media_files.items)
        |media|
    {
        const media_path = try std.fmt.allocPrint(
            arena_alloc,
            "{s}/{s}",
            .{ utils.BUNDLE_DIR_NAME, media.basename },
        );
        const media_crc = calculateCrc32(media.data);

        try entries.append(arena_alloc, .{
            .name = media_path,
            .data = media.data,
            .compress = false,  // Media files stored uncompressed
            .crc32 = media_crc,
            .compressed_size = @intCast(media.data.len),
            .local_header_offset = current_offset,
        });
        current_offset += 30 + @as(u32, @intCast(media_path.len)) +
            @as(u32, @intCast(media.data.len));
    }

    // Write local file headers and data
    for (entries.items)
        |entry|
    {
        try writeLocalFileHeader(writer, entry);
        try writer.writeAll(entry.data);
    }

    // Record central directory start offset
    const cd_offset = current_offset;

    // Write central directory
    var cd_size: u32 = 0;
    for (entries.items)
        |entry|
    {
        try writeCentralDirectoryHeader(writer, entry);
        cd_size += 46 + @as(u32, @intCast(entry.name.len));
    }

    // Write end of central directory
    try writeEndRecord(writer, total_entries, cd_size, cd_offset);

    // Flush buffered writer - use end() to finalize
    try buffered.end();
}

/// Collect media files from the timeline and update references
fn collectMediaFiles(
    allocator: std.mem.Allocator,
    timeline: *serialization.SerializableTimeline,
    media_files: *std.ArrayList(MediaFile),
    policy: utils.MediaReferencePolicy,
    maybe_base_dir: ?[]const u8,
) !void
{
    // Process all children recursively
    for (timeline.children)
        |*child|
    {
        try collectMediaFromComposable(allocator, child, media_files, policy, maybe_base_dir);
    }
}

/// Recursively collect media from a composable
fn collectMediaFromComposable(
    allocator: std.mem.Allocator,
    composable: *serialization.SerializableComposable,
    media_files: *std.ArrayList(MediaFile),
    policy: utils.MediaReferencePolicy,
    maybe_base_dir: ?[]const u8,
) !void
{
    switch (composable.*) {
        .clip => |*clip| {
            if (clip.media.data_reference == .uri)
            {
                const uri = clip.media.data_reference.uri.target_uri;

                // Skip non-file URIs
                if (std.mem.startsWith(u8, uri, "file:///"))
                {
                    // Skip absolute file:/// URIs that don't exist locally
                    // These are typically placeholders
                }
                else if (!std.mem.startsWith(u8, uri, "http://") and
                         !std.mem.startsWith(u8, uri, "https://"))
                {
                    // Relative path - try to resolve it
                    const disk_path = if (maybe_base_dir)
                        |base_dir|
                        try std.fs.path.join(allocator, &.{ base_dir, uri })
                    else
                        uri;

                    // Check if file exists
                    const file_exists = blk: {
                        std.fs.cwd().access(disk_path, .{}) catch {
                            break :blk false;
                        };
                        break :blk true;
                    };

                    if (file_exists)
                    {
                        // Read the file
                        const file = try std.fs.cwd().openFile(disk_path, .{});
                        defer file.close();

                        const data = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
                        const basename = utils.getBasename(uri);

                        // Add to media files list
                        try media_files.append(allocator, .{
                            .source_uri = uri,
                            .disk_path = disk_path,
                            .basename = basename,
                            .data = data,
                        });

                        // Update the URI to point to media/ directory
                        clip.media.data_reference.uri.target_uri = try std.fmt.allocPrint(
                            allocator,
                            "{s}/{s}",
                            .{ utils.BUNDLE_DIR_NAME, basename },
                        );
                    }
                    else if (policy == .ErrorIfNotFile)
                    {
                        return TlzError.MediaFileNotFound;
                    }
                    // MissingIfNotFile: leave as-is
                }
            }
        },
        .track => |*track| {
            for (track.children)
                |*child|
            {
                try collectMediaFromComposable(allocator, child, media_files, policy, maybe_base_dir);
            }
        },
        .stack => |*stack| {
            for (stack.children)
                |*child|
            {
                try collectMediaFromComposable(allocator, child, media_files, policy, maybe_base_dir);
            }
        },
        .warp => |*warp| {
            try collectMediaFromComposable(allocator, warp.child, media_files, policy, maybe_base_dir);
        },
        .transition => |*transition| {
            for (transition.container.children)
                |*child|
            {
                try collectMediaFromComposable(allocator, child, media_files, policy, maybe_base_dir);
            }
        },
        .gap => {},
    }
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

    // Verify file size is reasonable (should have version.txt + content.tla)
    const stat = try file.stat();
    try std.testing.expect(stat.size > 100); // Should be more than just headers
}

test "tlz_bundle: media bundling with app.png"
{
    // Use arena allocator since ziggy.parseLeaky leaks by design
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Load the test timeline that references app.png
    const timeline_path = "test_files/simple_cut_with_media.tla";
    const timeline_file = std.fs.cwd().openFile(timeline_path, .{}) catch |err| {
        std.debug.print("Skipping test: could not open {s}: {}\n", .{ timeline_path, err });
        return;
    };
    defer timeline_file.close();

    const source = try timeline_file.readToEndAllocOptions(
        allocator,
        std.math.maxInt(u32),
        null,
        .@"1",
        0,
    );

    const timeline = try ziggy.parseLeaky(
        serialization.SerializableTimeline,
        allocator,
        source,
        .{},
    );

    // Write to /var/tmp with media bundling
    const test_path = "/var/tmp/test_media_bundle.tlz";
    try writeToFile(allocator, timeline, test_path, .{
        .bundle_format = .tla,
        .media_policy = .MissingIfNotFile,  // Don't error on missing files
        .media_base_dir = "test_files",  // Resolve relative paths from tla file location
    });

    defer std.fs.cwd().deleteFile(test_path) catch {};

    // Verify the bundle was created
    const bundle_file = try std.fs.cwd().openFile(test_path, .{});
    defer bundle_file.close();

    // Check it's a valid ZIP
    var sig: [4]u8 = undefined;
    _ = try bundle_file.read(&sig);
    try std.testing.expectEqualSlices(u8, &zip.local_file_header_sig, &sig);

    // Use unzip -l to verify contents (via child process)
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "unzip", "-l", test_path },
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    // Check that version.txt and content.tla are present
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "version.txt") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "content.tla") != null);

    // Check if app.png was bundled (only if it exists)
    if (std.mem.indexOf(u8, result.stdout, "media/app.png"))
        |_|
    {
        // Verify the media content is correct by extracting to a temp file
        const extract_dir = "/var/tmp/tlz_extract_test";
        std.fs.cwd().deleteTree(extract_dir) catch {};
        try std.fs.cwd().makePath(extract_dir);
        defer std.fs.cwd().deleteTree(extract_dir) catch {};

        const extract_result = try std.process.Child.run(.{
            .allocator = allocator,
            .argv = &.{ "unzip", "-o", "-d", extract_dir, test_path },
            .max_output_bytes = 1024 * 1024, // 1MB should be enough for listing
        });
        defer allocator.free(extract_result.stdout);
        defer allocator.free(extract_result.stderr);

        // Read extracted app.png
        const extracted_path = extract_dir ++ "/media/app.png";
        const extracted_file = try std.fs.cwd().openFile(extracted_path, .{});
        defer extracted_file.close();
        const extracted_data = try extracted_file.readToEndAlloc(allocator, std.math.maxInt(usize));
        defer allocator.free(extracted_data);

        // Read original app.png
        const original_file = try std.fs.cwd().openFile("app.png", .{});
        defer original_file.close();
        const original_data = try original_file.readToEndAlloc(allocator, std.math.maxInt(usize));
        defer allocator.free(original_data);

        // Compare
        try std.testing.expectEqualSlices(u8, original_data, extracted_data);
    }
}
