const std = @import("std");
const expectEqual = std.testing.expectEqual;

const allocator = @import("opentime/allocator.zig");

// @TODO: TopologicalPathHash => std.bit_set.DynamicBitSet
// for now using a u128 for encoded the paths
pub const TopologicalPathHash = u128;
// pub const TopologicalPathHash = std.bit_set.DynamicBitSet;
pub const TopologicalPathHashMask = u64;
pub const TopologicalPathHashMaskTopBitCount = u8;

pub fn value_to_bitset(
    in_value: anytype,
    target_bitset: *std.bit_set.DynamicBitSet
) void 
{
    var current = in_value;

    var index : usize = 0;
    while (current > 0) {
        if (current & 1 == 1) {
            target_bitset.*.set(index);
        }

        index += 1;
        current >>= 1;
    }
}

///
/// append (child_index + 1) 1's to the end of the parent_hash:
///
/// parent hash: 0b10 (the starting hash for the root node) 
/// child index 2:
/// result: 0b10111
///
///  parent hash: 0b100
///  child index: 0
///  result: 0b1001
///
///  each "0" means a stack (go _down_ the tree) each 1 means a sequential (go
///  across the tree)
///
pub fn sequential_child_hash(
    parent_hash:TopologicalPathHash,
    child_index:usize
) TopologicalPathHash 
{
    const ind_offset = child_index + 1;
    return (
        std.math.shl(TopologicalPathHash, parent_hash, ind_offset) 
        | (std.math.shl(TopologicalPathHash, 2 , ind_offset - 1) - 1)
    );
}

pub fn depth_child_hash(
    parent_hash: TopologicalPathHash,
    child_index:usize
) TopologicalPathHash
{
    const ind_offset = child_index;
    return std.math.shl(TopologicalPathHash, parent_hash, ind_offset);
}

test "depth_child_hash: math" {
    const start_hash:TopologicalPathHash = 0b10;

    const TPH = TopologicalPathHash;
    
    try expectEqual(@as(TPH, 0b10), depth_child_hash(start_hash, 0));
    try expectEqual(@as(TPH, 0b100), depth_child_hash(start_hash, 1));
    try expectEqual(@as(TPH, 0b1000), depth_child_hash(start_hash, 2));
    try expectEqual(@as(TPH, 0b10000), depth_child_hash(start_hash, 3));
}

pub fn top_bits(
    n: TopologicalPathHashMaskTopBitCount
) TopologicalPathHash
{
    // Handle edge cases
    const tmp:TopologicalPathHash = 0;
    if (n == 64) {
        return ~ tmp;
    }

    // Create a mask with all bits set
    var mask: TopologicalPathHash = ~tmp;

    // Shift the mask right by n bits

    mask = std.math.shl(TopologicalPathHash, mask, n);

    return ~mask;
}

pub fn path_between_hash(
    in_a: TopologicalPathHash,
    in_b: TopologicalPathHash,
) !TopologicalPathHash
{
    var a = in_a;
    var b = in_b;
    
    if (a < b) {
        a = in_b;
        b = in_a;
    }

    if (path_exists_hash(a, b) == false) {
        return error.NoPathBetweenSpaces;
    }

    const r = @clz(b) - @clz(a);
    if (r == 0) {
        return 0;
    }

    // line b up with a
    // eg: b=101 and a1010, b -> 1010
    b <<= @intCast(u7,r);

    const path = a ^ b;

    return path;
}

test "path_between_hash: math" {
    const TestData = struct{
        source: TopologicalPathHash,
        dest: TopologicalPathHash,
        expect: TopologicalPathHash,
    };

    const test_data = [_]TestData{
        .{ .source = 0b10, .dest = 0b101, .expect = 0b1 },
        .{ .source = 0b101, .dest = 0b10, .expect = 0b1 },
        .{ .source = 0b10, .dest = 0b10, .expect = 0b0 },
        .{ .source = 0b10, .dest = 0b100, .expect = 0b0 },
        .{ .source = 0b10, .dest = 0b1011, .expect = 0b11 },
        .{ .source = 0b1011, .dest = 0b10, .expect = 0b11 },
        .{ 
            .source = 0b10,
            .dest = 0b10111010101110001111111,
            .expect = 0b111010101110001111111 
        },
    };

    for (test_data) |t, i| {
        errdefer std.log.err(
            "[{d}] source: {b} dest: {b} expected: {b}",
            .{ i, t.source, t.dest, t.expect }
        );

        try expectEqual(t.expect, try path_between_hash(t.source, t.dest));
    }
}

pub fn track_child_index_from_hash(hash: TopologicalPathHash) usize {
    var index: usize = 0;
    var current_hash = hash;

    // count the trailing 1s
    while (current_hash > 0 and 0b1 & current_hash == 1) {
        index += 1;
        current_hash >>= 1;
    }

    return index;
}

test "track_child_index_from_hash: math" {
    const TestData = struct{source: TopologicalPathHash, expect: usize };

    const test_data = [_]TestData{
        .{ .source = 0b10, .expect = 0 },
        .{ .source = 0b101, .expect = 1 },
        .{ .source = 0b1011, .expect = 2 },
        .{ .source = 0b10111101111, .expect = 4 },
    };

    for (test_data) |t, i| {
        errdefer std.log.err(
            "[{d}] source: {b} expected: {b}",
            .{ i, t.source, t.expect }
        );

        try expectEqual(t.expect, track_child_index_from_hash(t.source));
    }
}

