#include "hodographs.h"
#include <math.h>
#include <stdbool.h>

Vector2 vec2_add_vec2(Vector2 lhs, Vector2 rhs) {
    Vector2 result = { lhs.x + rhs.x, lhs.y + rhs.y };
    return result;
}

Vector2 vec2_sub_vec2(Vector2 lhs, Vector2 rhs) {
    Vector2 result = { lhs.x - rhs.x, lhs.y - rhs.y };
    return result;
}

Vector2 vec2_mul_float(Vector2 lhs, float rhs) {
    Vector2 result = { lhs.x * rhs, lhs.y * rhs };
    return result;
}

Vector2 float_mul_vec2(float lhs, Vector2 rhs) {
    Vector2 result = { lhs * rhs.x, lhs * rhs.y };
    return result;
}


BezierSegment compute_hodograph(const BezierSegment* const b)
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

// Cardano's method, per https://pomax.github.io/bezierinfo
// note that Cardano's method also has a solution for order 3, but
// that's not needed for this library

Vector2 bezier_roots(const BezierSegment* const bz) {
    Vector2 rv = { -1.f, -1.f };
    if (!bz || bz->order < 1 || bz->order > 2)
        return rv;

    if (bz->order == 2) {
        Vector2 p[3];
        p[0] = bz->p[0];
        p[1] = bz->p[1];
        p[2] = bz->p[2];

        float a = p[0].y - 2 * p[1].y + p[2].y;
        float b = 2 * (p[1].y - p[0].y);
        float c = p[0].y;
        // is it linear?
        if (fabsf(a) <= 1.e-4) {
            if (fabsf(b) <= 1.e-4)
                return rv; // no solutions
            float t = -c / b;
            if (t > 0 && t < 1.f)
                rv.x = t; // linear solution
            return rv;
        }
        
        // Check if discriminant is negative, meaning no real roots
        if (b * b - 4 * a * c < 0) {
            return rv;
        }

        // Compute roots using quadratic formula
        float sqrtDiscriminant = sqrtf(b * b - 4 * a * c);
        float t1 = (-b + sqrtDiscriminant) / (2 * a);
        float t2 = (-b - sqrtDiscriminant) / (2 * a);

        // Check if roots are within [0, 1], meaning they are on the curve
        if (t1 > 0 && t1 < 1) {
            rv.x = t1;
        }

        if (t2 > 0 && t2 < 1) {
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

// Compute the alignment of a Bezier curve, which means, rotate and translate the
// curve so that the first control point is at the origin and the last control point
// is on the x-axis
BezierSegment align_bezier(const BezierSegment* const bz) {
    if (!bz || bz->order < 2 || bz->order > 3) {
        return (BezierSegment) {0, {{0,0}, {0,0}, {0,0}, {0,0}}};
    }

    if (bz->order == 3) {
        BezierSegment rv;
        rv.order = 3;
        rv.p[0] = (Vector2) {0, 0};
        rv.p[1] = vec2_sub_vec2(bz->p[1], bz->p[0]);
        rv.p[2] = vec2_sub_vec2(bz->p[2], bz->p[0]);
        rv.p[3] = vec2_sub_vec2(bz->p[3], bz->p[0]);
        float dx = rv.p[3].x;
        float dy = rv.p[3].y;
        float a = atan2f(dy, dx);
        float cosa = cosf(-a);
        float sina = sinf(-a);
        rv.p[1] = (Vector2) { rv.p[1].x * cosa - rv.p[1].y * sina, rv.p[1].x * sina + rv.p[1].y * cosa };
        rv.p[2] = (Vector2) { rv.p[2].x * cosa - rv.p[2].y * sina, rv.p[2].x * sina + rv.p[2].y * cosa };
        rv.p[3] = (Vector2) { rv.p[3].x * cosa - rv.p[3].y * sina, rv.p[3].x * sina + rv.p[3].y * cosa };
        return rv;
    }
    else {
        BezierSegment rv;
        rv.order = 2;
        rv.p[0] = (Vector2) {0, 0};
        rv.p[1] = vec2_sub_vec2(bz->p[1], bz->p[0]);
        rv.p[2] = vec2_sub_vec2(bz->p[2], bz->p[0]);
        float dx = rv.p[2].x;
        float dy = rv.p[2].y;
        float a = atan2f(dy, dx);
        float cosa = cosf(-a);
        float sina = sinf(-a);
        rv.p[1] = (Vector2) { rv.p[1].x * cosa - rv.p[1].y * sina, rv.p[1].x * sina + rv.p[1].y * cosa };
        rv.p[2] = (Vector2) { rv.p[2].x * cosa - rv.p[2].y * sina, rv.p[2].x * sina + rv.p[2].y * cosa };
        return rv;
    }
}

Vector2 inflection_points(const BezierSegment* const bz) {
    if (!bz || bz->order != 3)
        return (Vector2){-1.f, -1.f};
    
    /// @TODO for order 2

    BezierSegment aligned = align_bezier(bz);
    float a = aligned.p[2].x * aligned.p[1].y;
    float b = aligned.p[3].x * aligned.p[1].y;
    float c = aligned.p[1].x * aligned.p[2].y;
    float d = aligned.p[3].x * aligned.p[2].y;
    float x = (-3.f * a) + (2.f*b) + (3.f*c) - d;
    float y = (3.f*a) - b - (3.f*c);
    float z = c - a;

    Vector2 roots = { -1.f, -1.f };

    if (fabsf(x) < 1e-6f) {
        if (fabsf(y) > 1e-6f) {
            roots.x = -z / y;
        }
        if (roots.x < 0 || roots.x > 1.f)
            roots.x = -1;
        return roots;
    }
    float det = y * y - 4 * x * z;
    float sq = sqrtf(det);
    float d2 = 2 * x;

    if (fabsf(d2) > 1e-6f) {
        roots.x = -(y + sq) / d2;
        roots.y = (sq - y) / d2;
        if (roots.x < 0 || roots.x > 1.f)
            roots.x = -1;
        if (roots.y < 0 || roots.y > 1.f)
            roots.y = -1;
    }
    
    if (roots.x < 0) {
        roots.x = roots.y;
        roots.y = -1.f;
    }
    else if (roots.x > roots.y && roots.y > 0) {
        float tmp = roots.x;
        roots.x = roots.y;
        roots.y = tmp;
    }
    return roots;
}

// split bz at t, into two curves r1 and r2

bool split_bezier(const BezierSegment* bz, float t, BezierSegment* r1, BezierSegment* r2)
{
    if (!bz || !r1 || !r2 || bz->order != 3)
        return false;

    /// @TODO for order 2

    if (t <= 0.f || t >= 1.f) {
        return false;
    }

    Vector2 p[4] = { bz->p[0], bz->p[1], bz->p[2], bz->p[3] };

    Vector2 Q0 = p[0];
    
    // Vector2 Q1 = (1 - t) * p[0] + t * p[1];
    Vector2 Q1 = vec2_add_vec2(float_mul_vec2((1 - t), p[0]),
                               float_mul_vec2(t, p[1]));

    //Vector2 Q2 = (1 - t) * Q1 + t * ((1 - t) * p[1] + t * p[2]);
    Vector2 Q2 = vec2_add_vec2(float_mul_vec2((1 - t), Q1),
                               float_mul_vec2(t, (vec2_add_vec2(float_mul_vec2((1 - t), p[1]),
                                                                float_mul_vec2(t, p[2])))));
    
    //Vector2 Q3 = (1 - t) * Q2 + t * ((1 - t) * ((1 - t) * p[1] + t * p[2]) + t * ((1 - t) * p[2] + t * p[3]));
    Vector2 Q3 = vec2_add_vec2(float_mul_vec2((1 - t), Q2),
                               float_mul_vec2(t, (vec2_add_vec2(float_mul_vec2((1 - t), (vec2_add_vec2(float_mul_vec2((1 - t), p[1]),
                                                                           float_mul_vec2(t, p[2])))),
                                                  float_mul_vec2(t, vec2_add_vec2(float_mul_vec2((1 - t), p[2]),
                                                                    float_mul_vec2(t, p[3])))))));

    Vector2 R0 = Q3;
    
    //Vector2 R2 = (1 - t) * p[2] + t * p[3];
    Vector2 R2 = vec2_add_vec2(float_mul_vec2((1 - t), p[2]),
                               float_mul_vec2(t, p[3]));
    
    //Vector2 R1 = (1 - t) * ((1 - t) * p[1] + t * p[2]) + t * R2;
    Vector2 R1 = vec2_add_vec2(float_mul_vec2((1 - t), (vec2_add_vec2(float_mul_vec2((1 - t), p[1]),
                                                                      float_mul_vec2(t, p[2])))),
                               float_mul_vec2(t, R2));
    Vector2 R3 = p[3];

    r1->order = 3;
    r1->p[0] = Q0;
    r1->p[1] = Q1;
    r1->p[2] = Q2;
    r1->p[3] = Q3;

    r2->order = 3;
    r2->p[0] = R0;
    r2->p[1] = R1;
    r2->p[2] = R2;
    r2->p[3] = R3;

    return true;
}


Vector2 evaluate_bezier(BezierSegment* b, float u)
{
    Vector2 r = {0, 0};
    if (!b || b->order < 2 || b->order > 3)
        return r;

    if (b->order == 3) {
        // evaluate the Bezier curve at parameter value u.
        // The function is defined recursively as follows:
        // B(u) = (1-u)^3 * p0 + 3u(1-u)^2 * p1 + 3u^2(1-u) * p2 + u^3 * p3
        float u2 = u*u;
        float u3 = u2*u;
        float omu = 1-u;
        float omu2 = omu*omu;
        float omu3 = omu2*omu;
        
        r = vec2_mul_float(b->p[0], omu3);
        r = vec2_add_vec2(vec2_mul_float(b->p[1], 3*u*omu2), r);
        r = vec2_add_vec2(vec2_mul_float(b->p[2], 3*u2*omu), r);
        r = vec2_add_vec2(vec2_mul_float(b->p[3], u3), r);
        return r;
    }
    else if (b->order == 2) {
        // evaluate the Bezier curve at parameter value u.
        // The function is defined recursively as follows:
        // B(u) = (1-u)^2 * p0 + 2u(1-u) * p1 + u^2 * p2
        float u2 = u*u;
        float omu = 1-u;
        float omu2 = omu*omu;
        r = vec2_mul_float(b->p[0], omu2);
        r = vec2_add_vec2(r, vec2_mul_float(b->p[1], 2*u*omu));
        r = vec2_add_vec2(vec2_mul_float(b->p[2], u2), r);
        return r;
    }
}
