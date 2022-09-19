
#ifndef OPENTIME_H
#define OPENTIME_H

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

ot_r32_t ot_r32_abs(ot_r32_t r);
ot_r32_t ot_r32_add(ot_r32_t lh, ot_r32_t rh);
ot_r32_t ot_r32_create(int32_t n_, int32_t d_);
ot_r32_t ot_r32_div(ot_r32_t lh, ot_r32_t rh);
bool     ot_r32_equal(ot_r32_t lh, ot_r32_t rh);
bool     ot_r32_equivalent(ot_r32_t lh, ot_r32_t rh);
int32_t  ot_r32_floor(ot_r32_t a);
ot_r32_t ot_r32_force_den(ot_r32_t r, uint32_t den);
bool     ot_r32_is_inf(ot_r32_t r);
ot_r32_t ot_r32_inverse(ot_r32_t r); // multiplicative inverse
bool     ot_r32_less_than(ot_r32_t lh, ot_r32_t rh);
bool     ot_r32_less_than_int(ot_r32_t r32, int i);
ot_r32_t ot_r32_mul(ot_r32_t lh, ot_r32_t rh);
ot_r32_t ot_r32_negate(ot_r32_t r);
ot_r32_t ot_r32_normalize(ot_r32_t r);
int32_t  ot_r32_sign(ot_r32_t r);
ot_r32_t ot_r32_sub(ot_r32_t lh, ot_r32_t rh);

typedef struct {
    int64_t start; // start count of rate units
    float frac;    // fraction [0, 1) between start and start + rate
    float kcenter; // sampling kernel center relative to the start count
    ot_r32_t rate; // rate, multiply with start to convert to seconds
} ot_sample_t;

typedef struct {
    ot_sample_t start; // start of interval
    int64_t end;      // end count of rate units
    float frace;      // normalized fraction of end within the end interval
} ot_interval_t;

typedef enum {
    ot_op_affine_transform
} ot_operator_tag;

typedef struct {
    ot_operator_tag tag;
    union {
        struct {
            // affine transform as slope + offset
            int64_t slopen, sloped;
            ot_sample_t offset;
        };
    };
} ot_operator_t;

void ot_test();

#endif
