const std = @import("std"); 
const util = @import("util.zig"); 

const expectEqual = std.testing.expectEqual;
const expect = std.testing.expect;

// Intervals and Points @{
// ////////////////////////////////////////////////////////////////////////////

// right open interval on the time continuum
// the default CTI splits the timeline at the origin
pub const ContinuousTimeInterval = struct {
    /// the start time of the interval in seconds, inclusive
    start_seconds: f32 = 0,

    /// the end time of the interval in seconds, exclusive
    end_seconds: f32 = util.inf,

    // compute the duration of the interval, if either boundary is not finite,
    // the duration is infinite.
    pub fn duration_seconds(self: @This()) f32 
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
        start_seconds: f32,
        in_duration_seconds: f32
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

    pub fn overlaps_seconds(self: @This(), t_seconds: f32) bool {
        return (
            (t_seconds >= self.start_seconds)
            and (t_seconds < self.end_seconds)
        );
    }
};

/// return a new interval that spans the duration of both argument intervals
pub fn extend(
    fst: ContinuousTimeInterval,
    snd: ContinuousTimeInterval
) ContinuousTimeInterval {
    return .{
        .start_seconds = @min(fst.start_seconds, snd.start_seconds),
        .end_seconds = @max(fst.end_seconds, snd.end_seconds),
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
        .start_seconds = @min(fst.start_seconds, snd.start_seconds),
        .end_seconds = @max(fst.end_seconds, snd.end_seconds),
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
        .start_seconds = @max(fst.start_seconds, snd.start_seconds),
        .end_seconds = @min(fst.end_seconds, snd.end_seconds),
    };
}

test "intersection test" {
    {
        const int1 = ContinuousTimeInterval{.start_seconds = 0, .end_seconds = 10};
        const int2 = ContinuousTimeInterval{.start_seconds = 1, .end_seconds = 3};
        const res = intersect(int1, int2) orelse ContinuousTimeInterval{};

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

    {
        const int1 = INF_CTI;
        const int2 = ContinuousTimeInterval{.start_seconds = 1, .end_seconds = 3};
        const res = intersect(int1, int2) orelse ContinuousTimeInterval{};

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

    {
        const int1 = INF_CTI;
        const int2 = ContinuousTimeInterval{.start_seconds = 1, .end_seconds = 3};
        const res = intersect(int2, int1) orelse ContinuousTimeInterval{};

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
}

pub const INF_CTI: ContinuousTimeInterval = .{
    .start_seconds = -util.inf, 
    .end_seconds = util.inf
};

test "ContinuousTimeInterval Tests" {
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

test "ContinuousTimeInterval: Overlap tests" {
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
// @}
