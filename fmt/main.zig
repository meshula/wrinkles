const std = @import("std");
const clap = @import("clap");
const formatter = @import("formatter.zig");

const ExitCode = enum(u8) {
    success = 0,
    check_failed = 1, // File would be changed (--check mode only)
    parse_error = 2, // Parse error / invalid input
    other_error = 3, // File not found, etc.
};

const Mode = enum {
    stdout,
    inplace,
    check,
    diff,
};

const ProcessResult = struct {
    success: bool,
    changed: bool,
};

const PARAMS = 
\\-h, --help             Display this help and exit.
\\-s, --stdout           Print formatted output to stdout.
\\-i, --inplace          Modify file in place.
\\-c, --check            Exit 0 if no changes needed, 1 if changes needed.
\\-d, --diff             Show diff between original and formatted.
\\-r, --recursive        Recursively process directories.
\\-t, --difftool <str>   Difftool to use (default: diff -u).
\\<str>...               Input files, directories, or glob patterns to format.
\\,
;

const params = clap.parseParamsComptime(PARAMS);

pub fn main(
) u8
{
    return main_impl() catch |err| {
        std.debug.print("Error: {}\n", .{err});
        return @intFromEnum(ExitCode.other_error);
    };
}

fn main_impl(
) !u8
{
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var diag: clap.Diagnostic = .{};
    var res = clap.parse(
        clap.Help,
        &params,
        clap.parsers.default,
        .{
            .diagnostic = &diag,
            .allocator = allocator,
        },
    ) catch |err| {
        diag.reportToFile(std.fs.File.stderr(), err) catch {};
        return @intFromEnum(ExitCode.other_error);
    };
    defer res.deinit();

    // Handle help
    if (res.args.help != 0)
    {
        print_usage();
        return @intFromEnum(ExitCode.success);
    }

    // Get file paths - res.positionals is a tuple, first element is the slice
    // of strings
    const positionals = res.positionals[0];
    if (positionals.len == 0)
    {
        std.debug.print("Error: No input files specified.\n\n", .{});
        print_usage();
        return @intFromEnum(ExitCode.other_error);
    }

    // Determine mode
    const mode: Mode = if (res.args.stdout != 0)
        .stdout
    else if (res.args.inplace != 0)
        .inplace
    else if (res.args.check != 0)
        .check
    else if (res.args.diff != 0)
        .diff
    else
    {
        std.debug.print(
            (
                "Error: Must specify one of --stdout, --inplace, --check, or "
                ++ "--diff.\n\n"
            ),
            .{},
        );
        print_usage();
        return @intFromEnum(ExitCode.other_error);
    };

    // Get difftool if specified
    const difftool: ?[]const u8 = res.args.difftool;

    // Get recursive flag
    const recursive = res.args.recursive != 0;

    // Collect all .zig files from arguments
    var files: std.ArrayListUnmanaged([]const u8) = .{};
    defer {
        for (files.items)
            |f|
        {
            allocator.free(f);
        }
        files.deinit(allocator);
    }

    for (positionals)
        |arg|
    {
        try collect_files(allocator, arg, recursive, &files);
    }

    if (files.items.len == 0)
    {
        std.debug.print("Error: No .zig files found.\n", .{});
        return @intFromEnum(ExitCode.other_error);
    }

    // Process all files
    var success_count: usize = 0;
    var changed_count: usize = 0;
    var error_count: usize = 0;
    var any_would_change = false;

    for (files.items)
        |file_path|
    {
        const result = process_file(allocator, file_path, mode, difftool);
        if (result.success)
        {
            success_count += 1;
            if (result.changed)
            {
                changed_count += 1;
                any_would_change = true;
            }
        }
        else
        {
            error_count += 1;
        }
    }

    // Print summary if multiple files
    if (files.items.len > 1)
    {
        std.debug.print(
            "\nSummary: {d} files processed, {d} changed, {d} errors\n",
            .{
                success_count,
                changed_count,
                error_count,
            },
        );
    }

    // Determine exit code
    if (error_count > 0)
    {
        return @intFromEnum(ExitCode.other_error);
    }
    if (
        mode == .check
        and any_would_change
    )
    {
        return @intFromEnum(ExitCode.check_failed);
    }
    return @intFromEnum(ExitCode.success);
}

/// Collect .zig files from a path (file, directory, or glob pattern)
fn collect_files(
    allocator: std.mem.Allocator,
    path: []const u8,
    recursive: bool,
    files: *std.ArrayListUnmanaged([]const u8),
) !void
{
    // Check if path contains glob characters
    if (contains_glob(path))
    {
        try expand_glob(allocator, path, files);
        return;
    }

    // Check if path is a file or directory
    const stat = std.fs.cwd().statFile(path) catch |err| {
        // Try as a directory
        var dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch {
            std.debug.print(
                "Error: Cannot access '{s}': {}\n",
                .{ path, err },
            );
            return;
        };
        defer dir.close();
        try collect_from_directory(allocator, path, dir, recursive, files);
        return;
    };

    if (stat.kind == .directory)
    {
        var dir = try std.fs.cwd().openDir(path, .{ .iterate = true });
        defer dir.close();
        try collect_from_directory(allocator, path, dir, recursive, files);
    }
    else
    {
        // It's a file - add it if it's a .zig file
        if (std.mem.endsWith(u8, path, ".zig"))
        {
            const owned = try allocator.dupe(u8, path);
            try files.append(allocator, owned);
        }
        else
        {
            std.debug.print(
                "Warning: Skipping non-.zig file '{s}'\n",
                .{path},
            );
        }
    }
}

