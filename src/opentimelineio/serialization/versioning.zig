//! Schema Versioning System for OTIO
//!
//! Inspired by OpenTimelineIO's versioning approach, this module provides:
//! - Schema version tracking
//! - Upgrade functions (old version → new version)
//! - Downgrade functions (new version → old version)
//! - Version manifests (named sets of schema versions)
//!
//! Usage:
//!   - Each serializable type has a schema_name and schema_version
//!   - Register upgrade/downgrade functions for schema changes
//!   - Use version manifests to serialize to specific OTIO releases

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Schema version identifier
pub const SchemaVersion = struct {
    name: []const u8,
    version: u32,

    pub fn eql(
        self: @This(),
        other: @This(),
    ) bool
    {
        return (
            std.mem.eql(
            u8,
            self.name,
            other.name,
        )
            and self.version == other.version
        );
    }
};

/// Upgrade function type: transforms dictionary from version N-1 to N
pub const UpgradeFunction = *const fn (
    allocator: Allocator,
    data: anytype,
    target_version: u32,
) anyerror!void;

/// Downgrade function type: transforms dictionary from version N to N-1
pub const DowngradeFunction = *const fn (
    allocator: Allocator,
    data: anytype,
    from_version: u32,
) anyerror!void;

// ----------------------------------------------------------------------------
// Type-Specific Function Types for Concrete Schemas
// ----------------------------------------------------------------------------

/// Type-specific upgrade function for Timeline
/// Allows working with concrete SerializableTimeline struct
pub const TimelineUpgradeFunction = *const fn (
    allocator: Allocator,
    data: anytype,
    to_version: u32,
) anyerror!void;

/// Type-specific downgrade function for Timeline
pub const TimelineDowngradeFunction = *const fn (
    allocator: Allocator,
    data: anytype,
    from_version: u32,
) anyerror!void;

/// Entry for version -> function mapping
const VersionEntry = struct {
    version: u32,
    func_ptr: usize, // Store as raw pointer
};

