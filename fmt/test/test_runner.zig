const std = @import("std");
const formatter = @import("formatter");

const TestPair = struct {
    name: []const u8,
    good_path: []const u8,
    bad_path: []const u8,
};

fn findTestPairs(allocator: std.mem.Allocator, dir_path: []const u8) ![]TestPair {
    var pairs: std.ArrayListUnmanaged(TestPair) = .{};
    errdefer pairs.deinit(allocator);

    var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch |err| {
        std.debug.print("Cannot open test directory '{s}': {}\n", .{ dir_path, err });
        return pairs.toOwnedSlice(allocator);
    };
    defer dir.close();

    var good_files: std.StringHashMapUnmanaged([]const u8) = .{};
    defer {
        var it = good_files.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        good_files.deinit(allocator);
    }

    var bad_files: std.StringHashMapUnmanaged([]const u8) = .{};
    defer {
        var it = bad_files.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        bad_files.deinit(allocator);
    }

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".zig")) continue;

        const full_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dir_path, entry.name });

        if (std.mem.startsWith(u8, entry.name, "GOOD_")) {
            const test_name = try allocator.dupe(u8, entry.name[5 .. entry.name.len - 4]);
            try good_files.put(allocator, test_name, full_path);
        } else if (std.mem.startsWith(u8, entry.name, "BAD_")) {
            const test_name = try allocator.dupe(u8, entry.name[4 .. entry.name.len - 4]);
            try bad_files.put(allocator, test_name, full_path);
        } else {
            allocator.free(full_path);
        }
    }

    // Match pairs
    var good_iter = good_files.iterator();
    while (good_iter.next()) |good_entry| {
        if (bad_files.get(good_entry.key_ptr.*)) |bad_path| {
            try pairs.append(allocator, .{
                .name = try allocator.dupe(u8, good_entry.key_ptr.*),
                .good_path = try allocator.dupe(u8, good_entry.value_ptr.*),
                .bad_path = try allocator.dupe(u8, bad_path),
            });
        }
    }

    return pairs.toOwnedSlice(allocator);
}

fn runTestPair(allocator: std.mem.Allocator, pair: TestPair) !void {
    // Read both files
    const good_content = try std.fs.cwd().readFileAlloc(allocator, pair.good_path, std.math.maxInt(usize));
    defer allocator.free(good_content);

    const bad_content = try std.fs.cwd().readFileAlloc(allocator, pair.bad_path, std.math.maxInt(usize));
    defer allocator.free(bad_content);

    // Format BAD and compare to GOOD
    const formatted_bad = try formatter.format(allocator, bad_content);
    defer allocator.free(formatted_bad);

    if (!std.mem.eql(u8, formatted_bad, good_content)) {
        std.debug.print("\n=== MISMATCH for test '{s}' ===\n", .{pair.name});
        std.debug.print("--- Expected (GOOD_{s}.zig) ---\n{s}\n", .{ pair.name, good_content });
        std.debug.print("--- Got (formatted BAD_{s}.zig) ---\n{s}\n", .{ pair.name, formatted_bad });
        return error.TestMismatch;
    }

    // Format GOOD (should be unchanged - idempotency)
    const formatted_good = try formatter.format(allocator, good_content);
    defer allocator.free(formatted_good);

    if (!std.mem.eql(u8, formatted_good, good_content)) {
        std.debug.print("\n=== NOT IDEMPOTENT for test '{s}' ===\n", .{pair.name});
        std.debug.print("--- Original GOOD_{s}.zig ---\n{s}\n", .{ pair.name, good_content });
        std.debug.print("--- After formatting ---\n{s}\n", .{formatted_good});
        return error.NotIdempotent;
    }
}

fn runTestsInDirectory(allocator: std.mem.Allocator, dir_path: []const u8) !struct { passed: usize, failed: usize } {
    const pairs = try findTestPairs(allocator, dir_path);
    defer {
        for (pairs) |pair| {
            allocator.free(pair.name);
            allocator.free(pair.good_path);
            allocator.free(pair.bad_path);
        }
        allocator.free(pairs);
    }

    if (pairs.len == 0) {
        std.debug.print("Warning: No test pairs found in {s}\n", .{dir_path});
        return .{ .passed = 0, .failed = 0 };
    }

    var passed: usize = 0;
    var failed: usize = 0;

    for (pairs) |pair| {
        runTestPair(allocator, pair) catch |err| {
            std.debug.print("FAIL: {s}/{s} - {}\n", .{ dir_path, pair.name, err });
            failed += 1;
            continue;
        };
        passed += 1;
    }

    return .{ .passed = passed, .failed = failed };
}

test "formatting tests" {
    const allocator = std.testing.allocator;

    const test_dirs = [_][]const u8{
        "test/if_statement",
        "test/for_loop",
        "test/while_loop",
        "test/test_decl",
        "test/fn_decl",
        "test/switch_stmt",
        "test/container_decl",
        "test/capture_placement",
        "test/labeled_block",
        "test/stacked_paren",
        "test/line_length",
    };

    var total_passed: usize = 0;
    var total_failed: usize = 0;

    for (test_dirs) |dir| {
        const result = try runTestsInDirectory(allocator, dir);
        total_passed += result.passed;
        total_failed += result.failed;
    }

    std.debug.print("\nTest results: {d} passed, {d} failed\n", .{ total_passed, total_failed });

    if (total_failed > 0) {
        return error.TestsFailed;
    }
}
