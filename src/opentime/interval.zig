//! Continuous Interval definition/Implementation

const std = @import("std"); 

const util = @import("util.zig"); 
const ordinate = @import("ordinate.zig"); 

/// An infinite interval
pub const INFINITE_INTERVAL: ContinuousInterval = .{
    .start = -util.inf, 
    .end = util.inf,
};

/// Right open interval in a continuous metric space.  Default interval starts
/// at 0 and has no end.
pub const ContinuousInterval = struct {
    /// the start ordinate of the interval, inclusive
    start: ordinate.Ordinate = 0,

    /// the end ordinate of the interval, exclusive
    end: ordinate.Ordinate = util.inf,

    /// compute the duration of the interval, if either boundary is not finite,
    /// the duration is infinite.
    pub fn duration(
        self: @This(),
    ) ordinate.Ordinate 
    {
        if (
            !std.math.isFinite(self.start) 
            or !std.math.isFinite(self.end)
        )
        {
            return util.inf;
        }

        return self.end - self.start;
    }

    pub fn from_start_duration(
        start: ordinate.Ordinate,
        in_duration: ordinate.Ordinate,
    ) ContinuousInterval
    {
        if (in_duration <= 0)
        {
            @panic("duration <= 0");
        }

        return .{
            .start = start,
            .end = start + in_duration
        };
    }

    /// return true if ord is within the interval
    pub fn overlaps(
        self: @This(),
        ord: ordinate.Ordinate,
    ) bool 
    {
        return (
            (
             self.is_instant()
             and self.start == ord
            )
            or 
            (
             (ord >= self.start)
             and (ord < self.end)
            )
        );
    }

    /// return whether one of the end points of the interval is infinite
    pub fn is_infinite(
        self: @This(),
    ) bool
    {
        return (
            std.math.isInf(self.start)
            or std.math.isInf(self.end)
        );
    }

    /// detect if this interval starts and ends at the same ordinate
    pub fn is_instant(
        self: @This(),
    ) bool
    {
        return (self.start == self.end);
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
                self.start,
                self.end,
            }
        );
    }
};

test "ContinuousInterval: is_infinite"
{
    var cti = ContinuousInterval{};

    try std.testing.expectEqual(true, cti.is_infinite());

    cti.end = 2;

    try std.testing.expectEqual(false, cti.is_infinite());

    cti.start = util.inf;

    try std.testing.expectEqual(true, cti.is_infinite());
}

/// return a new interval that spans the duration of both argument intervals
pub fn extend(
    fst: ContinuousInterval,
    snd: ContinuousInterval,
) ContinuousInterval 
{
    return .{
        .start = @min(fst.start, snd.start),
        .end = @max(fst.end, snd.end),
    };
}

test "ContinuousInterval: extend"
{
    const TestStruct = struct {
        fst: ContinuousInterval,
        snd: ContinuousInterval,
        res: ContinuousInterval,
    };
    const tests = [_]TestStruct{
        .{ 
            .fst = .{ .start = 0, .end = 10, },
            .snd = .{ .start = 8, .end = 12, },
            .res = .{ .start = 0, .end = 12, },
        },
        .{ 
            .fst = .{ .start = 0, .end = 10, },
            .snd = .{ .start = -2, .end = 9, },
            .res = .{ .start = -2, .end = 10, },
        },
        .{ 
            .fst = .{ .start = 0, .end = 10, },
            .snd = .{ .start = -2, .end = 12, },
            .res = .{ .start = -2, .end = 12, },
        },
        .{ 
            .fst = .{ .start = 0, .end = 2, },
            .snd = .{ .start = 4, .end = 12, },
            .res = .{ .start = 0, .end = 12, },
        },
    };

    for (tests)
        |t|
    {
        const measured = extend(t.fst, t.snd);

        try std.testing.expectEqual(
            t.res.start,
            measured.start
        );
        try std.testing.expectEqual(
            t.res.end,
            measured.end
        );
    }
}