/// Check if a path contains glob characters
fn contains_glob(
    path: []const u8,
) bool
{
    for (path)
        |c|
    {
        if (
            c == '*'
            or c == '?'
            or c == '['
        )
        {
            return true;
        }
    }
    return false;
}

/// Expand a glob pattern using shell
fn expand_glob(
    allocator: std.mem.Allocator,
    pattern: []const u8,
    files: *std.ArrayListUnmanaged([]const u8),
) !void
{
    // Use shell to expand glob pattern
    const shell_cmd = try std.fmt.allocPrint(
        allocator,
        "ls -1 {s} 2>/dev/null",
        .{pattern},
    );
    defer allocator.free(shell_cmd);

    const result = std.process.Child.run(
        .{
                .allocator = allocator,
                .argv = &.{ "/bin/sh", "-c", shell_cmd },
                .max_output_bytes = 1024 * 1024,
            // 1MB max,
            },
    ) catch {
        std.debug.print(
            "Warning: Failed to expand pattern '{s}'\n",
            .{pattern},
        );
        return;
    };
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    // Check if command succeeded
    if (result.term.Exited != 0)
    {
        std.debug.print(
            "Warning: No files match pattern '{s}'\n",
            .{pattern},
        );
        return;
    }

    // Parse output line by line
    var lines = std.mem.splitScalar(u8, result.stdout, '\n');
    while (lines.next())
        |line|
    {
        if (line.len == 0)
        {
            continue;
        }
        if (std.mem.endsWith(u8, line, ".zig"))
        {
            const owned = try allocator.dupe(u8, line);
            try files.append(allocator, owned);
        }
    }
}

/// Collect .zig files from a directory
fn collect_from_directory(
    allocator: std.mem.Allocator,
    base_path: []const u8,
    dir: std.fs.Dir,
    recursive: bool,
    files: *std.ArrayListUnmanaged([]const u8),
) !void
{
    var iter = dir.iterate();
    while (try iter.next())
        |entry|
    {
        const full_path = try std.fs.path.join(
            allocator,
            &.{ base_path, entry.name },
        );
        errdefer allocator.free(full_path);

        switch (entry.kind) {
            .file => {
                if (std.mem.endsWith(u8, entry.name, ".zig"))
                {
                    try files.append(allocator, full_path);
                }
                else
                {
                    allocator.free(full_path);
                }
            },
            .directory => {
                if (recursive)
                {
                    var subdir = try dir.openDir(
                        entry.name,
                        .{ .iterate = true },
                    );
                    defer subdir.close();
                    try collect_from_directory(
                        allocator,
                        full_path,
                        subdir,
                        recursive,
                        files,
                    );
                }
                allocator.free(full_path);
            },
            else => {
                allocator.free(full_path);
            },
        }
    }
}

/// Process a single file
fn process_file(
    allocator: std.mem.Allocator,
    file_path: []const u8,
    mode: Mode,
    difftool: ?[]const u8,
) ProcessResult
{
    // Read the input file
    const source = std.fs.cwd().readFileAlloc(
        allocator,
        file_path,
        std.math.maxInt(usize),
    ) catch |err| {
        std.debug.print(
            "Error reading file '{s}': {}\n",
            .{ file_path, err },
        );
        return .{ .success = false, .changed = false };
    };
    defer allocator.free(source);

    // Format the source
    const formatted = formatter.format(allocator, source) catch |err| {
        if (err == error.ParseError)
        {
            std.debug.print("Parse error in '{s}'\n", .{file_path});
            return .{
                .success = false,
                .changed = false,
            };
        }
        std.debug.print("Error formatting '{s}': {}\n", .{ file_path, err });
        return .{ .success = false, .changed = false };
    };
    defer allocator.free(formatted);

    const changed = !std.mem.eql(u8, source, formatted);

    switch (mode) {
        .stdout => {
            if (changed)
            {
                std.debug.print("--- {s} ---\n", .{file_path});
            }
            std.fs.File.stdout().writeAll(formatted) catch {};
            return .{
                .success = true,
                .changed = changed,
            };
        },
        .check => {
            if (changed)
            {
                std.debug.print("Would change: {s}\n", .{file_path});
            }
            return .{
                .success = true,
                .changed = changed,
            };
        },
        .inplace => {
            if (changed)
            {
                var file = std.fs.cwd().openFile(
                    file_path,
                    .{ .mode = .write_only },
                ) catch |err| {
                    std.debug.print(
                        "Error opening '{s}' for writing: {}\n",
                        .{ file_path, err },
                    );
                    return .{
                        .success = false,
                        .changed = false,
                            };
                };
                defer file.close();
                file.writeAll(formatted) catch |err| {
                    std.debug.print(
                        "Error writing to '{s}': {}\n",
                        .{ file_path, err },
                    );
                    return .{
                        .success = false,
                        .changed = false,
                            };
                };
                file.setEndPos(formatted.len) catch |err| {
                    std.debug.print(
                        "Error truncating '{s}': {}\n",
                        .{ file_path, err },
                    );
                    return .{
                        .success = false,
                        .changed = false,
                            };
                };
                std.debug.print("Formatted: {s}\n", .{file_path});
            }
            return .{
                .success = true,
                .changed = changed,
            };
        },
        .diff => {
            if (!changed)
            {
                std.debug.print(
                    "No changes needed for '{s}'\n",
                    .{file_path},
                );
                return .{
                    .success = true,
                    .changed = false,
                    };
            }
            const exit_code = run_diff(
                allocator,
                file_path,
                formatted,
                difftool,
            );
            return .{
                .success = exit_code == @intFromEnum(ExitCode.success),
                .changed = true,
            };
        },
    }
}

