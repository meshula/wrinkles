//! TLZ/TLCZ Bundle - ZIP-based timeline and collection archive format
//!
//! TLZ files are ZIP archives containing:
//! - version.txt: Format version string
//! - content.tla or content.tlb: Timeline data
//! - media/: Directory containing media files (optional)
//!
//! TLCZ files are ZIP archives containing:
//! - version.txt: Format version string
//! - content.tlca or content.tlcb: Collection data
//! - media/: Directory containing media files (optional)
//!
//! Bundles are containers, not codecs: `read_root_from_file` and
//! `write_root_to_file` handle the ZIP archive and media, and encode or
//! decode the content entry through `adapter.read_root` / `write_root`.
//! When writing, relative media URIs are resolved against
//! `BundleOptions.media_base_dir`; the caller's data is not modified.

const std = @import("std");
const test_output = @import("test_output");
const zip = std.zip;

const utils = @import("bundle_utils.zig");
const serializable = @import("serializable.zig");
const format_m = @import("format.zig");
const adapter = @import("adapter.zig");

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
    /// Media file not found on disk (error_if_not_file policy)
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

/// Read a .tlz or .tlcz bundle.  The content entry is decoded with
/// `adapter.read_root`, so the result owns its memory, honors `options`, and
/// is at the current schema version.
pub fn read_root_from_file(
    allocator: std.mem.Allocator,
    io: std.Io,
    filepath: []const u8,
    bundle_format: format_m.FileFormat,
    options: format_m.ReadOptions,
) !adapter.SerializableRoot
{
    const bundle_desc = adapter.descriptor(bundle_format);
    std.debug.assert(bundle_desc.is_bundle);

    const file = try std.Io.Dir.cwd().openFile(io, filepath, .{});
    defer file.close(io);

    var reader_buf: [4096]u8 = undefined;
    var file_reader = file.reader(io, &reader_buf);
    const file_data = try file_reader.interface.allocRemaining(
        allocator,
        .unlimited,
    );
    defer allocator.free(file_data);

    var maybe_content: ?[]const u8 = null;
    defer if (maybe_content)
        |content|
    {
        allocator.free(content);
    };
    var maybe_content_format: ?format_m.FileFormat = null;
    var version_found = false;

    // Note: We implement our own finder because std.zip.EndRecord.findBuffer
    // has a bug in Zig 0.15.2 where it returns error.EndOfStream which is not
    // in FindBufferError
    // @TODO ^ double check this
    const end_record = find_end_record(file_data) orelse
        return TlzError.InvalidArchive;

    const maybe_extract_dir: ?std.Io.Dir = if (options.extract_to_directory)
        |extract_path|
        try std.Io.Dir.cwd().openDir(io, extract_path, .{})
    else
        null;
    defer if (maybe_extract_dir)
        |dir|
    {
        dir.close(io);
    };

    var cd_offset: usize = end_record.central_directory_offset;

    for (0..end_record.record_count_total)
        |_|
    {
        if (
            cd_offset + @sizeOf(zip.CentralDirectoryFileHeader)
            > file_data.len
        )
        {
            return TlzError.InvalidArchive;
        }

        if (!std.mem.eql(u8, file_data[cd_offset..][0..4], &zip.central_file_header_sig))
        {
            return TlzError.InvalidArchive;
        }

        const header_ptr: *align(1) const zip.CentralDirectoryFileHeader =
            @ptrCast(file_data[cd_offset..][0..@sizeOf(zip.CentralDirectoryFileHeader)]);
        const header = header_ptr.*;

        const filename_start = (
            cd_offset + @sizeOf(zip.CentralDirectoryFileHeader)
        );
        const filename_end = filename_start + header.filename_len;
        if (filename_end > file_data.len)
        {
            return TlzError.InvalidArchive;
        }
        const filename = file_data[filename_start..filename_end];

        if (std.mem.eql(u8, filename, utils.BUNDLE_VERSION_FILE))
        {
            version_found = true;
        }
        else if (content_entry_format(filename))
            |entry_format|
        {
            if (
                adapter.descriptor(entry_format).is_collection
                != bundle_desc.is_collection
            )
            {
                return TlzError.NoContentFile;
            }
            if (maybe_content)
                |previous|
            {
                allocator.free(previous);
                maybe_content = null;
            }
            maybe_content = try readEntryDataFromBuffer(
                allocator,
                file_data,
                header.local_file_header_offset,
            );
            maybe_content_format = entry_format;
        }

        if (maybe_extract_dir)
            |dir|
        {
            const data = try readEntryDataFromBuffer(
                allocator,
                file_data,
                header.local_file_header_offset,
            );
            defer allocator.free(data);

            if (std.fs.path.dirname(filename))
                |parent|
            {
                try dir.createDirPath(io, parent);
            }

            const out_file = try dir.createFile(io, filename, .{});
            defer out_file.close(io);
            var extract_write_buf: [8 * 1024]u8 = undefined;
            var extract_writer = out_file.writer(io, &extract_write_buf);
            try extract_writer.interface.writeAll(data);
            try extract_writer.end();
        }

        cd_offset += @sizeOf(zip.CentralDirectoryFileHeader) +
            header.filename_len +
            header.extra_len +
            header.comment_len;
    }

    if (!version_found)
    {
        return TlzError.InvalidVersion;
    }

    const content = maybe_content orelse return TlzError.NoContentFile;
    var content_reader: std.Io.Reader = .fixed(content);
    return try adapter.read_root(
        allocator,
        &content_reader,
        maybe_content_format.?,
        options,
    );
}

