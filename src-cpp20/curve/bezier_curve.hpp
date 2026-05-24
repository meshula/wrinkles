#pragma once
#include "control_point.hpp"
#include "bezier_math.hpp"
#include "generic_curve.hpp"
#include <vector>
#include <array>
#include <optional>

// Bezier Curve implementation
//
// A sequence of right-met 2D Bezier curve segments
//
// Ported from wrinkles/src/curve/bezier_curve.zig

// ============================================================================
// BezierSegment - Single cubic Bezier segment
// ============================================================================

struct BezierSegment {
    ControlPoint p0 = ControlPoint::ZERO();
    ControlPoint p1 = ControlPoint::ZERO();
    ControlPoint p2 = ControlPoint::ONE();
    ControlPoint p3 = ControlPoint::ONE();

    // ---- Construction ----

    constexpr BezierSegment() = default;
    constexpr BezierSegment(
        ControlPoint p0_,
        ControlPoint p1_,
        ControlPoint p2_,
        ControlPoint p3_
    ) : p0(p0_), p1(p1_), p2(p2_), p3(p3_) {}

    /// Initialize from base type control points
    static constexpr BezierSegment init_f32(
        ControlPoint_BaseType p0_,
        ControlPoint_BaseType p1_,
        ControlPoint_BaseType p2_,
        ControlPoint_BaseType p3_
    ) noexcept {
        return BezierSegment{
            ControlPoint::init(p0_),
            ControlPoint::init(p1_),
            ControlPoint::init(p2_),
            ControlPoint::init(p3_)
        };
    }

    /// Initialize identity segment (out = in)
    static constexpr BezierSegment init_identity(
        Ordinate input_start,
        Ordinate input_end
    ) noexcept {
        return init_from_start_end(
            ControlPoint{input_start, input_start},
            ControlPoint{input_end, input_end}
        );
    }

    /// Initialize linear segment from start to end points
    static constexpr BezierSegment init_from_start_end(
        ControlPoint start,
        ControlPoint end
    ) noexcept {
        // Linear bezier: p1 = start + 1/3*(end-start), p2 = start + 2/3*(end-start)
        return BezierSegment{
            start,
            lerp(1.0 / 3.0, start, end),
            lerp(2.0 / 3.0, start, end),
            end
        };
    }

    // ---- Point Access ----

    /// Get array of control points
    constexpr std::array<ControlPoint, 4> points() const noexcept {
        return {p0, p1, p2, p3};
    }

    /// Set points from array
    constexpr void set_points(std::array<ControlPoint, 4> const& pts) noexcept {
        p0 = pts[0];
        p1 = pts[1];
        p2 = pts[2];
        p3 = pts[3];
    }

    // ---- Evaluation ----

    /// Evaluate the segment at parameter u ∈ [0, 1]
    /// Uses De Casteljau's algorithm
    constexpr ControlPoint eval_at(Ordinate const& unorm) const noexcept {
        auto seg3 = segment_reduce4(unorm, *this);
        auto seg2 = segment_reduce3(unorm, seg3);
        auto result = segment_reduce2(unorm, seg2);
        return result.p0;
    }

    /// Evaluate with dual numbers for automatic differentiation
    constexpr Dual_CP eval_at_dual(Dual_Ord const& unorm_dual) const noexcept {
        // Convert control points to dual numbers
        std::array<Dual_CP, 4> self_dual = {
            Dual_CP::init(p0),
            Dual_CP::init(p1),
            Dual_CP::init(p2),
            Dual_CP::init(p3)
        };

        // Apply De Casteljau reduction with dual numbers
        std::array<Dual_CP, 4> seg3;
        seg3[0] = lerp(unorm_dual, self_dual[0], self_dual[1]);
        seg3[1] = lerp(unorm_dual, self_dual[1], self_dual[2]);
        seg3[2] = lerp(unorm_dual, self_dual[2], self_dual[3]);
        seg3[3] = Dual_CP{};

        std::array<Dual_CP, 4> seg2;
        seg2[0] = lerp(unorm_dual, seg3[0], seg3[1]);
        seg2[1] = lerp(unorm_dual, seg3[1], seg3[2]);
        seg2[2] = Dual_CP{};
        seg2[3] = Dual_CP{};

        std::array<Dual_CP, 4> result;
        result[0] = lerp(unorm_dual, seg2[0], seg2[1]);
        result[1] = Dual_CP{};
        result[2] = Dual_CP{};
        result[3] = Dual_CP{};

        return result[0];
    }