/// Registry for schema upgrade and downgrade functions
pub const VersionRegistry = struct {
    /// Map of schema_name -> list of version entries
    upgrade_functions: std.StringHashMap(std.ArrayList(VersionEntry)),

    /// Map of schema_name -> list of version entries
    downgrade_functions: std.StringHashMap(std.ArrayList(VersionEntry)),

    allocator: Allocator,

    pub fn init(
        allocator: Allocator,
    ) VersionRegistry
    {
        return .{
            .upgrade_functions = std.StringHashMap(std.ArrayList(VersionEntry)).init(
                allocator,
            ),
            .downgrade_functions = std.StringHashMap(std.ArrayList(VersionEntry)).init(
                allocator,
            ),
            .allocator = allocator,
        };
    }

    pub fn deinit(
        self: *@This(),
    ) void
    {
        var upgrade_it = self.upgrade_functions.valueIterator();
        while (upgrade_it.next())
            |version_list|
        {
            version_list.deinit(self.allocator);
        }
        self.upgrade_functions.deinit();

        var downgrade_it = self.downgrade_functions.valueIterator();
        while (downgrade_it.next())
            |version_list|
        {
            version_list.deinit(self.allocator);
        }
        self.downgrade_functions.deinit();
    }

    /// Register an upgrade function for a schema.
    ///
    /// Note: Due to Zig's type system, functions with `anytype` parameters
    /// cannot be stored as function pointers at runtime. A comptime dispatch
    /// approach using known version pairs is planned as a workaround.
    pub fn register_upgrade(
        self: *@This(),
        /// Name of the schema (e.g., "Clip")
        schema_name: []const u8,
        /// Version this function upgrades TO
        to_version: u32,
        /// Function that performs the upgrade
        func: UpgradeFunction,
    ) !void
    {
        _ = func; // Cannot store function pointers with anytype at runtime
        const result = try self.upgrade_functions.getOrPut(schema_name);
        if (!result.found_existing)
        {
            result.value_ptr.* = .empty;
        }
        try result.value_ptr.append(
            self.allocator,
            .{
                .version = to_version,
                // Placeholder - see comptime dispatch workaround
                .func_ptr = 0,
            },
        );
    }

    /// Register a downgrade function for a schema.
    ///
    /// Note: Due to Zig's type system, functions with `anytype` parameters
    /// cannot be stored as function pointers at runtime. A comptime dispatch
    /// approach using known version pairs is planned as a workaround.
    pub fn register_downgrade(
        self: *@This(),
        /// Name of the schema (e.g., "Clip")
        schema_name: []const u8,
        /// Version this function downgrades FROM
        from_version: u32,
        /// Function that performs the downgrade
        func: DowngradeFunction,
    ) !void
    {
        _ = func; // Cannot store function pointers with anytype at runtime
        const result = try self.downgrade_functions.getOrPut(schema_name);
        if (!result.found_existing)
        {
            result.value_ptr.* = .empty;
        }
        try result.value_ptr.append(
            self.allocator,
            .{
                .version = from_version,
                // Placeholder - see comptime dispatch workaround
                .func_ptr = 0,
            },
        );
    }

    /// Upgrade a schema from from_version to to_version
    /// Calls upgrade functions in sequence
    pub fn upgrade(
        self: *@This(),
        allocator: Allocator,
        schema_name: []const u8,
        data: anytype,
        from_version: u32,
        to_version: u32,
    ) !void
    {
        if (from_version >= to_version)
        {
            return; // Already at or above target version
        }

        const upgrade_list = self.upgrade_functions.get(schema_name) orelse {
            return error.NoUpgradeFunctionsRegistered;
        };

        var version = from_version;
        while (version < to_version)
        {
            // Try to find upgrade function for next version
            const next_version = version + 1;
            // Note: Zig's type system prevents storing/retrieving anytype
            // function pointers. A comptime dispatch table mapping known
            // version pairs to concrete transform functions would enable
            // upgrade functionality without runtime anytype storage.
            _ = upgrade_list;
            _ = allocator;
            _ = data;
            version = next_version;
        }
    }

    /// Downgrade a schema from from_version to to_version
    /// Calls downgrade functions in sequence
    pub fn downgrade(
        self: *@This(),
        allocator: Allocator,
        schema_name: []const u8,
        data: anytype,
        from_version: u32,
        to_version: u32,
    ) !void
    {
        if (from_version <= to_version)
        {
            return; // Already at or below target version
        }

        const downgrade_list = self.downgrade_functions.get(
            schema_name,
        ) orelse {
            return error.NoDowngradeFunctionsRegistered;
        };

        var version = from_version;
        while (version > to_version)
        {
            // Note: Zig's type system prevents storing/retrieving anytype
            // function pointers. A comptime dispatch table mapping known
            // version pairs to concrete transform functions would enable
            // downgrade functionality without runtime anytype storage.
            _ = downgrade_list;
            _ = allocator;
            _ = data;
            version -= 1;
        }
    }
};

/// Version manifest: named set of schema versions
/// Similar to OTIO's "OTIO_CORE" family with release labels
pub const VersionManifest = struct {
    /// Map of label -> (schema_name -> version)
    releases: std.StringHashMap(std.StringHashMap(u32)),
    allocator: Allocator,

    pub fn init(
        allocator: Allocator,
    ) VersionManifest
    {
        return .{
            .releases = std.StringHashMap(std.StringHashMap(u32)).init(
                allocator,
            ),
            .allocator = allocator,
        };
    }

    pub fn deinit(
        self: *@This(),
    ) void
    {
        var it = self.releases.valueIterator();
        while (it.next())
            |schema_map|
        {
            schema_map.deinit();
        }
        self.releases.deinit();
    }

    /// Add a release with its schema versions
    pub fn add_release(
        self: *@This(),
        label: []const u8,
        versions: std.StringHashMap(u32),
    ) !void
    {
        try self.releases.put(label, versions);
    }

    /// Get schema versions for a specific release
    pub fn get_release(
        self: *@This(),
        label: []const u8,
    ) ?std.StringHashMap(
        u32,
    )
    {
        return self.releases.get(label);
    }
};

