# Wrinkles Zig Code Style Guide

This style guide documents the conventions used in the Wrinkles codebase.

## File Organization

### File Headers
- Start files with a `//!` documentation comment describing the file's purpose
- Example:
  ```zig
  //! Continuous Interval definition/Implementation
  ```

### Import Organization
- Standard library imports first (`std`)
- Local imports after standard library
- Blank line between imports and code
- Example:
  ```zig
  const std = @import("std");

  const ordinate = @import("ordinate.zig");
  const interval = @import("interval.zig");
  ```

## Naming Conventions

### Types
- **PascalCase** for types, structs, enums
  - Examples: `ContinuousInterval`, `AffineTransform1D`, `Treecode`
- Compound names use clear, descriptive words
  - `TreecodeWord`, `MappingAffine`, `ControlPoint`

### Functions and Methods
- **snake_case** for all functions and methods
  - Examples: `init()`, `applied_to_ordinate()`, `split_at_input_point()`
- Use descriptive verb-based names
  - `project_instantaneous_cc()`, `trim_in_input_space()`

### Variables
- **snake_case** for local variables
  - `input_bounds`, `result_mappings`, `target_word`
- Descriptive names over brevity
  - `maybe_bounds` instead of `mb`
  - `current_child_index` instead of `idx`

### Constants
- **SCREAMING_SNAKE_CASE** for compile-time constants
  - Examples: `ZERO`, `ONE`, `INF`, `EPSILON`, `MARKER`, `WORD_BIT_COUNT`
- Module-level constants: `EMPTY`, `IDENTITY`, `INFINITE_IDENTITY`

### Type Prefixes
- `maybe_` prefix for optional values
  - `maybe_name: ?string.latin_s8`
  - `maybe_bounds: ?ContinuousInterval`

## Indentation and Formatting

### Basic Rules
- **4 spaces** per indentation level (no tabs)
- **80 characters** maximum line length (soft limit)
  - Break long lines at logical points
  - Function parameters on separate lines if signature exceeds 80 chars
  - Long string literals and comments can exceed if necessary
- Opening brace on same line as declaration
- Closing brace aligned with opening statement

### Function Definitions
```zig
pub fn function_name(
    self: @This(),
    parameter: Type,
) ReturnType
{
    // function body
}
```

- **Each parameter on its own line** (always, even for single parameter)
- **Parameter format**: `name: Type` - colon immediately after name, space before type
  - ✅ Correct: `self: @This(),`
  - ❌ Incorrect: `self : @This(),` (space before colon)
  - ❌ Incorrect: `self:@This(),` (no space after colon)
- Opening paren on same line as function name
- **Closing paren on its own line** with return type
- Opening brace on new line after return type
- This applies to all functions, including those with zero or one parameter

Examples:
```zig
// Single parameter
pub fn init(
    allocator: std.mem.Allocator,
) !@This()

// Multiple parameters
pub fn create(
    allocator: std.mem.Allocator,
    name: []const u8,
    bounds: ContinuousInterval,
) !*Timeline

// Method with self
pub fn extents(
    self: @This(),
) opentime.ContinuousInterval

// No parameters (rare, but follows same pattern)
pub fn get_default()
    SomeType
```

### Struct Definitions
```zig
pub const StructName = struct {
    field_name: Type = default_value,
    another_field: Type,

    pub fn method(
        self: @This(),
        param: Type,
    ) ReturnType
    {
        // method body
    }
};
```

### Control Flow
```zig
// If statements
if (condition)
{
    // body
}
else if (other_condition)
{
    // body
}
else
{
    // body
}

// For loops - single item per line
for (items)
    |item|
{
    // body
}

// Multiple iteration variables
for (items, 0..)
    |item, index|
{
    // body
}

// While loops
while (condition)
    : (increment)
{
    // body
}
```

### Switch Statements
```zig
return switch (value) {
    .variant_one => result_one,
    .variant_two => {
        // multi-line body
        const computed = compute();
        break :label computed;
    },
    else => default_result,
};
```

## Documentation

### Doc Comments
- Use `///` for public API documentation
- Use `//!` for file/module level documentation
- Document all public functions, types, and fields
- Example:
  ```zig
  /// Right open interval in a continuous metric space.  Default interval starts
  /// at 0 and has no end.
  pub const ContinuousInterval = struct {
      /// the start ordinate of the interval, inclusive
      start: ordinate.Ordinate = ordinate.Ordinate.ZERO,

      /// the end ordinate of the interval, exclusive
      end: ordinate.Ordinate = ordinate.Ordinate.INF,
  ```

