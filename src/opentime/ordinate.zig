//! Ordinate type and support math for opentime

const std = @import("std");
const comath = @import("comath");

const util = @import("util.zig");

// 1 make sure we need this
//      because sampling rates, especially for audio, are high (ie 192khz),
//      even with reasonably long timelines can get into the error zone for
//      typical floating point numbers.
//
//      Additionally, the presence of hard-integer samples, with a continuous
//      transformation in the middle, means we want as much accuracy as
//      possible when determining indices.
//
// 2 how does the math behave?

// @TODO: remove the pub from the struct and force construction through
//        functions
// @TODO: model the fractional component as a fractional component instead of
//        f32
//        ^ integer math
//
// pub const Fractional = struct { 
//     v: u32,
// };

const count_t = i32;
pub const phase_t = f32;
const div_t = f64;

fn typeError(
    thing: anytype,
) PhaseOrdinate 
{
    @compileError(
        "PhaseOrdinate only supports math with integers,"
        ++ " floating point numbers, and other PhaseOrdinates."
        ++ " Not: " ++ @typeName(@TypeOf(thing))
    );
}

/// Phase based ordinate
pub const PhaseOrdinate = struct {
    // @TODO: can support ~4hrs at 192khz, if more space is needed, use 64 bits
    count: count_t,
    phase: phase_t,

    /// implies a rate of 1
    pub fn init(
        val: anytype,
    ) PhaseOrdinate
    {
        return switch(@typeInfo(@TypeOf(val))) {
            .Struct => switch(@TypeOf(val)) {
                PhaseOrdinate => result: {
                    const out = PhaseOrdinate{
                        .count = val.count,
                        .phase = val.phase,
                    };

                    break :result out.normalized();
                },
                else => typeError(val),
            },
            .ComptimeFloat, .Float => (
                // if (std.math.isFinite(val)) (
                    PhaseOrdinate { 
                        .count = @intFromFloat(val),
                        .phase = @floatCast(
                            std.math.sign(val) 
                            * (@abs(val) - @trunc(@abs(val)))
                        ),
                    }
                ).normalized()
                ,
                // else PhaseOrdinate { 
                //     .count = @intFromFloat(std.math.sign(val)),
                //     .phase = @floatCast(val),
                // }
            // ),
            .ComptimeInt, .Int => PhaseOrdinate{
                    .count = val,
                    .phase = 0,
                },
            else => typeError(val),
        };
    }

    pub inline fn normalized(
        self: @This(),
    ) @This()
    {
        // if (std.math.isInf(self.phase)) {
        //     return PhaseOrdinate {
        //         .count = @intFromFloat(std.math.sign(self.phase)),
        //         .phase = self.phase,
        //     };
        // }
        //
        var out = self;
        while (out.phase > 0) {
            out.phase -= 1.0;
            out.count += 1;
        }
        while (out.phase < 0) {
            out.phase += 1.0;
            out.count -= 1;
        }
        return out;
    }

    /// implies a rate of "1".  Any
    pub fn to_continuous(
        self: @This(),
    ) struct {
        value: phase_t,
        err: phase_t,
    }
    {
        const v = self.as(phase_t);

        const pord = PhaseOrdinate.init(v);

        const err_pord = self.sub(pord);

        const err_pord_f = err_pord.as(phase_t);

        return .{
            .value = v,
            .err = err_pord_f,
        };
    }


    // phase is a float in the range [0, 1.0)
    // subtracting phase has the same effect of negating the phase and adding it.
    // So, a phase of -0.25 is equivalent to a phase of 0.75. But when we get a 
    // PhaseOrdinate with a negative phase, we want to normalize it to a positive
    // phase and decrement the count. This is done in the normalize function.
    // as an example given
    // PhaseOrdinate p0 = {false, 0, -0.25};
    // if we draw it on a numberline it looks like this:
    // -1.25 -1.0 -0.75 -0.5 -0.25 0.0 0.25 0.5 0.75 1.0 1.25
    //  |----|----|----|----|----|----|----|----|----|----|----| p0 ------------------^
    // Normalizing to a positive phase should point to the same place on the numberline
    // which would be a negative -1 count, and a positive 0.75 phase.
    // If we draw a number line with the normalized phase it would look like this:
    // -1.0 +0.25, -1.0 +0.5, -1 +0.75, 0.0 +0.0, 0 +0.25, 0 +0.5, 0 +0.75, 1 +0.0, 1 +0.25, 1 +0.5, 1 +0.75
    pub inline fn negate(
        self: @This(),
    ) @This() 
    {
        if (self.phase > 0) {
            return .{ 
                .count = -1 - self.count,
                .phase = 1 - self.phase,
            };
        }
        else {
            return .{
                .count = - self.count,
                .phase = 0,
            };
        }
    }

    pub inline fn add(
        self: @This(),
        rhs: anytype,
    ) @This() 
    {
        return switch(@typeInfo(@TypeOf(rhs))) {
            .Struct => switch(@TypeOf(rhs)) {
                PhaseOrdinate => (
                    PhaseOrdinate{
                        .count = self.count + rhs.count,
                        .phase = self.phase + rhs.phase,
                    }
                ).normalized(),
                else => typeError(rhs),
            },
            .ComptimeFloat, .Float => self.add(PhaseOrdinate.init(rhs)),
            .ComptimeInt, .Int => self.add(
                PhaseOrdinate{
                    .count = rhs,
                    .phase = 0,
                }
            ),
            else => typeError(rhs),
        };
    }

     pub inline fn sub(
         self: @This(),
         rhs: anytype,
     ) @This() 
     {
         return switch(@typeInfo(@TypeOf(rhs))) {
             .Struct => switch(@TypeOf(rhs)) {
                 PhaseOrdinate => self.add(rhs.negate()),
                 else => typeError(rhs),
             },
             .ComptimeFloat, .Float => self.add(PhaseOrdinate.init(-rhs)),
             .ComptimeInt, .Int => self.add(
                 PhaseOrdinate{
                     .count = -rhs,
                     .phase = 0,
                 }
             ),
             else => typeError(rhs),
         };
     }

     inline fn as(
         self: @This(),
         comptime T: type,
     ) T
     {
         return switch (@typeInfo(T)) {
            .Float => (
                @as(T, @floatFromInt(self.count)) 
                + @as(T, @floatCast(self.phase))
            ),
            .Int => @intCast(self.count),
            else => @compileError(
                "PhaseOrdinate can be retrieved as a float or int type,"
                ++ " not: " ++ @typeName(T)
            ),
         };
     }

    //
    pub inline fn mul(
        self: @This(),
        rhs: anytype,
    ) @This() 
    {
        return switch(@typeInfo(@TypeOf(rhs))) {
            .Struct => switch(@TypeOf(rhs)) {
                PhaseOrdinate => ret: {
                    const self_count_f : phase_t = @floatFromInt(self.count);
                    const rhs_count_f : phase_t = @floatFromInt(rhs.count);
                    // middle terms
                    const middle = (
                        self_count_f * rhs.phase + rhs_count_f * self.phase
                    );

                    break :ret (
                       PhaseOrdinate{
                           .count = (self.count * rhs.count),
                           .phase = (middle + self.phase*rhs.phase),
                       }
                   ).normalized();
                },
                else => typeError(rhs),
            },
            .ComptimeFloat, .Float => self.mul(PhaseOrdinate.init(rhs)),
            .ComptimeInt, .Int => .{
                .count = self.count * rhs,
                .phase = self.phase,
            },
            else => typeError(rhs),
        };
    }

    pub inline fn div(
        self: @This(),
        rhs: anytype,
    ) @This() 
    {
        return switch(@typeInfo(@TypeOf(rhs))) {
            .Struct => switch(@TypeOf(rhs)) {
                PhaseOrdinate => (
                    PhaseOrdinate.init(self.as(div_t) / rhs.as(div_t))
                ),
                else => typeError(rhs),
            },
            .ComptimeFloat, .Float => (
                PhaseOrdinate.init(self.as(div_t) / @as(div_t, @floatCast(rhs)))
            ),
            .ComptimeInt, .Int => (
                PhaseOrdinate.init(self.as(div_t) / @as(div_t, @floatFromInt(rhs)))
            ),
            else => typeError(rhs),
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
            "PhaseOrd{{ {d} + {d} }}",
            .{ self.count, self.phase }
        );
    }

    pub fn is_inf(
        self: @This(),
    ) bool
    {
        return std.math.isInf(self.phase);
    }

    pub fn is_finite(
        self: @This(),
    ) bool
    {
        return std.math.is_finite(self.phase);
    }
};

