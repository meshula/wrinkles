const std = @import("std");

const treecode_128 = u128;

pub const Treecode = struct {
    sz: usize,
    treecode_array: []treecode_128,
    allocator: std.mem.Allocator,

    pub fn init_fill_count(
        allocator: std.mem.Allocator,
        count: usize,
        input: treecode_128,
    ) !Treecode {
        if (count == 0) {
            return error.InvalidCount;
        }

        var treecode_array:[]treecode_128 = try allocator.alloc(
            treecode_128,
            count
        );

        var i:usize = count - 1;
        treecode_array[i] = input;

        while (i <= 0) : (i -= 1) {
            treecode_array[i] = 0;
        }

        return .{
            .allocator = allocator,
            .sz = count,
            .treecode_array = treecode_array 
        };
    }

    pub fn init_128(
        allocator: std.mem.Allocator,
        input: treecode_128,
    ) !Treecode {
        var treecode_array:[]treecode_128 = try allocator.alloc(treecode_128, 1);
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

        std.mem.set(treecode_128, self.treecode_array[self.sz..], 0);

        self.sz = new_size;
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

        var count = 127 - @clz(@as(treecode_128, (self.treecode_array[occupied_words])));
        if (occupied_words == 0) {
            return count;
        }
        return count + (occupied_words) * 128;
    }

    pub fn eql(self: @This(), other: Treecode) bool {
        var len_self: usize = self.code_length();
        var len_other: usize = other.code_length();

        if (len_self != len_other) {
            return false;
        }

        var greatest_nozero_index: usize = len_self / 128;
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

        if (len < (@bitSizeOf(treecode_128) - 1)) {
            self.treecode_array[0] = treecode128_append(
                self.treecode_array[0],
                l_or_r_branch
            );
            return;
        }

        var space_available = self.sz * @bitSizeOf(treecode_128) - 1;
        const next_index = len + 1;

        if (next_index >= space_available) {
            // double the size
            try self.realloc(self.sz*2);
            space_available = self.sz * @bitSizeOf(treecode_128) - 1;
        }

        const new_marker_location_abs = len + 1;
        const new_marker_slot = new_marker_location_abs / @bitSizeOf(treecode_128);
        const new_marker_location_in_slot = @rem(new_marker_location_abs, @bitSizeOf(treecode_128));

        self.treecode_array[new_marker_slot] |= (std.math.shl(treecode_128, 1, new_marker_location_in_slot));

        const new_data_location_abs = len; 
        const new_data_slot = new_data_location_abs / @bitSizeOf(treecode_128);
        const new_data_location_in_slot = @rem(new_data_location_abs, @bitSizeOf(treecode_128));

        self.treecode_array[new_data_slot] |= (std.math.shl(treecode_128, l_or_r_branch, new_data_location_in_slot));

        return;
    }

    fn is_superset_of(self: @This(), rhs: Treecode) bool {
        var len_self: usize = self.code_length();
        var len_rhs: usize = rhs.code_length();

        if (len_self == 0 or len_rhs == 0 or len_rhs > len_self) {
            return false;
        }

        if (len_self <= 128) {
            return treecode128_b_is_a_subset(
                self.treecode_array[0],
                rhs.treecode_array[0]
            );
        }
        var greatest_nonzero_rhs_index: usize = len_rhs / 128;
        var i:usize = 0;
        while (i < greatest_nonzero_rhs_index) : (i += 1) {
            if (self.treecode_array[i] != rhs.treecode_array[i]) return false;
        }
        var mask: treecode_128 = treecode128_mask(128 - ((len_rhs - 1) % 128));
        return (
            self.treecode_array[greatest_nonzero_rhs_index] & mask) 
            == (rhs.treecode_array[greatest_nonzero_rhs_index] & mask
        );
    }

    pub fn to_str(self: @This(), buf:*std.ArrayList(u8)) !void {
        for (self.treecode_array) |tc| {
            var tc_current = tc;
            while (tc_current > 0) : (tc_current >>= 1) {
                try buf.insert(0, @intCast(u8, tc_current & @as(treecode_128, 1)));
            }
        }
    }
};

