//! Output locations for files written by unit tests.
//!
//! Two kinds of files are written by tests:
//!
//! * **Artifacts** meant for manual inspection (dot graphs, wavs, curve
//!   json).  Use `ArtifactDir`: by default these go to a `std.testing.tmpDir`
//!   that is removed when the test finishes, so tests run anywhere.  Pass
//!   `-Dtest_data_out_dir=<path>` to write them to `<path>` and keep them.
//!
//! * **Scratch files** a test writes and reads back.  Use
//!   `std.testing.tmpDir` directly, and `tmp_dir_path` to get a cwd-relative
//!   path to it for APIs that take file paths.

const std = @import("std");
const build_options = @import("build_options");

/// Directory configured with `-Dtest_data_out_dir`, if any.
pub const MAYBE_CONFIGURED_DIR: ?[]const u8 = build_options.test_data_out_dir;

/// Buffer size large enough for any path produced by this module.
pub const MAX_PATH_BYTES = std.fs.max_path_bytes;

/// Directory for test artifacts meant for manual inspection.
pub const ArtifactDir = struct {
    /// Set when no directory was configured and a temporary one is in use.
    maybe_tmp: ?std.testing.TmpDir,
    path_buf: [MAX_PATH_BYTES]u8,
    path_len: usize,

    /// Use the configured directory (creating it if needed), or a fresh
    /// temporary directory if none was configured.
    pub fn init(
        io: std.Io,
    ) !ArtifactDir
    {
        var result: ArtifactDir = .{
            .maybe_tmp = null,
            .path_buf = undefined,
            .path_len = 0,
        };

        if (MAYBE_CONFIGURED_DIR)
            |configured_dir|
        {
            try std.Io.Dir.cwd().createDirPath(io, configured_dir);
            result.path_len = (
                try std.fmt.bufPrint(&result.path_buf, "{s}", .{configured_dir})
            ).len;
        }
        else
        {
            result.maybe_tmp = std.testing.tmpDir(.{});
            result.path_len = (
                try tmp_dir_path(&result.maybe_tmp.?, &result.path_buf)
            ).len;
        }

        return result;
    }

    /// Remove the temporary directory, if one was used.  Files written to a
    /// configured directory are kept.
    pub fn deinit(
        self: *@This(),
    ) void
    {
        if (self.maybe_tmp)
            |*tmp|
        {
            tmp.cleanup();
        }
        self.* = undefined;
    }

    /// Path of the directory itself.
    pub fn dir_path(
        self: *const @This(),
    ) []const u8
    {
        return self.path_buf[0..self.path_len];
    }

    /// Path of `file_name` inside the directory, written into `buf`.
    pub fn file_path(
        self: *const @This(),
        buf: []u8,
        file_name: []const u8,
    ) ![]const u8
    {
        return std.fmt.bufPrint(
            buf,
            "{s}" ++ std.fs.path.sep_str ++ "{s}",
            .{ self.dir_path(), file_name },
        );
    }
};

/// Cwd-relative path of a `std.testing.TmpDir`, written into `buf`.
pub fn tmp_dir_path(
    tmp: *const std.testing.TmpDir,
    buf: []u8,
) ![]const u8
{
    const sep = std.fs.path.sep_str;
    return std.fmt.bufPrint(
        buf,
        ".zig-cache" ++ sep ++ "tmp" ++ sep ++ "{s}",
        .{ &tmp.sub_path },
    );
}

/// Cwd-relative path of `file_name` inside a `std.testing.TmpDir`, written
/// into `buf`.
pub fn tmp_file_path(
    tmp: *const std.testing.TmpDir,
    buf: []u8,
    file_name: []const u8,
) ![]const u8
{
    var dir_buf: [MAX_PATH_BYTES]u8 = undefined;
    const dir = try tmp_dir_path(tmp, &dir_buf);
    return std.fmt.bufPrint(
        buf,
        "{s}" ++ std.fs.path.sep_str ++ "{s}",
        .{ dir, file_name },
    );
}

test "test_output: ArtifactDir paths are writable"
{
    const io = std.testing.io;

    var artifacts = try ArtifactDir.init(io);
    defer artifacts.deinit();

    var buf: [MAX_PATH_BYTES]u8 = undefined;
    const path = try artifacts.file_path(&buf, "test_output_check.txt");

    try std.Io.Dir.cwd().writeFile(
        io,
        .{ .sub_path = path, .data = "ok" },
    );
    try std.Io.Dir.cwd().access(io, path, .{});
}
