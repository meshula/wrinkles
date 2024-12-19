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

/// build a dual around type T
pub fn DualOf(
    comptime T: type,
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
        comptime src: []const u8,
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
        comptime src: []const u8,
    ) EvalNumberLiteral(src) 
    {
        const target_type = EvalNumberLiteral(src);

        return switch (target_type) {
            .Dual_Ord => .{ 
                .r = std.fmt.parseFloat(
                    ordinate.Ordinate,
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
        .@"-" = &.{"sub", "neg"},
        .@"/" = "div",
    },
);

test "Dual: float + float" 
{
    const result = comath.eval(
        "x + 3",
        CTX,
        .{ .x = 1}
    ) catch |err| switch (err) {};
    try std.testing.expectEqual(4, result);
}

test "Dual: dual + float"
{
    const result = comath.eval(
        "x + three",
        CTX,
        .{
            .x = Dual_Ord{
                .r = ordinate.Ordinate.init(3),
                .i = ordinate.Ordinate.ONE, 
            },
            .three = Dual_Ord.init(3),
        }
    ) catch |err| switch (err) {};

    try ordinate.expectOrdinateEqual(
        ordinate.Ordinate.init(6),
        result.r
    );
}

test "Dual: * float"
{
    const result = comath.eval(
        "x * 3",
        CTX,
        .{
            .x = Dual_Ord{
                .r = ordinate.Ordinate.init(3),
                .i = ordinate.Ordinate.init(1), 
            },
        }
    ) catch |err| switch (err) {};
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
            // fmt
            comptime _: []const u8,
            // options
            _: std.fmt.FormatOptions,
            writer: anytype,
        ) !void 
        {
            try writer.print(
                "Dual ({s}){{ {s} + {s} }}",
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
                .r = comath.eval(
                    "self_r + rhs_r",
                    CTX,
                    .{ .self_r = self.r, .rhs_r = rhs_r }
                ) catch |err| switch (err) {},
                .i = comath.eval(
                    "self_i + rhs_i",
                    CTX,
                    .{ .self_i = self.i, .rhs_i = rhs_i }
                ) catch |err| switch (err) {}
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
                .r = comath.eval(
                    "self_r - rhs_r",
                    CTX,
                    .{ .self_r = self.r, .rhs_r = rhs_r }
                ) catch |err| switch (err) {},
                .i = comath.eval(
                    "self_i - rhs_i",
                    CTX,
                    .{ .self_i = self.i, .rhs_i = rhs_i }
                ) catch |err| switch (err) {}
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
                .i = ordinate.eval(
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
                .r = BaseType.init(std.math.acos(self.r.as(f32))),
                .i = (self.i.neg()).div(
                    comath.eval(
                        "- (r * r) + 1",
                        CTX,
                        .{ .r = self.r }
                    ) catch @panic("invalid acos")
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
                .i = comath.eval(
                    "i * (exp) * pow_minus_one",
                    CTX,
                    .{
                        .i = self.i,
                        .exp = exp, 
                        .pow_minus_one = self.r.pow(exp-1),
                    }
                ) catch @panic("invalid pow"),
            };
        }

        pub fn format(
            self: @This(),
            // fmt
            comptime _: []const u8,
            // options
            _: std.fmt.FormatOptions,
            writer: anytype,
        ) !void 
        {
            try writer.print(
                "Dual ({s}){{ {s} + {s} }}",
                .{ @typeName(BaseType), self.r, self.i, },
            );
        }
    };
}

test "Dual: comath dual test polymorphic" 
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
        .Struct => @hasDecl(T, "__IS_DUAL"),
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
        exp_r: f32,
        exp_i: f32,
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
            "error with {s}({d}, {d}): expected [{d}, {d}], got: {s}\n",
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
            "error with {s}({d}): expected [{d}, {d}], got: {s}\n",
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
        x: f32,
        exp: f32,
        exp_r: f32,
        exp_i: f32,
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
            "error with pow({d}, {d}): expected [{d}, {d}], got: {s}\n",
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
