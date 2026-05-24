# Topology Module C++20 Port Plan

## Overview

This directory contains the C++20 port of the topology module from `../../src/topology/`. The topology module provides a system for mapping between one-dimensional coordinate spaces using various transformation types.

## Source Files to Port

The Zig source files and their approximate complexity:

1. **mapping_empty.zig** (198 lines) - Empty/null mapping
2. **mapping_affine.zig** (234 lines) - Affine transformations (scale + offset)
3. **mapping_curve_linear.zig** (306 lines) - Linear curve-based mappings
4. **mapping_curve_bezier.zig** (339 lines) - Bezier curve-based mappings
5. **mapping.zig** (710 lines) - Polymorphic Mapping union and join operations
6. **root.zig** (1800+ lines) - Topology class and composition operations
7. **serialization.zig** (37 lines) - JSON serialization support

**Total**: ~3600 lines of Zig code

## Core Concepts

### Mapping

A **Mapping** is a polymorphic function that maps from an "input" space to an "output" space. Mappings can be composed via function composition to build complex transformations.

**Key operations:**
- `project_instantaneous_cc()` - Map an ordinate from input to output space
- `project_instantaneous_cc_inv()` - Map an ordinate from output to input space
- `input_bounds()` / `output_bounds()` - Get the valid domain/range
- `clone()` - Deep copy
- `shrink_to_input_interval()` / `shrink_to_output_interval()` - Trim to interval
- `split_at_input_point()` - Split mapping at a point
- `join()` - Compose two mappings via a common coordinate system

**Mapping types:**
1. **MappingEmpty** - Maps to no values (out of bounds everywhere)
2. **MappingAffine** - Linear transformation: `f(x) = scale * x + offset`
3. **MappingCurveLinearMonotonic** - Piecewise linear curve mapping
4. **MappingCurveBezier** - Bezier curve mapping (optional for initial port)

### Topology

A **Topology** binds regions of a one-dimensional space to a sequence of right-met monotonic mappings, separated by endpoints. There are implicit "Empty" mappings outside the endpoints.

**Core operations:**
- Construction from various mapping types
- Projection operations (input → output, output → input)
- Interval operations (overlap, intersection, etc.)
- Composition operations (join, project_topology_to)

## Dependencies

### External Dependencies
- Standard C++20 library
  - `<variant>` - polymorphic Mapping type
  - `<vector>` - dynamic arrays
  - `<optional>` - nullable types
  - `<algorithm>` - sorting, searching

### Internal Dependencies
- **opentime** module (already ported)
  - Ordinate, ContinuousInterval, ProjectionResult
  - AffineTransform1D
  - Interval operations
- **curve** module (already ported)
  - ControlPoint, Linear, Bezier
  - bezier_math operations
- **treecode** module (already ported) - NOT required for core topology

## Porting Strategy

### Phase 1: Mapping Types (mapping_*.hpp)

Port the individual mapping implementations as separate headers.

**Phase 1A: MappingEmpty (mapping_empty.hpp)**

Simplest mapping - always returns OutOfBounds.

```cpp
struct MappingEmpty {
    ContinuousInterval defined_range;

    ProjectionResult project_instantaneous_cc(Ordinate const& ord) const noexcept;
    ProjectionResult project_instantaneous_cc_inv(Ordinate const& ord) const noexcept;
    ContinuousInterval input_bounds() const noexcept;
    ContinuousInterval output_bounds() const noexcept;
    MappingEmpty clone() const;
    MappingEmpty shrink_to_input_interval(ContinuousInterval const& target) const;
    MappingEmpty shrink_to_output_interval(ContinuousInterval const& target) const;
};
```

**Phase 1B: MappingAffine (mapping_affine.hpp)**

Affine transformation mapping.

```cpp
struct MappingAffine {
    ContinuousInterval input_bounds_val = ContinuousInterval::INFINITE;
    AffineTransform1D input_to_output_xform = AffineTransform1D::IDENTITY;

    ProjectionResult project_instantaneous_cc(Ordinate const& ord) const noexcept;
    ProjectionResult project_instantaneous_cc_inv(Ordinate const& ord) const noexcept;
    ContinuousInterval input_bounds() const noexcept;
    ContinuousInterval output_bounds() const noexcept;
    MappingAffine clone() const;
    MappingAffine shrink_to_input_interval(ContinuousInterval const& target) const;
    MappingAffine shrink_to_output_interval(ContinuousInterval const& target) const;
};
```

**Phase 1C: MappingCurveLinearMonotonic (mapping_curve_linear.hpp)**

Linear curve-based mapping.

```cpp
struct MappingCurveLinearMonotonic {
    LinearOf<ControlPoint>::Monotonic input_to_output_curve;

    ProjectionResult project_instantaneous_cc(Ordinate const& ord) const;
    ProjectionResult project_instantaneous_cc_inv(Ordinate const& ord) const;
    ContinuousInterval input_bounds() const noexcept;
    ContinuousInterval output_bounds() const noexcept;
    MappingCurveLinearMonotonic clone() const;
    // ... etc
};
```

### Phase 2: Polymorphic Mapping (mapping.hpp)

Port the polymorphic Mapping variant and join operations.

**Key design:**
- Use `std::variant` for the polymorphic Mapping type
- Implement visitors for operations
- Port join functions for composition

