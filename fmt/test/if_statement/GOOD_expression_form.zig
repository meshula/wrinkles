const std = @import("std");

pub fn abs(
    x: i32,
) i32
{
    const result = if (x > 0) x else -x;
    return result;
}

pub fn max(
    a: i32,
    b: i32,
) i32
{
    return if (a > b) a else b;
}

test "abs"
{
    try std.testing.expectEqual(@as(i32, 5), abs(5));
    try std.testing.expectEqual(@as(i32, 5), abs(-5));
}

test "max"
{
    try std.testing.expectEqual(@as(i32, 10), max(5, 10));
    try std.testing.expectEqual(@as(i32, 10), max(10, 5));
}