pub fn next_branch_along_path_hash(
    source: TopologicalPathHash,
    destination: TopologicalPathHash,
) u1 
{
    var start = source;
    var end = destination;

    if (start < end) {
        start = destination;
        end = source;
    }

    const r = @clz(end) - @clz(start);
    if (r == 0) {
        return 0;
    }

    // line b up with a
    // eg: b=101 and a1010, b -> 1010
    end <<= @intCast(u7,r);

    const path = start ^ end;

    return @truncate(u1, path >> @intCast(u7, (r - 1)) );
}

test "next_branch_along_path_hash: math" {
    const TestData = struct{
        source: TopologicalPathHash,
        dest: TopologicalPathHash,
        expect: u1,
    };

    const test_data = [_]TestData{
        .{ .source = 0b10, .dest = 0b101, .expect = 0b1 },
        .{ .source = 0b10, .dest = 0b100, .expect = 0b0 },
        .{ .source = 0b10, .dest = 0b10011101, .expect = 0b0 },
        .{ .source = 0b10, .dest = 0b10001101, .expect = 0b0 },
        .{ .source = 0b10, .dest = 0b10111101, .expect = 0b1 },
        .{ .source = 0b10, .dest = 0b10101101, .expect = 0b1 },
        .{ .source = 0b101, .dest = 0b10111101, .expect = 0b1 },
        .{ .source = 0b101, .dest = 0b10101101, .expect = 0b0 },
    };

    for (test_data) |t, i| {
        errdefer std.log.err(
            "[{d}] source: {b} dest: {b} expected: {b}",
            .{ i, t.source, t.dest, t.expect }
        );

        try expectEqual(
            t.expect,
            next_branch_along_path_hash(t.source, t.dest)
        );
    }
}

pub fn path_exists_hash(
    in_a: TopologicalPathHash,
    in_b: TopologicalPathHash
) bool 
{
    var a = in_a;
    var b = in_b;

    if ((a == 0) or (b == 0)) {
        return false;
    }

    if (b>a) { 
        a = in_b;
        b = in_a;
    }

    const r = @clz(b) - @clz(a);
    if (r == 0) {
        return (a == b);
    }

    // line b up with a
    // eg: b=101 and a1010, b -> 1010
    b <<= @intCast(u7,r);

    var mask : TopologicalPathHash = 0;
    mask = ~mask;

    mask = std.math.shl(TopologicalPathHash, mask, r);

    return ((a & mask) == (b & mask));
}

test "sequential_child_hash: path tests" {
    // 0 never has a path
    try expectEqual(false, path_exists_hash(0b0, 0b101));

    // different bitwidths
    try expectEqual(true, path_exists_hash(0b10, 0b101));
    try expectEqual(true, path_exists_hash(0b101, 0b10));
    try expectEqual(true, path_exists_hash(0b101, 0b1011101010111000));
    try expectEqual(true, path_exists_hash(0b10111010101110001111111, 0b1011101010111000));

    // test maximum width
    var mask : TopologicalPathHash = 0;
    mask = ~mask;
    try expectEqual(false, path_exists_hash(0, mask));
    try expectEqual(true, path_exists_hash(mask, mask));
    try expectEqual(true, path_exists_hash(mask/2, mask));
    try expectEqual(true, path_exists_hash(mask, mask/2));
    try expectEqual(false, path_exists_hash(mask - 1, mask));
    try expectEqual(false, path_exists_hash(mask, mask - 1));

    // mismatch
    // same width
    try expectEqual(false, path_exists_hash(0b100, 0b101));
    // different width
    try expectEqual(false, path_exists_hash(0b10, 0b110));
    try expectEqual(false, path_exists_hash(0b11, 0b101));
    try expectEqual(false, path_exists_hash(0b100, 0b101110));
}

test "sequential_child_hash: math" {
    const start_hash:TopologicalPathHash = 0b10;

    try expectEqual(
        @as(TopologicalPathHash, 0b10111),
        sequential_child_hash(start_hash, 2)
    );

    try expectEqual(
        @as(TopologicalPathHash, 0b101),
        sequential_child_hash(start_hash, 0)
    );

    try expectEqual(
        @as(TopologicalPathHash, 0b10111111111111111111111),
        sequential_child_hash(start_hash, 20)
    );
}

test "DynamicBitSet test" {
    var dbs = try std.bit_set.DynamicBitSet.initEmpty(
        std.testing.allocator,
        // default length
        128 
    );
    defer dbs.deinit();

    const known:u128 = 0b11101;
    value_to_bitset(known, &dbs);

    // read it back into a number
    var iter = dbs.iterator(.{});
    var result: u128 = 0;

    while (iter.next()) |b| {
        result |= std.math.shl(@TypeOf(result), 1, b);
    }

    {
        var hasher = std.hash.Wyhash.init(0);
        std.hash.autoHash(&hasher, dbs);

        var hasher2 = std.hash.Wyhash.init(0);
        std.hash.autoHash(&hasher2, dbs);

        try expectEqual(hasher.final(), hasher2.final());
    }

    try expectEqual(known, result);
}
