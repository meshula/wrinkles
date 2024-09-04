const std = @import("std");
pub const EPSILON: f32 = 1.0e-3;
pub const inf = std.math.inf(f32);

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
        EPSILON,
    );
}
