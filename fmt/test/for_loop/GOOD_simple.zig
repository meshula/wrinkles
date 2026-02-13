const std = @import("std");

pub fn sum(
    items: []const i32,
) i32
{
    var total: i32 = 0;
    for (items)
        |item|
    {
        total += item;
    }
    return total;
}

test "sum"
{
    const items = [_]i32{ 1, 2, 3, 4, 5 };
    try std.testing.expectEqual(@as(i32, 15), sum(&items));
}
