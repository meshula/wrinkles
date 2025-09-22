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
            comath.ctx.namespace.context(
                .{},
                // XXX: in case the tests (< > <= >= etc) are desired
                //
                // struct {
                //     pub const UnOp = enum { @"-", };
                //     pub const BinOp = enum {
                //         @"+", @"-", @"*", @"/", @"<", @"<=", @">", @">=" 
                //     };
                //
                //     pub inline fn matchBinOp(comptime str: []const u8) bool {
                //         return @hasField(BinOp, str);
                //     }
                //
                //     pub const relations = .{
                //         .@"+" = comath.relation(.left, 0),
                //         .@"-" = comath.relation(.left, 0),
                //         .@"*" = comath.relation(.left, 1),
                //         .@"/" = comath.relation(.left, 1),
                //         // .@"cos" = comath.relation(.left, 2),
                //         .@"<" = comath.relation(.left, 3),
                //         // .@"<=" = comath.relation(.left, 3),
                //         // .@">" = comath.relation(.left, 3),
                //         // .@">=" = comath.relation(.left, 3),
                //         // .@"==" = comath.relation(.left, 3),
                //     };
                //
                //     pub inline fn orderBinOp(
                //         comptime lhs: []const u8,
                //         comptime rhs: []const u8,
                //     ) ?comath.Order 
                //     {
                //         return @field(
                //             relations,
                //             lhs
                //         ).order(
                //             @field(relations, rhs)
                //         );
                //     }
                // }{}
            )
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

/// convert the string expr into a series of function calls at compile time
/// ie "a + b" -> `a.add(b)`
pub inline fn eval(
    /// math expression ie: "a + b - c"
    comptime expr: []const u8, 
    /// inputs ie: .{ .a = first_thing, .b = 12, .c = other_thing }
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

    // @TODO: these require building the context out further to support these
    //        operators.

    // try std.testing.expectEqual(
    //     false,
    //     eval("lhs < v", .{ .lhs  = lhs, .v = 3 }),
    // );
    //
    // try std.testing.expectEqual(
    //     true,
    //     eval("lhs < v", .{ .lhs  = lhs, .v = 15 }),
    // );

    // try std.testing.expectEqual(
    //     true,
    //     eval("lhs > v", .{ .lhs  = lhs, .v = 3 }),
    // );
    //
    // try std.testing.expectEqual(
    //     false,
    //     eval("lhs > v", .{ .lhs  = lhs, .v = 15 }),
    // );

    // try std.testing.expectEqual(
    //     false,
    //     eval("lhs == v", .{ .lhs  = lhs, .v = 15 }),
    // );

    // try std.testing.expectEqual(
    //     false,
    //     eval("lhs <= v", .{ .lhs  = lhs, .v = 3 }),
    // );
}
