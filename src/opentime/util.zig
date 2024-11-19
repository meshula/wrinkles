const std = @import("std");

const ordinate = @import("ordinate.zig");

/// test precision
// pub const EPSILON_ORD: ordinate.Ordinate = 1.0e-4;
pub const EPSILON_F=  1.0e-4;

/// wrapper so that tests are skipped but not bumped for being unreachable.  to
/// use this, run: try skip_test()
pub fn skip_test() error{SkipZigTest}!void {
    if (true) {
        return error.SkipZigTest;
    }
}

/// wrapper around expectApproxEqAbs with baked in epsilon
pub inline fn expectApproxEql(
    expected: anytype,
    actual: @TypeOf(expected)
) !void 
{
    return std.testing.expectApproxEqAbs(
        expected,
        actual,
        EPSILON_F,
    );
}
