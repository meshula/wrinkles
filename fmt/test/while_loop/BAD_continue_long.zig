const std = @import("std");

fn long_continue_expression(
) void
{
    var iteration: usize = 0;
    while (iteration < max) : (iteration = some_long_reset_function(arg1, arg2, arg3, arg4, arg5_xx))
    {
        std.debug.print("{}\n", .{iteration});
    }
}
