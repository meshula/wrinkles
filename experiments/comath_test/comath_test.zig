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

pub fn DualOf(comptime T: type) type 
{
    return struct {
        /// real component
        r: T = 0,
        /// infinitesimal component
        i: T = 0,

        pub fn from(r: T) @TypeOf(@This()) {
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
}

const Dual_f32 = DualOf(f32);

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

    // const ctx = comath.contexts.fnMethodCtx(
    //     comath.contexts.simpleCtx({}),
    //     .{
    //         .@"+" = "add",
    //         .@"*" = "mul",
    //     }
    // );

/// control point for curve parameterization
pub const ControlPoint = struct {
    /// temporal coordinate of the control point
    time: f32,
    /// value of the Control point at the time cooridnate
    value: f32,

    // multiply with float
    pub fn mul(self: @This(), val: f32) ControlPoint {
        return .{
            .time = val*self.time,
            .value = val*self.value,
        };
    }

    pub fn div(self: @This(), val: f32) ControlPoint {
        return .{
            .time  = self.time/val,
            .value = self.value/val,
        };
    }

    pub fn add(self: @This(), rhs: ControlPoint) ControlPoint {
        return .{
            .time = self.time + rhs.time,
            .value = self.value + rhs.value,
        };
    }

    pub fn sub(self: @This(), rhs: ControlPoint) ControlPoint {
        return .{
            .time = self.time - rhs.time,
            .value = self.value - rhs.value,
        };
    }

    pub fn distance(self: @This(), rhs: ControlPoint) f32 {
        const diff = rhs.sub(self);
        return std.math.sqrt(diff.time * diff.time + diff.value * diff.value);
    }

    pub fn normalized(self: @This()) ControlPoint {
        const d = self.distance(.{ .time=0, .value=0 });
        return .{ .time = self.time/d, .value = self.value/d };
    }
};

test "reuse" {
    const ctx = comath.contexts.simpleCtx({});

    const p : []const f32 = &.{ 0, 1, 2, 3 };
    const unorm:f32 = 0.5;
    const q1 = try comath.eval(
        "(1 - unorm) * p[0] + unorm * p[1]",
        ctx,
        .{ 
            .p = p,
            .unorm = unorm,
        },
    );

    const q2 = try comath.eval(
        "(1 - unorm) * Q1 + unorm * ((1 - unorm) * p[1] + unorm * p[2])",
        ctx,
        .{ 
            .p = p,
            .Q1 = q1,
            .unorm = unorm,
        },
    );
    _ = q2;
}

// test "math_port_test" 
// {
//     const ctx = comath.contexts.fnMethodCtx(
//         comath.contexts.simpleCtx({}),
//         .{
//             .@"+" = "add",
//             .@"*" = "mul",
//         }
//     );
//
//     // inputs
//     const p : []const ControlPoint = &.{ 
//         .{ .time = 0, .value = 0 },
//         .{ .time = 0, .value = 1 },
//         .{ .time = 1, .value = 1 },
//         .{ .time = 1, .value = 0 },
//     };
//     const unorm:f32 = 0.5;
//
//     // left segment points
//     const q0 = p[0];
//     _ = q0;
//
//     const q1 = try comath.eval(
//         "(1 - unorm) * p[0] + unorm * p[1]",
//         ctx,
//         .{ 
//             .p = p,
//             .unorm = unorm,
//         },
//     );
//
//     const q2:f32 = try comath.eval(
//         "(1 - unorm) * q1 + unorm * ((1 - unorm) * p[1] + unorm * p[2])",
//         ctx,
//         .{ 
//             .p = p,
//             .q1 = q1,
//             .unorm = unorm,
//         },
//     );
//
//     const q3 = try comath.eval(
//         "(1 - unorm) * Q2" ++ 
//         " + unorm * ("
//             ++ "(1 - unorm) * ((1 - unorm) * p[1] "
//             ++ "+ unorm * p[2]) + unorm * ((1 - unorm) * p[2] + unorm * p[3])"
//         ++ ")",
//         ctx,
//         .{ 
//             .p = p,
//             .Q2 = q2,
//             .unorm = unorm,
//         },
//     );
//
//     // right segment points
//     const r0 = q3;
//     _ = r0;   
//
//     const r2:f32 = try comath.eval(
//         "(1 - unorm) * p[2] + unorm * p[3]",
//         ctx,
//         .{ 
//             .p = p,
//             .unorm = unorm,
//         },
//     );
//
//     const r1:f32 = try comath.eval(
//         "(1 - unorm) * ((1 - unorm) * p[1] + unorm * p[2]) + unorm * R2",
//         ctx,
//         .{ 
//             .p = p,
//             .R2 = r2,
//             .unorm = unorm,
//         },
//     );
//     _ = r1;
//
//     const r3 = p[3];
//     _ = r3;
// }
