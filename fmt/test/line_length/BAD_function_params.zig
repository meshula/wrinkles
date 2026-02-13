const std = @import("std");

// Function with parameters that would exceed 78 chars on one line
pub fn process_data(
    allocator: std.mem.Allocator,
    source: []const u8,
    options: struct { verbose: bool, strict: bool },
) !void {
    _ = allocator;
    _ = source;
    _ = options;
}

// Short function - NOW ALSO BREAKS (all fn sigs break)
pub fn add(
    a: i32,
    b: i32,
) i32 {
    return a + b;
}

test "functions compile" {
    try process_data(std.testing.allocator, "test", .{ .verbose = false, .strict = true });
    try std.testing.expectEqual(@as(i32, 3), add(1, 2));
}
