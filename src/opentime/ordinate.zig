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

/// Phase based ordinate
pub const PhaseOrdinate = struct {
    // @TODO: can support ~4hrs at 192khz, if more space is needed, use 63 bits
    //        (+ signed bit)
    count: i32,
    phase: f32,

    /// implies a rate of 1
    pub fn init(
        val: f32,
    ) PhaseOrdinate
    {
        var result = PhaseOrdinate { 
            .count = @intFromFloat(val),
            .phase = std.math.sign(val) * (@abs(val) - @trunc(@abs(val))),
        };

        return result.normalized();
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

     //
     // /// implies a rate of "1".  Any
     // pub fn to_continuous(
     //     self: @This(),
     // ) struct {
     //     value: f32,
     //     err: f32,
     // }
     // {
     //     const v = (
     //         @as(@TypeOf(self.phase), @floatFromInt(self.count)) 
     //         + self.phase
     //     );
     //
     //     const pord = PhaseOrdinate.init(v);
     //
     //     const err_pord = self.sub(pord);
     //
     //     const err_pord_f = (
     //         @as(@TypeOf(self.phase), @floatFromInt(err_pord.count)) + err_pord.phase
     //     );
     //
     //     return .{
     //         .value = v,
     //         .err = err_pord_f,
     //     };
     // }

    //
    // // add
    //
    //
    // // sub
    // // multiply
    // // divide
    // // neg
    // // lt
    // // gt
    // // eq
    //

    pub inline fn negate(
        self: @This(),
    ) @This() 
    {
        return .{ 
            .count = -1 * self.count,
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
                    const out = PhaseOrdinate{
                        .count = self.count + rhs.count,
                        .phase = self.phase + rhs.phase,
                    };

                    break :result out.normalized();
                },
                else => @compileError(
                    "PhaseOrdinate only supports math with integers,"
                    ++ " floating point numbers, and other PhaseOrdinates."
                ),
            },
            .Float => self.add(PhaseOrdinate.init(rhs)),
            .Int => self.add(
                PhaseOrdinate{
                    .count = rhs,
                    .phase = 0,
                }
            ),
            else => @compileError(
                "PhaseOrdinate only supports math with integers,"
                ++ " floating point numbers, and other PhaseOrdinates."
            ),
        };
    }
    //
    //     pub inline fn sub(
    //         self: @This(),
    //         rhs: anytype,
    //     ) @This() 
    //     {
    //         return switch(@typeInfo(@TypeOf(rhs))) {
    //             .Struct => switch(@TypeOf(rhs)) {
    //                 PhaseOrdinate => self.add(rhs.negate()),
    //                 else => @compileError(
    //                     "PhaseOrdinate only supports math with integers,"
    //                     ++ " floating point numbers, and other PhaseOrdinates."
    //                 ),
    //             },
    //             .Float => self.add(PhaseOrdinate.init(-1 * rhs)),
    //             .Int => |int_type| switch (int_type.signedness) {
    //                 .unsigned => self.add(
    //                     .{
    //                         // 0 = positive
    //                         .sign = 1,
    //                         .count = rhs,
    //                         .phase = 0,
    //                     }
    //                 ),
    //                 .signed => self.add(
    //                     .{
    //                         .sign = ! @intFromBool(rhs < 0),
    //                         .count = @intCast(rhs),
    //                         .phase = 0,
    //                     },
    //                 ),
    //             },
    //             else => @compileError(
    //                 "PhaseOrdinate only supports math with integers,"
    //                 ++ " floating point numbers, and other PhaseOrdinates."
    //             ),
    //         };
    //     }
    //
    //     pub inline fn mul(
    //         self: @This(),
    //         rhs: anytype,
    //     ) @This() 
    //     {
    //         return switch(@typeInfo(@TypeOf(rhs))) {
    //             .Struct => switch(@TypeOf(rhs)) {
    //                 PhaseOrdinate => result: {
    //                     var po_result = self;
    //
    //                     po_result.sign *= rhs.sign;
    //                     po_result.count = po_result.count * rhs.count;
    //                     po_result.phase *= rhs.phase;
    //
    //                     while (po_result.phase > 1) 
    //                     {
    //                         po_result.phase -= 1.0;
    //                         po_result.count += 1;
    //                     }
    //
    //                     break :result po_result;
    //                 },
    //                 else => @compileError(
    //                     "PhaseOrdinate only supports math with integers,"
    //                     ++ " floating point numbers, and other PhaseOrdinates."
    //                 ),
    //             },
    //             .Float => self.mul(PhaseOrdinate.init(rhs)),
    //             .Int => .{
    //                 .sign = self.sign * rhs.sign,
    //                 .count = self.count * rhs.count,
    //                 .phase = 0,
    //             },
    //             else => @compileError(
    //                 "PhaseOrdinate only supports math with integers,"
    //                 ++ " floating point numbers, and other PhaseOrdinates."
    //             ),
    //         };
    //     }
    //
    //     //
    //     // pub inline fn mul(
    //     //     self: @This(),
    //     //     rhs: anytype
    //     // ) @This() 
    //     // {
    //     //     return switch(@typeInfo(@TypeOf(rhs))) {
    //     //         .Struct => .{ 
    //     //             .r = self.r * rhs.r,
    //     //             .i = self.r * rhs.i + self.i*rhs.r,
    //     //         },
    //     //         else => .{
    //     //             .r = self.r * rhs,
    //     //             .i = self.i * rhs,
    //     //         },
    //     //     };
    //     // }
    //     //
    //     // pub inline fn lt(
    //     //     self: @This(),
    //     //     rhs: @This()
    //     // ) @This() 
    //     // {
    //     //     return self.r < rhs.r;
    //     // }
    //     //
    //     // pub inline fn gt(
    //     //     self: @This(),
    //     //     rhs: @This()
    //     // ) @This() 
    //     // {
    //     //     return self.r > rhs.r;
    //     // }
    //     //
    //     // pub inline fn div(
    //     //     self: @This(),
    //     //     rhs: anytype
    //     // ) @This() 
    //     // {
    //     //     return switch(@typeInfo(@TypeOf(rhs))) {
    //     //         .Struct => .{
    //     //             .r = self.r / rhs.r,
    //     //             .i = (rhs.r * self.i - self.r * rhs.i) / (rhs.r * rhs.r),
    //     //         },
    //     //         else => .{
    //     //             .r = self.r / rhs,
    //     //             .i = (self.i) / (rhs),
    //     //         },
    //     //     };
    //     // }
    //
    // pub fn format(
    //     self: @This(),
    //     // fmt
    //     comptime _: []const u8,
    //     // options
    //     _: std.fmt.FormatOptions,
    //     writer: anytype,
    // ) !void 
    // {
    //     try writer.print(
    //         "PhaseOrd{{ {s}{d}.{d} }}",
    //         .{ if (self.sign == 0) "+" else "-", self.count, self.phase }
    //     );
    //     // switch (self) {
    //     //     .SuccessOrdinate => |ord| try writer.print(
    //     //         "ProjResult{{ .ordinate = {d} }}",
    //     //         .{ ord },
    //     //     ),
    //     //     .SuccessInterval => |inf| try writer.print(
    //     //         "ProjResult{{ .interval = {s} }}",
    //     //         .{ inf },
    //     //     ),
    //     //     .OutOfBounds => try writer.print(
    //     //         "ProjResult{{ .OutOfBounds }}",
    //     //         .{},
    //     //     ),
    //     // }
    // }
};

