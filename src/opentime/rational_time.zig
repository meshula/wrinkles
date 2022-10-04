const std = @import("std");
const print = std.debug.print;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const absCast = std.math.absCast;

// a straightforward binary gcd, modeled after
// gist.github.com/cslarsen/binary_gcd.cpp, which is assigned to public domain

export fn gcd(u_: i32, v_: i32) u32 {
    var shl:u5 = 0;
    var u:u32 = absCast(u_);
    var v:u32 = absCast(v_);
    if (u == 0) return @intCast(u32, v);
    if (v == 0) return @intCast(u32, u);
    if (u == v) return @intCast(u32, u);

    while (u != 0 and v != 0 and u != v) {
        var eu: bool = (u & 1) == 0;
        var ev: bool = (v & 1) == 0;
        if (eu and ev) {
            shl += 1;
            u >>= 1;
            v >>= 1;
        }
        else if (eu and !ev) { u >>= 1; }
        else if (!eu and ev) { v >>= 1; }
        else if (u > v)      { u = (u-v) >> 1; }
        else {
            const tmp: u32 = u;
            u = (v-u) >> 1;
            v = tmp;
        }
    }
    if (u == 0) return v << shl;
    return u << shl;
}

pub fn lcm(u_: i32, v_: i32) i32 {
    var tst: i64 = u_ * v_;
    var sgn: i32 = if (tst < 0) -1 else 1;
    var u: u32 = absCast(u_);
    var v: u32 = absCast(v_);
    var div: u32 = @divExact(u, gcd(u_, v_));
    return @intCast(i32, div * v) * sgn;
}

// @TODO: add type free version
const rats32 = struct {
    n: i32,
    d: u32
};

fn create_rational(n_: i32, d_: i32) rats32 {
    if (d_ == 0) unreachable;
    var tst: i64 = n_ * d_;
    var sgn :i32 = if (tst < 0) -1 else 1;
    var n: u32 = absCast(n_);
    var d: u32 = absCast(d_);
    var div: u32 = if (n != 0) gcd(n_,d_) else 1;
    var ret = rats32 {
        .n = sgn * @intCast(i32, @divExact(n, div)),
        .d = @divExact(d, div)
    };
    return ret;
}

fn rats32_normalize(r: rats32) rats32 {
    if (r.numerator == 0) {
        return rats32 { .n = 0, .d = 1 };
    }
    var denom = gcd(r.n, r.d);
    return rats32 { .n = r.n / d, .d = r.d / d };
}

fn rats32_add(lh: rats32, rh: rats32) rats32 {
    var denom: i32 = lcm(lh.d, rh.d);
    var result = rats32 {
        .n = @divExact(denom, lh.d) * l.n + @divExact(denom, rh.d) * rh.n,
        .d = denom
    };
    return rats32_normalize(result);
}

fn rats32_neg(r: rats32) rats32 {
    return rats32 { .n = -r.n, .d = r.d };
}

fn rats32_sub(lh: rats32, rh: rats32) rats32 {
    return rats32_add(lh, rats32_neg(rh));
}

fn rats32_mul(lh: rats32, rh: rats32) rats32 {
    var g1: i32 = gcd(lh.n, rh.d);
    var g2: i32 = gcd(rh.n, lh.d);
    return rats32 {
        // lh.n/g1 * rh.n/g2 arranged to not lose bits
        .n = @divExact(@divExact(lh.n, g1) * rh.n, g2),
        // lh.d/g2 * rh.d/g1 arranged to not lose bits
        .d = @divExact(@divExact(lh.d, g2) * rh.d, g1)
    };
}

fn rats32_inv(r: rats32) rats32 {
    return rats32 {
        .n = r.d, .d = r.n
    };
}

fn rats32_div(lh: rats32, rh: rats32) rats32 {
    return rats32_mul(lh, rats32_inv(rh));
}

test "gcd" {
    try expectEqual(gcd(120, 16), 8);
    try expectEqual(gcd(120, -16), 8);
    try expectEqual(gcd(38400, 12000), 2400);
    try expectEqual(gcd(11,7), 1);
}

test "lcm" {
    try expectEqual(lcm(8,2), 8);
    try expectEqual(lcm(11,7), 77);
    try expectEqual(lcm(24,16), 48);
}

test "rational creation" {
    var a = create_rational(32,4);
    try expectEqual(a.n, 8); 
    try expectEqual(a.d, 1);

    a = create_rational(-1,99);
    try expectEqual(a.n, -1);
    try expectEqual(a.d, 99);

    a = create_rational(1, -99);
    try expectEqual(a.n, -1);
    try expectEqual(a.d, 99);

    a = create_rational(-11, -7);
    try expectEqual(a.n, 11);
    try expectEqual(a.d, 7);

    a = create_rational(38400, 24);
    try expectEqual(a.n, 1600);
    try expectEqual(a.d, 1);
}

test "exploring integer casting" {
    try std.testing.expectEqual(
        std.math.absCast(@as(i32, -16)),
        @as(u32, 16)
    );

    try std.testing.expectEqual(
        std.math.lossyCast(u2, @as(i32, 16)), 3
    );

    try std.testing.expectEqual(
        std.math.lossyCast(i2, @as(i32, 16)), 1
    );
}