test "treecode: code_length" {
    {
        var tc  = try Treecode.init_128(std.testing.allocator, 1);
        defer tc.deinit();

        try std.testing.expectEqual(@as(usize, 0), tc.code_length());
    }

    {
        var tc  = try Treecode.init_128(std.testing.allocator, 0b11);
        defer tc.deinit();

        try std.testing.expectEqual(@as(usize, 1), tc.code_length());
    }

    {
        var tc  = try Treecode.init_128(std.testing.allocator, 0b1111111);
        defer tc.deinit();

        try std.testing.expectEqual(@as(usize, 6), tc.code_length());
    }

    {
        // top word is 1, lower word is 0, therefore codelength is 128
        var tc  = try Treecode.init_fill_count(std.testing.allocator, 2, 0b1);
        defer tc.deinit();

        try std.testing.expectEqual(@as(usize, 128), tc.code_length());
    }

    {
        var tc  = try Treecode.init_fill_count(std.testing.allocator, 8, 0b1);
        defer tc.deinit();

        try std.testing.expectEqual(@as(usize, 7*128), tc.code_length());
    }

    {
        var tc  = try Treecode.init_fill_count(std.testing.allocator, 8, 0b11);
        defer tc.deinit();

        try std.testing.expectEqual(@as(usize, 7*128 + 1), tc.code_length());
    }
}

test "treecode: @clz" {
    var x: treecode_128 = 0;
    try std.testing.expectEqual(@as(treecode_128, 128), @clz(x));

    var i: treecode_128 = 0;

    while (i < 128) : (i += 1) {
        try std.testing.expectEqual(i, 128 - @clz(x));
        x = (x << 1) | 1;
    }
}

fn treecode128_mask(leading_zeros: usize) treecode_128 {
    return (
        @intCast(treecode_128, 1) << @intCast(u7, (128 - leading_zeros))
    ) - 1;
}

fn treecode128_b_is_a_subset(a: treecode_128, b: treecode_128) bool {
    if (a == b) {
        return true;
    }
    if (a == 0 or b == 0) {
        return false;
    }
    var leading_zeros: usize = @clz(b) - 1;
    var mask: treecode_128 = treecode128_mask(leading_zeros);
    return (a & mask) == (b & mask);
}

test "to_string" {
    var tc = try Treecode.init_128(std.testing.allocator, 0b1);
    defer tc.deinit();

    var known = std.ArrayList(u8).init(std.testing.allocator);
    defer known.deinit();
    try known.append(1);


    var buf = std.ArrayList(u8).init(std.testing.allocator);
    defer buf.deinit();
    try tc.to_str(&buf);

    try std.testing.expectEqualStrings(known.items, buf.items);
    std.debug.print("known: {b} buf: {b} \n", .{ known.items, buf.items } );

    try tc.append(0);
    try known.append(1);

    buf.clearAndFree();
    try tc.to_str(&buf);

    std.debug.print("known: {b} buf: {b} \n", .{ known.items, buf.items } );
    try std.testing.expectEqualStrings(known.items, buf.items);

    var i : usize= 0;
    while (i < 10) : (i += 1) {
        // const next:u1 = if (i & 5 != 0) 0 else 1;
        const next:u1 = 1;

        try known.append(next);

        try tc.append(next);
        buf.clearAndFree();
        try tc.to_str(&buf);

        std.debug.print("iteration: {} known: {b} buf: {b} \n", .{ i, known.items, buf.items } );

        try std.testing.expectEqualStrings(known.items, buf.items);
    }
}


test "treecode_128: is a subset" {
        // positive case, ending in 1
        {
            const tc_128_superset:treecode_128 = 0b11001101;
            const tc_128_subset:treecode_128 = 0b1101;

            try std.testing.expect(
                treecode128_b_is_a_subset(tc_128_superset, tc_128_subset)
            );
        }

        // positive case, ending in 0
        {
            const tc_128_superset:treecode_128 = 0b110011010;
            const tc_128_subset:treecode_128 = 0b11010;

            try std.testing.expect(
                treecode128_b_is_a_subset(tc_128_superset, tc_128_subset)
            );
        }

        // negative case 
        {
            const tc_128_superset:treecode_128 = 0b11001101;
            const tc_128_subset:treecode_128 = 0b11001;

            try std.testing.expectEqual(
                treecode128_b_is_a_subset(tc_128_superset, tc_128_subset),
                false
            );
        }
}

