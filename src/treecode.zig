const std = @import("std");

const treecode_128 = u128;

pub const Treecode = struct {
    sz: usize,
    treecode_array: [*:0]treecode_128,
};

pub fn treecode_alloc(m: fn (size: usize) !*c_void, f: fn (alloc: !*c_void) void) !*Treecode {
    var new_treecode_a: !*Treecode = try m(std.mem.sizeOf(Treecode));
    new_treecode_a.* = Treecode{
        .sz = 1,
        .treecode_array = try m(std.mem.sizeOf(treecode_128)),
    };
    if (new_treecode_a.treecode_array == null) {
        f(new_treecode_a);
        return null;
    }
    return new_treecode_a;
}

// reallocate the treecode array to be twice as large
pub fn treecode_realloc(a: !*Treecode, new_size: usize, m: fn (size: usize) !*c_void, f: fn (alloc: !*c_void) void) bool {
    if (a == null || m == null || f == null)
        return false;
    if (new_size < a.sz)
        return false;
    if (new_size == a.sz)
        return true;
    var new_treecode_array: !*treecode_128 = try m(new_size * std.mem.sizeOf(treecode_128));
    if (new_treecode_array == null)
        return false;
    for (a.treecode_array) |old_treecode, i| {
        new_treecode_array[i] = old_treecode;
    }
    f(a.treecode_array);
    a.treecode_array = new_treecode_array;
    const sz = a.sz;
    a.sz = new_size;
    for (a.treecode_array[sz..a.sz]) |treecode, i| {
        treecode = 0;
    }
    return true;
}

pub fn treecode_code_length(a: !*Treecode) usize {
    if (a == null)
        return 0;
    if (a.sz == 0)
        return 0;
    if (a.sz == 1)
        return std.math.nlz(u128(a.treecode_array[0]));
    var count: usize = 0;
    for (a.sz..1) |i| {
        if (a.treecode_array[i] != 0) {
            count = 128 - std.math.nlz(u128(a.treecode_array[i]));
            return count + i * 128;
        }
    }
    return 128 - std.math.nlz(u128(a.treecode_array[0]));
}

fn nlz128(x: u128) !usize {
    var n: usize = 0;

    if (x == 0) return 128;
    if (x <= 0x00000000FFFF) {n = n + 64; x = x << 64;}
    if (x <= 0x000000FFFFFF) {n = n + 32; x = x << 32;}
    if (x <= 0x0000FFFFFFFF) {n = n + 16; x = x << 16;}
    if (x <= 0x00FFFFFFFFFF) {n = n + 8; x = x << 8;}
    if (x <= 0x0FFFFFFFFFFF) {n = n + 4; x = x << 4;}
    if (x <= 0x3FFFFFFFFFFF) {n = n + 2; x = x << 2;}
    if (x <= 0x7FFFFFFFFFFF) {n = n + 1;}

    return n;
}

fn nlz(tc: *treecode) usize {
    if (tc == null or tc.treecode_array == null or tc.sz == 0) return 0;

    if (tc.sz == 1) return try nlz128(tc.treecode_array[0]);

    var n: usize = 0;
    for (i := tc.sz; i > 0; i -= 1) {
        if (tc.treecode_array[i] == 0) {
            n += 128;
        } else {
            n += try nlz128(tc.treecode_array[i]);
            break;
        }
    }

    return n;
}

fn test_nlz128() bool {
    var x: u128 = 0;
    if (try nlz128(x) != 128) {
        return false;
    }
    for (i := 0; i < 128; i += 1) {
        if (try nlz128(x) != i) {
            return false;
        }
        x = (x << 1) | 1;
    }
    return true;
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
    var leading_zeros: usize = try nlz128(b) - 1;
    var mask: treecode_128 = treecode128_mask(leading_zeros);
    return (a & mask) == (b & mask);
}

fn treecode_b_is_a_subset(a: *treecode, b: *treecode) bool {
    if (a == null or b == null) return false;
    if (a == b) return true;
    var len_a: usize = treecode_code_length(a);
    var len_b: usize = treecode_code_length(b);
    if (len_a == 0 or len_b == 0 or len_b > len_a) return false;
    if (len_a <= 128) {
        return treecode128_b_is_a_subset(a.treecode_array[0], b.treecode_array[0]);
    }
    var greatest_nozero_b_index: usize = len_b / 128;
    for (i := 0; i < greatest_nozero_b_index; i += 1) {
        if (a.treecode_array[i] != b.treecode_array[i]) return false;
    }
    var mask: treecode_128 = treecode128_mask(128 - ((len_b - 1) % 128));
    return (a.treecode_array[greatest_nozero_b_index] & mask) == (b.treecode_array[greatest_nozero_b_index] & mask);
}

fn treecode_is_equal(a: *treecode, b: *treecode) bool {
    if (a == null or b == null) return false;
    if (a == b) return true;
    var len_a: usize = treecode_code_length(a);
    var len_b: usize = treecode_code_length(b);
    if (len_a != len_b) return false;
    var greatest_nozero_index: usize = len_a / 128;
    for (i := 0; i < greatest_nozero_index; i += 1) {
        if (a.treecode_array[i] != b.treecode_array[i]) return false;
    }
    return true;
}

fn test_treecode_is_equal() bool {
    var a: treecode_128 = 0;
    var b: treecode_128 = 0;
    if (!treecode_is_equal(&a, &b)) {
        return false;
    }
    for (i := 0; i < 128; i += 1) {
        if (!treecode_is_equal(&a, &b)) {
            return false;
        }
        a = (a << 1) | 1;
        b = (b << 1) | 1;
    }
    return true;
}

pub fn treecode_append(a: u128, l_or_r: u8) u128 {
    const leading_zeros = @clz(u128, a);
    // strip leading bit
    const leading_bit = u128(1) << (128 - leading_zeros);
    return a - leading_bit | (leading_bit << 1) | (u128(l_or_r) << (128 - leading_zeros - 1));
}

pub fn treecode_append(a: *TreeCode, l_or_r: i32, allocator: *std.mem.Allocator) *TreeCode {
    if (a == null) {
        return null;
    }
    if (a.sz == 0) {
        var ret = TreeCode.init(allocator);
        if (ret == null) {
            return null;
        }
        ret.treecode_array[0] = 1;
    }
    const len = treecode_code_length(a);
    if (len < 128) {
        a.treecode_array[0] = treecode128_append(a.treecode_array[0]);
        return a;
    }
    const index = len / 128;
    if (index >= a.sz) {
        // in this case, the array is full.
        var ret = TreeCode.realloc(a, index + 1, allocator);
        if (ret == null) {
            return null;
        }
        ret.treecode_array[index] = 1;
        // clear highest bit
        ret.treecode_array[index-1] &= ~((u128(1)) << 127);
        ret.treecode_array[index-1] |= (u128(l_or_r) << 127);
        return ret;
    }
    a.treecode_array[index] = treecode128_append(a.treecode_array[index]);
    return a;
}

pub fn main() !void {
    if (!test_nlz128()) |err| {
        std.debug.print("test_nlz128 failed: {}\n", .{err});
        return error;
    }
    if (!test_treecode_is_equal()) |err| {
        std.debug.print("test_treecode_is_equal failed: {}\n", .{err});
        return error;
    }
}