/// Write a .tlz or .tlcz bundle.  The content entry is encoded with
/// `adapter.write_root` in `options.bundle_options.content_format`.
///
/// Media references are resolved per `bundle_options.media_policy`; found
/// files are copied into media/ and their URIs rewritten in the bundled
/// content.  `root` is not modified.
pub fn write_root_to_file(
    allocator: std.mem.Allocator,
    io: std.Io,
    root: adapter.SerializableRoot,
    filepath: []const u8,
    bundle_format: format_m.FileFormat,
    options: format_m.WriteOptions,
) !void
{
    const bundle_desc = adapter.descriptor(bundle_format);
    std.debug.assert(bundle_desc.is_bundle);

    const bundle_opts = (
        options.bundle_options orelse format_m.WriteOptions.BundleOptions{}
    );

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    const content_format: format_m.FileFormat = switch (bundle_opts.content_format) {
        .tla => if (bundle_desc.is_collection) .tlca else .tla,
        .tlb => if (bundle_desc.is_collection) .tlcb else .tlb,
    };
    const content_name = content_entry_name(content_format);

    // Media URIs are rewritten in place for encoding and restored on exit,
    // so the caller's data is unchanged afterwards.
    var restores: std.ArrayList(UriRestore) = .empty;
    defer for (restores.items)
        |restore|
    {
        restore.slot.* = restore.original;
    };

    var media_files: std.ArrayList(MediaFile) = .empty;
    var working = root;

    if (bundle_opts.media_policy != .all_missing)
    {
        var collector: MediaCollector = .{
            .allocator = arena_alloc,
            .io = io,
            .media_files = &media_files,
            .restores = &restores,
            .policy = bundle_opts.media_policy,
            .maybe_base_dir = bundle_opts.media_base_dir,
        };
        switch (working) {
            .timeline => |*tl| try collector.walk_timeline(tl),
            .collection => |*coll| try collector.walk_collection(coll),
        }
    }

    var content_writer: std.Io.Writer.Allocating = .init(arena_alloc);
    defer content_writer.deinit();
    try adapter.write_root(
        arena_alloc,
        working,
        &content_writer.writer,
        content_format,
        options,
    );
    const content_bytes = content_writer.written();

    const version_data = utils.BUNDLE_VERSION;

    const version_crc = calculateCrc32(version_data);
    const content_crc = calculateCrc32(content_bytes);

    if (bundle_opts.dryrun)
    {
        return;
    }

    const file = try std.Io.Dir.cwd().createFile(io, filepath, .{});
    defer file.close(io);

    var buf: [16 * 1024]u8 = undefined;
    var buffered = file.writer(io, &buf);
    const writer = &buffered.interface;

    // version + content + media files
    const total_entries: u16 = @intCast(2 + media_files.items.len);

    var entries: std.ArrayList(ZipEntry) = .empty;

    var current_offset: u32 = 0;

    // Entry 0: version.txt (uncompressed)
    try entries.append(
        arena_alloc,
        .{
            .name = utils.BUNDLE_VERSION_FILE,
            .data = version_data,
            .compress = false,
            .crc32 = version_crc,
            .compressed_size = @intCast(version_data.len),
            .local_header_offset = current_offset,
        },
    );
    current_offset += 30 + @as(u32, @intCast(utils.BUNDLE_VERSION_FILE.len)) +
        @as(u32, @intCast(version_data.len));

    // Entry 1: content (uncompressed)
    try entries.append(
        arena_alloc,
        .{
            .name = content_name,
            .data = content_bytes,
            .compress = false,
            .crc32 = content_crc,
            .compressed_size = @intCast(content_bytes.len),
            .local_header_offset = current_offset,
        },
    );
    current_offset += 30 + @as(u32, @intCast(content_name.len)) +
        @as(u32, @intCast(content_bytes.len));

    for (media_files.items)
        |media|
    {
        const media_path = try std.fmt.allocPrint(
            arena_alloc,
            "{s}/{s}",
            .{ utils.BUNDLE_DIR_NAME, media.basename },
        );
        const media_crc = calculateCrc32(media.data);

        try entries.append(
            arena_alloc,
            .{
                .name = media_path,
                .data = media.data,
                .compress = false,
                .crc32 = media_crc,
                .compressed_size = @intCast(media.data.len),
                .local_header_offset = current_offset,
            },
        );
        current_offset += 30 + @as(u32, @intCast(media_path.len)) +
            @as(u32, @intCast(media.data.len));
    }

    for (entries.items)
        |entry|
    {
        try writeLocalFileHeader(writer, entry);
        try writer.writeAll(entry.data);
    }

    const cd_offset = current_offset;

    var cd_size: u32 = 0;
    for (entries.items)
        |entry|
    {
        try writeCentralDirectoryHeader(writer, entry);
        cd_size += 46 + @as(u32, @intCast(entry.name.len));
    }

    try writeEndRecord(writer, total_entries, cd_size, cd_offset);

    try buffered.end();
}