### Implementation Comments
- Use `//` for inline comments
- Place on separate line above code being explained
- Explain "why" not "what" when the what is obvious
- Example:
  ```zig
  // move the marker one index over
  const new_marker_word = new_marker_bit_index / WORD_BIT_COUNT;
  ```

### Section Dividers
- Use `// ----` with exactly 76 hyphens (total 80 chars including `// `)
- Mark major sections within files
- Example:
  ```zig
  // ----------------------------------------------------------------------------
  // Helper Functions
  // ----------------------------------------------------------------------------
  ```

## Type Definitions

### Struct Fields
- Public fields first, then private
- Fields with defaults should show the default value
- Use `?Type` for optional fields with `maybe_` prefix
- Example:
  ```zig
  pub const Clip = struct {
      maybe_name: ?string.latin_s8 = null,
      maybe_bounds_s: ?opentime.ContinuousInterval = null,
      media: MediaReference,
  };
  ```

### Enums
- Simple enum values: lowercase
- Tagged union variants: lowercase
- Example:
  ```zig
  pub const l_or_r = enum(u1) { left = 0, right = 1 };

  pub const MediaDataReference = union(enum) {
      external: ExternalReference,
      signal: SignalReference,
      empty: EmptyReference,
  };
  ```

## Functions and Methods

### Method Organization in Structs
1. Constants (ZERO, ONE, EMPTY, etc.)
2. Constructors (`init()`, `init_*()`)
3. Converters (`from_*()`, `to_*()`)
4. Core functionality
5. Utilities (`clone()`, `deinit()`, `format()`)

### Parameter Patterns
- `self: @This()` for instance methods
- `allocator: std.mem.Allocator` when memory allocation is needed
  - **Always first parameter** in free functions
  - **Always second parameter** (after `self`) in methods
- Use `anytype` sparingly, primarily for generic math operations

### Parameter Ordering
Function parameters should follow this order:
1. `self: @This()` (if method)
2. `allocator: std.mem.Allocator` (if needed)
3. Primary data parameters
4. Configuration/option parameters

Examples:
```zig
// Free function with allocator
pub fn create_timeline(
    allocator: std.mem.Allocator,
    name: []const u8,
) !*Timeline

// Method with allocator
pub fn clone(
    self: @This(),
    allocator: std.mem.Allocator,
) !@This()

// Free function without allocator
pub fn compute_duration(
    interval: ContinuousInterval,
) f64
```

### Return Types
- Use error unions `!Type` for operations that can fail
- Use optionals `?Type` for operations that may not have a result
- Document error conditions

### Memory Management
```zig
pub fn init(
    allocator: std.mem.Allocator,
    copy_from: Clip,
) !Clip
{
    // ... initialization
}

pub fn deinit(
    self: @This(),
    allocator: std.mem.Allocator,
) void
{
    // ... cleanup
}
```

## Testing

### Test Organization
- Place tests near the code they test
- Use descriptive test names with `test "description"`
- Format: `test "Module: specific_test_case"`
- Example:
  ```zig
  test "ContinuousInterval: is_infinite"
  {
      var cti = ContinuousInterval{};

      try std.testing.expectEqual(true, cti.is_infinite());
  }
  ```

### Test Structure
```zig
test "Bezier.Segment: can_project test"
{
    const half = Bezier.Segment.init_from_start_end(
        control_point.ControlPoint.init(.{ .in = -0.5, .out = -0.25, }),
        control_point.ControlPoint.init(.{ .in = 0.5, .out = 0.25, }),
    );

    try expectEqual(true, half.can_project(double));
}
```

### Test Data
- Use inline initialization for test data
- Structure test data with clear labels
- Example:
  ```zig
  const TestStruct = struct {
      fst: ContinuousInterval,
      snd: ContinuousInterval,
      res: bool,
  };
  const tests = [_]TestStruct{
      .{
          .fst = ContinuousInterval.init(.{ .start = 0, .end = 10, }),
          .snd = ContinuousInterval.init(.{ .start = 8, .end = 12, }),
          .res = true,
      },
  };
  ```

## Error Handling

