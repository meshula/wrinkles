//! Ordinate type and support math for opentime

const std = @import("std");

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
const phase_t = f32;
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
                PhaseOrdinate { 
                    .count = @intFromFloat(val),
                    .phase = @floatCast(std.math.sign(val) * (@abs(val) - @trunc(@abs(val)))),
                }
            ).normalized(),
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

                    break :ret PhaseOrdinate.init(
                        self_count_f * rhs_count_f
                        + self_count_f * rhs.phase
                        + rhs_count_f * self.phase
                        + self.phase * rhs.phase
                    );
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
            util.EPSILON_ORD,
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
             util.EPSILON_ORD,
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
            util.EPSILON_ORD
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
            " \nError with test: {s}\nexpr: {s}\nresult: {d} {s}\n",
            .{ t.name, t.expr, t.result_c, t.result_o },
        );

        try std.testing.expectApproxEqAbs(
            t.expr.to_continuous().value,
            t.result_c,
            util.EPSILON_ORD,
        );

        try std.testing.expectEqual(
            t.expr.count,
            t.result_o.count,
        );

        try std.testing.expectApproxEqAbs(
            t.expr.phase,
            t.result_o.phase,
            util.EPSILON_ORD,
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
            util.EPSILON_ORD,
        );

        try std.testing.expectEqual(
            t.expr.count,
            t.result_o.count,
        );

        try std.testing.expectApproxEqAbs(
            t.expr.phase,
            t.result_o.phase,
            util.EPSILON_ORD,
        );
    }
}

// @TODO: helpful
// const PHASE_ORD_ZERO = ...
// const PHASE_ORD_ONE = ...

pub fn OrdinateOf(
    comptime t: type
) type
{
    return t;
}

/// ordinate type
pub const Ordinate = OrdinateOf(f32);
