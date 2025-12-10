//! Continuous Interval definition/Implementation

const std = @import("std"); 

const ordinate = @import("ordinate.zig"); 

/// Right open interval in a continuous metric space.  Default interval starts
/// at 0 and has no end.
pub const ContinuousInterval = struct {
    /// the start ordinate of the interval, inclusive
    start: ordinate.Ordinate = ordinate.Ordinate.zero,

    /// the end ordinate of the interval, exclusive
    end: ordinate.Ordinate = ordinate.Ordinate.INF,

    pub const ZERO_TO_INF: ContinuousInterval = .{
        .start = .zero,
        .end = .INF,
    };

    /// An infinite interval
    pub const inf_neg_to_pos : ContinuousInterval = .{
        .start = ordinate.Ordinate.INF_NEG, 
        .end = ordinate.Ordinate.INF,
    };

    pub const ZERO : ContinuousInterval = .{
        .start = ordinate.Ordinate.zero,
        .end = ordinate.Ordinate.zero,
    };

    pub fn init(
        args: ContinuousInterval_BaseType,
    ) ContinuousInterval
    {
        return .{
            .start = ordinate.Ordinate.init(args.start),
            .end = ordinate.Ordinate.init(args.end),
        };
    }

    /// compute the duration of the interval, if either boundary is not finite,
    /// the duration is infinite.
    pub fn duration(
        self: @This(),
    ) ordinate.Ordinate 
    {
        if (self.is_infinite())
        {
            return ordinate.Ordinate.INF;
        }

        return self.end.sub(self.start);
    }

    pub fn from_start_duration(
        start: ordinate.Ordinate,
        in_duration: ordinate.Ordinate,
    ) ContinuousInterval
    {
        if (in_duration.lteq(0))
        {
            @panic("duration <= 0");
        }

        return .{
            .start = start,
            .end = start.add(in_duration),
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
             and self.start.eql(ord)
            )
            or 
            (
             (ord.gteq(self.start))
             and (ord.lt(self.end))
            )
        );
    }

    /// return whether one of the end points of the interval is infinite
    pub fn is_infinite(
        self: @This(),
    ) bool
    {
        return (self.start.is_inf() or self.end.is_inf());
    }

    /// detect if this interval starts and ends at the same ordinate
    pub fn is_instant(
        self: @This(),
    ) bool
    {
        return (ordinate.eql(self.start, self.end));
    }

    /// custom formatter for std.fmt
    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
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

pub const ContinuousInterval_BaseType = struct {
    start : ordinate.Ordinate.BaseType,
    end : ordinate.Ordinate.BaseType,
};

test "ContinuousInterval: is_infinite"
{
    var cti = ContinuousInterval{};

    try std.testing.expectEqual(true, cti.is_infinite());

    cti.end = ordinate.Ordinate.init(2);

    try std.testing.expectEqual(false, cti.is_infinite());

    cti.start = ordinate.Ordinate.INF;

    try std.testing.expectEqual(true, cti.is_infinite());
}

