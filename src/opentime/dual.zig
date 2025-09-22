//! Automatic differentiation with dual numbers library based on the comath
//! module.
//!
//! Math on duals automatically computes derivatives.

const std = @import("std");

const ordinate = @import("ordinate.zig");
const comath_wrapper = @import("comath_wrapper.zig");

/// build a dual around type T
pub fn DualOf(
    comptime T: type,
) type 
{
    return switch(@typeInfo(T)) {
        .@"struct" =>  DualOfStruct(T),
        else => DualOfNumberType(T),
    };
}

test "Dual: float + float" 
{
    const result = comath_wrapper.eval(
        "x + 3",
        .{ .x = 1}
    );
    try std.testing.expectEqual(4, result);
}

test "Dual: dual + float"
{
    const result = comath_wrapper.eval(
        "x + three",
        .{
            .x = Dual_Ord{
                .r = ordinate.Ordinate.init(3),
                .i = ordinate.Ordinate.ONE, 
            },
            .three = Dual_Ord.init(3),
        }
    );

    try ordinate.expectOrdinateEqual(
        ordinate.Ordinate.init(6),
        result.r
    );
}

test "Dual: * float"
{
    const result = comath_wrapper.eval(
        "x * 3",
        .{
            .x = Dual_Ord{
                .r = ordinate.Ordinate.init(3),
                .i = ordinate.Ordinate.init(1), 
            },
        }
    );
    try std.testing.expectEqual(
        ordinate.Ordinate.init(9),
        result.r
    );
}

/// default dual type for opentime
pub const Dual_Ord = DualOf(ordinate.Ordinate);

