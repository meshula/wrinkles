const std = @import("std");

fn example() void {
    const cont_rparen_tok = cont_last_tok + 1; // the ) closing the continue expr
    const x: i32 = 42; // short comment, line is fine
    const result = some_function(arg1, arg2); // this trailing comment makes the line exceed the limit
    const s = "hello // world"; // comment after a string containing slashes is still a comment here!!
}

test "trailing_comment" {
    example();
}
