const std = @import("std");

const Color = enum {
    red,
    green,
    blue,
};

pub fn colorToInt(
    c: Color,
) i32
{
    return switch (c) {
        .red => 1,
        .green => 2,
        .blue => 3,
    };
}

pub fn describe(
    value: i32,
) []const u8
{
    return switch (value) {
        0 => "zero",
        1, 2, 3 => "small",
        4...10 => "medium",
        else => "large",
    };
}

test "colorToInt"
{
    try std.testing.expectEqual(@as(i32, 1), colorToInt(.red));
    try std.testing.expectEqual(@as(i32, 2), colorToInt(.green));
}

test "describe"
{
    try std.testing.expectEqualStrings("zero", describe(0));
    try std.testing.expectEqualStrings("small", describe(2));
    try std.testing.expectEqualStrings("medium", describe(7));
    try std.testing.expectEqualStrings("large", describe(100));
}
