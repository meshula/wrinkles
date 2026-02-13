const std = @import("std");

pub fn unwrapOrDefault(maybe: ?i32, default: i32) i32 {
    if (maybe) |value| {
        return value * 2;
    } else {
        return default;
    }
}

test "unwrapOrDefault" {
    try std.testing.expectEqual(@as(i32, 10), unwrapOrDefault(5, 0));
    try std.testing.expectEqual(@as(i32, 42), unwrapOrDefault(null, 42));
}
