const std = @import("std");

pub fn findFirst(items: []const i32, target: i32) ?usize {
    for (items, 0..) |item, i| {
        if (item == target) return i;
    } else {
        return null;
    }
}

test "findFirst" {
    const items = [_]i32{ 1, 2, 3, 4, 5 };
    try std.testing.expectEqual(@as(?usize, 2), findFirst(&items, 3));
    try std.testing.expectEqual(@as(?usize, null), findFirst(&items, 99));
}
