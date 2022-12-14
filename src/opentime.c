#include "opentime.h"
#include "cvector.h"
#include <math.h>


//-----------------------------------------------------------------------------
// Stein's algorithm

uint32_t ot_gcd32(uint32_t u, uint32_t v) {
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

int32_t ot_lcm32(int32_t u_, int32_t v_) {
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
    uint64_t div = (uu * vu) / ot_gcd32(uu, vu);
    return sgn * (int32_t) div;
}

uint32_t ot_lcm32u(uint32_t u, uint32_t v) {
    uint64_t uu = u;
    uint64_t vu = v;
    return (uint32_t)( (uu * vu) / ot_gcd32(u, v));
}

ot_r32_t ot_r32_abs(ot_r32_t r) {
    return (ot_r32_t) { r.num > 0 ? r.num : -r.num, r.den };
}

ot_r32_t ot_r32_add(ot_r32_t lh, ot_r32_t rh) {
    uint32_t g = ot_gcd32(lh.den, rh.den);
    uint32_t den = lh.den / g;
    uint32_t num = lh.num * (rh.den / g) + rh.num * den;
    g = ot_gcd32(num, g);
    return (ot_r32_t) { num / g, den * rh.den / g };
}

ot_r32_t ot_r32_create(int32_t n_, int32_t d_) {
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
    uint32_t div = ot_gcd32(nu, du);
    return (ot_r32_t) { 
        sign * (int32_t) (nu / div), du / div };
}

ot_r32_t ot_r32_div(ot_r32_t lh, ot_r32_t rh) {
    return ot_r32_mul(lh, ot_r32_inverse(rh));
}

bool ot_r32_equal(ot_r32_t lh, ot_r32_t rh) {
    return lh.num == rh.num && lh.den == rh.den;
}

bool ot_r32_equivalent(ot_r32_t lh, ot_r32_t rh) {
    ot_r32_t a = ot_r32_normalize(lh);
    ot_r32_t b = ot_r32_normalize(rh);
    return a.num == b.num && a.den == b.den;
}

int32_t ot_r32_floor(ot_r32_t a) {
    return a.num / a.den;
}

ot_r32_t ot_r32_force_den(ot_r32_t r, uint32_t den) {
    return (ot_r32_t) {
        (r.num * den) / r.den };
}

bool ot_r32_is_inf(ot_r32_t r) {
    return r.num != 0 && r.den == 0;
}

bool ot_r32_is_nan(ot_r32_t r) {
    return r.num == 0 && r.den == 0;
}

ot_r32_t ot_r32_inverse(ot_r32_t r) {
    return (ot_r32_t) { r.den, r.num };
}

// reference:
// operator < in https://www.boost.org/doc/libs/1_55_0/boost/rational.hpp
bool ot_r32_less_than(ot_r32_t lh, ot_r32_t rh) {
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

        n_l = d_l; 
        d_l = r_l;
        q_l = n_l / d_l;
        r_l = n_l % d_l;

        n_r = d_r; 
        d_r = r_r;
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

bool ot_r32_less_than_int(ot_r32_t r32, int i) {
    if (r32.den <= 0)
        return false;   // not comparable

    int32_t q = r32.num / r32.den;
    int32_t r = r32.num % r32.den;
    while (r < 0)  { r += r32.den; --q; }
    
    // remainder pushed the quotient down, so it's only necessary to
    // compare the quotient.
    return q < i;
}

ot_r32_t ot_r32_mul(ot_r32_t lh, ot_r32_t rh) {
    int32_t sign = ot_r32_sign(lh) * ot_r32_sign(rh);
    ot_r32_t lhu = ot_r32_abs(lh);
    ot_r32_t rhu = ot_r32_abs(rh);
    uint32_t g1 = ot_gcd32(lhu.num, lhu.den);
    uint32_t g2 = ot_gcd32(rhu.num, rhu.den);
    return ot_r32_normalize( (ot_r32_t) {
        sign * ((lhu.num / g1) * rhu.num) / g2,
               ((lhu.den / g2) * rhu.den) / g1 });
}

ot_r32_t ot_r32_negate(ot_r32_t r) {
    return (ot_r32_t) { -r.num, r.den };
}

ot_r32_t ot_r32_normalize(ot_r32_t r) {
    if (r.num == 0 || r.num == 1 || r.den == 1 || r.den == 0) 
        return r;
    uint32_t n = r.num < 0 ? -r.num : r.num;
    uint32_t gcd = ot_gcd32(n, r.den);
    int32_t sign = r.num < 0 ? -1 : 1;
    return (ot_r32_t) { r.num / gcd, r.den / gcd };
}

int32_t ot_r32_sign(ot_r32_t r) {
    return r.num > 0 ? 1 : -1;
}

ot_r32_t ot_r32_sub(ot_r32_t lh, ot_r32_t rh) {
    return ot_r32_add(lh, ot_r32_negate(rh));
}

//-----------------------------------------------------------------------------

ot_interval_t ot_interval_conform(const ot_interval_t *i, ot_r32_t rate) {
    if (!ot_interval_is_valid(i)) {
        return ot_invalid_interval();
    }

    if (ot_r32_equal(i->rate, rate)) {
        return *i;
    }
    if (ot_r32_equivalent(i->rate, rate)) {
        ot_interval_t result = *i;
        result.rate = rate;
        return result;
    }

    double t1 = ot_interval_start_as_seconds(i);
    double t2 = ot_interval_end_as_seconds(i);
    return ot_interval_at_seconds2(t1, t2, rate);
}

ot_interval_t ot_interval_at_seconds2(double t1, double t2, ot_r32_t rate) {
    if (ot_r32_is_inf(rate)) {
        return (ot_interval_t) { t1 >= 0? 1: -1, 0, 0, 0, 1, 0 }; // infinity
    }
    if (ot_r32_is_nan(rate)) {
        return (ot_interval_t) { t1 >= 0? 1: -1, 0, 0, 0, 0, 0 }; // NAN
    }
    if (isnan(t1) || isnan(t2)) {
        // construct a signed NAN
        return (ot_interval_t) { copysign(1.0, t1) > 0? 1: -1, 0, 0, 0, 0, 0 };
    }
    if (isinf(t1) || isinf(t2)) {
        // construct a signed INFINITY
        return (ot_interval_t) { copysign(1.0, t1) > 0? 1: -1, 0, 0, 0, 1, 0 };
    }

    ot_interval_t result;
    result.rate = rate;
    double t_rate = t1 * (double) rate.den / (double) rate.num;
    double int_part = floor(t_rate);
    result.start_frac = t_rate - int_part;
    result.start = (int64_t) int_part;

    t_rate = t2 * (double) rate.den / (double) rate.num;
    int_part = floor(t_rate);
    result.end_frac = t_rate - int_part;
    result.end = (int64_t) int_part;
    return result;
}

ot_interval_t ot_interval_at_seconds(double t, ot_r32_t rate) {
    if (ot_r32_is_inf(rate)) {
        return (ot_interval_t) { t >= 0? 1: -1, 0, 0, 0, 1, 0 }; // infinity
    }
    if (ot_r32_is_nan(rate)) {
        return (ot_interval_t) { t >= 0? 1: -1, 0, 0, 0, 0, 0 }; // NAN
    }
    if (isnan(t)) {
        // construct a signed NAN
        return (ot_interval_t) { copysign(1.0, t) > 0? 1: -1, 0, 0, 0, 0, 0 };
    }
    if (isinf(t)) {
        // construct a signed INFINITY
        return (ot_interval_t) { copysign(1.0, t) > 0? 1: -1, 0, 0, 0, 1, 0 };
    }

    ot_interval_t result;
    result.rate = rate;
    double t_rate = t * (double) rate.den / (double) rate.num;
    double int_part = floor(t_rate);
    result.start_frac = t_rate - int_part;
    result.start = (int64_t) int_part;
    result.end = result.start + 1;
    result.end_frac = result.start_frac;
    return result;
}

double ot_interval_start_as_seconds(const ot_interval_t* t) {
    if (!t) {
        return NAN;
    }
    if (ot_r32_is_inf(t->rate)) {
        return t->start < 0? -INFINITY : INFINITY;
    }
    if (ot_r32_is_nan(t->rate)) {
        return t->start < 0? -NAN : NAN;
    }
    if (!ot_interval_is_valid(t)) {
        return NAN;
    }

    double ret = ((double) t->start + t->start_frac) 
                    * (double) t->rate.num / (double) t->rate.den;
    return ret;
}

double ot_interval_end_as_seconds(const ot_interval_t* t) {
    if (!ot_interval_is_valid(t)) {
        return NAN;
    }
    return (double) t->end * (double) t->rate.num / (double) t->rate.den
               + t->end_frac;
}

ot_interval_t ot_invalid_interval() {
    return (ot_interval_t) { 0, 0, 0, 0, 0, 0 };
}

bool ot_interval_is_equal(const ot_interval_t* t1, const ot_interval_t * t2) {
    if (!t1 || !t2) {
        return false;
    }
    return (t1->start == t2->start && t1->end == t2->end &&
            t1->start_frac == t2->start_frac && t1->end_frac == t2->end_frac &&
            ot_r32_equal(t1->rate, t2->rate));
}

bool ot_interval_is_equivalent(const ot_interval_t* t1, const ot_interval_t * t2) {
    if (!t1 || !t2) {
        return false;
    }
    /// @TODO the exact math thing to do would be to find the lcm of t1 and t2's
    /// rate, conform the intervals to that rate (adjusting fractions as 
    /// necessary), then call interval_is_equal on the conformed intervals.
    /// I haven't written ot_interval_conform(t1, rate) yet
    /// @TODO needs thought - should rate be equivalent, or are we only 
    /// measuring bounds? If bounds and bounds + rate are both interesting
    /// make two different functions
    return ot_interval_start_as_seconds(t1) == ot_interval_start_as_seconds(t2) &&
           ot_interval_end_as_seconds(t1) == ot_interval_end_as_seconds(t2);
}


bool ot_interval_is_valid(const ot_interval_t* t) {
    if ((t == NULL) || (t->rate.den == 0) || (t->end < t->start)) {
        return false;
    }
    if ((t->start == t->end) && (t->start_frac >= t->end_frac)) {
        return false;
    }
    return true;
}

ot_interval_t ot_interval_normalize(const ot_interval_t* t) {
    if (!t || !t->rate.den) {
        return ot_invalid_interval();
    }

    ot_interval_t result = *t;
    result.rate = ot_r32_normalize(t->rate);
    while (result.start_frac < 0.f) {
        result.start_frac += 1.f;
        result.start -= 1;
    }
    while (result.start_frac >= 1.f) {
        result.start_frac -= 1.f;
        result.start += 1;
    }
     while (result.end_frac < 0.f) {
        result.end_frac += 1.f;
        result.end -= 1;
    }
    while (result.end_frac >= 1.f) {
        result.end_frac -= 1.f;
        result.end += 1;
    }
    return result;
}

ot_interval_t ot_interval_additive_inverse(const ot_interval_t* f) {
    ot_interval_t result = *f;
    result.start *= -1;
    result.start_frac *= -1.f;
    result.end *= -1;
    result.end_frac *= 1.f;
    return ot_interval_normalize(&result);
}

// the result will have the same rate as t.
ot_interval_t ot_interval_add(const ot_interval_t* t, const ot_interval_t* addend) {
    // since addend may not be an increasing interval, only test the rate for validity
    if (!ot_interval_is_valid(t) || !addend || !addend->rate.den) {
        return ot_invalid_interval();
    }
    ot_interval_t result = *t;
    ot_interval_t an = ot_interval_conform(addend, result.rate);
    result.start += an.start;
    result.start_frac += an.start_frac;
    result.end += an.end;
    result.end_frac += an.end_frac;
    return ot_interval_normalize(&result);
}

ot_interval_t ot_project(ot_interval_t* t, ot_operator_t* op) {
    if (!ot_interval_is_valid(t) || !op) {
        return ot_invalid_interval();
    }
    if (op->tag == ot_op_affine_transform) {
        if (ot_r32_equivalent(t->rate, op->offset_rate)) {
            ot_interval_t result = *t;
            result.start -= op->offset;
            result.end -= op->offset;
            result.start_frac -= op->offset_frac;
            result.end_frac -= op->offset_frac;
            result.start *= op->slope.num;
            result.start /= op->slope.den;
            result.end *= op->slope.num;
            result.end *= op->slope.den;
            return ot_interval_normalize(&result);
        }
        /// @TODO handle different rates
        return ot_invalid_interval();
    }
    return ot_invalid_interval();
}

//struct ot_topo_node_t;
//typedef void ot_operator_t(struct ot_topo_node_t* to, struct ot_topo_node_t* from);


//-----------------------------------------------------------------------------
// tests
//
#include "munit.h"
#include <stdio.h>

MunitResult interval_equality_test(const MunitParameter params[], 
                            void* user_data_or_fixture) {
    ot_interval_t i1 = ot_interval_at_seconds(0.5, (ot_r32_t) { 1, 12 });
    munit_assert_int(i1.start, ==, 6);
    ot_interval_t i2 = i1;
    munit_assert_int(i1.start, ==, i2.start);
    munit_assert_int(i1.end, ==, i2.end);
    munit_assert_float(i1.start_frac, ==, i2.start_frac);
    munit_assert_float(i1.end_frac, ==, i2.end_frac);
    munit_assert_int(i1.rate.num, ==, i2.rate.num);
    munit_assert_int(i1.rate.den, ==, i2.rate.den);
    munit_assert_true(ot_interval_is_equal(&i1, &i2));

    i2.start *= 2;
    i2.end *= 2;
    i2.rate.den *= 2;
    munit_assert_false(ot_interval_is_equal(&i1, &i2));
    munit_assert_true(ot_interval_is_equivalent(&i1, &i2));
    return MUNIT_OK;
}

MunitResult interval_conform_test(const MunitParameter params[], 
                            void* user_data_or_fixture) {
    ot_interval_t i1 = ot_interval_at_seconds(0.5, (ot_r32_t) { 1, 12 });
   
    // conform to a different rate
    ot_interval_t i2 = ot_interval_conform(&i1, (ot_r32_t) { 1, 60 });
    munit_assert_true(ot_interval_is_equivalent(&i1, &i2));
   
    // conform to same rate (special case)
    ot_interval_t i3 = ot_interval_conform(&i1, (ot_r32_t) { 1, 12 });
    munit_assert_true(ot_interval_is_equal(&i1, &i3));
   
    // conform to equivalent rate (special case)
    ot_interval_t i4 = ot_interval_conform(&i1, (ot_r32_t) { 10, 120 });
    munit_assert_true(ot_interval_is_equivalent(&i1, &i3));
    return MUNIT_OK;
}

MunitResult affine_identity_proj_test(const MunitParameter params[], 
                               void* user_data_or_fixture) {
    // first, a presentation timeline 1000 frames long at 24
    // and a movie, also 1000 frames long at 24
    ot_interval_t pres_tl = (ot_interval_t) {
        0, 1000, 0.f, 0.f, 1, 24 };
    ot_interval_t mov_1000 = (ot_interval_t) {
        0, 1000, 0.f, 0.f, 1, 24 };

    ot_operator_t op_identity_24;
    op_identity_24.tag = ot_op_affine_transform;
    op_identity_24.slope = (ot_r32_t) { 1, 1 };
    op_identity_24.offset = 0;
    op_identity_24.offset_frac = 0.f;
    op_identity_24.offset_rate = (ot_r32_t) { 1, 24 };

    // at 0.5 seconds, which frame of mov_1000 is showing on pres_tl?
    ot_interval_t sample_0_5 = ot_interval_at_seconds(0.5, (ot_r32_t) { 1, 24 });
    ot_interval_t mov_sample_0_5 = ot_project(&sample_0_5, &op_identity_24);
    munit_assert_int(mov_sample_0_5.start, ==, mov_sample_0_5.start);
    munit_assert_int(mov_sample_0_5.end, ==, mov_sample_0_5.end);

    ot_interval_t sample_1h_plus = ot_interval_at_seconds(3600.f + 600.f + 7.5f, (ot_r32_t) { 1, 24 });
    ot_interval_t mov_1h_plus = ot_project(&sample_1h_plus, &op_identity_24);
    munit_assert_int(sample_1h_plus.start, ==, mov_1h_plus.start);
    munit_assert_int(sample_1h_plus.end, ==, mov_1h_plus.end);
    return MUNIT_OK;
}

MunitResult affine_scale_proj_test(const MunitParameter params[], 
                                  void* user_data_or_fixture) {
    // first, a presentation timeline 1000 frames long at 24
    // and a movie, also 1000 frames long at 24
    ot_interval_t pres_tl = (ot_interval_t) {
        0, 1000, 0.f, 0.f, 1, 24 };
    ot_interval_t mov_1000 = (ot_interval_t) {
        0, 1000, 0.f, 0.f, 1, 24 };

    ot_operator_t op_identity_24;
    op_identity_24.tag = ot_op_affine_transform;
    op_identity_24.slope = (ot_r32_t) { 1, 2 };
    op_identity_24.offset = 0;
    op_identity_24.offset_frac = 0.f;
    op_identity_24.offset_rate = (ot_r32_t) { 1, 24 };

    // at 0.5 seconds, which frame of mov_1000 is showing on pres_tl?
    ot_interval_t sample_0_5 = ot_interval_at_seconds(0.5, (ot_r32_t) { 1, 24 });
    ot_interval_t mov_sample_0_5 = ot_project(&sample_0_5, &op_identity_24);
    munit_assert_int(sample_0_5.start, ==, mov_sample_0_5.start * 2);

    ot_interval_t sample_1h_plus = ot_interval_at_seconds(3600.f + 600.f + 7.5f, (ot_r32_t) { 1, 24 });
    ot_interval_t mov_1h_plus = ot_project(&sample_1h_plus, &op_identity_24);
    munit_assert_int(sample_1h_plus.start, ==, mov_1h_plus.start * 2);
    return MUNIT_OK;
}

MunitResult affine_offset_proj_test(const MunitParameter params[], 
                                  void* user_data_or_fixture) {
    // first, a presentation timeline 1000 frames long at 24
    // and a movie, also 1000 frames long at 24
    ot_interval_t pres_tl = (ot_interval_t) {
        0, 1000, 0.f, 0.f, 1, 24 };
    ot_interval_t mov_1000 = (ot_interval_t) {
        0, 1000, 0.f, 0.f, 1, 24 };

    ot_operator_t op_identity_24;
    op_identity_24.tag = ot_op_affine_transform;
    op_identity_24.slope = (ot_r32_t) { 1, 1 };
    op_identity_24.offset = -48; // offset into the movie by two seconds
    op_identity_24.offset_frac = 0.f;
    op_identity_24.offset_rate = (ot_r32_t) { 1, 24 };

    // at 0.5 seconds, which frame of mov_1000 is showing on pres_tl?
    ot_interval_t sample_0_5 = ot_interval_at_seconds(0.5, (ot_r32_t) { 1, 24 });
    ot_interval_t mov_sample_0_5 = ot_project(&sample_0_5, &op_identity_24);
    munit_assert_int(sample_0_5.start + 48, ==, mov_sample_0_5.start);

    ot_interval_t i2 = ot_interval_at_seconds(3600.f + 600.f + 7.5f, (ot_r32_t) { 1, 24 });
    ot_interval_t mov_1h_plus = ot_project(&i2, &op_identity_24);
    munit_assert_int(i2.start + 48, ==, mov_1h_plus.start);
    return MUNIT_OK;
}


MunitResult affine_offset_scale_proj_test(const MunitParameter params[], 
                                          void* user_data_or_fixture) {
    // first, a presentation timeline 1000 frames long at 24
    // and a movie, also 1000 frames long at 24
    ot_interval_t pres_tl = (ot_interval_t) {
        0, 1000, 0.f, 0.f, 1, 24 };
    ot_interval_t mov_1000 = (ot_interval_t) {
        0, 1000, 0.f, 0.f, 1, 24 };

    ot_operator_t op_identity_24;
    op_identity_24.tag = ot_op_affine_transform;
    op_identity_24.slope = (ot_r32_t) { 1, 2 };
    op_identity_24.offset = -48; // offset into the movie by two seconds
    op_identity_24.offset_frac = 0.f;
    op_identity_24.offset_rate = (ot_r32_t) { 1, 24 };

    // at 0.5 seconds, which frame of mov_1000 is showing on pres_tl?
    ot_interval_t sample_0_5 = ot_interval_at_seconds(0.5, (ot_r32_t) { 1, 24 });
    ot_interval_t mov_sample_0_5 = ot_project(&sample_0_5, &op_identity_24);
    munit_assert_int(sample_0_5.start + 24, ==, mov_sample_0_5.start);

    ot_interval_t i2 = ot_interval_at_seconds(3600.f + 600.f + 7.5f, (ot_r32_t) { 1, 24 });
    ot_interval_t mov_1h_plus = ot_project(&i2, &op_identity_24);
    munit_assert_int(i2.start + 24, ==, mov_1h_plus.start);
    return MUNIT_OK;
}

MunitResult seconds_test(const MunitParameter params[], 
                          void* user_data_or_fixture) {
    static double times[] = {
        1, 0, -1,
        1000.123,
        -1000.123,
        6804068040.386486,
        -6804068040.384686,
        1000000.0 * 365.0 * 24.0 * 3600.0 + 0.5,
        INFINITY, -INFINITY
    };

    for (int i = 0; i < sizeof(times) / sizeof(double); ++i) {
        ot_interval_t interval = ot_interval_at_seconds(times[i], (ot_r32_t) { 1, 192000 });
        //printf("seconds %f, frames %lld, frac %f\n",
        //        times[i], interval.start, interval.start_frac);
        double seconds = ot_interval_start_as_seconds(&interval);
        //printf("times[i] %f == %f seconds\n", times[i], seconds);
        munit_assert_double_equal(times[i], seconds, 9); // precision 1e-6
    }

   for (int i = 0; i < sizeof(times) / sizeof(double); ++i) {
        ot_interval_t interval = ot_interval_at_seconds(times[i], (ot_r32_t) { 1, 24 });
        //printf("seconds %f, frames %lld, frac %f\n",
        //        times[i], interval.start, interval.start_frac);
        double seconds = ot_interval_start_as_seconds(&interval);
        //printf("times[i] %f == %f seconds\n", times[i], seconds);
        munit_assert_double_equal(times[i], seconds, 9); // precision 1e-6
    }

    // test NAN
    ot_interval_t nan_i = ot_interval_at_seconds(33.0, (ot_r32_t) { 0, 0 });
    double nan = ot_interval_start_as_seconds(&nan_i);
    munit_assert(copysign(1, nan) > 0);
    munit_assert(isnan(nan));
    nan_i = ot_interval_at_seconds(-33.0, (ot_r32_t) { 0, 0 });
    nan = ot_interval_start_as_seconds(&nan_i);
    munit_assert(copysign(-1, nan) < 0);
    munit_assert(isnan(nan));
    nan_i = ot_interval_at_seconds(NAN, (ot_r32_t) { 1, 24 });
    nan = ot_interval_start_as_seconds(&nan_i);
    munit_assert(copysign(1, nan) > 0);
    munit_assert(isnan(nan));
    nan_i = ot_interval_at_seconds(-NAN, (ot_r32_t) { 1, 24 });
    nan = ot_interval_start_as_seconds(&nan_i);
    munit_assert(copysign(-1, nan) < 0);
    munit_assert(isnan(nan));
  
    return MUNIT_OK;
}

// [] test add an interval, with same and different rates, nan, and inf
// [x] test project with an offset
// [x] test project with a slope
// [x] test project with a slope and an offset
// [] verify project results with nan and inf in input and transform

void ot_test() {
    static MunitTest tests[] = {
        {
            "/interval_equality_test", /* name */
            interval_equality_test, /* test */
            NULL, /* setup */
            NULL, /* tear_down */
            MUNIT_TEST_OPTION_NONE, /* options */
            NULL /* parameters */
        },
        {   "/seconds_test", /* name */
            seconds_test, /* test */
            NULL, NULL, MUNIT_TEST_OPTION_NONE, NULL },
        {   "/interval_conform_test", interval_conform_test,
            NULL, NULL, MUNIT_TEST_OPTION_NONE, NULL },
        {   "/affine_identity_proj_test", /* name */
            affine_identity_proj_test, /* test */
            NULL, NULL, MUNIT_TEST_OPTION_NONE, NULL },
        {   "/affine_scale_proj_test", /* name */
            affine_scale_proj_test, /* test */
            NULL, NULL, MUNIT_TEST_OPTION_NONE, NULL },
        {   "/affine_offset_proj_test", /* name */
            affine_offset_proj_test, /* test */
            NULL, NULL, MUNIT_TEST_OPTION_NONE, NULL },
        {   "/affine_offset_scale_proj_test", /* name */
            affine_offset_proj_test, /* test */
            NULL, NULL, MUNIT_TEST_OPTION_NONE, NULL },
        
        // end of array mark
        { NULL, NULL, NULL, NULL, MUNIT_TEST_OPTION_NONE, NULL }
    };
    static const MunitSuite suite = {
        "/ot-test", /* name */
        tests, /* tests */
        NULL, /* suites */
        1, /* iterations */
        MUNIT_SUITE_OPTION_NONE /* options */
    };
    munit_suite_main(&suite, NULL, 0, NULL);
}