/// return a new interval that spans the duration of both argument intervals
pub fn extend(
    fst: ContinuousInterval,
    snd: ContinuousInterval,
) ContinuousInterval 
{
    return .{
        .start = ordinate.min(fst.start, snd.start),
        .end = ordinate.max(fst.end, snd.end),
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
            .fst = ContinuousInterval.init(.{ .start = 0, .end = 10, }),
            .snd = ContinuousInterval.init(.{ .start = 8, .end = 12, }),
            .res = ContinuousInterval.init(.{ .start = 0, .end = 12, }),
        },
        .{ 
            .fst = ContinuousInterval.init(.{ .start = 0, .end = 10, }),
            .snd = ContinuousInterval.init(.{ .start = -2, .end = 9, }),
            .res = ContinuousInterval.init(.{ .start = -2, .end = 10,}),
        },
        .{ 
            .fst = ContinuousInterval.init(.{ .start = 0, .end = 10,  }),
            .snd = ContinuousInterval.init(.{ .start = -2, .end = 12, }),
            .res = ContinuousInterval.init(.{ .start = -2, .end = 12, }),
        },
        .{ 
            .fst = ContinuousInterval.init(.{ .start = 0, .end = 2,  }),
            .snd = ContinuousInterval.init(.{ .start = 4, .end = 12, }),
            .res = ContinuousInterval.init(.{ .start = 0, .end = 12, }),
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
             and fst.start.gteq(snd.start)
             and fst.start.lt(snd.end)
        ) or (
            snd_is_instant
            and snd.start.gteq(fst.start)
            and snd.start.lt(fst.end)
        ) or (
        // for cases where BOTH intervals are the same point, check if they all
        // match
        //
            fst_is_instant
            and snd_is_instant
            and fst.start.eql(snd.start)
        ) or (
        // general case
         fst.start.lt(snd.end)
         and fst.end.gt(snd.start)
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
            .fst = ContinuousInterval.init(.{ .start = 0, .end = 10, }),
            .snd = ContinuousInterval.init(.{ .start = 8, .end = 12, }),
            .res = true,
        },
        .{ 
            .fst = ContinuousInterval.init(.{ .start = 0, .end = 10, }),
            .snd = ContinuousInterval.init(.{ .start = -2, .end = 9, }),
            .res = true,
        },
        .{ 
            .fst = ContinuousInterval.init(.{ .start = 0, .end = 10, }),
            .snd = ContinuousInterval.init(.{ .start = -2, .end = 12, }),
            .res = true,
        },
        .{ 
            .fst = ContinuousInterval.init(.{ .start = 0, .end = 4, }),
            .snd = ContinuousInterval.init(.{ .start = 5, .end = 12, }),
            .res = false,
        },
        .{ 
            .fst = ContinuousInterval.init(.{ .start = 0, .end = 4, }),
            .snd = ContinuousInterval.init(.{ .start = -2, .end = 0, }),
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
        .start = ordinate.max(fst.start, snd.start),
        .end = ordinate.min(fst.end, snd.end),
    };
}

test "intersection test - contained" {
    const int1 = ContinuousInterval.init(
        .{ .start = 0, .end = 10 },
    );
    const int2 = ContinuousInterval.init(
        .{ .start = 1, .end = 3 }
    );
    const res = intersect(
        int1, 
        int2
    ) orelse ContinuousInterval{};

    try ordinate.expectOrdinateEqual(
        res.start,
        int2.start,
    );
    try ordinate.expectOrdinateEqual(
        res.end,
        int2.end,
    );
}

test "intersection test - infinite" {
    const int1 = ContinuousInterval.inf_neg_to_pos;
    const int2 = ContinuousInterval.init(
        .{ .start = 1, .end = 3 }
    );
    const res = intersect(
        int1,
        int2
    ) orelse ContinuousInterval{};

    try ordinate.expectOrdinateEqual(
        res.start,
        int2.start,
    );
    try ordinate.expectOrdinateEqual(
        res.end,
        int2.end,
    );
}

test "ContinuousInterval Tests" 
{
    const ival = ContinuousInterval.init(
        .{ .start = 10, .end = 20, },
    );

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
    const ival = ContinuousInterval.init(
        .{ .start = 10, .end = 20, },
    );

    try std.testing.expect(!ival.overlaps(ordinate.Ordinate.init(0)));
    try std.testing.expect( ival.overlaps(ordinate.Ordinate.init(10)));
    try std.testing.expect( ival.overlaps(ordinate.Ordinate.init(15)));
    try std.testing.expect(!ival.overlaps(ordinate.Ordinate.init(20)));
    try std.testing.expect(!ival.overlaps(ordinate.Ordinate.init(30)));
}

test "ContinuousInterval: is_instant"
{
    const is_not_point = ContinuousInterval.init(
        .{ .start = 0, .end = 0.1, }
    );

    try std.testing.expect(is_not_point.is_instant() != true);

    const collapsed = ContinuousInterval.init(
        .{ .start = 10, .end = 10, }
    );

    try std.testing.expect(collapsed.is_instant());
}
