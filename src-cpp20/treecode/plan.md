# Treecode Module C++20 Port Plan

## Overview

This directory contains the C++20 port of the treecode module from `../../src/treecode/`. The treecode module provides a binary encoding scheme for representing paths through binary trees and a mapping system for associating treecodes with graph nodes.

## Source Files to Port

The Zig source files and their approximate complexity:

1. **treecode.zig** (1536 lines) - Core treecode implementation
2. **map.zig** (711 lines) - Bidirectional mapping of treecodes to graph nodes
3. **root.zig** (20 lines) - Module exports

**Total**: ~2267 lines of Zig code

## Core Concepts

### Treecode

A binary encoding of a path through a binary tree, packed into an array of 64-bit words (TreecodeWord).

**Key characteristics:**
- Path is read from LSB (right) to MSB (left)
- Contains a marker bit (always `0b1`) separating the path from unused bits
- Path step directions: `0` = left child, `1` = right child
- Example: `0b1011` = marker `0b1`, path `011` = right, right, left

**Core operations:**
- `init()` - Create new treecode with just marker bit
- `append()` - Add a branch (left/right) to the path
- `code_length()` - Get number of bits in the path
- `eql()` - Value equality comparison
- `is_prefix_of()` - Test if one treecode is a prefix of another
- `clone()` - Deep copy
- `hash()` - Hash value for use in hash maps

### Map

A bidirectional map connecting treecodes to graph nodes, enabling:
- Random access to nodes by path
- Path computation between nodes
- Tree traversal via PathIterator

**Core structures:**
- `PathNode` - Associates a graph node with its treecode and parent/child indices
- `PathIterator` - Depth-first traversal through the graph
- Dual hash maps: treecode→index and node→index

## Dependencies

### External Dependencies
- Standard C++20 library
  - `<vector>` - dynamic arrays
  - `<unordered_map>` - hash maps
  - `<optional>` - nullable types
  - `<cstdint>` - fixed-width integers
  - `<bit>` - bit manipulation utilities

### No Internal Dependencies
The treecode module is standalone and doesn't depend on opentime or curve modules.

## Porting Strategy

### Phase 1: Core Treecode (treecode.hpp)

Port the fundamental `Treecode` class with bit-manipulation operations.

**Key design considerations:**
- Use `std::vector<uint64_t>` for word storage (vs Zig slice with allocator)
- Leverage `<bit>` for `std::countl_zero` (count leading zeros)
- Enum class for `LeftOrRight`
- Static methods for bit manipulation on words

**Testing:** `test-treecode.cpp`

**Core functionality to port:**
```cpp
class Treecode {
    std::vector<uint64_t> words;

    // Construction
    static Treecode init();
    static Treecode init_word(uint64_t word);
    Treecode clone() const;

    // Path operations
    size_t code_length() const;
    void append(LeftOrRight branch);
    bool eql(Treecode const& other) const;
    bool is_prefix_of(Treecode const& other) const;

    // Hashing
    uint64_t hash() const;
};
```

### Phase 2: Treecode HashMap (treecode_hash.hpp)

Port the hash map wrapper for treecodes.

**Key design:**
- `std::unordered_map<Treecode, T, TreecodeHash>` specialization
- Custom hash functor using `Treecode::hash()`
- Custom equality comparator using `Treecode::eql()`

**Testing:** Tests embedded in treecode tests

### Phase 3: Map Implementation (map.hpp)

Port the bidirectional mapping system.

