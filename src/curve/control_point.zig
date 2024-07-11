//! Control Point implementation
//!
//! Note that this module uses a pattern:
//!   return switch (@typeInfo(@TypeOf(rhs))) {
//!       .Struct => self.mul_cp(rhs),
//!       else => self.mul_num(rhs),
//!   };
//!
//! Other parts of the Wrinkles project use the "comath" library to do
//! operator-overloaded math.  This pattern allows polymorphism with some type
//! specification,in other words, mul can be called with either a float or a
//! ControlPoint argument but not a []const u8, despite the anytype.
//!

const std = @import("std");
const expectEqual = std.testing.expectEqual;
const dual = @import("opentime").dual;

const generic_curve = @import("generic_curve.zig");

pub const Dual_CP = dual.DualOf(ControlPoint);

/// control point for curve parameterization
pub const ControlPoint = struct {
    /// temporal coordinate of the control point
    time: f32 = 0,
    /// value of the Control point at the time cooridnate
    value: f32 = 0,

    // polymorphic dispatch
    pub fn mul(
        self: @This(),
        rhs: anytype,
    ) ControlPoint 
    {
        return switch (@typeInfo(@TypeOf(rhs))) {
            .Struct => self.mul_cp(rhs),
            else => self.mul_num(rhs),
        };
    }

    pub fn mul_num(
        self: @This(),
        val: f32,
    ) ControlPoint 
    {
        return .{
            .time = val*self.time,
            .value = val*self.value,
        };
    }

    pub fn mul_cp(
        self: @This(),
        rhs: ControlPoint,
    ) ControlPoint 
    {
        return .{
            .time = rhs.time*self.time,
            .value = rhs.value*self.value,
        };
    }

    pub fn div(
        self: @This(),
        rhs: anytype,
    ) ControlPoint 
    {
        return switch (@typeInfo(@TypeOf(rhs))) {
            .Struct => self.div_cp(rhs),
            else => self.div_num(rhs),
        };
    }

    pub fn div_num(
        self: @This(),
        val: f32,
    ) ControlPoint 
    {
        return .{
            .time  = self.time/val,
            .value = self.value/val,
        };
    }

    pub fn div_cp(
        self: @This(),
        val: ControlPoint,
    ) ControlPoint 
    {
        return .{
            .time  = self.time/val.time,
            .value = self.value/val.value,
        };
    }

    pub fn add(
        self: @This(),
        rhs: anytype,
    ) ControlPoint 
    {
        return switch (@typeInfo(@TypeOf(rhs))) {
            .Struct => self.add_cp(rhs),
            else => self.add_num(rhs),
        };
    }

    pub fn add_num(
        self: @This(),
        rhs: anytype,
    ) ControlPoint 
    {
        return .{
            .time = self.time + rhs,
            .value = self.value + rhs,
        };
    }


    pub fn add_cp(
        self: @This(),
        rhs: ControlPoint,
    ) ControlPoint 
    {
        return .{
            .time = self.time + rhs.time,
            .value = self.value + rhs.value,
        };
    }

    pub fn sub(
        self: @This(),
        rhs: anytype,
    ) ControlPoint 
    {
        return switch (@typeInfo(@TypeOf(rhs))) {
            .Struct => self.sub_cp(rhs),
            else => self.sub_num(rhs),
        };
    }

    pub fn sub_cp(
        self: @This(),
        rhs: ControlPoint,
    ) ControlPoint 
    {
        return .{
            .time = self.time - rhs.time,
            .value = self.value - rhs.value,
        };
    }

    pub fn sub_num(
        self: @This(),
        rhs: anytype,
    ) ControlPoint 
    {
        return .{
            .time = self.time - rhs,
            .value = self.value - rhs,
        };
    }

    pub fn distance(
        self: @This(),
        rhs: ControlPoint,
    ) f32 
    {
        const diff = rhs.sub(self);
        return std.math.sqrt(diff.time * diff.time + diff.value * diff.value);
    }

    pub fn normalized(
        self: @This(),
    ) ControlPoint 
    {
        const d = self.distance(.{ .time=0, .value=0 });
        return .{ .time = self.time/d, .value = self.value/d };
    }
    
    pub fn debug_json_str(
        self: @This(),
        allocator: std.mem.Allocator,
    ) ![]const u8 
    {
        return try std.fmt.allocPrint(
            allocator,
            \\{{ "time": {d:.6}, "value": {d:.6} }}
            , .{ self.time, self.value, }
        );
    }
};

/// check equality between two control points
pub fn expectControlPointEqual(
    lhs: ControlPoint,
    rhs: ControlPoint,
) !void 
{
    inline for (.{ "time", "value" }) 
        |k| 
    {
        errdefer std.log.err("Error: expected {any} got {any}\n", .{ lhs, rhs });
        try std.testing.expectApproxEqAbs(
            @field(lhs, k),
            @field(rhs, k),
            generic_curve.EPSILON
        );
    }
}

// @{ TESTS
test "ControlPoint: add" 
{ 
    const cp1 = ControlPoint{ .time = 0, .value = 10 };
    const cp2 = ControlPoint{ .time = 20, .value = -10 };

    const result = ControlPoint{ .time = 20, .value = 0 };

    try expectControlPointEqual(cp1.add(cp2), result);
}

test "ControlPoint: sub" 
{ 
    const cp1 = ControlPoint{ .time = 0, .value = 10 };
    const cp2 = ControlPoint{ .time = 20, .value = -10 };

    const result = ControlPoint{ .time = -20, .value = 20 };

    try expectControlPointEqual(cp1.sub(cp2), result);
}

test "ControlPoint: mul" 
{ 
    const cp1:ControlPoint = .{ .time = 0.0, .value = 10.0 };
    const scale = -10.0;

    const expected:ControlPoint = .{ .time = 0.0, .value = -100 };
    const mul_direct = cp1.mul_num(scale);
    const mul_implct = cp1.mul(scale);

    errdefer std.log.err("result: {any}\n", .{ mul_implct });

    try expectControlPointEqual(mul_direct, mul_implct);
    try expectControlPointEqual(expected, mul_implct);
}

test "distance: 345 triangle" 
{
    const a:ControlPoint = .{ .time = 3, .value = -3 };
    const b:ControlPoint = .{ .time = 6, .value = 1 };

    try expectEqual(
        @as(f32, 5),
        a.distance(b)
    );
}
// @}
