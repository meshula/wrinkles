const std = @import("std");

fn add(a: i32, b: i32) i32 {
    return a + b;
}

test "add positive numbers" {
    try std.testing.expectEqual(@as(i32, 5), add(2, 3));
}

test "add negative numbers" {
    try std.testing.expectEqual(@as(i32, -5), add(-2, -3));
}

test "add mixed numbers" {
    try std.testing.expectEqual(@as(i32, 1), add(3, -2));
}