pub fn DualOfNumberType(
    comptime T: type,
) type 
{
    return struct {
        /// real component
        r: T = 0,
        /// infinitesimal component
        i: T = 0,

        pub const BaseType = T;
        pub const __IS_DUAL = true;

        /// initialize with i = 0
        pub fn init(
            r: T,
        ) @This() 
        {
            return .{ .r = r };
        }

        pub inline fn neg(
            self: @This(),
        ) @This() 
        {
            return .{ .r = -self.r, .i = -self.i, };
        }
        
        pub inline fn add(
            self: @This(),
            rhs: anytype,
        ) @This() 
        {
            return switch(is_dual_type((@TypeOf(rhs)))) {
                true => .{ 
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
            rhs: anytype,
        ) @This() 
        {
            return switch(is_dual_type(@TypeOf(rhs))) {
                true => .{ 
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
            return switch(is_dual_type(@TypeOf(rhs))) {
                true => .{ 
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
            rhs: anytype,
        ) @This() 
        {
            return switch(is_dual_type(@TypeOf(rhs))) {
                true => .{
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

        pub fn format(
            self: @This(),
            writer: anytype,
        ) !void 
        {
            try writer.print(
                "Dual ({s}){{ {f} + {f} }}",
                .{ @typeName(BaseType), self.r, self.i, },
            );
        }
    };
}

pub fn DualOfStruct(
    comptime T: type,
) type 
{
    return struct {
        /// real component
        r: T = T.ZERO,
        /// infinitesimal component
        i: T = T.ZERO,

        pub const BaseType = T;
        pub const DualType = @This();
        pub const __IS_DUAL = true;

        pub const ZERO_ZERO = DualType{
            .r = T.ZERO,
            .i = T.ZERO,
        };
        pub const ONE_ZERO = DualType{
            .r = T.ONE,
            .i = T.ZERO,
        };
        pub const EPSILON = DualType {
            .r = T.EPSILON,
            .i = T.ZERO,
        };

        pub inline fn init(
            r: anytype,
        ) @This()
        {
            return switch (@TypeOf(r)) {
                @This() => r,
                T => .{ .r = r },
                else => .{ .r = T.init(r)},
            };
        }

        pub inline fn init_ri(
            r: anytype,
            i: anytype,
        ) @This()
        {
            return .{
                .r = switch (@TypeOf(r)) {
                    BaseType => r,
                    else => BaseType.init(r),
                },
                .i = switch (@TypeOf(i)) {
                    BaseType => i,
                    else => BaseType.init(i),
                },
            };
        }

        pub inline fn add(
            self: @This(),
            rhs: anytype,
        ) @This() 
        {
            const rhs_r = switch (is_dual_type(@TypeOf(rhs))) {
                true => rhs.r,
                else => rhs,
            };
            const rhs_i = switch (is_dual_type(@TypeOf(rhs))) {
                true => rhs.i,
                else => BaseType.init(0.0),
            };

            return .{
                .r = comath_wrapper.eval(
                    "self_r + rhs_r",
                    .{ .self_r = self.r, .rhs_r = rhs_r }
                ),
                .i = comath_wrapper.eval(
                    "self_i + rhs_i",
                    .{ .self_i = self.i, .rhs_i = rhs_i }
                )
            };
        }

        pub inline fn sub(
            self: @This(),
            rhs: anytype,
        ) @This() 
        {
            const rhs_r = switch (is_dual_type(@TypeOf(rhs))) {
                true => rhs.r,
                else => rhs,
            };
            const rhs_i = switch (is_dual_type(@TypeOf(rhs))) {
                true => rhs.i,
                else => BaseType.init(0.0),
            };

            return .{
                .r = comath_wrapper.eval(
                    "self_r - rhs_r",
                    .{ .self_r = self.r, .rhs_r = rhs_r }
                ),
                .i = comath_wrapper.eval(
                    "self_i - rhs_i",
                    .{ .self_i = self.i, .rhs_i = rhs_i }
                )
            };
        }

        pub inline fn mul(
            self: @This(),
            rhs: anytype,
        ) DualType
        {
            return switch(is_dual_type(@TypeOf(rhs))) {
                true => .{ 
                    .r = self.r.mul(rhs.r),
                    .i = (self.r.mul(rhs.i)).add(self.i.mul(rhs.r)),
                },
                else => .{
                    .r = self.r.mul(rhs),
                    .i = self.i.mul(rhs),
                },
            };
        }

        pub inline fn div(
            self: @This(),
            rhs: anytype,
        ) @This() 
        {
            return switch(is_dual_type(@TypeOf(rhs))) {
                true => .{ 
                    .r = self.r.div(rhs.r),
                    .i = (
                        (rhs.r.mul(self.i)).sub(self.r.mul(rhs.i))).div(
                        rhs.r.mul(rhs.r)
                    ),
                },
                else => .{
                    .r = self.r.div(rhs),
                    .i = self.i.div(rhs),
                },
            };
        }

        pub inline fn sqrt(
            self: @This(),
        ) @This() 
        {
            return .{ 
                .r = self.r.sqrt(),
                .i = comath_wrapper.eval(
                    "i / (sqrt_r * 2)",
                    .{
                        .i = self.i,
                        .sqrt_r = self.r.sqrt(),
                    }
                ),
            };
        }

        pub inline fn neg(
            self: @This(),
        ) @This() 
        {
            return .{ 
                .r = self.r.neg(),
                .i = self.i.neg(),
            };
        }

        pub inline fn cos(
            self: @This()
        ) @This() 
        {
            return .{
                .r = (
                    BaseType.init(
                        std.math.cos(
                            self.r.as(ordinate.Ordinate.BaseType)
                        )
                    )
                ),
                .i = (
                    (self.i.neg()).mul(
                        BaseType.init(
                            std.math.sin(
                                self.r.as(ordinate.Ordinate.BaseType)
                            )
                        )
                    )
                ),
            };
        }

        pub inline fn acos(
            self: @This(),
        ) @This() 
        {
            return .{
                // XXX: Easier right now to route through f64 than build an
                //      acos out on opentime.Ordinate
                .r = BaseType.init(std.math.acos(self.r.as(BaseType))),
                .i = (self.i.neg()).div(
                    comath_wrapper.eval(
                        "- (r * r) + 1",
                        .{ .r = self.r }
                    )
                ).sqrt(),
            };
        }

        pub inline fn pow(
            self: @This(),
            /// exponent
            exp: anytype,
        ) @This() 
        {
            return .{
                // .r = std.math.pow(@TypeOf(self.r), self.r, exp),
                .r = self.r.pow(exp),
                // .i = (
                //     self.i 
                //     * (exp - 1) 
                //     * std.math.pow(@TypeOf(self.r), self.r, exp - 1)
                // ),
                .i = comath_wrapper.eval(
                    "i * (exp) * pow_minus_one",
                    .{
                        .i = self.i,
                        .exp = exp, 
                        .pow_minus_one = self.r.pow(exp-1),
                    }
                ),
            };
        }

        pub fn format(
            self: @This(),
            writer: anytype,
        ) !void 
        {
            try writer.print(
                "Dual ({s}){{ {f} + {f} }}",
                .{ @typeName(BaseType), self.r, self.i, },
            );
        }

        // binary tests

        /// strict equality
        pub inline fn eql(
            self: @This(),
            rhs: anytype,
        ) bool
        {
            return switch (@TypeOf(rhs)) {
                DualType => self.r.eql(rhs.r),
                else => self.r.eql(rhs),
            };
        }

        /// approximate equality with the EPSILON as the width
        pub inline fn eql_approx(
            self: @This(),
            rhs: anytype,
        ) bool
        {
            return switch (@TypeOf(rhs)) {
                DualType => (
                    self.r.lt(EPSILON.add(rhs.r))
                    and self.r.gt((EPSILON.neg().add(rhs.r)))
                ),
                else => self.r.eql(rhs),
            };
        }

        /// less than rhs
        pub inline fn lt(
            self: @This(),
            rhs: anytype,
        ) bool
        {
            return switch (@TypeOf(rhs)) {
                DualType => self.r.lt(rhs.r),
                else => self.r.lt(rhs),
            };
        }

        /// less than or equal rhs
        pub inline fn lteq(
            self: @This(),
            rhs: anytype,
        ) bool
        {
            return switch (@TypeOf(rhs)) {
                DualType => self.r.lteq(rhs.r),
                else => self.r.lteq(rhs),
            };
        }

        /// greater than rhs
        pub inline fn gt(
            self: @This(),
            rhs: anytype,
        ) bool
        {
            return switch (@TypeOf(rhs)) {
                DualType => self.r.gt(rhs.r),
                else => self.r.gt(rhs),
            };
        }

        /// greater than or equal to rhs
        pub inline fn gteq(
            self: @This(),
            rhs: anytype,
        ) bool
        {
            return switch (@TypeOf(rhs)) {
                DualType => self.r.gteq(rhs.r),
                else => self.r.gteq(rhs),
            };
        }

        inline fn type_error(
            thing: anytype,
        ) void
        {
            @compileError(
                @typeName(@This()) ++ " can only do math over floats,"
                ++ " ints, " ++ @typeName(BaseType) ++ ", and other " ++ @typeName(@This()) ++ ", not: " 
                ++ @typeName(@TypeOf(thing))
            );
        }
    };
}

test "Dual: dual test polymorphic" 
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
            .x = Dual_Ord{
                .r = ordinate.Ordinate.init(3),
                .i = ordinate.Ordinate.init(1),
            },
            .off1 = Dual_Ord.init(2),
            .off2 = Dual_Ord.init(1),
            .expect = Dual_Ord{
                .r = ordinate.Ordinate.init(20),
                .i = ordinate.Ordinate.init(9),
            },
        },
    };

    // function we want derivatives of
    const fn_str = "(x + off1) * (x + off2)";

    inline for (test_data, 0..) 
        |td, i| 
    {
        const value = comath_wrapper.eval(
            fn_str,
            .{.x = td.x, .off1 = td.off1, .off2 = td.off2}
        );

        errdefer std.debug.print(
            "{d}: Failed for type: {s}, \nrecieved: {any}\nexpected: {any}\n\n",
            .{ i,  @typeName(@TypeOf(td.x)), value, td.expect }
        );

        try std.testing.expect(std.meta.eql(value, td.expect));
    }
}

test "Dual: Dual_Ord sqrt (3-4-5 triangle)" 
{
    const d = Dual_Ord{
        .r = ordinate.Ordinate.init(3*3 + 4*4),
        .i = ordinate.Ordinate.ONE, 
    };

    try ordinate.expectOrdinateEqual(
        ordinate.Ordinate.init(5),
        d.sqrt().r,
    );
}

pub inline fn is_dual_type(
    comptime T: type,
) bool
{
    return switch (@typeInfo(T)) {
        .@"struct" => @hasDecl(T, "__IS_DUAL"),
        else => false,
    };
}

test "Dual: binary operator test"
{
    const r1 = 8;
    const r2 = 2;

    // operations over 8 and 2
    const TestCase = struct {
        op: []const u8,
        exp_r: ordinate.Ordinate.BaseType,
        exp_i: ordinate.Ordinate.BaseType,
    };
    const tests = [_]TestCase{
        .{ .op = "add", .exp_r = 10, .exp_i = 1 },
        .{ .op = "sub", .exp_r = 6,  .exp_i = 1 },
        .{ .op = "mul", .exp_r = 16, .exp_i = 2 },
        .{ .op = "div", .exp_r = 4,  .exp_i = 0.5 },
    };
    inline for (tests)
        |t|
    { 
        const x = Dual_Ord.init_ri(r1, 1);
        const x2 = @field(Dual_Ord, t.op)(x, Dual_Ord.init(r2));
        const x3 = @field(Dual_Ord, t.op)(x, r2);

        errdefer std.debug.print(
            "error with {s}({d}, {d}): expected [{d}, {d}], got: {f}\n",
            .{ t.op, r1, r2, t.exp_r, t.exp_i, x2 },
        );

        try ordinate.expectOrdinateEqual(
            t.exp_r,
            x2.r,
        );
        try ordinate.expectOrdinateEqual(
            t.exp_i,
            x2.i,
        );
        try ordinate.expectOrdinateEqual(
            t.exp_r,
            x3.r,
        );
        try ordinate.expectOrdinateEqual(
            t.exp_i,
            x3.i,
        );
    }
}

test "Dual: unary operator test"
{
    const r1 = 16;

    // operations over 8 and 2
    const TestCase = struct {
        op: []const u8,
        exp_r: ordinate.Ordinate.BaseType,
        exp_i: ordinate.Ordinate.BaseType,
    };
    const tests = [_]TestCase{
        .{ .op = "neg", .exp_r = -16, .exp_i = -1 },
        .{
            .op = "sqrt",
            .exp_r = 4, .exp_i = 1.0/(std.math.sqrt(16.0) * 2.0) 
        },
    };
    inline for (tests)
        |t|
    { 
        const x = Dual_Ord.init_ri(r1, 1);
        const x2 = @field(Dual_Ord, t.op)(x);

        errdefer std.debug.print(
            "error with {s}({d}): expected [{d}, {d}], got: {f}\n",
            .{ t.op, r1, t.exp_r, t.exp_i, x2 },
        );

        try ordinate.expectOrdinateEqual(
            t.exp_r,
            x2.r,
        );
        try ordinate.expectOrdinateEqual(
            t.exp_i,
            x2.i,
        );
    }
}

test "Dual: pow"
{ 
    const TestCase = struct{
        x: ordinate.Ordinate.BaseType,
        exp: ordinate.Ordinate.BaseType,
        exp_r: ordinate.Ordinate.BaseType,
        exp_i: ordinate.Ordinate.BaseType,
    };
    const tests = [_]TestCase{
        .{
            .x = 4,
            .exp = 1.0 / 2.0,
            // expected
            .exp_r = 2,
            .exp_i = 1.0/4.0,
        },
        .{
            .x = 4,
            .exp = 3,
            // expected
            .exp_r = 64,
            .exp_i = 48,
        },
    };

    for (tests)
        |t|
    {

        const r1 = t.x;
        const r2 = t.exp;

        const x = Dual_Ord.init_ri(r1, 1);
        const x2 = x.pow(r2);

        errdefer std.debug.print(
            "error with pow({d}, {d}): expected [{d}, {d}], got: {f}\n",
            .{ r1, r2, t.exp_r, t.exp_i, x2 },
        );

        try ordinate.expectOrdinateEqual(
            t.exp_r,
            x2.r,
        );
        try ordinate.expectOrdinateEqual(
            t.exp_i,
            x2.i,
        );
    }
}
