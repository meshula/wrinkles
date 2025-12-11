//! Wrapper around the comath library for the wrinkles project.  Exposes an 
//! eval function to convert math expressions at compile time from strings like
//! "a+b / c" into function calls, ie `(a.add(b.div(c))`.

const std = @import("std");

const comath = @import("comath");

/// Comath Context for the wrinkles project.  Comath allows for compile time
/// operator overloading for math expressions like "a + b / c".
const CTX = (
    comath.ctx.fn_method.context(
        comath.ctx.simple.context(
            comath.ctx.namespace.context(.{},)
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
            .@"==" = "eq",
            .@"cos" = "cos",
        },
    )
);

/// Convert the string expr into a series of function calls at compile time
/// ie "a + b" -> `a.add(b)`.
pub inline fn eval(
    /// Math expression ie: "a + b - c".
    comptime expr: []const u8, 
    /// Inputs ie: .{ .a = first_thing, .b = 12, .c = other_thing }.
    inputs: anytype,
) comath.Eval(expr, @TypeOf(CTX), @TypeOf(inputs))
{
    @setEvalBranchQuota(100000);
    return comath.eval(
        expr, CTX, inputs
    ) catch @compileError(
        "couldn't comath: " ++ expr ++ "."
    );
}

test "comath test"
{
    const TestType = struct{
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
        ) @This() {
            return .{ .val = self.val + rhs };
        }
    };

    const lhs = TestType{ .val = 12 };

    try std.testing.expectEqual(
        TestType{ .val = 15 },
        eval("lhs + v", .{ .lhs = lhs, .v = 3 }),
    );
}
