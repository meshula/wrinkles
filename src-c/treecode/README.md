# Treecode C Port

A C17 port of the Treecode library, originally written in Zig. Treecode provides a binary encoding of paths through binary trees, enabling efficient navigation and path computation.

## Overview

This is a port of the Zig implementation from `src/treecode` to idiomatic C17 in `src-c/treecode`. The treecode encoding allows O(1) path existence checks and efficient tree navigation without traditional pointer-heavy tree structures.

The port includes:
- **Treecode**: Binary path encoding (480 LOC)
- **BinaryTree**: Tree container using treecodes (550 LOC)

## What is a Treecode?

A treecode is a compact binary representation of a path through a binary tree:
- Each bit represents a direction: `0` = left, `1` = right
- Paths are packed into 64-bit words (`TreecodeWord`)
- A marker bit separates the path from unused bits
- Multiple words can represent deep paths

Example: `0x5` (binary: `0b101`)
- Marker: `1` (leftmost bit)
- Path: `01` (read right-to-left)
- Directions: left(0), right(1) from root

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

## Usage

```c
#include <treecode/treecode.h>

Treecode_Allocator* alloc = &TREECODE_STD_ALLOCATOR;

// Create a treecode
Treecode tc;
treecode_init(&tc, alloc);

// Append directions
treecode_append(&tc, alloc, TREECODE_LEFT);   // Go left
treecode_append(&tc, alloc, TREECODE_RIGHT);  // Go right
treecode_append(&tc, alloc, TREECODE_LEFT);   // Go left again

// Check properties
printf("Code length: %zu\n", tc.code_length);  // 3

// Check if one is a prefix of another
Treecode parent, child;
treecode_init_word(&parent, alloc, 0x5);   // shorter path
treecode_init_word(&child, alloc, 0x15);  // longer path

bool is_ancestor = treecode_is_prefix_of(&parent, &child);  // true

// Clean up
treecode_deinit(&tc, alloc);
treecode_deinit(&parent, alloc);
treecode_deinit(&child, alloc);
```

## API Reference

### Initialization
- `treecode_init()` - Create empty treecode (just marker bit)
- `treecode_init_word()` - Initialize from a single 64-bit word
- `treecode_deinit()` - Free treecode memory
- `treecode_clone()` - Create a deep copy

### Manipulation
- `treecode_append()` - Add a direction (left/right) to the path
- `treecode_realloc()` - Grow capacity (usually automatic)

### Queries
- `treecode_is_prefix_of()` - Check if one treecode is ancestor of another
- `treecode_eql()` - Check equality by value
- `treecode_path_exists()` - Check if monotonic path exists between two codes
- `treecode_next_step_towards()` - Find next direction from source to dest
- `treecode_hash()` - Compute hash for use in hash tables

### Memory Management

The library uses a simple allocator interface:

```c
typedef struct {
    void* (*alloc)(void* ctx, size_t size);
    void* (*realloc)(void* ctx, void* ptr, size_t old_size, size_t new_size);
    void (*free)(void* ctx, void* ptr, size_t size);
    void* ctx;
} Treecode_Allocator;

// Standard malloc-based allocator provided
extern Treecode_Allocator TREECODE_STD_ALLOCATOR;
```

## Architecture

