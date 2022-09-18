#include "cvector.h"
#include <math.h>
#include <stdbool.h>
#include <stdint.h>


/*
 * ot_r32_t
 *
 * a 32 bit signed rational number
 *
 * A denominator of zero indicates infinity
 */

typedef struct {
    int32_t num;
    uint32_t den;
} ot_r32_t;

/// @TODO replace all raten, rated with ot_r32_t

typedef struct {
    int64_t start; // start count of rate units
    float frac;    // fraction [0, 1) between start and start + rate
    float kcenter; // sampling kernel center relative to the start count
    int64_t raten; // rate in seconds; numerator
    int64_t rated; // rate in seconds; denominator
} ot_frame_t;

typedef struct {
    ot_frame_t start; // start of interval
    int64_t end;   // end count of rate units
    float frace;   // normalized fraction of end within the end interval
} ot_interval_t;

typedef enum {
    ot_op_affine_transform
} ot_operator_tag;

typedef struct {
    int64_t start;
    float frac;
    uint64_t raten, rated;
} ot_sample_t;

typedef struct {
    ot_operator_tag tag;
    union {
        struct {
            // affine transform as slope + offset
            int64_t slopen, sloped;
            ot_frame_t offset;
        };
    };
} ot_operator_t;



// Stein's algorithm

uint32_t gcd32(uint32_t u, uint32_t v) 
{
    uint32_t shl = 0;
    if (u == 0) return v;
    if (v == 0) return u;
    if (u == v) return u;

    while ((u != 0) && (v != 0) && (u != v)) {
        bool eu = (u&1) == 0;
        bool ev = (v&1) == 0;
        if (eu && ev) {
            shl += 1;
            v >>= 1;
            u >>= 1;
        }
        else if (eu && !ev) { u >>= 1; }
        else if (!eu && ev) { v >>= 1; }
        else if (u > v)     { u = (u - v) >> 1; }
        else {
            uint32_t temp = u;
            u = (v - u ) >> 1;
            v = temp;
        }
    }
    if (u == 0) return v << shl;
    return u << shl;
}

int32_t lcm32(int32_t u_, int32_t v_) 
{
    // 
    int32_t u = u_;
    int32_t v = v_;
    if (v < 0) {
        u = -u;
        v = -v;
    }
    int32_t sgn = (u < 0) ? -1 : 1;
    uint64_t uu = (u < 0) ? -u : u;
    uint64_t vu = v;
    uint64_t div = (uu * vu) / gcd32(uu, vu);
    return sgn * (int32_t) div;
}

uint32_t lcm32u(uint32_t u, uint32_t v) 
{
    uint64_t uu = u;
    uint64_t vu = v;
    return (uint32_t)( (uu * vu) / gcd32(u, v));
}

int32_t ot_r32_sign(ot_r32_t r)
{
    return r.num > 0 ? 1 : -1;
}

ot_r32_t ot_r32_abs(ot_r32_t r)
{
    return (ot_r32_t) { r.num > 0 ? r.num : -r.num, r.den };
}

ot_r32_t ot_r32_create(int32_t n_, int32_t d_)
{
    if (d_ == 0 || n_ == 0)
        return (ot_r32_t) { n_, d_ };
    int32_t n = n_;
    int32_t d = d_;
    if (d_ < 0) {
        n = -n;
        d = -d;
    }
    int32_t sign = (n < 0) ? -1 : 1;
    uint32_t nu = (n < 0) ? -n : n;
    uint32_t du = d;
    uint32_t div = gcd32(nu, du);
    return (ot_r32_t) { 
        sign * (int32_t) (nu / div), du / div };
}

bool ot_r32_is_inf(ot_r32_t r)
{
    return r.den == 0;
}

ot_r32_t ot_r32_normalize(ot_r32_t r)
{
    if (r.num == 0 || r.num == 1 || r.den == 1 || r.den == 0) 
        return r;
    uint32_t n = r.num < 0 ? -r.num : r.num;
    uint32_t denom = gcd32(n, r.den);
    int32_t sign = r.num < 0 ? -1 : 1;
    return (ot_r32_t) { 
        r.num / denom, r.den / denom };
}

