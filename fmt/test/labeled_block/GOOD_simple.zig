const std = @import("std");

pub fn with_labeled_block(
    x: i32,
) i32
{
    const result = blk: {
        if (x > 10)
        {
            break :blk x * 2;
        }
        break :blk x;
    };
    return result;
}

pub fn labeled_if(
    condition: bool,
) i32
{
    if (condition) myblock: {
        const temp = 42;
        _ = temp;
        break :myblock;
    }
    return 0;
}

pub fn labeled_while(
    n: usize,
) usize
{
    var i: usize = 0;
    while (i < n) : (i += 1) outer: {
        var j: usize = 0;
        while (j < n) : (j += 1) inner: {
            if (i == j)
            {
                break :inner;
            }
        }
        if (i > 5)
        {
            break :outer;
        }
    }
    return i;
}

test "labeled block"
{
    try std.testing.expectEqual(@as(i32, 5), with_labeled_block(5));
    try std.testing.expectEqual(@as(i32, 30), with_labeled_block(15));
}
