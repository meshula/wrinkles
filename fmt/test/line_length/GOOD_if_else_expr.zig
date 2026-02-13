const std = @import("std");

fn example(
    is_call: bool,
) std.zig.Token.Tag
{
    const open_tag = (
        if (is_call) std.zig.Token.Tag.l_paren
        else std.zig.Token.Tag.l_brace
    );
    return open_tag;
}

test "if else expr"
{
    try std.testing.expectEqual(
        std.zig.Token.Tag.l_paren,
        example(true),
    );
}
