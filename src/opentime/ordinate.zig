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

// @TODO: can support ~4hrs at 192khz, if more space is needed, use 64 bits
const count_t = i32;
pub const phase_t = f32;
/// the math type for the Ordinate.  Will cast to this for division/pow/etc.
const div_t = f64;

/// PhaseOrdinate - An Ordinate that maintains precision over the number line.
///
/// This pairs an integer count with a floating point decimal component, the
/// phase. The phase is always [0, 1) and also encodes special float values NaN,
/// +Inf, -Inf and -0.  This acts like a float but has the same precision over
/// the entire range supported by the integer component.
pub const PhaseOrdinate = struct {
    count: count_t,
    phase: phase_t,

    pub const BaseType = phase_t;
    pub const OrdinateType = @This();

    pub const ZERO = OrdinateType.init(0.0);
    pub const ONE = OrdinateType.init(1.0);
    pub const EPSILON = OrdinateType.init(util.EPSILON_F);
    pub const NAN = OrdinateType {
        .count = 0,
        .phase = std.math.nan(phase_t) 
    };
    pub const INF = OrdinateType {
        .count = 0,
        .phase = std.math.inf(phase_t) 
    };
    pub const INF_NEG = OrdinateType {
        .count = -1,
        .phase = -std.math.inf(phase_t) 
    };

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
                else => type_error(val),
            },
            .Float => (
                if (std.math.isInf(val) and val > 0) OrdinateType.INF else 
                    if (std.math.isInf(val) and val < 0) OrdinateType.INF_NEG else 
                        if (std.math.isNan(val)) OrdinateType.NAN else 
                            OrdinateType.init_float(val)
            ),
            .ComptimeFloat => OrdinateType.init_float(val),
            .ComptimeInt, .Int => PhaseOrdinate{
                    .count = @intCast(val),
                    .phase = @floatCast(0),
                },
            else => type_error(val),
        };
    }

    pub inline fn init_float(
        val: anytype,
    ) PhaseOrdinate
    {
        const ti = @typeInfo(@TypeOf(val));
        comptime {
            switch (ti) {
                .ComptimeFloat, .Float, => {},
                else => type_error(val),
            }
        }

        // There are some subtle differences between -0.0 and 0.0 that aren't
        // captured by std.math.sign -- which always returns 0 for both -0.0
        // and 0.0.  For example, -1.0 / -0.0 -> +inf while -1.0 / 0.0 -> =inf.
        //
        // using signbit is an attempt to preserve the signbit from the
        // incoming floating point number into the floating point phase
        // component.  The hope is that this preserves the math behavior of the 
        // PhaseOrdinate with regards to special floating point numbers like
        // inf and nan.
        const signbit = switch (ti) {
            .ComptimeFloat => val < 0,
            .Float => std.math.signbit(val),
            // already handled by previous comptime block
            else => {},
        };
        
        const sign : BaseType = if (signbit) -1 else 1;

        return (
            PhaseOrdinate { 
                .count = @intFromFloat(val),
                .phase = @floatCast(
                    sign * (@abs(val) - @trunc(@abs(val)))
                ),
            }
        ).normalized();
    }

    inline fn special_float(
        self:@This(),
    ) ?OrdinateType
    {
        if (std.math.isInf(self.phase)) {
            if (self.count < 0) {
                return OrdinateType.INF_NEG;
            } else {
                return OrdinateType.INF;
            }
        } else if (std.math.isNan(self.phase)) {
            return OrdinateType.NAN;
        }

        return null;
    }

    pub inline fn as(
        self: @This(),
        comptime T: type,
    ) T
    {
        return switch (@typeInfo(T)) {
            .Float => (
                if (self.count != 0) (
                    @as(T, @floatFromInt(self.count)) 
                    + @as(T, @floatCast(self.phase))
                ) else @as(T, @floatCast(self.phase))
            ),
            // @TODO: this probably also needs either an error or special
            //        handling for the special number types of INF/NaN
            .Int => @intCast(
                if (self.count >= 0) self.count 
                else if (self.phase > 0) 1 + self.count 
                else self.count
            ),
            else => @compileError(
                "PhaseOrdinate can be retrieved as a float or int type,"
                ++ " not: " ++ @typeName(T)
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
            "PhaseOrd{{ {d} + {d} }}",
            .{ self.count, self.phase }
        );
    }
 
    /// implies a rate of "1".  returns the float as 
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

    // unary operators
    pub inline fn normalized(
        self: @This(),
    ) @This()
    {
        if (self.is_inf()) {
            if (self.count < 0) {
                return OrdinateType.INF_NEG;
            }
            else {
                return OrdinateType.INF;
            }
        }
        if (self.is_nan()) {
            return OrdinateType.NAN;
        }

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

    pub inline fn sqrt(
        self: @This(),
    ) OrdinateType
    {
        return OrdinateType.init(std.math.sqrt(self.as(div_t)));
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
    pub inline fn neg(
        self: @This(),
    ) @This() 
    {
        if (self.is_inf()) {
            if (std.math.signbit(self.phase)) {
                return OrdinateType.INF;
            }
            return OrdinateType.INF_NEG;
        }
        if (self.is_nan()) {
            return OrdinateType.NAN;
        }

        return if (self.phase > 0) .{ 
            .count = -1 - self.count,
            .phase = 1 - self.phase,
        }
        else .{
            .count = - self.count,
            .phase = if (self.count > 0) -0.0 else 0,
        };
    }

    pub inline fn abs(
        self: @This(),
    ) OrdinateType
    {
        return (
            if ((self.phase > 0 and self.count < 0) or self.phase < 0)
                self.neg() 
            else .{
                .count = @intCast(@abs(self.count)),
                .phase = @abs(self.phase),
            }
        );
    }

    /// utility function for handling unknown types
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

    // binary operators

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
                else => type_error(rhs),
            },
            .ComptimeFloat => self.add(PhaseOrdinate.init(rhs)),
            .Float => (
                if (std.math.isInf(rhs)) OrdinateType.INF else
                    if (std.math.isNan(rhs)) OrdinateType.NAN else
                        self.add(PhaseOrdinate.init(rhs))
            ),
            .ComptimeInt, .Int => PhaseOrdinate{
                .count = self.count + rhs,
                .phase = self.phase,
            },
            else => type_error(rhs),
        };
    }

     pub inline fn sub(
         self: @This(),
         rhs: anytype,
     ) @This() 
     {
         return switch(@typeInfo(@TypeOf(rhs))) {
             .Struct => (
                 switch(@TypeOf(rhs)) {
                     PhaseOrdinate => self.add(rhs.neg()),
                     else => type_error(rhs),
                 }
             ),
             .ComptimeFloat, .Float => (
                 self.add(PhaseOrdinate.init(-rhs))
             ),
             .ComptimeInt, .Int => (
                 self.add(
                     PhaseOrdinate{
                         .count = -rhs,
                         .phase = 0,
                     }
                 )
             ),
             else => type_error(rhs),
         };
     }

    //
    pub fn mul(
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
                else => type_error(rhs),
            },
            .ComptimeFloat, .Float => self.mul(PhaseOrdinate.init(rhs)),
            .ComptimeInt, .Int => .{
                .count = self.count * rhs,
                .phase = self.phase,
            },
            else => type_error(rhs),
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
                else => type_error(rhs),
            },
            .ComptimeFloat, .Float =>  (
                PhaseOrdinate.init(self.as(div_t) / @as(div_t, @floatCast(rhs)))
            ),
            .ComptimeInt, .Int => (
                PhaseOrdinate.init(self.as(div_t) / @as(div_t, @floatFromInt(rhs)))
            ),
            else => type_error(rhs),
        };
    }

    pub inline fn pow(
        self: @This(),
        exp: div_t,
    ) OrdinateType
    {
        return OrdinateType.init(
            std.math.pow(div_t, self.as(div_t), exp)
        );
    }

    // unary tests
    pub inline fn is_inf(
        self: @This(),
    ) bool
    {
        return std.math.isInf(self.phase);
    }

    pub inline fn is_finite(
        self: @This(),
    ) bool
    {
        return std.math.isFinite(self.phase);
    }

    pub inline fn is_nan(
        self: @This(),
    ) bool
    {
        return std.math.isNan(self.phase);
    }

    // binary tests

    pub fn lt(
        self: @This(),
        rhs: anytype,
    ) bool
    {
        return switch (@TypeOf(rhs)) {
            OrdinateType => (
                self.count < rhs.count
                or (self.count == rhs.count and self.phase < rhs.phase)
            ),
            else => switch (@typeInfo(@TypeOf(rhs))) {
                // @TODO: is it better to do this comparison in float?  Or 
                //        making both phase ordinates?
                .Float, .ComptimeFloat, .Int, .ComptimeInt => (
                    self.lt(OrdinateType.init(rhs))
                ),
                else => type_error(rhs),
            },
        };
    }

    pub fn lteq(
        self: @This(),
        rhs: anytype,
    ) bool
    {
        return switch (@TypeOf(rhs)) {
            OrdinateType => (
                self.count < rhs.count
                or (self.count == rhs.count and self.phase <= rhs.phase)
            ),
            else => switch (@typeInfo(@TypeOf(rhs))) {
                // @TODO: is it better to do this comparison in float?  Or 
                //        making both phase ordinates?
                .Float, .ComptimeFloat, .Int, .ComptimeInt => (
                    self.lteq(OrdinateType.init(rhs))
                ),
                else => type_error(rhs),
            },
        };
    }

    pub fn gt(
        self: @This(),
        rhs: anytype,
    ) bool
    {
        return switch (@TypeOf(rhs)) {
            OrdinateType => (
                self.count > rhs.count
                or (self.count == rhs.count and self.phase > rhs.phase)
            ),
            else => switch (@typeInfo(@TypeOf(rhs))) {
                // @TODO: is it better to do this comparison in float?  Or 
                //        making both phase ordinates?
                .Float, .ComptimeFloat, .Int, .ComptimeInt => (
                    self.gt(OrdinateType.init(rhs))
                ),
                else => type_error(rhs),
            },
        };
    }

    pub fn gteq(
        self: @This(),
        rhs: anytype,
    ) bool
    {
        return switch (@TypeOf(rhs)) {
            OrdinateType => (
                self.count > rhs.count
                or (self.count == rhs.count and self.phase >= rhs.phase)
            ),
            else => switch (@typeInfo(@TypeOf(rhs))) {
                // @TODO: is it better to do this comparison in float?  Or 
                //        making both phase ordinates?
                .Float, .ComptimeFloat, .Int, .ComptimeInt => (
                    self.gteq(OrdinateType.init(rhs))
                ),
                else => type_error(rhs),
            },
        };
    }

    pub fn eql(
        self: @This(),
        rhs: anytype,
    ) bool
    {
        return switch (@TypeOf(rhs)) {
            OrdinateType => (
                self.count == rhs.count
                and self.phase == rhs.phase
            ),
            else => switch (@typeInfo(@TypeOf(rhs))) {
                // @TODO: is it better to do this comparison in float?  Or 
                //        making both phase ordinates?
                .Float, .ComptimeFloat, .Int, .ComptimeInt => (
                    self.eql(OrdinateType.init(rhs))
                ),
                else => type_error(rhs),
            },
        };
    }

    pub fn eql_approx(
        self: @This(),
        rhs: anytype,
    ) bool
    {
        return switch (@TypeOf(rhs)) {
            OrdinateType => std.math.approxEqAbs(
                BaseType,
                self.phase,
                rhs.phase,
                util.EPSILON_F
            ),
            else => switch (@typeInfo(@TypeOf(rhs))) {
                // @TODO: is it better to do this comparison in float?  Or 
                //        making both phase ordinates?
                .Float, .ComptimeFloat, .Int, .ComptimeInt => self.eql_approx(
                    OrdinateType.init(rhs)
                ),
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
            OrdinateType => if (self.lt(rhs)) return self else rhs,
            else => switch (@typeInfo(@TypeOf(rhs))) {
                .Float, .ComptimeFloat, .Int, .ComptimeInt => 
                    if (self.lt(rhs)) return self else rhs,
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
            OrdinateType => if (self.gt(rhs)) return self else rhs,
            else => switch (@typeInfo(@TypeOf(rhs))) {
                .Float, .ComptimeFloat, .Int, .ComptimeInt => 
                    if (self.gt(rhs)) return self else rhs,
                else => type_error(rhs),
            },
        };
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

test "PhaseOrdinate: neg"
{
    const ord_neg = PhaseOrdinate.init(1).neg();

    try std.testing.expectEqual( -1, ord_neg.count);
    try std.testing.expectEqual( -1, ord_neg.to_continuous().value);

    const ord_neg_neg = ord_neg.neg();

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
        pub const INF : OrdinateType = OrdinateType.init(std.math.inf(t));
        pub const INF_NEG : OrdinateType = OrdinateType.init(-std.math.inf(t));
        pub const NAN : OrdinateType = OrdinateType.init(std.math.nan(t));
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
                    .Float, .ComptimeFloat, .Int, .ComptimeInt => (
                        self.v < rhs.v + EPSILON.v and self.v > rhs.v - EPSILON.v
                    ),
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
// pub const Ordinate = OrdinateOf(f64);
pub const Ordinate = PhaseOrdinate;

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
            .ComptimeInt, .Int, .ComptimeFloat, .Float => (
                Ordinate.init(expected_in)
            ),
            else => @compileError(
                "Error: can only compare an Ordinate to a float, int, or "
                ++ "other Ordinate.  Got a: " ++ @typeName(@TypeOf(expected_in))
            ),
        },
    };

    const measured = (
        measured_in catch |err| return err
    );

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
            .Int, .ComptimeInt => try std.testing.expectEqual(
                @field(expected, f.name),
                @field(measured, f.name),
            ),
            .Float, .ComptimeFloat => try std.testing.expectApproxEqAbs(
                @field(expected, f.name),
                @field(measured, f.name),
                util.EPSILON_F,
            ),
            inline else => @compileError(
                "Do not know how to handle fields of type: " ++ f.type
            ),
        }
    }
}

