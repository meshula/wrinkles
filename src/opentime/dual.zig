const std = @import("std");
const comath = @import("comath");

pub fn eval(
    comptime expr: []const u8, 
    inputs: anytype,
) !comath.Eval(expr, @TypeOf(CTX), @TypeOf(inputs))
{
    return comath.eval(expr, CTX, inputs);
}


pub fn DualOf(comptime T: type) type 
{
    return switch(@typeInfo(T)) {
        .Struct =>  DualOfStruct(T),
        else => DualOfNumberType(T),
    };
}

// build the context
pub const CTX = comath.ctx.fnMethod(
    comath.ctx.simple({}),
    .{
        .@"+" = "add",
        .@"*" = "mul",
    }
);

pub const Dual_f32 = DualOf(f32);
pub const Dual_CP = DualOf(ControlPoint);

// default dual type for opentime
pub const Dual_t = Dual_f32;

pub fn DualOfNumberType(comptime T: type) type {
    return struct {
        /// real component
        r: T = 0,
        /// infinitesimal component
        i: T = 0,

        pub fn init(r: T) @This() {
            return .{ .r = r };
        }

        pub fn negate(self: @This()) @This() {
            return .{ .r = -self.r, .i = -self.i };
        }

        pub inline fn add(self: @This(), rhs: anytype) @This() {
            return switch(@typeInfo(@TypeOf(rhs))) {
                .Struct => .{ 
                    .r = self.r + rhs.r,
                    .i = self.i + rhs.i,
                },
                else => .{
                    .r = self.r + rhs,
                    .i = self.i,
                },
            };
        }

        pub inline fn sub(self: @This(), rhs: anytype) @This() {
            return switch(@typeInfo(@TypeOf(rhs))) {
                .Struct => .{ 
                    .r = self.r - rhs.r,
                    .i = self.i - rhs.i,
                },
                else => .{
                    .r = self.r - rhs,
                    .i = self.i,
                },
            };
        }

        pub inline fn mul(self: @This(), rhs: anytype) @This() {
            return switch(@typeInfo(@TypeOf(rhs))) {
                .Struct => .{ 
                    .r = self.r * rhs.r,
                    .i = self.r * rhs.i + self.i*rhs.r,
                },
                else => .{
                    .r = self.r * rhs,
                    .i = self.i * rhs,
                },
            };
        }

        pub inline fn lt(self: @This(), rhs: @This()) @This() {
            return self.r < rhs.r;
        }

        pub inline fn gt(self: @This(), rhs: @This()) @This() {
            return self.r > rhs.r;
        }

        pub inline fn div(self: @This(), rhs: @This()) @This() {
            return .{
                .r = self.r / rhs.r,
                .i = (rhs.r * self.i - self.r * rhs.i) / (rhs.r * rhs.r),
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
                    .{ .self_i = self.i, .rhs_i = rhs.i }
                ) catch |err| switch (err) {}
            };
        }

        pub inline fn mul(self: @This(), rhs: anytype) @This() {
            return switch(@typeInfo(@TypeOf(rhs))) {
                .Struct => .{ 
                    .r = self.r.mul(rhs.r),
                    .i = (self.r.mul(rhs.i)).add(self.i.mul(rhs.r)),
                },
                else => .{
                    .r = self.r.mul(rhs),
                    .i = self.i.mul(rhs),
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


    inline for (test_data, 0..) |td, i| {
        const value = comath.eval(
            fn_str,
            CTX,
            .{.x = td.x, .off1 = td.off1, .off2 = td.off2}
        ) catch |err| switch (err) {};

        errdefer std.debug.print(
            "{d}: Failed for type: {s}, \nrecieved: {any}\nexpected: {any}\n\n",
            .{ i,  @typeName(@TypeOf(td.x)), value, td.expect }
        );

        try std.testing.expect(std.meta.eql(value, td.expect));
    }
}
