const std = @import("std");

fn is_block_tag(
    tag: std.zig.Ast.Node.Tag,
) bool
{
    return tag == .block
    or tag == .block_two
    or tag == .block_two_semicolon
    or tag == .block_semicolon;
}

fn check_status(
    a: bool,
    b: bool,
    c: bool,
) bool
{
    if (
        a
        and !b
        and c
    )
    {
        return true;
    }
    return false;
}