const basic_math = struct {
    // unary
    pub fn neg(in: anytype) @TypeOf(in) { return 0-in; }
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
        .{ .in =  -0.0 },
        .{ .in =  std.math.inf(f32) },
        .{ .in =  -std.math.inf(f32) },
        .{ .in =  std.math.nan(f32) },
    };

    inline for (&.{ "neg", "sqrt", "abs", })
        |op|
    {
        for (tests)
            |t|
        {
            // std.debug.print("{s}: {d}\n", .{ op, t.in });
            //
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

            try std.testing.expectEqual(
                std.math.signbit(expected.phase),
                std.math.signbit(measured.phase),
            );

            try expectOrdinateEqual(expected, measured);
        }
    }
}

test "Base Ordinate: Binary Operator Tests"
{
    const values = [_]f32{
        0,
        1,
        1.2,
        5.345,
        3.14159,
        1001.45,
        std.math.inf(f32),
        std.math.nan(f32),
    };

    const signs = [_]f32{ -1, 1 };

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
                    inline for (&.{ "add", "sub", "mul", "div", })
                        |op|
                    {
                        const lhs_sv = s_lhs * lhs_v;
                        const rhs_sv = s_rhs * rhs_v;

                        const lhs_o = Ordinate.init(lhs_sv);
                        const rhs_o = Ordinate.init(rhs_sv);

                        const expected = Ordinate.init(
                           @field(basic_math, op)(
                               lhs_sv,
                               rhs_sv
                            ) 
                        );

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
                                lhs_o.as(f32)
                            );
                        }

                        if ((std.math.isNan(rhs_sv) and rhs_o.is_nan()) == false)
                        {
                            try std.testing.expectEqual(
                                rhs_sv,
                                rhs_o.as(f32)
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
        .Float => std.math.isInf(thing),
        else => false,
   };
}

inline fn _is_nan(
    thing: anytype,
) bool
{
    return switch (@typeInfo(@TypeOf(thing))) {
        .Float => std.math.isNan(thing),
        else => false,
   };
}

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
        .@"-" = &.{"sub", "negate", "neg"},
        .@"*" = "mul",
        .@"/" = "div",
    },
);
pub inline fn eval(
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

            errdefer std.log.err(
                "Error with type: " ++ @typeName(target_type) 
                ++ " t: {d} ord: {s} ({d})",
                .{ t, ord, ord.as(target_type) },
            );

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

test "PhaseOrdinate: as float roundtrip test"
{
    const values = [_]Ordinate.BaseType {
        0,
        -0.0,
        1,
        -1,
        std.math.inf(f32),
        -std.math.inf(f32),
        std.math.nan(f32),
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

