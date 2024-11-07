//! This module implements the Treecode struct for encoding paths through
//! binary trees.

const std = @import("std");

pub const TreecodeWord = u128;
pub const WORD_BIT_COUNT = @bitSizeOf(TreecodeWord);
pub const Hash = u64;

/// An encoding of a path through a binary tree.  The root bit is the right
/// side of a number, and the directions are read right to left.  
///
/// The directions:
/// - 0: left child
/// - 1: right child
///
/// Examples:
/// - 0b1001 => right, left, left
/// - 0b111001 => right, left, left, right, right
/// - 0b1010 => left, right, left
pub const Treecode = struct {
    /// the array of words that make up the treecode
    treecode_array: []TreecodeWord,
    /// index in treecode_array of the leftmost bit in the treecode
    sz: usize,

    /// do not touch, for internal purposes
    allocator: std.mem.Allocator,

    /// preallocate a Treecode of size count and stamp input into the LSB
    /// (leftmost)
    pub fn init_fill_count(
        allocator: std.mem.Allocator,
        /// number of inputs to stamp into result
        count: usize,
        /// word to stamp into each block of the result
        input: TreecodeWord,
    ) !Treecode 
    {
        if (count == 0) {
            return error.InvalidCount;
        }

        var treecode_array:[]TreecodeWord = try allocator.alloc(
            TreecodeWord,
            count
        );

        // zero everything out
        @memset(treecode_array, 0);

        // set the argument in the LSB
        treecode_array[count - 1] = input;

        return .{
            .allocator = allocator,
            .sz = count,
            .treecode_array = treecode_array 
        };
    }

    /// initialize from a single TreecodeWord
    pub fn init_word(
        allocator: std.mem.Allocator,
        input: TreecodeWord,
    ) !Treecode 
    {
        var treecode_array = try allocator.alloc(
            TreecodeWord,
            1,
        );

        treecode_array[0] = input;
        return .{
            .allocator = allocator,
            .sz = 1,
            .treecode_array = treecode_array 
        };
    }

    fn realloc(
        self: *@This(),
        new_size: usize,
    ) !void 
    {
        self.treecode_array = try self.allocator.realloc(
            self.treecode_array,
            new_size
        );

        @memset(self.treecode_array[self.sz..], 0);

        self.sz = new_size;
    }

    pub fn clone(
        self: @This(),
    ) !Treecode 
    {
        return .{
            .sz = self.sz,
            .treecode_array = try self.allocator.dupe(
                TreecodeWord,
                self.treecode_array
            ),
            .allocator = self.allocator,
        };
    }

    pub fn deinit(
        self: @This(),
    ) void 
    {
        self.allocator.free(self.treecode_array);
    }

    /// sentinel bit is not included in the code_length (hence the 127 - )
    pub fn code_length(
        self: @This(),
    ) usize 
    {
        if (self.sz == 0) {
            return 0;
        }
        var occupied_words : usize = 0;

        var i : usize = 0;
        while (i < self.sz) 
            : (i += 1)
        {
            if (self.treecode_array[i] != 0) {
                occupied_words = i;
            }
        }

        const count = (
            (WORD_BIT_COUNT - 1) - @clz(self.treecode_array[occupied_words])
        );

        if (occupied_words == 0) {
            return count;
        }

        return count + (occupied_words) * WORD_BIT_COUNT;
    }

    pub fn eql(
        self: @This(),
        other: Treecode,
    ) bool 
    {
        const len_self = self.code_length();
        const len_other = other.code_length();

        if (len_self != len_other) {
            return false;
        }

        const greatest_nozero_index: usize = len_self / WORD_BIT_COUNT;

        var i:usize = 0;
        while (i <= greatest_nozero_index)
            : (i += 1) 
        {
            if (self.treecode_array[i] != other.treecode_array[i]) {
                return false;
            }
        }

        return true;
    }

    /// in place append a bit to this treecode. will realloc if needed.
    pub fn append(
        self: *@This(),
        l_or_r_branch: u1,
    ) !void 
    {
        if (self.sz == 0) {
            return error.InvalidTreecode;
        }

        const len = self.code_length();

        if (len < (WORD_BIT_COUNT - 1)) 
        {
            self.treecode_array[0] = treecode_word_append(
                self.treecode_array[0],
                l_or_r_branch
            );
            return;
        }

        var space_available = self.sz * WORD_BIT_COUNT - 1;
        const next_index = len + 1;

        if (next_index >= space_available) 
        {
            // double the size
            try self.realloc(self.sz*2);
            space_available = self.sz * WORD_BIT_COUNT - 1;
        }

        const new_marker_location_abs = len + 1;
        const new_marker_slot = (
            new_marker_location_abs / WORD_BIT_COUNT
        );
        const new_marker_location_in_slot = (
            @rem(new_marker_location_abs, WORD_BIT_COUNT)
        );

        self.treecode_array[new_marker_slot] |= std.math.shl(
            TreecodeWord,
            1,
            new_marker_location_in_slot
        );

        const new_data_location_abs = len; 
        const new_data_slot = new_data_location_abs / WORD_BIT_COUNT;
        const new_data_location_in_slot = (
            @rem(new_data_location_abs, WORD_BIT_COUNT)
        );

        const old_marker_bit = std.math.shl(
            TreecodeWord,
            1,
            new_data_location_in_slot,
        );

        // subtract old marker position
        self.treecode_array[new_data_slot] = (
            self.treecode_array[new_data_slot] 
            - old_marker_bit
        );

        self.treecode_array[new_data_slot] |= std.math.shl(
            TreecodeWord,
            l_or_r_branch,
            new_data_location_in_slot,
        );

        return;
    }

    /// determine whether self is a strict superset of rhs
    pub fn is_superset_of(
        self: @This(),
        rhs: Treecode,
    ) bool 
    {
        const len_self: usize = self.code_length();
        const len_rhs: usize = rhs.code_length();

        // empty lhs path is always a superset
        if (len_self == 0) {
            return true;
        }

        if (len_rhs == 0 or len_rhs > len_self) {
            return false;
        }

        if (len_self <= WORD_BIT_COUNT) {
            return treecode_word_b_is_a_subset(
                self.treecode_array[0],
                rhs.treecode_array[0],
            );
        }

        const greatest_nonzero_rhs_index: usize = (
            len_rhs / WORD_BIT_COUNT
        );
        var i:usize = 0;
        while (i < greatest_nonzero_rhs_index) 
            : (i += 1) 
        {
            if (self.treecode_array[i] != rhs.treecode_array[i]) {
                return false;
            }
        }

        const mask_location_local = @rem(len_rhs, WORD_BIT_COUNT);
        const mask_bits = WORD_BIT_COUNT - mask_location_local;

        // already checked all the other locations
        if (mask_location_local == 0) {
            return true;
        }

        const mask: TreecodeWord = treecode_word_mask(mask_bits);

        const self_masked = (
            self.treecode_array[greatest_nonzero_rhs_index] & mask
        );
        const rhs_masked = (
            rhs.treecode_array[greatest_nonzero_rhs_index] & mask
        );

        return (self_masked == rhs_masked);
    }

    /// compute a hash for this treecode
    pub fn hash(
        self: @This()
    ) Hash 
    {
        var hasher = std.hash.Wyhash.init(0);

        for (self.treecode_array, 0..) 
            |tc, index| 
        {
            if (tc > 0) 
            {
                std.hash.autoHash(&hasher, index + 1);

                // ensure no overflow
                std.hash.autoHash(
                    &hasher,
                    @as(u256, @intCast(tc)) + 1
                );
            }
        }

        return hasher.final();
    }

    /// return a 0 or 1 for appending to self to approach dest.  Assumes that
    /// dest is longer than self.
    pub fn next_step_towards(
        self: @This(),
        dest: Treecode,
    ) !u1 
    {
        const self_len = self.code_length();

        const self_len_pos_local = @rem(self_len, WORD_BIT_COUNT);
        const self_len_word = self_len / WORD_BIT_COUNT;

        const mask = std.math.shl(
            TreecodeWord,
            1,
            self_len_pos_local,
        );

        const masked_val = dest.treecode_array[self_len_word] & mask;

        return @intCast(
            std.math.shr(
                TreecodeWord,
                masked_val,
                self_len_pos_local,
            )
        );
    }

    pub fn format(
        self: @This(),
        // fmt
        comptime _: []const u8,
        // options
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void 
    {
        const marker_pos_abs = self.code_length();
        const last_index = (marker_pos_abs / WORD_BIT_COUNT);

        try writer.print("{b}", .{self.treecode_array[last_index]});

        for (1..last_index+1)
           |i|
        {
            const tcw = self.treecode_array[last_index - i];
            try writer.print("{b:0>128}", .{tcw});
        }
    }
};

test "treecode: code_length - init_word" 
{
    const TestData = struct {
        input: TreecodeWord,
        expected: usize,
    };
    const tests = [_]TestData{
        .{ .input = 1,         .expected = 0 },
        .{ .input = 0b11,      .expected = 1 },
        .{ .input = 0b1111111, .expected = 6 },
    };
    for (tests)
        |t|
    {
        var tc  = try Treecode.init_word(
            std.testing.allocator,
            t.input
        );
        defer tc.deinit();

        try std.testing.expectEqual(
            t.expected,
            tc.code_length(),
        );
    }
}

test "treecode: code_length - init_fill_count"
{
    inline for (
        .{
            .{ 0b1,  2, WORD_BIT_COUNT },
            .{ 0b1,  8, 7*WORD_BIT_COUNT },
            .{ 0b11, 8, 7*WORD_BIT_COUNT + 1 },
        }
    ) |t|
    {
        // top word is 1, lower word is 0, therefore codelength is 
        // WORD_BIT_COUNT
        var tc  = try Treecode.init_fill_count(
            std.testing.allocator,
            t[1],
            t[0],
        );
        defer tc.deinit();

        try std.testing.expectEqual(
            t[2],
            tc.code_length(),
        );
    }
}

test "treecode: @clz" 
{
    var x: TreecodeWord = 0;
    try std.testing.expectEqual(@as(usize, WORD_BIT_COUNT), @clz(x));

    var i: TreecodeWord = 0;
    while (i < WORD_BIT_COUNT) 
        : (i += 1) 
    {
        try std.testing.expectEqual(i, WORD_BIT_COUNT - @clz(x));
        x = (x << 1) | 1;
    }
}

fn treecode_word_mask(
    leading_zeros: usize,
) TreecodeWord 
{
    return (
        @as(TreecodeWord, @intCast(1)) << (
            @as(u7, @intCast((WORD_BIT_COUNT - leading_zeros)))
        )
    ) - 1;
}

fn treecode_word_b_is_a_subset(
    a: TreecodeWord,
    b: TreecodeWord,
) bool 
{
    if (a == b) {
        return true;
    }

    if (a == 0 or b == 0) {
        return false;
    }

    const leading_zeros: usize = @clz(b) + 1;
    const mask: TreecodeWord = treecode_word_mask(leading_zeros);

    const a_masked = (a & mask);
    const b_masked = (b & mask);

    return a_masked == b_masked;
}

test "fmt all ones"
{
    var ltc = try Treecode.init_word(std.testing.allocator, 0b1);
    defer ltc.deinit();

    try ltc.append(1);
    for (0..125)
        |_|
    {
        try ltc.append(0);
    }
    try ltc.append(1);
    try ltc.append(0);
    try ltc.append(1);

    var buf = std.ArrayList(u8).init(std.testing.allocator);
    defer buf.deinit();

    const result = try std.fmt.bufPrint(buf.items, "{s}", ltc);

    try std.testing.expectEqual(ltc.code_length() + 1, result.len);
}

test "to_string" 
{
    const allocator = std.testing.allocator;
    const one = "1"[0];

    var tc = try Treecode.init_word(allocator, 0b1);
    defer tc.deinit();

    var known = std.ArrayList(u8).init(allocator);
    defer known.deinit();
    try known.append(one);


    var buf = try std.fmt.allocPrint(
        allocator,
        "{s}",
        .{ tc }
    );

    try std.testing.expectEqualStrings(known.items, buf);

    errdefer std.log.err(
        "known: {s} buf: {s} \n",
        .{ known.items, buf } 
    );

    try tc.append(1);
    try known.append(one);

    allocator.free(buf);
    buf = try std.fmt.allocPrint(allocator,"{s}", .{ tc });

    errdefer std.log.err(
        "known: {s} buf: {s} \n",
        .{ known.items, buf } 
    );
    try std.testing.expectEqualStrings(known.items, buf);

    allocator.free(buf);

    for (0..10)
       |i|
    {
        // const next:u1 = if (i & 5 != 0) 0 else 1;
        const next:u1 = 1;

        try known.insert(1, one);
        try tc.append(next);

        buf.clearAndFree();
        try tc.to_str(&buf);

        errdefer std.log.err(
            "iteration: {} known: {s} buf: {s} \n",
            .{ i, known.items, buf.items } 
        );

        try std.testing.expectEqualStrings(known.items, buf.items);
    }
}


test "TreecodeWord: is a subset" 
{
    inline for (
        .{ 
            .{ 0b11001101, 0b1101, true}, 
            .{ 0b110011010, 0b11010, true}, 
            .{ 0b11001101, 0b11001, false}, 
        }
    ) |t|
    {
        try std.testing.expectEqual(
            treecode_word_b_is_a_subset(t[0], t[1]),
            t[2]
        );
    }
}

test "treecode: is a superset" 
{
    // positive case, ending in 1
    inline for(
        .{
            .{ 0b1101101, 0b1101, true },
            .{ 0b11011010, 0b11010, true },
            .{ 0b1101101, 0b11001, false },
        }
    ) |t|
    {
        const tc_superset = try Treecode.init_word(
            std.testing.allocator, t[0]
        );
        defer tc_superset.deinit();
        const tc_subset = try Treecode.init_word(
            std.testing.allocator, t[1]
        );
        defer tc_subset.deinit();

        try std.testing.expectEqual(
            tc_superset.is_superset_of(tc_subset),
            t[2],
        );
    }
}

test "treecode: is superset very long"
{
    var tc_superset  = try Treecode.init_word(
        std.testing.allocator,
        0b111111101
        //   0x1101
    );
    defer tc_superset.deinit();

    var tc_subset  = try Treecode.init_word(
        std.testing.allocator,
        0b11101
    );
    defer tc_subset.deinit();

    var i:usize = 0;
    // walk exactly off the end of one span
    while (i < 124)  
        : (i += 1) 
    {
        try tc_superset.append(1);
        try tc_subset.append(1);
    }

    errdefer std.log.err(
        "\n\niteration: {}\n superset: {b} \n subset:   {b}\n\n",
        .{i, tc_superset.treecode_array[1], tc_subset.treecode_array[1]}
    );

    try std.testing.expect(tc_superset.is_superset_of(tc_subset));

    i = 4;
    while (i < 1000)  
        : (i += 1) 
    {
        errdefer std.log.err(
            "\n\niteration: {}\n superset: {b} \n subset:   {b}\n\n",
            .{i, tc_superset.treecode_array[1], tc_subset.treecode_array[1]}
        );
        try std.testing.expect(tc_superset.is_superset_of(tc_subset));

        try tc_superset.append(1);
        try tc_subset.append(1);
    }
}

test "treecode: append" 
{
    inline for (
        .{ 
            .{ 0b10, 0b1, 0 },
            .{ 0b11, 0b1, 1 },
            .{ 0b1101, 0b101, 1 },
            .{ 0b1001, 0b101, 0 },
        }
    ) |t|
    {
        try std.testing.expectEqual(
            @as(TreecodeWord, t[0]),
            treecode_word_append(t[1], t[2])
        );
    }
}

test "treecode: apped lots of 0"
{
    var tc = try Treecode.init_word(std.testing.allocator, 0b1);
    defer tc.deinit();

    var i:usize = 0;
    while (i < 130) 
        : (i += 1) 
    {
        try tc.append(0);
    }

    errdefer std.log.err(
        "tc[1]: {b} tc[0]: {b}\n",
        .{ tc.treecode_array[1], tc.treecode_array[0] }
    );

    try std.testing.expectEqual(
        @as(TreecodeWord, 0b100),
        tc.treecode_array[1]
    );
    try std.testing.expectEqual(@as(TreecodeWord, 130), tc.code_length());

    try tc.append(0);

    try std.testing.expectEqual(
        @as(TreecodeWord, 0b1000),
        tc.treecode_array[1]
    );
    try std.testing.expectEqual(@as(TreecodeWord, 131), tc.code_length());
}

test "treecode: append lots of 1"
{
    var tc = try Treecode.init_word(std.testing.allocator, 0b1);
    defer tc.deinit();

    var i:usize = 0;
    while (i < 130) 
        : (i += 1) 
    {
        try tc.append(1);
    }

    errdefer std.log.err(
        "tc[1]: {b} tc[0]: {b}\n",
        .{ tc.treecode_array[1], tc.treecode_array[0] }
    );

    try std.testing.expectEqual(
        @as(TreecodeWord, 0b111),
        tc.treecode_array[1]
    );
    try std.testing.expectEqual(@as(TreecodeWord, 130), tc.code_length());

    try tc.append(0);

    try std.testing.expectEqual(
        @as(TreecodeWord, 0b1011),
        tc.treecode_array[1]
    );
    try std.testing.expectEqual(@as(TreecodeWord, 131), tc.code_length());
}

test "treecode: append beyond one word w/ 1"
{
    var tc = try Treecode.init_word(std.testing.allocator, 0b1);
    defer tc.deinit();

    var i:usize = 0;
    while (i < 258) 
        : (i += 1) 
    {
        try tc.append(1);
    }

    errdefer std.log.err(
        "tc[2]: {b} \n",
        .{ tc.treecode_array[2] }
    );

    try std.testing.expectEqual(
        @as(TreecodeWord, 0b111),
        tc.treecode_array[2]
    );
    try std.testing.expectEqual(@as(TreecodeWord, 258), tc.code_length());

    try tc.append(0);

    try std.testing.expectEqual(
        @as(TreecodeWord, 0b1011),
        tc.treecode_array[2]
    );
    try std.testing.expectEqual(@as(TreecodeWord, 259), tc.code_length());
}

test "treecode: append beyond one word w/ 0"
{
    var tc = try Treecode.init_word(std.testing.allocator, 0b1);
    defer tc.deinit();

    var i:usize = 0;
    while (i < 258) 
        : (i += 1) 
    {
        try tc.append(0);
    }

    errdefer std.log.err(
        "tc[2]: {b} \n",
        .{ tc.treecode_array[2] }
    );

    try std.testing.expectEqual(
        @as(TreecodeWord, 0b100),
        tc.treecode_array[2]
    );
    try std.testing.expectEqual(@as(TreecodeWord, 258), tc.code_length());

    try tc.append(1);

    try std.testing.expectEqual(
        @as(TreecodeWord, 0b1100),
        tc.treecode_array[2]
    );
    try std.testing.expectEqual(@as(TreecodeWord, 259), tc.code_length());
}

test "treecode: append alternating 0 and 1"
{   
    var tc = try Treecode.init_word(std.testing.allocator, 0b1);
    defer tc.deinit();

    var buf_tc = std.ArrayList(u8).init(std.testing.allocator);
    defer buf_tc.deinit();

    var buf_known = std.ArrayList(u8).init(std.testing.allocator);
    defer buf_known.deinit();
    try buf_known.ensureTotalCapacity(1024);
    try buf_known.append("1"[0]);

    buf_tc.clearAndFree();
    try tc.to_str(&buf_tc);
    // try std.testing.expectEqualStrings(buf_known.items, buf_tc.items);

    allocator.free(buf_tc);

    for (0..1)
        |i|
    {

        errdefer std.log.err("iteration: {} \n", .{i});

        const next:u1 = if (@rem(i, 5) == 0) 0 else 1;
        const next_str = (if (@rem(i, 5) == 0) "0" else "1")[0];

        try tc.append(next);
        try buf_known.insert(1, next_str);
    }

    buf_tc.clearAndFree();
    try tc.to_str(&buf_tc);

    errdefer std.log.err(
        "iteration: {} \n  buf_tc:    {s}\n  expected:  {s}\n",
        .{256, buf_tc.items, buf_known.items}
    );

    try std.testing.expectEqual(buf_known.items.len-1, tc.code_length());
    try std.testing.expectEqualStrings(buf_known.items, buf_tc.items);
}

test "treecode: append variable size"
{
    const one = "1"[0];
    const zero = "0"[0];

    // Variable size flavor, adding a mix of 0s and 1s
    var tc = try Treecode.init_word(std.testing.allocator, 0b1);
    defer tc.deinit();

    var buf_tc = std.ArrayList(u8).init(std.testing.allocator);
    defer buf_tc.deinit();

    var buf_known = std.ArrayList(u8).init(std.testing.allocator);
    defer buf_known.deinit();
    try buf_known.ensureTotalCapacity(1024);
    try buf_known.append(one);

    buf_tc.clearAndFree();
    try tc.to_str(&buf_tc);
    try std.testing.expectEqualStrings(buf_known.items, buf_tc.items);

    for (0..1000)
        |i|
    {
        // do the append
        const next:u1 = if (@rem(i, 5) == 0) 0 else 1;
        try tc.append(next);

        buf_tc.clearAndFree();

        try tc.to_str(&buf_tc);

        const next_str = if (@rem(i, 5) == 0) zero else one;
        try buf_known.insert(1, next_str);

        errdefer std.log.err(
            "\niteration: {} \n  buf_tc:    {s}\n  buf_known: {s}\n  next: {b}\n\n",
            .{i, buf_tc.items, buf_known.items, next}
        );

        errdefer std.log.err(
            "\ntc[2]tc[1]tc[0]: {b}{b}{b}",
            .{tc.treecode_array[0], tc.treecode_array[1], tc.treecode_array[2]}
        );

        errdefer std.log.err(
            "\niteration: {} \n  buf_tc:    {s} {s}\n  buf_known: {s} {s}\n  next: {b}\n\n",
            .{
                i, 
                buf_tc.items[128..],
                buf_tc.items[0..127],
                buf_known.items[128..],
                buf_known.items[0..127],
                next
            }
        );

        try std.testing.expectEqual(
            buf_known.items.len - 1,
            tc.code_length()
        );
        try std.testing.expectEqualStrings(
            buf_known.items,
            buf_tc.items
        );
    }
}

test "treecode: Treecode.eql positive" 
{
    var a  = try Treecode.init_word(std.testing.allocator, 1);
    defer a.deinit();

    var b  = try Treecode.init_word(std.testing.allocator, 1);
    defer b.deinit();

    for (0..1000)
       |i|
    {
        errdefer std.log.err(
            "iteration: {} a: {b} b: {b}\n",
            .{i, a.treecode_array[0], b.treecode_array[0]}
        );
        try std.testing.expect(a.eql(b));
        const next:u1 = if (@rem(i, 5) == 0) 0 else 1;
        try a.append(next);
        try b.append(next);
    }
}

test "treecode: Treecode.eql negative" 
{
    {
        const tc_fst = try Treecode.init_word(std.testing.allocator, 0b1101);
        defer tc_fst.deinit();
        const tc_snd = try Treecode.init_word(std.testing.allocator, 0b1011);
        defer tc_snd.deinit();

        try std.testing.expect(tc_fst.eql(tc_snd) == false);
        try std.testing.expect(tc_snd.eql(tc_fst) == false);
    }

    {
        const tc_fst = try Treecode.init_word(std.testing.allocator, 0b1101);
        defer tc_fst.deinit();
        const tc_snd = try Treecode.init_word(std.testing.allocator, 0b1010);
        defer tc_snd.deinit();

        try std.testing.expect(tc_fst.eql(tc_snd) == false);
        try std.testing.expect(tc_snd.eql(tc_fst) == false);
    }
}

test "treecode: Treecode.eql preallocated" 
{
    var a  = try Treecode.init_word(std.testing.allocator, 1);
    defer a.deinit();

    var b  = try Treecode.init_word(std.testing.allocator, 10);
    defer b.deinit();

    var i:usize = 0;
    while (i < 1000)  
        : (i += 1) 
    {
        errdefer std.log.err(
            "iteration: {} a: {b} b: {b}\n",
            .{i, a.treecode_array[0], b.treecode_array[0]}
        );
        try std.testing.expect(a.eql(b) == false);
        const next:u1 = if (@rem(i, 5) == 0) 0 else 1;
        try a.append(next);
        try b.append(next);
    }
}

fn treecode_word_append(
    a: TreecodeWord,
    l_or_r_branch: u1
) TreecodeWord 
{
    const signficant_bits:u8 = WORD_BIT_COUNT - 1 - @clz(a);

    // strip leading bit
    const leading_bit = (
        @as(TreecodeWord, 1) << @as(u7, @intCast(@as(u8, signficant_bits)))
    );

    const a_without_leading_bit = (a - leading_bit) ;
    const leading_bit_shifted = (leading_bit << 1);

    const l_or_r_branch_shifted = (
        @as(TreecodeWord, @intCast(l_or_r_branch) )
        << @as(u7, @intCast((@as(u8, signficant_bits))))
    );

    const result = (
        a_without_leading_bit 
        | leading_bit_shifted
        | l_or_r_branch_shifted
    );

    return result;
}

test "treecode: hash - built from init_word" 
{
    var tc1 = try Treecode.init_word(
        std.testing.allocator, 
        0b101,
    );
    defer tc1.deinit();

    var tc2 = try Treecode.init_word(
        std.testing.allocator,
        0b101,
    );
    defer tc2.deinit();

    try std.testing.expectEqual(
        tc1.hash(),
        tc2.hash()
    );

    try tc1.append(1);
    try tc2.append(1);

    try std.testing.expectEqual(tc1.hash(), tc2.hash());

    try tc1.append(0);
    try tc2.append(0);

    try std.testing.expectEqual(tc1.hash(), tc2.hash());

    try tc1.realloc(1024);
    try std.testing.expectEqual(tc1.hash(), tc2.hash());

    try tc2.append(0);
    try std.testing.expect(tc1.hash() != tc2.hash());

    try tc1.append(0);
    try std.testing.expectEqual(tc1.hash(), tc2.hash());
}

test "treecode: hash - built from init_fill_count"
{
    var tc1 = try Treecode.init_fill_count(std.testing.allocator, 2, 0b1);
    defer tc1.deinit();

    var tc2 = try Treecode.init_fill_count(std.testing.allocator, 2, 0b1);
    defer tc2.deinit();

    errdefer std.log.err("\ntc1: {b}\ntc2: {b}\n\n",
        .{ tc1.treecode_array[1], tc2.treecode_array[1] }
    );

    try std.testing.expectEqual(tc1.hash(), tc2.hash());
}

test "treecode: hash - test long treecode hashes"
{
    var tc1 = try Treecode.init_word(
        std.testing.allocator,
        0b1,
    );
    defer tc1.deinit();

    var tc2 = try tc1.clone();
    defer tc2.deinit();

    try tc1.realloc(1024);
    var i:usize = 0;
    while (i < 128) 
        : (i+=1) 
    {
        try tc1.append(0);
    }

    errdefer std.log.err("\ntc1: {b}{b}\ntc2: {b}\n\n",
        .{
            tc1.treecode_array[1],
            tc1.treecode_array[0],
            tc2.treecode_array[0] 
        }
    );

    try std.testing.expect(tc1.eql(tc2) == false);
    try std.testing.expect(tc1.hash() != tc2.hash());

    i = 0;
    while (i < 128) 
        : (i+=1) 
    {
        try tc2.append(0);
    }

    try std.testing.expectEqual(tc1.hash(), tc2.hash());

    i = 0;
    while (i < 122) 
        : (i+=1) 
    {
        try tc2.append(0);
    }

    try std.testing.expect(tc1.hash() != tc2.hash());

    i = 0;
    while (i < 122) 
        : (i+=1) 
    {
        try tc1.append(0);
    }

    try std.testing.expect(tc1.hash() == tc2.hash());
}

test "treecode: allocator doesn't participate in hash"
{
    var tmp = [_]TreecodeWord{ 0b101 };
    const t1 = Treecode{
        .allocator = undefined,
        .sz = 1,
        .treecode_array = &tmp,
    };
    const t2 = try Treecode.init_word(
        // different allocator
        std.testing.allocator,
        0b101
    );
    defer t2.deinit();
    try std.testing.expectEqual(
        t1.hash(),
        t2.hash()
    );

    try std.testing.expect(t1.eql(t2));
    var thm = TreecodeHashMap(u8).init(std.testing.allocator);
    defer thm.deinit();

    try thm.put(t1, 4);
    try std.testing.expectEqual(
        thm.get(t1), thm.get(t2)
    );
}

test "treecode: init_fill_count" 
{
    const tc = try Treecode.init_fill_count(
        std.testing.allocator,
        2,
        0b1,
    );
    defer tc.deinit();

    try std.testing.expectEqual(
        @as(TreecodeWord, 0b0),
        tc.treecode_array[0],
    );
    try std.testing.expectEqual(
        @as(TreecodeWord, 0b1),
        tc.treecode_array[1],
    );
}

test "treecode: next_step_towards - single word size" 
{
    const TestData = struct{
        source: TreecodeWord,
        dest: TreecodeWord,
        expect: u1,
    };

    const test_data = [_]TestData{
        .{ .source = 0b11,      .dest = 0b101,      .expect = 0b0 },
        .{ .source = 0b11,      .dest = 0b111,      .expect = 0b1 },
        .{ .source = 0b10,      .dest = 0b10011100, .expect = 0b0 },
        .{ .source = 0b10,      .dest = 0b10001100, .expect = 0b0 },
        .{ .source = 0b10,      .dest = 0b10111110, .expect = 0b1 },
        .{ .source = 0b11,      .dest = 0b10101111, .expect = 0b1 },
        .{ .source = 0b101,     .dest = 0b10111101, .expect = 0b1 },
        .{ .source = 0b101,     .dest = 0b10101001, .expect = 0b0 },
        .{ .source = 0b1101001, .dest = 0b10101001, .expect = 0b0 },
    };

    for (test_data, 0..) 
        |t, i| 
    {
        errdefer std.log.err(
            "[{d}] source: {b} dest: {b} expected: {b}",
            .{ i, t.source, t.dest, t.expect }
        );

        const tc_src = try Treecode.init_word(std.testing.allocator, t.source);
        defer tc_src.deinit();

        const tc_dst = try Treecode.init_word(std.testing.allocator, t.dest);
        defer tc_dst.deinit();

        try std.testing.expectEqual(
            t.expect,
            try tc_src.next_step_towards(tc_dst),
        );
    }
}

test "treecode: next_step_towards - larger than a single word" 
{
    var tc_src = try Treecode.init_word(
        std.testing.allocator,
        0b1
    );
    defer tc_src.deinit();
    var tc_dst = try Treecode.init_word(
        std.testing.allocator,
        0b1
    );
    defer tc_dst.deinit();

    // straddle the word boundary
    var i:usize = 0;
    while (i < WORD_BIT_COUNT - 1) 
        : (i += 1) 
    {
        try tc_src.append(0);
        try tc_dst.append(0);
    }

    try std.testing.expectEqual(
        @as(usize, WORD_BIT_COUNT) - 1,
        tc_src.code_length()
    );

    try tc_dst.append(1);

    try std.testing.expectEqual(
        @as(u1, 0b1),
        try tc_src.next_step_towards(tc_dst)
    );

    try tc_src.append(1);

    // add a bunch of values
    i = 0;
    while (i < 1000) 
        : (i += 1) 
    {
        try tc_src.append(0);
        try tc_dst.append(0);
    }

    try tc_dst.append(1);

    try std.testing.expectEqual(
        @as(u1, 0b1),
        try tc_src.next_step_towards(tc_dst)
    );
}

test "treecode: clone - 0b1" 
{
    const tc_src = try Treecode.init_word(
        std.testing.allocator,
        0b1
    );
    defer tc_src.deinit();
    const tc_cln = try tc_src.clone();
    defer tc_cln.deinit();

    // the pointers are different
    try std.testing.expect(
        tc_src.treecode_array.ptr != tc_cln.treecode_array.ptr
    );
    try std.testing.expectEqual(
        tc_src.treecode_array.len,
        tc_cln.treecode_array.len,
    );

    try std.testing.expect(tc_src.eql(tc_cln));
}

test "treecode: clone - add items" 
{
    var tc_src = try Treecode.init_word(
        std.testing.allocator,
        0b1
    );
    defer tc_src.deinit();
    var tc_cln = try tc_src.clone();
    defer tc_cln.deinit();

    try std.testing.expect(tc_src.eql(tc_cln));

    try std.testing.expect(
        tc_src.treecode_array.ptr != tc_cln.treecode_array.ptr
    );
    try std.testing.expectEqual(
        tc_src.treecode_array.len,
        tc_cln.treecode_array.len,
    );

    try tc_src.append(1);

    try std.testing.expect(tc_src.eql(tc_cln) == false);
}

test "treecode: clone - with deinit"
{
    var tc_src = try Treecode.init_word(
        std.testing.allocator,
        0b1
    );

    var tc_cln = try tc_src.clone();

    defer tc_cln.deinit();

    // explicitly deinit the first
    tc_src.deinit();

    try std.testing.expect(tc_src.eql(tc_cln) == false);
}

/// wrapper around std.HashMap for treecodes
pub fn TreecodeHashMap(
    comptime V: type
) type 
{
    return std.HashMap(
        Treecode,
        V,
        struct{
            pub fn hash(
                _: @This(),
                key: Treecode
            ) u64 
            {
                return key.hash();
            }

            pub fn eql(
                _:@This(),
                fst: Treecode,
                snd: Treecode
            ) bool 
            {
                return fst.eql(snd);
            }
        },
        std.hash_map.default_max_load_percentage
    );
}

test "treecode: BidirectionalTreecodeHashMap" 
{
    const allocator = std.testing.allocator;
    const this_type = u64;

    var code_to_thing = TreecodeHashMap(this_type).init(allocator);
    defer code_to_thing.deinit();

    var thing_to_code = std.AutoHashMap(this_type, Treecode).init(allocator);
    defer thing_to_code.deinit();

    var tc = try Treecode.init_word(allocator, 0b1101);
    defer tc.deinit();

    const value: this_type = 3651;

    try code_to_thing.put(tc, value);
    try thing_to_code.put(value, tc);

    try std.testing.expectEqual(value, code_to_thing.get(tc));
    try std.testing.expectEqual(tc, thing_to_code.get(value));
}

/// determine if there is a path between the two codes.  Either can be parent.
pub fn path_exists(
    fst: Treecode,
    snd: Treecode,
) bool 
{
    return (
        fst.eql(snd) 
        or (
            fst.is_superset_of(snd) 
            or snd.is_superset_of(fst)
        )
    );
}

