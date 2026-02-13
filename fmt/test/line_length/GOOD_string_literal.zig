const std = @import("std");

fn warn_naming(
    name: []const u8,
    line_num: usize,
) void
{
    std.debug.print(
        (
            "warning: line {d}: function '{s}' is not snake_case and "
            ++ "violates naming conventions\n"
        ),
        .{ line_num, name },
    );
}

const long_message = (
    "This is a very long string literal that definitely exceeds the "
    ++ "seventy-eight character column limit"
);

fn nested_example(
) void
{
    if (true)
    {
        if (true)
        {
            std.debug.print(
                (
                    "deeply nested: this string is too long for the line "
                    ++ "limit and should be split at words\n"
                ),
                .{},
            );
        }
    }
}

fn escape_example(
) void
{
    std.debug.print(
        (
            "escape sequences: first\\nsecond\\nthird line is quite long and "
            ++ "exceeds the limit\n"
        ),
        .{},
    );
}

test "string_literal"
{
    warn_naming("test", 1);
    nested_example();
    escape_example();
    _ = long_message;
}
