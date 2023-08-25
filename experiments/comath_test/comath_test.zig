const std = @import("std");
const comath = @import("comath");

test "basic comath test" {
    const ctx = comath.contexts.simpleCtx({});
    const value = comath.eval(
        "a * 2",
        ctx,
        .{ .a = 4 }
    ) catch |err| switch (err) {};

    try std.testing.expect(value == 8);
}

const Dual_f32 = struct {
    /// real component
    r: f32 = 0,
    /// infinitesimal component
    i: f32 = 0,

    pub fn from(r: f32) Dual_f32 {
        return .{ .r = r };
    }

    pub inline fn add(self: @This(), rhs: @This()) @This() {
        return .{ 
            .r = self.r + rhs.r,
            .i = self.i + rhs.i,
        };
    }

    pub inline fn mul(self: @This(), rhs: @This()) @This() {
        return .{ 
            .r = self.r * rhs.r,
            .i = self.r * rhs.i + self.i*rhs.r,
        };
    }
};

test "comath really simple example" {
    // really simple example
    {
        const ctx = comath.contexts.simpleCtx({});
        const value = comath.eval(
            "(x+2)*(x+1)",
            ctx,
            .{ .x = 3 }
        ) catch |err| switch (err) {};

        try std.testing.expect(value == 20);
    }
}

test "comath dual test" {

    // function we want derivatives of
    const fn_str = "(x + off1) * (x + off2)";

    // build the context
    const ctx = comath.contexts.fnMethodCtx(
        comath.contexts.simpleCtx({}),
        .{
            .@"+" = "add",
            .@"*" = "mul",
        }
    );

    // evaluate as floats
    {
        const value = comath.eval(
            fn_str,
            ctx,
            .{.x = 3, .off1 = 2, .off2 = 1}
        ) catch |err| switch (err) {};

        try std.testing.expect(value == 20);
    }

    // evaluate as duals
    {
        const value_dual = comath.eval(
            fn_str,
            ctx,
            .{
                .x = Dual_f32{.r = 3, .i = 1},
                .off1 = Dual_f32{.r = 2},
                .off2 = Dual_f32{.r = 1},
            }
        ) catch |err| switch (err) {};

        // the value of f at x = 3
        try std.testing.expectEqual(@as(f32, 20), value_dual.r);
        // the derivative of f at x = 3
        try std.testing.expectEqual(@as(f32, 9), value_dual.i);
    }
}
