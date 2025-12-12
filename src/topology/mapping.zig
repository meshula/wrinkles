//! Mapping / OpenTimelineIO
//!
//! Functions and structs related to the Mapping component of OTIO.

const std = @import("std");

const opentime = @import("opentime");

const mapping_empty = @import("mapping_empty.zig");
pub const MappingEmpty = mapping_empty.MappingEmpty;

const mapping_affine = @import("mapping_affine.zig");
pub const MappingAffine = mapping_affine.MappingAffine;

const mapping_curve_linear = @import("mapping_curve_linear.zig");
pub const MappingCurveLinearMonotonic = (
    mapping_curve_linear.MappingCurveLinearMonotonic
);

const curve = @import("curve");

/// A Mapping is a polymorphic container for a function that maps from an
/// "input" space to an "output" space.  Mappings can be joined with other
/// mappings via function composition to build new transformations via common
/// spaces. Mappings can project ordinates and ranges from their input space
/// to their output space.
pub const Mapping = union (enum) {
    empty: mapping_empty.MappingEmpty,
    affine: mapping_affine.MappingAffine,
    linear: mapping_curve_linear.MappingCurveLinearMonotonic,

    pub const identity_infinite = (
        MappingAffine.identity_infinite.mapping()
    );

    pub fn deinit(
        self: @This(),
        allocator: std.mem.Allocator,
    ) void
    {
        return switch (self) {
            // these do not have allocations, and do not need to be deinited
            .empty, .affine => {},
            inline else => |m| m.deinit(allocator),
        };
    }

    /// project an instantaneous ordinate from the input space to the output
    /// space
    pub fn project_instantaneous_cc(
        self: @This(),
        input_ord: anytype,
    ) opentime.ProjectionResult 
    {
        return switch (self) {
            inline else => |m| m.project_instantaneous_cc(
                switch (@TypeOf(input_ord)) {
                    opentime.Ordinate => input_ord,
                    else => opentime.Ordinate.init(input_ord),
                }
            ),
        };
    }

    /// project an instantaneous ordinate from the input space to the output
    /// space, without the bounds check
    pub fn project_instantaneous_cc_assume_in_bounds(
        self: @This(),
        input_ord: anytype,
    ) opentime.ProjectionResult 
    {
        return switch (self) {
            inline else => |m| m.project_instantaneous_cc_assume_in_bounds(
                switch (@TypeOf(input_ord)) {
                    opentime.Ordinate => input_ord,
                    else => opentime.Ordinate.init(input_ord),
                }
            ),
        };
    }

    /// project an instantaneous ordinate from the output space to the input
    /// space
    pub fn project_instantaneous_cc_inv(
        self: @This(),
        output_ord: opentime.Ordinate,
    ) opentime.ProjectionResult
    {
        return switch (self) {
            inline else => |m| m.project_instantaneous_cc_inv(output_ord),
        };
    }

    /// fetch (computing if necessary) the input bounds of the mapping
    pub fn input_bounds(
        self: @This(),
    ) ?opentime.ContinuousInterval
    {
        return switch (self) {
            inline else => |contained| contained.input_bounds(),
        };
    }

    /// fetch (computing if necessary) the output bounds of the mapping
    pub fn output_bounds(
        self: @This(),
    ) ?opentime.ContinuousInterval
    {
        return switch (self) {
            inline else => |contained| contained.output_bounds(),
        };
    }

    /// Make a copy of this Mapping
    pub fn clone(
        self: @This(),
        allocator: std.mem.Allocator,
    ) !Mapping
    {
        return switch (self) {
            // do not need an allocator
            inline .affine, .empty => |m| (
                m.clone().mapping()
            ),
            inline else => |contained| (
                try contained.clone(allocator)
            ).mapping(),
        };
    }

    /// return a new interval with bounds trimmed in the input space to the
    /// target interval
    pub fn shrink_to_input_interval(
        self: @This(),
        allocator: std.mem.Allocator,
        target_input_interval: opentime.ContinuousInterval,
    ) !?Mapping
    {
        return switch (self) {
            inline else => |contained| (
                try contained.shrink_to_input_interval(
                    allocator,
                    target_input_interval
                )
            ),
        };
    }

    /// return a new interval with bounds trimmed in the input space to the
    /// target interval
    pub fn shrink_to_output_interval(
        self: @This(),
        allocator: std.mem.Allocator,
        target_output_interval: opentime.ContinuousInterval,
    ) !?Mapping
    {
        return switch (self) {
            inline else => |contained| (
                (
                 try (
                     contained.shrink_to_output_interval(
                         allocator,
                         target_output_interval
                     ) 
                 )
                ) orelse return null
            )
        };
    }

    /// split the mapping at the point in its input space, assumes that a
    /// bounds check has already been made.  will return an error if the split
    /// point is invalid
    pub fn split_at_input_ord(
        self: @This(),
        allocator: std.mem.Allocator,
        pt_input: opentime.Ordinate,
    ) ![2]Mapping
    {
        return switch (self) {
            inline else => |m| try m.split_at_input_ord(allocator, pt_input),
        };
    }

    /// split the mapping at the point in its input space, assumes that a
    /// bounds check has already been made.  will return an error if the split
    /// point is invalid
    pub fn split_at_each_input_ord(
        self: @This(),
        allocator: std.mem.Allocator,
        input_ordinates: []const opentime.Ordinate,
    ) ![]const Mapping
    {
        return switch (self) {
            .empty => try allocator.dupe(Mapping, &.{ self }),
            inline else => |m| try m.split_at_each_input_ord(
                allocator, 
                input_ordinates,
            ),
        };
    }

    /// Split the mapping at each point in output space.
    pub fn split_at_output_points(
        self: @This(),
        allocator: std.mem.Allocator,
        output_points: []const opentime.Ordinate,
    ) ![]const Mapping
    {
        var result_mappings = (
            std.ArrayList(Mapping).init(allocator)
        );

        if (self == .empty) {
            try result_mappings.append(self);
            return result_mappings.toOwnedSlice();
        }

        // project all the points back to input points
        var input_points = (
            std.ArrayList(opentime.Ordinate).init(allocator)
        );
        try input_points.ensureTotalCapacity(output_points.len);
        defer input_points.deinit();

        const out_bounds = self.output_bounds();

        for (output_points)
            |o_p|
        {
            if (out_bounds.overlaps(o_p))
            {
                input_points.appendAssumeCapacity(
                    try self.project_instantaneous_cc_inv(o_p)
                );
            }
        }

        return self.split_at_each_input_ord(
            allocator,
            input_points.items,
        );
    }

    /// Formatter function for `std.Io.Writer`.
    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) !void 
    {
        try writer.print(
            "Mapping {s} mapping space {?f} to {?f}",
            .{
                @tagName(self),
                self.input_bounds(),
                self.output_bounds(),
            },
        );
    }

    /// Return an self inverted.  Caller owns the memory.
    pub fn inverted(
        self: @This(),
        allocator: std.mem.Allocator,
    ) !Mapping
    {
        switch (self) {
            .empty => |empty| return (
                empty.clone()
            ).mapping(),
            .affine => |aff| return .{
                .affine = .{
                    .input_bounds_val = (
                        aff.output_bounds()
                    ),
                    .input_to_output_xform = (
                        aff.input_to_output_xform.inverted()
                    ),
                },
            },
            .linear => |lin| return .{
                .linear = .{
                    .input_to_output_curve = (
                        try curve.linear.inverted_linear(
                            allocator,
                           lin.input_to_output_curve
                        )
                    ),
                },
            },
        }
    }

    // @{ Errors
    pub const ProjectionError = error { OutOfBounds };
    // @}
};

