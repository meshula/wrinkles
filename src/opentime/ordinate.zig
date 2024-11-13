//! Ordinate type and support math for opentime

const std = @import("std");

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

/// Phase based ordinate
pub const PhaseOrdinate = struct {
    sign: u1,
    // @TODO: can support ~4hrs at 192khz, if more space is needed, use 63 bits
    count: u31,
    phase: f32,

    /// implies a rate of 1
    pub fn init(
        val: f32,
    ) PhaseOrdinate
    {
        const abs_val = @abs(val);
        return .{
            .sign = @intFromBool(val < 0),
            .count = @intFromFloat(abs_val),
            .phase = @abs(abs_val) - @trunc(abs_val),
        };
    }

    /// implies a rate of "1".  Any
    pub fn to_continuous(
        self: @This(),
    ) struct {
        value: f32,
        err: f32,
    }
    {
        var val:f32 = @as(f32, @floatFromInt(self.count)) + self.phase;

        if (self.sign == 1) {
            val *= -1;
        }

        const pord = PhaseOrdinate.init(val);

        const err_pord = self.sub(pord);

        const err_pord_f:f32 = (
            @as(f32, @floatFromInt(err_pord.count)) + err_pord.phase
        );

        return .{
            .value = val,
            .err = err_pord_f,
        };
    }

    // add
    

    // sub
    // multiply
    // divide
    // neg
    // lt
    // gt
    // eq

        pub inline fn negate(
            self: @This(),
        ) @This() 
        {
            return .{ 
                .sign = 1 - self.sign,
                .count = self.count,
                .phase = self.phase,
            };
        }

        pub inline fn add(
            self: @This(),
            rhs: anytype,
        ) @This() 
        {
            return switch(@typeInfo(@TypeOf(rhs))) {
                .Struct => switch(@TypeOf(rhs)) {
                    PhaseOrdinate => result: {
                        var po_result = self;
                        po_result.count = po_result.count + rhs.count;
                        po_result.phase += rhs.phase;
                        while (po_result.phase > 0) 
                        {
                            po_result.phase -= 1.0;
                            po_result.count += 1;
                        }
                        while (po_result.phase < 0) {
                            po_result.phase += 1;
                            po_result.count -= 1;
                        }
                        break:result po_result;
                    },
                    else => @compileError(
                        "PhaseOrdinate only supports math with integers,"
                        ++ " floating point numbers, and other PhaseOrdinates."
                    ),
                },
                .Float => self.add(PhaseOrdinate.init(rhs)),
                .Int => |int_type| switch (int_type.signedness) {
                    .unsigned => self.add(
                        .{
                            // 0 = positive
                            .sign = 0,
                            .count = rhs,
                            .phase = 0,
                        }
                    ),
                    .signed => self.add(
                        .{
                            .sign = @intFromBool(rhs < 0),
                            .count = @intCast(rhs),
                            .phase = 0,
                        },
                    ),
                },
                else => @compileError(
                    "PhaseOrdinate only supports math with integers,"
                    ++ " floating point numbers, and other PhaseOrdinates."
                ),
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
                    else => @compileError(
                        "PhaseOrdinate only supports math with integers,"
                        ++ " floating point numbers, and other PhaseOrdinates."
                    ),
                },
                .Float => self.add(PhaseOrdinate.init(-1 * rhs)),
                .Int => |int_type| switch (int_type.signedness) {
                    .unsigned => self.add(
                        .{
                            // 0 = positive
                            .sign = 1,
                            .count = rhs,
                            .phase = 0,
                        }
                    ),
                    .signed => self.add(
                        .{
                            .sign = ! @intFromBool(rhs < 0),
                            .count = @intCast(rhs),
                            .phase = 0,
                        },
                    ),
                },
                else => @compileError(
                    "PhaseOrdinate only supports math with integers,"
                    ++ " floating point numbers, and other PhaseOrdinates."
                ),
            };
        }

        pub inline fn mul(
            self: @This(),
            rhs: anytype,
        ) @This() 
        {
            return switch(@typeInfo(@TypeOf(rhs))) {
                .Struct => switch(@TypeOf(rhs)) {
                    PhaseOrdinate => result: {
                        var po_result = self;

                        po_result.sign *= rhs.sign;
                        po_result.count = po_result.count * rhs.count;
                        po_result.phase *= rhs.phase;

                        while (po_result.phase > 1) 
                        {
                            po_result.phase -= 1.0;
                            po_result.count += 1;
                        }

                        break :result po_result;
                    },
                    else => @compileError(
                        "PhaseOrdinate only supports math with integers,"
                        ++ " floating point numbers, and other PhaseOrdinates."
                    ),
                },
                .Float => self.mul(PhaseOrdinate.init(rhs)),
                .Int => .{
                    .sign = self.sign * rhs.sign,
                    .count = self.count * rhs.count,
                    .phase = 0,
                },
                else => @compileError(
                    "PhaseOrdinate only supports math with integers,"
                    ++ " floating point numbers, and other PhaseOrdinates."
                ),
            };
        }

        //
        // pub inline fn mul(
        //     self: @This(),
        //     rhs: anytype
        // ) @This() 
        // {
        //     return switch(@typeInfo(@TypeOf(rhs))) {
        //         .Struct => .{ 
        //             .r = self.r * rhs.r,
        //             .i = self.r * rhs.i + self.i*rhs.r,
        //         },
        //         else => .{
        //             .r = self.r * rhs,
        //             .i = self.i * rhs,
        //         },
        //     };
        // }
        //
        // pub inline fn lt(
        //     self: @This(),
        //     rhs: @This()
        // ) @This() 
        // {
        //     return self.r < rhs.r;
        // }
        //
        // pub inline fn gt(
        //     self: @This(),
        //     rhs: @This()
        // ) @This() 
        // {
        //     return self.r > rhs.r;
        // }
        //
        // pub inline fn div(
        //     self: @This(),
        //     rhs: anytype
        // ) @This() 
        // {
        //     return switch(@typeInfo(@TypeOf(rhs))) {
        //         .Struct => .{
        //             .r = self.r / rhs.r,
        //             .i = (rhs.r * self.i - self.r * rhs.i) / (rhs.r * rhs.r),
        //         },
        //         else => .{
        //             .r = self.r / rhs,
        //             .i = (self.i) / (rhs),
        //         },
        //     };
        // }

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
            "PhaseOrd{{ {s}{d}.{d} }}",
            .{ if (self.sign == 0) "+" else "-", self.count, self.phase }
        );
        // switch (self) {
        //     .SuccessOrdinate => |ord| try writer.print(
        //         "ProjResult{{ .ordinate = {d} }}",
        //         .{ ord },
        //     ),
        //     .SuccessInterval => |inf| try writer.print(
        //         "ProjResult{{ .interval = {s} }}",
        //         .{ inf },
        //     ),
        //     .OutOfBounds => try writer.print(
        //         "ProjResult{{ .OutOfBounds }}",
        //         .{},
        //     ),
        // }
    }
};

