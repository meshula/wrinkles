//! Ordinate type and support math for opentime

const std = @import("std");
const comath_wrapper = @import("comath_wrapper.zig");

const util = @import("util.zig");

/// Construct Struct wrapper around a POD value as Ordinate
fn OrdinateOf(
    comptime t: type,
) type
{
    return struct {
        v : t,

        pub const BaseType = t;
        pub const OrdinateType = @This();
        pub const ZERO : OrdinateType = OrdinateType.init(0);
        pub const ONE : OrdinateType = OrdinateType.init(1);
        pub const INF : OrdinateType = OrdinateType.init(std.math.inf(t));
        pub const INF_NEG : OrdinateType = OrdinateType.init(-std.math.inf(t));
        pub const NAN : OrdinateType = OrdinateType.init(std.math.nan(t));
        pub const EPSILON = OrdinateType.init(util.EPSILON_F);

        /// build an ordinate out of the incoming value, casting as necessary
        pub inline fn init(
            value: anytype,
        ) OrdinateType
        {
            return switch (@typeInfo(@TypeOf(value))) {
                .float, .comptime_float => .{ .v = @floatCast(value) },
                .int, .comptime_int => .{ .v = @floatFromInt(value) },
                else => @compileError(
                    "Can only be constructed from a float or an int, not"
                    ++ " a " ++ @typeName(@TypeOf(value))
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
            try writer.print( "Ord{{ {d} }}", .{ self.v });
        }

        inline fn type_error(
            thing: anytype,
        ) void
        {
            @compileError(
                @typeName(@This()) ++ " can only do math over floats,"
                ++ " ints and other " ++ @typeName(@This()) ++ ", not: " 
                ++ @typeName(@TypeOf(thing))
            );
        }

        /// unbox and cast to the target type. @TODO: remove this in favor of
        /// directly unboxing at the API site?
         pub inline fn as(
             self: @This(),
             comptime T: type,
         ) T
         {
             return switch (@typeInfo(T)) {
                .float => (
                    @floatCast(self.v) 
                ),
                .int => @intFromFloat(self.v),
                else => @compileError(
                    "Ordinate can be retrieved as a float or int type,"
                    ++ " not: " ++ @typeName(T)
                ),
             };
         }

        // unary operators

        /// negate the ordinate (ie *= -1)
        pub inline fn neg(
            self: @This(),
        ) OrdinateType
        {
            return .{
                .v = - self.v,
            };
        }

        /// return the square root of the ordinate
        pub inline fn sqrt(
            self: @This(),
        ) OrdinateType
        {
            return .{
                .v = std.math.sqrt(self.v),
            };
        }

        /// return the absolute value of the ordinate
        pub inline fn abs(
            self: @This(),
        ) OrdinateType
        {
            return .{
                .v = @abs(self.v),
            };
        }

        // binary operators

        /// add to rhs, constructing an Ordinate as necessary
        pub inline fn add(
            self: @This(),
            rhs: anytype,
        ) OrdinateType
        {
            return switch (@TypeOf(rhs)) {
                OrdinateType => .{ .v = self.v + rhs.v },
                else => switch (@typeInfo(@TypeOf(rhs))) {
                    .float, .comptime_float, => .{
                        .v = self.v + @as(BaseType, @floatCast(rhs)),
                    },
                    .int, .comptime_int => .{ 
                        .v = self.v + @as(BaseType, @floatFromInt(rhs)),
                    },
                    else => type_error(rhs),
                },
            };
        }

        /// subtract rhs from self
        pub inline fn sub(
            self: @This(),
            rhs: anytype,
        ) OrdinateType
        {
            return switch (@TypeOf(rhs)) {
                OrdinateType => .{ .v = self.v - rhs.v },
                else => switch (@typeInfo(@TypeOf(rhs))) {
                    .float, .comptime_float, => .{
                        .v = self.v - @as(BaseType, @floatCast(rhs)),
                    },
                    .int, .comptime_int => .{ 
                        .v = self.v - @as(BaseType, @floatFromInt(rhs)),
                    },
                    else => type_error(rhs),
                },
            };
        }

        /// multiply rhs with self
        pub inline fn mul(
            self: @This(),
            rhs: anytype,
        ) OrdinateType
        {
            return switch (@TypeOf(rhs)) {
                OrdinateType => .{ .v = self.v * rhs.v },
                else => switch (@typeInfo(@TypeOf(rhs))) {
                    .float, .comptime_float, => .{
                        .v = self.v * @as(BaseType, @floatCast(rhs)),
                    },
                    .int, .comptime_int => .{ 
                        .v = self.v * @as(BaseType, @floatFromInt(rhs)),
                    },
                    else => type_error(rhs),
                },
            };
        }

        /// divide self by rhs
        pub inline fn div(
            self: @This(),
            rhs: anytype,
        ) OrdinateType
        {
            return switch (@TypeOf(rhs)) {
                OrdinateType => .{ .v = self.v / rhs.v },
                else => switch (@typeInfo(@TypeOf(rhs))) {
                    .float, .comptime_float, => .{
                        .v = self.v / @as(BaseType, @floatCast(rhs)),
                    },
                    .int, .comptime_int => .{ 
                        .v = self.v / @as(BaseType, @floatFromInt(rhs)),
                    },
                    else => type_error(rhs),
                },
            };
        }

        // binary macros

        /// wrapper around std.math.pow for Ordinate
        pub inline fn pow(
            self: @This(),
            exp: BaseType,
        ) OrdinateType
        {
            return .{ .v = std.math.pow(BaseType, self.v, exp) };
        }

        pub inline fn min(
            self: @This(),
            rhs: anytype,
        ) OrdinateType
        {
            return switch (@TypeOf(rhs)) {
                OrdinateType => .{ .v = @min(self.v,rhs.v) },
                else => switch (@typeInfo(@TypeOf(rhs))) {
                    .float, .comptime_float, .int, .comptime_int => .{ 
                        .v = @min(self.v,rhs)
                    },
                    else => type_error(rhs),
                },
            };
        }

        pub inline fn max(
            self: @This(),
            rhs: anytype,
        ) OrdinateType
        {
            return switch (@TypeOf(rhs)) {
                OrdinateType => .{ .v = @max(self.v,rhs.v) },
                else => switch (@typeInfo(@TypeOf(rhs))) {
                    .float, .comptime_float, .int, .comptime_int => .{ 
                        .v = @max(self.v,rhs)
                    },
                    else => type_error(rhs),
                },
            };
        }

        // binary tests

        /// strict equality
        pub inline fn eql(
            self: @This(),
            rhs: anytype,
        ) bool
        {
            return switch (@TypeOf(rhs)) {
                OrdinateType => self.v == rhs.v,
                else => switch (@typeInfo(@TypeOf(rhs))) {
                    .float, .comptime_float, .int, .comptime_int => self.v == rhs,
                    else => type_error(rhs),
                },
            };
        }

        /// approximate equality with the EPSILON as the width
        pub inline fn eql_approx(
            self: @This(),
            rhs: anytype,
        ) bool
        {
            return switch (@TypeOf(rhs)) {
                OrdinateType => (
                    self.v < rhs.v + EPSILON.v 
                    and self.v > rhs.v - EPSILON.v
                ),
                else => switch (@typeInfo(@TypeOf(rhs))) {
                    .float, .comptime_float, .int, .comptime_int => (
                        self.v < rhs.v + EPSILON.v and self.v > rhs.v - EPSILON.v
                    ),
                    else => type_error(rhs),
                },
            };
        }

        /// less than rhs
        pub inline fn lt(
            self: @This(),
            rhs: anytype,
        ) bool
        {
            return switch (@TypeOf(rhs)) {
                OrdinateType => self.v < rhs.v,
                else => switch (@typeInfo(@TypeOf(rhs))) {
                    .float, .comptime_float, .int, .comptime_int => self.v < rhs,
                    else => type_error(rhs),
                },
            };
        }

        /// less than or equal rhs
        pub inline fn lteq(
            self: @This(),
            rhs: anytype,
        ) bool
        {
            return switch (@TypeOf(rhs)) {
                OrdinateType => self.v <= rhs.v,
                else => switch (@typeInfo(@TypeOf(rhs))) {
                    .float, .comptime_float, .int, .comptime_int => self.v <= rhs,
                    else => type_error(rhs),
                },
            };
        }

        /// greater than rhs
        pub inline fn gt(
            self: @This(),
            rhs: anytype,
        ) bool
        {
            return switch (@TypeOf(rhs)) {
                OrdinateType => self.v > rhs.v,
                else => switch (@typeInfo(@TypeOf(rhs))) {
                    .float, .comptime_float, .int, .comptime_int => self.v > rhs,
                    else => type_error(rhs),
                },
            };
        }

        /// greater than or equal to rhs
        pub inline fn gteq(
            self: @This(),
            rhs: anytype,
        ) bool
        {
            return switch (@TypeOf(rhs)) {
                OrdinateType => self.v >= rhs.v,
                else => switch (@typeInfo(@TypeOf(rhs))) {
                    .float, .comptime_float, .int, .comptime_int => self.v >= rhs,
                    else => type_error(rhs),
                },
            };
        }

        /// if the ordinate is infinite
        pub inline fn is_inf(
            self: @This(),
        ) bool
        {
            return std.math.isInf(self.v);
        }

        /// if the ordinate is finite
        pub inline fn is_finite(
            self: @This(),
        ) bool
        {
            return std.math.isFinite(self.v);
        }

        /// if the ordinate is a NaN
        pub inline fn is_nan(
            self: @This(),
        ) bool
        {
            return std.math.isNan(self.v);
        }
    };
}

/// ordinate type
// pub const Ordinate = OrdinateOf(f32);
pub const Ordinate = OrdinateOf(f64);


/// compare two ordinates.  Create an ordinate from expected if it is not
/// already one.  NaN == NaN is true.
pub fn expectOrdinateEqual(
    expected_in: anytype,
    measured_in: anyerror!Ordinate,
) !void
{
    const expected = switch(@TypeOf(expected_in)) {
        Ordinate => expected_in,
        else => switch(@typeInfo(@TypeOf(expected_in))) {
            .comptime_int, .int, .comptime_float, .float => (
                Ordinate.init(expected_in)
            ),
            else => @compileError(
                "Error: can only compare an Ordinate to a float, int, or "
                ++ "other Ordinate.  Got a: " ++ @typeName(@TypeOf(expected_in))
            ),
        },
    };

    const measured = try measured_in;

    if (expected.is_nan() and measured.is_nan()) {
        return;
    }

    inline for (std.meta.fields(Ordinate))
        |f|
    {
        errdefer std.log.err(
            "field: " ++ f.name ++ " did not match.", .{}
        );
        switch (@typeInfo(f.type)) {
            .int, .comptime_int => try std.testing.expectEqual(
                @field(expected, f.name),
                @field(measured, f.name),
            ),
            .float, .comptime_float => try std.testing.expectApproxEqAbs(
                @field(expected, f.name),
                @field(measured, f.name),
                // util.EPSILON_F,
                1e-3,
            ),
            inline else => @compileError(
                "Do not know how to handle fields of type: " ++ f.type
            ),
        }
    }
}

/// wrapper structure for tests
const basic_math = struct {
    // unary
    pub inline fn neg(in: anytype) @TypeOf(in) { return 0-in; }
    pub inline fn sqrt(in: anytype) @TypeOf(in) { return std.math.sqrt(in); }
    pub inline fn abs(in: anytype) @TypeOf(in) { return @abs(in); }
    pub inline fn normalized(in: anytype) @TypeOf(in) { return in; }

    // binary
    pub inline fn add(lhs: anytype, rhs: anytype) @TypeOf(lhs) { return lhs + rhs; }
    pub inline fn sub(lhs: anytype, rhs: anytype) @TypeOf(lhs) { return lhs - rhs; }
    pub inline fn mul(lhs: anytype, rhs: anytype) @TypeOf(lhs) { return lhs * rhs; }
    pub inline fn div(lhs: anytype, rhs: anytype) @TypeOf(lhs) { return lhs / rhs; }

    // binary macros
    pub inline fn min(lhs: anytype, rhs: anytype) @TypeOf(lhs) { return @min(lhs, rhs); }
    pub inline fn max(lhs: anytype, rhs: anytype) @TypeOf(lhs) { return @max(lhs, rhs); }

    // binline fnary tests
    pub inline fn eql(lhs: anytype, rhs: anytype) bool { return lhs == rhs; }
    pub inline fn eql_approx(lhs: anytype, rhs: anytype) bool { return std.math.approxEqAbs(Ordinate.BaseType, lhs, rhs, util.EPSILON_F); }
    pub inline fn gt(lhs: anytype, rhs: anytype) bool { return lhs > rhs; }
    pub inline fn gteq(lhs: anytype, rhs: anytype) bool { return lhs >= rhs; }
    pub inline fn lt(lhs: anytype, rhs: anytype) bool { return lhs < rhs; }
    pub inline fn lteq(lhs: anytype, rhs: anytype) bool { return lhs <= rhs; }
};

test "Base Ordinate: Unary Operator Tests"
{
    const TestCase = struct {
        in: Ordinate.BaseType,
    };
    const tests = &[_]TestCase{
        .{ .in =  1 },
        .{ .in =  -1 },
        .{ .in = 25 },
        .{ .in = 64.34 },
        .{ .in =  5.345 },
        .{ .in =  -5.345 },
        .{ .in =  0 },
        .{ .in =  -0.0 },
        .{ .in =  std.math.inf(Ordinate.BaseType) },
        .{ .in =  -std.math.inf(Ordinate.BaseType) },
        .{ .in =  std.math.nan(Ordinate.BaseType) },
    };

    inline for (&.{ "neg", "sqrt", "abs",})
        |op|
    {
        for (tests)
            |t|
        {
            const expected_in = (@field(basic_math, op)(t.in));
            const expected = Ordinate.init(expected_in);

            const in = Ordinate.init(t.in);
            const measured = @field(Ordinate, op)(in);

            errdefer std.debug.print(
                "Error with test: \n" ++ @typeName(Ordinate) ++ "." ++ op 
                ++ ":\n iteration: {any}\nin: {d}\nexpected_in: {d}\n"
                ++ "expected: {d}\nmeasured_in: {s}\nmeasured: {s}\n",
                .{ t, t.in, expected_in, expected, in, measured },
            );

            try expectOrdinateEqual(expected, measured);
        }
    }
}

test "Base Ordinate: Binary Operator Tests"
{
    const values = [_]Ordinate.BaseType{
        0,
        1,
        1.2,
        5.345,
        3.14159,
        std.math.pi,
        // 0.45 not exactly representable in binary floating point numbers
        1001.45,
        std.math.inf(Ordinate.BaseType),
        std.math.nan(Ordinate.BaseType),
    };

    const signs = [_]Ordinate.BaseType{ -1, 1 };

    inline for (&.{ "add", "sub", "mul", "div", })
        |op|
    {
        for (values)
            |lhs_v|
        {
            for (signs)
                |s_lhs|
            {
                for (values)
                    |rhs_v|
                {
                    for (signs) 
                        |s_rhs|
                    {
                        const lhs_sv = s_lhs * lhs_v;
                        const rhs_sv = s_rhs * rhs_v;

                        const expected = Ordinate.init(
                           @field(basic_math, op)(
                               lhs_sv,
                               rhs_sv
                            ) 
                        );

                        const lhs_o = Ordinate.init(lhs_sv);
                        const rhs_o = Ordinate.init(rhs_sv);

                        const measured = (
                            @field(Ordinate, op)(lhs_o, rhs_o)
                        );

                        errdefer std.debug.print(
                            "Error with test: " ++ @typeName(Ordinate) 
                            ++ "." ++ op ++ ": \nlhs: {d} * {d} rhs: {d} * {d}\n"
                            ++ "lhs_sv: {d} rhs_sv: {d}\n"
                            ++ "{s} " ++ op ++ " {s}\n"
                            ++ "expected: {d}\nmeasured: {s}\n",
                            .{
                                s_lhs, lhs_v,
                                s_rhs, rhs_v,
                                lhs_sv, rhs_sv,
                                lhs_o, rhs_o,
                                expected, measured,
                            },
                        );

                        if ((std.math.isNan(lhs_sv) and lhs_o.is_nan()) == false)
                        {
                            try std.testing.expectEqual(
                                lhs_sv,
                                lhs_o.as(Ordinate.BaseType)
                            );
                        }

                        if ((std.math.isNan(rhs_sv) and rhs_o.is_nan()) == false)
                        {
                            try std.testing.expectEqual(
                                rhs_sv,
                                rhs_o.as(Ordinate.BaseType)
                            );
                        }

                        try expectOrdinateEqual(
                            expected,
                            measured
                        );
                    }
                }
            }
        }
    }
}

// unary macros
inline fn _is_inf(
    thing: anytype,
) bool
{
    return switch (@typeInfo(@TypeOf(thing))) {
        .float => std.math.isInf(thing),
        else => false,
   };
}

inline fn _is_nan(
    thing: anytype,
) bool
{
    return switch (@typeInfo(@TypeOf(thing))) {
        .float => std.math.isNan(thing),
        else => false,
   };
}

pub inline fn abs(
    lhs: anytype,
) @TypeOf(lhs)
{
    return switch (@typeInfo(@TypeOf(lhs))) {
        .@"struct" => lhs.abs(),
        else => @abs(lhs),
    };
}

// binary macros
pub inline fn min(
    lhs: anytype,
    rhs: @TypeOf(lhs),
) @TypeOf(lhs)
{
    return switch (@typeInfo(@TypeOf(lhs))) {
        .@"struct" => lhs.min(rhs),
        else => std.math.min(lhs, rhs),
    };
}

pub inline fn max(
    lhs: anytype,
    rhs: @TypeOf(lhs),
) @TypeOf(lhs)
{
    return switch (@typeInfo(@TypeOf(lhs))) {
        .@"struct" => lhs.max(rhs),
        else => std.math.max(lhs, rhs),
    };
}

pub inline fn eql(
    lhs: anytype,
    rhs: @TypeOf(lhs),
) bool
{
    return switch (@typeInfo(@TypeOf(lhs))) {
        .@"struct" => lhs.eql(rhs),
        else => lhs == rhs,
    };
}

pub inline fn eql_approx(
    lhs: anytype,
    rhs: @TypeOf(lhs),
) bool
{
    return switch (@typeInfo(@TypeOf(lhs))) {
        .@"struct" => lhs.eql_approx(rhs),
        else => std.math.approxEqAbs(@TypeOf(lhs), lhs, rhs, util.EPSILON_F),
    };
}

pub inline fn lt(
    lhs: anytype,
    rhs: @TypeOf(lhs),
) bool
{
    return switch (@typeInfo(@TypeOf(lhs))) {
        .@"struct" => lhs.lt(rhs),
        else => lhs < rhs,
    };
}

pub inline fn lteq(
    lhs: anytype,
    rhs: @TypeOf(lhs),
) bool
{
    return switch (@typeInfo(@TypeOf(lhs))) {
        .@"struct" => lhs.lteq(rhs),
        else => lhs <= rhs,
    };
}

pub inline fn gt(
    lhs: anytype,
    rhs: @TypeOf(lhs),
) bool
{
    return switch (@typeInfo(@TypeOf(lhs))) {
        .@"struct" => lhs.gt(rhs),
        else => lhs > rhs,
    };
}

pub inline fn gteq(
    lhs: anytype,
    rhs: @TypeOf(lhs),
) bool
{
    return switch (@typeInfo(@TypeOf(lhs))) {
        .@"struct" => lhs.gteq(rhs),
        else => lhs >= rhs,
    };
}

test "Base Ordinate: Binary Function Tests"
{
    const TestCase = struct {
        lhs: Ordinate.BaseType,
        rhs: Ordinate.BaseType,
    };
    const tests = &[_]TestCase{
        .{ .lhs =  1, .rhs =  1 },
        .{ .lhs = -1, .rhs =  1 },
        .{ .lhs =  1, .rhs = -1 },
        .{ .lhs = -1, .rhs = -1 },
        .{ .lhs = -1.2, .rhs = -1001.45 },
        .{ .lhs =  0, .rhs =  5.345 },
    };

    inline for (&.{ "min", "max", "eql", "lt", "lteq", "gt", "gteq", "eql_approx" })
        |op|
    {
        for (tests)
            |t|
        {
            const lhs = Ordinate.init(t.lhs);
            const rhs = Ordinate.init(t.rhs);

            const expected_raw = (
                @field(basic_math, op)(t.lhs, t.rhs) 
            );

            const measured = @field(@This(), op)(lhs, rhs);

            const is_ord = @TypeOf(measured) == Ordinate;

            const expected = if (is_ord) Ordinate.init(
                expected_raw
            ) else expected_raw;

            if (is_ord) {
                errdefer std.debug.print(
                    "Error with test: " ++ @typeName(Ordinate) ++ "." ++ op ++ 
                    ": iteration: {any}\nexpected: {d}\nmeasured: {s}\n",
                    .{ t, expected, measured },
                );
            } else {
                errdefer std.debug.print(
                    "Error with test: " ++ @typeName(Ordinate) ++ "." ++ op ++ 
                    ": iteration: {any}\nexpected: {any}\nmeasured: {any}\n",
                    .{ t, expected, measured },
                );
            }

            if (is_ord) {
                try expectOrdinateEqual(expected, measured);
            }
            else {
                try std.testing.expectEqual(expected, measured);
            }
        }
    }
}

test "Base Ordinate: as"
{
    const tests = &[_]Ordinate.BaseType{
        1.0, -1.0, 3.45, -3.45, 1.0/3.0,
    };

    inline for (&.{ f32, f64, i32, u32, i64, })
        |target_type|
    {
        for (tests)
            |t|
        {
            const ord = Ordinate.init(t);

            if (t < 0 and target_type == u32) {
                continue;
            }

            errdefer std.log.err(
                "Error with type: " ++ @typeName(target_type) 
                ++ " t: {d} ord: {s} ({d})",
                .{ t, ord, ord.as(target_type) },
            );

            try switch (@typeInfo(target_type)) {
                .float, .comptime_float => std.testing.expectApproxEqAbs(
                    @as(target_type, @floatCast(t)),
                    ord.as(target_type),
                    util.EPSILON_F,
                ),
                .int, .comptime_int => std.testing.expectEqual(
                    @as(target_type, @intFromFloat(t)),
                    ord.as(target_type),
                ),
                else => return error.BARF,
            };
        }
    }
}

// sort
pub const sort = struct {
    pub fn asc(
        comptime T: type
    ) fn (void, T, T) bool 
    {
        return struct {
            pub fn inner(
                _: void,
                a: T,
                b: T,
            ) bool 
            {
                return switch (@typeInfo(T)) {
                    .@"struct" => a.lt(b),
                    else => a < b,
                };
            }
        }.inner;
    }
};

test "Ordinate: as float roundtrip test"
{
    const values = [_]Ordinate.BaseType {
        0,
        -0.0,
        1,
        -1,
        std.math.inf(Ordinate.BaseType),
        -std.math.inf(Ordinate.BaseType),
        std.math.nan(Ordinate.BaseType),
    };

    for (values)
        |v|
    {
        const ord = Ordinate.init(v);

        errdefer std.debug.print(
            "error with test: \n{d}: {s} sign: {d} {d} signbit: {any} {any}\n",
            .{
                v, ord,
                std.math.sign(v), std.math.sign(ord.as(Ordinate.BaseType)),
                std.math.signbit(v), std.math.signbit(ord.as(Ordinate.BaseType)),
            }
        );

        if (std.math.isNan(v)) {
            try std.testing.expect(ord.is_nan());
        } else {
            try std.testing.expectEqual(
                std.math.sign(v),
                std.math.sign(ord.as(Ordinate.BaseType)),
            );

            try std.testing.expectEqual(
                std.math.signbit(v),
                std.math.signbit(ord.as(Ordinate.BaseType)),
            );

            try std.testing.expectEqual(
                v,
                ord.as(Ordinate.BaseType)
            );
        }
    }
}

test "Base Ordinate: sort"
{
    const allocator = std.testing.allocator;

    const known = [_]Ordinate{
        Ordinate.init(-1.01),
        Ordinate.init(-1),
        Ordinate.init(0),
        Ordinate.init(1),
        Ordinate.init(1.001),
        Ordinate.init(100),
    };

    var test_arr = (
        std.ArrayList(Ordinate).init(allocator)
    );

    try test_arr.appendSlice(&known);
    defer test_arr.deinit();

    var engine = std.Random.DefaultPrng.init(0x42);
    const rnd =  engine.random();

    std.Random.shuffle(rnd, Ordinate, test_arr.items);

    std.mem.sort(
        Ordinate, 
        test_arr.items,
        {},
        sort.asc(Ordinate),
    );

    try std.testing.expectEqualSlices(
        Ordinate,
        &known,
        test_arr.items,
    );
}

test "ordinate / eval test"
{
    const o3 = Ordinate.init(3);
    const o4 = Ordinate.init(4);

    try std.testing.expectEqual(
        Ordinate.init(15),
        comath_wrapper.eval(
            "(o3 * o4) + o4 - o3 + (o3 / o3) + 1",
            .{ .o3 = o3, .o4 = o4 },
        )
    );
}

