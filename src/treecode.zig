const std = @import("std");

const treecode_word = u128;
const WORD_BIT_COUNT = @bitSizeOf(treecode_word);
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
    sz: usize,
    treecode_array: []treecode_word,
    allocator: std.mem.Allocator,

    pub fn init_empty(allocator: std.mem.Allocator) !Treecode {
        return .{
            .sz = 0,
            .treecode_array = try allocator.alloc(treecode_word, 0),
            .allocator = allocator,
        };
    }

    pub fn init_fill_count(
        allocator: std.mem.Allocator,
        count: usize,
        input: treecode_word,
    ) !Treecode {
        if (count == 0) {
            return error.InvalidCount;
        }

        var treecode_array:[]treecode_word = try allocator.alloc(
            treecode_word,
            count
        );

        // zero everything out
        std.mem.set(treecode_word, treecode_array, 0);

        // set the argument in the LSB
        treecode_array[count - 1] = input;

        return .{
            .allocator = allocator,
            .sz = count,
            .treecode_array = treecode_array 
        };
    }

    pub fn init_word(
        allocator: std.mem.Allocator,
        input: treecode_word,
    ) !Treecode {
        var treecode_array:[]treecode_word = try allocator.alloc(
            treecode_word,
            1
        );

        treecode_array[0] = input;
        return .{
            .allocator = allocator,
            .sz = 1,
            .treecode_array = treecode_array 
        };
    }

    fn realloc(self: *@This(), new_size: usize) !void {
        self.treecode_array = try self.allocator.realloc(
            self.treecode_array,
            new_size
        );

        std.mem.set(treecode_word, self.treecode_array[self.sz..], 0);

        self.sz = new_size;
    }

    pub fn clone(self: @This()) !Treecode {
        var result_array = try self.allocator.alloc(treecode_word, self.sz);

        for (self.treecode_array) |tc, index| {
            result_array[index] = tc;
        }

        return .{
            .sz = self.sz,
            .treecode_array = result_array,
            .allocator = self.allocator,
        };
    }

    pub fn deinit(self: @This()) void {
        self.allocator.free(self.treecode_array);
    }

    // sentinel bit is not included in the code_length (hence the 127 - )
    pub fn code_length(self: @This()) usize {
        if (self.sz == 0) {
            return 0;
        }
        var occupied_words : usize = 0;
        var i : usize = 0;

        while (i < self.sz) {
            if (self.treecode_array[i] != 0) {
                occupied_words = i;
            }
            i += 1;
        }

        var count = (
            (WORD_BIT_COUNT - 1) - @clz(self.treecode_array[occupied_words])
        );

        if (occupied_words == 0) {
            return count;
        }

        return count + (occupied_words) * WORD_BIT_COUNT;
    }

    pub fn eql(self: @This(), other: Treecode) bool {
        const len_self = self.code_length();
        const len_other = other.code_length();

        if (len_self != len_other) {
            return false;
        }

        var greatest_nozero_index: usize = len_self / WORD_BIT_COUNT;
        var i:usize = 0;
        while (i <= greatest_nozero_index): (i += 1) {
            if (self.treecode_array[i] != other.treecode_array[i]) {
                return false;
            }
        }

        return true;
    }

    // will realloc if needed
    pub fn append(
        self: *@This(),
        l_or_r_branch: u1,
    ) !void
    {
        if (self.sz == 0) {
            return error.InvalidTreecode;
        }

        const len = self.code_length();

        if (len < (WORD_BIT_COUNT - 1)) {
            self.treecode_array[0] = treecode_word_append(
                self.treecode_array[0],
                l_or_r_branch
            );
            return;
        }

        var space_available = self.sz * WORD_BIT_COUNT - 1;
        const next_index = len + 1;

        if (next_index >= space_available) {
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
            treecode_word,
            1,
            new_marker_location_in_slot
        );

        const new_data_location_abs = len; 
        const new_data_slot = new_data_location_abs / WORD_BIT_COUNT;
        const new_data_location_in_slot = (
            @rem(new_data_location_abs, WORD_BIT_COUNT)
        );

        const old_marker_bit = std.math.shl(
            treecode_word,
            1,
            new_data_location_in_slot
        );

        // subtract old marker position
        self.treecode_array[new_data_slot] = (
            self.treecode_array[new_data_slot] 
            - old_marker_bit
        );

        self.treecode_array[new_data_slot] |= std.math.shl(
            treecode_word,
            l_or_r_branch,
            new_data_location_in_slot
        );

        return;
    }

    pub fn is_superset_of(self: @This(), rhs: Treecode) bool {
        var len_self: usize = self.code_length();
        var len_rhs: usize = rhs.code_length();

        if (len_self == 0 or len_rhs == 0 or len_rhs > len_self) {
            return false;
        }

        if (len_self <= WORD_BIT_COUNT) {
            return treecode_word_b_is_a_subset(
                self.treecode_array[0],
                rhs.treecode_array[0],
            );
        }

        var greatest_nonzero_rhs_index: usize = (
            len_rhs / WORD_BIT_COUNT
        );
        var i:usize = 0;
        while (i < greatest_nonzero_rhs_index) : (i += 1) {
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

        var mask: treecode_word = treecode_word_mask(mask_bits);

        const self_masked = (
            self.treecode_array[greatest_nonzero_rhs_index] & mask
        );
        const rhs_masked = (
            rhs.treecode_array[greatest_nonzero_rhs_index] & mask
        );

        return (self_masked == rhs_masked);
    }

    pub fn to_str(self: @This(), buf:*std.ArrayList(u8)) !void {

        try buf.ensureTotalCapacity(self.code_length());

        const marker_pos_abs = self.code_length();
        const last_index = (marker_pos_abs / WORD_BIT_COUNT);

        for (self.treecode_array) |tc, index| {
            if (index > last_index) {
                break;
            }

            var this_tc = tc;
            var end_at:usize = WORD_BIT_COUNT;

            if (index == last_index) {
                end_at = @rem(marker_pos_abs, WORD_BIT_COUNT) + 1;
            }

            var bits_shifted:usize = 0;

            // scoot each bit of this treecode over and see if its 1
            while (bits_shifted < end_at) : (bits_shifted += 1) {
                var result = this_tc & 1;
                try buf.insert(0, @intCast(u8, result));
                this_tc >>= 1;
            }
        }
    }

    pub fn hash(self: @This()) Hash {
        var hasher = std.hash.Wyhash.init(0);
        
        for (self.treecode_array) |tc, index| {
            if (tc > 0) {
                std.hash.autoHash(&hasher, index + 1);
                std.hash.autoHash(&hasher, tc + 1);
            }
        }

        return hasher.final();
    }

    pub fn next_step_towards(self: @This(), dest: Treecode) !u1 {
        const self_len = self.code_length();

        const self_len_pos_local = @rem(self_len, WORD_BIT_COUNT);
        const self_len_word = self_len / WORD_BIT_COUNT;

        const mask = std.math.shl(treecode_word, 1, self_len_pos_local);

        const masked_val = dest.treecode_array[self_len_word] & mask;

        return @intCast(u1, std.math.shr(treecode_word, masked_val, self_len_pos_local));
    }


};

