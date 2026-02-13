const std = @import("std");

pub fn findNonZero(items: []const i32) ?i32 {
    var i: usize = 0;
    while (i < items.len) : (i += 1) {
        if (items[i] != 0) return items[i];
    } else {
        return null;
    }
}

test "findNonZero" {
    const items = [_]i32{ 0, 0, 5, 0 };
    try std.testing.expectEqual(@as(?i32, 5), findNonZero(&items));
}
