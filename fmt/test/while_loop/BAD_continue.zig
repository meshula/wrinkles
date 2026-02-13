const std = @import("std");

fn simple_while_continue(
) void {
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        std.debug.print("{}\n", .{i});
    }
}

fn multiline_while_continue(
) void {
    var iteration: usize = 0;
    while (
        iteration < some_long_variable_name
        or iteration < another_long_variable_name
    ) : (iteration += 1) {
        std.debug.print("{}\n", .{iteration});
    }
}
