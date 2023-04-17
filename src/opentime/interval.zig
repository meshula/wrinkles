const std = @import("std"); 
const util = @import("util.zig"); 

const ot_ord = @import("ordinate.zig"); 
const Ordinate = ot_ord.Ordinate; 

const expectEqual = std.testing.expectEqual;
const expect = std.testing.expect;

// Intervals and Points @{
// ////////////////////////////////////////////////////////////////////////////

const ContinuousInterval_f32 = struct {
    start_sc: f32,
    end_sc: f32,

    // @TODO: should this do checks for end after start, etc?
    pub fn init(in_start: f32, in_end: f32) ContinuousInterval {
        return .{ .f32 = .{ .start_sc = in_start, .end_sc = in_end } };
    }

    pub fn start(self: @This()) Ordinate {
        return .{ .f32 = self.start_sc };
    }

    pub fn end(self: @This()) Ordinate {
        return .{ .f32 = self.end_sc };
    }
};

const ContinuousInterval_rational = struct {
    start_sc:i32,
    end_sc:i32,
    denominator: i32,

    // @TODO: should this do checks for end after start, etc?
    //        ... or consistent denominator
    pub fn init(
        in_start: ot_ord.Rational,
        in_end: ot_ord.Rational
    ) ContinuousInterval 
    {
        return .{
            .rational = .{ 
                .start_sc = in_start.numerator,
                .end_sc = in_end.numerator,
                .denominator = in_start.denominator,
            } 
        };
    }

    pub fn start(self: @This()) Ordinate {
        return .{
            .rational = .{
                .numerator = self.start_sc,
                .denominator = self.denominator 
            } 
        };
    }

    pub fn end(self: @This()) Ordinate {
        return .{
            .rational = .{
                .numerator = self.end_sc,
                .denominator = self.denominator 
            } 
        };
    }
};

// right open interval on the time continuum
// the default CTI splits the timeline at the origin
pub const ContinuousInterval = union(ot_ord.OrdinateKinds) {
    f32: ContinuousInterval_f32,
    rational: ContinuousInterval_rational,

    // @{ Initializers
    pub fn init(
        in_start: anytype,
        in_end: @TypeOf(in_start)
    ) ContinuousInterval 
    {
        return switch(@TypeOf(in_start)) {
            f32 => ContinuousInterval_f32.init(in_start, in_end),
            ot_ord.Rational => ContinuousInterval_rational.init(in_start, in_end),
            Ordinate => {
                if (std.meta.activeTag(in_start) != std.meta.activeTag(in_end)) {
                    unreachable;
                }
                switch (in_start) {
                    .f32 => return ContinuousInterval.init(in_start.f32, in_end.f32),
                    .rational => return ContinuousInterval.init(in_start.rational, in_end.rational),
                }
            },
            else => unreachable,
        };
    }
    // @}

    // @{ accessors
    pub fn start(self: @This()) Ordinate {
        return switch (self) {
            inline else => |value| value.start()
        };
    }

    pub fn end(self: @This()) Ordinate {
        return switch (self) {
            inline else => |value| value.end() 
        };
    }

    // compute the duration of the interval, if either boundary is not finite,
    // the duration is infinite.
    pub fn duration(self: @This()) Ordinate 
    {
        switch(self) {
            .f32 => |value| {
                if (
                    !std.math.isFinite(value.start_sc) or 
                    !std.math.isFinite(value.end_sc)
                ) {
                    return .{ .f32 = util.inf };
                }

                return .{ .f32 = value.end_sc - value.start_sc };
            },
            .rational => |value| {
                return .{
                    .rational = .{
                        .numerator = value.end_sc-value.start_sc,
                        .denominator = value.denominator
                    }
                };
            }
        }
    }
    // @}

    pub fn init_start_duration(
        in_start: anytype,
        in_duration: @TypeOf(in_start),
    ) ContinuousInterval
    {
        switch (@TypeOf(in_start)) {
            ot_ord.Rational => {
                if (in_duration.to_f32() <= 0)
                {
                    @panic("duration <= 0");
                }

                return .{
                    .start_sc = in_start,
                    .end_sc = in_start.add(in_duration)
                };
            },
            inline else => {
                if (in_duration <= 0)
                {
                    @panic("duration <= 0");
                }

                return .{
                    .f32 = .{
                        .start_sc = in_start,
                        .end_sc = in_start + in_duration,
                    }
                };
            }
        }
    }

    pub fn overlaps_ordinate(self: @This(), ord: Ordinate) bool {
        return (
            (ord.to_f32() >= self.start().to_f32())
            and (ord.to_f32() < self.end().to_f32())
        );
    }
};

