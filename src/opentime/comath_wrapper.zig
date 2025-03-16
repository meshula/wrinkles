
const std = @import("std");

const comath = @import("comath");

pub const CTX = comath.ctx.fnMethod(
    comath.ctx.simple({}),
    .{
        .@"+" = "add",
        .@"-" = &.{"sub", "negate", "neg"},
        .@"*" = "mul",
        .@"/" = "div",
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
