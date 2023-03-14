const std = @import("std");

// using a string type locally.  Refers to zig array of latin_s8 encoded 
// characters, see:
// https://en.wikipedia.org/wiki/ISO/IEC_8859-1
pub const latin_s8 = []const u8; 

// @TODO: other notes on strings
// implementing it this way prevents handing it directly to functions that 
// operate on []const u8 (for better or for worse)
// const latin_s8 = struct {
//     bytes = []const u8;
// };

// const sutf8 = struct {
//     bytes = []const u8;
//
//     pub fn is_convertable_to_ascii(self: @This()) bool {
//     };
//     pub fn to_su8(self: @This()) !sutf8 {
//
//     };
// };


// concatenate two strings together
pub fn concatenate(
    one: []const u8,
    two: []const u8
) ![]const u8 {
    return try std.fmt.allocPrint(
        std.heap.page_allocator,
        "{s}{s}",
        .{one, two}
    ); 
}

pub fn generate_spaces(count: i32) ![]const u8 {
    var result:[]const u8 = "";
    var i: i32 = 0;
    while (i < count) {
        result = try concatenate(result, " ");
        i += 1;
    }
    return result;
}