test "treecode: code_length" {
    {
        var tc  = try Treecode.init_word(std.testing.allocator, 1);
        defer tc.deinit();

        try std.testing.expectEqual(@as(usize, 0), tc.code_length());
    }

    {
        var tc  = try Treecode.init_word(std.testing.allocator, 0b11);
        defer tc.deinit();

        try std.testing.expectEqual(@as(usize, 1), tc.code_length());
    }

    {
        var tc  = try Treecode.init_word(std.testing.allocator, 0b1111111);
        defer tc.deinit();

        try std.testing.expectEqual(@as(usize, 6), tc.code_length());
    }

    {
        // top word is 1, lower word is 0, therefore codelength is 
        // WORD_BIT_COUNT
        var tc  = try Treecode.init_fill_count(std.testing.allocator, 2, 0b1);
        defer tc.deinit();

        try std.testing.expectEqual(
            @as(usize, WORD_BIT_COUNT),
            tc.code_length()
        );
    }

    {
        var tc  = try Treecode.init_fill_count(std.testing.allocator, 8, 0b1);
        defer tc.deinit();

        try std.testing.expectEqual(
            @as(usize, 7*WORD_BIT_COUNT),
            tc.code_length()
        );
    }

    {
        var tc  = try Treecode.init_fill_count(std.testing.allocator, 8, 0b11);
        defer tc.deinit();

        try std.testing.expectEqual(
            @as(usize, 7*WORD_BIT_COUNT + 1),
            tc.code_length()
        );
    }
}