test "treecode: is a superset" {
    // positive case, ending in 1
    {
        const tc_superset = try Treecode.init_128(std.testing.allocator, 0b11001101);
        const tc_subset = try Treecode.init_128(std.testing.allocator, 0b1101);
        defer tc_superset.deinit();
        defer tc_subset.deinit();

        try std.testing.expect(tc_superset.is_superset_of(tc_subset));
    }

    // positive case, ending in 0
    {
        const tc_superset = try Treecode.init_128(std.testing.allocator, 0b110011010);
        const tc_subset = try Treecode.init_128(std.testing.allocator, 0b11010);
        defer tc_superset.deinit();
        defer tc_subset.deinit();

        try std.testing.expect(tc_superset.is_superset_of(tc_subset));
    }

    // positive case, very long
    {  
        var tc_superset  = try Treecode.init_128(
            std.testing.allocator,
            0x11011010101
        );
        var tc_subset  = try Treecode.init_128(std.testing.allocator, 0b101);
        defer tc_superset.deinit();
        defer tc_subset.deinit();

        var i:treecode_128 = 0;
        while (i < 1000)  : (i += 1) {
            errdefer std.debug.print("iteration: {}\n", .{i});
            try std.testing.expect(tc_superset.is_superset_of(tc_subset));
            try tc_superset.append(1);
            try tc_subset.append(1);
        }
    }

    // negative case 
    {
        const tc_superset = try Treecode.init_128(std.testing.allocator, 0b11001101);
        const tc_subset = try Treecode.init_128(std.testing.allocator, 0b11001);
        defer tc_superset.deinit();
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
            @as(treecode_128, 0b10),
            treecode128_append(0b1, 0)
        );
        try std.testing.expectEqual(
            @as(treecode_128, 0b11),
            treecode128_append(0b1, 1)
        );

        try std.testing.expectEqual(
            @as(treecode_128, 0b1101),
            treecode128_append(@as(treecode_128, 0b101), 1)
        );
        try std.testing.expectEqual(
            @as(treecode_128, 0b1001),
            treecode128_append(@as(treecode_128, 0b101), 0)
        );
    }

    {
        var tc = try Treecode.init_128(std.testing.allocator, 0b1);
        defer tc.deinit();

        var i:usize = 0;
        while (i < 130) : (i += 1) {
            try tc.append(1);
        }

        errdefer std.debug.print(
            "tc[1]: {b} tc[0]: {b}\n",
            .{ tc.treecode_array[1], tc.treecode_array[0] }
        );

        try std.testing.expectEqual(@as(treecode_128, 0b111), tc.treecode_array[1]);
        try std.testing.expectEqual(@as(treecode_128, 130), tc.code_length());
    }

    // Variable size flavor
    {
        var tc = try Treecode.init_128(std.testing.allocator, 0b1);
        defer tc.deinit();

        var buf_tc = std.ArrayList(u8).init(std.testing.allocator);
        defer buf_tc.deinit();

        var buf_known = std.ArrayList(u8).init(std.testing.allocator);
        defer buf_known.deinit();
        try buf_known.append(1);

        var i:usize = 0;
        while (i < 1000)  : (i += 1) {

            buf_tc.clearAndFree();
            try tc.to_str(&buf_tc);

            errdefer std.debug.print(
                "iteration: {} \n  buf_tc: {b}\n  buf_known: {b}\n",
                .{i, buf_tc.items, buf_known.items}
            );

            try std.testing.expectEqualSlices(u8, buf_known.items, buf_tc.items);
            const next:u1 = if (@rem(i, 5) == 0) 0 else 1;
            try tc.append(next);
            try buf_known.insert(1, next);
        }
    }
}


test "treecode: Treecode.eql" {
    // positive tests
    {
        var a  = try Treecode.init_128(std.testing.allocator, 1);
        defer a.deinit();

        var b  = try Treecode.init_128(std.testing.allocator, 1);
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
        const tc_fst = try Treecode.init_128(std.testing.allocator, 0b1101);
        defer tc_fst.deinit();
        const tc_snd = try Treecode.init_128(std.testing.allocator, 0b1011);
        defer tc_snd.deinit();

        try std.testing.expect(tc_fst.eql(tc_snd) == false);
        try std.testing.expect(tc_snd.eql(tc_fst) == false);
    }

    {
        const tc_fst = try Treecode.init_128(std.testing.allocator, 0b1101);
        defer tc_fst.deinit();
        const tc_snd = try Treecode.init_128(std.testing.allocator, 0b1010);
        defer tc_snd.deinit();

        try std.testing.expect(tc_fst.eql(tc_snd) == false);
        try std.testing.expect(tc_snd.eql(tc_fst) == false);
    }

    {
        var a  = try Treecode.init_128(std.testing.allocator, 1);
        defer a.deinit();

        var b  = try Treecode.init_128(std.testing.allocator, 10);
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

fn treecode128_append(a: treecode_128, l_or_r_branch: u8) treecode_128 {
    const signficant_bits:u8 = 127 - @clz(a);

    // strip leading bit
    const leading_bit = @as(treecode_128, 1) << @intCast(u7, @as(u8, signficant_bits));

    const a_without_leading_bit = (a - leading_bit) ;
    const leading_bit_shifted = (leading_bit << 1);
    const l_or_r_branch_shifted = (@intCast(treecode_128, l_or_r_branch) << @intCast(u7, (@as(u8, signficant_bits))));

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

