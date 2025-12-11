//! ProjectionResult implementation

const std = @import("std");

const ordinate_m = @import("ordinate.zig");
const interval_m = @import("interval.zig");

/// Contains the result of a projection, which can be an instant (single
/// ordinate), a range (continuous interval) or an out of bounds result.
pub const ProjectionResult = union (enum) {
    success_ordinate: ordinate_m.Ordinate,
    success_interval: interval_m.ContinuousInterval,
    out_of_bounds: void,

    pub const Errors = struct {
        pub const NotAnOrdinateResult = error.NotAnOrdinateResult;
        pub const NotAnIntervalResult = error.NotAnIntervalResult;
        pub const OutOfBounds = error.OutOfBounds;
    };

    /// fetch the finite result or return an error if it is not a finite sucess
    pub fn ordinate(
        self: @This(),
    ) !ordinate_m.Ordinate
    {
        switch (self) {
            .success_ordinate => |val| return val,
            .out_of_bounds => return Errors.OutOfBounds,
            else => return Errors.NotAnOrdinateResult,
        }
    }

    /// fetch a range result or return an error if the result isn't a range
    pub fn interval(
        self: @This(),
    ) !interval_m.ContinuousInterval
    {
        switch (self) {
            .success_interval => |val| return val,
            .out_of_bounds => return Errors.OutOfBounds,
            else => return Errors.NotAnIntervalResult,
        }
    }

    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) !void 
    {
        switch (self) {
            .success_ordinate => |ord| try writer.print(
                "ProjResult{{ .ordinate = {d} }}",
                .{ ord },
            ),
            .success_interval => |inf| try writer.print(
                "ProjResult{{ .interval = {s} }}",
                .{ inf },
            ),
            .out_of_bounds => try writer.print(
                "ProjResult{{ .out_of_bounds }}",
                .{},
            ),
        }
    }
};
