const std = @import("std");

const Allocator = std.mem.Allocator;

const treecode_128 = u128;

pub const Treecode = struct {
    sz: usize,
    treecode_array: []treecode_128,
    allocator: Allocator,

    pub fn init_fill_count(
        allocator: Allocator,
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

        treecode_array[count - 1] = input;

        var i:usize = 0;
        while (i < count - 1) : (i += 1) {
            treecode_array[i] = 0;
        }

        return .{
            .allocator = allocator,
            .sz = 1,
            .treecode_array = treecode_array 
        };
    }

    pub fn init_128(
        allocator: Allocator,
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
        if (self.sz == 1) {
            return @as(usize, 128) - @clz(@as(u128,self.treecode_array[0])) - 1;
        }
        var count: usize = 0;
        var i = self.sz;
        while (i < 1) {
            if (self.treecode_array[i] != 0) {
                count = 127 - @clz(@as(u128,(self.treecode_array[i])));
                return count + i * 128;
            }
        }
        return 127 - @clz(@as(u128, self.treecode_array[0]));
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
        var tc  = try Treecode.init_fill_count(std.testing.allocator, 2, 0b1);
        defer tc.deinit();

        try std.testing.expectEqual(@as(usize, 256), tc.code_length());
    }

    {
        var tc  = try Treecode.init_fill_count(std.testing.allocator, 8, 0b1);
        defer tc.deinit();

        try std.testing.expectEqual(@as(usize, 8*128), tc.code_length());
    }

    {
        var tc  = try Treecode.init_fill_count(std.testing.allocator, 8, 0b11);
        defer tc.deinit();

        try std.testing.expectEqual(@as(usize, 8*128 + 1), tc.code_length());
    }
}


fn nlz(tc: *Treecode) usize {
    if (tc == null or tc.treecode_array == null or tc.sz == 0) return 0;

    if (tc.sz == 1) return @clz(tc.treecode_array[0]);

    var n: usize = 0;
    var i = tc.sz;
    while (i > 0) : (i -= 1) {
        if (tc.treecode_array[i] == 0) {
            n += 128;
        } else {
            n += @clz(tc.treecode_array[i]);
            break;
        }
    }

    return n;
}

test "treecode: @clz" {
    var x: u128 = 0;
    try std.testing.expectEqual(@as(u128, 128), @clz(x));

    var i: u128 = 0;

    while (i < 128) : (i += 1) {
        try std.testing.expectEqual(i, @clz(x));
        x = (x << 1) | 1;
    }
}

fn treecode128_mask(leading_zeros: usize) treecode_128 {
    return (@bitCast(treecode_128, 1) << (128 - leading_zeros)) - 1;
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

fn treecode_b_is_a_subset(a: *Treecode, b: *Treecode) bool {
    if (a == null or b == null) return false;
    if (a == b) return true;
    var len_a: usize = a.code_length();
    var len_b: usize = b.code_length();
    if (len_a == 0 or len_b == 0 or len_b > len_a) return false;
    if (len_a <= 128) {
        return treecode128_b_is_a_subset(a.treecode_array[0], b.treecode_array[0]);
    }
    var greatest_nozero_b_index: usize = len_b / 128;
    var i = 0;
    while (i < greatest_nozero_b_index) : (i += 1) {
        if (a.treecode_array[i] != b.treecode_array[i]) return false;
    }
    var mask: treecode_128 = treecode128_mask(128 - ((len_b - 1) % 128));
    return (a.treecode_array[greatest_nozero_b_index] & mask) == (b.treecode_array[greatest_nozero_b_index] & mask);
}

fn treecode_is_equal(maybe_a: ?Treecode, maybe_b: ?Treecode) bool {
    if (maybe_a == null or maybe_b == null) {
        return false;
    }

    const a = maybe_a.?;
    const b = maybe_b.?;

    var len_a: usize = a.code_length();
    var len_b: usize = b.code_length();
    if (len_a != len_b) {
        return false;
    }

    var greatest_nozero_index: usize = len_a / 128;
    var i:usize = 0;
    while (i < greatest_nozero_index): (i += 1) {
        if (a.treecode_array[i] != b.treecode_array[i]) {
            return false;
        }
    }

    return true;
}

test "treecode: treecode_is_equal" {
    var a  = try Treecode.init_128(std.testing.allocator, 1);
    defer a.deinit();
    var b  = try Treecode.init_128(std.testing.allocator, 1);
    defer b.deinit();

    var i:u128 = 0;
    while (i < 1000)  : (i += 1) {
        try std.testing.expect(treecode_is_equal(a, b));
        try treecode_append(&a, 1);
        try treecode_append(&b, 1);
    }
}

pub fn treecode128_append(a: u128, l_or_r_branch: u8) u128 {
    const leading_zeros:u8 = @clz(a);
    // strip leading bit
    const leading_bit = @as(u128, 1) << @intCast(u7, (@as(u8, 128) - leading_zeros));
    return (
        (a - leading_bit) 
        | (leading_bit << 1) 
        | (@intCast(u128, l_or_r_branch) << @intCast(u7, (@as(u8, 128) - leading_zeros - 1)))
    );
}

pub fn treecode_append(
    a: *Treecode,
    l_or_r_branch: u8,
) !void
{
    if (a.sz == 0) {
        return error.InvalidTreecode;
    }

    const len = a.code_length();
    if (len < 128) {
        a.treecode_array[0] = treecode128_append(
            a.treecode_array[0],
            l_or_r_branch
        );
        return;
    }

    const index = len / 128;

    if (index >= a.sz) 
    {
        // in this case, the array is full.
        try a.realloc(index + 1);

        a.treecode_array[index] = 1;

        // clear highest bit
        a.treecode_array[index-1] &= ~((@as(u128,1)) << 127);
        a.treecode_array[index-1] |= (@intCast(u128, (l_or_r_branch)) << 127);

        return;
    }

    a.treecode_array[index] = treecode128_append(a.treecode_array[index], l_or_r_branch);
}
