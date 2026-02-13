const std = @import("std");

pub fn add(
    a: i32,
    b: i32,
) i32
{
    return a + b;
}

fn multiply(
    a: i32,
    b: i32,
) i32
{
    return a * b;
}

pub fn complex(
    a: i32,
    b: i32,
    c: i32,
) i32
{
    return a + b * c;
}

test "functions"
{
    try std.testing.expectEqual(@as(i32, 5), add(2, 3));
    try std.testing.expectEqual(@as(i32, 6), multiply(2, 3));
    try std.testing.expectEqual(@as(i32, 8), complex(2, 3, 2));
}
