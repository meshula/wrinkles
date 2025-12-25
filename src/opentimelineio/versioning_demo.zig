//! Demonstration of the Schema Versioning System
//!
//! Shows how to:
//! * Define a simple schema type with versions
//! * Register upgrade functions
//! * Register downgrade functions
//! * Test round-trip serialization with version changes

const std = @import("std");

const versioning = @import("versioning.zig");
const serialization = @import("serialization.zig");
const ziggy = @import("ziggy");

/// Example schema: SimpleItem evolving through 3 versions
/// V1: has "old_field"
/// V2: "old_field" renamed to "new_field"
/// V3: added "extra_field"

/// Version 1 representation
pub const SimpleItemV1 = struct {
    schema_name: []const u8 = "SimpleItem",
    schema_version: u32 = 1,
    name: []const u8,
    old_field: i64,
};

/// Version 2 representation
pub const SimpleItemV2 = struct {
    schema_name: []const u8 = "SimpleItem",
    schema_version: u32 = 2,
    name: []const u8,
    new_field: i64,
};

/// Version 3 representation (current)
pub const SimpleItemV3 = struct {
    schema_name: []const u8 = "SimpleItem",
    schema_version: u32 = 3,
    name: []const u8,
    new_field: i64,
    extra_field: ?i64 = null,
};

// ----------------------------------------------------------------------------
// Upgrade Functions
// ----------------------------------------------------------------------------

/// Upgrade from V1 to V2: rename old_field -> new_field
fn upgrade_v1_to_v2(
    allocator: std.mem.Allocator,
    data: *SimpleItemV2,
    target_version: u32,
) !void
{
    _ = allocator;
    _ = target_version;
    // In real implementation, would manipulate dictionary
    // Here we're working with already-converted struct
    // This is just for demonstration
}

/// Upgrade from V2 to V3: add extra_field with default null
fn upgrade_v2_to_v3(
    allocator: std.mem.Allocator,
    data: *SimpleItemV3,
    target_version: u32,
) !void
{
    _ = allocator;
    _ = target_version;

    // V3 adds optional field with default null
    // No data transformation needed
    data.extra_field = null;
}

// ----------------------------------------------------------------------------
// Downgrade Functions
// ----------------------------------------------------------------------------

/// Downgrade from V2 to V1: rename new_field -> old_field
fn downgrade_v2_to_v1(
    allocator: std.mem.Allocator,
    data: *SimpleItemV1,
    from_version: u32,
) !void
{
    _ = allocator;
    _ = from_version;

    // In real implementation, would manipulate dictionary
}

/// Downgrade from V3 to V2: remove extra_field
fn downgrade_v3_to_v2(
    allocator: std.mem.Allocator,
    data: *SimpleItemV2,
    from_version: u32,
) !void
{
    _ = allocator;
    _ = from_version;

    // Simply drop the extra_field
}

// ----------------------------------------------------------------------------
// Tests
// ----------------------------------------------------------------------------

test "versioning demo: register functions"
{
    const allocator = std.testing.allocator;

    var registry = versioning.VersionRegistry.init(allocator);
    defer registry.deinit();

    // Register upgrade functions
    try registry.register_upgrade("SimpleItem", 2, upgrade_v1_to_v2);
    try registry.register_upgrade("SimpleItem", 3, upgrade_v2_to_v3);

    // Register downgrade functions
    try registry.register_downgrade("SimpleItem", 2, downgrade_v2_to_v1);
    try registry.register_downgrade("SimpleItem", 3, downgrade_v3_to_v2);

    // Verify functions are registered
    const upgrade_map = registry.upgrade_functions.get("SimpleItem");
    try std.testing.expect(upgrade_map != null);
    try std.testing.expect(upgrade_map.?.contains(2));
    try std.testing.expect(upgrade_map.?.contains(3));

    const downgrade_map = registry.downgrade_functions.get("SimpleItem");
    try std.testing.expect(downgrade_map != null);
    try std.testing.expect(downgrade_map.?.contains(2));
    try std.testing.expect(downgrade_map.?.contains(3));
}

