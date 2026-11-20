//! Schema versioning for wrinkles files.
//!
//! The format carries a single schema version, stored on the root object
//! (timeline or collection).  Any change to the format, including to nested
//! types, bumps that one version.
//!
//! This module provides:
//! - `CURRENT_SCHEMA_VERSION`, the version this library reads and writes
//! - `DocumentUpgrades` / `DocumentDowngrades`: comptime tables of
//!   single-version steps on the whole document (`SerializableRoot`),
//!   checked for completeness at compile time
//! - `upgrade_with` / `downgrade_with`, which walk those tables

const std = @import("std");
const Allocator = std.mem.Allocator;

/// The schema version this library reads and writes.  Bump this, and add
/// the matching upgrade steps below, whenever the format changes.
pub const CURRENT_SCHEMA_VERSION: u32 = 1;

// ----------------------------------------------------------------------------
// Schema-Version Transform Tables
// ----------------------------------------------------------------------------
//
// Upgrades and downgrades are applied one version at a time, by walking a
// comptime table of single-version steps.  A chain from v0 to v2 runs the
// 0 -> 1 step and then the 1 -> 2 step; each step sees the output of the one
// before it.
//
// Every step is explicit: a step either names a transform function or is
// marked `.none` to say the data needs no changes.  Upgrade tables are
// checked at compile time to contain exactly one step for every version from
// the oldest readable version up to the current version, so
// forgetting a step fails the build instead of silently relabelling data.
//
// Data with a schema version newer than the current version is unreadable:
// the newer library must downgrade it before it is handed to this one.
//
// To add a schema version:
// 1. Bump `CURRENT_SCHEMA_VERSION`.
// 2. Add the `N-1 -> N` step to `DocumentUpgrades` (a transform, or
//    `.none`); a transform handles each root kind it affects.
// 3. Optionally add the `N -> N-1` step to `DocumentDowngrades`.

/// Errors produced when moving data between schema versions.
pub const VersionError = error{
    /// The data is newer than this library supports; it must be downgraded
    /// by a library that understands its version.
    SchemaVersionNewerThanSupported,
    /// No upgrade step is registered for a version in the requested range.
    UpgradeNotSupported,
    /// No downgrade step is registered for a version in the requested range.
    DowngradeNotSupported,
    /// A downgrade target is newer than the data's version.
    DowngradeTargetIsNewer,
};

/// Signature of a single-version transform on `Data`.
pub fn TransformFn(
    comptime Data: type,
) type
{
    return *const fn (
        allocator: Allocator,
        data: *Data,
    ) anyerror!void;
}

/// One single-version step in a transform table.
pub fn TransformStep(
    comptime Data: type,
) type
{
    return struct {
        from: u32,
        to: u32,
        change: Change,

        pub const Change = union(enum) {
            /// The step is known to need no changes to the data.
            none,
            /// Transform the data from `from` to `to`.
            transform: TransformFn(Data),
        };
    };
}

/// Direction of the steps in a transform table.
pub const Direction = enum { upgrade, downgrade };

/// A comptime table of single-version steps on `Data` (which must have a
/// `schema_version: u32` field).
pub fn TransformTable(
    comptime Data: type,
    comptime direction: Direction,
    comptime steps: []const TransformStep(Data),
) type
{
    return struct {
        pub const DataType = Data;
        pub const DIRECTION = direction;
        pub const STEPS = steps;

        /// The step from `from` to `to`, or null if none is registered.
        pub fn get(
            from: u32,
            to: u32,
        ) ?TransformStep(Data)
        {
            for (STEPS)
                |step|
            {
                if (step.from == from and step.to == to)
                {
                    return step;
                }
            }
            return null;
        }
    };
}