test "treecode: @clz" {
    var x: treecode_word = 0;
    try std.testing.expectEqual(@as(usize, WORD_BIT_COUNT), @clz(x));

    var i: treecode_word = 0;

    while (i < WORD_BIT_COUNT) : (i += 1) {
        try std.testing.expectEqual(i, WORD_BIT_COUNT - @clz(x));
        x = (x << 1) | 1;
    }
}

fn treecode_word_mask(leading_zeros: usize) treecode_word {
    return (
        @intCast(treecode_word, 1) << (
            @intCast(u7, (WORD_BIT_COUNT - leading_zeros))
        )
    ) - 1;
}

fn treecode_word_b_is_a_subset(a: treecode_word, b: treecode_word) bool {
    if (a == b) {
        return true;
    }

    if (a == 0 or b == 0) {
        return false;
    }

    const leading_zeros: usize = @clz(b) + 1;
    const mask: treecode_word = treecode_word_mask(leading_zeros);

    const a_masked = (a & mask);
    const b_masked = (b & mask);

    return a_masked == b_masked;
}

test "to_string" {
    var tc = try Treecode.init_word(std.testing.allocator, 0b1);
    defer tc.deinit();

    var known = std.ArrayList(u8).init(std.testing.allocator);
    defer known.deinit();
    try known.append(1);


    var buf = std.ArrayList(u8).init(std.testing.allocator);
    defer buf.deinit();
    try tc.to_str(&buf);

    try std.testing.expectEqualStrings(known.items, buf.items);
    errdefer std.debug.print(
        "known: {b} buf: {b} \n",
        .{ known.items, buf.items } 
    );

    try tc.append(1);
    try known.append(1);

    buf.clearAndFree();
    try tc.to_str(&buf);

    errdefer std.debug.print(
        "known: {b} buf: {b} \n",
        .{ known.items, buf.items } 
    );
    try std.testing.expectEqualStrings(known.items, buf.items);

    var i : usize= 0;
    while (i < 10) : (i += 1) {
        // const next:u1 = if (i & 5 != 0) 0 else 1;
        const next:u1 = 1;

        try known.append(next);

        try tc.append(next);
        buf.clearAndFree();
        try tc.to_str(&buf);

        errdefer std.debug.print(
            "iteration: {} known: {b} buf: {b} \n",
            .{ i, known.items, buf.items } 
        );

        try std.testing.expectEqualStrings(known.items, buf.items);
    }
}


test "treecode_word: is a subset" {
        // positive case, ending in 1
        {
            const tc_word_superset:treecode_word = 0b11001101;
            const tc_word_subset:treecode_word = 0b1101;

            try std.testing.expect(
                treecode_word_b_is_a_subset(tc_word_superset, tc_word_subset)
            );
        }

        // positive case, ending in 0
        {
            const tc_word_superset:treecode_word = 0b110011010;
            const tc_word_subset:treecode_word = 0b11010;

            try std.testing.expect(
                treecode_word_b_is_a_subset(tc_word_superset, tc_word_subset)
            );
        }

        // negative case 
        {
            const tc_word_superset:treecode_word = 0b11001101;
            const tc_word_subset:treecode_word = 0b11001;

            try std.testing.expectEqual(
                treecode_word_b_is_a_subset(tc_word_superset, tc_word_subset),
                false
            );
        }
}