test "PhaseOrdinate: negate"
{
    const po = PhaseOrdinate.init(1);

    try std.testing.expectEqual(
        -1.0,
        po.negate().to_continuous().value,
    );

    try std.testing.expectEqual(
        1,
        po.negate().negate().to_continuous().value,
    );
}

test "PhaseOrdinate: add"
{
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
        const po_should_be_pt1 = (
            PhaseOrdinate.init(0.3).add(
                PhaseOrdinate.init(-0.3)
            )
        );

        try std.testing.expectEqual(
            0.0,
            po_should_be_pt1.to_continuous().value,
        );
    }
}

test "PhaseOrdinate: sub"
{
    {
        const po_five = PhaseOrdinate.init(5);
        const po_should_be_ten = po_five.sub(po_five);

        try std.testing.expectEqual(
            0,
            po_should_be_ten.to_continuous().value,
        );
    }

    {
        const po_1pt5 = PhaseOrdinate.init(1.5);
        const po_should_be_one = po_1pt5.sub(
            PhaseOrdinate.init(0.5)
        );

        try std.testing.expectEqual(
            1,
            po_should_be_one.to_continuous().value,
        );
    }
}

test "PhaseOrdinate mul"
{
    {
        const po_five = PhaseOrdinate.init(5);
        const po_should_be_25 = po_five.mul(po_five);

        try std.testing.expectEqual(
            25,
            po_should_be_25.to_continuous().value,
        );
    }

    {
        const po_1pt5 = PhaseOrdinate.init(1.5);
        const po_should_be_225 = po_1pt5.add(po_1pt5);

        try std.testing.expectEqual(
            2.25,
            po_should_be_225.to_continuous().value,
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