/// The format of a bundle content entry, or null if `filename` is not one.
fn content_entry_format(
    filename: []const u8,
) ?format_m.FileFormat
{
    const names = .{
        .{ utils.BUNDLE_CONTENT_TLA, format_m.FileFormat.tla },
        .{ utils.BUNDLE_CONTENT_TLB, format_m.FileFormat.tlb },
        .{ utils.BUNDLE_CONTENT_TLCA, format_m.FileFormat.tlca },
        .{ utils.BUNDLE_CONTENT_TLCB, format_m.FileFormat.tlcb },
    };
    inline for (names)
        |entry|
    {
        if (std.mem.eql(u8, filename, entry[0]))
        {
            return entry[1];
        }
    }
    return null;
}

/// The bundle entry name for content in `format`.
fn content_entry_name(
    format: format_m.FileFormat,
) []const u8
{
    return switch (format) {
        .tla => utils.BUNDLE_CONTENT_TLA,
        .tlb => utils.BUNDLE_CONTENT_TLB,
        .tlca => utils.BUNDLE_CONTENT_TLCA,
        .tlcb => utils.BUNDLE_CONTENT_TLCB,
        .tlz, .tlcz, .otio => unreachable,
    };
}

/// Find ZIP end record in buffer (workaround for std.zip bug in Zig 0.15.2)
fn find_end_record(
    buffer: []const u8,
) ?zip.EndRecord
{
    const pos = std.mem.lastIndexOf(
        u8,
        buffer,
        &zip.end_record_sig,
    ) orelse return null;
    if (pos + @sizeOf(zip.EndRecord) > buffer.len)
    {
        return null;
    }
    const record_ptr: *align(1) const zip.EndRecord = (
        @ptrCast(buffer[pos..][0..@sizeOf(zip.EndRecord)])
    );
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

    const compressed_data = (
        archive_data[data_offset..][0..header.compressed_size]
    );

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

/// A URI field rewritten for bundling, and the value to restore.
const UriRestore = struct {
    slot: *[]const u8,
    original: []const u8,
};

/// Walks a serializable root, loads referenced media files and rewrites
/// their URIs to point into media/, recording each rewrite for restoration.
const MediaCollector = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    media_files: *std.ArrayList(MediaFile),
    restores: *std.ArrayList(UriRestore),
    policy: utils.MediaReferencePolicy,
    maybe_base_dir: ?[]const u8,

    fn walk_timeline(
        self: *@This(),
        timeline: *serializable.SerializableTimeline,
    ) !void
    {
        try self.walk_children(timeline.children);
    }

    fn walk_collection(
        self: *@This(),
        collection: *serializable.SerializableCollection,
    ) !void
    {
        for (collection.children)
            |*child|
        {
            switch (child.*) {
                .timeline => |*tl| try self.walk_timeline(tl),
                .clip => |*cl| try self.walk_clip(cl),
                .track => |*tr| try self.walk_children(tr.children),
                .stack => |*st| try self.walk_children(st.children),
                .warp => |*wp| try self.walk_composable(wp.child),
                .transition => |*tx| try self.walk_children(tx.container.children),
                .gap => {},
            }
        }
    }

    fn walk_children(
        self: *@This(),
        children: []serializable.SerializableComposable,
    ) anyerror!void
    {
        for (children)
            |*child|
        {
            try self.walk_composable(child);
        }
    }

    fn walk_composable(
        self: *@This(),
        composable: *serializable.SerializableComposable,
    ) anyerror!void
    {
        switch (composable.*) {
            .clip => |*cl| try self.walk_clip(cl),
            .track => |*tr| try self.walk_children(tr.children),
            .stack => |*st| try self.walk_children(st.children),
            .warp => |*wp| try self.walk_composable(wp.child),
            .transition => |*tx| try self.walk_children(tx.container.children),
            .gap => {},
        }
    }

    fn walk_clip(
        self: *@This(),
        clip: *serializable.SerializableClip,
    ) !void
    {
    if (clip.media.data_reference == .uri)
    {
        const uri = clip.media.data_reference.uri.target_uri;

        // Skip non-file URIs
        if (std.mem.startsWith(u8, uri, "file:///"))
        {
            // Skip absolute file:/// URIs that don't exist locally
            // These are typically placeholders
        }
        else if (
            !std.mem.startsWith(u8, uri, "http://")
        and !std.mem.startsWith(u8, uri, "https://")
        )
        {
            // Relative path - try to resolve it
            const disk_path = (
                if (self.maybe_base_dir)
                |base_dir|
                    try std.fs.path.join(
                        self.allocator,
                        &.{ base_dir, uri },
                    )
                else uri
            );

            // Check if file exists
            const file_exists = blk: {
                std.Io.Dir.cwd().access(self.io, disk_path, .{}) catch {
                    break :blk false;
                };
                break :blk true;
            };

            if (file_exists)
            {
                // Read the file
                const file = try std.Io.Dir.cwd().openFile(
                    self.io,
                    disk_path,
                    .{},
                );
                defer file.close(self.io);

                var media_read_buf: [4096]u8 = undefined;
                var file_reader = file.reader(self.io, &media_read_buf);
                const data = try file_reader.interface.allocRemaining(
                    self.allocator,
                    .unlimited,
                );
                const basename = utils.get_basename(uri);

                // Add to media files list
                try self.media_files.append(
                    self.allocator,
                    .{
                        .source_uri = uri,
                        .disk_path = disk_path,
                        .basename = basename,
                        .data = data,
                    },
                );

                // Point the URI at the media/ directory; restored after
                // the bundle is written.
                try self.restores.append(
                    self.allocator,
                    .{
                        .slot = &clip.media.data_reference.uri.target_uri,
                        .original = uri,
                    },
                );
                clip.media.data_reference.uri.target_uri = try std.fmt.allocPrint(
                    self.allocator,
                    "{s}/{s}",
                    .{ utils.BUNDLE_DIR_NAME, basename },
                );
            }
            else if (self.policy == .error_if_not_file)
            {
                return TlzError.MediaFileNotFound;
            }
            // missing_if_not_file: leave as-is
        }
    }
    }
};