fn run_diff(
    allocator: std.mem.Allocator,
    original_path: []const u8,
    formatted: []const u8,
    difftool: ?[]const u8,
) u8
{
    // Create a temporary file for the formatted output
    const tmp_dir = std.fs.cwd().openDir("/tmp", .{}) catch |err|
    {
        std.debug.print("Error opening /tmp: {}\n", .{err});
        return @intFromEnum(ExitCode.other_error);
    };

    // Generate temp filename based on original
    const basename = std.fs.path.basename(original_path);
    const tmp_filename = std.fmt.allocPrint(
        allocator,
        "zig-fmt-wrinkles-{s}",
        .{basename},
    ) catch
    {
        std.debug.print("Error allocating temp filename\n", .{});
        return @intFromEnum(ExitCode.other_error);
    };
    defer allocator.free(tmp_filename);

    // Write formatted content to temp file
    const tmp_file = tmp_dir.createFile(tmp_filename, .{}) catch |err|
    {
        std.debug.print("Error creating temp file: {}\n", .{err});
        return @intFromEnum(ExitCode.other_error);
    };
    tmp_file.writeAll(formatted) catch |err|
    {
        std.debug.print("Error writing temp file: {}\n", .{err});
        return @intFromEnum(ExitCode.other_error);
    };
    tmp_file.close();

    const tmp_path = std.fmt.allocPrint(
        allocator,
        "/tmp/{s}",
        .{tmp_filename},
    ) catch
    {
        std.debug.print("Error allocating temp path\n", .{});
        return @intFromEnum(ExitCode.other_error);
    };
    defer allocator.free(tmp_path);

    // Run the difftool
    if (difftool)
        |tool|
    {
        // User specified a custom difftool
        var child = std.process.Child.init(
            &.{ tool, original_path, tmp_path },
            allocator,
        );
        child.spawn() catch |err|
        {
            std.debug.print(
                "Error spawning difftool '{s}': {}\n",
                .{ tool, err },
            );
            return @intFromEnum(ExitCode.other_error);
        };
        const term = child.wait() catch |err|
        {
            std.debug.print("Error waiting for difftool: {}\n", .{err});
            return @intFromEnum(ExitCode.other_error);
        };
        _ = term;
    }
    else
    {
        // Default: use diff -u
        var child = std.process.Child.init(
            &.{ "diff", "-u", "--color=auto", original_path, tmp_path },
            allocator,
        );
        child.stdout_behavior = .Inherit;
        child.stderr_behavior = .Inherit;
        child.spawn() catch |err|
        {
            std.debug.print("Error spawning diff: {}\n", .{err});
            return @intFromEnum(ExitCode.other_error);
        };
        const term = child.wait() catch |err|
        {
            std.debug.print("Error waiting for diff: {}\n", .{err});
            return @intFromEnum(ExitCode.other_error);
        };
        _ = term;
    }

    // Clean up temp file
    tmp_dir.deleteFile(tmp_filename) catch {};

    return @intFromEnum(ExitCode.success);
}

fn print_usage(
) void
{
    clap.helpToFile(std.fs.File.stderr(), clap.Help, &params, .{}) catch {};
    std.fs.File.stderr().writeAll(
            \\
            \\Examples:
            \\  zig-fmt-wrinkles --check file1.zig file2.zig
            \\  zig-fmt-wrinkles --inplace src/*.zig
            \\  zig-fmt-wrinkles --recursive --check src/
            \\
            \\Exit codes:
            \\  0  Success (or no changes needed in --check mode)
            \\  1  File would be changed (--check mode only)
            \\  2  Parse error / invalid input
            \\  3  Other error (file not found, etc.)
            \\,
        ) catch {};
}
