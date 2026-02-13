const std = @import("std");

pub fn check(x: i32) i32 {
    if (x > 0) {
        return 1;
    } else {
        return -1;
    }
}

test "check" {
    try std.testing.expectEqual(@as(i32, 1), check(5));
    try std.testing.expectEqual(@as(i32, -1), check(-1));
}