/// Produce test structures at comptime
pub fn test_structs(
    int: opentime.ContinuousInterval_BaseType,
) type
{
    return struct {
        pub const START_PT = curve.ControlPoint.init(
            .{ .in = int.start, .out = int.start, }
        );
        pub const END_PT = curve.ControlPoint.init(
            .{ .in = int.end, .out = int.end * 4, }
        );
        pub const CENTER_PT = (
            opentime.lerp(0.5, START_PT, END_PT)
        );

        pub const INT = (
            opentime.ContinuousInterval.init(int)
        );

        // mappings and (simple) topologies
        pub const AFF = mapping_affine.MappingAffine {
            .input_bounds_val = INT,
            .input_to_output_xform = .{
                .offset = opentime.Ordinate.init(4),
                .scale = opentime.Ordinate.init(2),
            },
        };

        pub const LIN = mapping_curve_linear.MappingCurveLinearMonotonic {
            .input_to_output_curve = .{
                .knots = &.{
                    START_PT,
                    END_PT, 
                },
            },
        };
    };
}

pub const LEFT = test_structs(
    .{
        .start = -2,
        .end = 2,
    }
);
pub const MIDDLE = test_structs(
    .{
        .start = 0,
        .end = 10,
    }
);
pub const RIGHT = test_structs(
    .{
        .start = 8,
        .end = 12,
    }
);

