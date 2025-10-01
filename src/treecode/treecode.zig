//! `Treecode` is a binary encoding of a path through a binary tree.
//!
//! Also includes a `TreecodeHashMap` (`std.HashMap` wrapper for mapping
//! treecodes to values).

const std = @import("std");

/// The type of a single word in a `Treecode`
pub const TreecodeWord = u128;
/// bit width of a single word in a `Treecode`
pub const WORD_BIT_COUNT = @bitSizeOf(TreecodeWord);
/// Hash type for a `Treecode`
pub const Hash = u64;
/// The left or the right branch
pub const l_or_r = enum(u1) { left = 0, right = 1 };

/// All treecodes start with this code
pub const ROOT_TREECODE:TreecodeWord = 0b1;

/// A binary encoding of a path through a binary tree.  The root bit is the
/// left most / LSB, and the directions are read right to left.  Each bit until
/// the root bit indicates which direction down the binary tree to take.
///
/// The root (left most/MSB) bit is always a 1 and is not part of the path.
///
/// The directions:
/// - 0: left child
/// - 1: right child
///
/// Examples:
/// - 0b1 => root bit only (no direction)
/// - 0b1001 => 0b1 001 -> right, left, left
/// - 0b111001 => 0b1 11001 -> right, left, left, right, right
/// - 0b1010 => 0b1 010 -> left, right, left
///
/// In memory, the treecode is implemented as an array of TreecodeWords.  When
/// a path is appended path the capacity of the current word, realloc is
/// triggered to increase capacity.
pub const Treecode = struct {
    /// the array of words that make up the treecode
    treecode_array: []TreecodeWord,

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
            count,
        );

        // zero everything out
        @memset(treecode_array, 0);

        // set the argument in the LSB
        treecode_array[count - 1] = input;

        return .{
            .treecode_array = treecode_array,
        };
    }

    /// initialize from a single TreecodeWord
    pub fn init_word(
        allocator: std.mem.Allocator,
        input: TreecodeWord,
    ) !Treecode 
    {
        const treecode_array = try allocator.dupe(
            TreecodeWord,
            &.{ input },
        );

        return .{
            .treecode_array = treecode_array,
        };
    }

    /// reallocate in place to a larger size container
    fn realloc(
        self: *@This(),
        allocator: std.mem.Allocator,
        new_size: usize,
    ) !void 
    {
        const old_size = self.treecode_array.len;

        self.treecode_array = try allocator.realloc(
            self.treecode_array,
            new_size,
        );

        @memset(self.treecode_array[old_size..], 0);
    }

    /// return a clone of self in freshly allocated memory
    pub fn clone(
        self: @This(),
        allocator: std.mem.Allocator,
    ) !Treecode 
    {
        return .{
            .treecode_array = try allocator.dupe(
                TreecodeWord,
                self.treecode_array,
            ),
        };
    }

    pub fn deinit(
        self: @This(),
        allocator: std.mem.Allocator,
    ) void 
    {
        allocator.free(self.treecode_array);
    }

    /// sentinel bit is not included in the code_length (hence the 127 - )
    pub fn code_length(
        self: @This(),
    ) usize 
    {
        if (self.treecode_array.len == 0) {
            return 0;
        }
        var occupied_words : usize = 0;

        for (0..self.treecode_array.len)
            |i|
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

        return count + (occupied_words * WORD_BIT_COUNT);
    }

    /// By-value equality of the treecode.  IE does not consider the size of
    /// the treecode array 
    pub fn eql(
        self: @This(),
        rhs: Treecode,
    ) bool 
    {
        const self_code_len = self.code_length();

        if (self_code_len != rhs.code_length()) {
            return false;
        }

        const end_word = (self_code_len / WORD_BIT_COUNT) + 1;

        for (
            self.treecode_array[0..end_word],
            rhs.treecode_array[0..end_word],
        )
            |self_word, rhs_word|
        {
            if (self_word != rhs_word) {
                return false;
            }
        }

        return true;
    }

    /// in place append a bit to this treecode. will realloc if needed.
    pub fn append(
        self: *@This(),
        allocator: std.mem.Allocator,
        /// new bit to append to self
        new_branch: l_or_r,
    ) !void 
    {
        if (self.treecode_array.len == 0) {
            return error.InvalidTreecode;
        }

        const current_code_length = self.code_length();

        // index for the new branch
        const next_index = current_code_length + 1;

        // special case where there is only one word in the treecode and there
        // is still room in that one word for an append
        if (next_index < WORD_BIT_COUNT) 
        {
            self.treecode_array[0] = treecode_word_append(
                self.treecode_array[0],
                new_branch,
            );
            return;
        }

        // the last index that can be written to without triggering a realloc
        const last_allocated_index = (
            (self.treecode_array.len * WORD_BIT_COUNT) 
            - 1
        );

        if (next_index > last_allocated_index) 
        {
            // double the size
            try self.realloc(
                allocator,
                self.treecode_array.len*2,
            );
        }

        // move the marker one index over
        const new_marker_word = next_index / WORD_BIT_COUNT;
        const new_marker_index_in_word = @rem(next_index, WORD_BIT_COUNT);

        self.treecode_array[new_marker_word] |= std.math.shl(
            TreecodeWord,
            1,
            new_marker_index_in_word,
        );

        // add the new_branch to the target index in the target word
        const new_data_word = current_code_length / WORD_BIT_COUNT;
        const new_data_index_in_word = @rem(current_code_length, WORD_BIT_COUNT);

        const old_marker_bit = std.math.shl(
            TreecodeWord,
            1,
            new_data_index_in_word,
        );

        // subtract old marker position
        self.treecode_array[new_data_word] = (
            self.treecode_array[new_data_word] - old_marker_bit
        );

        self.treecode_array[new_data_word] |= std.math.shl(
            TreecodeWord,
            @intFromEnum(new_branch),
            new_data_index_in_word,
        );

        return;
    }

    /// determine whether self is a strict superset of rhs
    pub fn is_prefix_of(
        self: @This(),
        rhs: Treecode,
    ) bool 
    {
        const len_self: usize = self.code_length();

        // empty lhs path is always a prefix of rhs, regardless of what rhs is
        if (len_self == 0) {
            return true;
        }

        const len_rhs: usize = rhs.code_length();

        // if rhs is 0 length or shorter than self, self is not a prefix of rhs
        if (len_rhs == 0 or len_rhs < len_self) {
            return false;
        }

        if (len_self < WORD_BIT_COUNT) {
            return treecode_word_is_prefix_of(
                self.treecode_array[0],
                rhs.treecode_array[0],
            );
        }

        const greatest_nonzero_rhs_index = len_self / WORD_BIT_COUNT;

        for (0..greatest_nonzero_rhs_index)
            |i|
        {
            if (self.treecode_array[i] != rhs.treecode_array[i]) {
                return false;
            }
        }

        return treecode_word_is_prefix_of(
            self.treecode_array[greatest_nonzero_rhs_index], 
            rhs.treecode_array[greatest_nonzero_rhs_index]
        );
    }

    /// compute a hash for this treecode
    pub fn hash(
        self: @This(),
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

    /// Given a `dest` code which is a child of `self`, find the next bit after
    /// the bits in `self` that is present in `dest` (IE the next step down the
    /// tree towards the location of `dest`).
    ///
    /// @TODO: this doesn't confirm the assumptions that 
    ///        (1) dest is a child of self
    ///        (2) dest is long enough to have a value at the correct position
    ///        Should it?  Should there be a fallible flavor of this that adds
    ///        the extra checks and can return an error?
    pub fn next_step_towards(
        self: @This(),
        dest: Treecode,
    ) l_or_r 
    {
        std.debug.assert(self.is_prefix_of(dest));

        const self_len = self.code_length();

        const self_len_pos_local = @rem(self_len, WORD_BIT_COUNT);
        const self_len_word = self_len / WORD_BIT_COUNT;

        const mask = std.math.shl(
            TreecodeWord,
            1,
            self_len_pos_local,
        );

        const masked_val = dest.treecode_array[self_len_word] & mask;

        return @enumFromInt(
            std.math.shr(
                TreecodeWord,
                masked_val,
                self_len_pos_local,
            )
        );
    }

    /// formatter for {f}
    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
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
    const allocator = std.testing.allocator;

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
            allocator,
            t.input
        );
        defer tc.deinit(allocator);

        try std.testing.expectEqual(
            t.expected,
            tc.code_length(),
        );
    }
}