test "PhaseOrdinate: init and normalized"
{
    const TestCase = struct {
        in: phase_t,
        result_o: PhaseOrdinate,
    };
    const tests = &[_]TestCase{
        .{
            .in = 1.25,
            .result_o = .{ .count = 1, .phase = 0.25 },
        },
        .{
            .in = -1.25,
            .result_o = .{ .count = -2, .phase = 0.75 },
        },
        .{
            .in = -0.05,
            .result_o = .{ .count = -1, .phase = 0.95 },
        },
    };
    for (tests)
        |t|
    {
        errdefer std.debug.print(
           "PhaseOrdinate.init({d})\nresult_o: {s}\n",
            .{ t.in, t.result_o },
        );

        const v = PhaseOrdinate.init(t.in);

        try std.testing.expectEqual(
            t.result_o.count,
            v.count,
        );
        try std.testing.expectEqual(
            t.result_o.phase,
            v.phase,
        );
    }
}

test "PhaseOrdinate: to_continuous"
{
    try std.testing.expectEqual(
        0.3,
        PhaseOrdinate.init(0.3).to_continuous().value,
    );

    try std.testing.expectEqual(
        -0.3,
        PhaseOrdinate.init(-0.3).to_continuous().value,
    );
}

test "PhaseOrdinate: negate"
{
    const ord_neg = PhaseOrdinate.init(1).negate();

    try std.testing.expectEqual( -1, ord_neg.count);
    try std.testing.expectEqual( -1, ord_neg.to_continuous().value);

    const ord_neg_neg = ord_neg.negate();

    try std.testing.expectEqual( 1, ord_neg_neg.count);
}

