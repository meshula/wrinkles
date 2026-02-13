const std = @import("std");

pub fn classify(
    x: i32,
) i32
{
    if (x > 0)
    {
        return 1;
    }
    else if (x < 0)
    {
        return -1;
    }
    else
    {
        return 0;
    }
}

test "classify"
{
    try std.testing.expectEqual(@as(i32, 1), classify(5));
    try std.testing.expectEqual(@as(i32, -1), classify(-5));
    try std.testing.expectEqual(@as(i32, 0), classify(0));
}
