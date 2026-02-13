const std = @import("std");

fn getMaybeValue(
    x: i32,
    y: i32,
) ?i32
{
    if (x > y) return x else return null;
}

pub fn processIt(
    x: i32,
    y: i32,
) i32
{
    if (
        getMaybeValue(
            x,
            y,
        )
    ) |blah|
    {
        return blah;
    }
    return 0;
}

test "stacked paren simple"
{
    try std.testing.expectEqual(@as(i32, 10), processIt(10, 5));
}