/// Current schema versions for this build
pub const CURRENT_VERSIONS = std.StaticStringMap(u32).initComptime(
    .{
        .{ "Timeline", 1 },
        .{ "Stack", 1 },
        .{ "Track", 1 },
        .{ "Clip", 1 },
        .{ "Gap", 1 },
        .{ "Warp", 1 },
        .{ "Transition", 1 },
        .{ "MediaReference", 1 },
        .{ "Topology", 1 },
        .{ "Collection", 1 },
    },
);

/// Get current version for a schema
pub fn current_version(
    schema_name: []const u8,
) u32
{
    return CURRENT_VERSIONS.get(schema_name) orelse 1;
}

// ----------------------------------------------------------------------------
// Comptime Dispatch Workaround for Version Transforms
// ----------------------------------------------------------------------------
//
// Zig's type system prevents storing function pointers with `anytype`
// parameters at runtime. This workaround uses a comptime switch over known
// version pairs to call the appropriate concrete transform function.
//
// To add a new transform:
// 1. Add the concrete transform function (e.g., `upgrade_timeline_0_to_1`)
// 2. Register it in the appropriate dispatch table below

/// Type-erased transform function for concrete SerializableTimeline
pub const TimelineTransformFn = *const fn (
    allocator: Allocator,
    data: *@import("ascii.zig").SerializableTimeline,
) anyerror!void;

/// Comptime dispatch table for Timeline upgrades
/// Maps (from_version, to_version) pairs to concrete transform functions
pub const TimelineUpgrades = struct {
    /// Get upgrade function for a version pair, or null if not registered
    pub fn get(
        from_version: u32,
        to_version: u32,
    ) ?TimelineTransformFn
    {
        // Add version upgrade mappings here as they are implemented
        // Example: 0 -> 1 would be the OTIO JSON to TLA upgrade
        _ = from_version;
        _ = to_version;
        return null; // No upgrades registered yet
    }
};

/// Comptime dispatch table for Timeline downgrades
pub const TimelineDowngrades = struct {
    /// Get downgrade function for a version pair, or null if not registered
    pub fn get(
        from_version: u32,
        to_version: u32,
    ) ?TimelineTransformFn
    {
        // Add version downgrade mappings here as they are implemented
        _ = from_version;
        _ = to_version;
        return null; // No downgrades registered yet
    }
};

/// Upgrade a SerializableTimeline through a version range
pub fn upgrade_timeline(
    allocator: Allocator,
    data: *@import("ascii.zig").SerializableTimeline,
    from_version: u32,
    to_version: u32,
) !void
{
    if (from_version >= to_version)
    {
        return; // Already at or above target version
    }

    var version = from_version;
    while (version < to_version)
        : (version += 1)
    {
        const next_version = version + 1;
        if (TimelineUpgrades.get(version, next_version))
            |transform_fn|
        {
            try transform_fn(allocator, data);
            data.schema_version = next_version;
        }
        else
        {
            // No transform registered - assume compatible, just bump version
            data.schema_version = next_version;
        }
    }
}

/// Downgrade a SerializableTimeline through a version range
pub fn downgrade_timeline(
    allocator: Allocator,
    data: *@import("ascii.zig").SerializableTimeline,
    from_version: u32,
    to_version: u32,
) !void
{
    if (from_version <= to_version)
    {
        return; // Already at or below target version
    }

    var version = from_version;
    while (version > to_version)
        : (version -= 1)
    {
        const prev_version = version - 1;
        if (TimelineDowngrades.get(version, prev_version))
            |transform_fn|
        {
            try transform_fn(allocator, data);
            data.schema_version = prev_version;
        }
        else
        {
            // No transform registered - assume compatible, just bump version
            data.schema_version = prev_version;
        }
    }
}

