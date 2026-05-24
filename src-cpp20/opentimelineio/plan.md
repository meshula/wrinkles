# OpenTimelineIO C++20 Implementation Plan

## Overview
Port the slim OpenTimelineIO implementation from Zig to C++20, building on the existing opentime, curve, and topology modules.

## Architecture

### Core Modules

1. **core.hpp** - Core types and concepts
   - `SpaceLabel` - enum for coordinate spaces (media, presentation, intrinsic)
   - `SpaceReference` - reference to a specific space
   - `ComposedValueRef` - variant holding pointers to OTIO objects
   - `ProjectionOperator` - represents mappings between spaces
   - `ProjectionOperatorMap` - collection of projection operators

2. **schema.hpp** - OTIO schema types
   - `MediaReference` - information about media (external files, signals, etc.)
   - `Clip` - a piece of media with optional trim
   - `Gap` - empty space in timeline
   - `Track` - sequence of children (right-met in time)
   - `Stack` - parallel children (simultaneous in time)
   - `Warp` - nonlinear transformation between parent and child
   - `Timeline` - top level object containing tracks

3. **json.hpp** - JSON serialization/deserialization
   - Use RapidJSON for parsing and writing
   - Implement to_json() and from_json() for each type
   - Support reading OTIO JSON files

4. **temporal_hierarchy.hpp** - Building projection maps
   - `TemporalMap` - maps between spaces in the hierarchy
   - `build_temporal_map()` - constructs maps from timeline structure
   - `build_projection_operator()` - creates projection operators

## Implementation Strategy

### Phase 1: Core Types
- Implement SpaceLabel enum
- Implement ComposedValueRef variant
- Implement basic space reference types

### Phase 2: Schema Types
Start with simplest types and build up:
1. MediaReference (simple struct)
2. Gap (just duration)
3. Clip (media reference + bounds)
4. Track (container, sequential)
5. Stack (container, parallel)
6. Warp (transform wrapper)
7. Timeline (top level)

### Phase 3: Topology Integration
- Add topology() methods to each schema type
- Implement bounds_of() methods
- Add transform building for Tracks

### Phase 4: JSON Support
- Implement JSON serialization for each type
- Implement JSON deserialization
- Add file I/O support
- Test with real OTIO files

### Phase 5: Temporal Hierarchy
- Implement graph building algorithms
- Add projection operator construction
- Create temporal maps

## Design Patterns

### Memory Management
- Use `std::unique_ptr` for owned pointers
- Use `std::shared_ptr` for shared ownership
- RAII for automatic cleanup
- No manual memory management

### Type Safety
- Use `std::variant` for ComposedValueRef
- Strong typing for space labels
- Const-correctness throughout

### C++20 Features
- Concepts for type constraints
- Ranges for iteration
- std::span for non-owning array views
- constexpr where applicable

## Dependencies
- **opentime**: Ordinate, ContinuousInterval, ProjectionResult
- **topology**: Topology, Mapping types
- **RapidJSON**: JSON parsing and generation
- **Standard library**: variant, optional, string, vector

## Testing Strategy
- Unit tests for each schema type
- Integration tests with topology
- JSON round-trip tests
- Test with example OTIO files from Zig implementation

## Files to Create
```
opentimelineio/
├── plan.md                    (this file)
├── core.hpp                   (core types)
├── schema.hpp                 (schema types)
├── json.hpp                   (JSON support)
├── temporal_hierarchy.hpp     (temporal maps)
├── test-core.cpp              (core tests)
├── test-schema.cpp            (schema tests)
├── test-json.cpp              (JSON tests)
└── Makefile                   (build system)
```

## Notes
- Start simple, add complexity incrementally
- Test each component thoroughly before moving on
- Follow established patterns from opentime/topology modules
- Maintain compatibility with existing Zig OTIO files
