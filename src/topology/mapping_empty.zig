//! MappingEmpty & Tests

const std = @import("std");

const opentime = @import("opentime");
const mapping_mod = @import("mapping.zig");

/// Regardless what the input ordinate is, there is no value mapped to it.
pub const MappingEmpty = struct {
    /// The input range (and effective output range) of the mapping.
    defined_range: opentime.ContinuousInterval,

    pub const empty_infinite = MappingEmpty{
        .defined_range = .inf_neg_to_pos,
    };

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
    ) opentime.ProjectionResult
    {
        return .out_of_bounds;
    }

    pub const project_instantaneous_cc_assume_in_bounds = (
        project_instantaneous_cc
    );

    pub fn project_instantaneous_cc_inv(
        _: @This(),
        _: opentime.Ordinate
    ) opentime.ProjectionResult
    {
        return .out_of_bounds;
    }

    pub fn inverted(
        _: @This()
    ) !MappingEmpty 
    {
        return .{};
    }

    pub fn input_bounds(
        self: @This(),
    ) opentime.ContinuousInterval 
    {
        return self.defined_range;
    }

    pub fn output_bounds(
        self: @This(),
    ) opentime.ContinuousInterval 
    {
        return self.input_bounds();
    }

    pub fn clone(
        self: @This(),
        _: std.mem.Allocator,
    ) !MappingEmpty
    {
        return .{
            .defined_range = .{
                .start = self.defined_range.start,
                .end = self.defined_range.end,
            },
        };
    }

    pub fn shrink_to_input_interval(
        self: @This(),
        _: std.mem.Allocator,
        target_range: opentime.ContinuousInterval,
    ) !?mapping_mod.Mapping
    {
        const maybe_new_range = (
            opentime.interval.intersect(
                self.defined_range,
                target_range,
            )
        );
        if (maybe_new_range)
            |new_range|
        {
            return (
                MappingEmpty{
                    .defined_range = new_range,
                }
            ).mapping();
        }

        return error.OutOfBounds;
    }

    /// for the empty, return self, no output interval to shrink
    pub fn shrink_to_output_interval(
        self: @This(),
        _: std.mem.Allocator,
        _: opentime.ContinuousInterval,
    ) !?mapping_mod.Mapping
    {
        return self.mapping();
    }

    /// Empty always splits to more emptys.
    pub fn split_at_input_ord(
        self: @This(),
        _: std.mem.Allocator,
        pt: opentime.Ordinate,
    ) ![2]mapping_mod.Mapping
    {
        return .{ 
            .{
                .empty = .{
                    .defined_range = .{
                        .start = self.defined_range.start,
                        .end = pt,
                    },
                },
            },
            .{
                .empty = .{
                    .defined_range = .{
                        .start = pt,
                        .end = self.defined_range.end,
                    },
                },
            },
        };
    }
};

test "MappingEmpty: Project"
{
    const me = MappingEmpty.empty_infinite;

    var v = opentime.Ordinate.init(-10);
    while (v.lt(10))
        : (v = v.add(0.2))
    {
        try std.testing.expectError(
            error.OutOfBounds,
            me.project_instantaneous_cc(v).ordinate()
        );
    }
}

test "MappingEmpty: Bounds"
{
    const me = (
        MappingEmpty{
            .defined_range = .{
                .start = .init(-2),
                .end = .init(2),
            },
        }
    ).mapping();

    const i_b = me.input_bounds().?;
    try opentime.expectOrdinateEqual(
        -2,
        i_b.start
    );
    try opentime.expectOrdinateEqual(
        2,
        i_b.end
    );

    // returns an infinite output bounds
    const o_b = me.output_bounds().?;
    try opentime.expectOrdinateEqual(
        -2,
        o_b.start
    );
    try opentime.expectOrdinateEqual(
        2,
        o_b.end
    );
}