**Key design considerations:**
- Template on `GraphNodeType`: `template<typename GraphNodeType> class Map`
- Use `std::unordered_map` for both directions
- Use `std::vector` for node storage (vs Zig's MultiArrayList)
- Implement `PathIterator` with stack-based traversal

**Testing:** `test-map.cpp`

**Core functionality:**
```cpp
template<typename GraphNodeType>
class Map {
    struct PathNode {
        GraphNodeType space;
        Treecode code;
        std::optional<NodeIndex> parent_index;
        std::array<std::optional<NodeIndex>, 2> child_indices;
    };

    std::unordered_map<GraphNodeType, NodeIndex> map_space_to_index;
    std::unordered_map<Treecode, NodeIndex, TreecodeHash> map_code_to_index;
    std::vector<PathNode> nodes;

    // Operations
    NodeIndex put(PathNode node);
    std::optional<NodeIndex> fetch_index_by_code(Treecode const& code) const;
    std::optional<NodeIndex> fetch_index_by_space(GraphNodeType const& space) const;
    PathIterator iter() const;
};
```

## C++20 Port Conventions

Following the patterns established in the `opentime/` and `curve/` ports:

### 1. Type System
- `uint64_t` for `TreecodeWord`
- `enum class LeftOrRight : uint8_t { Left = 0, Right = 1 }`
- Template-based `Map<GraphNodeType>`
- Type aliases for clarity: `using NodeIndex = size_t;`

### 2. Memory Management
- `std::vector` for dynamic arrays (automatic memory management)
- RAII semantics - no explicit `deinit()`
- Move semantics for efficiency
- Copy constructor for cloning

### 3. Naming Conventions
- Types: `PascalCase` (e.g., `Treecode`, `PathNode`)
- Functions: `snake_case` (e.g., `code_length`, `is_prefix_of`)
- Constants: `UPPER_CASE` (e.g., `MARKER`, `WORD_BIT_COUNT`)
- Member variables: `snake_case`

### 4. Bit Manipulation
- Use C++20 `<bit>` header: `std::countl_zero`, `std::countr_zero`
- Leverage bitwise operators
- Inline bit manipulation helpers as private methods

### 5. Hash Map Integration
- Custom hash functor for `std::unordered_map`
- Equality comparator using `Treecode::eql()`
- Consider hash collision handling

### 6. Testing
- Follow `tiny-test.hpp` framework
- One test file per major component
- Test bit manipulation edge cases
- Test tree traversal logic
- Makefile with `make tests` target

### 7. Error Handling
- Use `std::optional` for operations that may fail
- Throw exceptions for invalid operations (e.g., appending to empty treecode)
- No silent failures

## File Structure

```
./treecode/
├── plan.md                    # This file
├── Makefile                   # Build system
├── treecode.hpp               # Core Treecode class
├── treecode_hash.hpp          # Hash map support
├── map.hpp                    # Map and PathIterator
├── test-treecode.cpp          # Treecode tests
└── test-map.cpp               # Map tests
```

## Implementation Order

1. **treecode.hpp** (core functionality)
   - `TreecodeWord`, `MARKER`, `WORD_BIT_COUNT` constants
   - `LeftOrRight` enum
   - `Treecode` class with basic operations
   - Bit manipulation helpers

2. **test-treecode.cpp** (validate core)
   - Test construction (`init`, `init_word`)
   - Test `code_length` calculation
   - Test `append` operations
   - Test `eql` and `is_prefix_of`
   - Test multi-word treecodes
   - Test hashing

3. **treecode_hash.hpp** (hash map support)
   - `TreecodeHash` functor
   - `TreecodeEqual` comparator
   - Type alias for `TreecodeHashMap<T>`

4. **map.hpp** (mapping system)
   - `PathNode` struct
   - `Map<GraphNodeType>` template
   - Basic put/fetch operations
   - `PathIterator` for traversal

5. **test-map.cpp** (validate mapping)
   - Test node insertion and retrieval
   - Test bidirectional lookups
   - Test path iteration
   - Test parent/child relationships

## Notes

- **Performance**: Bit manipulation should be highly optimized
- **Portability**: Use standard C++20 features only
- **Memory**: Vector growth strategy mimics Zig's realloc behavior
- **Debugging**: Include stream operators for visualization
- **Thread safety**: Not required (matches Zig implementation)

## Success Criteria

- [ ] Treecode class compiles and all tests pass
- [ ] Multi-word treecodes work correctly
- [ ] Hash map integration functions properly
- [ ] Map template works with various GraphNodeType types
- [ ] PathIterator correctly traverses trees
- [ ] All edge cases handled (empty treecode, large paths, etc.)
- [ ] Code follows established C++20 patterns
- [ ] API is idiomatic C++ while maintaining conceptual fidelity

## References

- Source: `../../src/treecode/`
- Opentime port: `../opentime/`
- Curve port: `../curve/`
- C++20 `<bit>` header: https://en.cppreference.com/w/cpp/header/bit
