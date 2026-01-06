//! Shared utilities for TLZ file bundle operations

const std = @import("std");

// ----------------------------------------------------------------------------
// Constants
// ----------------------------------------------------------------------------

/// Version of the TLZ bundle format
pub const BUNDLE_VERSION = "1.0.0";

/// Name of the version file in the bundle
pub const BUNDLE_VERSION_FILE = "version.txt";

/// Name of the media directory in the bundle
pub const BUNDLE_DIR_NAME = "media";

/// Name of the Ziggy content file in the bundle
pub const BUNDLE_CONTENT_ZIGGY = "content.ziggy";

/// Name of the FlatBuffers content file in the bundle
pub const BUNDLE_CONTENT_TLFB = "content.tlfb";

// ----------------------------------------------------------------------------
// Types
// ----------------------------------------------------------------------------

/// Policy for handling media references during bundle creation
pub const MediaReferencePolicy = enum {
    /// Raise error if any media reference doesn't point to valid file
    ErrorIfNotFile,

    /// Replace invalid media references with MissingReference placeholders
    MissingIfNotFile,

    /// Replace all media references with MissingReference placeholders
    AllMissing,
};

/// Timeline format to use inside the TLZ bundle
pub const BundleFormat = enum {
    /// Human-readable Ziggy text format
    ziggy,

    /// Binary FlatBuffers format
    tlfb,
};

// ----------------------------------------------------------------------------
// Utility Functions
// ----------------------------------------------------------------------------

/// Validate that all media basenames are unique. Returns an error if any
/// duplicate basenames are found, as TLZ bundles require unique basenames
/// in the flat media directory structure.
pub fn guaranteeUniqueBasenames(
    paths: []const []const u8,
) !void
{
    var seen = std.StringHashMap(void).init(
        std.heap.page_allocator
    );
    defer seen.deinit();

    for (paths)
        |path|
    {
        const basename = getBasename(path);

        if (seen.contains(basename))
        {
            return error.DuplicateBasename;
        }

        try seen.put(basename, {});
    }
}

/// Convert path separators to Unix-style (/) regardless of platform.
/// Returns a newly allocated string that the caller owns.
pub fn pathToUnixStyle(
    allocator: std.mem.Allocator,
    path: []const u8,
) ![]const u8
{
    const result = try allocator.alloc(
        u8,
        path.len
    );

    for (path, 0..)
        |char, i|
    {
        result[i] = if (char == '\\') '/' else char;
    }

    return result;
}

/// Extract the filename (basename) from a path.
/// Returns a slice pointing into the original path string.
pub fn getBasename(
    path: []const u8,
) []const u8
{
    if (path.len == 0)
    {
        return path;
    }

    // Find the last path separator (/ or \)
    var i = path.len - 1;

    while (i > 0)
        : (i -= 1)
    {
        if (path[i] == '/' or path[i] == '\\')
        {
            return path[i + 1..];
        }
    }

    // No separator found, entire path is the basename
    return path;
}

// ----------------------------------------------------------------------------
// Tests
// ----------------------------------------------------------------------------

test "tlz_bundle_utils: getBasename with Unix paths"
{
    const tests = [_]struct {
        input: []const u8,
        expected: []const u8,
    }{
        .{ .input = "path/to/file.txt", .expected = "file.txt" },
        .{ .input = "/absolute/path/file.mov", .expected = "file.mov" },
        .{ .input = "file.wav", .expected = "file.wav" },
        .{ .input = "", .expected = "" },
        .{ .input = "single", .expected = "single" },
    };

    for (tests)
        |t|
    {
        const result = getBasename(t.input);
        try std.testing.expectEqualStrings(t.expected, result);
    }
}

test "tlz_bundle_utils: getBasename with Windows paths"
{
    const tests = [_]struct {
        input: []const u8,
        expected: []const u8,
    }{
        .{ .input = "path\\to\\file.txt", .expected = "file.txt" },
        .{ .input = "C:\\absolute\\path\\file.mov", .expected = "file.mov" },
    };

    for (tests)
        |t|
    {
        const result = getBasename(t.input);
        try std.testing.expectEqualStrings(t.expected, result);
    }
}

test "tlz_bundle_utils: pathToUnixStyle"
{
    const allocator = std.testing.allocator;

    const tests = [_]struct {
        input: []const u8,
        expected: []const u8,
    }{
        .{ .input = "path\\to\\file.txt", .expected = "path/to/file.txt" },
        .{ .input = "path/to/file.txt", .expected = "path/to/file.txt" },
        .{ .input = "C:\\Windows\\Path", .expected = "C:/Windows/Path" },
        .{ .input = "mixed\\path/file", .expected = "mixed/path/file" },
    };

    for (tests)
        |t|
    {
        const result = try pathToUnixStyle(allocator, t.input);
        defer allocator.free(result);

        try std.testing.expectEqualStrings(t.expected, result);
    }
}

test "tlz_bundle_utils: guaranteeUniqueBasenames success"
{
    const paths = [_][]const u8{
        "path/to/file1.txt",
        "other/path/file2.txt",
        "/absolute/file3.mov",
    };

    try guaranteeUniqueBasenames(&paths);
}

test "tlz_bundle_utils: guaranteeUniqueBasenames failure"
{
    const paths = [_][]const u8{
        "path/to/file.txt",
        "other/path/file.txt",  // Duplicate basename!
    };

    const result = guaranteeUniqueBasenames(&paths);
    try std.testing.expectError(error.DuplicateBasename, result);
}

test "tlz_bundle_utils: guaranteeUniqueBasenames empty"
{
    const paths = [_][]const u8{};
    try guaranteeUniqueBasenames(&paths);
}
