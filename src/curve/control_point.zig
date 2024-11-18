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

/// A control point maps a single instantaneous input ordinate to a single
/// instantaneous output ordinate.
pub fn ControlPointOf(
    comptime t: type,
    default_in: t,
    default_out: t,
) type
{
    return struct {
        /// input ordinate
        in: t = default_in,
        /// output ordinate
        out: t = default_out,

        /// internal type aliases
        pub const OrdinateType = t;
        pub const ControlPointType = ControlPointOf(
            t,
            default_in,
            default_out,
        );

        pub inline fn init(
            from: struct {
                in: f32,
                out: f32,
            },
        ) ControlPointType
        {
            return .{ 
                .in =  OrdinateType.init(from.in),
                .out = OrdinateType.init(from.out),
            };
       }

        /// polymorphic dispatch for multiply
        pub fn mul(
            self: @This(),
            rhs: anytype,
        ) ControlPointType 
        {
            return switch (@typeInfo(@TypeOf(rhs))) {
                .Struct => self.mul_cp(rhs),
                else => self.mul_num(rhs),
            };
        }

        /// multiply w/ number
        pub fn mul_num(
            self: @This(),
            val: anytype,
        ) ControlPointType
        {
            return .{
                .in = self.in.mul(val),
                .out = self.out.mul(val),
            };
        }

        /// multiply w/ struct
        pub fn mul_cp(
            self: @This(),
            rhs: ControlPointType,
        ) ControlPointType
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
        ) ControlPointType
        {
            return switch (@typeInfo(@TypeOf(rhs))) {
                .Struct => self.div_cp(rhs),
                else => self.div_num(rhs),
            };
        }

        /// divide w/ number
        pub fn div_num(
            self: @This(),
            val: opentime.Ordinate,
        ) ControlPointType 
        {
            return .{
                .in  = self.in/val,
                .out = self.out/val,
            };
        }

        /// divide w/ struct
        pub fn div_cp(
            self: @This(),
            val: ControlPointType,
        ) ControlPointType 
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
        ) ControlPointType 
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
        ) ControlPointType 
        {
            return .{
                .in = self.in + rhs,
                .out = self.out + rhs,
            };
        }

        /// addition w/ struct
        pub fn add_cp(
            self: @This(),
            rhs: ControlPointType,
        ) ControlPointType 
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
        ) ControlPointType 
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
        ) ControlPointType 
        {
            return .{
                .in = self.in - rhs,
                .out = self.out - rhs,
            };
        }

        /// subtract w/ struct
        pub fn sub_cp(
            self: @This(),
            rhs: ControlPointType,
        ) ControlPointType 
        {
            return .{
                .in = self.in - rhs.in,
                .out = self.out - rhs.out,
            };
        }

        /// distance of this point from another point
        pub fn distance(
            self: @This(),
            rhs: ControlPointType,
        ) t
        {
            const diff = rhs.sub(self);
            return std.math.sqrt(diff.in * diff.in + diff.out * diff.out);
        }

        /// compute the normalized vector for the point
        pub fn normalized(
            self: @This(),
        ) ControlPointType 
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
            \\{{ "in": {d:.6}, "out": {d:.6} }}
            , .{ self.in, self.out, },
            );
        }

        pub fn format(
            self: @This(),
            comptime _: []const u8,
            _: std.fmt.FormatOptions,
            writer: anytype,
        ) !void 
        {
            try writer.print("({d}, {d})", .{ self.in, self.out });
        }
    };
}

/// Define base ControlPoint type over the ordinate from opentime
pub const ControlPoint = ControlPointOf(
    opentime.Ordinate,
    opentime.Ordinate.ZERO,
    opentime.Ordinate.ZERO,
);
pub const Dual_CP = opentime.dual.DualOf(ControlPoint);

/// check equality between two control points
pub fn expectControlPointEqual(
    lhs: ControlPoint,
    rhs: ControlPoint,
) !void 
{
    inline for (.{ "in", "out" }) 
        |k| 
    {
        errdefer std.log.err(
            "Error: expected {any} got {any}\n",
            .{ lhs, rhs }
        );
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
    const cp1=ControlPoint.init(.{ .in = 0.0, .out = 10.0 });
    const scale = -10.0;

    const expected=ControlPoint.init(.{ .in = 0.0, .out = -100 });
    const mul_direct = cp1.mul_num(scale);
    const mul_implct = cp1.mul(scale);

    errdefer std.log.err("result: {any}\n", .{ mul_implct });

    try expectControlPointEqual(mul_direct, mul_implct);
    try expectControlPointEqual(expected, mul_implct);
}

test "distance: 345 triangle" 
{
    const a=ControlPoint.init(.{ .in = 3, .out = -3 });
    const b=ControlPoint.init(.{ .in = 6, .out = 1 });

    try std.testing.expectEqual(
        opentime.Ordinate.init(5),
        a.distance(b)
    );
}
// @}