test "treecode: is a superset" {
    // positive case, ending in 1
    {
        const tc_superset = try Treecode.init_word(
            std.testing.allocator, 0b11001101
        );
        defer tc_superset.deinit();
        const tc_subset = try Treecode.init_word(
            std.testing.allocator, 0b1101
        );
        defer tc_subset.deinit();

        try std.testing.expect(tc_superset.is_superset_of(tc_subset));
    }

    // positive case, ending in 0
    {
        const tc_superset = try Treecode.init_word(
            std.testing.allocator, 0b110011010
        );
        defer tc_superset.deinit();
        const tc_subset = try Treecode.init_word(
            std.testing.allocator,
            0b11010
        );
        defer tc_subset.deinit();

        try std.testing.expect(tc_superset.is_superset_of(tc_subset));
    }

    // positive case, very long
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
        while (i < 124)  : (i += 1) {
            try tc_superset.append(1);
            try tc_subset.append(1);
        }

        errdefer std.debug.print(
            "\n\niteration: {}\n superset: {b} \n subset:   {b}\n\n",
            .{i, tc_superset.treecode_array[1], tc_subset.treecode_array[1]}
        );

        try std.testing.expect(tc_superset.is_superset_of(tc_subset));

        i = 4;
        while (i < 1000)  : (i += 1) {
            errdefer std.debug.print(
                "\n\niteration: {}\n superset: {b} \n subset:   {b}\n\n",
                .{i, tc_superset.treecode_array[1], tc_subset.treecode_array[1]}
            );
            try std.testing.expect(tc_superset.is_superset_of(tc_subset));

            try tc_superset.append(1);
            try tc_subset.append(1);
        }
    }

    // negative case 
    {
        const tc_superset = try Treecode.init_word(
            std.testing.allocator,
            0b11001101
        );
        defer tc_superset.deinit();

        const tc_subset = try Treecode.init_word(
            std.testing.allocator,
            0b11001
        );
        defer tc_subset.deinit();

        try std.testing.expectEqual(
            tc_superset.is_superset_of(tc_subset),
            false
        );

    }

    // write very long negative test
    // stamp DEADBEEF into each word and ensure its not a subset
    // ...until the == condition
}