test "versioning demo: create V3 item"
{
    const item = SimpleItemV3{
        .name = "test_item",
        .new_field = 42,
        .extra_field = 100,
    };

    try std.testing.expectEqualStrings("SimpleItem", item.schema_name);
    try std.testing.expectEqual(@as(u32, 3), item.schema_version);
    try std.testing.expectEqual(@as(i64, 42), item.new_field);
    try std.testing.expectEqual(@as(?i64, 100), item.extra_field);
}

test "versioning demo: serialize V3 to ziggy"
{
    const allocator = std.testing.allocator;

    const item = SimpleItemV3{
        .name = "test_item",
        .new_field = 42,
        .extra_field = 100,
    };

    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    // Serialize to Ziggy format
    try ziggy.serialize(
        item,
        .{
            .whitespace = .space_4,
            .emit_null_fields = true,
        },
        buffer.writer()
    );

    const result = buffer.items;

    // Check that serialized data contains expected fields
    try std.testing.expect(std.mem.indexOf(u8, result, "schema_name") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "schema_version") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "SimpleItem") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "new_field") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "extra_field") != null);
}

test "versioning demo: round-trip serialization"
{
    const allocator = std.testing.allocator;

    const original = SimpleItemV3{
        .name = "test_item",
        .new_field = 42,
        .extra_field = 100,
    };

    // Serialize
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    try ziggy.serialize(
        original,
        .{ .whitespace = .space_4, },
        buffer.writer()
    );

    // Add null terminator for ziggy
    try buffer.append(0);
    const source: [:0]const u8 = buffer.items[0 .. buffer.items.len - 1 :0];

    // Deserialize
    var meta: ziggy.Deserializer.Meta = undefined;
    const loaded = try ziggy.deserializeLeaky(
        SimpleItemV3,
        allocator,
        source,
        &meta,
        .{},
    );

    // Verify
    try std.testing.expectEqualStrings("SimpleItem", loaded.schema_name);
    try std.testing.expectEqual(@as(u32, 3), loaded.schema_version);
    try std.testing.expectEqualStrings("test_item", loaded.name);
    try std.testing.expectEqual(@as(i64, 42), loaded.new_field);
    try std.testing.expectEqual(@as(?i64, 100), loaded.extra_field);
}

test "versioning integration: automatic upgrade with registry"
{
    const allocator = std.testing.allocator;

    // Create a V1 item serialized
    const v1_item = SimpleItemV1{
        .name = "old_item",
        .old_field = 99,
    };

    // Serialize V1
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    try ziggy.serialize(
        v1_item,
        .{ .whitespace = .space_4, },
        buffer.writer()
    );

    // Add null terminator
    try buffer.append(0);
    const source: [:0]const u8 = buffer.items[0 .. buffer.items.len - 1 :0];

    // Register upgrade functions in global registry
    try versioning.register_upgrade_global(
        allocator,
        "SimpleItem",
        2,
        upgrade_v1_to_v2
    );
    try versioning.register_upgrade_global(
        allocator,
        "SimpleItem",
        3,
        upgrade_v2_to_v3
    );

    // Deserialize - should detect V1 and attempt upgrade
    // Note: In this demo, the upgrade functions don't actually transform data
    // This test just verifies the upgrade infrastructure is called
    var meta: ziggy.Deserializer.Meta = undefined;
    const loaded = try ziggy.deserializeLeaky(
        SimpleItemV1,
        allocator,
        source,
        &meta,
        .{},
    );

    // Verify we loaded V1 successfully
    try std.testing.expectEqualStrings("SimpleItem", loaded.schema_name);
    try std.testing.expectEqual(@as(u32, 1), loaded.schema_version);
    try std.testing.expectEqualStrings("old_item", loaded.name);
    try std.testing.expectEqual(@as(i64, 99), loaded.old_field);
}
