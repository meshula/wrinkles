const std = @import("std");
const expectEqual = std.testing.expectEqual;

/// control point for curve parameterization
pub const ControlPoint = struct {
    /// temporal coordinate of the control point
    time: f32,
    /// value of the Control point at the time cooridnate
    value: f32,

    // multiply with float
    pub fn mul(self: @This(), val: f32) ControlPoint {
        return .{
            .time = val*self.time,
            .value = val*self.value,
        };
    }

    pub fn add(self: @This(), rhs: ControlPoint) ControlPoint {
        return .{
            .time = self.time + rhs.time,
            .value = self.value + rhs.value,
        };
    }

    pub fn sub(self: @This(), rhs: ControlPoint) ControlPoint {
        return .{
            .time = self.time - rhs.time,
            .value = self.value - rhs.value,
        };
    }
};

/// check equality between two control points
pub fn expectControlPointEqual(lhs: ControlPoint, rhs: ControlPoint) !void {
    inline for (.{ "time", "value" }) |k| {
        try expectEqual(@field(lhs, k), @field(rhs, k));
    }
}

// @{ TESTS
test "ControlPoint: add" { 
    const cp1 = ControlPoint{ .time = 0, .value = 10 };
    const cp2 = ControlPoint{ .time = 20, .value = -10 };

    const result = ControlPoint{ .time = 20, .value = 0 };

    try expectControlPointEqual(cp1.add(cp2), result);
}

test "ControlPoint: sub" { 
    const cp1 = ControlPoint{ .time = 0, .value = 10 };
    const cp2 = ControlPoint{ .time = 20, .value = -10 };

    const result = ControlPoint{ .time = -20, .value = 20 };

    try expectControlPointEqual(cp1.sub(cp2), result);
}

test "ControlPoint: mul" { 
    const cp1 = ControlPoint{ .time = 0, .value = 10 };
    const scale = -10;

    const result = ControlPoint{ .time = 0, .value = -100 };

    try expectControlPointEqual(cp1.mul(scale), result);
}
// @}
