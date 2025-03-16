
const std = @import("std");

const comath = @import("comath");

pub const CTX = comath.ctx.fnMethod(
    comath.ctx.simple(
        .{},
        // struct {
        //     pub fn matchBinOp(comptime str: []const u8) bool {
        //         return str.len == 1 and (str[0] == '<' or str[0] == '>');
        //     }
        //     pub fn orderBinOp(comptime lhs: []const u8, comptime rhs: []const u8) ?comath.Order {
        //         comptime return switch (std.math.order(lhs, rhs)) {
        //             .lt => .lt,
        //             .gt => .gt,
        //             .eq => if (lhs.assoc != rhs.assoc) .incompatible else switch (lhs.assoc) {
        //                 .none => .incompatible,
        //                 .right => .lt,
        //                 .left => .gt,
        //             },
        //         };
        //
        //     }
        // }{}
    ),
    .{
        .@"+" = "add",
        .@"-" = &.{"sub", "negate", "neg"},
        .@"*" = "mul",
        .@"/" = "div",
        .@"<" = "lt",
        .@"<=" = "lteq",
        .@">" = "gt",
        .@">=" = "gteq",
        .@"cos" = "cos",
    },
);
pub inline fn eval(
    comptime expr: []const u8, 
    inputs: anytype,
) comath.Eval(expr, @TypeOf(CTX), @TypeOf(inputs))
{
    @setEvalBranchQuota(16000);
    return raw_eval(expr, CTX, inputs);
}

pub fn raw_eval(
    comptime expr: []const u8, 
    ctx: anytype,
    inputs: anytype
) comath.Eval(expr, @TypeOf(ctx), @TypeOf(inputs))
{
    @setEvalBranchQuota(16000);
    return comath.eval(
        expr, CTX, inputs
    ) catch @compileError(
        "couldn't comath: " ++ expr ++ "."
    );
}

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

test "comath test"
{
    const f = F{ .val = 12 };

    try std.testing.expectEqual(
        F{ .val = 15 },
        eval("f + v", .{ .f = f, .v = 3 }),
    );

    // try std.testing.expectEqual(
    //     false,
    //     eval("f < v", .{ .f  = f, .v = 3 }),
    // );
}
