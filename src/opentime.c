#include "cvector.h"
#include <math.h>
#include <stdint.h>

typedef struct {
    int64_t start; // start count of rate units
    float fracs;   // fraction [0, 1) between start and start + rate
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
    ot_sample_t mov_sample_0_5 = ot_project(sample_0_5, op_identity_24);
};