/// Describe what is wrong with `Table` as an upgrade table that reads data
/// from `oldest_version` up to `latest_version`, or return null if it is
/// valid.
///
/// A valid upgrade table has exactly one `v -> v+1` step for every `v` in
/// `oldest_version..latest_version`, and no other steps.  Data older than
/// `oldest_version` cannot be upgraded (`error.UpgradeNotSupported`).
pub fn upgrade_table_problem(
    comptime Table: type,
    comptime oldest_version: u32,
    comptime latest_version: u32,
) ?[]const u8
{
    comptime {
        if (Table.DIRECTION != .upgrade)
        {
            return "table is not an upgrade table";
        }
        for (Table.STEPS)
            |step|
        {
            if (step.to != step.from + 1)
            {
                return std.fmt.comptimePrint(
                    "upgrade step {d} -> {d} does not advance exactly one "
                    ++ "version",
                    .{ step.from, step.to },
                );
            }
            if (step.from < oldest_version)
            {
                return std.fmt.comptimePrint(
                    "upgrade step {d} -> {d} starts before the oldest "
                    ++ "readable version {d}",
                    .{ step.from, step.to, oldest_version },
                );
            }
            if (step.to > latest_version)
            {
                return std.fmt.comptimePrint(
                    "upgrade step {d} -> {d} goes past the current "
                    ++ "version {d}",
                    .{ step.from, step.to, latest_version },
                );
            }
        }
        for (oldest_version..latest_version)
            |v|
        {
            var count: usize = 0;
            for (Table.STEPS)
                |step|
            {
                if (step.from == v)
                {
                    count += 1;
                }
            }
            if (count != 1)
            {
                return std.fmt.comptimePrint(
                    "upgrade table must have exactly one {d} -> {d} step "
                    ++ "(found {d}); use `.none` if no data changes are "
                    ++ "needed",
                    .{ v, v + 1, count },
                );
            }
        }
        return null;
    }
}

/// Describe what is wrong with `Table` as a downgrade table for data whose
/// current version is `latest_version`, or return null if it is valid.
///
/// Downgrade tables need not reach version 0, but every step must go back
/// exactly one version, start at or below `latest_version`, and appear at
/// most once.
pub fn downgrade_table_problem(
    comptime Table: type,
    comptime latest_version: u32,
) ?[]const u8
{
    comptime {
        if (Table.DIRECTION != .downgrade)
        {
            return "table is not a downgrade table";
        }
        for (Table.STEPS, 0..)
            |step, i|
        {
            if (step.from != step.to + 1)
            {
                return std.fmt.comptimePrint(
                    "downgrade step {d} -> {d} does not go back exactly one "
                    ++ "version",
                    .{ step.from, step.to },
                );
            }
            if (step.from > latest_version)
            {
                return std.fmt.comptimePrint(
                    "downgrade step {d} -> {d} starts past the current "
                    ++ "version {d}",
                    .{ step.from, step.to, latest_version },
                );
            }
            for (Table.STEPS[i + 1 ..])
                |other|
            {
                if (other.from == step.from)
                {
                    return std.fmt.comptimePrint(
                        "downgrade step {d} -> {d} appears more than once",
                        .{ step.from, step.to },
                    );
                }
            }
        }
        return null;
    }
}

/// Upgrade `data` from its current `schema_version` to `to_version` by
/// applying each single-version step in `Table` in order.
///
/// Every step is checked to exist before any is applied.  If a transform
/// fails part way, `data` may be partially upgraded and should be discarded.
pub fn upgrade_with(
    comptime Table: type,
    allocator: Allocator,
    data: *Table.DataType,
    to_version: u32,
) !void
{
    comptime std.debug.assert(Table.DIRECTION == .upgrade);

    const from_version = data.schema_version;
    if (from_version > to_version)
    {
        return VersionError.SchemaVersionNewerThanSupported;
    }

    for (from_version..to_version)
        |v|
    {
        const version: u32 = @intCast(v);
        if (Table.get(version, version + 1) == null)
        {
            return VersionError.UpgradeNotSupported;
        }
    }

    for (from_version..to_version)
        |v|
    {
        const version: u32 = @intCast(v);
        const step = Table.get(version, version + 1).?;
        switch (step.change)
        {
            .none => {},
            .transform => |transform_fn| try transform_fn(allocator, data),
        }
        data.schema_version = version + 1;
    }
}