test "PhaseOrdinate: add (PhaseOrdinate)"
{
    {
        const v = PhaseOrdinate.init(0.2).add(
            PhaseOrdinate.init(0.05)
        );

        try std.testing.expectEqual(
            0,
            v.count,
        );

        try std.testing.expectEqual(
            0.25,
            v.phase,
        );
    }

    {
        const v = PhaseOrdinate.init(0.2).add(
            PhaseOrdinate.init(-0.05)
        );

        try std.testing.expectEqual(
            0,
            v.count,
        );

        try std.testing.expectApproxEqAbs(
            0.15,
            v.phase,
            util.EPSILON_F,
        );
    }

    {
        const po_five = PhaseOrdinate.init(5);
        const po_should_be_ten = po_five.add(po_five);

        try std.testing.expectEqual(
            10,
            po_should_be_ten.to_continuous().value,
        );
    }

     {
         const po_1pt5 = PhaseOrdinate.init(1.5);
         const po_should_be_three = po_1pt5.add(po_1pt5);

         try std.testing.expectEqual(
             3,
             po_should_be_three.to_continuous().value,
         );
     }

     {
         const po_should_be_pt6 = (
             PhaseOrdinate.init(0.3).add(
                 PhaseOrdinate.init(0.2)
             ).add(PhaseOrdinate.init(0.1))
         );

         try std.testing.expectEqual(
             0.6,
             po_should_be_pt6.to_continuous().value,
         );
     }

     {
         try std.testing.expectApproxEqAbs(
             0.1,
             PhaseOrdinate.init(0.3).add(
                 PhaseOrdinate.init(-0.2)
             ).to_continuous().value,
             util.EPSILON_F,
         );
     }
}

test "PhaseOrdinate: add (int/float)"
{
    var ord = PhaseOrdinate.init(1.0);

    {
        const r = ord.add(@as(i16, 1));

        try std.testing.expectEqual(2, r.count);
        try std.testing.expectEqual(0, r.phase);
    }

    {
        const r = ord.add(@as(f32, 0.25));

        try std.testing.expectEqual(1, r.count);
        try std.testing.expectEqual(0.25, r.phase);
    }

    {
        const r = ord.add(@as(i16, -1));

        try std.testing.expectEqual(0, r.count);
        try std.testing.expectEqual(0, r.phase);
    }

    {
        const r = ord.add(@as(f32, -0.25));

        try std.testing.expectEqual(0, r.count);
        try std.testing.expectEqual(0.75, r.phase);
    }
}

test "PhaseOrdinate: sub"
{
    {
        const ord = (
            PhaseOrdinate.init(5).sub(PhaseOrdinate.init(3))
        );

        try std.testing.expectEqual(2, ord.count,);
        try std.testing.expectEqual(0, ord.phase,);
    }

    {
        const ord = (
            PhaseOrdinate.init(5.3).sub(PhaseOrdinate.init(1.3))
        );

        try std.testing.expectEqual(4, ord.count,);
        try std.testing.expectApproxEqAbs(
            0,
            ord.phase,
            util.EPSILON_F
        );
    }

    {
        const ord = (
            PhaseOrdinate.init(0.3).sub(PhaseOrdinate.init(0.6))
        );

        try std.testing.expectEqual(-1, ord.count,);
        try std.testing.expectEqual(0.7, ord.phase,);
    }
}