- **treecode.h** - Core treecode implementation (header-only)
- **binary_tree.h** - Binary tree container with treecode addressing
- **treecode_lib.h** - Main library entry point
- **tests/** - Comprehensive test suite

The implementation is header-only with all functions `static inline` for maximum performance.

### BinaryTree

The BinaryTree is a specialized container that uses treecodes for node addressing. Features:

- **Efficient path computation**: O(n) where n is path length, not tree size
- **Fast lookups**: Hash-based node-to-index mapping
- **Flexible structure**: Nodes can be added in any order
- **Low overhead**: Structure-of-Arrays layout

Current implementation is monomorphic (specialized for a simple node type), but can be extended for domain-specific types like `TemporalSpaceNode` when porting OpenTimelineIO components.

## Testing

**Treecode tests** (12 test cases):
- Code length measurement
- Append operations (single/multi-word)
- Prefix checking
- Equality and hashing
- Path navigation
- Clone operations

**BinaryTree tests** (5 test cases):
- Tree construction with parent/child relationships
- Path computation between nodes
- Root node access
- Index and code lookup
- Edge cases (reversed paths, single-node paths)

All 17 tests pass with comprehensive coverage.

---

## Appendix: Port Strategy and Comparison to Zig Source

### Port Strategy

#### 1. **Language Standards & Tooling**
- **Target**: C17 (ISO/IEC 9899:2017)
- **Build System**: CMake 3.17+
- **Compiler Flags**: All warnings enabled, warnings are fatal
- **Dependencies**: Standard library only (`stdlib.h`, `string.h`, `stdint.h`)

#### 2. **Memory Management**
- **Allocator Pattern**: Function pointer-based allocator interface
- **Default Allocator**: Standard `malloc`/`realloc`/`free` wrapper provided
- **Ownership**: Caller owns treecode memory, must call `deinit()`
- **Reallocation**: Dynamic growth when appending beyond current capacity

#### 3. **Type System Mapping**

| Zig Construct | C17 Equivalent | Notes |
|---------------|----------------|-------|
| `u64` | `uint64_t` | TreecodeWord base type |
| `usize` | `size_t` | Code lengths, capacities |
| `std.mem.Allocator` | `Treecode_Allocator*` | Function pointer interface |
| Slices `[]T` | Pointer + length | Manual size tracking |
| Error unions `!T` | `bool` return + out-param | Common C pattern |

#### 4. **Key Differences from Zig Source**

**Zig (Allocator Parameter)**:
```zig
pub fn append(
    self: *@This(),
    allocator: std.mem.Allocator,
    new_branch: l_or_r,
) !void
{
    // ...
}
```

**C (Allocator Pointer)**:
```c
static inline bool treecode_append(
    Treecode* self,
    Treecode_Allocator* allocator,
    Treecode_LorR new_branch
) {
    // Returns false on allocation failure
}
```

**Rationale**: C doesn't have error unions, so we use bool return + out-parameters.

#### 5. **Binary Literals**

**Zig**:
```zig
const MARKER: TreecodeWord = 0b1;
```

**C**:
```c
#define TREECODE_MARKER ((TreecodeWord)1)  // or 0x1
```

**Rationale**: Binary literals (`0b1`) are C23 only. We use hex or decimal for C17.

#### 6. **Bit Operations**

Both Zig and C use similar bit manipulation:
- `@clz()` → `__builtin_clzll()` (GCC/Clang intrinsic)
- `@bitSizeOf()` → `sizeof(T) * 8`
- Bitwise ops (`<<`, `>>`, `&`, `|`) are identical

#### 7. **Inline Functions**

**Zig**: Functions are aggressively inlined by default

**C**: All functions marked `static inline` for similar behavior
- `static` ensures no symbol conflicts across translation units
- `inline` provides inlining hint to compiler

### Lines of Code Comparison

| Component | Zig (LOC) | C (LOC) | Notes |
|-----------|-----------|---------|-------|
| treecode.zig | 1,532 | ~480 | Includes ~900 lines of tests in Zig |
| binary_tree.zig | 881 | ~550 | Ported with monomorphic node type |
| root.zig | 24 | ~10 | Entry point |
| **Tests** | (inline) | ~400 | C separates tests into dedicated files |
| **Total** | ~1,400 | ~1,030 | Core implementations |

**Note**: The Zig source includes extensive inline tests. The C port separates tests into dedicated files, making direct comparison difficult. The core treecode implementation is slightly more compact in C due to less generic abstraction.

### What's Ported

1. **✅ Treecode** - Binary path encoding (~480 LOC)
2. **✅ BinaryTree** - Monomorphic tree container (~550 LOC)
   - Specialized for simple node types
   - Includes basic hash map for node lookups
   - All core functionality working

### What's Not Ported (Yet)

1. **TreecodeHashMap** - Standalone HashMap wrapper for treecode keys
   - BinaryTree includes an internal hash map
   - Standalone version not needed yet

2. **Graphviz Export** - DOT file generation for visualization
   - Would require string formatting utilities
   - Can be added if needed for debugging

3. **Generic BinaryTree** - Template-style implementation
   - Current version is monomorphic (single node type)
   - Can be extended with macros if multiple node types are needed

### Design Decisions

1. **Why Header-Only?**
   - Matches Zig's inline-heavy design
   - Allows aggressive compiler optimization
   - Simplifies distribution (just copy headers)
   - No ABI concerns for a low-level library

2. **Why Custom Allocator Interface?**
   - Allows arena allocators for batch operations
   - Matches Zig's explicit allocator pattern
   - Enables custom memory tracking/debugging
   - Standard malloc/free still available as default

3. **Why `bool` Return + Out-Parameters?**
   - C has no error unions
   - Common idiom for fallible operations
   - Matches stdlib conventions (`strtol`, etc.)
   - Clear separation of success/failure vs. result value

4. **Why Monomorphic BinaryTree?**
   - Zig version uses generics: `BinaryTree(NodeType)`
   - In practice, only one node type is used: `TemporalSpaceNode`
   - Monomorphic C implementation is simpler and type-safe
   - Current version uses a simple test node type
   - Can be extended for domain-specific types without macros
   - Avoids complexity of void pointers or macro-based generics

### Performance Characteristics

Both implementations should have similar performance:

| Operation | Complexity | Notes |
|-----------|------------|-------|
| `init()` | O(1) | Single allocation |
| `append()` | Amortized O(1) | Realloc when capacity exceeded |
| `is_prefix_of()` | O(n) | n = words in shorter treecode |
| `eql()` | O(n) | n = words needed for code length |
| `hash()` | O(n) | n = non-zero words |
| `next_step_towards()` | O(1) | Simple bit test |

### Future Work

1. ✅ ~~Port `BinaryTree`~~ - Complete!
2. Extend BinaryTree for OpenTimelineIO types (`TemporalSpaceNode`)
3. Add CMake option for custom allocators (arena, pool, etc.)
4. Consider x86 SIMD for multi-word treecode operations
5. Add fuzz testing for edge cases (very long paths, etc.)
6. Optional: Graphviz export for tree visualization

---

## Conclusion

This C port faithfully reproduces both the treecode encoding and binary tree container from Zig while adapting to C's idioms. All tests pass, and the implementation is production-ready for use in C or C++ projects requiring efficient binary tree path encoding and navigation.

The monomorphic BinaryTree implementation provides all the core functionality of the Zig version while maintaining type safety and simplicity. When porting OpenTimelineIO components, the node type can be extended to `TemporalSpaceNode` without requiring generic programming constructs.