test "PhaseOrdinate: init and normalized"
{
    {
        const t = PhaseOrdinate.init(1.25);

        try std.testing.expectEqual(
            1,
            t.count,
        );

        try std.testing.expectEqual(
            0.25,
            t.phase,
        );
    }

    {
        const t = PhaseOrdinate.init(-1.25);

        try std.testing.expectEqual(
            -2,
            t.count,
        );

        try std.testing.expectEqual(
            0.75,
            t.phase,
        );
    }

    {
        const t = (
            PhaseOrdinate{
                .count = 0,
                .phase = -1.25,
            }
        ).normalized();

        try std.testing.expectEqual(
            -2,
            t.count,
        );

        try std.testing.expectEqual(
            0.75,
            t.phase,
        );
    }
    
    {
        const t = (
            PhaseOrdinate.init(-0.05)
        ).normalized();

        try std.testing.expectEqual(
            -1,
            t.count,
        );

        try std.testing.expectEqual(
            0.95,
            t.phase,
        );
    }
}

// test "PhaseOrdinate: to_continuous"
// {
//     try std.testing.expectEqual(
//         0.3,
//         PhaseOrdinate.init(0.3).to_continuous().value,
//     );
//
//     try std.testing.expectEqual(
//         -0.3,
//         PhaseOrdinate.init(-0.3).to_continuous().value,
//     );
// }

test "PhaseOrdinate: negate"
{
    const ord_neg = PhaseOrdinate.init(1).negate();

    try std.testing.expectEqual( -1, ord_neg.count);

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

    // {
    //     const po_five = PhaseOrdinate.init(5);
    //     const po_should_be_ten = po_five.add(po_five);
    //
    //     try std.testing.expectEqual(
    //         10,
    //         po_should_be_ten.to_continuous().value,
    //     );
    // }
    //
    // {
    //     const po_1pt5 = PhaseOrdinate.init(1.5);
    //     const po_should_be_three = po_1pt5.add(po_1pt5);
    //
    //     try std.testing.expectEqual(
    //         3,
    //         po_should_be_three.to_continuous().value,
    //     );
    // }
    //
    // {
    //     const po_should_be_pt6 = (
    //         PhaseOrdinate.init(0.3).add(
    //             PhaseOrdinate.init(0.2)
    //         ).add(PhaseOrdinate.init(0.1))
    //     );
    //
    //     try std.testing.expectEqual(
    //         0.6,
    //         po_should_be_pt6.to_continuous().value,
    //     );
    // }
    //
    // {
    //     try std.testing.expectEqual(
    //         0.1,
    //         PhaseOrdinate.init(0.3).add(
    //             PhaseOrdinate.init(-0.2)
    //         ).to_continuous().value,
    //     );
    // }
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
//
// test "PhaseOrdinate: sub"
// {
//     {
//         const po_five = PhaseOrdinate.init(5);
//         const po_should_be_ten = po_five.sub(po_five);
//
//         try std.testing.expectEqual(
//             0,
//             po_should_be_ten.to_continuous().value,
//         );
//     }
//
//     {
//         const po_1pt5 = PhaseOrdinate.init(1.5);
//         const po_should_be_one = po_1pt5.sub(
//             PhaseOrdinate.init(0.5)
//         );
//
//         try std.testing.expectEqual(
//             1,
//             po_should_be_one.to_continuous().value,
//         );
//     }
// }
//
// test "PhaseOrdinate mul"
// {
//     {
//         const po_five = PhaseOrdinate.init(5);
//         const po_should_be_25 = po_five.mul(po_five);
//
//         try std.testing.expectEqual(
//             25,
//             po_should_be_25.to_continuous().value,
//         );
//     }
//
//     {
//         const po_1pt5 = PhaseOrdinate.init(1.5);
//         const po_should_be_225 = po_1pt5.add(po_1pt5);
//
//         try std.testing.expectEqual(
//             2.25,
//             po_should_be_225.to_continuous().value,
//         );
//     }
// }

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
