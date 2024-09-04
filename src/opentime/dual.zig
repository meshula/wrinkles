//! Automatic differentiation with dual numbers library based on the comath
//! module.
//!
//! Math on duals automatically computes derivatives.

const std = @import("std");
const comath = @import("comath");

const ordinate = @import("ordinate.zig");

pub fn eval(
    comptime expr: []const u8, 
    inputs: anytype,
) !comath.Eval(expr, @TypeOf(CTX), @TypeOf(inputs))
{
    return comath.eval(expr, CTX, inputs);
}

pub fn DualOf(
    comptime T: type
) type 
{
    return switch(@typeInfo(T)) {
        .Struct =>  DualOfStruct(T),
        else => DualOfNumberType(T),
    };
}

/// comath context for dual math
pub const dual_ctx = struct{
    pub fn EvalNumberLiteral(
        comptime src: []const u8
    ) type 
    {
        const result = comath.ctx.DefaultEvalNumberLiteral(src);
        if (result == comptime_float or result == comptime_int) {
            return Dual_Ord; 
        } else {
            return result;
        }
    }

    pub fn evalNumberLiteral(
        comptime src: []const u8
    ) EvalNumberLiteral(src) 
    {
        const target_type = EvalNumberLiteral(src);

        return switch (target_type) {
            .Dual_Ord => .{ 
                .r = std.fmt.parseFloat(
                    f32,
                    src
                ) catch |err| @compileError(
                @errorName(err)
                ),
                .i = 0.0,
            },
            else => comath.ctx.defaultEvalNumberLiteral(src),
        };
    }
};

/// static instantiation of the comath context
pub const CTX = comath.ctx.fnMethod(
    comath.ctx.simple({}),
    // dual_ctx,
    .{
        .@"+" = "add",
        .@"*" = "mul",
    }
);

test "dual: float + float" 
{
    const result = comath.eval(
        "x + 3",
        CTX,
        .{ .x = 1}
    ) catch |err| switch (err) {};
    try std.testing.expectEqual(@as(f32, 4), result);
}

test "dual: dual + float"
{
    const result = comath.eval(
        "x + 3",
        CTX,
        .{ .x = Dual_Ord{ .r = 3, .i = 1 }}
    ) catch |err| switch (err) {};
    try std.testing.expectEqual(@as(f32, 6), result.r);
}

test "dual * float"
{
    const result = comath.eval(
        "x * 3",
        CTX,
        .{ .x = Dual_Ord{ .r = 3, .i = 1 }}
    ) catch |err| switch (err) {};
    try std.testing.expectEqual(@as(f32, 9), result.r);
}

/// default dual type for opentime
pub const Dual_Ord = DualOf(ordinate.Ordinate);

