const std = @import("std");

fn helper(
    a: i32,
    b: i32,
    c: i32,
    d: i32,
) i32
{
    return a + b + c + d;
}

pub fn example(
) i32
{
    // Long function call broken across lines
    const result = helper(
        100,
        200,
        300,
        400,
    );
    return result;
}

test "function call"
{
    try std.testing.expectEqual(@as(i32, 1000), example());
}
