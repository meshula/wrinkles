# Wrinkles C Port Status

This document tracks the progress of porting the wrinkles library from Zig to C17.

**Last Updated:** 2025-12-17

## Overall Progress

| Module | Status | LOC Ported | LOC Remaining | Tests |
|--------|--------|------------|---------------|-------|
| opentime | ✅ Complete | ~680 | 0 | 3/3 passing |
| treecode | ✅ Complete | ~400 | 0 | 2/2 passing |
| hodographs | ✅ Complete | ~305 | 0 | N/A (library) |
| curve | 🟢 Core + Projection + Trimming/Splitting | ~2,720 | ~570 (advanced) | 4/4 passing (41 tests) |
| **Total** | 🟡 **In Progress** | **~4,105** | **~570** | **9/9 passing** |

## Module Status

### ✅ opentime (Complete)

All core functionality ported and tested.

- [x] ordinate.h (~200 LOC) - Double-precision ordinate type with arithmetic
- [x] interval.h (~150 LOC) - Continuous and discrete intervals
- [x] transform.h (~200 LOC) - Affine transformations (1D)
- [x] dual.h (~80 LOC) - Dual numbers for automatic differentiation
- [x] lerp.h (~50 LOC) - Linear interpolation with dual number support
- [x] projection_result.h - Projection result types
- [x] util.h, dbg_print.h - Utilities
- [x] Test coverage: 100% (3 test suites)

**Build System:**
- [x] CMakeLists.txt configured
- [x] Headers installed to `/tmp/wrinkles-install/include/opentime/`
- [x] Interface library target created

---

### ✅ treecode (Complete)

Treecode management system ported and tested.

- [x] treecode.h (~150 LOC) - Treecode type and operations
- [x] binary_tree.h (~250 LOC) - Binary tree construction and traversal
- [x] treecode_lib.h - Module entry point
- [x] Test coverage: 100% (2 test suites)

**Build System:**
- [x] CMakeLists.txt configured
- [x] Headers installed to `/tmp/wrinkles-install/include/treecode/`
- [x] Interface library target created

---

### 🟢 curve (Core + Projection + Trimming/Splitting Complete)

Core Bezier and linear curve functionality complete. Critical point splitting, adaptive linearization, projection/transformation, and trimming/splitting operations integrated. Advanced features remain.

---

### ✅ hodographs (Complete - Integrated C Library)

Hodograph computation library for Bezier curve analysis, now integrated.

- [x] hodographs.h (~40 LOC) - C API header
- [x] hodographs.c (~305 LOC) - Hodograph computation and root finding
  - `compute_hodograph` - Compute derivative of Bezier curve
  - `bezier_roots` - Find roots using Cardano's method
  - `inflection_points` - Find inflection points
  - `split_bezier` - Split at parameter value
  - `evaluate_bezier` - Evaluate curve at u
- [x] Renamed types to avoid conflicts (`HodoBezierSegment`)
- [x] Fixed float/double promotion warnings
- [x] CMakeLists.txt configured
- [x] Static library built and linked to curve module
- [x] Headers installed to `/tmp/wrinkles-install/include/hodographs/`

---

#### ✅ Completed Components

**Foundational (~640 LOC):**
- [x] control_point.h (~220 LOC)
  - ControlPoint and Dual_CP types
  - Arithmetic operations (add, sub, mul, div, lerp)
  - Distance calculations
  - Dual number initialization (`dual_cp_init`)
- [x] epsilon.h (~10 LOC)
  - Floating point comparison epsilon constant
