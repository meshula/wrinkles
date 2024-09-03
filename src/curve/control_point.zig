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

const opentime = @import("opentime");

const generic_curve = @import("generic_curve.zig");

pub const Dual_CP = opentime.dual.DualOf(ControlPoint);

/// A control point maps a single instantaneous input ordinate to a single
/// output ordinate.
pub const ControlPoint = struct {
    /// input ordinate
    in: opentime.Ordinate = 0,
    /// output ordinate
    out: opentime.Ordinate = 0,

    /// polymorphic dispatch for multiply
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

    /// multiply w/ number
    pub fn mul_num(
        self: @This(),
        val: f32,
    ) ControlPoint 
    {
        return .{
            .in = val*self.in,
            .out = val*self.out,
        };
    }

    /// multiply w/ struct
    pub fn mul_cp(
        self: @This(),
        rhs: ControlPoint,
    ) ControlPoint 
    {
        return .{
            .in = rhs.in*self.in,
            .out = rhs.out*self.out,
        };
    }

    /// polymorphic dispatch for divide
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

    /// divide w/ number
    pub fn div_num(
        self: @This(),
        val: f32,
    ) ControlPoint 
    {
        return .{
            .in  = self.in/val,
            .out = self.out/val,
        };
    }

    /// divide w/ struct
    pub fn div_cp(
        self: @This(),
        val: ControlPoint,
    ) ControlPoint 
    {
        return .{
            .in  = self.in/val.in,
            .out = self.out/val.out,
        };
    }

    /// polymorphic dispatch for addition
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

    /// addition w/ number
    pub fn add_num(
        self: @This(),
        rhs: anytype,
    ) ControlPoint 
    {
        return .{
            .in = self.in + rhs,
            .out = self.out + rhs,
        };
    }

    /// addition w/ struct
    pub fn add_cp(
        self: @This(),
        rhs: ControlPoint,
    ) ControlPoint 
    {
        return .{
            .in = self.in + rhs.in,
            .out = self.out + rhs.out,
        };
    }

    /// polymorphic dispatch for subtract
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

    /// subtract w/ struct
    pub fn sub_num(
        self: @This(),
        rhs: anytype,
    ) ControlPoint 
    {
        return .{
            .in = self.in - rhs,
            .out = self.out - rhs,
        };
    }

    /// subtract w/ struct
    pub fn sub_cp(
        self: @This(),
        rhs: ControlPoint,
    ) ControlPoint 
    {
        return .{
            .in = self.in - rhs.in,
            .out = self.out - rhs.out,
        };
    }

    /// distance of the point from the origin
    pub fn distance(
        self: @This(),
        rhs: ControlPoint,
    ) f32 
    {
        const diff = rhs.sub(self);
        return std.math.sqrt(diff.in * diff.in + diff.out * diff.out);
    }

    /// compute the normalized vector for the point
    pub fn normalized(
        self: @This(),
    ) ControlPoint 
    {
        const d = self.distance(.{ .in=0, .out=0 });
        return .{ .in = self.in/d, .out = self.out/d };
    }
    
    /// build a string of the control point
    pub fn debug_json_str(
        self: @This(),
        allocator: std.mem.Allocator,
    ) ![]const u8 
    {
        return try std.fmt.allocPrint(
            allocator,
            \\{{ "time": {d:.6}, "value": {d:.6} }}
            , .{ self.in, self.out, }
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
    const cp1 = ControlPoint{ .in = 0, .out = 10 };
    const cp2 = ControlPoint{ .in = 20, .out = -10 };

    const result = ControlPoint{ .in = 20, .out = 0 };

    try expectControlPointEqual(cp1.add(cp2), result);
}

test "ControlPoint: sub" 
{ 
    const cp1 = ControlPoint{ .in = 0, .out = 10 };
    const cp2 = ControlPoint{ .in = 20, .out = -10 };

    const result = ControlPoint{ .in = -20, .out = 20 };

    try expectControlPointEqual(cp1.sub(cp2), result);
}

test "ControlPoint: mul" 
{ 
    const cp1:ControlPoint = .{ .in = 0.0, .out = 10.0 };
    const scale = -10.0;

    const expected:ControlPoint = .{ .in = 0.0, .out = -100 };
    const mul_direct = cp1.mul_num(scale);
    const mul_implct = cp1.mul(scale);

    errdefer std.log.err("result: {any}\n", .{ mul_implct });

    try expectControlPointEqual(mul_direct, mul_implct);
    try expectControlPointEqual(expected, mul_implct);
}

test "distance: 345 triangle" 
{
    const a:ControlPoint = .{ .in = 3, .out = -3 };
    const b:ControlPoint = .{ .in = 6, .out = 1 };

    try std.testing.expectEqual(
        @as(f32, 5),
        a.distance(b)
    );
}
// @}
