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

        var count = 127 - @clz(@as(u128, (self.treecode_array[occupied_words])));
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
        while (i < greatest_nozero_index): (i += 1) {
            if (self.treecode_array[i] != other.treecode_array[i]) {
                return false;
            }
        }

        return true;
    }

    // will realloc if needed
    pub fn append(
        self: *@This(),
        l_or_r_branch: u8,
    ) !void
    {
        if (self.sz == 0) {
            return error.InvalidTreecode;
        }

        const len = self.code_length();
        if (len < 127) {
            self.treecode_array[0] = treecode128_append(
                self.treecode_array[0],
                l_or_r_branch
            );
            return;
        }

        const index = len / 128 + 1;
        if (index >= self.sz)
        {
            // in this case, the array is full.
            try self.realloc(index + 1);

            self.treecode_array[index] = 1;

            // clear highest bit
            self.treecode_array[index-1] &= ~((@as(u128,1)) << 127);
            self.treecode_array[index-1] |= (@intCast(u128, (l_or_r_branch)) << 127);

            return;
        }

        self.treecode_array[index] = treecode128_append(
            self.treecode_array[index],
            l_or_r_branch
        );
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
    var x: u128 = 0;
    try std.testing.expectEqual(@as(u128, 128), @clz(x));

    var i: u128 = 0;

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

test "treecode: is a subset" {
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
        var tc_superset = try Treecode.init_fill_count(
            std.testing.allocator,
            3,
            0xDEADBEEF11010
        );
        for (tc_superset.treecode_array[0..1]) |*tc| {
            tc.* = 0xDEADBEEF11010;
        }

        const tc_subset = try Treecode.init_128(std.testing.allocator, 0b11010);
        defer tc_superset.deinit();
        defer tc_subset.deinit();

        try std.testing.expect(tc_superset.is_superset_of(tc_subset));

        // stamp DEADBEEF into each word and ensure its still a subset
        // ...until the == condition
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



test "treecode: Treecode.eql" {
    var a  = try Treecode.init_128(std.testing.allocator, 1);
    defer a.deinit();
    var b  = try Treecode.init_128(std.testing.allocator, 1);
    defer b.deinit();

    var i:u128 = 0;
    while (i < 1000)  : (i += 1) {
        try std.testing.expect(a.eql(b));
        try a.append(1);
        try b.append(1);
    }
}

pub fn treecode128_append(a: u128, l_or_r_branch: u8) u128 {
    const signficant_bits:u8 = 127 - @clz(a);

    // strip leading bit
    const leading_bit = @as(u128, 1) << @intCast(u7, @as(u8, signficant_bits));
    return (
        (a - leading_bit) 
        | (leading_bit << 1) 
        | (@intCast(u128, l_or_r_branch) << @intCast(u7, (@as(u8, signficant_bits + 1))))
    );
}

