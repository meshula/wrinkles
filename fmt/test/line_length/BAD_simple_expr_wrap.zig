const std = @import("std");

fn example(source: []const u8) void {
    if (true) {
        if (true) {
            if (true) {
                if (true) {
                    const existing_indent = source[line_start_pos..indent_end];
                    _ = existing_indent;
                }
            }
        }
    }
}

fn return_example(source: []const u8) []const u8 {
    if (true) {
        if (true) {
            if (true) {
                return source[some_long_start_position..some_long_end_position];
            }
        }
    }
    return source;
}

fn already_wrapped(source: []const u8) []const u8 {
    const short = source[0..1];
    _ = short;
    return source;
}

test "simple_expr_wrap" {
    example("hello");
    _ = return_example("hello");
    _ = already_wrapped("hello");
}