// ----------------------------------------------------------------------------
// ZIP Writing Helpers
// ----------------------------------------------------------------------------

/// Calculate CRC32 checksum for data (ZIP uses CRC-32/ISO-HDLC)
fn calculateCrc32(
    data: []const u8,
) u32
{
    return std.hash.Crc32.hash(data);
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
    // 8 = deflate, 0 = store
    const method: u16 = if (entry.compress) 8 else 0;
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
    const io = std.testing.io;

    // Create a minimal SerializableTimeline
    const timeline = serializable.SerializableTimeline{
        .schema_version = 1,
        .name = "Test Timeline",
        .children = &.{},
        .presentation_space_discrete_partitions = .{},
        .metadata_map = null,
    };

    // Write to temp file
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [test_output.MAX_PATH_BYTES]u8 = undefined;
    const test_path = try test_output.tmp_file_path(
        &tmp,
        &path_buf,
        "test_tlz_write.tlz",
    );
    try write_root_to_file(
        allocator,
        io,
        .{ .timeline = timeline },
        test_path,
        .tlz,
        .{},
    );


    // Verify file exists and has valid ZIP structure
    const file = try std.Io.Dir.cwd().openFile(io, test_path, .{});
    defer file.close(io);

    // Check first 4 bytes are ZIP local file header signature
    var sig: [4]u8 = undefined;
    const bytes_read = try file.readPositionalAll(io, &sig, 0);
    try std.testing.expectEqual(@as(usize, 4), bytes_read);
    try std.testing.expectEqualSlices(u8, &zip.local_file_header_sig, &sig);

    // Verify file size is reasonable (should have version.txt + content.tla)
    const stat = try file.stat(io);
    // Should be more than just headers
    try std.testing.expect(stat.size > 100);
}

