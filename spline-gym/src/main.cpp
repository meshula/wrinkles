/*******************************************************************************************
*
*
********************************************************************************************/

#include "raylib.h"
#include <math.h>

#define RAYGUI_IMPLEMENTATION
#include "raygui.h"

#include "hodographs.h"

// add two Vector2's
Vector2 operator+(const Vector2& a, const Vector2& b)
{
    return Vector2{a.x + b.x, a.y + b.y};
}

// multiply a Vector2 by a scalar
Vector2 operator*(const Vector2& a, const float& b)
{
    return Vector2{a.x * b, a.y * b};
}

// multiply a Vector2 by a scalar
Vector2 operator*(const float& b, const Vector2& a)
{
    return Vector2{a.x * b, a.y * b};
}

// *= a Vector2 by a scalar
Vector2& operator*=(Vector2& a, const float& b)
{
    a.x *= b;
    a.y *= b;
    return a;
}

// += two Vector2's
Vector2& operator+=(Vector2& a, const Vector2& b)
{
    a.x += b.x;
    a.y += b.y;
    return a;
}


// -= two Vector2's
Vector2& operator-=(Vector2& a, const Vector2& b)
{
    a.x -= b.x;
    a.y -= b.y;
    return a;
}

// subtract two Vector2's
Vector2 operator-(const Vector2& a, const Vector2& b)
{
    return Vector2{a.x - b.x, a.y - b.y};
}

float dot(const Vector2& a, const Vector2& b)
{
    return a.x * b.x + a.y * b.y;
}

BezierSegment translate_bezier(BezierSegment* bz, Vector2 v)
{
    BezierSegment rv;
    rv.order = bz->order;
    for (int i = 0; i <= bz->order; i++)
        rv.p[i] = bz->p[i] + v;
    return rv;
}

BezierSegment move_bezier_to_origin(BezierSegment* bz) {
    if (!bz || bz->order != 3)
        return BezierSegment{3, {{0,0}, {0,0}, {0,0}, {0,0}}};

    return translate_bezier(bz, bz->p[0] * -1.f);
}

BezierSegment scale_bezier(BezierSegment* bz, float s) {
    if (!bz)
        return BezierSegment{0, {{0,0}, {0,0}, {0,0}, {0,0}}};

    BezierSegment rv;
    rv.order = bz->order;
    for (int i = 0; i <= bz->order; i++)
        rv.p[i] = bz->p[i] * s;
    return rv;
}

// Compute the alignment of a Bezier curve, which means, rotate and translate the
// curve so that the first control point is at the origin and the last control point
// is on the x-axis
BezierSegment align_bezier(BezierSegment* bz) {
    if (!bz || bz->order < 2 || bz->order > 3)
        return BezierSegment{0, {{0,0}, {0,0}, {0,0}, {0,0}}};

    if (bz->order == 3) {
        BezierSegment rv;
        rv.order = 3;
        rv.p[0] = {0, 0};
        rv.p[1] = bz->p[1] - bz->p[0];
        rv.p[2] = bz->p[2] - bz->p[0];
        rv.p[3] = bz->p[3] - bz->p[0];
        float dx = rv.p[3].x;
        float dy = rv.p[3].y;
        float a = atan2f(dy, dx);
        float cosa = cosf(-a);
        float sina = sinf(-a);
        rv.p[1] = { rv.p[1].x * cosa - rv.p[1].y * sina, rv.p[1].x * sina + rv.p[1].y * cosa };
        rv.p[2] = { rv.p[2].x * cosa - rv.p[2].y * sina, rv.p[2].x * sina + rv.p[2].y * cosa };
        rv.p[3] = { rv.p[3].x * cosa - rv.p[3].y * sina, rv.p[3].x * sina + rv.p[3].y * cosa };
        return rv;
    }
    else {
        BezierSegment rv;
        rv.order = 2;
        rv.p[0] = {0, 0};
        rv.p[1] = bz->p[1] - bz->p[0];
        rv.p[2] = bz->p[2] - bz->p[0];
        float dx = rv.p[2].x;
        float dy = rv.p[2].y;
        float a = atan2f(dy, dx);
        float cosa = cosf(-a);
        float sina = sinf(-a);
        rv.p[1] = { rv.p[1].x * cosa - rv.p[1].y * sina, rv.p[1].x * sina + rv.p[1].y * cosa };
        rv.p[2] = { rv.p[2].x * cosa - rv.p[2].y * sina, rv.p[2].x * sina + rv.p[2].y * cosa };
        return rv;
    }
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
        
        r =  b->p[0] * omu3;
        r += b->p[1] * 3*u*omu2;
        r += b->p[2] * 3*u2*omu;
        r += b->p[3] * u3;
        return r;
    }
    else if (b->order == 2) {
        // evaluate the Bezier curve at parameter value u.
        // The function is defined recursively as follows:
        // B(u) = (1-u)^2 * p0 + 2u(1-u) * p1 + u^2 * p2
        float u2 = u*u;
        float omu = 1-u;
        float omu2 = omu*omu;
        r =  b->p[0] * omu2;
        r += b->p[1] * 2*u*omu;
        r += b->p[2] * u2;
        return r;
    }
}