test "treecode: append" {
    {
        try std.testing.expectEqual(
            @as(treecode_word, 0b10),
            treecode_word_append(0b1, 0)
        );
        try std.testing.expectEqual(
            @as(treecode_word, 0b11),
            treecode_word_append(0b1, 1)
        );

        try std.testing.expectEqual(
            @as(treecode_word, 0b1101),
            treecode_word_append(@as(treecode_word, 0b101), 1)
        );
        try std.testing.expectEqual(
            @as(treecode_word, 0b1001),
            treecode_word_append(@as(treecode_word, 0b101), 0)
        );
    }

    {
        var tc = try Treecode.init_word(std.testing.allocator, 0b1);
        defer tc.deinit();

        var i:usize = 0;
        while (i < 130) : (i += 1) {
            try tc.append(0);
        }

        errdefer std.debug.print(
            "tc[1]: {b} tc[0]: {b}\n",
            .{ tc.treecode_array[1], tc.treecode_array[0] }
        );

        try std.testing.expectEqual(
            @as(treecode_word, 0b100),
            tc.treecode_array[1]
        );
        try std.testing.expectEqual(@as(treecode_word, 130), tc.code_length());

        try tc.append(0);

        try std.testing.expectEqual(
            @as(treecode_word, 0b1000),
            tc.treecode_array[1]
        );
        try std.testing.expectEqual(@as(treecode_word, 131), tc.code_length());
    }

    {
        var tc = try Treecode.init_word(std.testing.allocator, 0b1);
        defer tc.deinit();

        var i:usize = 0;
        while (i < 130) : (i += 1) {
            try tc.append(1);
        }

        errdefer std.debug.print(
            "tc[1]: {b} tc[0]: {b}\n",
            .{ tc.treecode_array[1], tc.treecode_array[0] }
        );

        try std.testing.expectEqual(
            @as(treecode_word, 0b111),
            tc.treecode_array[1]
        );
        try std.testing.expectEqual(@as(treecode_word, 130), tc.code_length());

        try tc.append(0);

        try std.testing.expectEqual(
            @as(treecode_word, 0b1011),
            tc.treecode_array[1]
        );
        try std.testing.expectEqual(@as(treecode_word, 131), tc.code_length());
    }

    {
        var tc = try Treecode.init_word(std.testing.allocator, 0b1);
        defer tc.deinit();

        var i:usize = 0;
        while (i < 258) : (i += 1) {
            try tc.append(1);
        }

        errdefer std.debug.print(
            "tc[2]: {b} \n",
            .{ tc.treecode_array[2] }
        );

        try std.testing.expectEqual(
            @as(treecode_word, 0b111),
            tc.treecode_array[2]
        );
        try std.testing.expectEqual(@as(treecode_word, 258), tc.code_length());

        try tc.append(0);

        try std.testing.expectEqual(
            @as(treecode_word, 0b1011),
            tc.treecode_array[2]
        );
        try std.testing.expectEqual(@as(treecode_word, 259), tc.code_length());
    }

    {
        var tc = try Treecode.init_word(std.testing.allocator, 0b1);
        defer tc.deinit();

        var i:usize = 0;
        while (i < 258) : (i += 1) {
            try tc.append(0);
        }

        errdefer std.debug.print(
            "tc[2]: {b} \n",
            .{ tc.treecode_array[2] }
        );

        try std.testing.expectEqual(
            @as(treecode_word, 0b100),
            tc.treecode_array[2]
        );
        try std.testing.expectEqual(@as(treecode_word, 258), tc.code_length());

        try tc.append(1);

        try std.testing.expectEqual(
            @as(treecode_word, 0b1100),
            tc.treecode_array[2]
        );
        try std.testing.expectEqual(@as(treecode_word, 259), tc.code_length());
    }

    {   
        var tc = try Treecode.init_word(std.testing.allocator, 0b1);
        defer tc.deinit();

        var buf_tc = std.ArrayList(u8).init(std.testing.allocator);
        defer buf_tc.deinit();

        var buf_known = std.ArrayList(u8).init(std.testing.allocator);
        defer buf_known.deinit();
        try buf_known.ensureTotalCapacity(1024);
        try buf_known.append(1);

        var i:usize = 0;
        while (i < 256)  : (i += 1) 
        {

            errdefer std.debug.print("iteration: {} \n", .{i});

            const next:u1 = if (@rem(i, 5) == 0) 0 else 1;

            try tc.append(next);
            try buf_known.insert(1, next);
        }

        errdefer std.debug.print(
            "iteration: {} \n  buf_tc:    {any}\n  buf_known: {any}\n",
            .{256, buf_tc.items, buf_known.items}
        );


        errdefer std.debug.print(
            "tc: {b} \n",
            .{ tc.treecode_array[1] }
        );

        buf_tc.clearAndFree();
        try tc.to_str(&buf_tc);

        try std.testing.expectEqual(buf_known.items.len - 1, tc.code_length());
        try std.testing.expectEqualStrings(buf_known.items, buf_tc.items);

        try std.testing.expectEqual(buf_known.items.len - 1, tc.code_length());
    }

    // Variable size flavor, adding a mix of 0s and 1s
    {
        var tc = try Treecode.init_word(std.testing.allocator, 0b1);
        defer tc.deinit();

        var buf_tc = std.ArrayList(u8).init(std.testing.allocator);
        defer buf_tc.deinit();

        var buf_known = std.ArrayList(u8).init(std.testing.allocator);
        defer buf_known.deinit();
        try buf_known.ensureTotalCapacity(1024);
        try buf_known.append(1);

        var i:usize = 0;
        while (i < 1000)  : (i += 1) 
        {
            try std.testing.expectEqual(
                buf_known.items.len - 1,
                tc.code_length()
            );
            buf_tc.clearAndFree();
            try tc.to_str(&buf_tc);

            errdefer std.debug.print("iteration: {} \n", .{i});

            errdefer std.debug.print(
                "iteration: {} \n  buf_tc:    {b}\n  buf_known: {b}\n",
                .{i, buf_tc.items, buf_known.items}
            );

            try std.testing.expectEqual(
                buf_known.items.len - 1,
                tc.code_length()
            );
            try std.testing.expectEqualStrings(buf_known.items, buf_tc.items);

            const next:u1 = if (@rem(i, 5) == 0) 0 else 1;
            try tc.append(next);
            try buf_known.insert(1, next);

            errdefer std.debug.print(
                "tc: {b} \n",
                .{ tc.treecode_array[0] }
            );

            try std.testing.expectEqual(
                buf_known.items.len - 1,
                tc.code_length()
            );
        }
    }
}


