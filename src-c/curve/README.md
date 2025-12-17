# Curve C Port

A C17 port of the Curve library from Zig, providing 2D curve operations for time-based transformations. This library is designed for working with Bezier and linear curves in multimedia applications.

## Overview

The curve library builds on top of `opentime` data structures to provide curve manipulation functionality. The Zig implementation includes ~7,318 LOC across several modules for working with 2D parametric curves.

## Current Status

### ✅ Completed Components

1. **control_point.h** (~190 LOC)
   - 2D control point type (input/output ordinate pairs)
   - Arithmetic operations (add, sub, mul, div)
   - Geometric operations (distance, normalized)
   - Component-wise and scalar operations
   - 5 test cases passing

2. **epsilon.h** (~10 LOC)
   - Floating point comparison epsilon constant
   - Simple header-only constant definition

### 🚧 Remaining Components

The following modules remain to be ported (~7K LOC combined):

1. **bezier_math.h** (~1,520 LOC from bezier_math.zig)
   - De Casteljau's algorithm for Bezier evaluation
   - Segment reduction (degree lowering)
   - Dual number support for automatic differentiation
   - Bezier projection and root finding
   - This is a prerequisite for bezier_curve.h

2. **linear_curve.h** (~1,980 LOC from linear_curve.zig)
   - Piecewise linear curves (polylines)
   - Monotonic curve forms
   - Linear interpolation between knots
   - Curve splitting at critical points
   - Extent computation

3. **bezier_curve.h** (~3,268 LOC from bezier_curve.zig)
   - Cubic Bezier curve segments
   - Right-met segment sequences
   - Bezier segment projection onto other segments
   - Finding `u` parameter for given input/output values
   - JSON serialization/deserialization
   - Extensive projection and inversion algorithms

4. **test_segment_projection.zig** (~179 LOC)
   - Additional comprehensive tests for segment projection
   - Cross-module integration tests

## Build & Test

```bash
# Configure
cmake -B /tmp/wrinkles-build -S src-c -DCMAKE_INSTALL_PREFIX=/tmp/wrinkles-install

# Build
cmake --build /tmp/wrinkles-build

# Test
cd /tmp/wrinkles-build && ctest --output-on-failure

# Install
cmake --install /tmp/wrinkles-build
```

Current test results:
```
Test #6: control_point_tests ..............   Passed    0.20 sec

100% tests passed (control_point tests)
```

## Usage (Current Components)

```c
#include <curve/control_point.h>

// Create control points
ControlPoint p1 = control_point_init(0.0, 0.0);
ControlPoint p2 = control_point_init(1.0, 2.0);

// Arithmetic
ControlPoint sum = control_point_add(p1, p2);
ControlPoint scaled = control_point_mul_scalar(p2, 0.5);

// Geometric operations
Ordinate dist = control_point_distance(p1, p2);
ControlPoint normalized = control_point_normalized(p2);

// Comparison
bool equal = control_point_equal(p1, p2);
```

## Architecture

### Completed Structure

```
curve/
├── control_point.h      # 2D control point type (~190 LOC)
├── epsilon.h            # Epsilon constant (~10 LOC)
├── curve_lib.h          # Library entry point
├── CMakeLists.txt       # Build configuration
└── tests/
    └── test_control_point.c  # Control point tests (5 tests)
```

### Planned Structure

```
curve/
├── control_point.h      # ✅ Done
├── epsilon.h            # ✅ Done
├── bezier_math.h        # 🚧 TODO (~1,520 LOC)
├── linear_curve.h       # 🚧 TODO (~1,980 LOC)
├── bezier_curve.h       # 🚧 TODO (~3,268 LOC)
├── curve_lib.h          # ✅ Entry point created
└── tests/
    ├── test_control_point.c       # ✅ Done
    ├── test_bezier_math.c         # 🚧 TODO
    ├── test_linear_curve.c        # 🚧 TODO
    ├── test_bezier_curve.c        # 🚧 TODO
    └── test_segment_projection.c  # 🚧 TODO
```

## Design Decisions

### 1. Monomorphic Control Points

The Zig implementation uses generics: `ControlPointOf(inner_type)`. The C port is monomorphic, specialized for `opentime.Ordinate` (f64/double), as this is the only instantiation used in practice.

**Rationale:**
- Simpler implementation without template complexity
- Type safety maintained
- Direct compatibility with opentime types
- Matches actual usage patterns in the codebase

### 2. Header-Only Design

Following the opentime and treecode patterns, curve uses header-only implementation with `static inline` functions.

**Benefits:**
- Aggressive compiler optimization
- Zero function call overhead
- Simplified distribution
- Consistent with project patterns

### 3. Naming Conventions

Functions follow the pattern: `<type>_<operation>`

Examples:
- `control_point_add()` - Add two control points
- `control_point_mul_scalar()` - Multiply by scalar
- `control_point_distance()` - Geometric distance

This follows C standard library conventions and maintains readability.

### 4. Double vs Float

All floating point operations use `double` (f64) to match opentime's Ordinate type, not `float` (f32).

## Port Strategy for Remaining Modules

### Phase 1: Bezier Math (Priority: High)

**bezier_math.h** is a dependency for bezier_curve.h and contains:

1. **Core algorithms:**
   - De Casteljau's algorithm
   - Segment reduction (degree 4→3→2→1)
   - Bezier evaluation at parameter `u`