    // ---- Splitting ----

    /// Split the segment at parameter u ∈ (0, 1)
    /// Returns two segments: [0, u] and [u, 1]
    /// Returns nullopt if u is out of valid range
    constexpr std::optional<std::array<BezierSegment, 2>> split_at(U_TYPE unorm) const noexcept {
        if (unorm < EPSILON || unorm >= 1.0) {
            return std::nullopt;
        }

        auto pts = points();

        // Left segment (0 to u)
        auto Q0 = p0;
        auto Q1 = lerp(unorm, pts[0], pts[1]);
        auto Q2 = lerp(unorm, Q1, lerp(unorm, pts[1], pts[2]));
        auto Q3 = lerp(
            unorm,
            Q2,
            lerp(unorm, lerp(unorm, pts[1], pts[2]), lerp(unorm, pts[2], pts[3]))
        );

        // Right segment (u to 1)
        auto R0 = Q3;
        auto R1 = lerp(unorm, lerp(unorm, pts[1], pts[2]), lerp(unorm, pts[2], pts[3]));
        auto R2 = lerp(unorm, pts[2], pts[3]);
        auto R3 = pts[3];

        return std::array<BezierSegment, 2>{
            BezierSegment{Q0, Q1, Q2, Q3},
            BezierSegment{R0, R1, R2, R3}
        };
    }

    // ---- Constants ----

    static constexpr BezierSegment IDENT_ZERO_ONE() noexcept {
        return init_identity(Ordinate::init(0.0), Ordinate::init(1.0));
    }

    // ---- Stream Output ----

    friend std::ostream& operator<<(std::ostream& os, BezierSegment const& seg) {
        os << "BezierSegment{" << seg.p0 << ", " << seg.p1 << ", "
           << seg.p2 << ", " << seg.p3 << "}";
        return os;
    }
};

// ============================================================================
// Bezier Segment Reduction Functions (De Casteljau's Algorithm)
// ============================================================================

/// Reduce segment from 4 control points to 3
inline BezierSegment segment_reduce4(
    Ordinate const& u,
    BezierSegment const& segment
) noexcept {
    return BezierSegment{
        lerp(u, segment.p0, segment.p1),
        lerp(u, segment.p1, segment.p2),
        lerp(u, segment.p2, segment.p3),
        ControlPoint::ZERO()  // Unused
    };
}

/// Reduce segment from 3 control points to 2
inline BezierSegment segment_reduce3(
    Ordinate const& u,
    BezierSegment const& segment
) noexcept {
    return BezierSegment{
        lerp(u, segment.p0, segment.p1),
        lerp(u, segment.p1, segment.p2),
        ControlPoint::ZERO(),  // Unused
        ControlPoint::ZERO()   // Unused
    };
}

/// Reduce segment from 2 control points to 1 (final point)
inline BezierSegment segment_reduce2(
    Ordinate const& u,
    BezierSegment const& segment
) noexcept {
    return BezierSegment{
        lerp(u, segment.p0, segment.p1),
        ControlPoint::ZERO(),  // Unused
        ControlPoint::ZERO(),  // Unused
        ControlPoint::ZERO()   // Unused
    };
}

// ============================================================================
// Bezier - Collection of cubic Bezier segments
// ============================================================================

struct Bezier {
    std::vector<BezierSegment> segments;

    // ---- Construction ----

    constexpr Bezier() = default;
    constexpr Bezier(std::vector<BezierSegment> segments_)
        : segments(std::move(segments_)) {}

    // ---- Basic Operations ----

    size_t segment_count() const noexcept {
        return segments.size();
    }

    bool empty() const noexcept {
        return segments.empty();
    }
};