test "PhaseOrdinate: sub (int/float)"
{
     var ord = PhaseOrdinate.init(1.0);

    {
        const r = ord.sub(@as(i16, 1));

        try std.testing.expectEqual(0, r.count);
        try std.testing.expectEqual(0, r.phase);
    }

    {
        const r = ord.sub(@as(f32, 0.25));

        try std.testing.expectEqual(0, r.count);
        try std.testing.expectEqual(0.75, r.phase);
    }

    {
        const r = ord.sub(@as(i16, -1));

        try std.testing.expectEqual(2, r.count);
        try std.testing.expectEqual(0, r.phase);
    }

    {
        const r = ord.sub(@as(f32, -0.25));

        try std.testing.expectEqual(1, r.count);
        try std.testing.expectEqual(0.25, r.phase);
    }
   
}

test "PhaseOrdinate mul"
{
    const TestCase = struct {
        name: []const u8,
        expr: PhaseOrdinate,
        result_c: phase_t,
        result_o: PhaseOrdinate,
    };
    const tests = &[_]TestCase{
        .{
            .name = "5*5 (f)",
            .expr = PhaseOrdinate.init(5).mul(5.0),
            .result_c = 25,
            .result_o = .{ .count = 25, .phase = 0 },
        },
        .{
            .name = "5*5 (int)",
            .expr = PhaseOrdinate.init(5).mul(5),
            .result_c = 25,
            .result_o = .{ .count = 25, .phase = 0 },
        },
        .{
            .name = "5*5 (PhaseOrdinate)",
            .expr = PhaseOrdinate.init(5).mul(PhaseOrdinate.init(5)),
            .result_c = 25,
            .result_o = .{ .count = 25, .phase = 0 },
        },
        .{
            .name = "-5*-5 (PhaseOrdinate)",
            .expr = PhaseOrdinate.init(-5).mul(PhaseOrdinate.init(-5)),
            .result_c = 25,
            .result_o = .{ .count = 25, .phase = 0 },
        },
        .{
            .name = "-5*5 (PhaseOrdinate)",
            .expr = PhaseOrdinate.init(-5).mul(PhaseOrdinate.init(5)),
            .result_c = -25,
            .result_o = .{ .count = -25, .phase = 0 },
        },
        .{
            .name = ".5 * .5 (f)",
            .expr = PhaseOrdinate.init(0.5).mul(0.5),
            .result_c = 0.25,
            .result_o = .{ .count = 0, .phase = 0.25 },
        },
        .{
            .name = ".5 * .5 (PhaseOrdinate)",
            .expr = PhaseOrdinate.init(0.5).mul(PhaseOrdinate.init(0.5)),
            .result_c = 0.25,
            .result_o = .{ .count = 0, .phase = 0.25 },
        },
        .{
            .name = "-0.5 * .5 (PhaseOrdinate)",
            .expr = PhaseOrdinate.init(-0.5).mul(PhaseOrdinate.init(0.5)),
            .result_c = -0.25,
            .result_o = .{ .count = -1, .phase = 0.75 },
        },
        .{
            .name = "1.5 * 1.5 (f)",
            .expr = PhaseOrdinate.init(1.5).mul(1.5),
            .result_c = 2.25,
            .result_o = .{ .count = 2, .phase = 0.25 },
        },
        .{
            .name = "1.5 * 1.5 (PhaseOrdinate)",
            .expr = PhaseOrdinate.init(1.5).mul(PhaseOrdinate.init(1.5)),
            .result_c = 2.25,
            .result_o = .{ .count = 2, .phase = 0.25 },
        },
    };
    for (tests)
        |t|
    {
        errdefer std.debug.print(
            " \nError with test: {s}\nexpr: {s}\nexpected result: {d} {s}\n",
            .{ t.name, t.expr, t.result_c, t.result_o },
        );

        try std.testing.expectApproxEqAbs(
            t.result_c,
            t.expr.to_continuous().value,
            util.EPSILON_F,
        );

        try std.testing.expectEqual(
            t.result_o.count,
            t.expr.count,
        );

        try std.testing.expectApproxEqAbs(
            t.result_o.phase,
            t.expr.phase,
            util.EPSILON_F,
        );
    }
}