pub fn DualOfNumberType(
    comptime T: type
) type 
{
    return struct {
        /// real component
        r: T = 0,
        /// infinitesimal component
        i: T = 0,

        /// initialize with i = 0
        pub fn init(
            r: T
        ) @This() 
        {
            return .{ .r = r };
        }

        pub inline fn negate(
            self: @This()
        ) @This() 
        {
            return .{ .r = -self.r, .i = -self.i };
        }

        pub inline fn add(
            self: @This(),
            rhs: anytype
        ) @This() 
        {
            return switch(@typeInfo(@TypeOf(rhs))) {
                .Struct => .{ 
                    .r = self.r + rhs.r,
                    .i = self.i + rhs.i,
                },
                else => .{
                    .r = self.r + rhs,
                    .i = self.i,
                },
            };
        }

        pub inline fn sub(
            self: @This(),
            rhs: anytype
        ) @This() 
        {
            return switch(@typeInfo(@TypeOf(rhs))) {
                .Struct => .{ 
                    .r = self.r - rhs.r,
                    .i = self.i - rhs.i,
                },
                else => .{
                    .r = self.r - rhs,
                    .i = self.i,
                },
            };
        }

        pub inline fn mul(
            self: @This(),
            rhs: anytype
        ) @This() 
        {
            return switch(@typeInfo(@TypeOf(rhs))) {
                .Struct => .{ 
                    .r = self.r * rhs.r,
                    .i = self.r * rhs.i + self.i*rhs.r,
                },
                else => .{
                    .r = self.r * rhs,
                    .i = self.i * rhs,
                },
            };
        }

        pub inline fn lt(
            self: @This(),
            rhs: @This()
        ) @This() 
        {
            return self.r < rhs.r;
        }

        pub inline fn gt(
            self: @This(),
            rhs: @This()
        ) @This() 
        {
            return self.r > rhs.r;
        }

        pub inline fn div(
            self: @This(),
            rhs: anytype
        ) @This() 
        {
            return switch(@typeInfo(@TypeOf(rhs))) {
                .Struct => .{
                    .r = self.r / rhs.r,
                    .i = (rhs.r * self.i - self.r * rhs.i) / (rhs.r * rhs.r),
                },
                else => .{
                    .r = self.r / rhs,
                    .i = (self.i) / (rhs),
                },
            };
        }

        /// derivative is self.i * f'(self.r)
        pub inline fn sqrt(
            self: @This()
        ) @This() 
        {
            return .{ 
                .r = std.math.sqrt(self.r),
                .i = self.i / (2 * std.math.sqrt(self.r)),
            };
        }

        pub inline fn cos(
            self: @This()
        ) @This() 
        {
            return .{
                .r = std.math.cos(self.r),
                .i = -self.i * std.math.sin(self.r),
            };
        }

        pub inline fn acos(
            self: @This()
        ) @This() 
        {
            return .{
                .r = std.math.acos(self.r),
                .i = -self.i / std.math.sqrt(1 - (self.r * self.r)),
            };
        }

        pub inline fn pow(
            self: @This(),
            y: @TypeOf(self.r)
        ) @This() 
        {
            return .{
                .r = std.math.pow(@TypeOf(self.r), self.r, y),
                .i = (
                    self.i 
                    * (y - 1) 
                    * std.math.pow(@TypeOf(self.r), self.r, y - 1)
                ),
            };
        }
    };
}

pub fn DualOfStruct(
    comptime T: type
) type 
{
    return struct {
        /// real component
        r: T = .{},
        /// infinitesimal component
        i: T = .{},

        pub fn from(
            r: T
        ) @TypeOf(@This()) 
        {
            return .{ .r = r };
        }

        pub inline fn add(
            self: @This(),
            rhs: @This()
        ) @This() 
        {
            return .{
                .r = comath.eval(
                    "self_r + rhs_r",
                    CTX,
                    .{ .self_r = self.r, .rhs_r = rhs.r }
                ) catch |err| switch (err) {},
                .i = comath.eval(
                    "self_i + rhs_i",
                    CTX,
                    .{ .self_i = self.i, .rhs_i = rhs.i }
                ) catch |err| switch (err) {}
            };
        }

        pub inline fn mul(
            self: @This(),
            rhs: anytype
        ) @This() 
        {
            return switch(@typeInfo(@TypeOf(rhs))) {
                .Struct => .{ 
                    .r = self.r.mul(rhs.r),
                    .i = (self.r.mul(rhs.i)).add(self.i.mul(rhs.r)),
                },
                else => .{
                    .r = self.r.mul(rhs),
                    .i = self.i.mul(rhs),
                },
            };
        }
    };
}

test "comath dual test polymorphic" 
{
    const test_data = &.{
        // as float
        .{
            .x = 3,
            .off1 = 2,
            .off2 = 1 ,
            .expect = 20,
        },
        // as float dual
        .{
            .x = Dual_Ord{.r = 3, .i = 1},
            .off1 = Dual_Ord{ .r = 2 },
            .off2 = Dual_Ord{ .r = 1 }, 
            .expect = Dual_Ord{ .r = 20, .i = 9},
        },
    };

    // function we want derivatives of
    const fn_str = "(x + off1) * (x + off2)";

    inline for (test_data, 0..) 
        |td, i| 
    {
        const value = comath.eval(
            fn_str,
            CTX,
            .{.x = td.x, .off1 = td.off1, .off2 = td.off2}
        ) catch |err| switch (err) {};

        errdefer std.debug.print(
            "{d}: Failed for type: {s}, \nrecieved: {any}\nexpected: {any}\n\n",
            .{ i,  @typeName(@TypeOf(td.x)), value, td.expect }
        );

        try std.testing.expect(std.meta.eql(value, td.expect));
    }
}

test "Dual_Ord sqrt (3-4-5 triangle)" 
{
    const d = Dual_Ord{ .r = (3*3 + 4*4), .i = 1 };

    try std.testing.expectApproxEqAbs(
        @as(f32, 5),
        d.sqrt().r,
        0.00000001
    );
}
