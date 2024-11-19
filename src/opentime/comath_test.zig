const std = @import("std");
const comath = @import("comath");

const F = struct{
    val: f32,

    pub fn lt(
        self: @This(),
        rhs: f32,
    ) bool {
        return self.val < rhs;
    }

    pub fn add(
        self: @This(),
        rhs: f32,
    ) F {
        return .{ .val = self.val + rhs };
    }
};
pub const CTX = comath.ctx.fnMethod(
    comath.ctx.simple({}),
    .{
        .@"+" = "add",
        .@"<" = "lt",
    },
);
pub fn eval(
    comptime expr: []const u8, 
    inputs: anytype,
) comath.Eval(expr, @TypeOf(CTX), @TypeOf(inputs))
{
    return comath.eval(expr, CTX, inputs) catch @compileError(
        "couldn't comath: " ++ expr ++ "."
    );
}

test "comath test"
{
    const f = F{ .val = 12 };

    try std.testing.expectEqual(
        F{ .val = 15 },
        try comath.eval("f + v", CTX, .{ .f = f, .v = 3 }),
    );

    try std.testing.expectEqual(
        false,
        eval("f < v", .{ .f  = f, .v = 3 }),
    );
}
