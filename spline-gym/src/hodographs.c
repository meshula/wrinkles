#include "hodographs.h"

Vector2 vec2_sub_vec2(Vector2 lhs, Vector2 rhs) {
    Vector2 result = { lhs.x - rhs.x, lhs.y - rhs.y };
    return result;
}

BezierSegment compute_hodograph(BezierSegment* b)
{
    BezierSegment r = {0, {{0,0}, {0,0}, {0,0}, {0,0}}};
    if (!b || b->order < 2 || b->order > 3)
        return r;

    // compute the hodograph of b. Calculate the derivative of the Bezier curve.
    // Subtracting each consecutive control point from the next
    r.order = b->order - 1;
    if (b->order == 3) {
        r.p[0] = vec2_sub_vec2(b->p[1], b->p[0]);
        r.p[1] = vec2_sub_vec2(b->p[2], b->p[1]);
        r.p[2] = vec2_sub_vec2(b->p[3], b->p[2]);
    }
    else if (b->order == 2) {
        r.p[0] = vec2_sub_vec2(b->p[1], b->p[0]);
        r.p[1] = vec2_sub_vec2(b->p[2], b->p[1]);
        r.p[2].x = 0;
        r.p[2].y = 0;
    }
    r.p[3].x = 0;
    r.p[3].y = 0;

    return r;
}
