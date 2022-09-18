#include "cvector.h"
#include <math.h>
#include <stdbool.h>
#include <stdint.h>

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

