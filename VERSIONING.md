# Schema Versioning in Wrinkles

## Overview

Wrinkles implements a schema versioning system inspired by OpenTimelineIO, allowing the library to read files from older versions and write files compatible with older versions. This ensures backward and forward compatibility across library releases.

## Key Concepts

### Schema Name and Version

Each serializable type has two metadata fields:
- `schema_name`: String identifying the type (e.g., "Timeline", "Clip")
- `schema_version`: Integer version number (starts at 1)

These fields are automatically included in serialized Ziggy files.

### Ziggy vs OpenTimelineIO Versioning

**Ziggy** (the serialization library) does **not** have built-in schema versioning. It's a format-level library similar to JSON - it serializes whatever structs you give it.

**Wrinkles** implements versioning **on top** of Ziggy, similar to how OpenTimelineIO implements versioning on top of JSON.

## How It Works

### Current Versions

The `versioning.zig` module defines current schema versions:

```zig
pub const CURRENT_VERSIONS = std.ComptimeStringMap(u32, .{
    .{ "Timeline", 1 },
    .{ "Stack", 1 },
    .{ "Track", 1 },
    .{ "Clip", 1 },
    .{ "Gap", 1 },
    .{ "Warp", 1 },
    .{ "Transition", 1 },
    .{ "MediaReference", 1 },
    .{ "Topology", 1 },
});
```

### Version Registry

The `VersionRegistry` manages upgrade and downgrade functions:

```zig
var registry = versioning.VersionRegistry.init(allocator);
defer registry.deinit();

// Register upgrade function (version 1 -> 2)
try registry.register_upgrade("Clip", 2, upgrade_clip_v1_to_v2);

// Register downgrade function (version 2 -> 1)
try registry.register_downgrade("Clip", 2, downgrade_clip_v2_to_v1);
```

### Upgrade Functions

Upgrade functions transform data from version N-1 to version N:

```zig
fn upgrade_clip_v1_to_v2(
    allocator: Allocator,
    data: anytype,
    target_version: u32,
) !void {
    // Example: rename field "my_field" to "new_field"
    // In practice, you'd manipulate the serializable struct
    _ = allocator;
    _ = data;
    _ = target_version;
}
```

**Key points:**
- Upgrade functions are called in sequence (1→2, 2→3, etc.)
- **Gaps are allowed**: If no function exists for version N, it's skipped
- Useful when adding optional fields with sensible defaults

### Downgrade Functions

Downgrade functions transform data from version N to version N-1:

```zig
fn downgrade_clip_v2_to_v1(
    allocator: Allocator,
    data: anytype,
    from_version: u32,
) !void {
    // Example: rename field "new_field" back to "my_field"
    _ = allocator;
    _ = data;
    _ = from_version;
}
```

**Key points:**
- Downgrade functions are called in sequence (3→2, 2→1, etc.)
- **No gaps allowed**: Every version must have a downgrade function
- Necessary for writing files compatible with older library versions

### Version Manifests

Version manifests group schema versions by release label:

```zig
var manifest = versioning.VersionManifest.init(allocator);
defer manifest.deinit();

// Define version set for "0.1.0" release
var v0_1_0 = std.StringHashMap(u32).init(allocator);
try v0_1_0.put("Timeline", 1);
try v0_1_0.put("Clip", 1);
try v0_1_0.put("Track", 1);
try manifest.add_release("0.1.0", v0_1_0);

// Later: retrieve versions for a specific release
const versions = manifest.get_release("0.1.0");
```

This allows you to write:
```zig
// Serialize timeline compatible with 0.1.0 release
try serialize_timeline(timeline, allocator, writer, versions);
```

## Example: Evolving a Schema

### Version 1: Initial Clip

```zig
pub const SerializableClip = struct {
    schema_name: []const u8 = "Clip",
    schema_version: u32 = 1,
    name: ?[]const u8,
    my_field: i64,
};
```

### Version 2: Renamed Field

```zig
pub const SerializableClip = struct {
    schema_name: []const u8 = "Clip",
    schema_version: u32 = 2,  // Bumped
    name: ?[]const u8,
    new_field: i64,  // Renamed from my_field
};

// Upgrade function
fn upgrade_clip_v1_to_v2(allocator: Allocator, data: *SerializableClip, _: u32) !void {
    // In actual implementation, you'd work with a dictionary-like structure
    // data.new_field = data.my_field;
    // remove my_field
    _ = allocator;
    _ = data;
}

// Downgrade function
fn downgrade_clip_v2_to_v1(allocator: Allocator, data: *SerializableClip, _: u32) !void {
    // data.my_field = data.new_field;
    // remove new_field
    _ = allocator;
    _ = data;
}
```

### Version 3: Added Optional Field

```zig
pub const SerializableClip = struct {
    schema_name: []const u8 = "Clip",
    schema_version: u32 = 3,  // Bumped again
    name: ?[]const u8,
    new_field: i64,
    extra_field: ?i64 = null,  // New optional field
};

// No upgrade function needed!
// V2 data without extra_field will use default (null)

// Downgrade function removes the new field
fn downgrade_clip_v3_to_v2(allocator: Allocator, data: *SerializableClip, _: u32) !void {
    // Simply ignore extra_field when serializing to v2
    _ = allocator;
    _ = data;
}
```

## When to Bump Versions

### Bump Version When:
- Renaming a field
- Changing a field's type
- Removing a required field
- Changing field semantics

### No Need to Bump When:
- Adding an optional field with a sensible default
- Adding internal methods that don't affect serialization
- Fixing bugs that don't change the wire format

## Comparison with OpenTimelineIO

| Feature | OpenTimelineIO | Wrinkles |
|---------|---------------|----------|
| **Format** | JSON | Ziggy |
| **Schema Metadata** | `OTIO_SCHEMA` field | `schema_name` + `schema_version` |
| **Upgrade Functions** | Dictionary → Dictionary | Serializable struct manipulation |
| **Downgrade Functions** | Dictionary → Dictionary | Serializable struct manipulation |
| **Version Manifests** | Family→Label→Versions | Label→Versions |
| **Gap Handling** | Upgrades: yes, Downgrades: no | Same |
| **Environment Variable** | `OTIO_DEFAULT_TARGET_VERSION_FAMILY_LABEL` | Not yet implemented |

## Future Work

- [ ] Implement automatic upgrade during deserialization
- [ ] Implement downgrade option in serialize functions
- [ ] Add environment variable support
- [ ] Create version manifest for each release
- [ ] Add CLI tool for converting between versions
- [ ] Document upgrade/downgrade patterns for each schema

## Benefits

1. **Backward Compatibility**: Read files from older library versions
2. **Forward Compatibility**: Write files for older library versions
3. **Gradual Migration**: Upgrade schemas incrementally across releases
4. **Interoperability**: Different tools with different library versions can exchange files
5. **Archive Longevity**: Old files remain readable indefinitely

## Resources

- [OpenTimelineIO Versioning Documentation](https://github.com/AcademySoftwareFoundation/OpenTimelineIO/blob/main/docs/tutorials/versioning-schemas.md)
- [Ziggy Documentation](https://ziggy-lang.io)
- `src/opentimelineio/versioning.zig` - Implementation
- `src/opentimelineio/serialization.zig` - Serializable types with versions