// Draw line using cubic-bezier curves in-out
void DrawLineBezierx(BezierSegment* b, int steps, float thick, Color color)
{
    if (!b)
        return;
    
    for (int i = 0; i < steps; ++i) {
        float u = (float)i / (float)steps;
        float v = (float)(i+1) / (float)steps;
        Vector2 p0 = evaluate_bezier(b, u);
        Vector2 p1 = evaluate_bezier(b, v);
        DrawLineEx(p0, p1, thick, color);
    }
}

BezierSegment compute_hodograph(BezierSegment* b)
{
    BezierSegment r{0, {{0,0}, {0,0}, {0,0}, {0,0}}};
    if (!b || b->order < 2 || b->order > 3)
        return r;

    // compute the hodograph of b. Calculate the derivative of the Bezier curve.
    // Subtracting each consecutive control point from the next
    r.order = b->order - 1;
    if (b->order == 3) {
        r.p[0] = b->p[1] - b->p[0];
        r.p[1] = b->p[2] - b->p[1];
        r.p[2] = b->p[3] - b->p[2];
    }
    else if (b->order == 2) {
        r.p[0] = b->p[1] - b->p[0];
        r.p[1] = b->p[2] - b->p[1];
        r.p[2] = {0, 0};
    }
    r.p[3] = {0, 0};
    return r;
}

