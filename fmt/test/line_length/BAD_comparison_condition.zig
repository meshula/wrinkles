const std = @import("std");

const MAX_LINE_LENGTH: usize = 78;

fn example_if(lbrace_loc_column: usize, rbrace_start: usize, lbrace_start: usize) void {
    if (true) {
        if (lbrace_loc_column + (rbrace_start - lbrace_start) <= MAX_LINE_LENGTH) {
            return;
        }
    }
}

fn example_while(lbrace_loc_column: usize, rbrace_start: usize, lbrace_start: usize) void {
    while (lbrace_loc_column + (rbrace_start - lbrace_start) <= MAX_LINE_LENGTH) {
        return;
    }
}

fn example_not_equal(very_long_variable_name_alpha: usize, very_long_variable_name_beta: usize) void {
    if (very_long_variable_name_alpha != very_long_variable_name_beta) {
        return;
    }
}

fn short_condition(a: usize, b: usize) void {
    if (a <= b) {
        return;
    }
}

test "comparison_condition" {
    example_if(0, 100, 0);
    example_while(0, 100, 0);
    example_not_equal(1, 2);
    short_condition(1, 2);
}