ot_r32_t ot_r32_force_den(ot_r32_t r, uint32_t den)
{
    return (ot_r32_t) {
        (r.num * den) / r.den };
}

ot_r32_t ot_r32_add(ot_r32_t lh, ot_r32_t rh)
{
    uint32_t g = gcd32(lh.den, rh.den);
    uint32_t den = lh.den / g;
    uint32_t num = lh.num * (rh.den / g) + rh.num * den;
    g = gcd32(num, g);
    return (ot_r32_t) { num / g, den * rh.den / g };
}

ot_r32_t ot_r32_negate(ot_r32_t r)
{
    return (ot_r32_t) { -r.num, r.den };
}

ot_r32_t ot_r32_sub(ot_r32_t lh, ot_r32_t rh)
{
    return ot_r32_add(lh, ot_r32_negate(rh));
}

ot_r32_t ot_r32_mul(ot_r32_t lh, ot_r32_t rh)
{
    int32_t sign = ot_r32_sign(lh) * ot_r32_sign(rh);
    ot_r32_t lhu = ot_r32_abs(lh);
    ot_r32_t rhu = ot_r32_abs(rh);
    uint32_t g1 = gcd32(lhu.num, lhu.den);
    uint32_t g2 = gcd32(rhu.num, rhu.den);
    return ot_r32_normalize( (ot_r32_t) {
        sign * ((lhu.num / g1) * rhu.num) / g2,
               ((lhu.den / g2) * rhu.den) / g1 });
}

ot_r32_t ot_r32_inverse(ot_r32_t r)
{
    return (ot_r32_t) { r.den, r.num };
}

ot_r32_t ot_r32_div(ot_r32_t lh, ot_r32_t rh)
{
    return ot_r32_mul(lh, ot_r32_inverse(rh));
}

bool ot_r32_equal(ot_r32_t lh, ot_r32_t rh)
{
    ot_r32_t a = ot_r32_normalize(lh);
    ot_r32_t b = ot_r32_normalize(rh);
    return a.num == b.num && a.den == b.den;
}

// reference:
// operator < in https://www.boost.org/doc/libs/1_55_0/boost/rational.hpp
bool ot_r32_less_than(ot_r32_t lh, ot_r32_t rh)
{
    if (lh.den < 0 || rh.den < 0)
        return false;   // not comparable

    int32_t n_l = lh.num;
    int32_t d_l = lh.den;
    int32_t q_l = n_l / d_l;
    int32_t r_l = n_l % d_l;
    int32_t n_r = rh.num;
    int32_t d_r = rh.den;
    int32_t q_r = n_r / d_r;
    int32_t r_r = n_r % d_r;
    
    // normalize non-negative moduli
    while (r_l < 0) { r_l += d_l; --q_l; }
    while (r_r < 0) { r_r += d_r; --q_r; }

    uint8_t reversed = 0;
    // compare continued fraction components
    while (true) {
        // quotients of the current cycle are continued-fraction components.
        // comparing these is comparing their sequences, stop at the first
        // difference
        if (q_l != q_r) {
            return reversed? q_l > q_r : q_l < q_r;
        }

        reversed ^= 1;
        if (r_l == 0 || r_r == 0) {
            // expansion has ended
            break;
        }

        n_l = d_l; d_l = r_l;
        q_l = n_l / d_l;
        r_l = n_l % d_l;

        n_r = d_r; d_r = r_r;
        q_r = n_r / d_r;
        r_r = n_r % d_r;
    }

    if (r_l == r_r) {
        // previous loop broke on zero remainder; both zeroes means
        // the sequence is over and the values are equal.
        return false;
    }

    // one of the remainders is zero, so the other value is lesser
    return (r_r != 0) != (reversed == 1);
}

bool ot_r32_less_than_int(ot_r32_t r32, int i)
{
    if (r32.den <= 0)
        return false;   // not comparable

    int32_t q = r32.num / r32.den;
    int32_t r = r32.num % r32.den;
    while (r < 0)  { r += r32.den; --q; }
    
    // remainder pushed the quotient down, so it's only necessary to
    // compare the quotient.
    return q < i;
}

int32_t ot_r32_floor(ot_r32_t a)
{
    return a.num / a.den;
}