test "treecode: code_length - init_fill_count"
{
    const allocator = std.testing.allocator;

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
            allocator,
            t[1],
            t[0],
        );
        defer tc.deinit(allocator);

        try std.testing.expectEqual(
            t[2],
            tc.code_length(),
        );
    }
}

test "treecode: @clz" 
{
    var x: TreecodeWord = 0;
    try std.testing.expectEqual(
        @as(usize, WORD_BIT_COUNT),
        @clz(x),
    );

    for (0..WORD_BIT_COUNT)
        |i|
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

fn treecode_word_is_prefix_of(
    lhs: TreecodeWord,
    rhs: TreecodeWord,
) bool 
{
    if (lhs == rhs or lhs == 0b1) {
        return true;
    }

    if (lhs == 0 or rhs == 0) {
        return false;
    }

    // mask the leading zeros + the marker bit
    const lhs_leading_zeros: usize = @clz(lhs) + 1;
    const mask: TreecodeWord = treecode_word_mask(lhs_leading_zeros);

    const lhs_masked = (lhs & mask);
    const rhs_masked = (rhs & mask);

    return lhs_masked == rhs_masked;
}

test "fmt all ones"
{
    const allocator = std.testing.allocator;

    var ltc = try Treecode.init_word(
        allocator,
        0b1,
    );
    defer ltc.deinit(allocator);

    try ltc.append(allocator, .right);
    for (0..125)
        |_|
    {
        try ltc.append(allocator, .left);
    }
    try ltc.append(allocator, .right);
    try ltc.append(allocator, .left);
    try ltc.append(allocator, .right);

    const result = try std.fmt.allocPrint(
        allocator,
        "{f}",
        .{ ltc },
    );
    defer allocator.free(result);

    try std.testing.expectEqual(
        ltc.code_length() + 1,
        result.len,
    );

    try std.testing.expectEqualStrings(
        (
           "1101000000000000000000000000000000000000000000000000000000"
           ++ "0000000000000000000000000000000000000000000000000000000" 
           ++ "00000000000000001"
        ), 
        result,
    );
}

test "Treecode: format" 
{
    const allocator = std.testing.allocator;
    const one = "1"[0];

    var tc = try Treecode.init_word(
        allocator,
        0b1,
    );
    defer tc.deinit(allocator);

    var known = std.ArrayList(u8){};
    defer known.deinit(allocator);
    try known.append(allocator, one);

    var buf = try std.fmt.allocPrint(
        allocator,
        "{f}",
        .{ tc },
    );

    try std.testing.expectEqualStrings(known.items, buf);

    errdefer std.log.err(
        "known: {s} buf: {s} \n",
        .{ known.items, buf } 
    );

    try tc.append(allocator, .right);
    try known.append(allocator, one);

    allocator.free(buf);
    buf = try std.fmt.allocPrint(
        allocator,
        "{f}",
        .{ tc },
    );

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
        const next = .right;

        try known.insert(allocator,1, one);
        try tc.append(allocator, next);

        buf = try std.fmt.allocPrint(
            allocator,
            "{f}",
            .{ tc },
        );
        defer allocator.free(buf);

        errdefer std.log.err(
            "iteration: {} known: {s} buf: {s} \n",
            .{ i, known.items, buf },
        );

        try std.testing.expectEqualStrings(known.items, buf);
    }
}