- [x] bezier_math.h (~410 LOC)
  - Segment reduction (de Casteljau's algorithm)
  - Bezier evaluation (bezier0 form)
  - Root finding (`bezier_find_u` using Illinois algorithm)
  - Dual number variants for automatic differentiation
  - Fixed critical bug: changed (1-u) to (u-1) in bezier0 evaluation

**Linear Curves (~350 LOC):**
- [x] linear_curve.h (~350 LOC)
  - LinearCurve and LinearCurve_Monotonic types
  - Lifecycle functions (init, deinit, clone, init_identity)
  - Extent computation (extents, extents_input, extents_output)
  - Interpolation (output_at_input, input_at_output)
  - Memory management using standard malloc/free

**Bezier Curves (~1,010 LOC core + critical points + linearization):**
- [x] bezier_curve.h (~1,010 LOC)
  - BezierSegment and BezierCurve types
  - Segment constructors:
    - `bezier_segment_init_identity` - Linear identity segment
    - `bezier_segment_init_from_start_end` - Linear segment between points
    - `bezier_segment_init` - From raw values
  - Segment evaluation:
    - `bezier_segment_eval_at` - De Casteljau evaluation
    - `bezier_segment_eval_at_dual` - With automatic differentiation
  - FindU functions (inverse evaluation):
    - `bezier_segment_findU_input` - Find u for given input
    - `bezier_segment_findU_output` - Find u for given output
  - Segment splitting:
    - `bezier_segment_split_at` - Split at parameter u using de Casteljau
  - Extents:
    - `bezier_segment_extents`, `bezier_segment_extents_input/output`
  - Curve operations:
    - `bezier_curve_init`, `bezier_curve_deinit`, `bezier_curve_clone`
    - `bezier_curve_find_segment`, `bezier_curve_find_segment_index`
    - `bezier_curve_output_at_input`
    - `bezier_curve_extents_input`, `bezier_curve_extents_output`
  - **Hodograph integration (~320 LOC):**
    - `bezier_segment_to_hodograph` - Convert to hodographs format
    - `bezier_segment_from_hodograph` - Convert from hodographs format
    - `bezier_segment_split_on_critical_points` - Split at inflections/extrema
    - Automatic detection of inflection points
    - Automatic detection of extrema (critical points of derivative)
  - **Linearization (~210 LOC):**
    - `bezier_segment_is_approximately_linear` - Control point deviation test
    - `bezier_segment_linearize` - Recursive adaptive subdivision
    - `bezier_curve_linearize` - Full curve linearization with critical point pre-splitting
    - Based on academic paper algorithm
    - Splits at u=0.5 until approximately linear
  - **Projection & Transformation (~130 LOC):**
    - `bezier_segment_output_at_input` - Evaluate segment at input coordinate
    - `bezier_segment_can_project` - Check if projection is valid
    - `bezier_segment_project_segment` - Project one segment through another
    - `bezier_curve_project_affine` - Apply affine transform to curve
    - Note: `bezier_curve_project_linear_curve` deferred (needs linear_curve projection)
  - **Trimming & Splitting (~290 LOC) ✅ NEW:**
    - `bezier_curve_split_at_input_ordinate` - Split curve at single ordinate
    - `bezier_curve_split_at_each_input_ordinate` - Split curve at multiple ordinates
    - `bezier_curve_trimmed_from_input_ordinate` - Trim curve in one direction
    - `bezier_curve_trimmed_in_input_space` - Trim curve to bounds
    - `TrimDirection` enum for TRIM_BEFORE/TRIM_AFTER
    - Dynamic array growth for multi-point splitting

**Tests (~1,465 LOC):**
- [x] test_control_point.c - 15 tests
- [x] test_bezier_math.c - 10 tests
- [x] test_linear_curve.c - 9 tests
- [x] test_bezier_curve.c - 41 tests (includes critical point, linearization, projection, and trimming/splitting tests)
- [x] Test coverage: 100% (4 test suites, 75 tests total)

**Build System:**
- [x] curve/CMakeLists.txt configured
- [x] Headers installed to `/tmp/wrinkles-install/include/curve/`
- [x] curve_lib.h entry point updated

#### 🔲 Advanced Features Not Yet Ported (~570 LOC)

**Priority 1: Core Algorithm Extensions**

- [ ] **findU_dual3** (~200-300 LOC)
  - Cubic root finding using dual numbers with Newton-Raphson
  - Complex algorithm involving discriminant calculation
  - **Note:** May not be needed immediately - regular `bezier_find_u` works well
  - Can be added later if needed for specific use cases
  - **Priority:** Low (optimization, not required for basic functionality)

**Priority 3: Projection & Transformation - ✅ MOSTLY COMPLETE**

- [x] **Core projection algorithms** (~130 LOC) ✅ **COMPLETE** (2025-12-17)
  - `bezier_segment_can_project` - Validate projection is possible
  - `bezier_segment_project_segment` - Project one Bezier segment through another
  - `bezier_curve_project_affine` - Apply affine transformation to curves
  - **Status:** Complete with tests
  - **Tests:** 6 tests covering can_project, project_segment, and affine projection
- [ ] **Additional projection** (~50 LOC)
  - `bezier_curve_project_linear_curve` - Requires linear_curve projection (not yet ported)
  - Can be added when linear_curve projection is implemented

**Priority 2: Adaptive Subdivision - ✅ COMPLETE**

- [x] **Linearization** (~210 LOC) ✅ **COMPLETE**
  - `bezier_segment_is_approximately_linear` - Linearity test based on control point deviation
  - `bezier_segment_linearize` - Recursive adaptive subdivision with tolerance
  - `bezier_curve_linearize` - Linearize entire curve with critical point pre-splitting
  - Recursive algorithm based on control point deviation (academic paper)
  - Splits at u=0.5 until approximately linear within tolerance
  - **Dependencies:** Core evaluation (✅ complete), critical point splitting (✅ complete)
  - **Status:** Complete with tests (2025-12-17)
  - **Tests:** 8 tests covering linearity detection, various tolerances, and full curve linearization
  - **Implementation notes:** Returns dynamically allocated ControlPoint arrays, uses dynamic growth for efficiency

**Priority 2 (MOVED UP): Critical Point Splitting - ✅ COMPLETE**

- [x] **Critical point splitting** (~250 LOC) ✅ **COMPLETE**
  - `bezier_segment_split_on_critical_points` - Split at inflection points and extrema
  - Integrated with **hodographs C library** (copied to src-c/hodographs)
  - **Dependencies:** hodographs library (✅ integrated)
  - **Status:** Complete with tests (2025-12-17)
  - **Tests:** 4 tests covering linear, S-curve, and U-shaped curves
  - **Implementation notes:** Renamed hodographs types to avoid conflicts, fixed float/double warnings

- [ ] **Three-point approximation** (~150-200 LOC)
  - `init_approximate_from_three_points` - Fit curve through 3 points
  - `three_point_guts_plot` - Core fitting algorithm
  - Specialized curve fitting with derivatives
  - **Dependencies:** Core evaluation (✅ complete)
  - **Priority:** Low (specialized use case)

**Priority 5: Additional Curve Operations - ✅ COMPLETE**

- [x] **Trimming & Splitting functions** (~290 LOC) ✅ **COMPLETE** (2025-12-17)
  - `bezier_curve_split_at_input_ordinate` - Split curve at single ordinate
  - `bezier_curve_split_at_each_input_ordinate` - Split at multiple input points
  - `bezier_curve_trimmed_from_input_ordinate` - Trim curve at boundary
  - `bezier_curve_trimmed_in_input_space` - Trim to interval bounds
  - `TrimDirection` enum for directional trimming
  - Boundary condition handling with epsilon tolerance
  - **Dependencies:** Splitting and findU (✅ complete)
  - **Status:** Complete with tests (2025-12-17)
  - **Tests:** 5 tests covering single split, trimming, and multi-point splitting
  - **Note:** `split_at_each_output_ordinate` not yet ported (low priority)

**Priority 6: I/O & Serialization**

- [ ] **JSON I/O** (~200-250 LOC)
  - `read_curve_json` - Parse .curve.json files
  - `read_segment_json` - Parse segment from JSON
  - `read_bezier_curve_data` - Parse Bezier data
  - `write_json_file_curve` - Write curve to file
  - `debug_json_str` - JSON serialization
  - **Dependencies:** None (standalone)
  - **Priority:** Low (utility feature, can use alternative serialization)

**Priority 7: Utility Functions**

- [ ] **Additional utilities** (~100-150 LOC)
  - `segment_endpoints` - Extract all endpoints
  - `points` / `point_ptrs` - Access segment points
  - `from_pt_array` / `set_points` - Array conversion
  - `to_cSeg` - Convert to C hodographs struct
  - **Priority:** Low (convenience functions)

---

## Implementation Notes

### Memory Management Strategy

**Adopted approach:** Standard C `malloc`/`free` for simplicity
- Removed Zig's explicit allocator parameters
- All `init_from_*` functions allocate and copy data
- All `deinit` functions free allocated memory
- Caller owns memory after initialization

**Future consideration:** May add arena allocator option for performance-critical code

### Automatic Differentiation

**Status:** ✅ Fully implemented using dual numbers
- All core operations support dual number variants
- Enables implicit differentiation for optimization algorithms
- Used in `eval_at_dual`, `findU_dual`, segment reduction

### Type Safety

**Approach:** Strong typing with C structs
- No raw `double` arrays - all values wrapped in `Ordinate`
- Explicit type conversions via `ordinate_init()`
- Helps catch dimensional errors at compile time

### Testing Strategy

**Current coverage:** 9 test suites, 100% pass rate
- Unit tests per function
- Property tests for mathematical invariants
- Numerical stability tests (near-zero, near-one, large values)
- Memory safety verified (no leaks in tests)

**Test frameworks used:**
- Custom lightweight framework (opentime/tests/test_harness.h)
- Integrated with CMake/CTest

---

## Build Configuration

### Compiler Requirements

- **Standard:** C17
- **Compiler:** GCC, Clang, or MSVC
- **Flags:** `-Wall -Wextra -Wpedantic -Werror`
- **Additional:** `-Wformat=2 -Wconversion -Wsign-conversion`

### Build Targets

```bash
# Build all
cmake --build /tmp/wrinkles-build

# Run tests
cd /tmp/wrinkles-build && ctest

# Install
cmake --install /tmp/wrinkles-build --prefix /tmp/wrinkles-install
```

### Installation Paths

- Headers: `/tmp/wrinkles-install/include/{opentime,treecode,curve}/`
- CMake config: `/tmp/wrinkles-install/lib/cmake/{opentime,treecode,curve}/`

---

## Known Issues & Limitations

### Resolved Issues

1. ✅ **INFINITY float promotion** - Fixed by using `HUGE_VAL` instead
2. ✅ **bezier_evaluate_bezier0 bug** - Fixed (1-u) → (u-1) sign error
3. ✅ **Missing dual_cp_init** - Added to control_point.h
4. ✅ **Epsilon float/double mismatch** - Changed to double precision

### Current Limitations

1. ✅ ~~**No hodographs integration**~~ - ✅ Complete, integrated successfully
2. ✅ ~~**No linearization**~~ - ✅ Complete, adaptive subdivision working
3. **No JSON I/O** - Alternative serialization needed if required
4. **Limited projection support** - Only basic operations available
5. **No three-point fitting** - Specialized feature not yet ported

### Performance Considerations

- All functions are `static inline` for zero call overhead
- Header-only design enables full compiler optimization
- De Casteljau's algorithm is numerically stable but not the fastest
- Illinois algorithm (findU) typically converges in <10 iterations

---

## Next Steps

### Recommended Priority Order

1. ✅ ~~**Critical point splitting**~~ - **COMPLETE** (2025-12-17)

2. ✅ ~~**Linearization**~~ - **COMPLETE** (2025-12-17)
   - Adaptive subdivision with tolerance
   - ~210 LOC, recursive algorithm
   - 8 tests covering various scenarios

3. ✅ ~~**Projection algorithms**~~ - **COMPLETE** (2025-12-17)
   - Core projection and affine transformation
   - ~130 LOC, segment and curve projection
   - 6 tests covering can_project, project_segment, affine transforms

4. **Trimming functions** (Priority 5) - **NEXT**
   - Useful for curve editing operations
   - Builds on existing split/findU
   - ~250 LOC, straightforward

5. **Three-point approximation** (Priority 4)
   - Specialized use case
   - Can defer until specific need arises

6. **JSON I/O** (Priority 6)
   - Nice to have for debugging/persistence
   - Can use alternative serialization methods

7. **findU_dual3** (Priority 1)
   - Optimization, not required
   - Only needed if regular findU has precision issues

### Optional Enhancements

- [ ] Add arena allocator option for performance
- [ ] SIMD optimizations for segment evaluation
- [ ] GPU compute shader versions of core algorithms
- [ ] Python bindings via cffi or pybind11
- [ ] Benchmark suite comparing to Zig implementation

---

## References

### Source Repositories

- **Zig source:** `/Users/nporcino/dev/Lab/wrinkles/src/`
- **C port:** `/Users/nporcino/dev/Lab/wrinkles/src-c/`
- **Build directory:** `/tmp/wrinkles-build`
- **Install directory:** `/tmp/wrinkles-install`

### Documentation

- Zig source includes extensive inline documentation
- Each C header includes porting notes and references
- Test files demonstrate usage patterns

### Related Libraries

- **hodographs** - C library for Bezier curve analysis (not yet integrated)
- **spline_gym** - Referenced in Zig source for advanced features

---

## Contributing

When porting additional features:

1. Read the corresponding Zig source thoroughly
2. Identify dependencies on already-ported code
3. Create comprehensive tests before implementing
4. Match the Zig behavior exactly (including edge cases)
5. Use the same function naming conventions
6. Add comments explaining algorithm choices
7. Update this status document
8. Ensure all tests pass with `-Werror`

---

**Port Status:** 🟡 Core functionality complete, advanced features pending

**Version:** 0.1.0-dev

**License:** (Same as original Zig implementation)
