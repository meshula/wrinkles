const std = @import("std");

pub fn nested(
    x: i32,
    y: i32,
) i32
{
    if (x > 0)
    {
        if (y > 0)
        {
            return 1;
        }
        else
        {
            return 2;
        }
    }
    else
    {
        if (y > 0)
        {
            return 3;
        }
        else
        {
            return 4;
        }
    }
}

test "nested"
{
    try std.testing.expectEqual(@as(i32, 1), nested(1, 1));
    try std.testing.expectEqual(@as(i32, 2), nested(1, -1));
    try std.testing.expectEqual(@as(i32, 3), nested(-1, 1));
    try std.testing.expectEqual(@as(i32, 4), nested(-1, -1));
}
