const std = @import("std");

// Single-line condition: capture goes on its own indented line
pub fn processMaybe(maybe_value: ?i32) i32
{
    if (maybe_value) |value|
    {
        return value * 2;
    }
    return 0;
}

pub fn processSlice(slice: []const u8) void
{
    for (slice) |item|
    {
        std.debug.print("{c}", .{item});
    }
}

pub fn processOptionalIter(maybe_iter: ?[]const u8) void
{
    while (maybe_iter) |iter|
    {
        _ = iter;
        break;
    }
}

test "single line condition with capture"
{
    try std.testing.expectEqual(@as(i32, 10), processMaybe(5));
    try std.testing.expectEqual(@as(i32, 0), processMaybe(null));
}
