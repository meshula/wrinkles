#include "hodographs.h"
#include <math.h>

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

Vector2 bezier_roots(BezierSegment* bz) {
    Vector2 rv = { -1.f, -1.f };
    if (!bz || bz->order < 1 || bz->order > 2)
        return rv;

    if (bz->order == 2) {
        Vector2 p[3];
        p[0] = bz->p[0];
        p[1] = bz->p[1];
        p[2] = bz->p[2];

        if (p[0].y == p[1].y) {
            // nudge p[0].y slightly
            p[0].y += 0.00001;
        }

        float a = p[0].y - 2 * p[1].y + p[2].y;
        float b = 2 * (p[1].y - p[0].y);
        float c = p[0].y;

        // Check if discriminant is negative, meaning no real roots
        if (b * b - 4 * a * c < 0) {
            return rv;
        }

        // Compute roots using quadratic formula
        float sqrtDiscriminant = sqrtf(b * b - 4 * a * c);
        float t1 = (-b + sqrtDiscriminant) / (2 * a);
        float t2 = (-b - sqrtDiscriminant) / (2 * a);

        // Check if roots are within [0, 1], meaning they are on the curve
        if (t1 >= 0 && t1 <= 1) {
            rv.x = t1;
        }

        if (t2 >= 0 && t2 <= 1) {
            rv.y = t2;
        }

        if (rv.x < 0) {
            rv.x = rv.y;
            rv.y = -1.f;
        }
        else if (rv.x > rv.y && rv.y > 0) {
            float tmp = rv.x;
            rv.x = rv.y;
            rv.y = tmp;
        }
    }
    else {
        float m = (bz->p[1].y - bz->p[0].y) / (bz->p[1].x - bz->p[0].x);
        float b = bz->p[0].y - m * bz->p[0].x;
        rv.x = -(bz->p[0].y - m * bz->p[0].x) / m;
    }
    return rv;
}
