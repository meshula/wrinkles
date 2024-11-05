//! Continuous Interval definition/Implementation

const std = @import("std"); 
const expectEqual = std.testing.expectEqual;
const expect = std.testing.expect;

const util = @import("util.zig"); 
const ordinate = @import("ordinate.zig"); 

/// An infinite interval
pub const INF_CTI: ContinuousTimeInterval = .{
    .start_seconds = -util.inf, 
    .end_seconds = util.inf
};

/// right open interval on the time continuum
/// the default CTI splits the timeline at the origin
pub const ContinuousTimeInterval = struct {
    /// the start time of the interval in seconds, inclusive
    start_seconds: ordinate.Ordinate = 0,

    /// the end time of the interval in seconds, exclusive
    end_seconds: ordinate.Ordinate = util.inf,

    /// compute the duration of the interval, if either boundary is not finite,
    /// the duration is infinite.
    pub fn duration_seconds(
        self: @This(),
    ) ordinate.Ordinate 
    {
        if (
            !std.math.isFinite(self.start_seconds) 
            or !std.math.isFinite(self.end_seconds)
        )
        {
            return util.inf;
        }

        return self.end_seconds - self.start_seconds;
    }

    pub fn from_start_duration_seconds(
        start_seconds: ordinate.Ordinate,
        in_duration_seconds: ordinate.Ordinate,
    ) ContinuousTimeInterval
    {
        if (in_duration_seconds <= 0)
        {
            @panic("duration <= 0");
        }

        return .{
            .start_seconds = start_seconds,
            .end_seconds = start_seconds + in_duration_seconds
        };
    }

    /// return true if t_seconds is within the interval
    pub fn overlaps_seconds(
        self: @This(),
        t_seconds: ordinate.Ordinate,
    ) bool 
    {
        return (
            (t_seconds >= self.start_seconds)
            and (t_seconds < self.end_seconds)
        );
    }

    /// return whether one of the end points of the interval is infinite
    pub fn is_infinite(
        self: @This(),
    ) bool
    {
        return (
            self.start_seconds == util.inf
            or self.end_seconds == util.inf
        );
    }

    /// detect if this interval starts and ends at the same ordinate
    pub fn is_instant(
        self: @This(),
    ) bool
    {
        return (self.start_seconds == self.end_seconds);
    }

    /// custom formatter for std.fmt
    pub fn format(
        self: @This(),
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void 
    {
        try writer.print(
            "c@[{d}, {d})",
            .{
                self.start_seconds,
                self.end_seconds,
            }
        );
    }
};

test "ContinuousTimeInterval: is_infinite"
{
    var cti = ContinuousTimeInterval{};

    try expectEqual(true, cti.is_infinite());

    cti.end_seconds = 2;

    try expectEqual(false, cti.is_infinite());

    cti.start_seconds = util.inf;

    try expectEqual(true, cti.is_infinite());
}

/// return a new interval that spans the duration of both argument intervals
pub fn extend(
    fst: ContinuousTimeInterval,
    snd: ContinuousTimeInterval
) ContinuousTimeInterval 
{
    return .{
        .start_seconds = @min(fst.start_seconds, snd.start_seconds),
        .end_seconds = @max(fst.end_seconds, snd.end_seconds),
    };
}

test "ContinuousTimeInterval: extend"
{
    const TestStruct = struct {
        fst: ContinuousTimeInterval,
        snd: ContinuousTimeInterval,
        res: ContinuousTimeInterval,
    };
    const tests = [_]TestStruct{
        .{ 
            .fst = .{
                .start_seconds = 0,
                .end_seconds = 10,
            },
            .snd = .{
                .start_seconds = 8,
                .end_seconds = 12,
            },
            .res = .{
                .start_seconds = 0,
                .end_seconds = 12,
            },
        },
        .{ 
            .fst = .{
                .start_seconds = 0,
                .end_seconds = 10,
            },
            .snd = .{
                .start_seconds = -2,
                .end_seconds = 9,
            },
            .res = .{
                .start_seconds = -2,
                .end_seconds = 10,
            },
        },
        .{ 
            .fst = .{
                .start_seconds = 0,
                .end_seconds = 10,
            },
            .snd = .{
                .start_seconds = -2,
                .end_seconds = 12,
            },
            .res = .{
                .start_seconds = -2,
                .end_seconds = 12,
            },
        },
        .{ 
            .fst = .{
                .start_seconds = 0,
                .end_seconds = 2,
            },
            .snd = .{
                .start_seconds = 4,
                .end_seconds = 12,
            },
            .res = .{
                .start_seconds = 0,
                .end_seconds = 12,
            },
        },
    };

    for (tests)
        |t|
    {
        const measured = extend(t.fst, t.snd);

        try std.testing.expectEqual(
            t.res.start_seconds,
            measured.start_seconds
        );
        try std.testing.expectEqual(
            t.res.end_seconds,
            measured.end_seconds
        );
    }
}

/// return whether there is any overlap between fst and snd
pub fn any_overlap(
    fst: ContinuousTimeInterval,
    snd: ContinuousTimeInterval,
) bool 
{
    const fst_is_instant = fst.is_instant();
    const snd_is_instant = snd.is_instant();
    return (
        // for cases when one interval starts and ends on the same point, allow
        // allow that point to overlap (because of the clusivity the start
        // point).
        (
             fst_is_instant
             and fst.start_seconds >= snd.start_seconds
             and fst.start_seconds < snd.end_seconds
        ) or (
            snd_is_instant
            and snd.start_seconds >= fst.start_seconds
            and snd.start_seconds <  fst.end_seconds
        ) or (
        // general case
         fst.start_seconds < snd.end_seconds
         and fst.end_seconds > snd.start_seconds
        )
    );
}

test "ContinuousTimeInterval: any_overlap"
{ 
    const TestStruct = struct {
        fst: ContinuousTimeInterval,
        snd: ContinuousTimeInterval,
        res: bool,
    };
    const tests = [_]TestStruct{
        .{ 
            .fst = .{
                .start_seconds = 0,
                .end_seconds = 10,
            },
            .snd = .{
                .start_seconds = 8,
                .end_seconds = 12,
            },
            .res = true,
        },
        .{ 
            .fst = .{
                .start_seconds = 0,
                .end_seconds = 10,
            },
            .snd = .{
                .start_seconds = -2,
                .end_seconds = 9,
            },
            .res = true,
        },
        .{ 
            .fst = .{
                .start_seconds = 0,
                .end_seconds = 10,
            },
            .snd = .{
                .start_seconds = -2,
                .end_seconds = 12,
            },
            .res = true,
        },
        .{ 
            .fst = .{
                .start_seconds = 0,
                .end_seconds = 4,
            },
            .snd = .{
                .start_seconds = 5,
                .end_seconds = 12,
            },
            .res = false,
        },
        .{ 
            .fst = .{
                .start_seconds = 0,
                .end_seconds = 4,
            },
            .snd = .{
                .start_seconds = -2,
                .end_seconds = 0,
            },
            .res = false,
        },
    };

    for (tests)
        |t|
    {
        const measured = any_overlap(t.fst, t.snd);

        try std.testing.expectEqual(
            t.res,
            measured,
        );
    }
}

/// return an interval of the intersection or null if they are disjoint
pub fn intersect(
    fst: ContinuousTimeInterval,
    snd: ContinuousTimeInterval
) ?ContinuousTimeInterval 
{
    if (any_overlap(fst, snd) == false) {
        return null;
    }

    return .{
        .start_seconds = @max(fst.start_seconds, snd.start_seconds),
        .end_seconds = @min(fst.end_seconds, snd.end_seconds),
    };
}

test "intersection test - contained" {
    const int1 = ContinuousTimeInterval{
        .start_seconds = 0,
        .end_seconds = 10
    };
    const int2 = ContinuousTimeInterval{
        .start_seconds = 1,
        .end_seconds = 3
    };
    const res = intersect(
        int1, 
        int2
    ) orelse ContinuousTimeInterval{};

    try std.testing.expectApproxEqAbs(
        res.start_seconds,
        int2.start_seconds,
        util.EPSILON
    );
    try std.testing.expectApproxEqAbs(
        res.end_seconds,
        int2.end_seconds,
        util.EPSILON
    );
}

test "intersection test - infinite" {
    const int1 = INF_CTI;
    const int2 = ContinuousTimeInterval{
        .start_seconds = 1,
        .end_seconds = 3
    };
    const res = intersect(
        int1,
        int2
    ) orelse ContinuousTimeInterval{};

    try std.testing.expectApproxEqAbs(
        res.start_seconds,
        int2.start_seconds,
        util.EPSILON
    );
    try std.testing.expectApproxEqAbs(
        res.end_seconds,
        int2.end_seconds,
        util.EPSILON
    );
}

test "ContinuousTimeInterval Tests" 
{
    const ival : ContinuousTimeInterval = .{
        .start_seconds = 10,
        .end_seconds = 20,
    };

    try expectEqual(
        ival,
        ContinuousTimeInterval.from_start_duration_seconds(
            ival.start_seconds,
            ival.duration_seconds()
        )
    );
}

test "ContinuousTimeInterval: Overlap tests" 
{
    const ival : ContinuousTimeInterval = .{
        .start_seconds = 10,
        .end_seconds = 20,
    };

    try expect(!ival.overlaps_seconds(0));
    try expect(ival.overlaps_seconds(10));
    try expect(ival.overlaps_seconds(15));
    try expect(!ival.overlaps_seconds(20));
    try expect(!ival.overlaps_seconds(30));
}

test "ContinuousTimeInterval: is_instant"
{
    const is_not_point = ContinuousTimeInterval {
        .start_seconds = 0,
        .end_seconds = 0.1,
    };

    try std.testing.expect(is_not_point.is_instant() != true);

    const collapsed = ContinuousTimeInterval {
        .start_seconds = 10,
        .end_seconds = 10,
    };

    try std.testing.expect(collapsed.is_instant());
}