```cpp
using Mapping = std::variant<
    MappingEmpty,
    MappingAffine,
    MappingCurveLinearMonotonic
>;

// Visitor-based operations
ProjectionResult project_instantaneous_cc(
    Mapping const& mapping,
    Ordinate const& ord
);

ContinuousInterval input_bounds(Mapping const& mapping);
ContinuousInterval output_bounds(Mapping const& mapping);

// Join operations
Mapping join(Mapping const& a2b, Mapping const& b2c);
```

### Phase 3: Topology Class (topology.hpp)

Port the main Topology class.

```cpp
class Topology {
    std::vector<Mapping> mappings;

public:
    static Topology init(std::vector<Mapping> in_mappings);
    static Topology init_from_linear_monotonic(
        LinearOf<ControlPoint>::Monotonic const& crv
    );
    static Topology init_affine(MappingAffine const& aff);

    ProjectionResult project_instantaneous_cc(Ordinate const& ord) const;
    ProjectionResult project_instantaneous_cc_inv(Ordinate const& ord) const;
    ContinuousInterval input_bounds() const noexcept;
    ContinuousInterval output_bounds() const noexcept;

    // Composition operations
    Topology project_topology_to(Topology const& other) const;
    // ... etc
};
```

## C++20 Port Conventions

Following established patterns from opentime, curve, and treecode:

### 1. Type System
- `std::variant` for polymorphic Mapping
- Static factory methods (init, init_affine, etc.)
- Type aliases for clarity

### 2. Memory Management
- `std::vector` for dynamic arrays
- RAII semantics - no explicit deinit()
- Move semantics for efficiency
- Copy operations where needed (clone)

### 3. Naming Conventions
- Types: `PascalCase` (e.g., `MappingEmpty`, `Topology`)
- Functions: `snake_case` (e.g., `project_instantaneous_cc`, `input_bounds`)
- Constants: `UPPER_CASE` (e.g., `INFINITE_IDENTITY`, `EMPTY`)
- Member variables: `snake_case`

### 4. Visitor Pattern
- Use `std::visit` for operations on std::variant
- Create helper visitors for common operations
- Generic lambdas where appropriate

### 5. Error Handling
- Use `std::optional` for operations that may fail
- Return `ProjectionResult` (already defined in opentime)
- Throw exceptions for invalid operations

### 6. Testing
- Follow `tiny-test.hpp` framework
- Test each mapping type individually
- Test join operations
- Test Topology composition
- Makefile with `make tests` target

## File Structure

```
./topology/
├── plan.md                           # This file
├── Makefile                          # Build system
├── mapping_empty.hpp                 # Empty mapping
├── mapping_affine.hpp                # Affine mapping
├── mapping_curve_linear.hpp          # Linear curve mapping
├── mapping.hpp                       # Polymorphic Mapping variant
├── topology.hpp                      # Topology class
├── test-mapping-empty.cpp            # Tests for empty mapping
├── test-mapping-affine.cpp           # Tests for affine mapping
├── test-mapping-curve-linear.cpp     # Tests for linear mapping
├── test-mapping.cpp                  # Tests for Mapping variant and joins
└── test-topology.cpp                 # Tests for Topology class
```

## Implementation Order

1. **mapping_empty.hpp** - Simplest mapping type
   - MappingEmpty struct with all operations
   - EMPTY constant

2. **test-mapping-empty.cpp** - Validate empty mapping
   - Test construction
   - Test bounds operations
   - Test projection (always OutOfBounds)
   - Test shrink operations

3. **mapping_affine.hpp** - Affine transformation
   - MappingAffine struct
   - INFINITE_IDENTITY constant
   - Forward and inverse projection

4. **test-mapping-affine.cpp** - Validate affine mapping
   - Test identity transformation
   - Test scale and offset
   - Test inverse projection
   - Test bounds computation

5. **mapping_curve_linear.hpp** - Linear curve mapping
   - MappingCurveLinearMonotonic struct
   - Integration with Linear::Monotonic

6. **test-mapping-curve-linear.cpp** - Validate linear mapping
   - Test curve projection
   - Test inverse projection
   - Test split operations

7. **mapping.hpp** - Polymorphic Mapping
   - std::variant definition
   - Visitor helpers
   - Join operations (join_aff_aff, join_aff_lin, join_lin_lin, etc.)
   - Generic join() function

8. **test-mapping.cpp** - Validate Mapping variant
   - Test variant operations
   - Test join operations
   - Test composition

9. **topology.hpp** - Topology class
   - Construction from various mapping types
   - Projection operations
   - Composition operations

10. **test-topology.cpp** - Validate Topology
    - Test construction
    - Test projection
    - Test composition
    - Test interval operations

11. **Makefile** - Build system

## Notes

- **Bezier mapping**: Can be deferred for initial port (commented out in Zig)
- **Serialization**: Skip for initial port (JSON support can be added later)
- **Performance**: Focus on correctness first, optimize later
- **Portability**: Use standard C++20 features only
- **Thread safety**: Not required (matches Zig implementation)

## Success Criteria

- [ ] All mapping types compile and tests pass
- [ ] Polymorphic Mapping variant works correctly
- [ ] Join operations compose mappings correctly
- [ ] Topology class handles multiple mappings
- [ ] Projection operations work forward and inverse
- [ ] All edge cases handled (empty intervals, out of bounds, etc.)
- [ ] Code follows established C++20 patterns
- [ ] API is idiomatic C++ while maintaining conceptual fidelity

## References

- Source: `../../src/topology/`
- Opentime port: `../opentime/`
- Curve port: `../curve/`
- Treecode port: `../treecode/`
- C++20 std::variant: https://en.cppreference.com/w/cpp/utility/variant