Vector2 inflection_points(BezierSegment* bz) {
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
    Vector2 Q1 = (1 - t) * p[0] + t * p[1];
    Vector2 Q2 = (1 - t) * Q1 + t * ((1 - t) * p[1] + t * p[2]);
    Vector2 Q3 = (1 - t) * Q2 + t * ((1 - t) * ((1 - t) * p[1] + t * p[2]) + t * ((1 - t) * p[2] + t * p[3]));

    Vector2 R0 = Q3;
    Vector2 R2 = (1 - t) * p[2] + t * p[3];
    Vector2 R1 = (1 - t) * ((1 - t) * p[1] + t * p[2]) + t * R2;
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


/// @class CubicInit
/// @brief Initialization parameters to create a cubic curve with start and
///        end y-values and derivatives.
/// Start is x = 0. End is x = width_x.
struct CubicInit {
  CubicInit(const float start_y, const float start_derivative,
            const float end_y, const float end_derivative, const float width_x)
      : start_y(start_y),
        start_derivative(start_derivative),
        end_y(end_y),
        end_derivative(end_derivative),
        width_x(width_x) {}

  // Short-form in comments:
  float start_y;           // y0
  float start_derivative;  // s0
  float end_y;             // y1
  float end_derivative;    // s1
  float width_x;           // w
};


/// @class CubicCurve
/// @brief Represent a cubic polynomial of the form,
///   c_[3] * x^3  +  c_[2] * x^2  +  c_[1] * x  +  c_[0]
class CubicCurve {
 public:
  static const int kNumCoeff = 4;
  CubicCurve() {
    for (int i = 0; i < kNumCoeff; ++i)
      c_[i] = 0.f;
  }

  CubicCurve(const float c3, const float c2, const float c1, const float c0) {
    c_[3] = c3;
    c_[2] = c2;
    c_[1] = c1;
    c_[0] = c0;
  }
  CubicCurve(const float* c) {
    for (int i = 0; i < kNumCoeff; ++i)
        c_[i] = c[i];
  }

  CubicCurve(const CubicInit& init) { Init(init); }
  void Init(const CubicInit& init);

  /// Shift the curve along the x-axis: x_shift to the left.
  /// That is x_shift becomes the curve's x=0.
  void ShiftLeft(const float x_shift);

  /// Shift the curve along the x-axis: x_shift to the right.
  void ShiftRight(const float x_shift) { ShiftLeft(-x_shift); }

  /// Shift the curve along the y-axis by y_offset: y_offset up the y-axis.
  void ShiftUp(float y_offset) { c_[0] += y_offset; }

  /// Scale the curve along the y-axis by a factor of y_scale.
  void ScaleUp(float y_scale) {
    for (int i = 0; i < kNumCoeff; ++i) {
      c_[i] *= y_scale;
    }
  }

  /// Return the cubic function's value at `x`.
  /// f(x) = c3*x^3 + c2*x^2 + c1*x + c0
  float Evaluate(const float x) const {
    /// Take advantage of multiply-and-add instructions that are common on FPUs.
    return ((c_[3] * x + c_[2]) * x + c_[1]) * x + c_[0];
  }

  /// Return the cubic function's slope at `x`.
  /// f'(x) = 3*c3*x^2 + 2*c2*x + c1
  float Derivative(const float x) const {
    return (3.0f * c_[3] * x + 2.0f * c_[2]) * x + c_[1];
  }

  /// Return the cubic function's second derivative at `x`.
  /// f''(x) = 6*c3*x + 2*c2
  float SecondDerivative(const float x) const {
    return 6.0f * c_[3] * x + 2.0f * c_[2];
  }

  /// Return the cubic function's constant third derivative.
  /// Even though `x` is unused, we pass it in for consistency with other
  /// curve classes.
  /// f'''(x) = 6*c3
  float ThirdDerivative(const float x) const {
    (void)x;
    return 6.0f * c_[3];
  }
/*
  /// Returns true if always curving upward or always curving downward on the
  /// specified x_limits.
  /// That is, returns true if the second derivative has the same sign over
  /// all of x_limits.
  bool UniformCurvature(const Range& x_limits) const;

  /// Return a value below which floating point precision is unreliable.
  /// If we're testing for zero, for instance, we should test against this
  /// Epsilon().
  float Epsilon() const {
    using std::max;
    using std::fabs;
    const float max_c =
        max(max(max(fabs(c_[3]), fabs(c_[2])), fabs(c_[1])), fabs(c_[0]));
    return max_c * kEpsilonScale;
  }*/

  /// Returns the coefficient for x to the ith power.
  float Coeff(int i) const { return c_[i]; }

  /// Overrides the coefficent for x to the ith power.
  void SetCoeff(int i, float coeff) { c_[i] = coeff; }

  /// Returns the number of coefficients in this curve.
  int NumCoeff() const { return kNumCoeff; }

  /// Equality. Checks for exact match. Useful for testing.
  bool operator==(const CubicCurve& rhs) const;
  bool operator!=(const CubicCurve& rhs) const { return !operator==(rhs); }



 private:
  float c_[kNumCoeff];  /// c_[3] * x^3  +  c_[2] * x^2  +  c_[1] * x  +  c_[0]
};

void CubicCurve::Init(const CubicInit& init) {
  //  f(x) = dx^3 + cx^2 + bx + a
  //
  // Solve for a and b by substituting with x = 0.
  //  y0 = f(0) = a
  //  s0 = f'(0) = b
  //
  // Solve for c and d by substituting with x = init.width_x = w. Gives two
  // linear equations with unknowns 'c' and 'd'.
  //  y1 = f(x1) = dw^3 + cw^2 + bw + a
  //  s1 = f'(x1) = 3dw^2 + 2cw + b
  //    ==> 3*y1 - w*s1 = (3dw^3 + 3cw^2 + 3bw + 3a) - (3dw^3 + 2cw^2 + bw)
  //        3*y1 - w*s1 = cw^2 - 2bw + 3a
  //               cw^2 = 3*y1 - w*s1 + 2bw - 3a
  //               cw^2 = 3*y1 - w*s1 + 2*s0*w - 3*y0
  //               cw^2 = 3(y1 - y0) - w*(s1 + 2*s0)
  //                  c = (3/w^2)*(y1 - y0) - (1/w)*(s1 + 2*s0)
  //    ==> 2*y1 - w*s1 = (2dw^3 + 2cw^2 + 2bw + 2a) - (3dw^3 + 2cw^2 + bw)
  //        2*y1 - w*s1 = -dw^3 + bw + 2a
  //               dw^3 = -2*y1 + w*s1 + bw + 2a
  //               dw^3 = -2*y1 + w*s1 + s0*w + 2*y0
  //               dw^3 = 2(y0 - y1) + w*(s1 + s0)
  //                  d = (2/w^3)*(y0 - y1) + (1/w^2)*(s1 + s0)
  const float one_over_w = init.width_x > 0.f ? (1.0f / init.width_x) : 1.f;
  const float one_over_w_sq = one_over_w * one_over_w;
  const float one_over_w_cubed = one_over_w_sq * one_over_w;
  c_[0] = init.start_y;
  c_[1] = init.width_x > 0.f ? init.start_derivative : 0.f;
  c_[2] = 3.0f * one_over_w_sq * (init.end_y - init.start_y) -
          one_over_w * (init.end_derivative + 2.0f * init.start_derivative);
  c_[3] = 2.0f * one_over_w_cubed * (init.start_y - init.end_y) +
          one_over_w_sq * (init.end_derivative + init.start_derivative);
}


//------------------------------------------------------------------------------------
// Program main entry point
//------------------------------------------------------------------------------------
int main(void)
{
    // Initialization
    //--------------------------------------------------------------------------------------
    const int screenWidth = 800;
    const int screenHeight = 450;

    SetConfigFlags(FLAG_MSAA_4X_HINT);
    InitWindow(screenWidth, screenHeight, "raylib [shapes] example - cubic-bezier lines");

    Vector2 start = { screenWidth * 0.25f, screenHeight * 0.25f };
    Vector2 end = { screenWidth * 0.75f, screenHeight * 0.75f };
    Vector2 p1 = start;
    p1.x = (start.x + end.x) * 0.5f;
    p1.y -= 30;
    Vector2 p2 = end;
    p2.y += 30;
    p2.x = (start.x + end.x) * 0.5f;

    SetTargetFPS(60);               // Set our game to run at 60 frames-per-second
    //--------------------------------------------------------------------------------------

    bool dragging = false;
    bool mouseDown = false;
    int selected = -1;
    
    bool draw_normals = false;
    bool draw_roots = true;
    bool draw_inflections = true;
    bool draw_approx = true;
    bool draw_split = true;
    bool draw_curve = false;
    
    // Main game loop
    while (!WindowShouldClose())    // Detect window close button or ESC key
    {
        // Update
        //----------------------------------------------------------------------------------
        if (IsMouseButtonDown(MOUSE_BUTTON_LEFT)) {
            mouseDown = true;
        }
        else {
            dragging = false;
            selected = -1;
        }
        Vector2 mousePos = GetMousePosition();
        if (!dragging) {
            draw_curve = GuiCheckBox((Rectangle){ 20, 170, 20, 20 }, "Draw curve", draw_curve);
            draw_split = GuiCheckBox((Rectangle){ 20, 200, 20, 20 }, "Draw split", draw_split);
            draw_approx = GuiCheckBox((Rectangle){ 20, 230, 20, 20 }, "Draw approximation", draw_approx);
            draw_inflections = GuiCheckBox((Rectangle){ 20, 260, 20, 20 }, "Draw Inflections", draw_inflections);
            draw_normals = GuiCheckBox((Rectangle){ 20, 290, 20, 20 }, "Draw Normals", draw_normals);
            draw_roots = GuiCheckBox((Rectangle){ 20, 320, 20, 20 }, "Draw Roots", draw_roots);
        }
        //----------------------------------------------------------------------------------
        BezierSegment b = {3, start, p1, p2, end};
        BezierSegment h = compute_hodograph(&b);
        BezierSegment h2 = compute_hodograph(&h);
        
        BezierSegment alb = align_bezier(&b);
        alb.p[0] += b.p[0];
        alb.p[1] += b.p[0];
        alb.p[2] += b.p[0];
        alb.p[3] += b.p[0];
        //DrawLineBezierx(&alb, steps, 2.0f, BLACK);

        Vector2 inflections = inflection_points(&b);
        Vector2 roots = bezier_roots(&h);

        float split1 = roots.x;
        if (split1 == -1) {
            split1 = inflections.x;
        }
        if (inflections.x > 0 && inflections.x < split1)
            split1 = inflections.x;

        BezierSegment s1;
        BezierSegment s2;
        if (split1 > 0)
            split_bezier(&b, split1, &s1, &s2);
        else
            draw_split = false;
        
        BezierSegment b0 = move_bezier_to_origin(&s1);
        BezierSegment h0 = compute_hodograph(&b0);
        // start dstart end dend, width
        float run_left    = b0.p[1].x - b0.p[0].x;
        float rise_left   = b0.p[1].y - b0.p[0].y;
        float slope_left  = rise_left / run_left;
        float run_right   = b0.p[3].x - b0.p[2].x;
        float rise_right  = b0.p[3].y - b0.p[2].y;
        float slope_right = rise_right / run_right;

        float cubic_width = b0.p[3].x - b0.p[0].x;
        CubicInit ci_x(b0.p[0].y, slope_left, b0.p[3].y, slope_right, cubic_width);
        CubicCurve cubic_x(ci_x);


        // Draw
        //----------------------------------------------------------------------------------
        BeginDrawing();
        {
            ClearBackground(RAYWHITE);
            
            DrawText("BEZIER DEMONSTRATOR", 15, 20, 20, GRAY);
            
            const int steps = 100;
            if (draw_split) {
                DrawLineBezierx(&s1, steps, 2.0f, RED);
                DrawLineBezierx(&s2, steps, 2.0f, DARKBROWN);
            }

            if (draw_inflections) {
                if (inflections.x > 0) {
                    Vector2 p = evaluate_bezier(&b, inflections.x);
                    DrawCircle(p.x, p.y, 5, RED);
                }
                if (inflections.y > 0) {
                    Vector2 p = evaluate_bezier(&b, inflections.y);
                    DrawCircle(p.x, p.y, 5, RED);
                }
            }

            if (draw_approx) {
                for (float x = 0; x < cubic_width; x += 2) {
                    float y = cubic_x.Evaluate(x);
                    DrawPixel(b.p[0].x + x, b.p[0].y + y, BLACK);
                }
            }


            Vector2* points[4] = { &b.p[0], &b.p[1], &b.p[2], &b.p[3] };
            
            int closest = -1;
            if (selected >= 0) {
                *(points[selected]) = mousePos;
                switch(selected) {
                    case 0:
                        start = mousePos;
                        break;
                    case 1:
                        p1 = mousePos; break;
                    case 2:
                        p2 = mousePos; break;
                    case 3:
                        end = mousePos; break;
                }
            }
            else {
                float closestDist = 1000000;
                for (int i = 0; i < 4; ++i) {
                    Vector2 dp = mousePos - *points[i];
                    float d2 = dot(dp, dp);
                    if (d2 < closestDist) {
                        closestDist = d2;
                        closest = i;
                    }
                }
                if (closestDist < 100 && IsMouseButtonDown(MOUSE_BUTTON_LEFT)) {
                    selected = closest;
                    *(points[closest]) = mousePos;
                    switch(closest) {
                        case 0:
                            start = mousePos;
                            break;
                        case 1:
                            p1 = mousePos; break;
                        case 2:
                            p2 = mousePos; break;
                        case 3:
                            end = mousePos; break;
                    }
                }
            }

            if (draw_normals) {
                for (int i = 0; i < steps; ++i) {
                    float u = (float)i / (float)20;
                    Vector2 p0 = evaluate_bezier(&h, u);
                    Vector2 b0 = evaluate_bezier(&b, u);
                    p0 += b0;
                    DrawLineEx(b0, p0, 2.0f, BLUE);
                    //DrawLineEx(b0, p1, 2.0f, BLUE);
                }
            }
            
            DrawLineEx(b.p[0], b.p[1], 2.f, GREEN);
            DrawLineEx(b.p[3], b.p[2], 2.f, GREEN);
            for (int i = 0; i < 4; ++i)
                DrawRing(*points[i], 2, 6, 0, 360, 16, (closest >= 0)? RED : GREEN);

            if (draw_curve)
                DrawLineBezierx(&b, steps, 2.0f, RED);
            
            if (draw_roots) {
                Vector2 root = bezier_roots(&h);
                if (root.x >= 0.f) {
                    Vector2 r = evaluate_bezier(&b, root.x);
                    DrawRing(r, 2, 6, 0, 360, 16, DARKGREEN);
                }
                if (root.y >= 0.f) {
                    Vector2 r = evaluate_bezier(&b, root.y);
                    DrawRing(r, 2, 6, 0, 360, 16, DARKGREEN);
                }
            }
/*            if (draw_inflections) {
                Vector2 inflection = bezier_roots(&h2);
                if (inflection.x >= 0.f) {
                    Vector2 r = evaluate_bezier(&b, inflection);
                    //DrawRing(r, 2, 6, 0, 360, 16, DARKBLUE);
                }
            }*/
        }
        EndDrawing();
        //----------------------------------------------------------------------------------
    }

    // De-Initialization
    //--------------------------------------------------------------------------------------
    CloseWindow();        // Close window and OpenGL context
    //--------------------------------------------------------------------------------------

    return 0;
}
