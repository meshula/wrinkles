const std = @import("std");

pub fn countdown(n: u32) u32 {
    var count = n;
    var sum: u32 = 0;
    while (count > 0) {
        sum += count;
        count -= 1;
    }
    return sum;
}

test "countdown" {
    try std.testing.expectEqual(@as(u32, 15), countdown(5));
}