/// Downgrade `data` from its current `schema_version` to `to_version` by
/// applying each single-version step in `Table` in order.
///
/// Every step is checked to exist before any is applied.  If a transform
/// fails part way, `data` may be partially downgraded and should be
/// discarded.
pub fn downgrade_with(
    comptime Table: type,
    allocator: Allocator,
    data: *Table.DataType,
    to_version: u32,
) !void
{
    comptime std.debug.assert(Table.DIRECTION == .downgrade);

    const from_version = data.schema_version;
    if (to_version > from_version)
    {
        return VersionError.DowngradeTargetIsNewer;
    }

    var version = from_version;
    while (version > to_version)
        : (version -= 1)
    {
        if (Table.get(version, version - 1) == null)
        {
            return VersionError.DowngradeNotSupported;
        }
    }

    version = from_version;
    while (version > to_version)
        : (version -= 1)
    {
        const step = Table.get(version, version - 1).?;
        switch (step.change)
        {
            .none => {},
            .transform => |transform_fn| try transform_fn(allocator, data),
        }
        data.schema_version = version - 1;
    }
}

/// True if `Table` has every step from `from_version` down to `to_version`
/// (trivially true when they are equal).
pub fn downgrade_supported(
    comptime Table: type,
    from_version: u32,
    to_version: u32,
) bool
{
    if (to_version > from_version)
    {
        return false;
    }
    var version = from_version;
    while (version > to_version)
        : (version -= 1)
    {
        if (Table.get(version, version - 1) == null)
        {
            return false;
        }
    }
    return true;
}

/// Every version data at `from_version` can be written as with `Table`,
/// newest first (always includes `from_version` itself).
pub fn downgrade_targets(
    comptime Table: type,
    comptime from_version: u32,
) []const u32
{
    comptime {
        var targets: []const u32 = &.{};
        var version: u32 = from_version;
        while (true)
        {
            if (downgrade_supported(Table, from_version, version))
            {
                targets = targets ++ &[_]u32{version};
            }
            if (version == 0)
            {
                break;
            }
            version -= 1;
        }
        const result = targets[0..targets.len].*;
        return &result;
    }
}

const serializable = @import("serializable.zig");
const SerializableRoot = serializable.SerializableRoot;

/// Oldest timeline document version that can be read.  v0 is
/// OTIO-JSON-shaped data produced by the legacy importer.
pub const OLDEST_TIMELINE_VERSION: u32 = 0;

/// Oldest collection document version that can be read.  Collections were
/// introduced in v1.
pub const OLDEST_COLLECTION_VERSION: u32 = 1;

/// v0 -> v1: fill in transition containers missing from OTIO-JSON-shaped
/// timelines.  (No v0 collections exist; `SerializableRoot.finalize` rejects
/// them before the table runs.)
fn upgrade_document_v0_to_v1(
    allocator: Allocator,
    root: *SerializableRoot,
) anyerror!void
{
    switch (root.content) {
        .timeline => |*timeline| try serializable.fix_v0_transitions(
            allocator,
            timeline,
        ),
        .collection => return VersionError.UpgradeNotSupported,
    }
}

/// Document upgrade steps.  Each step handles every root kind it applies
/// to; the version lives on the root.
pub const DocumentUpgrades = TransformTable(
    SerializableRoot,
    .upgrade,
    &.{
        .{
            .from = 0,
            .to = 1,
            .change = .{ .transform = upgrade_document_v0_to_v1 },
        },
    },
);

/// Document downgrade steps.  None are registered yet.
pub const DocumentDowngrades = TransformTable(
    SerializableRoot,
    .downgrade,
    &.{},
);

