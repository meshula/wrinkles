const std = @import("std");

pub fn check_conditions(
    a: bool,
    b: bool,
    c: bool,
    d: bool,
) bool {
    // Long boolean expression broken before operators
    return a and b and c and d;
}

pub fn compute(
    x: i32,
    y: i32,
    z: i32,
) i32 {
    // Long arithmetic broken before operators
    return x * 100 + y * 10 + z;
}

pub fn validate(before_close: usize, after_close: usize, source: []const u8) bool {
    const closing_on_own_line = before_close > 0 and source[before_close - 1] == '\n' and after_close < source.len;
    return closing_on_own_line;
}

test "binary expressions" {
    try std.testing.expect(check_conditions(true, true, true, true));
    try std.testing.expect(!check_conditions(true, false, true, true));
    try std.testing.expectEqual(@as(i32, 123), compute(1, 2, 3));
    try std.testing.expect(validate(5, 6, "hello\nworld"));
}