ot_sample_t ot_sample_at_seconds(double t, uint64_t raten, uint64_t rated) {
    ot_sample_t result;
    result.raten = raten;
    result.rated = rated;
    double t_rate = t * (double) rated / (double) raten;
    double int_part;
    result.frac = (float) modf(t_rate, &int_part);
    result.start = (int64_t) int_part;
    return result;
}

ot_sample_t ot_sample_invalid() {
    return (ot_sample_t) { 0, 0, 0, 0 };
}

bool ot_sample_is_valid(const ot_sample_t* t) {
    return t != NULL && t->rated != 0;
}

bool ot_frame_is_valid(const ot_frame_t* f) {
    return f != NULL & f->rated != 0;
}

ot_sample_t ot_sample_normalize(const ot_sample_t* t) {
    /// @TODO actually normalize. Need to drop the gcd library in here
    return *t;
}

ot_frame_t ot_frame_normalize(const ot_frame_t* f) {
    /// @TODO actually normalize. Need to drop the gcd library in here
    return *f;
}

bool ot_sample_rates_equivalent(const ot_sample_t* t1, const ot_sample_t* t2) {
    if (!t1 || !t2) {
        return false;
    }
    ot_sample_t t1n = ot_sample_normalize(t1);
    ot_sample_t t2n = ot_sample_normalize(t2);
    return t1n.raten == t2n.raten && t1n.rated == t2n.rated;
}

bool ot_sample_frame_rates_equivalent(const ot_sample_t* t, const ot_frame_t* f) {
    if (!t || !f) {
        return false;
    }
    ot_sample_t tn = ot_sample_normalize(t);
    ot_frame_t fn = ot_frame_normalize(f);
    return tn.raten == fn.raten && tn.rated == fn.rated;
}

ot_frame_t ot_frame_inv(const ot_frame_t* f) {
    ot_frame_t result = *f;
    result.start *= -1;
    result.frac = 1.f - result.frac;
    return result;
}

ot_sample_t ot_sample_add_frame(const ot_sample_t* t, const ot_frame_t* f) {
    if (!ot_sample_is_valid(t) || !ot_frame_is_valid(f)) {
        return ot_sample_invalid();
    }
    if (ot_sample_frame_rates_equivalent(t, f)) {
        ot_sample_t result = *t;
        result.start += f->start;
        result.frac += f->frac;
        return ot_sample_normalize(&result);
    }
    /// @TODO do rate conversion
    return ot_sample_invalid();
}

ot_sample_t ot_project(ot_sample_t* t, ot_operator_t* op) {
    if (!ot_sample_is_valid(t) || !op) {
        return ot_sample_invalid();
    }
    if (op->tag == ot_op_affine_transform) {
        if (ot_sample_frame_rates_equivalent(t, &op->offset)) {
            ot_sample_t result = *t;
            ot_frame_t offset = ot_frame_inv(&op->offset);
            result = ot_sample_add_frame(&result, &offset);
            result.start = result.start * op->sloped / op->slopen;
            return ot_sample_normalize(&result);
        }
        /// @TODO handle different rates
        return ot_sample_invalid();
    }
    return ot_sample_invalid();
}

//struct ot_topo_node_t;
//typedef void ot_operator_t(struct ot_topo_node_t* to, struct ot_topo_node_t* from);

void test_ot() {
    // first, a presentation timeline 1000 frames long at 24
    // and a movie, also 1000 frames long at 24
    ot_interval_t pres_tl = (ot_interval_t) {
        { 0, 0.f, 0.f, 1, 24 }, 1000, 0.f };
    ot_interval_t mov_1000 = (ot_interval_t) {
        { 0, 0.f, 0.f, 1, 24 }, 1000, 0.f };

    ot_operator_t op_identity_24;
    op_identity_24.tag = ot_op_affine_transform;
    op_identity_24.slopen = 1;
    op_identity_24.sloped = 1;
    op_identity_24.offset = (ot_frame_t) { 0, 0.f, 0.f, 1, 24 };

    // at 0.5 seconds, which frame of mov_1000 is showing on pres_tl?
    ot_sample_t sample_0_5 = ot_sample_at_seconds(0.5, 1, 24);
    ot_sample_t mov_sample_0_5 = ot_project(&sample_0_5, &op_identity_24);
};

