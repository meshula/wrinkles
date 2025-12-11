//! Control Point implementation
//!
//! Note that this module uses a pattern:
//!   return switch (@typeInfo(@TypeOf(rhs))) {
//!       .@"struct" => self.mul_cp(rhs),
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

        pub const zero = ControlPointType.init(
            .{ .in = 0, .out = 0 }
        );
        pub const one = ControlPointType.init(
            .{ .in = 1, .out = 1 }
        );

        pub inline fn init(
            from: ControlPoint_BaseType,
        ) ControlPointType
        {
            return .{ 
                .in =  OrdinateType.init(from.in),
                .out = OrdinateType.init(from.out),
            };
       }

        /// polymorphic dispatch for multiply
        pub inline fn mul(
            self: @This(),
            rhs: anytype,
        ) ControlPointType 
        {
            return switch (@TypeOf(rhs)) {
                ControlPointType => self.mul_cp(rhs),
                else => self.mul_num(rhs),
            };
        }

        /// multiply w/ number
        pub inline fn mul_num(
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
        pub inline fn mul_cp(
            self: @This(),
            rhs: ControlPointType,
        ) ControlPointType
        {
            return .{
                .in = rhs.in.mul(self.in),
                .out = rhs.out.mul(self.out),
            };
        }

        /// polymorphic dispatch for divide
        pub fn div(
            self: @This(),
            rhs: anytype,
        ) ControlPointType
        {
            return switch (@TypeOf(rhs)) {
                ControlPointType => self.div_cp(rhs),
                else => self.div_num(rhs),
            };
        }

        /// divide w/ number
        pub fn div_num(
            self: @This(),
            val: anytype,
        ) ControlPointType 
        {
            return .{
                .in  = self.in.div(val),
                .out = self.out.div(val),
            };
        }

        /// divide w/ struct
        pub fn div_cp(
            self: @This(),
            val: ControlPointType,
        ) ControlPointType 
        {
            return .{
                .in  = self.in.div(val.in),
                .out = self.out.div(val.out),
            };
        }

        /// polymorphic dispatch for addition
        pub fn add(
            self: @This(),
            rhs: anytype,
        ) ControlPointType 
        {
            return switch (@typeInfo(@TypeOf(rhs))) {
                .@"struct" => self.add_cp(rhs),
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
                .in = self.in.add(rhs.in),
                .out = self.out.add(rhs.out),
            };
        }

        /// polymorphic dispatch for subtract
        pub fn sub(
            self: @This(),
            rhs: anytype,
        ) ControlPointType 
        {
            return switch (@typeInfo(@TypeOf(rhs))) {
                .@"struct" => self.sub_cp(rhs),
                else => self.sub_num(rhs),
            };
        }

        /// subtract w/ struct
        pub fn sub_num(
            self: @This(),
            rhs: anytype,
        ) ControlPointType 
        {
            // @TODO: doesn't look like this gets called
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
                .in = self.in.sub(rhs.in),
                .out = self.out.sub(rhs.out),
            };
        }

        /// distance of this point from another point
        pub fn distance(
            self: @This(),
            rhs: ControlPointType,
        ) OrdinateType
        {
            const diff = rhs.sub(self);
            return (diff.in.mul(diff.in).add(diff.out.mul(diff.out))).sqrt();
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
            writer: *std.Io.Writer,
        ) !void 
        {
            try writer.print("({d}, {d})", .{ self.in, self.out });
        }
    };
}

/// Define base ControlPoint type over the ordinate from opentime
pub const ControlPoint = ControlPointOf(
    opentime.Ordinate,
    opentime.Ordinate.zero,
    opentime.Ordinate.zero,
);
pub const ControlPoint_BaseType = ControlPointOf(
    opentime.Ordinate.InnerType, 
    0,
    0,
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

        try opentime.expectOrdinateEqual(
            @field(lhs, k),
            @field(rhs, k)
        );
    }
}

// @{ TESTS
test "ControlPoint: add" 
{ 
    const cp1 = ControlPoint.init(
        .{ .in = 0, .out = 10 }
    );
    const cp2 = ControlPoint.init(
        .{ .in = 20, .out = -10 }
    );

    const result = ControlPoint.init(
        .{ .in = 20, .out = 0 }
    );

    try expectControlPointEqual(cp1.add(cp2), result);
}

test "ControlPoint: sub" 
{ 
    const cp1 = ControlPoint.init(
        .{ .in = 0, .out = 10 }
    );
    const cp2 = ControlPoint.init(
        .{ .in = 20, .out = -10 }
    );

    const result = ControlPoint.init(
        .{ .in = -20, .out = 20 }
    );

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
