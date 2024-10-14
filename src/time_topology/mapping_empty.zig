//! MappingEmpty & Tests

const std = @import("std");

const opentime = @import("opentime");
const serialization = @import("serialization.zig");
const mapping_mod = @import("mapping.zig");

/// Regardless what the input ordinate is, there is no value mapped to it
pub const MappingEmpty = struct {

    /// build a generic mapping from this empty mapping
    pub fn mapping(
        self:@This(),
    ) mapping_mod.Mapping
    {
        return .{
            .empty = self,
        };
    }

    pub fn project_instantaneous_cc(
        _: @This(),
        _: opentime.Ordinate
    ) !opentime.Ordinate 
    {
        return error.OutOfBounds;
    }

    pub fn inverted(
        _: @This()
    ) !MappingEmpty 
    {
        return .{};
    }

    pub fn input_bounds(
        _: @This(),
    ) opentime.ContinuousTimeInterval 
    {
        return opentime.interval.INF_CTI;
    }

    pub fn output_bounds(
        _: @This(),
    ) opentime.ContinuousTimeInterval 
    {
        return opentime.interval.INF_CTI;
    }

    pub fn clone(
        _: @This(),
        _: std.mem.Allocator,
    ) !MappingEmpty
    {
        return EMPTY;
    }

    pub fn shrink_to_input_interval(
        _: @This(),
        _: std.mem.Allocator,
        _: opentime.ContinuousTimeInterval,
    ) !MappingEmpty
    {
        return EMPTY;
    }

    pub fn shrink_to_output_interval(
        _: @This(),
        _: std.mem.Allocator,
        _: opentime.ContinuousTimeInterval,
    ) !MappingEmpty
    {
        return EMPTY;
    }

    ///
    pub fn split_at_input_point(
        self: @This(),
        allocator: std.mem.Allocator,
        pt: opentime.Ordinate,
    ) ![2]mapping_mod.Mapping
    {
        _ = self;
        _ = allocator;
        _ = pt;

        return .{ EMPTY.mapping(), EMPTY.mapping() };
    }
};

pub const EMPTY = MappingEmpty{};

test "MappingEmpty: instantiate and convert"
{
    const me = (MappingEmpty{}).mapping();
    const json_txt =  try serialization.to_string(
        std.testing.allocator,
        me
    );
    defer std.testing.allocator.free(json_txt);
}

test "MappingEmpty: Project"
{
    const me = (MappingEmpty{}).mapping();

    var v : f32 = -10;
    while (v < 10)
        : (v += 0.2)
    {
        try std.testing.expectError(
            error.OutOfBounds,
            me.project_instantaneous_cc(1.0)
        );
    }
}

test "MappingEmpty: Bounds"
{
    const me = (MappingEmpty{}).mapping();

    const i_b = me.input_bounds();
    try std.testing.expect(i_b.is_infinite());
    try std.testing.expectEqual(
        opentime.interval.INF_CTI.start_seconds,
        i_b.start_seconds
    );
    try std.testing.expectEqual(
        opentime.interval.INF_CTI.end_seconds,
        i_b.end_seconds
    );

    const o_b = me.output_bounds();
    try std.testing.expect(o_b.is_infinite());
    try std.testing.expectEqual(
        opentime.interval.INF_CTI.start_seconds,
        o_b.start_seconds
    );
    try std.testing.expectEqual(
        opentime.interval.INF_CTI.end_seconds,
        o_b.end_seconds
    );
}