comptime {
    const oldest = @min(OLDEST_TIMELINE_VERSION, OLDEST_COLLECTION_VERSION);
    if (upgrade_table_problem(DocumentUpgrades, oldest, CURRENT_SCHEMA_VERSION))
        |problem|
    {
        @compileError("DocumentUpgrades: " ++ problem);
    }
    if (downgrade_table_problem(DocumentDowngrades, CURRENT_SCHEMA_VERSION))
        |problem|
    {
        @compileError("DocumentDowngrades: " ++ problem);
    }
}

/// Keep only versions at or above `oldest` (comptime).
fn at_least(
    comptime versions: []const u32,
    comptime oldest: u32,
) []const u32
{
    comptime {
        var result: []const u32 = &.{};
        for (versions)
            |version|
        {
            if (version >= oldest)
            {
                result = result ++ &[_]u32{version};
            }
        }
        const final = result[0..result.len].*;
        return &final;
    }
}

/// Schema versions a timeline document can be written as, newest first.
pub const TIMELINE_WRITE_VERSIONS = at_least(
    downgrade_targets(DocumentDowngrades, CURRENT_SCHEMA_VERSION),
    OLDEST_TIMELINE_VERSION,
);

/// Schema versions a collection document can be written as, newest first.
pub const COLLECTION_WRITE_VERSIONS = at_least(
    downgrade_targets(DocumentDowngrades, CURRENT_SCHEMA_VERSION),
    OLDEST_COLLECTION_VERSION,
);

// ----------------------------------------------------------------------------
// Tests
// ----------------------------------------------------------------------------

test "versioning: DocumentUpgrades is a no-op at the current version"
{
    const allocator = std.testing.allocator;

    var root: SerializableRoot = .{
        .content = .{
            .timeline = .{
                .name = "",
                .children = &.{},
                .presentation_space_discrete_partitions = .{},
            },
        },
    };

    try upgrade_with(DocumentUpgrades, allocator, &root, CURRENT_SCHEMA_VERSION);
    try std.testing.expectEqual(CURRENT_SCHEMA_VERSION, root.schema_version);
}

test "versioning: DocumentUpgrades rejects data newer than supported"
{
    const allocator = std.testing.allocator;

    var root: SerializableRoot = .{
        .schema_version = CURRENT_SCHEMA_VERSION + 1,
        .content = .{ .collection = .{ .children = &.{} } },
    };

    try std.testing.expectError(
        VersionError.SchemaVersionNewerThanSupported,
        upgrade_with(DocumentUpgrades, allocator, &root, CURRENT_SCHEMA_VERSION),
    );
}

/// Stand-in for a versioned schema type: records which transforms ran, in
/// order, and the version each one saw.
const FakeVersioned = struct {
    schema_version: u32,
    log: [8]Entry = undefined,
    log_len: usize = 0,

    const Entry = struct { name: u8, saw_version: u32 };

    fn record(
        self: *@This(),
        name: u8,
    ) void
    {
        self.log[self.log_len] = .{
            .name = name,
            .saw_version = self.schema_version,
        };
        self.log_len += 1;
    }

    fn entries(
        self: *const @This(),
    ) []const Entry
    {
        return self.log[0..self.log_len];
    }
};

const fake_transforms = struct {
    fn up_0_1(_: Allocator, d: *FakeVersioned) anyerror!void { d.record('a'); }
    fn up_1_2(_: Allocator, d: *FakeVersioned) anyerror!void { d.record('b'); }
    fn up_3_4(_: Allocator, d: *FakeVersioned) anyerror!void { d.record('d'); }
    fn down_4_3(_: Allocator, d: *FakeVersioned) anyerror!void { d.record('D'); }
    fn down_2_1(_: Allocator, d: *FakeVersioned) anyerror!void { d.record('B'); }
    fn failing(_: Allocator, _: *FakeVersioned) anyerror!void
    {
        return error.FakeTransformFailed;
    }
};

