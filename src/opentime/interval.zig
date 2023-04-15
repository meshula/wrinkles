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
};

const ContinuousInterval_rational = struct {
    start_sc:f32,
    end_sc:f32,
    denominator: f32,
};

// right open interval on the time continuum
// the default CTI splits the timeline at the origin
pub const ContinuousInterval = union(ot_ord.OrdinateKinds) {
    f32: ContinuousInterval_f32,
    rational: ContinuousInterval_rational,

    pub fn init(
        k: ot_ord.OrdinateKinds,
        start_ord: anytype,
        end_ord: @TypeOf(start_ord)
    ) ContinuousInterval 
    {
        return switch (k) {
            .rational => .{
                .start_sc = start_ord.numerator,
                .end_sc = end_ord.numerator,
                .denominator = start_ord.denominator,
            },
            inline else => @unionInit(
                ContinuousInterval,
                @tagName(k),
                .{ 
                    .start_sc = start_ord,
                    .end_sc = end_ord
                }
            )
        };
    }

    pub fn start(self: @This()) Ordinate {
        return switch (self) {
            inline else => |value, tag| @unionInit(
                Ordinate,
                @tagName(tag),
                value.start_sc
            )
        };
    }

    pub fn end(self: @This()) Ordinate {
        return switch (self) {
            inline else => |value, tag| @unionInit(
                Ordinate,
                @tagName(tag),
                value.end_sc
            )
        };
    }

    // compute the duration of the interval, if either boundary is not finite,
    // the duration is infinite.
    pub fn duration_seconds(self: @This()) Ordinate 
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
                if (!value.start_sc.isFinite() or !value.end_sc.isFinite()) {
                    return .{ .f32 = util.inf };
                }

                return .{
                    .rational = .{
                        .numerator = value.end_sc-value.start_sc,
                        .denominator = value.denominator
                    }
                };
            }
        }
    }

    pub fn from_start_duration_seconds(
        start_seconds: Ordinate,
        in_duration_seconds: Ordinate
    ) ContinuousTimeInterval
    {
        if (in_duration_seconds.to_f32() <= 0)
        {
            @panic("duration <= 0");
        }

        return .{
            .start_seconds = start_seconds,
            .end_seconds = start_seconds.add(in_duration_seconds)
        };
    }

    pub fn overlaps_ordinate(self: @This(), t_seconds: Ordinate) bool {
        return (
            (t_seconds.to_f32() >= self.start_seconds.to_f32())
            and (t_seconds.to_f32() < self.end_seconds.to_f32())
        );
    }
};

/// return a new interval that spans the duration of both argument intervals
pub fn extend(
    fst: ContinuousTimeInterval,
    snd: ContinuousTimeInterval
) ContinuousTimeInterval {
    return .{
        .start_seconds = Ordinate{ 
            .f32 = std.math.min(
                fst.start_seconds.to_f32(),
                snd.start_seconds.to_f32()
            )
        },
        .end_seconds = Ordinate{ 
            .f32 = std.math.max(
                fst.end_seconds.to_f32(),
                snd.end_seconds.to_f32()
            ),
        }
    };
}

pub fn any_overlap(
    fst: ContinuousTimeInterval,
    snd: ContinuousTimeInterval
) bool {
    return (
        fst.start_seconds < snd.end_seconds
        and fst.end_seconds > snd.start_seconds
    );
}

pub fn union_of(
    fst: ContinuousTimeInterval,
    snd: ContinuousTimeInterval
) ?ContinuousTimeInterval {
    if (!any_overlap(fst, snd)) {
        return null;
    }

    return .{
        .start_seconds = std.math.min(fst.start_seconds, snd.start_seconds),
        .end_seconds = std.math.max(fst.end_seconds, snd.end_seconds),
    };
}

pub fn intersect(
    fst: ContinuousTimeInterval,
    snd: ContinuousTimeInterval
) ?ContinuousTimeInterval {
    if (!any_overlap(fst, snd)) {
        return null;
    }

    return .{
        .start_seconds = std.math.max(fst.start_seconds, snd.start_seconds),
        .end_seconds = std.math.min(fst.end_seconds, snd.end_seconds),
    };
}

test "intersection test" {
    {
        const int1 = ContinuousTimeInterval.init_f32(
            .{
                .start_seconds = 0,
                .end_seconds = 10
            }
        );
        const int2 = ContinuousTimeInterval.init_f32(
            .{
                .start_seconds = 1,
                .end_seconds = 3
            }
        );
        const res = intersect(int1, int2) orelse ContinuousTimeInterval{};

        try std.testing.expectApproxEqAbs(
            res.start_seconds.f32,
            int2.start_seconds.f32,
            util.EPSILON
        );
        try std.testing.expectApproxEqAbs(
            res.end_seconds.f32,
            int2.end_seconds.f32,
            util.EPSILON
        );
    }

    {
        const int1 = INF_CTI;
        const int2 = ContinuousTimeInterval.init_f32(
            .{
                .start_seconds = 1,
                .end_seconds = 3
            }
        );
        const res = intersect(int1, int2) orelse ContinuousTimeInterval{};

        try std.testing.expectApproxEqAbs(
            res.start_seconds.f32,
            int2.start_seconds.f32,
            util.EPSILON
        );
        try std.testing.expectApproxEqAbs(
            res.end_seconds.f32,
            int2.end_seconds.f32,
            util.EPSILON
        );
    }

    {
        const int1 = INF_CTI;
        const int2 = ContinuousTimeInterval.init_f32(
            .{
                .start_seconds = 1,
                .end_seconds = 3
            }
        );
        const res = intersect(int2, int1) orelse ContinuousTimeInterval{};

        try std.testing.expectApproxEqAbs(
            res.start_seconds.f32,
            int2.start_seconds.f32,
            util.EPSILON
        );
        try std.testing.expectApproxEqAbs(
            res.end_seconds.f32,
            int2.end_seconds.f32,
            util.EPSILON
        );
    }
}

pub const INF_CTI: ContinuousTimeInterval = .{
    .start_seconds = .{ .f32 = -util.inf }, 
    .end_seconds = .{ .f32 = util.inf },
};

test "ContinuousTimeInterval Tests" {
    const ival = ContinuousTimeInterval.init_f32(
        .{
            .start_seconds = 10,
            .end_seconds = 20,
        }
    );

    try expectEqual(
        ival,
        ContinuousTimeInterval.from_start_duration_seconds(
            ival.start_seconds,
            ival.duration_seconds()
        )
    );
}

test "ContinuousTimeInterval: Overlap tests" {
    const ival = ContinuousTimeInterval.init_f32(
        .{
            .start_seconds = 10,
            .end_seconds = 20,
        }
    );

    try expect(!ival.overlaps_ordinate(.{ .f32 = 0}));
    try expect(ival.overlaps_ordinate(.{ .f32 = 10}));
    try expect(ival.overlaps_ordinate(.{ .f32 = 15}));
    try expect(!ival.overlaps_ordinate(.{ .f32 = 20}));
    try expect(!ival.overlaps_ordinate(.{ .f32 = 30}));
}
// @}
