const std = @import("std");

pub fn check(
    x: i32,
) bool
{
    if (x > 0)
    {
        return true;
    }
    return false;
}

test "check"
{
    try std.testing.expect(check(5) == true);
    try std.testing.expect(check(-1) == false);
}