### Error Handling Patterns
```zig
// Defer for cleanup
defer allocator.free(buffer);

// Error handling with context
errdefer std.log.err(
    "Failed at iteration {}: input={d}\n",
    .{ i, input }
);

// Returning errors
if (condition) {
    return error.OutOfBounds;
}

// Unwrapping with orelse
const value = maybe_value orelse return error.NotFound;
```

## Code Organization Patterns

### Inline Functions
- Use `inline` for small, frequently called functions
- Typically used for: accessors, simple math operations, type conversions
- Example:
  ```zig
  pub inline fn as(
      self: @This(),
      comptime T: type,
  ) T
  {
      return @floatCast(self.v);
  }
  ```

### Comptime
- Use `comptime` for compile-time known values
- Generic functions use `anytype` or `comptime T: type`
- Example:
  ```zig
  fn OrdinateOf(
      comptime t: type,
  ) type
  {
      return struct {
          v : t,
          // ...
      };
  }
  ```

### Anonymous Structs for Options
```zig
pub fn init(
    args: struct {
        start: Ordinate,
        end: Ordinate,
    },
) Interval
{
    return .{
        .start = args.start,
        .end = args.end,
    };
}
```

## Specific Patterns

### Builder Pattern
```zig
// Initialization with defaults
pub const MyStruct = struct {
    field_a: i32 = 0,
    field_b: bool = false,
};

// Usage
var instance: MyStruct = .{
    .field_a = 42,
};
```

### Iterator Pattern
```zig
for (collection, 0..)
    |item, index|
{
    errdefer std.log.err(
        "iteration: {} item: {any}\n",
        .{ index, item }
    );
    // process item
}
```

### Result Accumulation
```zig
var results: std.ArrayList(Type) = .{};
defer results.deinit(allocator);

for (items)
    |item|
{
    try results.append(allocator, process(item));
}

return try results.toOwnedSlice(allocator);
```

## Comments and Annotations

### TODO Comments
```zig
// @TODO: implement this feature
// @TODO: this function should compute and preserve derivatives
```

### Section Markers
```zig
//-----------------------------------------------------------------
// compute splits
//-----------------------------------------------------------------
```

### Inline For Metadata
```zig
inline for (
    &.{ "add", "sub", "mul", "div" },
    0..
) |op, index|
{
    // process each operation
}
```

## Whitespace

### Vertical Spacing
- Blank line between function definitions
- Blank line between logical sections within functions
- No blank lines within tightly related code blocks

### Horizontal Spacing
- Space after keywords (`if`, `for`, `while`)
- Space around binary operators (`=`, `+`, `*`)
- No space between function name and opening paren
- Space after comma in parameter lists

### Alignment
- Align field initializers vertically when appropriate
- Align similar lines for readability
- Example:
  ```zig
  .start = ordinate.Ordinate.ZERO,
  .end   = ordinate.Ordinate.INF,
  ```

## Module Structure

### Public API First
1. Type definitions
2. Public constants
3. Public functions
4. Implementation details (private)
5. Tests at end of file

### Namespace Organization
```zig
pub const topology_m = @import("topology");
pub const mapping = @import("mapping.zig");

pub const Topology = struct {
    // public API
};
```

## Best Practices

### Prefer Explicit Over Implicit
- Explicit type annotations when not obvious
- Explicit error handling
- Clear variable names

### Memory Safety
- Always pair `init()` with `deinit()`
- Use `defer` for resource cleanup immediately after allocation
- Use `errdefer` for error-path cleanup

### Performance
- Mark hot-path functions as `inline`
- Use `@branchHint(.likely)` for expected branches
- Pre-allocate when size is known: `try results.ensureTotalCapacity(allocator, size)`

### Error Messages
```zig
errdefer std.log.err(
    "\n  test: {s}\n  input: {any}\n  expected: {any}\n  actual: {any}\n",
    .{ test_name, input, expected, actual }
);
```

## Anti-Patterns to Avoid

### Don't
- ❌ Use tabs for indentation
- ❌ Use single-letter variable names (except loop indices)
- ❌ Omit documentation for public APIs
- ❌ Use `catch unreachable` without strong justification
- ❌ Nest deeply (>4 levels) - refactor into helper functions

### Do
- ✅ Use descriptive names
- ✅ Document public APIs
- ✅ Test edge cases
- ✅ Clean up resources properly
- ✅ Use error unions appropriately

---

This style guide is derived from the actual codebase patterns and should be followed for consistency across the project.