test "TreecodeWord: is a prefix" 
{
    inline for (
        .{ 
            .{ 0b11,    0b0,         false}, 
            .{ 0b0,     0b01,        false}, 
            .{ 0b11,    0b1101,      true}, 
            .{ 0b1101,  0b11001101,  true}, 
            .{ 0b11010, 0b110011010, true}, 
            .{ 0b11001, 0b11001101,  false}, 
        },
        0..
    ) |t, ind|
    {
        errdefer std.debug.print(
            "ACK! Problem with loop: [{d}]\n lhs: {b}\n rhs: {b}\n {any}",
            .{ ind, t[0], t[1], t[2] },
        );
        try std.testing.expectEqual(
            treecode_word_is_prefix_of(t[0], t[1]),
            t[2]
        );
    }
}

test "Treecode: is a prefix" 
{
    const allocator = std.testing.allocator;

    // positive case, ending in 1
    inline for(
        .{
            // lhs         rhs      lhs is_prefix_of rhs
            .{ 0b1,        0b1,        true },
            .{ 0b1,        0b1101,     true },
            .{ 0b1,        0b101010100100010101110001,  true },
            .{ 0b10,       0b1,        false },
            .{ 0b10,       0b11,       false },
            .{ 0b11,       0b11,       true },
            .{ 0b11,       0b101,      true },
            .{ 0b1101101,  0b1101,     false },
            .{ 0b11011010, 0b11010,    false },
            .{ 0b1101101,  0b11001,    false },
            .{ 0b1101,     0b1101101,  true },
            .{ 0b11010,    0b11011010, true },
            .{ 0b11001,    0b1101101,  false },
        },
        0..
    ) |t, i|
    {
        const lhs = try Treecode.init_word(
            allocator,
            t[0],
        );
        defer lhs.deinit(allocator);

        const rhs = try Treecode.init_word(
            allocator,
            t[1],
        );
        defer rhs.deinit(allocator);

        errdefer std.debug.print(
            "Problem with loop: [{d}]\n  lhs: {f}\n rhs: {f}\n expected: {any}\n",
            .{ i, lhs, rhs, t[2] },
        );

        try std.testing.expectEqual(
            lhs.is_prefix_of(rhs),
            t[2],
        );
    }
}

