//! Affine Transform Mapping

const std = @import("std");

const opentime = @import("opentime");
const mapping_mod = @import("mapping.zig");

/// An affine mapping from intput to output
pub const MappingAffine = struct {
    input_bounds_val: opentime.ContinuousInterval,
    input_to_output_xform: opentime.AffineTransform1D, 

    /// An infinite identity mapping.
    pub const identity_infinite: MappingAffine = .{
        .input_bounds_val= .inf_neg_to_pos,
        .input_to_output_xform= .identity, 
    };

    pub fn mapping(
        self: @This(),
    ) mapping_mod.Mapping
    {
        return .{ .affine = self };
    }

    pub fn input_bounds(
        self: @This(),
    ) opentime.ContinuousInterval 
    {
        return self.input_bounds_val;
    }

    pub fn output_bounds(
        self: @This(),
    ) opentime.ContinuousInterval 
    {
        const unsorted_bounds = (
            self.input_to_output_xform.applied_to_interval(
                self.input_bounds_val,
            )
        );

        return .{
            .start = opentime.min(
                unsorted_bounds.start,
                unsorted_bounds.end
            ),
            .end = opentime.max(
                unsorted_bounds.start,
                unsorted_bounds.end
            ),
        };
    }

    pub fn project_instantaneous_cc(
        self: @This(),
        input_space_ordinate: opentime.Ordinate,
    ) opentime.ProjectionResult
    {
        if (
            !self.input_bounds_val.overlaps(input_space_ordinate) 
            // allow projecting the end point
            and !input_space_ordinate.eql(self.input_bounds_val.end)
        )
        {
            return .out_of_bounds;
        }

        return self.project_instantaneous_cc_assume_in_bounds(
            input_space_ordinate
        );
    }

    pub fn project_instantaneous_cc_assume_in_bounds(
        self: MappingAffine,
        input_space_ordinate: opentime.Ordinate,
    ) opentime.ProjectionResult
    {
        return .{ 
            .success_ordinate = (
                self.input_to_output_xform.applied_to_ordinate(
                    input_space_ordinate
                )
            ),
        };
    }

    /// project from the output space back to the input space
    pub fn project_instantaneous_cc_inv(
        self: @This(),
        output_ordinate: opentime.Ordinate,
    ) opentime.ProjectionResult
    {
        if (
            !self.output_bounds().overlaps(output_ordinate) 
            // allow projecting the end point
            and !(output_ordinate.eql(self.output_bounds().end))
        )
        {
            return .out_of_bounds;
        }

        return self.project_instantaneous_cc_assume_in_bounds(output_ordinate);
    }

    // @TODO: also needed?
    // pub fn project_instantaneous_cc_inv_assume_in_bounds(
    //     self: @This(),
    //     output_ordinate: opentime.Ordinate,
    // ) opentime.ProjectionResult
    // {
    //     return .{
    //         .success_ordinate = self.input_to_output_xform.inverted(
    //         ).applied_to_ordinate(output_ordinate)
    //     };
    // }

    pub fn clone(
        self: @This(),
    ) MappingAffine
    {
        return .{
            .input_bounds_val = self.input_bounds_val,
            .input_to_output_xform = self.input_to_output_xform,
        };
    }

    pub fn shrink_to_output_interval(
        self: @This(),
        // other implementations of shrink_to_input_interval take an allocator
        // and might return an error
        _: std.mem.Allocator,
        target_output_interval: opentime.ContinuousInterval,
    ) !?mapping_mod.Mapping
    {
        const target_input_interval = (
            self.input_to_output_xform.inverted().applied_to_bounds(
                target_output_interval
            )
        );

        return (
            MappingAffine{
                .input_bounds_val = opentime.interval.intersect(
                    self.input_bounds_val,
                    target_input_interval,
                ) orelse return null,
                .input_to_output_xform = (
                    self.input_to_output_xform
                ),
            }
        ).mapping();
    }

    pub fn shrink_to_input_interval(
        self: @This(),
        _: std.mem.Allocator,
        target_output_interval: opentime.ContinuousInterval,
    ) !?mapping_mod.Mapping
    {
        return (
            MappingAffine{
                .input_bounds_val = (
                    opentime.interval.intersect(
                        self.input_bounds_val,
                        target_output_interval,
                    ) orelse return error.NoOverlap
                ),
                .input_to_output_xform = self.input_to_output_xform,
            }
        ).mapping();
    }

    pub fn split_at_input_ord(
        self: @This(),
        _: std.mem.Allocator,
        pt_input: opentime.Ordinate,
    ) ![2]mapping_mod.Mapping
    {
        return .{
            .{ 
                .affine = .{
                    .input_bounds_val = .{
                        .start = self.input_bounds_val.start,
                        .end = pt_input,
                    },
                    .input_to_output_xform = self.input_to_output_xform,
                },
            },
            .{ 
                .affine = .{
                    .input_bounds_val = .{
                        .start = pt_input,
                        .end = self.input_bounds_val.end,
                    },
                    .input_to_output_xform = self.input_to_output_xform,
                },
            },
        };
    }

    /// split at any of the points that are within the bounds of the mapping
    pub fn split_at_each_input_ord(
        self: @This(),
        allocator: std.mem.Allocator,
        input_points: []const opentime.Ordinate,
    ) ![]const mapping_mod.Mapping
    {
        var result_mappings: std.ArrayList(mapping_mod.Mapping) = .empty;
        defer result_mappings.deinit(allocator);

        var maybe_first_pt: ?usize = null;
        
        for (input_points, 0..)
            |pt, pt_ind|
        {
            if (
                pt.gt(self.input_bounds_val.start)
                and pt.lt(self.input_bounds_val.end)
            )
            {
                maybe_first_pt = pt_ind;
                break;
            }
        }

        // none of the points map
        if (maybe_first_pt == null)
        {
            try result_mappings.append(allocator,self.mapping());
            return try result_mappings.toOwnedSlice(allocator);
        }

        var current_start = self.input_bounds_val.start;
        var current_end_ind = maybe_first_pt.?;

        try result_mappings.ensureTotalCapacity(
            allocator,
            input_points.len + 2,
        );

        while (current_end_ind < input_points.len)
        {
            var current_end = input_points[current_end_ind];

            if (current_end.gt(self.input_bounds_val.end))
            {
                current_end = self.input_bounds_val.end;
                current_end_ind = input_points.len;
            }

            result_mappings.appendAssumeCapacity(
                .{
                    .affine = .{
                        .input_bounds_val = .{
                            .start = current_start,
                            .end = current_end,
                        },
                        .input_to_output_xform = (
                            self.input_to_output_xform
                        ),
                    },
                },
            );

            current_start = current_end;
            current_end_ind += 1;
        }

        return try result_mappings.toOwnedSlice(allocator);
    }
};