/// return whether there is any overlap between fst and snd
pub fn any_overlap(
    fst: ContinuousInterval,
    snd: ContinuousInterval,
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
             and fst.start >= snd.start
             and fst.start < snd.end
        ) or (
            snd_is_instant
            and snd.start >= fst.start
            and snd.start <  fst.end
        ) or (
        // for cases where BOTH intervals are the same point, check if they all
        // match
        //
            fst_is_instant
            and snd_is_instant
            and fst.start == snd.start
        ) or (
        // general case
         fst.start < snd.end
         and fst.end > snd.start
        )
    );
}

test "ContinuousInterval: any_overlap"
{ 
    const TestStruct = struct {
        fst: ContinuousInterval,
        snd: ContinuousInterval,
        res: bool,
    };
    const tests = [_]TestStruct{
        .{ 
            .fst = .{ .start = 0, .end = 10, },
            .snd = .{ .start = 8, .end = 12, },
            .res = true,
        },
        .{ 
            .fst = .{ .start = 0, .end = 10, },
            .snd = .{ .start = -2, .end = 9, },
            .res = true,
        },
        .{ 
            .fst = .{ .start = 0, .end = 10, },
            .snd = .{ .start = -2, .end = 12, },
            .res = true,
        },
        .{ 
            .fst = .{ .start = 0, .end = 4, },
            .snd = .{ .start = 5, .end = 12, },
            .res = false,
        },
        .{ 
            .fst = .{ .start = 0, .end = 4, },
            .snd = .{ .start = -2, .end = 0, },
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
    fst: ContinuousInterval,
    snd: ContinuousInterval,
) ?ContinuousInterval 
{
    if (any_overlap(fst, snd) == false) {
        return null;
    }

    return .{
        .start = @max(fst.start, snd.start),
        .end = @min(fst.end, snd.end),
    };
}

test "intersection test - contained" {
    const int1 = ContinuousInterval{
        .start = 0,
        .end = 10
    };
    const int2 = ContinuousInterval{
        .start = 1,
        .end = 3
    };
    const res = intersect(
        int1, 
        int2
    ) orelse ContinuousInterval{};

    try std.testing.expectApproxEqAbs(
        res.start,
        int2.start,
        util.EPSILON
    );
    try std.testing.expectApproxEqAbs(
        res.end,
        int2.end,
        util.EPSILON
    );
}

test "intersection test - infinite" {
    const int1 = INFINITE_INTERVAL;
    const int2 = ContinuousInterval{
        .start = 1,
        .end = 3
    };
    const res = intersect(
        int1,
        int2
    ) orelse ContinuousInterval{};

    try std.testing.expectApproxEqAbs(
        res.start,
        int2.start,
        util.EPSILON
    );
    try std.testing.expectApproxEqAbs(
        res.end,
        int2.end,
        util.EPSILON
    );
}

test "ContinuousInterval Tests" 
{
    const ival : ContinuousInterval = .{
        .start = 10,
        .end = 20,
    };

    try std.testing.expectEqual(
        ival,
        ContinuousInterval.from_start_duration(
            ival.start,
            ival.duration()
        )
    );
}

test "ContinuousInterval: Overlap tests" 
{
    const ival : ContinuousInterval = .{
        .start = 10,
        .end = 20,
    };

    try std.testing.expect(!ival.overlaps(0));
    try std.testing.expect(ival.overlaps(10));
    try std.testing.expect(ival.overlaps(15));
    try std.testing.expect(!ival.overlaps(20));
    try std.testing.expect(!ival.overlaps(30));
}

test "ContinuousInterval: is_instant"
{
    const is_not_point = ContinuousInterval {
        .start = 0,
        .end = 0.1,
    };

    try std.testing.expect(is_not_point.is_instant() != true);

    const collapsed = ContinuousInterval {
        .start = 10,
        .end = 10,
    };

    try std.testing.expect(collapsed.is_instant());
}