test "Treecode: is prefix of very long"
{
    const allocator = std.testing.allocator;

    var lhs  = try Treecode.init_word(
        allocator,
        0b11101,
    );
    defer lhs.deinit(allocator);

    var rhs  = try Treecode.init_word(
        allocator,
        0b111111101,
        //   0x1101
    );
    defer rhs.deinit(allocator);

    for (9..1000)
        |i|
    {
        errdefer std.log.err(
            "\n\niteration: {}\n lhs: {f} \n rhs: {f}\n",
            .{ i, lhs, rhs, },
        );

        try lhs.append(allocator, .right);
        try rhs.append(allocator, .right);

        try std.testing.expect(lhs.is_prefix_of(rhs));
    }
}

test "treecode: append" 
{
    inline for (
        .{ 
            .{ 0b10, 0b1, .left },
            .{ 0b11, 0b1, .right },
            .{ 0b1101, 0b101, .right },
            .{ 0b1001, 0b101, .left },
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
    const allocator = std.testing.allocator;

    var tc = try Treecode.init_word(
        allocator,
        ROOT_TREECODE,
    );
    defer tc.deinit(allocator);

    for (0..130)
        |_|
    {
        try tc.append(allocator, .left);
    }

    errdefer std.log.err(
        "tc[1]: {b} tc[0]: {b}\n",
        .{ tc.treecode_array[1], tc.treecode_array[0] }
    );

    try std.testing.expectEqual(
        @as(TreecodeWord, 0b100),
        tc.treecode_array[1]
    );
    try std.testing.expectEqual(
        @as(TreecodeWord, 130),
        tc.code_length()
    );

    try tc.append(allocator, .left);

    try std.testing.expectEqual(
        @as(TreecodeWord, 0b1000),
        tc.treecode_array[1]
    );
    try std.testing.expectEqual(
        @as(TreecodeWord, 131),
        tc.code_length(),
    );
}

test "treecode: append lots of 1"
{
    const allocator = std.testing.allocator;

    var tc = try Treecode.init_word(
        std.testing.allocator,
        0b1
    );
    defer tc.deinit(allocator);

    for (0..130)
        |_|
    {
        try tc.append(allocator, .right);
    }

    errdefer std.log.err(
        "tc[1]: {b} tc[0]: {b}\n",
        .{ tc.treecode_array[1], tc.treecode_array[0] }
    );

    try std.testing.expectEqual(
        @as(TreecodeWord, 0b111),
        tc.treecode_array[1]
    );
    try std.testing.expectEqual(130, tc.code_length());

    try tc.append(allocator, .left);

    try std.testing.expectEqual(
        @as(TreecodeWord, 0b1011),
        tc.treecode_array[1]
    );
    try std.testing.expectEqual(131, tc.code_length());
}

test "treecode: append beyond one word w/ 1"
{
    const allocator = std.testing.allocator;

    var tc = try Treecode.init_word(
        allocator,
        ROOT_TREECODE,
    );
    defer tc.deinit(allocator);

    for (0..258)
        |_|
    {
        try tc.append(allocator, .right);
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

    try tc.append(allocator, .left);

    try std.testing.expectEqual(
        @as(TreecodeWord, 0b1011),
        tc.treecode_array[2]
    );
    try std.testing.expectEqual(@as(TreecodeWord, 259), tc.code_length());
}

test "treecode: append beyond one word w/ 0"
{
    const allocator = std.testing.allocator;

    var tc = try Treecode.init_word(
        allocator,
        0b1,
    );
    defer tc.deinit(allocator);

    for (0..258)
        |_|
    {
        try tc.append(allocator, .left);
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

    try tc.append(allocator, .right);

    try std.testing.expectEqual(
        @as(TreecodeWord, 0b1100),
        tc.treecode_array[2]
    );
    try std.testing.expectEqual(@as(TreecodeWord, 259), tc.code_length());
}

test "treecode: append alternating 0 and 1"
{   
    const allocator = std.testing.allocator;

    var tc = try Treecode.init_word(allocator, 0b1);
    defer tc.deinit(allocator);

    var buf_known = std.ArrayList(u8){};
    defer buf_known.deinit(allocator);
    try buf_known.ensureTotalCapacity(allocator, 1024);
    try buf_known.append(allocator, "1"[0]);

    var buf_tc = try std.fmt.allocPrint(allocator,"{f}", .{ tc });
    try std.testing.expectEqualStrings(buf_known.items, buf_tc);

    allocator.free(buf_tc);

    for (0..1)
        |i|
    {

        errdefer std.log.err("iteration: {} \n", .{i});

        const next:l_or_r = (
            if (@rem(i, 5) == 0) .left else .right
        );
        const next_str = (if (@rem(i, 5) == 0) "0" else "1")[0];

        try tc.append(allocator, next);
        try buf_known.insert(allocator, 1, next_str);
    }

    buf_tc = try std.fmt.allocPrint(allocator,"{f}", .{ tc });
    defer allocator.free(buf_tc);

    errdefer std.log.err(
        "iteration: {} \n  buf_tc:    {s}\n  expected:  {s}\n",
        .{256, buf_tc, buf_known.items}
    );

    try std.testing.expectEqual(buf_known.items.len-1, tc.code_length());
    try std.testing.expectEqualStrings(buf_known.items, buf_tc);
}

test "treecode: append variable size"
{
    const allocator = std.testing.allocator;

    const one = "1"[0];
    const zero = "0"[0];

    // Variable size flavor, adding a mix of 0s and 1s
    var tc = try Treecode.init_word(allocator, 0b1);
    defer tc.deinit(allocator);

    var buf_known = std.ArrayList(u8){};
    defer buf_known.deinit(allocator);
    try buf_known.ensureTotalCapacity(allocator, 1024);
    buf_known.appendAssumeCapacity(one);

    var buf = try std.fmt.allocPrint(
        allocator,
        "{f}",
        .{ tc }
    );
    try std.testing.expectEqualStrings(buf_known.items, buf);
    allocator.free(buf);

    for (0..1000)
        |i|
    {
        // do the append
        const next:l_or_r = if (@rem(i, 5) == 0) .left else .right;
        try tc.append(allocator, next);

        buf = try std.fmt.allocPrint(allocator,"{f}", .{ tc });
        defer allocator.free(buf);

        const next_str = if (@rem(i, 5) == 0) zero else one;
        buf_known.insertAssumeCapacity(1, next_str);

        errdefer std.log.err(
            "\niteration: {} \n  buf_tc:    {s}\n  buf_known: {s}\n"
            ++ "  next: {b}\n\n",
            .{i, buf, buf_known.items, next}
        );

        errdefer std.log.err(
            "\ntc[2]tc[1]tc[0]: {b}{b}{b}",
            .{
                tc.treecode_array[0],
                tc.treecode_array[1],
                tc.treecode_array[2],
            },
        );

        errdefer std.log.err(
            "\niteration: {} \n  buf_tc:    {s} {s}\n"
            ++ "  buf_known: {s} {s}\n  next: {b}\n\n",
            .{
                i, 
                buf[128..],
                buf[0..127],
                buf_known.items[128..],
                buf_known.items[0..127],
                next,
            }
        );

        try std.testing.expectEqual(
            buf_known.items.len - 1,
            tc.code_length(),
        );
        try std.testing.expectEqualStrings(
            buf_known.items,
            buf,
        );
    }
}

test "treecode: Treecode.eql positive" 
{
    const allocator = std.testing.allocator;

    var a  = try Treecode.init_word(allocator, 1);
    defer a.deinit(allocator);

    var b  = try Treecode.init_word(allocator, 1);
    defer b.deinit(allocator);

    for (0..1000)
       |i|
    {
        errdefer std.log.err(
            "iteration: {} a: {b} b: {b}\n",
            .{i, a.treecode_array[0], b.treecode_array[0]}
        );
        try std.testing.expect(a.eql(b));
        const next:l_or_r = if (@rem(i, 5) == 0) .left else .right;
        try a.append(allocator, next);
        try b.append(allocator, next);
    }
}

test "treecode: Treecode.eql negative" 
{
    const allocator = std.testing.allocator;

    {
        const tc_fst = try Treecode.init_word(
            allocator,
            0b1101,
        );
        defer tc_fst.deinit(allocator);

        const tc_snd = try Treecode.init_word(
            allocator, 
            0b1011,
        );
        defer tc_snd.deinit(allocator);

        try std.testing.expect(tc_fst.eql(tc_snd) == false);
        try std.testing.expect(tc_snd.eql(tc_fst) == false);
    }

    {
        const tc_fst = try Treecode.init_word(
            allocator,
            0b1101,
        );
        defer tc_fst.deinit(allocator);

        const tc_snd = try Treecode.init_word(
            allocator,
            0b1010,
        );
        defer tc_snd.deinit(allocator);

        try std.testing.expect(tc_fst.eql(tc_snd) == false);
        try std.testing.expect(tc_snd.eql(tc_fst) == false);
    }
}

test "treecode: Treecode.eql preallocated" 
{
    const allocator = std.testing.allocator;

    var a  = try Treecode.init_word(allocator, 1);
    defer a.deinit(allocator);

    var b  = try Treecode.init_word(allocator, 10);
    defer b.deinit(allocator);

    for (0..1000)
        |i|
    {
        errdefer std.log.err(
            "iteration: {} a: {b} b: {b}\n",
            .{i, a.treecode_array[0], b.treecode_array[0]}
        );
        try std.testing.expect(a.eql(b) == false);
        const next:l_or_r = if (@rem(i, 5) == 0) .left else .right;
        try a.append(allocator, next);
        try b.append(allocator, next);
    }
}

/// append a bit to the next free bit in `target_word`.  Assumes that
/// `target_word` has capacity for `new_branch`.
fn treecode_word_append(
    target_word: TreecodeWord,
    /// bit to append to `target_word`
    new_branch: l_or_r,
) TreecodeWord 
{
    const signficant_bits:u8 = WORD_BIT_COUNT - 1 - @clz(target_word);

    // strip leading bit
    const leading_bit = (
        @as(TreecodeWord, 1) << @as(u7, @intCast(@as(u8, signficant_bits)))
    );

    const a_without_leading_bit = (target_word - leading_bit) ;
    const leading_bit_shifted = (leading_bit << 1);

    const l_or_r_branch_shifted = (
        @as(TreecodeWord, @intCast(@intFromEnum(new_branch)) )
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
    const allocator = std.testing.allocator;

    var tc1 = try Treecode.init_word(
        allocator, 
        0b101,
    );
    defer tc1.deinit(allocator);

    var tc2 = try Treecode.init_word(
        allocator,
        0b101,
    );
    defer tc2.deinit(allocator);

    try std.testing.expectEqual(
        tc1.hash(),
        tc2.hash()
    );

    try tc1.append(allocator, .right);
    try tc2.append(allocator, .right);

    try std.testing.expectEqual(tc1.hash(), tc2.hash());

    try tc1.append(allocator, .left);
    try tc2.append(allocator, .left);

    try std.testing.expectEqual(tc1.hash(), tc2.hash());

    try tc1.realloc(allocator, 1024);
    try std.testing.expectEqual(tc1.hash(), tc2.hash());

    try tc2.append(allocator, .left);
    try std.testing.expect(tc1.hash() != tc2.hash());

    try tc1.append(allocator, .left);
    try std.testing.expectEqual(tc1.hash(), tc2.hash());
}

test "treecode: hash - built from init_fill_count"
{
    const allocator = std.testing.allocator;

    var tc1 = try Treecode.init_fill_count(
        allocator,
        2,
        0b1,
    );
    defer tc1.deinit(allocator);

    var tc2 = try Treecode.init_fill_count(
        allocator,
        2,
        0b1,
    );
    defer tc2.deinit(allocator);

    errdefer std.log.err(
        "\ntc1: {b}\ntc2: {b}\n\n",
        .{ tc1.treecode_array[1], tc2.treecode_array[1] }
    );

    try std.testing.expectEqual(tc1.hash(), tc2.hash());
}

test "treecode: hash - test long treecode hashes"
{
    const allocator = std.testing.allocator;

    var tc1 = try Treecode.init_word(
        allocator,
        0b1,
    );
    defer tc1.deinit(allocator);

    var tc2 = try tc1.clone(allocator);
    defer tc2.deinit(allocator);

    try tc1.realloc(allocator, 1024);
    
    for (0..128)
        |_|
    {
        try tc1.append(allocator, .left);
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

    for (0..128)
        |_|
    {
        try tc2.append(allocator, .left);
    }

    try std.testing.expectEqual(tc1.hash(), tc2.hash());

    for (0..122)
        |_|
    {
        try tc2.append(allocator, .left);
    }

    try std.testing.expect(tc1.hash() != tc2.hash());

    for (0..122)
        |_|
    {
        try tc1.append(allocator, .left);
    }

    try std.testing.expect(tc1.hash() == tc2.hash());
}

test "treecode: allocator doesn't participate in hash"
{
    const allocator = std.testing.allocator;

    var tmp = [_]TreecodeWord{ 0b101 };
    const t1 = Treecode{
        .treecode_array = &tmp,
    };
    const t2 = try Treecode.init_word(
        // different allocator
        allocator,
        0b101,
    );
    defer t2.deinit(allocator);

    try std.testing.expectEqual(t1.hash(), t2.hash());
    try std.testing.expect(t1.eql(t2));

    var thm = TreecodeHashMap(u8).init(allocator);
    defer thm.deinit();
    try thm.put(t1, 4);

    try std.testing.expectEqual(thm.get(t1), thm.get(t2));
}

test "treecode: init_fill_count" 
{
    const allocator = std.testing.allocator;

    const tc = try Treecode.init_fill_count(
        allocator,
        2,
        0b1,
    );
    defer tc.deinit(allocator);

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
    const allocator = std.testing.allocator;

    const TestData = struct{
        source: TreecodeWord,
        dest: TreecodeWord,
        expect: l_or_r,
    };

    const test_data = [_]TestData{
        .{ .source = 0b11,      .dest = 0b101,      .expect = .left},
        .{ .source = 0b11,      .dest = 0b111,      .expect = .right},
        .{ .source = 0b10,      .dest = 0b10011100, .expect = .left},
        .{ .source = 0b10,      .dest = 0b10001100, .expect = .left},
        .{ .source = 0b10,      .dest = 0b10111110, .expect = .right},
        .{ .source = 0b11,      .dest = 0b10101111, .expect = .right},
        .{ .source = 0b101,     .dest = 0b10111101, .expect = .right},
        .{ .source = 0b101,     .dest = 0b10101001, .expect = .left},
        .{ .source = 0b1101001, .dest = 0b10101001, .expect = .left},
    };

    for (test_data, 0..) 
        |t, i| 
    {
        errdefer std.log.err(
            "[{d}] source: {b} dest: {b} expected: {b}",
            .{ i, t.source, t.dest, t.expect }
        );

        const tc_src = try Treecode.init_word(
            allocator,
            t.source
        );
        defer tc_src.deinit(allocator);

        const tc_dst = try Treecode.init_word(
            allocator,
            t.dest
        );
        defer tc_dst.deinit(allocator);

        try std.testing.expectEqual(
            t.expect,
            tc_src.next_step_towards(tc_dst),
        );
    }
}

test "treecode: next_step_towards - larger than a single word" 
{
    const allocator = std.testing.allocator;

    var tc_src = try Treecode.init_word(
        allocator,
        0b1,
    );
    defer tc_src.deinit(allocator);

    var tc_dst = try Treecode.init_word(
        allocator,
        0b1,
    );
    defer tc_dst.deinit(allocator);

    // straddle the word boundary
    for (0..WORD_BIT_COUNT-1)
        |_|
    {
        try tc_src.append(allocator, .left);
        try tc_dst.append(allocator, .left);
    }

    try std.testing.expectEqual(
        @as(usize, WORD_BIT_COUNT) - 1,
        tc_src.code_length(),
    );

    try tc_dst.append(allocator, .right);

    try std.testing.expectEqual(
        0b1,
        @intFromEnum(tc_src.next_step_towards(tc_dst))
    );
    try std.testing.expectEqual(
        .right,
        tc_src.next_step_towards(tc_dst)
    );

    try tc_src.append(allocator, .right);

    // add a bunch of values
    for (0..1000)
        |_|
    {
        try tc_src.append(allocator, .left);
        try tc_dst.append(allocator, .left);
    }

    try tc_dst.append(allocator, .right);

    try std.testing.expectEqual(
        0b1,
        @intFromEnum(tc_src.next_step_towards(tc_dst)),
    );
}

test "treecode: clone - 0b1" 
{
    const allocator = std.testing.allocator;

    const tc_src = try Treecode.init_word(
        allocator,
        0b1,
    );
    defer tc_src.deinit(allocator, );

    const tc_cln = try tc_src.clone(allocator);
    defer tc_cln.deinit(allocator, );

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
    const allocator = std.testing.allocator;

    var tc_src = try Treecode.init_word(
        allocator,
        0b1,
    );
    defer tc_src.deinit(allocator);
    var tc_cln = try tc_src.clone(allocator);
    defer tc_cln.deinit(allocator);

    try std.testing.expect(tc_src.eql(tc_cln));

    try std.testing.expect(
        tc_src.treecode_array.ptr != tc_cln.treecode_array.ptr
    );
    try std.testing.expectEqual(
        tc_src.treecode_array.len,
        tc_cln.treecode_array.len,
    );

    try tc_src.append(allocator, .right);

    try std.testing.expect(tc_src.eql(tc_cln) == false);
}

test "treecode: clone - with deinit"
{
    const allocator = std.testing.allocator;

    var tc_src = try Treecode.init_word(
        allocator,
        0b1,
    );

    var tc_cln = try tc_src.clone(allocator);

    defer tc_cln.deinit(allocator);

    // explicitly deinit the first
    tc_src.deinit(allocator);

    try std.testing.expect(tc_src.eql(tc_cln) == false);
}

/// wrapper around std.HashMap for treecodes
pub fn TreecodeHashMap(
    comptime V: type
) type 
{
    // @TODO: use the unmanaged flavor
    return std.HashMap(
        Treecode,
        V,
        struct{
            pub fn hash(
                _: @This(),
                key: Treecode,
            ) u64 
            {
                return key.hash();
            }

            pub fn eql(
                _:@This(),
                fst: Treecode,
                snd: Treecode,
            ) bool 
            {
                return fst.eql(snd);
            }
        },
        std.hash_map.default_max_load_percentage,
    );
}

test "treecode: BidirectionalTreecodeHashMap" 
{
    const allocator = std.testing.allocator;
    const this_type = u64;

    var code_to_thing = TreecodeHashMap(this_type).init(allocator);
    defer code_to_thing.deinit();

    var thing_to_code = std.AutoHashMap(
        this_type,
        Treecode
    ).init(allocator);
    defer thing_to_code.deinit();

    var tc = try Treecode.init_word(
        allocator,
        0b1101,
    );
    defer tc.deinit(allocator);

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
            fst.is_prefix_of(snd) 
            or snd.is_prefix_of(fst)
        )
    );
}
