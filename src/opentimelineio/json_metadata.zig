//! Ownership helpers for metadata stored as `std.json.Value` on schema
//! objects.
//!
//! Schema objects (Clip, Timeline, Collection) own their metadata: every
//! string, array and object in it is allocated with the allocator the schema
//! object was built with, and is freed by the object's `deinit`.  Use `clone`
//! to take a copy of metadata owned by someone else (e.g. a JSON parse
//! arena).

const std = @import("std");

/// Deep-copy `value` so every string, array and object is owned by
/// `allocator`.
pub fn clone(
    allocator: std.mem.Allocator,
    value: std.json.Value,
) std.mem.Allocator.Error!std.json.Value
{
    return switch (value) {
        .null, .bool, .integer, .float => value,
        .number_string => |s| .{ .number_string = try allocator.dupe(u8, s) },
        .string => |s| .{ .string = try allocator.dupe(u8, s) },
        .array => |arr| arr_blk: {
            var result = try std.json.Array.initCapacity(
                allocator,
                arr.items.len,
            );
            errdefer deinit(allocator, .{ .array = result });
            for (arr.items)
                |item|
            {
                result.appendAssumeCapacity(try clone(allocator, item));
            }
            break :arr_blk .{ .array = result };
        },
        .object => |obj| obj_blk: {
            var result: std.json.ObjectMap = .empty;
            errdefer deinit(allocator, .{ .object = result });
            try result.ensureTotalCapacity(allocator, obj.count());
            var iter = obj.iterator();
            while (iter.next())
                |entry|
            {
                const key = try allocator.dupe(u8, entry.key_ptr.*);
                errdefer allocator.free(key);
                const item = try clone(allocator, entry.value_ptr.*);
                result.putAssumeCapacity(key, item);
            }
            break :obj_blk .{ .object = result };
        },
    };
}

/// Free metadata built by `clone` or with the same allocator throughout.
pub fn deinit(
    allocator: std.mem.Allocator,
    value: std.json.Value,
) void
{
    switch (value) {
        .null, .bool, .integer, .float => {},
        .number_string, .string => |s| allocator.free(s),
        .array => |arr| {
            for (arr.items)
                |item|
            {
                deinit(allocator, item);
            }
            var mutable = arr;
            mutable.deinit();
        },
        .object => |obj| {
            var iter = obj.iterator();
            while (iter.next())
                |entry|
            {
                allocator.free(entry.key_ptr.*);
                deinit(allocator, entry.value_ptr.*);
            }
            var mutable = obj;
            mutable.deinit(allocator);
        },
    }
}

test "json_metadata: clone is independent of the source and deinit frees it"
{
    const allocator = std.testing.allocator;

    var arena = std.heap.ArenaAllocator.init(allocator);
    const parsed = (
        try std.json.parseFromSliceLeaky(
            std.json.Value,
            arena.allocator(),
            \\{"scene": "001", "takes": [1, 2.5, null, true], "nested": {"a": "b"}}
            ,
            .{},
        )
    );

    const copy = try clone(allocator, parsed);
    defer deinit(allocator, copy);

    // The source is gone; the copy must still be intact.
    arena.deinit();

    try std.testing.expectEqualStrings(
        "001",
        copy.object.get("scene").?.string,
    );
    try std.testing.expectEqual(
        @as(usize, 4),
        copy.object.get("takes").?.array.items.len,
    );
    try std.testing.expectEqualStrings(
        "b",
        copy.object.get("nested").?.object.get("a").?.string,
    );
}
