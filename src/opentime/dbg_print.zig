//! Utility debugger function including a compile switch and line/file in the
//! printout.
const std = @import("std");

const build_options = @import("build_options");

pub const DEBUG_MESSAGES= (
    build_options.debug_graph_construction_trace_messages 
    or build_options.debug_print_messages 
);

/// Utility function that injects the calling info into the debug print.  Uses
/// `std.debug.print`.
pub fn dbg_print(
    src: std.builtin.SourceLocation,
    comptime fmt: []const u8,
    args: anytype,
) void 
{
    if (DEBUG_MESSAGES) 
    {
        std.debug.print(
            "[{s}:{s}:{d}] " ++ fmt ++ "\n",
            .{
                src.file,
                src.fn_name,
                src.line,
            } ++ args,
        );
    }
}