test "PhaseOrdinate div"
{
    const TestCase = struct {
        name: []const u8,
        expr: PhaseOrdinate,
        result_c: phase_t,
        result_o: PhaseOrdinate,
    };
    const tests = &[_]TestCase{
        .{
            .name = "5/5 (f)",
            .expr = PhaseOrdinate.init(5).div(5.0),
            .result_c = 1,
            .result_o = .{ .count = 1, .phase = 0 },
        },
        .{
            .name = "5/5 (int)",
            .expr = PhaseOrdinate.init(5).div(5),
            .result_c = 1,
            .result_o = .{ .count = 1, .phase = 0 },
        },
        .{
            .name = "5/5 (PhaseOrdinate)",
            .expr = PhaseOrdinate.init(5).div(PhaseOrdinate.init(5)),
            .result_c = 1,
            .result_o = .{ .count = 1, .phase = 0 },
        },
        .{
            .name = "-5/-5 (PhaseOrdinate)",
            .expr = PhaseOrdinate.init(-5).div(PhaseOrdinate.init(-5)),
            .result_c = 1,
            .result_o = .{ .count = 1, .phase = 0 },
        },
        .{
            .name = "-5/5 (PhaseOrdinate)",
            .expr = PhaseOrdinate.init(-5).div(PhaseOrdinate.init(5)),
            .result_c = -1,
            .result_o = .{ .count = -1, .phase = 0 },
        },
        .{
            .name = ".5 / 2 (f)",
            .expr = PhaseOrdinate.init(0.5).div(2.0),
            .result_c = 0.25,
            .result_o = .{ .count = 0, .phase = 0.25 },
        },
        .{
            .name = ".5 / 2 (PhaseOrdinate)",
            .expr = PhaseOrdinate.init(0.5).div(PhaseOrdinate.init(2)),
            .result_c = 0.25,
            .result_o = .{ .count = 0, .phase = 0.25 },
        },
        .{
            .name = "-0.5 / 2 (PhaseOrdinate)",
            .expr = PhaseOrdinate.init(-0.5).div(PhaseOrdinate.init(2)),
            .result_c = -0.25,
            .result_o = .{ .count = -1, .phase = 0.75 },
        },
        .{
            .name = "1.32/1.2 (f)",
            .expr = PhaseOrdinate.init(1.32).div(1.2),
            .result_c = 1.1,
            .result_o = .{ .count = 1, .phase = 0.1 },
        },
        .{
            .name = "1.32/1.2 (PhaseOrdinate)",
            .expr = PhaseOrdinate.init(1.32).div(PhaseOrdinate.init(1.2)),
            .result_c = 1.1,
            .result_o = .{ .count = 1, .phase = 0.1 },
        },
        .{
            .name = "-1.32/1.2 (PhaseOrdinate)",
            .expr = PhaseOrdinate.init(-1.32).div(PhaseOrdinate.init(1.2)),
            .result_c = -1.1,
            .result_o = .{ .count = -2, .phase = 0.9 },
        },
    };
    for (tests)
        |t|
    {
        errdefer std.debug.print(
            " \nError with test: {s}\nexpr: {s}\nresult: {d} {s}\n",
            .{ t.name, t.expr, t.result_c, t.result_o },
        );

        try std.testing.expectApproxEqAbs(
            t.expr.to_continuous().value,
            t.result_c,
            util.EPSILON_F,
        );

        try std.testing.expectEqual(
            t.expr.count,
            t.result_o.count,
        );

        try std.testing.expectApproxEqAbs(
            t.expr.phase,
            t.result_o.phase,
            util.EPSILON_F,
        );
    }
}

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
        pub const INF : OrdinateType = OrdinateType.init(std.math.inf(f32));
        pub const INF_NEG : OrdinateType = OrdinateType.init(-std.math.inf(f32));
        pub const NAN : OrdinateType = OrdinateType.init(std.math.nan(f32));
        pub const EPSILON = OrdinateType.init(util.EPSILON_F);

        pub inline fn init(
            value: anytype,
        ) OrdinateType
        {
            return switch (@typeInfo(@TypeOf(value))) {
                .Float, .ComptimeFloat => .{ .v = value },
                .Int, .ComptimeInt => .{ .v = @floatFromInt(value) },
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

         pub inline fn as(
             self: @This(),
             comptime T: type,
         ) T
         {
             return switch (@typeInfo(T)) {
                .Float => (
                    @floatCast(self.v) 
                ),
                .Int => @intFromFloat(self.v),
                else => @compileError(
                    "Ordinate can be retrieved as a float or int type,"
                    ++ " not: " ++ @typeName(T)
                ),
             };
         }

        // unary operators
        pub inline fn neg(
            self: @This(),
        ) OrdinateType
        {
            return .{
                .v = - self.v,
            };
        }

        pub inline fn sqrt(
            self: @This(),
        ) OrdinateType
        {
            return .{
                .v = std.math.sqrt(self.v),
            };
        }

        pub inline fn abs(
            self: @This(),
        ) OrdinateType
        {
            return .{
                .v = @abs(self.v),
            };
        }

        // binary operators
        pub inline fn add(
            self: @This(),
            rhs: anytype,
        ) OrdinateType
        {
            return switch (@TypeOf(rhs)) {
                OrdinateType => .{ .v = self.v + rhs.v },
                else => switch (@typeInfo(@TypeOf(rhs))) {
                    .Float, .ComptimeFloat, .Int, .ComptimeInt => .{ 
                        .v = self.v + rhs 
                    },
                    else => type_error(rhs),
                },
            };
        }

        pub inline fn sub(
            self: @This(),
            rhs: anytype,
        ) OrdinateType
        {
            return switch (@TypeOf(rhs)) {
                OrdinateType => .{ .v = self.v - rhs.v },
                else => switch (@typeInfo(@TypeOf(rhs))) {
                    .Float, .ComptimeFloat, .Int, .ComptimeInt => .{ 
                        .v = self.v - rhs 
                    },
                    else => type_error(rhs),
                },
            };
        }

        pub inline fn mul(
            self: @This(),
            rhs: anytype,
        ) OrdinateType
        {
            return switch (@TypeOf(rhs)) {
                OrdinateType => .{ .v = self.v * rhs.v },
                else => switch (@typeInfo(@TypeOf(rhs))) {
                    .Float, .ComptimeFloat, .Int, .ComptimeInt => .{ 
                        .v = self.v * rhs,
                    },
                    else => type_error(rhs),
                },
            };
        }

        pub inline fn pow(
            self: @This(),
            exp: BaseType,
        ) OrdinateType
        {
            return .{ .v = std.math.pow(BaseType, self.v, exp) };
        }

        pub inline fn div(
            self: @This(),
            rhs: anytype,
        ) OrdinateType
        {
            return switch (@TypeOf(rhs)) {
                OrdinateType => .{ .v = self.v / rhs.v },
                else => switch (@typeInfo(@TypeOf(rhs))) {
                    .Float, .ComptimeFloat, .Int, .ComptimeInt => .{ 
                        .v = self.v / rhs 
                    },
                    else => type_error(rhs),
                },
            };
        }

        // binary macros
        pub inline fn min(
            self: @This(),
            rhs: anytype,
        ) OrdinateType
        {
            return switch (@TypeOf(rhs)) {
                OrdinateType => .{ .v = @min(self.v,rhs.v) },
                else => switch (@typeInfo(@TypeOf(rhs))) {
                    .Float, .ComptimeFloat, .Int, .ComptimeInt => .{ 
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
                    .Float, .ComptimeFloat, .Int, .ComptimeInt => .{ 
                        .v = @max(self.v,rhs)
                    },
                    else => type_error(rhs),
                },
            };
        }

        // binary tests
        pub inline fn eql(
            self: @This(),
            rhs: anytype,
        ) bool
        {
            return switch (@TypeOf(rhs)) {
                OrdinateType => self.v == rhs.v,
                else => switch (@typeInfo(@TypeOf(rhs))) {
                    .Float, .ComptimeFloat, .Int, .ComptimeInt => self.v == rhs,
                    else => type_error(rhs),
                },
            };
        }

        pub inline fn lt(
            self: @This(),
            rhs: anytype,
        ) bool
        {
            return switch (@TypeOf(rhs)) {
                OrdinateType => self.v < rhs.v,
                else => switch (@typeInfo(@TypeOf(rhs))) {
                    .Float, .ComptimeFloat, .Int, .ComptimeInt => self.v < rhs,
                    else => type_error(rhs),
                },
            };
        }

        pub inline fn lteq(
            self: @This(),
            rhs: anytype,
        ) bool
        {
            return switch (@TypeOf(rhs)) {
                OrdinateType => self.v <= rhs.v,
                else => switch (@typeInfo(@TypeOf(rhs))) {
                    .Float, .ComptimeFloat, .Int, .ComptimeInt => self.v <= rhs,
                    else => type_error(rhs),
                },
            };
        }

        pub inline fn gt(
            self: @This(),
            rhs: anytype,
        ) bool
        {
            return switch (@TypeOf(rhs)) {
                OrdinateType => self.v > rhs.v,
                else => switch (@typeInfo(@TypeOf(rhs))) {
                    .Float, .ComptimeFloat, .Int, .ComptimeInt => self.v > rhs,
                    else => type_error(rhs),
                },
            };
        }

        pub inline fn gteq(
            self: @This(),
            rhs: anytype,
        ) bool
        {
            return switch (@TypeOf(rhs)) {
                OrdinateType => self.v >= rhs.v,
                else => switch (@typeInfo(@TypeOf(rhs))) {
                    .Float, .ComptimeFloat, .Int, .ComptimeInt => self.v >= rhs,
                    else => type_error(rhs),
                },
            };
        }

        pub inline fn is_inf(
            self: @This(),
        ) bool
        {
            return std.math.isInf(self.v);
        }

        pub inline fn is_finite(
            self: @This(),
        ) bool
        {
            return std.math.isFinite(self.v);
        }
    };
}

/// ordinate type
pub const Ordinate = OrdinateOf(f32);
// pub const Ordinate = OrdinateOf(f64);
// pub const Ordinate = OrdinateOf(PhaseOrdinate);

/// compare two ordinates.  Create an ordinate from expected if it is not
/// already one.
pub fn expectOrdinateEqual(
    expected_in: anytype,
    measured: anyerror!Ordinate,
) !void
{

    const expected = switch(@TypeOf(expected_in)) {
        Ordinate => expected_in,
        else => switch(@typeInfo(@TypeOf(expected_in))) {
            .ComptimeInt, .Int, .ComptimeFloat, .Float => (
                Ordinate.init(expected_in)
            ),
            else => @compileError(
                "Error: can only compare an Ordinate to a float, int, or "
                ++ "other Ordinate.  Got a: " ++ @typeName(@TypeOf(expected_in))
            ),
        },
    };

    try std.testing.expectApproxEqAbs(
        expected.v,
        (measured catch |err| return err).v, 
        util.EPSILON_F,
    );
}

const basic_math = struct {
    // unary
    pub fn neg(in: anytype) @TypeOf(in) { return - in; }
    pub fn sqrt(in: anytype) @TypeOf(in) { return std.math.sqrt(in); }
    pub fn abs(in: anytype) @TypeOf(in) { return @abs(in); }

    // binary
    pub fn add(lhs: anytype, rhs: anytype) @TypeOf(lhs) { return lhs + rhs; }
    pub fn sub(lhs: anytype, rhs: anytype) @TypeOf(lhs) { return lhs - rhs; }
    pub fn mul(lhs: anytype, rhs: anytype) @TypeOf(lhs) { return lhs * rhs; }
    pub fn div(lhs: anytype, rhs: anytype) @TypeOf(lhs) { return lhs / rhs; }

    // binary macros
    pub fn min(lhs: anytype, rhs: anytype) @TypeOf(lhs) { return @min(lhs, rhs); }
    pub fn max(lhs: anytype, rhs: anytype) @TypeOf(lhs) { return @max(lhs, rhs); }

    // binary tests
    pub fn eql(lhs: anytype, rhs: anytype) bool { return lhs == rhs; }
    pub fn gt(lhs: anytype, rhs: anytype) bool { return lhs > rhs; }
    pub fn gteq(lhs: anytype, rhs: anytype) bool { return lhs >= rhs; }
    pub fn lt(lhs: anytype, rhs: anytype) bool { return lhs < rhs; }
    pub fn lteq(lhs: anytype, rhs: anytype) bool { return lhs <= rhs; }
};

test "Base Ordinate: Unary Operator Tests"
{
    const TestCase = struct {
        in: f32,
    };
    const tests = &[_]TestCase{
        .{ .in =  1 },
        .{ .in =  -1 },
        .{ .in = 25 },
        .{ .in = 64.34 },
        .{ .in =  5.345 },
        .{ .in =  -5.345 },
        .{ .in =  0 },
    };

    // @TODO: sqrt(negative => nan)

    inline for (&.{ "neg", "sqrt", "abs", })
        |op|
    {
        for (tests)
            |t|
        {
            if (t.in < 0 and std.mem.eql(u8, "sqrt", op)) {
                continue;
            }

            const in = Ordinate.init(t.in);

            const expected = Ordinate.init(
                (@field(basic_math, op)(t.in))
            );

            const measured = @field(Ordinate, op)(in);

            errdefer std.debug.print(
                "Error with test: " ++ @typeName(Ordinate) ++ "." ++ op ++ 
                ": iteration: {any}\nexpected: {d}\nmeasured: {s}\n",
                .{ t, expected, measured },
            );

            try expectOrdinateEqual(expected, measured);
        }
    }
}

test "Base Ordinate: Binary Operator Tests"
{
    const TestCase = struct {
        lhs: f32,
        rhs: f32,
    };
    const tests = &[_]TestCase{
        .{ .lhs =  1, .rhs =  1 },
        .{ .lhs = -1, .rhs =  1 },
        .{ .lhs =  1, .rhs = -1 },
        .{ .lhs = -1, .rhs = -1 },
        .{ .lhs = -1.2, .rhs = -1001.45 },
        .{ .lhs =  0, .rhs =  5.345 },
    };

    inline for (&.{ "add", "sub", "mul", "div", })
        |op|
    {
        for (tests)
            |t|
        {
            const lhs = Ordinate.init(t.lhs);
            const rhs = Ordinate.init(t.rhs);

            const expected = Ordinate.init(
                (@field(basic_math, op)(t.lhs, t.rhs))
            );

            const measured = @field(Ordinate, op)(lhs, rhs);

            errdefer std.debug.print(
                "Error with test: " ++ @typeName(Ordinate) ++ "." ++ op ++ 
                ": iteration: {any}\nexpected: {d}\nmeasured: {s}\n",
                .{ t, expected, measured },
            );

            try expectOrdinateEqual(expected, measured);
        }
    }
}

// unary macros
pub inline fn abs(
    lhs: anytype,
) @TypeOf(lhs)
{
    return switch (@typeInfo(@TypeOf(lhs))) {
        .Struct => lhs.abs(),
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
        .Struct => lhs.min(rhs),
        else => std.math.min(lhs, rhs),
    };
}

pub inline fn max(
    lhs: anytype,
    rhs: @TypeOf(lhs),
) @TypeOf(lhs)
{
    return switch (@typeInfo(@TypeOf(lhs))) {
        .Struct => lhs.max(rhs),
        else => std.math.max(lhs, rhs),
    };
}

pub inline fn eql(
    lhs: anytype,
    rhs: @TypeOf(lhs),
) bool
{
    return switch (@typeInfo(@TypeOf(lhs))) {
        .Struct => lhs.eql(rhs),
        else => lhs == rhs,
    };
}

pub inline fn lt(
    lhs: anytype,
    rhs: @TypeOf(lhs),
) bool
{
    return switch (@typeInfo(@TypeOf(lhs))) {
        .Struct => lhs.lt(rhs),
        else => lhs < rhs,
    };
}

pub inline fn lteq(
    lhs: anytype,
    rhs: @TypeOf(lhs),
) bool
{
    return switch (@typeInfo(@TypeOf(lhs))) {
        .Struct => lhs.lteq(rhs),
        else => lhs <= rhs,
    };
}

pub inline fn gt(
    lhs: anytype,
    rhs: @TypeOf(lhs),
) bool
{
    return switch (@typeInfo(@TypeOf(lhs))) {
        .Struct => lhs.gt(rhs),
        else => lhs > rhs,
    };
}

pub inline fn gteq(
    lhs: anytype,
    rhs: @TypeOf(lhs),
) bool
{
    return switch (@typeInfo(@TypeOf(lhs))) {
        .Struct => lhs.gteq(rhs),
        else => lhs >= rhs,
    };
}

test "Base Ordinate: Binary Function Tests"
{
    const TestCase = struct {
        lhs: f32,
        rhs: f32,
    };
    const tests = &[_]TestCase{
        .{ .lhs =  1, .rhs =  1 },
        .{ .lhs = -1, .rhs =  1 },
        .{ .lhs =  1, .rhs = -1 },
        .{ .lhs = -1, .rhs = -1 },
        .{ .lhs = -1.2, .rhs = -1001.45 },
        .{ .lhs =  0, .rhs =  5.345 },
    };

    inline for (&.{ "min", "max", "eql", "lt", "lteq", "gt", "gteq", })
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

pub const CTX = comath.ctx.fnMethod(
    comath.ctx.simple({}),
    .{
        .@"+" = "add",
        .@"-" = &.{"sub", "neg", "negate"},
        .@"*" = "mul",
        .@"/" = "div",
    },
);
pub fn eval(
    comptime expr: []const u8, 
    inputs: anytype,
) comath.Eval(expr, @TypeOf(CTX), @TypeOf(inputs))
{
    return comath.eval(expr, CTX, inputs) catch @compileError(
        "couldn't comath: " ++ expr ++ "."
    );
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

            try switch (@typeInfo(target_type)) {
                .Float, .ComptimeFloat => std.testing.expectApproxEqAbs(
                    @as(target_type, @floatCast(t)),
                    ord.as(target_type),
                    util.EPSILON_F,
                ),
                .Int, .ComptimeInt => std.testing.expectEqual(
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
    pub fn asc(comptime T: type) fn (void, T, T) bool {
        return struct {
            pub fn inner(_: void, a: T, b: T) bool {
                return switch (@typeInfo(T)) {
                    .Struct => a.lt(b),
                    else => a < b,
                };
            }
        }.inner;
    }
};

test "Base Ordinate: sort"
{
    const allocator = std.testing.allocator;

    const known = [_]Ordinate{
        .{ .v = -1.01 },
        .{ .v = -1 },
        .{ .v = 0 },
        .{ .v = 1 },
        .{ .v = 1.001 },
        .{ .v = 100 },
    };

    var test_arr = std.ArrayList(Ordinate).init(allocator);
    try test_arr.appendSlice(&known);
    defer test_arr.deinit();

    var engine = std.rand.DefaultPrng.init(0x42);
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

