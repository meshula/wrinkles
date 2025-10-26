//! ProjectionResult implementation

const std = @import("std");

const ordinate_m = @import("ordinate.zig");
const interval_m = @import("interval.zig");

/// Contains the result of a projection, which can be an instant (single
/// ordinate), a range (continuous interval) or an out of bounds result.
pub const ProjectionResult = union (enum) {
    SuccessOrdinate : ordinate_m.Ordinate,
    SuccessInterval : interval_m.ContinuousInterval,
    OutOfBounds : ?void,

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
            .SuccessOrdinate => |val| return val,
            .OutOfBounds => return Errors.OutOfBounds,
            else => return Errors.NotAnOrdinateResult,
        }
    }

    /// fetch a range result or return an error if the result isn't a range
    pub fn interval(
        self: @This(),
    ) !interval_m.ContinuousInterval
    {
        switch (self) {
            .SuccessInterval => |val| return val,
            .OutOfBounds => return Errors.OutOfBounds,
            else => return Errors.NotAnIntervalResult,
        }
    }

    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) !void 
    {
        switch (self) {
            .SuccessOrdinate => |ord| try writer.print(
                "ProjResult{{ .ordinate = {d} }}",
                .{ ord },
            ),
            .SuccessInterval => |inf| try writer.print(
                "ProjResult{{ .interval = {s} }}",
                .{ inf },
            ),
            .OutOfBounds => try writer.print(
                "ProjResult{{ .OutOfBounds }}",
                .{},
            ),
        }
    }
};

/// an out of bounds projection result
pub const OUTOFBOUNDS = ProjectionResult{
    .OutOfBounds = null,
};
