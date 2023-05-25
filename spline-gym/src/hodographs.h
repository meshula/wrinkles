#ifdef __cplusplus
#define HODO_API_EXTERN_C extern "C"
#else 
#define HODO_API_EXTERN_C
#endif

#ifndef RAYGUI_H
    typedef struct Vector2 {
        float x;
        float y;
    } Vector2;
#endif // RAYGUI_H

typedef struct {
    int order;
    Vector2 p[4];
} BezierSegment;

HODO_API_EXTERN_C BezierSegment compute_hodograph(BezierSegment* b);

HODO_API_EXTERN_C Vector2 bezier_roots(BezierSegment* bz);

// 
// 1. compute the hodograph a (quadratic bezier from the cubic)
// 2. pass the hodograph into the root finder
// 3. split the original segment on the roots
//
