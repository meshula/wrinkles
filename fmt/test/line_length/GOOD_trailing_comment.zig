const std = @import("std");

fn example(
) void
{
    // the ) closing the continue expr
    const cont_rparen_tok = cont_last_tok + 1;
    const x: i32 = 42; // short comment, line is fine
    // this trailing comment makes the line exceed the limit
    const result = some_function(arg1, arg2);
    // comment after a string containing slashes is still a comment here!!
    const s = "hello // world";
}

test "trailing_comment"
{
    example();
}
