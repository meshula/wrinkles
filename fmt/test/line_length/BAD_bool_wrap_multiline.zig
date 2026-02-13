const std = @import("std");

const MAX_LINE_LENGTH: usize = 78;

fn compute_line_length(source: []const u8, start: usize) usize {
    _ = source;
    _ = start;
    return 0;
}

fn example(source: []const u8) bool {
    const continue_lparen_location_line: usize = 1;
    const continue_first_location_line: usize = 1;
    const continue_rparen_location_line: usize = 2;
    const colon_location_line_start: usize = 0;

    // Boolean chain already multiline at `and` but first line still too long
    const needs_break = continue_lparen_location_line == continue_first_location_line
        and (
            continue_lparen_location_line != continue_rparen_location_line
            or compute_line_length(
                source,
                colon_location_line_start,
            ) > MAX_LINE_LENGTH
        );

    return needs_break;
}

test "bool_wrap_multiline" {
    try std.testing.expect(!example(""));
}