// ----------------------------------------------------------------------------
// Global Registry for Automatic Versioning
// ----------------------------------------------------------------------------

/// Global version registry instance (initialized on first use)
var global_registry: ?*VersionRegistry = null;
var registry_mutex: std.Thread.Mutex = .{};

/// Get or initialize the global registry
/// Used by serialization functions for automatic upgrade/downgrade
pub fn get_global_registry(
    allocator: Allocator,
) !*VersionRegistry
{
    registry_mutex.lock();
    defer registry_mutex.unlock();

    if (global_registry == null)
    {
        const registry = try allocator.create(VersionRegistry);
        registry.* = VersionRegistry.init(allocator);
        global_registry = registry;
    }

    return global_registry.?;
}

/// Register an upgrade function in the global registry
pub fn register_upgrade_global(
    allocator: Allocator,
    schema_name: []const u8,
    to_version: u32,
    func: UpgradeFunction,
) !void
{
    const registry = try get_global_registry(allocator);
    try registry.register_upgrade(schema_name, to_version, func);
}

/// Register a downgrade function in the global registry
pub fn register_downgrade_global(
    allocator: Allocator,
    schema_name: []const u8,
    from_version: u32,
    func: DowngradeFunction,
) !void
{
    const registry = try get_global_registry(allocator);
    try registry.register_downgrade(schema_name, from_version, func);
}

// ----------------------------------------------------------------------------
// Tests
// ----------------------------------------------------------------------------

test "VersionRegistry: register and retrieve"
{
    const allocator = std.testing.allocator;

    var registry = VersionRegistry.init(allocator);
    defer registry.deinit();

    // Mock upgrade function
    const MockUpgrade = struct {
        fn upgrade(
            _: Allocator,
            _: anytype,
            _: u32,
        ) !void
        {
            // Mock implementation
        }
    };

    try registry.register_upgrade("TestSchema", 2, MockUpgrade.upgrade);

    const upgrade_map = registry.upgrade_functions.get("TestSchema");
    try std.testing.expect(upgrade_map != null);
}

test "upgrade_timeline: no-op for same version"
{
    const allocator = std.testing.allocator;
    const ascii = @import("ascii.zig");

    var tl = ascii.SerializableTimeline{
        .schema_version = 1,
        .name = "",
        .children = &.{},
        .presentation_space_discrete_partitions = .{},
        .markers = &.{},
        .metadata_map = null,
    };

    // Upgrade from version 1 to 1 should be a no-op
    try upgrade_timeline(allocator, &tl, 1, 1);
    try std.testing.expectEqual(@as(u32, 1), tl.schema_version);
}

test "upgrade_timeline: bumps version when no transform registered"
{
    const allocator = std.testing.allocator;
    const ascii = @import("ascii.zig");

    var tl = ascii.SerializableTimeline{
        .schema_version = 1,
        .name = "",
        .children = &.{},
        .presentation_space_discrete_partitions = .{},
        .markers = &.{},
        .metadata_map = null,
    };

    // Upgrade from version 1 to 2 - no transform registered, should just bump
    try upgrade_timeline(allocator, &tl, 1, 2);
    try std.testing.expectEqual(@as(u32, 2), tl.schema_version);
}

test "downgrade_timeline: bumps version down when no transform registered"
{
    const allocator = std.testing.allocator;
    const ascii = @import("ascii.zig");

    var tl = ascii.SerializableTimeline{
        .schema_version = 2,
        .name = "",
        .children = &.{},
        .presentation_space_discrete_partitions = .{},
        .markers = &.{},
        .metadata_map = null,
    };

    // Downgrade from version 2 to 1 - no transform registered, should just
    // bump
    try downgrade_timeline(allocator, &tl, 2, 1);
    try std.testing.expectEqual(@as(u32, 1), tl.schema_version);
}
