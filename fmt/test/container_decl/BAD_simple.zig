const std = @import("std");

const Point = struct
{
    x: i32,
    y: i32,

    pub fn add(self: Point, other: Point) Point {
        return .{
            .x = self.x + other.x,
            .y = self.y + other.y,
        };
    }
};

const Color = enum
{
    red,
    green,
    blue,
};

const Value = union(enum)
{
    int: i32,
    float: f32,
    none,
};

test "Point" {
    const p1 = Point{ .x = 1, .y = 2 };
    const p2 = Point{ .x = 3, .y = 4 };
    const sum = p1.add(p2);
    try std.testing.expectEqual(@as(i32, 4), sum.x);
}
