const std = @import("std");

var raw = std.heap.GeneralPurposeAllocator(.{}){};
pub const ALLOCATOR:std.mem.Allocator = raw.allocator();