2. **Root finding:**
   - Newton-Raphson with dual numbers
   - Bisection fallback
   - Numerical robustness

3. **Dual number support:**
   - Automatic differentiation
   - May require porting opentime's Dual types first
   - Or implement simplified non-dual variants

**Challenges:**
- Zig's `eval()` metaprogramming for expression evaluation
- Dual number arithmetic (automatic differentiation)
- Complex numerical algorithms

**Approach:**
- Start with non-dual variants of core algorithms
- Port dual support if needed (or simplify)
- Focus on tested, working implementations

### Phase 2: Linear Curves (Priority: High)

**linear_curve.h** is self-contained and provides:

1. **Linear curve type:**
   - Array of control point knots
   - Piecewise linear interpolation

2. **Monotonic form:**
   - Guaranteed monotonic in input space
   - Split at critical points

3. **Operations:**
   - Extent computation
   - Trimming and splitting
   - Projection

**Challenges:**
- Dynamic array management
- Allocator integration
- Monotonicity guarantees

### Phase 3: Bezier Curves (Priority: High)

**bezier_curve.h** is the most complex module:

1. **Bezier segments:**
   - Four control points (cubic Bezier)
   - Segment sequences (right-met)

2. **Projection algorithms:**
   - Project Bezier onto Bezier
   - Project Bezier onto Linear
   - Complex numerical methods

3. **Inversion:**
   - Find `u` for given input value
   - Find `u` for given output value
   - Root finding with robustness

4. **JSON I/O:**
   - Serialization for test data
   - May be optional for C port

**Challenges:**
- Most complex algorithms in the library
- Extensive use of bezier_math
- Numerical stability critical
- Large test surface area

**Approach:**
- Port after bezier_math is complete
- May simplify some advanced features
- Focus on core functionality first
- Extensive testing required

## Testing Strategy

The Zig implementation includes extensive inline tests. The C port separates tests into dedicated files:

- **test_control_point.c**: ✅ 5 tests passing
- **test_bezier_math.c**: 🚧 TODO (estimate ~15 tests)
- **test_linear_curve.c**: 🚧 TODO (estimate ~20 tests)
- **test_bezier_curve.c**: 🚧 TODO (estimate ~30 tests)
- **test_segment_projection.c**: 🚧 TODO (specialized tests)

Total estimated tests: ~70 test cases

## Dependencies

### Internal Dependencies

- ✅ **opentime** - Ordinate, Interval, Transform types
- ✅ **control_point** - 2D control point (completed)
- 🚧 **bezier_math** - Math utilities (TODO)

### External Dependencies

- Standard C library (math.h, stdlib.h, string.h)
- Math library (`-lm` on Unix)

### Optional Dependencies

- JSON library (for curve serialization) - TBD

## Lines of Code Comparison

| Component | Zig (LOC) | C (LOC) | Status |
|-----------|-----------|---------|--------|
| control_point.zig | 338 | ~190 | ✅ Complete |
| epsilon.zig | 1 | ~10 | ✅ Complete |
| bezier_math.zig | 1,520 | TBD | 🚧 TODO |
| linear_curve.zig | 1,980 | TBD | 🚧 TODO |
| bezier_curve.zig | 3,268 | TBD | 🚧 TODO |
| test_segment_projection.zig | 179 | TBD | 🚧 TODO |
| **Total** | **7,318** | **~200** | **3% complete** |

**Note**: The Zig LOC includes inline tests. C tests are in separate files.

## Performance Characteristics

Expected performance for completed components:

| Operation | Complexity | Notes |
|-----------|------------|-------|
| `control_point_init()` | O(1) | Constant time |
| `control_point_add()` | O(1) | Component-wise operation |
| `control_point_mul()` | O(1) | Component-wise operation |
| `control_point_distance()` | O(1) | Includes sqrt() |
| `control_point_normalized()` | O(1) | Includes distance + division |

All operations are header-only `static inline`, providing zero function call overhead.

## Future Work

### Immediate (Next Steps)

1. ✅ ~~Port control_point~~ - Complete!
2. ✅ ~~Port epsilon~~ - Complete!
3. 🚧 Port bezier_math.h (~1,520 LOC)
   - Start with core de Casteljau algorithm
   - Add segment reduction
   - Port root finding (simplified if needed)
4. 🚧 Port linear_curve.h (~1,980 LOC)
   - Basic linear curve type
   - Monotonic forms
   - Extent/trimming operations
5. 🚧 Port bezier_curve.h (~3,268 LOC)
   - Cubic Bezier segments
   - Projection algorithms
   - Integration with bezier_math

### Medium Term

1. Comprehensive test suite (all modules)
2. JSON serialization (if needed)
3. Performance profiling and optimization
4. Documentation and examples

### Long Term

1. Consider SIMD optimization for batch operations
2. GPU acceleration for curve evaluation
3. Python bindings via ctypes/cffi
4. Integration with USD/OpenTimelineIO

## Conclusion

The curve library port is in early stages with foundational components complete. The control_point module provides the basic building blocks for 2D curve operations.

The remaining ~7K LOC represents substantial work, particularly the bezier_curve module with its complex projection and inversion algorithms. A phased approach targeting bezier_math → linear_curve → bezier_curve is recommended.

All completed code is production-ready with tests passing and full C17 compliance.