// Join Functions
//
// These functions are all of the form:
// fn (
//   [allocator]
//   args: struct {
//     .a2b: MappingSubType,
//     .b2c: MappingSubType,
//   }
// ) MappingSubType
//
// The intent is to use the join() function in the interface
///////////////////////////////////////////////////////////////////////////////

pub fn join_aff_aff(
    args: struct{
        a2b: mapping_affine.MappingAffine,
        b2c: mapping_affine.MappingAffine,
    },
) mapping_affine.MappingAffine
{
    const result= MappingAffine{
        .input_to_output_xform = (
            args.b2c.input_to_output_xform.applied_to_transform(
                args.a2b.input_to_output_xform,
            )
        ),
        .input_bounds_val = args.a2b.input_bounds(),
    };

    return result;
}

test "Mapping: join_aff_aff"
{
    // because of the boundary condition, this should return empty
    // @TODO: enforce the boundary condition!
    const left_right = try join(
        std.testing.allocator,
        .{
            .a2b = LEFT.AFF.mapping(),
            .b2c = RIGHT.AFF.mapping(),
        },
    );
    try std.testing.expectEqual(
        .empty,
        std.meta.activeTag(left_right),
    );
}

pub fn join_aff_lin(
    allocator: std.mem.Allocator,
    args: struct{
        a2b: mapping_affine.MappingAffine,
        b2c: mapping_curve_linear.MappingCurveLinearMonotonic,
    },
) !mapping_curve_linear.MappingCurveLinearMonotonic
{
    const a2b_input_bounds = args.a2b.input_bounds();
    const a2b_output_bounds = args.a2b.input_bounds();
    const a2b_linearized = (
        mapping_curve_linear.MappingCurveLinearMonotonic{
            .input_to_output_curve = .{
                .knots = &.{
                    .{ 
                        .in = a2b_input_bounds.start,
                        .out = a2b_output_bounds.start,
                    },
                    .{ 
                        .in = a2b_input_bounds.end,
                        .out = a2b_output_bounds.end,
                    },
                },
            },
        }
    );

    return join_lin_lin(
        allocator,
        .{
            .a2b = a2b_linearized,
            .b2c = args.b2c,
        },
    );
}

pub fn join_lin_aff(
    allocator: std.mem.Allocator,
    args: struct{
        a2b: mapping_curve_linear.MappingCurveLinearMonotonic,
        b2c: mapping_affine.MappingAffine,
    },
) !mapping_curve_linear.MappingCurveLinearMonotonic
{
    const a2c_knots = (
        try allocator.dupe(
            curve.ControlPoint,
            args.a2b.input_to_output_curve.knots,
        )
    );
    errdefer allocator.free(a2c_knots);

    for (a2c_knots)
        |*k|
    {
        k.*.out = try args.b2c.project_instantaneous_cc(k.out).ordinate();
    }

    return mapping_curve_linear.MappingCurveLinearMonotonic{
        .input_to_output_curve =  .{
            .knots = a2c_knots,
        },
    };
}

pub fn join_lin_lin(
    allocator: std.mem.Allocator,
    args: struct{
        a2b: mapping_curve_linear.MappingCurveLinearMonotonic,
        b2c: mapping_curve_linear.MappingCurveLinearMonotonic,
    },
) !mapping_curve_linear.MappingCurveLinearMonotonic
{
    return .{
        .input_to_output_curve = try curve.join(
            allocator,
            .{
                .a2b = args.a2b.input_to_output_curve,
                .b2c = args.b2c.input_to_output_curve,
            },
        )
    };
}