test "ContinuousInterval: Initializers and accesesors" 
{
    {
        const start = Ordinate{ .f32 = 10 };
        const end = Ordinate{ .f32 =  20 };

        // f32
        {
            const ci = ContinuousInterval.init(start.f32, end.f32);

            try expectEqual(ci.start().f32, start.f32);
            try expectEqual(ci.end().f32, end.f32);

            try expectEqual(ci.f32.start_sc, start.f32);
            try expectEqual(ci.f32.end_sc, end.f32);
        }

        // Ordinate / f32
        {
            const ci = ContinuousInterval.init(start, end);

            try expectEqual(ci.start().f32, start.f32);
            try expectEqual(ci.end().f32, end.f32);

            try expectEqual(ci.f32.start_sc, start.f32);
            try expectEqual(ci.f32.end_sc, end.f32);
        }
    }
}

test "ContinuousInterval: Overlap" 
{
    {
        const start = Ordinate{ .f32 = 10 };
        const end = Ordinate{ .f32 =  20 };
        const mid = start.add(end).divExact(.{ .f32 = 2 });

        // f32
        {
            const ci = ContinuousInterval.init(start.f32, end.f32);

            try expect(ci.overlaps_ordinate(start));
            try expect(ci.overlaps_ordinate(mid));
            try expect(ci.overlaps_ordinate(end) == false);
        }

        // Ordinate / f32
        {
            const ci = ContinuousInterval.init(start, end);

            try expect(ci.overlaps_ordinate(start));
            try expect(ci.overlaps_ordinate(mid));
            try expect(ci.overlaps_ordinate(end) == false);
        }
    }

    // rational
    {
        const start = Ordinate{ .rational = .{ .numerator = 10, .denominator = 24 } };
        const end   = Ordinate{ .rational = .{ .numerator = 20, .denominator = 24 } };
        const mid   = start.add(end).div(.{ .f32 = 2 });

        // rational
        {
            const ci = ContinuousInterval.init(start.rational, end.rational);

            try expect(ci.overlaps_ordinate(start));
            try expect(ci.overlaps_ordinate(mid));
            try expect(ci.overlaps_ordinate(end) == false);
        }

        // Ordinate / rational
        {
            const ci = ContinuousInterval.init(start, end);

            try expect(ci.overlaps_ordinate(start));
            try expect(ci.overlaps_ordinate(mid));
            try expect(ci.overlaps_ordinate(end) == false);
        }
    }
}

// return a new interval that spans the duration of both argument intervals
// the type of the interval will match the type of the first argument
pub fn extend(
    fst: ContinuousInterval,
    snd: ContinuousInterval
) ContinuousInterval {
    return .{
        .f32 = .{
            .start_sc = std.math.min(
                fst.start().to_f32(),
                snd.start().to_f32()
            ),
            .end_sc = std.math.max(
                fst.end().to_f32(),
                snd.end().to_f32()
            )
        }
    };
}

test "ContinuousInterval: extend" {
    const ci_1 = ContinuousInterval.init(@as(f32, 10), @as(f32, 20));
    const ci_2 = ContinuousInterval.init(@as(f32, 20), @as(f32, 24));
    const ci_3 = ContinuousInterval.init(@as(f32, 5), @as(f32, 24));

    try std.testing.expectApproxEqAbs(ci_2.end().f32, extend(ci_1, ci_2).end().f32, util.EPSILON);
    try std.testing.expectApproxEqAbs(ci_3.start().f32, extend(ci_1, ci_3).start().f32, util.EPSILON);
}

pub fn any_overlap(
    fst: ContinuousInterval,
    snd: ContinuousInterval
) bool {
    return (
        fst.start().to_f32() < snd.end().to_f32() 
        and fst.end().to_f32() > snd.start().to_f32()
    );
}

