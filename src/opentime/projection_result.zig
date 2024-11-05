const ordinate = @import("ordinate.zig");
const interval = @import("interval.zig");

const std = @import("std");

pub const ProjectionResult = union (enum) {
    SuccessFinite : ordinate.Ordinate,
    SuccessInfinite : interval.ContinuousTimeInterval,
    OutOfBounds : ?void,

    pub const Errors = struct {
        pub const NotAFiniteProjectionResult = error.NotAFiniteProjectionResult;
        pub const OutOfBounds = error.OutOfBounds;
    };

    /// fetch the finite result or return an error if it is not a finite sucess
    pub fn finite(
        self: @This(),
    ) !f32
    {
        switch (self) {
            .SuccessFinite => |val| return val,
            else => return Errors.NotAFiniteProjectionResult,
        }
    }

    pub fn format(
        self: @This(),
        // fmt
        comptime _: []const u8,
        // options
        _: std.fmt.FormatOptions,
        writer: anytype,
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

pub const OUTOFBOUNDS = ProjectionResult{
    .OutOfBounds = null,
};
