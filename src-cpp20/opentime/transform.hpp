#pragma once
#include "ordinate.hpp"
#include "interval.hpp"
#include <iostream>

// AffineTransform1D: 1D affine transformation
// Represents a homogeneous-coordinates transform matrix:
//     | scale  offset |
//     |   0      1    | (implicit bottom row)
//
// Transform order: scale then offset → y = x * scale + offset

template<typename OrdinateT>
struct AffineTransform1DImpl {
    using TransformType = AffineTransform1DImpl<OrdinateT>;
    using Ordinate = OrdinateT;
    using Interval = ContinuousIntervalImpl<Ordinate>;

    // Member data with defaults matching Zig: offset=0, scale=1
    Ordinate offset = Ordinate::ZERO();
    Ordinate scale = Ordinate::ONE();

    // Static constants
    static constexpr TransformType IDENTITY() noexcept {
        return TransformType{ Ordinate::ZERO(), Ordinate::ONE() };
    }

    // Default constructor (identity transform)
    constexpr AffineTransform1DImpl() = default;

    // Direct construction from offset and scale
    constexpr AffineTransform1DImpl(Ordinate o, Ordinate s) noexcept
        : offset(o), scale(s) {}

    // applied_to_ordinate() - transform single point
    // Formula: y = x * scale + offset
    constexpr Ordinate applied_to_ordinate(Ordinate ord) const noexcept {
        // C++20 elegance: no comath magic needed!
        // Direct method chaining matches Zig's intent perfectly
        return ord.mul(scale).add(offset);
    }

    // applied_to_interval() - transform interval by transforming endpoints
    constexpr Interval applied_to_interval(Interval const& cint) const noexcept {
        return Interval{
            applied_to_ordinate(cint.start),
            applied_to_ordinate(cint.end)
        };
    }

    // applied_to_bounds() - transform interval ensuring start < end
    // If scale is negative, endpoints flip - this corrects that
    constexpr Interval applied_to_bounds(Interval const& bnds) const noexcept {
        if (scale.lt(0)) {
            // Negative scale: flip the order
            return Interval{
                applied_to_ordinate(bnds.end),
                applied_to_ordinate(bnds.start)
            };
        }
        return applied_to_interval(bnds);
    }

    // applied_to_transform() - compose two transforms (matrix multiplication)
    // Formula: (self ∘ rhs)(x) = self(rhs(x))
    constexpr TransformType applied_to_transform(TransformType const& rhs) const noexcept {
        return TransformType{
            applied_to_ordinate(rhs.offset),  // Transform rhs's offset through self
            rhs.scale.mul(scale)               // Multiply scales
        };
    }

    // inverted() - return inverse transform
    // ** Assumes scale ≠ 0 (no bounds checking) **
    //
    // Matrix inverse of:
    //     | scale  offset |     | 1/scale  -offset/scale |
    //     |   0      1    |  =  |    0           1       |
    constexpr TransformType inverted() const noexcept {
        // Again, pure C++20 elegance - no expression parser needed
        return TransformType{
            offset.neg().div(scale),      // -offset/scale
            Ordinate::ONE().div(scale)    // 1/scale
        };
    }

    // Stream output
    friend std::ostream& operator<<(std::ostream& os, TransformType const& xform) {
        os << "Aff1D{ offset: " << xform.offset << " scale: " << xform.scale << " }";
        return os;
    }

    // Equality for testing
    constexpr bool operator==(TransformType const& other) const noexcept {
        return offset.eql(other.offset) && scale.eql(other.scale);
    }
};