const FAKE_CURRENT: u32 = 4;

const FakeUpgrades = TransformTable(
    FakeVersioned,
    .upgrade,
    &.{
        .{ .from = 0, .to = 1, .change = .{ .transform = fake_transforms.up_0_1 } },
        .{ .from = 1, .to = 2, .change = .{ .transform = fake_transforms.up_1_2 } },
        .{ .from = 2, .to = 3, .change = .none },
        .{ .from = 3, .to = 4, .change = .{ .transform = fake_transforms.up_3_4 } },
    },
);

// No 1 -> 0 step: downgrading below v1 is unsupported.
const FakeDowngrades = TransformTable(
    FakeVersioned,
    .downgrade,
    &.{
        .{ .from = 4, .to = 3, .change = .{ .transform = fake_transforms.down_4_3 } },
        .{ .from = 3, .to = 2, .change = .none },
        .{ .from = 2, .to = 1, .change = .{ .transform = fake_transforms.down_2_1 } },
    },
);

fn expect_log(
    expected: []const FakeVersioned.Entry,
    data: FakeVersioned,
) !void
{
    try std.testing.expectEqual(expected.len, data.log_len);
    for (expected, data.entries())
        |want, got|
    {
        try std.testing.expectEqual(want.name, got.name);
        try std.testing.expectEqual(want.saw_version, got.saw_version);
    }
}

test "versioning: valid fake tables pass the comptime checks"
{
    comptime {
        std.debug.assert(upgrade_table_problem(FakeUpgrades, 0, FAKE_CURRENT) == null);
        std.debug.assert(downgrade_table_problem(FakeDowngrades, FAKE_CURRENT) == null);
    }
}

test "versioning: upgrades chain single-version steps in order"
{
    const allocator = std.testing.allocator;

    var from_0: FakeVersioned = .{ .schema_version = 0 };
    try upgrade_with(FakeUpgrades, allocator, &from_0, FAKE_CURRENT);
    try std.testing.expectEqual(FAKE_CURRENT, from_0.schema_version);
    // 2 -> 3 is `.none`, so nothing is recorded for it.
    try expect_log(
        &.{
            .{ .name = 'a', .saw_version = 0 },
            .{ .name = 'b', .saw_version = 1 },
            .{ .name = 'd', .saw_version = 3 },
        },
        from_0,
    );

    // Starting part way only runs the remaining steps.
    var from_2: FakeVersioned = .{ .schema_version = 2 };
    try upgrade_with(FakeUpgrades, allocator, &from_2, FAKE_CURRENT);
    try expect_log(&.{ .{ .name = 'd', .saw_version = 3 } }, from_2);

    // Stopping short of the current version is allowed.
    var to_2: FakeVersioned = .{ .schema_version = 0 };
    try upgrade_with(FakeUpgrades, allocator, &to_2, 2);
    try std.testing.expectEqual(@as(u32, 2), to_2.schema_version);
    try std.testing.expectEqual(@as(usize, 2), to_2.log_len);

    // Already at the target: nothing runs.
    var current: FakeVersioned = .{ .schema_version = FAKE_CURRENT };
    try upgrade_with(FakeUpgrades, allocator, &current, FAKE_CURRENT);
    try std.testing.expectEqual(@as(usize, 0), current.log_len);
}

test "versioning: data newer than the target is unreadable"
{
    const allocator = std.testing.allocator;

    var newer: FakeVersioned = .{ .schema_version = FAKE_CURRENT + 1 };
    try std.testing.expectError(
        VersionError.SchemaVersionNewerThanSupported,
        upgrade_with(FakeUpgrades, allocator, &newer, FAKE_CURRENT),
    );
    try std.testing.expectEqual(FAKE_CURRENT + 1, newer.schema_version);
    try std.testing.expectEqual(@as(usize, 0), newer.log_len);
}