test "ContinuousInterval: any overlap" {
    const TestData = struct{
        fst: ContinuousInterval,
        snd: ContinuousInterval,
        res: bool,
    };

    const tests = [_]TestData {
        // 2 overlaps the front of 1
        .{
            .fst = ContinuousInterval.init(@as(f32, 10), @as(f32, 20)),
            .snd = ContinuousInterval.init(@as(f32, 5), @as(f32, 15)),
            .res = true,
        },
        // 2 overlaps the end of 1
        .{
            .fst = ContinuousInterval.init(@as(f32, 10), @as(f32, 20)),
            .snd = ContinuousInterval.init(@as(f32, 15), @as(f32, 25)),
            .res = true,
        },
        // 2 within 1
        .{
            .fst = ContinuousInterval.init(@as(f32, 10), @as(f32, 20)),
            .snd = ContinuousInterval.init(@as(f32, 15), @as(f32, 17)),
            .res = true,
        },
        // 1 within 2
        .{
            .fst = ContinuousInterval.init(@as(f32, 10), @as(f32, 20)),
            .snd = ContinuousInterval.init(@as(f32, 5), @as(f32, 30)),
            .res = true,
        },
        // 2 meets start of 1
        .{
            .fst = ContinuousInterval.init(@as(f32, 10), @as(f32, 20)),
            .snd = ContinuousInterval.init(@as(f32, 5), @as(f32, 10)),
            .res = false,
        },
        // 2 meets end of 1
        .{
            .fst = ContinuousInterval.init(@as(f32, 10), @as(f32, 20)),
            .snd = ContinuousInterval.init(@as(f32, 20), @as(f32, 25)),
            .res = false,
        },
        // 2 > 1
        .{
            .fst = ContinuousInterval.init(@as(f32, 10), @as(f32, 20)),
            .snd = ContinuousInterval.init(@as(f32, 21), @as(f32, 25)),
            .res = false,
        },
        // 2 < 1
        .{
            .fst = ContinuousInterval.init(@as(f32, 10), @as(f32, 20)),
            .snd = ContinuousInterval.init(@as(f32, 1), @as(f32, 5)),
            .res = false,
        },
        // 2 == 1
        .{
            .fst = ContinuousInterval.init(@as(f32, 10), @as(f32, 20)),
            .snd = ContinuousInterval.init(@as(f32, 10), @as(f32, 20)),
            .res = true,
        },
    };

    for (tests) |t, index| {
        errdefer std.log.err(
            "Index: {d}, fst: [{d}, {d}), snd: [{d}, {d}), res: {any}\n",
            .{ 
                index,
                t.fst.start().f32, t.fst.end().f32,
                t.snd.start().f32, t.snd.end().f32,
                t.res 
            }
        );

        try expectEqual(t.res, any_overlap(t.fst, t.snd));
        try expectEqual(t.res, any_overlap(t.snd, t.fst));
    }
}



pub fn union_of(
    fst: ContinuousInterval,
    snd: ContinuousInterval
) ?ContinuousInterval {
    if (!any_overlap(fst, snd)) {
        return null;
    }

    return .{
        .f32 = .{ 
            .start_sc = std.math.min(fst.start().to_f32(), snd.start().to_f32()),
            .end_sc = std.math.max(fst.end().to_f32(), snd.end().to_f32()),
        }
    };
}

test "ContinuousInterval: union_of" {
    const TestData = struct{
        fst: ContinuousInterval,
        snd: ContinuousInterval,
        res: ?ContinuousInterval,
    };

    const tests = [_]TestData {
        // 2 overlaps the front of 1
        .{
            .fst = ContinuousInterval.init(@as(f32, 10), @as(f32, 20)),
            .snd = ContinuousInterval.init(@as(f32, 5), @as(f32, 15)),
            .res = ContinuousInterval.init(@as(f32, 5), @as(f32, 20)),
        },
        // 2 overlaps the end of 1
        .{
            .fst = ContinuousInterval.init(@as(f32, 10), @as(f32, 20)),
            .snd = ContinuousInterval.init(@as(f32, 15), @as(f32, 25)),
            .res = ContinuousInterval.init(@as(f32, 10), @as(f32, 25)),
        },
        // 2 within 1
        .{
            .fst = ContinuousInterval.init(@as(f32, 10), @as(f32, 20)),
            .snd = ContinuousInterval.init(@as(f32, 15), @as(f32, 17)),
            .res = ContinuousInterval.init(@as(f32, 10), @as(f32, 20)),
        },
        // 1 within 2
        .{
            .fst = ContinuousInterval.init(@as(f32, 10), @as(f32, 20)),
            .snd = ContinuousInterval.init(@as(f32, 5), @as(f32, 30)),
            .res = ContinuousInterval.init(@as(f32, 5), @as(f32, 30)),
        },
        // 2 meets start of 1
        .{
            .fst = ContinuousInterval.init(@as(f32, 10), @as(f32, 20)),
            .snd = ContinuousInterval.init(@as(f32, 5), @as(f32, 10)),
            .res = null,
        },
        // 2 meets end of 1
        .{
            .fst = ContinuousInterval.init(@as(f32, 10), @as(f32, 20)),
            .snd = ContinuousInterval.init(@as(f32, 20), @as(f32, 25)),
            .res = null,
        },
        // 2 > 1
        .{
            .fst = ContinuousInterval.init(@as(f32, 10), @as(f32, 20)),
            .snd = ContinuousInterval.init(@as(f32, 21), @as(f32, 25)),
            .res = null,
        },
        // 2 < 1
        .{
            .fst = ContinuousInterval.init(@as(f32, 10), @as(f32, 20)),
            .snd = ContinuousInterval.init(@as(f32, 1), @as(f32, 5)),
            .res = null,
        },
        // 2 == 1
        .{
            .fst = ContinuousInterval.init(@as(f32, 10), @as(f32, 20)),
            .snd = ContinuousInterval.init(@as(f32, 10), @as(f32, 20)),
            .res = ContinuousInterval.init(@as(f32, 10), @as(f32, 20)),
        },
    };

    for (tests) |t, index| {
        errdefer std.log.err(
            "Index: {d}, fst: [{d}, {d}), snd: [{d}, {d}), res: {any}\n",
            .{ 
                index,
                t.fst.start().f32, t.fst.end().f32,
                t.snd.start().f32, t.snd.end().f32,
                t.res 
            }
        );

        try expectEqual(t.res, union_of(t.fst, t.snd));
        try expectEqual(t.res, union_of(t.snd, t.fst));
    }
}



