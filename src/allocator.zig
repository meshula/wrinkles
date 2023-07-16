const std = @import("std");

var raw = std.heap.GeneralPurposeAllocator(.{.stack_trace_frames = 32}){};
pub const ALLOCATOR:std.mem.Allocator = raw.allocator();