test "versioning: downgrades chain single-version steps in order"
{
    const allocator = std.testing.allocator;

    var data: FakeVersioned = .{ .schema_version = FAKE_CURRENT };
    try downgrade_with(FakeDowngrades, allocator, &data, 1);
    try std.testing.expectEqual(@as(u32, 1), data.schema_version);
    try expect_log(
        &.{
            .{ .name = 'D', .saw_version = 4 },
            .{ .name = 'B', .saw_version = 2 },
        },
        data,
    );
}

test "versioning: a missing downgrade step fails before anything runs"
{
    const allocator = std.testing.allocator;

    var data: FakeVersioned = .{ .schema_version = FAKE_CURRENT };
    try std.testing.expectError(
        VersionError.DowngradeNotSupported,
        downgrade_with(FakeDowngrades, allocator, &data, 0),
    );
    // The chain is checked up front, so the data is untouched.
    try std.testing.expectEqual(FAKE_CURRENT, data.schema_version);
    try std.testing.expectEqual(@as(usize, 0), data.log_len);

    var upward: FakeVersioned = .{ .schema_version = 1 };
    try std.testing.expectError(
        VersionError.DowngradeTargetIsNewer,
        downgrade_with(FakeDowngrades, allocator, &upward, 2),
    );
}

test "versioning: a failing transform stops the chain"
{
    const allocator = std.testing.allocator;

    const FailingUpgrades = TransformTable(
        FakeVersioned,
        .upgrade,
        &.{
            .{ .from = 0, .to = 1, .change = .{ .transform = fake_transforms.up_0_1 } },
            .{ .from = 1, .to = 2, .change = .{ .transform = fake_transforms.failing } },
            .{ .from = 2, .to = 3, .change = .{ .transform = fake_transforms.up_3_4 } },
        },
    );

    var data: FakeVersioned = .{ .schema_version = 0 };
    try std.testing.expectError(
        error.FakeTransformFailed,
        upgrade_with(FailingUpgrades, allocator, &data, 3),
    );
    // The first step completed; the failing one did not bump the version
    // and later steps never ran.
    try std.testing.expectEqual(@as(u32, 1), data.schema_version);
    try expect_log(&.{ .{ .name = 'a', .saw_version = 0 } }, data);
}

test "versioning: comptime checks reject malformed tables"
{
    comptime {
        // Missing the 1 -> 2 step.
        const Gap = TransformTable(
            FakeVersioned,
            .upgrade,
            &.{
                .{ .from = 0, .to = 1, .change = .none },
                .{ .from = 2, .to = 3, .change = .none },
            },
        );
        std.debug.assert(upgrade_table_problem(Gap, 0, 3) != null);

        // Duplicate step.
        const Dup = TransformTable(
            FakeVersioned,
            .upgrade,
            &.{
                .{ .from = 0, .to = 1, .change = .none },
                .{ .from = 0, .to = 1, .change = .none },
            },
        );
        std.debug.assert(upgrade_table_problem(Dup, 0, 1) != null);

        // Skips a version in one step.
        const Skip = TransformTable(
            FakeVersioned,
            .upgrade,
            &.{
                .{ .from = 0, .to = 2, .change = .none },
            },
        );
        std.debug.assert(upgrade_table_problem(Skip, 0, 2) != null);

        // Goes past the current version.
        const Past = TransformTable(
            FakeVersioned,
            .upgrade,
            &.{
                .{ .from = 0, .to = 1, .change = .none },
            },
        );
        std.debug.assert(upgrade_table_problem(Past, 0, 0) != null);

        // Starts before the oldest readable version.
        const TooOld = TransformTable(
            FakeVersioned,
            .upgrade,
            &.{
                .{ .from = 0, .to = 1, .change = .none },
                .{ .from = 1, .to = 2, .change = .none },
            },
        );
        std.debug.assert(upgrade_table_problem(TooOld, 1, 2) != null);

        // Downgrade tables: wrong direction step, duplicate, past current.
        const Backwards = TransformTable(
            FakeVersioned,
            .downgrade,
            &.{
                .{ .from = 1, .to = 2, .change = .none },
            },
        );
        std.debug.assert(downgrade_table_problem(Backwards, 2) != null);

        const DownDup = TransformTable(
            FakeVersioned,
            .downgrade,
            &.{
                .{ .from = 2, .to = 1, .change = .none },
                .{ .from = 2, .to = 1, .change = .none },
            },
        );
        std.debug.assert(downgrade_table_problem(DownDup, 2) != null);

        const DownPast = TransformTable(
            FakeVersioned,
            .downgrade,
            &.{
                .{ .from = 3, .to = 2, .change = .none },
            },
        );
        std.debug.assert(downgrade_table_problem(DownPast, 2) != null);

        // Tables used in the wrong direction.
        std.debug.assert(upgrade_table_problem(FakeDowngrades, 0, FAKE_CURRENT) != null);
        std.debug.assert(downgrade_table_problem(FakeUpgrades, FAKE_CURRENT) != null);
    }
}

