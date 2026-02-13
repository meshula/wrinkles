const std = @import("std");

pub fn unwrap(
    maybe: ?i32,
) i32
{
    if (maybe)
        |value|
    {
        return value * 2;
    }
    return 0;
}

test "unwrap"
{
    try std.testing.expectEqual(@as(i32, 10), unwrap(5));
    try std.testing.expectEqual(@as(i32, 0), unwrap(null));
}
