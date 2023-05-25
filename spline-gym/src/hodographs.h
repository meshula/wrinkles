
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

// a Bezier curve segment is defined by four control points
BezierSegment compute_hodograph(BezierSegment* b);
