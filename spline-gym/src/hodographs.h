
#ifndef RAYGUI_H
    typedef struct Vector2 {
        float x;
        float y;
    } Vector2;
#endif // RAYGUI_H

typedef struct {
    int order;
    Vector2 p[4];
} BezierCurve;

// a Bezier curve is defined by four control points
BezierCurve compute_hodograph(BezierCurve* b);