test "MappingAffine: instantiate (identity)"
{
    const ma = MappingAffine.identity_infinite.mapping();

    try opentime.expectOrdinateEqual(
        12, 
        ma.project_instantaneous_cc(
            opentime.Ordinate.init(12)
        ).ordinate(),
    );
}

test "MappingAffine: non-identity"
{
    const ma = (
        MappingAffine{
            .input_bounds_val = .init(
                .{ .start = 3, .end = 6, }
            ),
            .input_to_output_xform = .{
                .offset = .init(2),
                .scale = .init(4),
            },
        }
    ).mapping();

    try opentime.expectOrdinateEqual(
        14,
        ma.project_instantaneous_cc(
            opentime.Ordinate.init(3)
        ).ordinate(),
    );
}

test "MappingAffine: clone"
{
    const allocator = std.testing.allocator;

    const ma = (
        MappingAffine{
            .input_bounds_val = .init(
                .{ .start = 3, .end = 6, }
            ),
            .input_to_output_xform = .{
                .offset = .init(2),
                .scale = .init(4),
            },
        }
    ).mapping();

    try opentime.expectOrdinateEqual(
        14,
        ma.project_instantaneous_cc(
            opentime.Ordinate.init(3)
        ).ordinate(),
    );

    const ma_2 = try ma.clone(allocator);

    try std.testing.expectEqual(
        ma.affine.input_bounds_val.start,
        ma_2.affine.input_bounds_val.start,
    );
}
