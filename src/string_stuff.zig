const std = @import("std");

// using a string type locally.  Refers to zig array of latin_s8 encoded 
// characters, see:
// https://en.wikipedia.org/wiki/ISO/IEC_8859-1
pub const latin_s8 = []const u8; 

/// used in otvis for commandline argument checking
pub fn eql_latin_s8(
    fst: latin_s8,
    snd: latin_s8
) bool
{
    return std.mem.eql(u8, fst, snd);
}