test "treecode: Treecode.eql" {
    // positive tests
    {
        var a  = try Treecode.init_word(std.testing.allocator, 1);
        defer a.deinit();

        var b  = try Treecode.init_word(std.testing.allocator, 1);
        defer b.deinit();

        var i:usize = 0;
        while (i < 1000)  : (i += 1) {
            errdefer std.debug.print(
                "iteration: {} a: {b} b: {b}\n",
                .{i, a.treecode_array[0], b.treecode_array[0]}
            );
            try std.testing.expect(a.eql(b));
            const next:u1 = if (@rem(i, 5) == 0) 0 else 1;
            try a.append(next);
            try b.append(next);
        }
    }

    // negative tests
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

    {
        var a  = try Treecode.init_word(std.testing.allocator, 1);
        defer a.deinit();

        var b  = try Treecode.init_word(std.testing.allocator, 10);
        defer b.deinit();

        var i:usize = 0;
        while (i < 1000)  : (i += 1) {
            errdefer std.debug.print(
                "iteration: {} a: {b} b: {b}\n",
                .{i, a.treecode_array[0], b.treecode_array[0]}
            );
            try std.testing.expect(a.eql(b) == false);
            const next:u1 = if (@rem(i, 5) == 0) 0 else 1;
            try a.append(next);
            try b.append(next);
        }
    }
}

fn treecode_word_append(a: treecode_word, l_or_r_branch: u1) treecode_word {
    const signficant_bits:u8 = WORD_BIT_COUNT - 1 - @clz(a);

    // strip leading bit
    const leading_bit = (
        @as(treecode_word, 1) << @intCast(u7, @as(u8, signficant_bits))
    );

    const a_without_leading_bit = (a - leading_bit) ;
    const leading_bit_shifted = (leading_bit << 1);

    const l_or_r_branch_shifted = (
        @intCast(treecode_word, l_or_r_branch) 
        << @intCast(u7, (@as(u8, signficant_bits)))
    );

    const result = (
       a_without_leading_bit 
       | leading_bit_shifted
       | l_or_r_branch_shifted
    );

    // std.debug.print(
    //     "input tc: {b}, " ++
    //     "input l_or_r_branch: u8: {b}, " ++
    //     "signficant_bits: {}, " ++
    //     "a_without_leading_bit: {b}," ++
    //     " leading_bit_shifted: {b}," ++
    //     " l_or_r_branch_shifted: {b}, " ++
    //     " result: {b}, " ++
    //     "\n",
    //     .{
    //         a,
    //         l_or_r_branch,
    //         signficant_bits,
    //         a_without_leading_bit,
    //         leading_bit_shifted,
    //         l_or_r_branch_shifted,
    //         result,
    //     }
    // );

    return result;
}