/// Given two mappings, one that maps from space a->space b and a second that
/// maps from space b to space c, joins two mappings via their common
/// coordinate system (Referred to in the arguments as "b"), and computes the
/// mapping from space a->space c.
///
/// Does not transform the mappings prior to joining, and the computation
/// happens over the intersection of their domains within the common coordinate
/// system (b).
///
/// Handles the type mapping:
///
/// ```
///     .    a2b ->
/// b2c v  | empty | affine | linear | bezier |
/// -------|-------|--------|--------|--------|
/// empty  | empty | empty  | empty  | empty  | 
/// affine | empty | affine | linear | linear |
/// linear | empty | linear | linear | linear |
/// bezier | empty | linear | linear | linear |
/// -------|-------|--------|--------|--------|
/// ```
///
/// (return value is always a `Mapping`)
///
pub fn join(
    allocator: std.mem.Allocator,
    mappings: struct{
        a2b: Mapping,
        b2c: Mapping,
    },
) !Mapping
{
    var a2b: Mapping = mappings.a2b;
    var b2c: Mapping = mappings.b2c;

    const empty_result = (
        MappingEmpty{
            .defined_range = (
                a2b.input_bounds() 
                orelse return error.InvalidMapping
            )
        }
    ).mapping();

    // joining anything with an empty results in an empty
    if (a2b == .empty or b2c == .empty) {
        return empty_result;
    }

    // manage the boundary conditions
    const a2b_b_bounds = a2b.output_bounds().?;
    const b2c_b_bounds = (
        b2c.input_bounds() 
        orelse return empty_result
    );

    const maybe_b_bounds_intersection = (
        opentime.interval.intersect(
            a2b_b_bounds,
            b2c_b_bounds,
        )
    );

    const b_bounds_intersection = (
        // if there is no intersection, the result is empty
        maybe_b_bounds_intersection orelse {
            return empty_result;
        }
    );

    // trimmed and linearized
    const a2b_trimmed = (
        try (
            a2b.shrink_to_output_interval(
                allocator,
                b_bounds_intersection,

            )
        ) orelse return empty_result
    );
    defer a2b_trimmed.deinit(allocator);

    // already checked that there is an intersection, would have caught the
    // invalid bounds
    const b2c_trimmed = (
        try b2c.shrink_to_input_interval(
            allocator,
            b_bounds_intersection,
        )
    ).?;
    defer b2c_trimmed.deinit(allocator);

    return switch (b2c_trimmed) {
        .affine => |b2c_aff| switch (a2b_trimmed) {
            .affine => |a2b_aff| join_aff_aff(
                .{
                    .a2b = a2b_aff, 
                    .b2c = b2c_aff, 
                },
            ).mapping(),
            .linear => |a2b_lin| (
                try join_lin_aff(
                    allocator,
                    .{ 
                        .a2b = a2b_lin,
                        .b2c = b2c_aff 
                    }
                )
            ).mapping(),
            inline else => unreachable,
        },
        .linear => |b2c_lin| switch (a2b_trimmed) {
            .affine => |a2b_aff| ( 
                try join_aff_lin(
                    allocator,
                    .{
                        .a2b = a2b_aff,
                        .b2c = b2c_lin, 
                    },
                )
            ).mapping(),
            .linear => |a2b_lin| (
                try join_lin_lin(
                    allocator,
                    .{ 
                        .a2b = a2b_lin,
                        .b2c = b2c_lin
                    },
                )
            ).mapping(),
            inline else => unreachable,
        },
        inline else => unreachable,
    };
}

test "Mapping: join aff/aff"
{
    const allocator = std.testing.allocator;

    const aff = (
        MappingAffine{
            .input_bounds_val = (
                opentime.ContinuousInterval.init(
                    .{ .start = 0, .end = 8, },
                )
            ),
            .input_to_output_xform = .{
                .offset = .one,
                .scale = .one,
            },
        }
    );

    const result = try join(
        allocator,
        .{
            .a2b = .identity_infinite,
            .b2c = aff.mapping(),
        },
    );

    try opentime.expectOrdinateEqual(
        4,
        aff.project_instantaneous_cc(opentime.Ordinate.init(3)).ordinate(),
    );
    try opentime.expectOrdinateEqual(
        4,
        result.project_instantaneous_cc(opentime.Ordinate.init(3)).ordinate(),
    );

    const ib = (
        result.input_bounds() 
        orelse return error.InvalidBounds
    );
    try opentime.expectOrdinateEqual(
        aff.input_bounds().start,
        ib.start,
    );
    try opentime.expectOrdinateEqual(
        aff.input_bounds().end,
        ib.end,
    );

    const ob = (
        result.output_bounds()
        orelse return error.InvalidBounds
    );
    try opentime.expectOrdinateEqual(
        aff.output_bounds().start,
        ob.start,
    );
    try opentime.expectOrdinateEqual(
        aff.output_bounds().end,
        ob.end,
    );

    try std.testing.expectEqual(
        .affine,
        std.meta.activeTag(result)
    );
}
