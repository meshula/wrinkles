const std = @import("std");

// Multi-line condition: capture stays on same line as closing )
pub fn processMultiLineFor(
    first_slice: []const u8,
    second_slice: []const u8,
) void
{
    for (
        first_slice,
        second_slice,
    )
        |first_item, second_item|
    {
        std.debug.print("{c}{c}", .{ first_item, second_item });
    }
}

fn getMaybeValue(
    x: i32,
    y: i32,
) ?i32
{
    if (x > y) return x else return null;
}

pub fn processMultiLineIf(x: i32, y: i32) i32
{
    if (
        getMaybeValue(
            x,
            y,
        )
    )
        |value|
    {
        return value * 2;
    }
    return 0;
}

test "multi line condition with capture"
{
    try std.testing.expectEqual(@as(i32, 20), processMultiLineIf(10, 5));
}