/// The URI of the first clip with a URI data reference, if any.
fn first_clip_uri(
    children: []serializable.SerializableComposable,
) ?[]const u8
{
    for (children)
        |child|
    {
        switch (child) {
            .clip => |cl| if (cl.media.data_reference == .uri)
            {
                return cl.media.data_reference.uri.target_uri;
            },
            .track => |tr| if (first_clip_uri(tr.children))
                |uri|
            {
                return uri;
            },
            .stack => |st| if (first_clip_uri(st.children))
                |uri|
            {
                return uri;
            },
            else => {},
        }
    }
    return null;
}

test "tlz_bundle: media bundling with app.png"
{
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    // Load the test timeline that references app.png
    var root = try adapter.read_root_from_file(
        allocator,
        io,
        "test_files/simple_cut_with_media.tla",
        .tla,
        .{},
    );
    defer root.deinit(allocator);

    const original_uri = try allocator.dupe(
        u8,
        first_clip_uri(root.timeline.children).?,
    );
    defer allocator.free(original_uri);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [test_output.MAX_PATH_BYTES]u8 = undefined;
    const test_path = try test_output.tmp_file_path(
        &tmp,
        &path_buf,
        "test_media_bundle.tlz",
    );
    try write_root_to_file(
        allocator,
        io,
        root,
        test_path,
        .tlz,
        .{
            .bundle_options = .{
                .content_format = .tla,
                .media_policy = .missing_if_not_file,
                // Resolve relative paths from tla file location
                .media_base_dir = "test_files",
            },
        },
    );

    // The caller's data is unchanged by bundling.
    try std.testing.expectEqualStrings(
        original_uri,
        first_clip_uri(root.timeline.children).?,
    );

    // Verify ZIP structure
    const bundle_file = try std.Io.Dir.cwd().openFile(io, test_path, .{});
    defer bundle_file.close(io);

    var sig: [4]u8 = undefined;
    const bytes_read = try bundle_file.readPositionalAll(io, &sig, 0);
    try std.testing.expectEqual(@as(usize, 4), bytes_read);
    try std.testing.expectEqualSlices(u8, &zip.local_file_header_sig, &sig);

    const stat = try bundle_file.stat(io);
    try std.testing.expect(stat.size > 100);

    // Read the bundle back: the bundled URI points into media/.
    var bundled = try read_root_from_file(allocator, io, test_path, .tlz, .{});
    defer bundled.deinit(allocator);

    const bundled_uri = first_clip_uri(bundled.timeline.children).?;
    try std.testing.expect(
        std.mem.startsWith(u8, bundled_uri, utils.BUNDLE_DIR_NAME ++ "/")
    );
    try std.testing.expectEqualStrings(
        utils.get_basename(original_uri),
        utils.get_basename(bundled_uri),
    );
}
