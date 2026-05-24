#pragma once

// Generic curve utilities and constants
//
// Ported from wrinkles/src/curve/generic_curve.zig

// ============================================================================
// Constants
// ============================================================================

constexpr float EPSILON = 0.00001f;

// ============================================================================
// Segment Comparison Utilities
// ============================================================================

// Compare the start coordinate of two segments
// Segments are expected to have a p0 member with an in field
template<typename SegmentType>
constexpr bool cmpSegmentsByStart(SegmentType const& a, SegmentType const& b) noexcept {
    return a.p0.in < b.p0.in;
}