test "treecode: hash" {
    {
        var tc1 = try Treecode.init_word(std.testing.allocator, 0b101);
        defer tc1.deinit();

        var tc2 = try Treecode.init_word(std.testing.allocator, 0b101);
        defer tc2.deinit();

        try std.testing.expectEqual(tc1.hash(), tc2.hash());

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

    {
        var tc1 = try Treecode.init_fill_count(std.testing.allocator, 2, 0b1);
        defer tc1.deinit();

        var tc2 = try Treecode.init_fill_count(std.testing.allocator, 2, 0b1);
        defer tc2.deinit();

        errdefer std.debug.print("\ntc1: {b}\ntc2: {b}\n\n",
            .{ tc1.treecode_array[1], tc2.treecode_array[1] }
        );

        try std.testing.expectEqual(tc1.hash(), tc2.hash());
    }

    {
        var tc1 = try Treecode.init_word(std.testing.allocator, 0b1);
        defer tc1.deinit();

        var tc2 = try Treecode.init_word(std.testing.allocator, 0b1);
        defer tc2.deinit();

        try tc1.realloc(1024);
        var i:usize = 0;
        while (i < 128) : (i+=1) {
            try tc1.append(0);
        }

        errdefer std.debug.print("\ntc1: {b}{b}\ntc2: {b}\n\n",
            .{ tc1.treecode_array[1], tc1.treecode_array[0], tc2.treecode_array[0] }
        );

        try std.testing.expect(tc1.eql(tc2) == false);
        try std.testing.expect(tc1.hash() != tc2.hash());

        i = 0;
        while (i < 128) : (i+=1) {
            try tc2.append(0);
        }

        try std.testing.expectEqual(tc1.hash(), tc2.hash());

        i = 0;
        while (i < 122) : (i+=1) {
            try tc2.append(0);
        }

        try std.testing.expect(tc1.hash() != tc2.hash());

        i = 0;
        while (i < 122) : (i+=1) {
            try tc1.append(0);
        }

        try std.testing.expect(tc1.hash() == tc2.hash());
    }
}

test "treecode: init_fill_count" {
    {
        const tc = try Treecode.init_fill_count(std.testing.allocator, 2, 0b1);
        defer tc.deinit();

        try std.testing.expectEqual(
            @as(treecode_word, 0b0),
            tc.treecode_array[0]
        );
        try std.testing.expectEqual(
            @as(treecode_word, 0b1),
            tc.treecode_array[1]
        );

        // NOT
        // try std.testing.expectEqual(@as(treecode_word, 0b11), tc.treecode_array[1]);
    }
}

test "treecode: next_step_towards" {
    // single word size
    {
        const TestData = struct{
            source: treecode_word,
            dest: treecode_word,
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

        for (test_data) |t, i| {
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

    // codes longer than a single word
    {
        var tc_src = try Treecode.init_word(std.testing.allocator, 0b1);
        defer tc_src.deinit();
        var tc_dst = try Treecode.init_word(std.testing.allocator, 0b1);
        defer tc_dst.deinit();

        // straddle the word boundary
        var i:usize = 0;
        while (i < WORD_BIT_COUNT - 1) : (i += 1) {
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
        while (i < 1000) : (i += 1) {
            try tc_src.append(0);
            try tc_dst.append(0);
        }

        try tc_dst.append(1);

        try std.testing.expectEqual(
            @as(u1, 0b1),
            try tc_src.next_step_towards(tc_dst)
        );
    }
}

test "treecode: clone" {
    {
        const tc_src = try Treecode.init_word(std.testing.allocator, 0b1);
        defer tc_src.deinit();
        const tc_cln = try tc_src.clone();
        defer tc_cln.deinit();

        try std.testing.expect(tc_src.eql(tc_cln));
    }

    {
        var tc_src = try Treecode.init_word(std.testing.allocator, 0b1);
        defer tc_src.deinit();
        var tc_cln = try tc_src.clone();
        defer tc_cln.deinit();

        try std.testing.expect(tc_src.eql(tc_cln));

        try tc_src.append(1);

        try std.testing.expect(tc_src.eql(tc_cln) == false);
    }
}
