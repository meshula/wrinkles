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

const CTX = comath.contexts.fnMethodCtx(
    comath.contexts.simpleCtx({}),
    .{
        .@"+" = "add",
        .@"*" = &.{"mul_float", "mul"},
    }
);

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
    return switch(@typeInfo(T)) {
        .Struct =>  DualOfStruct(T),
        else => DualOfNumberType(T),
    };
}

const Dual_f32 = DualOf(f32);
const Dual_CP = DualOf(ControlPoint);

pub fn DualOfNumberType(comptime T: type) type {
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

pub fn DualOfStruct(comptime T: type) type 
{
    return struct {
        /// real component
        r: T = .{},
        /// infinitesimal component
        i: T = .{},

        pub fn from(r: T) @TypeOf(@This()) {
            return .{ .r = r };
        }

        pub inline fn add(self: @This(), rhs: @This()) @This() {
            return .{
                .r = comath.eval(
                    "self_r + rhs_r",
                    CTX,
                    .{ .self_r = self.r, .rhs_r = rhs.r }
                ) catch |err| switch (err) {},
                .i = comath.eval(
                    "self_i + rhs_i",
                    CTX,
                    .{ .self_r = self.r, .rhs_r = rhs.r }
                ) catch |err| switch (err) {}
            };

            // return .{ 
            //     .r = self.r.add(rhs.r),
            //     .i = self.i.add(rhs.i),
            // };
        }

        pub inline fn mul(self: @This(), rhs: anytype) @This() {
            return switch(@typeInfo(@TypeOf(rhs))) {
                .Struct => .{ 
                    .r = self.r.mul(rhs.r),
                    .i = (self.r.mul(rhs.i)).add(self.i.mul(rhs.r)),
                },
                else => .{
                    .r = self.r * rhs,
                    .i = self.i * rhs,
                },
            };
        }
    };
}

/// control point for curve parameterization
pub const ControlPoint = struct {
    /// temporal coordinate of the control point
    time: f32 = 0,
    /// value of the Control point at the time cooridnate
    value: f32 = 0,

    // multiply with float
    pub fn mul(self: @This(), rhs: anytype) ControlPoint {
        return switch(@typeInfo(rhs)) {
            .Struct =>  .{
                .time = rhs.time*self.time,
                .value = rhs.value*self.value,
            },
            else => .{
                .time = rhs.time*self.time,
                .value = rhs.value*self.value,
            },
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

test "comath dual test polymorphic" {
    const test_data = &.{
        // as float
        .{
            .x = 3,
            .off1 = 2,
            .off2 = 1 ,
            .expect = 20,
        },
        // as float dual
        .{
            .x = Dual_f32{.r = 3, .i = 1},
            .off1 = Dual_f32{ .r = 2 },
            .off2 = Dual_f32{ .r = 1 }, 
            .expect = Dual_f32{ .r = 20, .i = 9},
        },
        // as control point dual
        .{
            .x = Dual_CP{
                .r = .{ .time = 3, .value = 3 },
                .i = .{ .time = 1, .value = 1 },
            },
            .off1 = Dual_CP{
                .r = .{ .time = 2, .value = 2 },
            },
            .off2 = Dual_CP{
                .r = .{ .time = 1, .value = 1 },
            },
            .expect = Dual_CP{
                .r = .{ .time = 20, .value = 20 },
                .i = .{ .time = 9, .value = 9 },
            },
        },
        .{
            .x = Dual_CP{
                .r = .{ .time = -3, .value = -2 },
                .i = .{ .time = 1, .value = 1 },
            },
            .off1 = Dual_CP{
                .r = .{ .time = 2, .value = 3 },
            },
            .off2 = Dual_CP{
                .r = .{ .time = 1, .value = 1 },
            },
            .expect = Dual_CP{
                .r = .{ .time = 2, .value = -1 },
                .i = .{ .time = -3, .value = 0 },
            },
        },
    };

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

    inline for (test_data, 0..) |td, i| {
        const value = comath.eval(
            fn_str,
            ctx,
            .{.x = td.x, .off1 = td.off1, .off2 = td.off2}
        ) catch |err| switch (err) {};

        errdefer std.debug.print(
            "{d}: Failed for type: {s}, \nrecieved: {any}\nexpected: {any}\n\n",
            .{ i,  @typeName(@TypeOf(td.x)), value, td.expect }
        );

        try std.testing.expect(std.meta.eql(value, td.expect));
    }
}

pub fn lerp(u: f32, a: anytype, b: @TypeOf(a)) @TypeOf(a) {
    return comath.eval(
        "a * (1 - u) + b * u",
        CTX,
        .{ .a = a, .b = b, .u = u}
    ) catch |err| switch (err) {};
}

test "test lerp" {
    const test_data = &.{
        // as float
        .{
            .u = 0.25,
            .a = 1.0,
            .b = 2.0,
            .expect = 1.25,
        },
        // as float dual
        .{
            .u = 0.25,
            .a = Dual_f32{ .r = 1 },
            .b = Dual_f32{ .r = 2 }, 
            .expect = Dual_f32{ .r = 1.25, .i = 3.14 },
        },
        // as control point dual
        .{
            .u = 0.25,
            .a = Dual_CP{
                .r = .{ .time = 1, .value = 5 },
            },
            .b = Dual_CP{
                .r = .{ .time = 2, .value = 15 },
            },
            .expect = Dual_CP{
                .r = .{ .time = 2, .value = 15 },
                .i = .{ .time = -3, .value = 0 },
            },
        },
    };

    inline for (test_data, 0..) |td, i| {
        const value = lerp(td.u, td.a, td.b);

        errdefer std.debug.print(
            "{d}: Failed for type: {s}, \nrecieved: {any}\nexpected: {any}\n\n",
            .{ i,  @typeName(@TypeOf(td.a)), value, td.expect }
        );

        try std.testing.expect(std.meta.eql(value, td.expect));
    }
}
