
#ifndef OPENTIME_H
#define OPENTIME_H

#include <stdbool.h>
#include <stdint.h>

/*
 * ot_r32_t
 *
 * a 32 bit signed rational number
 *
 * A value of {  0, 0 } indicates NAN
 * A value of {  N, 0 } where N is >0 indicates +INFINITY
 * A value of { -N, 0 } indicates -INFINITY
 */

typedef struct {
    int32_t  num;
    uint32_t den;
} ot_r32_t;

ot_r32_t ot_r32_abs(ot_r32_t r);
ot_r32_t ot_r32_add(ot_r32_t lh, ot_r32_t rh);
ot_r32_t ot_r32_create(int32_t n_, int32_t d_);
ot_r32_t ot_r32_div(ot_r32_t lh, ot_r32_t rh);
bool     ot_r32_equal(ot_r32_t lh, ot_r32_t rh);
bool     ot_r32_equivalent(ot_r32_t lh, ot_r32_t rh);
int32_t  ot_r32_floor(ot_r32_t a);
ot_r32_t ot_r32_force_den(ot_r32_t r, uint32_t den);
bool     ot_r32_is_inf(ot_r32_t r);
bool     ot_r32_is_nan(ot_r32_t r);
ot_r32_t ot_r32_inverse(ot_r32_t r); // multiplicative inverse
bool     ot_r32_less_than(ot_r32_t lh, ot_r32_t rh);
bool     ot_r32_less_than_int(ot_r32_t r32, int i);
ot_r32_t ot_r32_mul(ot_r32_t lh, ot_r32_t rh);
ot_r32_t ot_r32_negate(ot_r32_t r);
ot_r32_t ot_r32_normalize(ot_r32_t r);
int32_t  ot_r32_sign(ot_r32_t r);
ot_r32_t ot_r32_sub(ot_r32_t lh, ot_r32_t rh);

typedef struct {
    int64_t  start;      // start count of rate units
    int64_t  end;        // end count
    float    start_frac; // fraction [0, 1) between start and start + rate
    float    end_frac;   // end fraction
    ot_r32_t rate;       // rate, multiply with start to convert to seconds
} ot_interval_t;

ot_interval_t ot_interval_add(const ot_interval_t* t, const ot_interval_t* addend);
ot_interval_t ot_interval_additive_inverse(const ot_interval_t* f);
ot_interval_t ot_interval_at_seconds(double t, uint64_t raten, uint64_t rated);
double        ot_interval_end_as_seconds(const ot_interval_t* t);
bool          ot_interval_is_equal(const ot_interval_t*, const ot_interval_t*);
bool          ot_interval_is_equalivalent(const ot_interval_t*, const ot_interval_t*);
bool          ot_interval_is_valid(const ot_interval_t* t);
ot_interval_t ot_interval_normalize(const ot_interval_t* t);
double        ot_interval_start_as_seconds(const ot_interval_t* t);
ot_interval_t ot_invalid_interval();

typedef enum {
    ot_op_affine_transform
} ot_operator_tag;

typedef struct {
    ot_operator_tag tag;
    union {
        struct {
            // affine transform as slope + offset
            ot_r32_t    slope;
            int64_t     offset;
            float       offset_frac;
            ot_r32_t    offset_rate;
        };
    };
} ot_operator_t;

ot_interval_t ot_project(ot_interval_t* t, ot_operator_t* op);

void ot_test();

#endif

