#ifdef __cplusplus
#define HODO_API_EXTERN_C extern "C"
#else 
#define HODO_API_EXTERN_C
#endif

#include <stdbool.h>

#ifndef RAYGUI_H
    typedef struct Vector2 {
        float x;
        float y;
    } Vector2;
#endif // RAYGUI_H

typedef struct {
    int order;
    Vector2 p[4];
} HodoBezierSegment;

HODO_API_EXTERN_C HodoBezierSegment compute_hodograph(const HodoBezierSegment* const b);

HODO_API_EXTERN_C Vector2 bezier_roots(const HodoBezierSegment* const bz);

HODO_API_EXTERN_C Vector2 inflection_points(const HodoBezierSegment* const bz);

HODO_API_EXTERN_C bool split_bezier(
        const HodoBezierSegment* bz, float t,
        HodoBezierSegment* r1, HodoBezierSegment* r2);

HODO_API_EXTERN_C Vector2 evaluate_bezier(HodoBezierSegment* b, float u);

// 
// 1. compute the hodograph a (quadratic bezier from the cubic)
// 2. pass the hodograph into the root finder
// 3. split the original segment on the roots
//