test "versioning: data older than the oldest readable version is rejected"
{
    const allocator = std.testing.allocator;

    // Reads v2..v4 only.
    const FromTwo = TransformTable(
        FakeVersioned,
        .upgrade,
        &.{
            .{ .from = 2, .to = 3, .change = .none },
            .{ .from = 3, .to = 4, .change = .{ .transform = fake_transforms.up_3_4 } },
        },
    );
    comptime std.debug.assert(upgrade_table_problem(FromTwo, 2, 4) == null);

    var too_old: FakeVersioned = .{ .schema_version = 1 };
    try std.testing.expectError(
        VersionError.UpgradeNotSupported,
        upgrade_with(FromTwo, allocator, &too_old, 4),
    );
    try std.testing.expectEqual(@as(u32, 1), too_old.schema_version);
    try std.testing.expectEqual(@as(usize, 0), too_old.log_len);

    var oldest: FakeVersioned = .{ .schema_version = 2 };
    try upgrade_with(FromTwo, allocator, &oldest, 4);
    try std.testing.expectEqual(@as(u32, 4), oldest.schema_version);
}

test "versioning: write versions respect the oldest version per root kind"
{
    for (COLLECTION_WRITE_VERSIONS)
        |version|
    {
        try std.testing.expect(version >= OLDEST_COLLECTION_VERSION);
    }
    for (TIMELINE_WRITE_VERSIONS)
        |version|
    {
        try std.testing.expect(version >= OLDEST_TIMELINE_VERSION);
    }
    try std.testing.expectEqualSlices(
        u32,
        &.{ 3, 2 },
        comptime at_least(&.{ 3, 2, 1, 0 }, 2),
    );
}

test "versioning: downgrade_targets lists reachable versions newest first"
{
    // FakeDowngrades has 4->3, 3->2 and 2->1 but no 1->0.
    const targets = comptime downgrade_targets(FakeDowngrades, FAKE_CURRENT);
    try std.testing.expectEqualSlices(u32, &.{ 4, 3, 2, 1 }, targets);

    try std.testing.expect(downgrade_supported(FakeDowngrades, 4, 1));
    try std.testing.expect(!downgrade_supported(FakeDowngrades, 4, 0));
    try std.testing.expect(!downgrade_supported(FakeDowngrades, 1, 2));

    // The real tables always allow writing the current version.
    try std.testing.expectEqual(
        CURRENT_SCHEMA_VERSION,
        TIMELINE_WRITE_VERSIONS[0],
    );
    try std.testing.expectEqual(
        CURRENT_SCHEMA_VERSION,
        COLLECTION_WRITE_VERSIONS[0],
    );
}
