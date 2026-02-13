const std = @import("std");

const Status = enum {
    ok,
    err,
};

fn getStatus(
    x: i32,
    y: i32,
) Status
{
    if (x > y) return .ok else return .err;
}

pub fn processMultilineSwitch(
    x: i32,
    y: i32,
) i32
{
    return switch (
        getStatus(
            x,
            y,
        )
    )
    {
        .ok => 1,
        .err => -1,
    };
}

test "multiline switch"
{
    try std.testing.expectEqual(@as(i32, 1), processMultilineSwitch(10, 5));
    try std.testing.expectEqual(@as(i32, -1), processMultilineSwitch(5, 10));
}
