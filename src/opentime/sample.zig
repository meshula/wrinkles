const std = @import("std");

const util = @import("util.zig");
const curve = @import("curve");
const ALLOCATOR = @import("otio_allocator").ALLOCATOR;

const expectEqual = std.testing.expectEqual;
const expectApproxEqAbs = std.testing.expectApproxEqAbs;

// @{ Sample Interface
pub const Sample = struct {
    ordinate_seconds: f32 = 0,
    support_negative_seconds: f32 = 0,
    support_positive_seconds: f32 = 0,
};
// @}


