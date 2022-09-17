
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

typedef struct {
    ot_frame_t offset;
    int64_t slopen;
    int64_t sloped;
} ot_affine_transform_t;

typedef struct {
    ot_frame_t origin;
} ot_continuum_t;

struct ot_topo_node_t;
typedef void ot_operator_t(struct ot_topo_node_t* to, struct ot_topo_node_t* from);

typedef struct {
    struct ot_topo_node_t* from;
    ot_operator_t* transfer_function;
    struct ot_topo_node_t* to;
} ot_topo_node_t;

// example:
// a 24 fps origin
ot_frame_t origin24() { return (ot_frame_t) { 0, 0.f, 0.5, 1, 24 }; }
// a 24 fps presentation continuum
ot_continuum_t presentation_continuum() { return (ot_continuum_t) { origin24() }; }
// first frame
ot_frame_t first_frame() { return (ot_frame_t){ 1, 0.f, 0.5f, 1, 24 } }
// movie 1, starting at 1, ending but not including 10
ot_interval_t mov1() { return (ot_interval_t){first_frame(), 10, 0.f} }
// play the movie at half speed
ot_affine_transform_t half_speed() { return (ot_affine_transform_t){ first(), 1, 2 }; }
// map the movie to the timeline at the origin
ot_topo_node_t topo1() { return (ot_topo_node_t){presentation_continuum(),
                                       half_speed(),
                                       mov1()}; }
// interested in frame 3 of the presentation timeline
ot_frame_t frame3() { return (ot_frame_t) { 3, 0.f, 0.5, 1, 24 }; }
// evaluate the topology at that frame
ot_frame_t mov1_frame3() { return ot_topo_eval(topo1(), frame3()); }

