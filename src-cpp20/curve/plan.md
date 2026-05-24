# Curve Module C++20 Port Plan

## Overview

This directory contains the C++20 port of the curve module from `../src/curve/`. The curve module provides fundamental curve types and mathematical operations for temporal transformations in the wrinkles library.

## Source Files to Port

The Zig source files and their approximate complexity:

1. **control_point.zig** (8.3 KB) - Fundamental type representing (in, out) coordinate pairs
2. **generic_curve.zig** (174 B) - Generic utilities and constants
3. **bezier_math.zig** (43 KB) - Mathematical operations for bezier and linear curves
4. **linear_curve.zig** (47 KB) - Piecewise linear curve implementation
5. **bezier_curve.zig** (116 KB) - Cubic bezier curve implementation
6. **test_segment_projection.zig** (6.7 KB) - Test utilities for segment projection

**Total**: ~220 KB of Zig code

## Dependencies

### External Dependencies
- `opentime` module (already ported to `../opentime/`)
  - `Ordinate` - base type for control point coordinates
  - `Dual_Ord` - automatic differentiation support
  - `Interval` - interval types
  - `Transform` - affine transformations

### Internal Dependencies
```
control_point.zig
    ↓
bezier_math.zig ← linear_curve.zig
    ↓                   ↓
    └──→ bezier_curve.zig ←──┘
```

## Porting Strategy

### Phase 1: Foundation (control_point.hpp)
Port `control_point.zig` first as it's the foundation for all curve types.

**Key design patterns:**
- Template-based generic type: `ControlPointOf<T>`
- Polymorphic arithmetic operations (handle both scalar and ControlPoint operands)
- Distance and normalization operations
- Default specialization: `ControlPoint = ControlPointOf<Ordinate>`
- Dual number support: `Dual_CP = DualOf<ControlPoint>`

**Testing:** `test-control-point.cpp`

### Phase 2: Generic Utilities
Port `generic_curve.zig` - minimal file with constants and comparison functions.

**Contents:**
- `EPSILON` constant for floating-point comparisons
- Comparison utilities for segments

### Phase 3: Linear Curves (linear_curve.hpp)
Port `linear_curve.zig` - piecewise linear interpolation.

**Key design patterns:**
- Template-based: `LinearOf<ControlPointType>`
- Nested `Monotonic` type for immutable monotonic curves
- Memory management with allocator parameter
- Operations: extents, projection, splitting, trimming

**Testing:** `test-linear-curve.cpp`

### Phase 4: Bezier Math (bezier_math.hpp)
Port `bezier_math.zig` - mathematical operations for curves.

**Key operations:**
- `lerp` / `invlerp` - linear interpolation
- Segment reduction for bezier evaluation
- Curve inversion
- Normalization and rescaling
- Split and trim operations

**Testing:** Tests embedded in bezier and linear curve tests

### Phase 5: Bezier Curves (bezier_curve.hpp)
Port `bezier_curve.zig` - cubic bezier curve implementation (largest file).

**Key design patterns:**
- Template-based: `BezierOf<ControlPointType>`
- Segment representation: arrays of 4 control points
- Operations: evaluation, projection, splitting, joining
- Linearization for approximation
- JSON serialization support (may defer)

**Testing:** `test-bezier-curve.cpp`

### Phase 6: Test Utilities
Port `test_segment_projection.zig` if needed for comprehensive testing.

## C++20 Port Conventions

Following the patterns established in the `opentime/` port:

### 1. Type System
- Use C++20 concepts and `requires` clauses instead of Zig's `comptime`
- Template specialization for different base types
- Type traits for polymorphic dispatch
- `using` declarations for default types

### 2. Memory Management
- Stack allocation where possible (like Zig)
- Pass `std::allocator` or custom allocators for dynamic memory
- Use `std::vector` for dynamic arrays instead of Zig slices
- RAII for automatic cleanup

### 3. Naming Conventions
- Types: `PascalCase` (e.g., `ControlPoint`, `LinearCurve`)
- Functions: `snake_case` (e.g., `init_ri`, `eval_at`)
- Constants: `UPPER_CASE` (e.g., `EPSILON`, `ZERO`)
- Member variables: `snake_case`

### 4. Function Patterns
- Static factory methods: `init()`, `init_ri()`
- Method chaining where appropriate
- `constexpr` and `noexcept` where applicable
- Template functions for polymorphic operations

### 5. Polymorphic Arithmetic
Zig pattern:
```zig
pub fn mul(self: @This(), rhs: anytype) ControlPointType {
    return switch (@TypeOf(rhs)) {
        ControlPointType => self.mul_cp(rhs),
        else => self.mul_num(rhs),
    };
}
```

C++20 pattern:
```cpp
template<typename RHS>
constexpr ControlPointType mul(RHS const& rhs) const noexcept {
    if constexpr (std::is_same_v<RHS, ControlPointType>) {
        return mul_cp(rhs);
    } else {
        return mul_num(rhs);
    }
}
```

### 6. Testing
- Follow `tiny-test.hpp` framework from opentime
- One test file per module: `test-control-point.cpp`, `test-linear-curve.cpp`, etc.
- Makefile with `make tests` target
- Each test case uses `TEST_CASE()` macro
- Use `REQUIRE()` for assertions

### 7. Error Handling
- Zig errors → C++ exceptions or return codes
- Validation in constructors/factory methods
- `std::optional` for operations that may fail
- `std::expected` (C++23) or equivalent for error returns if needed

## File Structure

```
./curve/
├── plan.md                    # This file
├── Makefile                   # Build system
├── control_point.hpp          # ControlPoint type and operations
├── generic_curve.hpp          # Constants and utilities
├── linear_curve.hpp           # Linear curve implementation
├── bezier_math.hpp            # Bezier mathematical operations
├── bezier_curve.hpp           # Bezier curve implementation
├── test-control-point.cpp     # ControlPoint tests
├── test-linear-curve.cpp      # Linear curve tests
├── test-bezier-curve.cpp      # Bezier curve tests
└── test-bezier-math.cpp       # Bezier math tests
```

## Implementation Order

1. **control_point.hpp** + **test-control-point.cpp** - Foundation type
2. **generic_curve.hpp** - Simple utilities
3. **bezier_math.hpp** (basic functions) - Core math operations
4. **linear_curve.hpp** + **test-linear-curve.cpp** - Simpler curve type
5. **bezier_curve.hpp** + **test-bezier-curve.cpp** - Complex curve type
6. **bezier_math.hpp** (advanced functions) - Remaining operations
7. Integration testing and refinement

## Notes

- **JSON support**: The Zig code includes JSON serialization. We may defer this to later or use a C++ JSON library
- **Allocator abstraction**: C++ uses `std::allocator` by default, but we can template on allocator type if needed
- **Performance**: Use `constexpr` aggressively for compile-time evaluation
- **Debugging**: Include stream operators (`operator<<`) for debugging output
- **Documentation**: Port comments and add C++-specific notes where patterns differ

## Success Criteria

- [ ] All curve types compile without errors
- [ ] All tests pass
- [ ] Code follows established C++20 patterns from opentime
- [ ] Performance is comparable to Zig implementation
- [ ] API is idiomatic C++ while maintaining conceptual fidelity to original

## References

- Source: `../src/curve/`
- Opentime port: `../opentime/`
- Zig documentation: https://ziglang.org/documentation/master/