// pub fn intersect(
//     fst: ContinuousTimeInterval,
//     snd: ContinuousTimeInterval
// ) ?ContinuousTimeInterval {
//     if (!any_overlap(fst, snd)) {
//         return null;
//     }
//
//     return .{
//         .start_sc = std.math.max(fst.start_sc, snd.start_sc),
//         .end_sc = std.math.min(fst.end_sc, snd.end_sc),
//     };
// }
//
// test "intersection test" {
//     {
//         const int1 = ContinuousTimeInterval.init_f32(
//             .{
//                 .start_sc = 0,
//                 .end_sc = 10
//             }
//         );
//         const int2 = ContinuousTimeInterval.init_f32(
//             .{
//                 .start_sc = 1,
//                 .end_sc = 3
//             }
//         );
//         const res = intersect(int1, int2) orelse ContinuousTimeInterval{};
//
//         try std.testing.expectApproxEqAbs(
//             res.start_sc.f32,
//             int2.start_sc.f32,
//             util.EPSILON
//         );
//         try std.testing.expectApproxEqAbs(
//             res.end_sc.f32,
//             int2.end_sc.f32,
//             util.EPSILON
//         );
//     }
//
//     {
//         const int1 = INF_CTI;
//         const int2 = ContinuousTimeInterval.init_f32(
//             .{
//                 .start_sc = 1,
//                 .end_sc = 3
//             }
//         );
//         const res = intersect(int1, int2) orelse ContinuousTimeInterval{};
//
//         try std.testing.expectApproxEqAbs(
//             res.start_sc.f32,
//             int2.start_sc.f32,
//             util.EPSILON
//         );
//         try std.testing.expectApproxEqAbs(
//             res.end_sc.f32,
//             int2.end_sc.f32,
//             util.EPSILON
//         );
//     }
//
//     {
//         const int1 = INF_CTI;
//         const int2 = ContinuousTimeInterval.init_f32(
//             .{
//                 .start_sc = 1,
//                 .end_sc = 3
//             }
//         );
//         const res = intersect(int2, int1) orelse ContinuousTimeInterval{};
//
//         try std.testing.expectApproxEqAbs(
//             res.start_sc.f32,
//             int2.start_sc.f32,
//             util.EPSILON
//         );
//         try std.testing.expectApproxEqAbs(
//             res.end_sc.f32,
//             int2.end_sc.f32,
//             util.EPSILON
//         );
//     }
// }
//
// pub const INF_CTI: ContinuousTimeInterval = .{
//     .start_sc = .{ .f32 = -util.inf }, 
//     .end_sc = .{ .f32 = util.inf },
// };
//

test "ContinuousTimeInterval Duration Tests" {
    // f32
    {
        const ci = ContinuousInterval.init(@as(f32, 10), @as(f32, 20));

        try expectEqual(@as(f32, 10), ci.duration().f32);
    }

    // rational
    {
        const rat1 = ot_ord.Rational{ .numerator = 10, .denominator = 24 };
        const rat2 = ot_ord.Rational{ .numerator = 20, .denominator = 24 };
        const ci = ContinuousInterval.init(rat1, rat2);

        try expectEqual(rat1.numerator, ci.duration().rational.numerator);
        try expectEqual(rat1.denominator, ci.duration().rational.denominator);
    }

    // from duration
    {
        const ci = ContinuousInterval.init(@as(f32, 10), @as(f32, 20));

        try expectEqual(
            ci,
            ContinuousInterval.init_start_duration(
                ci.f32.start_sc,
                ci.duration().f32,
            )
        );
    }

}
//
// test "ContinuousTimeInterval: Overlap tests" {
//     const ival = ContinuousTimeInterval.init_f32(
//         .{
//             .start_sc = 10,
//             .end_sc = 20,
//         }
//     );
//
//     try expect(!ival.overlaps_ordinate(.{ .f32 = 0}));
//     try expect(ival.overlaps_ordinate(.{ .f32 = 10}));
//     try expect(ival.overlaps_ordinate(.{ .f32 = 15}));
//     try expect(!ival.overlaps_ordinate(.{ .f32 = 20}));
//     try expect(!ival.overlaps_ordinate(.{ .f32 = 30}));
// }
// // @}
