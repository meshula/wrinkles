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

    pub fn eql(self: @This(), other: @This()) bool {
        return std.mem.eql(u8, self.name, other.name) and self.version == other.version;
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

/// Registry for schema upgrade and downgrade functions
pub const VersionRegistry = struct {
    /// Map of schema_name -> version -> upgrade function
    upgrade_functions: std.StringHashMap(std.AutoHashMap(u32, UpgradeFunction)),

    /// Map of schema_name -> version -> downgrade function
    downgrade_functions: std.StringHashMap(std.AutoHashMap(u32, DowngradeFunction)),

    allocator: Allocator,

    pub fn init(allocator: Allocator) VersionRegistry {
        return .{
            .upgrade_functions = std.StringHashMap(std.AutoHashMap(u32, UpgradeFunction)).init(allocator),
            .downgrade_functions = std.StringHashMap(std.AutoHashMap(u32, DowngradeFunction)).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *@This()) void {
        var upgrade_it = self.upgrade_functions.valueIterator();
        while (upgrade_it.next()) |version_map| {
            version_map.deinit();
        }
        self.upgrade_functions.deinit();

        var downgrade_it = self.downgrade_functions.valueIterator();
        while (downgrade_it.next()) |version_map| {
            version_map.deinit();
        }
        self.downgrade_functions.deinit();
    }

    /// Register an upgrade function for a schema
    /// @param schema_name: Name of the schema (e.g., "Clip")
    /// @param to_version: Version this function upgrades TO
    /// @param func: Function that performs the upgrade
    pub fn register_upgrade(
        self: *@This(),
        schema_name: []const u8,
        to_version: u32,
        func: UpgradeFunction,
    ) !void {
        const result = try self.upgrade_functions.getOrPut(schema_name);
        if (!result.found_existing) {
            result.value_ptr.* = std.AutoHashMap(u32, UpgradeFunction).init(self.allocator);
        }
        try result.value_ptr.put(to_version, func);
    }

    /// Register a downgrade function for a schema
    /// @param schema_name: Name of the schema (e.g., "Clip")
    /// @param from_version: Version this function downgrades FROM
    /// @param func: Function that performs the downgrade
    pub fn register_downgrade(
        self: *@This(),
        schema_name: []const u8,
        from_version: u32,
        func: DowngradeFunction,
    ) !void {
        const result = try self.downgrade_functions.getOrPut(schema_name);
        if (!result.found_existing) {
            result.value_ptr.* = std.AutoHashMap(u32, DowngradeFunction).init(self.allocator);
        }
        try result.value_ptr.put(from_version, func);
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
    ) !void {
        if (from_version >= to_version) {
            return; // Already at or above target version
        }

        const upgrade_map = self.upgrade_functions.get(schema_name) orelse {
            return error.NoUpgradeFunctionsRegistered;
        };

        var version = from_version;
        while (version < to_version) {
            // Try to find upgrade function for next version
            const next_version = version + 1;
            if (upgrade_map.get(next_version)) |upgrade_func| {
                try upgrade_func(allocator, data, next_version);
                version = next_version;
            } else {
                // No upgrade function for this version, skip it
                // OTIO allows gaps in upgrade functions
                version = next_version;
            }
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
    ) !void {
        if (from_version <= to_version) {
            return; // Already at or below target version
        }

        const downgrade_map = self.downgrade_functions.get(schema_name) orelse {
            return error.NoDowngradeFunctionsRegistered;
        };

        var version = from_version;
        while (version > to_version) {
            if (downgrade_map.get(version)) |downgrade_func| {
                try downgrade_func(allocator, data, version);
                version -= 1;
            } else {
                // Downgrade functions must not have gaps
                return error.MissingDowngradeFunction;
            }
        }
    }
};

/// Version manifest: named set of schema versions
/// Similar to OTIO's "OTIO_CORE" family with release labels
pub const VersionManifest = struct {
    /// Map of label -> (schema_name -> version)
    releases: std.StringHashMap(std.StringHashMap(u32)),
    allocator: Allocator,

    pub fn init(allocator: Allocator) VersionManifest {
        return .{
            .releases = std.StringHashMap(std.StringHashMap(u32)).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *@This()) void {
        var it = self.releases.valueIterator();
        while (it.next()) |schema_map| {
            schema_map.deinit();
        }
        self.releases.deinit();
    }

    /// Add a release with its schema versions
    pub fn add_release(
        self: *@This(),
        label: []const u8,
        versions: std.StringHashMap(u32),
    ) !void {
        try self.releases.put(label, versions);
    }

    /// Get schema versions for a specific release
    pub fn get_release(self: *@This(), label: []const u8) ?std.StringHashMap(u32) {
        return self.releases.get(label);
    }
};

/// Current schema versions for this build
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

/// Get current version for a schema
pub fn current_version(schema_name: []const u8) u32 {
    return CURRENT_VERSIONS.get(schema_name) orelse 1;
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

test "VersionRegistry: register and retrieve" {
    const allocator = std.testing.allocator;

    var registry = VersionRegistry.init(allocator);
    defer registry.deinit();

    // Mock upgrade function
    const MockUpgrade = struct {
        fn upgrade(_: Allocator, _: anytype, _: u32) !void {
            // Mock implementation
        }
    };

    try registry.register_upgrade("TestSchema", 2, MockUpgrade.upgrade);

    const upgrade_map = registry.upgrade_functions.get("TestSchema");
    try std.testing.expect(upgrade_map != null);
}
