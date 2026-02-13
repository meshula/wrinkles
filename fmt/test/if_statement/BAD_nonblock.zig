const std = @import("std");

pub fn process(x: i32) i32 {
    if (x > 0) return x;
    if (x < -10) return -10;
    return 0;
}

test "nonblock if" {
    try std.testing.expectEqual(@as(i32, 5), process(5));
    try std.testing.expectEqual(@as(i32, -10), process(-20));
    try std.testing.expectEqual(@as(i32, 0), process(0));
}
