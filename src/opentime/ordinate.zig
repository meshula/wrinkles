const std = @import("std"); 

const util = @import("util.zig"); 

const EPSILON_ORD = Ordinate{ .f32 = util.EPSILON };

pub const Rational = struct {
    numerator: i32,
    denominator: i32,
};

pub const OrdinateKinds = enum {
    f32,
    rational,
};

pub const Ordinate = union(OrdinateKinds) {
    f32: f32,
    rational: Rational,

    pub fn init(v: anytype) Ordinate {
        return switch (@TypeOf(v)) {
            f32 => .{ .f32 = v },
            Rational => .{ .rational = v },
            else => unreachable
        };
    }

    // math
    // @{
    pub fn add(self: @This(), other: Ordinate) Ordinate {
       return Ordinate{ .f32 = self.to_f32() + other.to_f32()};
    }
    pub fn addWithOverflow(
        self: @This(),
        other: Ordinate,
        result: *Ordinate
    ) bool 
    {
        return @addWithOverflow(f32, self.to_f32(), other.to_f32(), result);
    }
    pub fn sub(self: @This(), other: Ordinate) Ordinate {
        return Ordinate{ .f32 = self.to_f32() - other.to_f32() };
    }
    pub fn subWithOverflow(
        self: @This(),
        other: Ordinate,
        result: *Ordinate
    ) bool 
    {
        return @subWithOverflow(f32, self.to_f32(), other.to_f32(), result);
    }
    pub fn mul(self: @This(), other: Ordinate) Ordinate {
        return Ordinate{ .f32 = self.to_f32() * other.to_f32()};
    }
    pub fn mulWithOverflow(
        self: @This(),
        other: Ordinate,
        result: *Ordinate
    ) bool 
    {
        return @mulWithOverflow(f32, self.to_f32(), other.to_f32(), result);
    }

    // float div
    pub fn div(self: @This(), other: Ordinate) Ordinate {
        return .{ .f32 = self.to_f32() / other.to_f32() };
    }

    // integer divs
    pub fn divExact(self: @This(), other: Ordinate) Ordinate {
        return .{ .f32 = @divExact(self.to_f32(),other.to_f32()) };
    }
    pub fn divFloor(self: @This(), other: Ordinate) Ordinate {
        return .{ .f32 = @divFloor(self.to_f32(),other.to_f32()) };
    }
    pub fn divTrunc(self: @This(), other: Ordinate) Ordinate {
        return .{ .f32 = @divTrunc(self.to_f32(),other.to_f32()) };
    }

    // @}

    pub fn to_float(self: @This(), comptime T: type) T {
        return switch (self) {
            .f32 => |f| @floatCast(T, f),
            .rational => |r| (
                @intToFloat(T, r.numerator) 
                / @intToFloat(T, r.denominator)
            ),
        };
    }

    pub fn to_f32(self: @This()) f32 {
        return self.to_float(f32);
    }

    pub fn lessthan(self: @This(), other: Ordinate) bool {
        return (self.to_f32() < other.to_f32());
    }

    pub fn equal_approx(
        self: @This(),
        other: Ordinate,
        tolerance: Ordinate
    ) bool 
    {
        // @TODO: check types and preserver the rational
        return std.math.approxEqAbs(
            f32,
            self.to_f32(),
            other.to_f32(),
            tolerance.to_f32()
        );
    }
};

test "init" {
    // @f32
    {
        const o = Ordinate.init( @as(f32, 3) );

        try std.testing.expectEqual(@as(f32, 3), o.to_f32());
        try std.testing.expectEqual(@as(f64, 3), o.to_float(f64));
    }

    // @rational
    {
        const r = Ordinate.init(Rational{ .numerator = 12, .denominator = 24 });

        try std.testing.expectEqual(@as(f32, 0.5), r.to_f32());
        try std.testing.expectEqual(@as(f64, 0.5), r.to_float(f64));
    }
}

test "to_float" {
    const o = Ordinate{ .f32 = 3 };

    try std.testing.expectEqual(@as(f32, 3), o.to_f32());
    try std.testing.expectEqual(@as(f64, 3), o.to_float(f64));

    const r = Ordinate{ .rational = .{ .numerator = 12, .denominator = 24 } };
    const f = Ordinate{ .f32 = 0.5 };

    try std.testing.expect(r.equal_approx(f, EPSILON_ORD));

    try std.testing.expectEqual(@as(f32, 0.5), r.to_f32());
    try std.testing.expectEqual(@as(f64, 0.5), r.to_float(f64));

    const o_plus_r = o.add(r);
    try std.testing.expectEqual(@as(f32, 3.5), o_plus_r.to_f32());

    const o_sub_r = o.sub(r);
    try std.testing.expectEqual(@as(f32, 2.5), o_sub_r.to_f32());

    const o_mul_r = o.mul(r);
    try std.testing.expectEqual(@as(f32, 1.5), o_mul_r.to_f32());

    {
        const o_divExact_r = o.divExact(r);
        try std.testing.expectEqual(@as(f32, 6), o_divExact_r.to_f32());

        const start = Ordinate{ .rational = .{ .numerator = 10, .denominator = 24 } };
        const end   = Ordinate{ .rational = .{ .numerator = 20, .denominator = 24 } };
        const mid = start.add(end).div(.{ .f32 = 2 });

        try std.testing.expectApproxEqAbs(mid.to_f32(), mid.to_f32(), util.EPSILON);
    }
 
}
