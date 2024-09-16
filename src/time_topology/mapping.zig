//! Mapping / OpenTimelineIO
//!
//! Functions and structs related to the Mapping component of OTIO.

const std = @import("std");

const opentime = @import("opentime");
const serialization = @import("serialization.zig");

const mapping_empty = @import("mapping_empty.zig");
pub const MappingEmpty = mapping_empty.MappingEmpty;
pub const EMPTY = mapping_empty.EMPTY;

const mapping_affine = @import("mapping_affine.zig");
pub const MappingAffine = mapping_affine.MappingAffine;
pub const INFINITE_IDENTIY = mapping_affine.INFINITE_IDENTIY;

const mapping_curve_linear = @import("mapping_curve_linear.zig");
pub const MappingCurveLinear = mapping_curve_linear.MappingCurveLinear;

const mapping_curve_bezier = @import("mapping_curve_bezier.zig");
pub const MappingCurveBezier = mapping_curve_bezier.MappingCurveBezier;

const curve = @import("curve");

/// A Mapping is a polymorphic container for a function that maps from an
/// "input" space to an "output" space.  Mappings can be joined with other
/// mappings via function composition to build new transformations via common
/// spaces. Mappings can project ordinates and ranges from their input space
/// to their output space.  Some (but not all) mappings are also invertible.
pub const Mapping = union (enum) {
    empty: mapping_empty.MappingEmpty,
    affine: mapping_affine.MappingAffine,
    linear: mapping_curve_linear.MappingCurveLinear,
    bezier: mapping_curve_bezier.MappingCurveBezier,

    pub fn deinit(
        self: @This(),
        allocator: std.mem.Allocator,
    ) void
    {
        return switch (self) {
            .empty, .affine => {},
            inline else => |m| m.deinit(allocator),
        };
    }

    /// project an instantaneous ordinate from the input space to the output
    /// space
    pub fn project_instantaneous_cc(
        self: @This(),
        ord: opentime.Ordinate,
    ) !opentime.Ordinate 
    {
        return switch (self) {
            inline else => |m| m.project_instantaneous_cc(ord),
        };
    }

    /// fetch (computing if necessary) the input bounds of the mapping
    pub fn input_bounds(
        self: @This(),
    ) opentime.ContinuousTimeInterval
    {
        return switch (self) {
            inline else => |contained| contained.input_bounds(),
        };
    }

    /// fetch (computing if necessary) the output bounds of the mapping
    pub fn output_bounds(
        self: @This(),
    ) opentime.ContinuousTimeInterval
    {
        return switch (self) {
            inline else => |contained| contained.output_bounds(),
        };
    }

    /// Make a copy of this Mapping
    pub fn clone(
        self: @This(),
    ) !Mapping
    {
        return switch (self) {
            inline else => |contained| contained.clone().mapping(),
        };
    }

    // @{ Errors
    pub const ProjectionError = error { OutOfBounds };
    // @}
};

/// A Topology binds regions of a one dimensional space to a sequence of right
/// met mappings, separated by a list of end points.  There are implicit
/// "Empty" mappings outside of the end points which map to no values before
/// and after the segments defined by the Topology.
pub const TopologyMapping = struct {
    end_points_input: []const opentime.Ordinate,
    mappings: []const Mapping,

    pub fn end_points_output(
        self: @This(),
        allocator: std.mem.Allocator,
    ) []const opentime.Ordinate
    {
        var pts_output_space = try allocator.dupe(
            opentime.Ordinate,
            self.end_points_input
        );
    }
};

/// build a topological mapping from a to c
pub fn join_t(
    allocator: std.mem.Allocator,
    args: struct{
        a2b: TopologyMapping,
        b2c: TopologyMapping,
    },
) TopologyMapping
{
    const a2b_b_bounds = a2b.end_points_output(allocator);
}

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

/// Produce test structures at comptime
fn test_structs(
    int: opentime.ContinuousTimeInterval,
) type
{
    return struct {
        pub const START_PT = curve.ControlPoint{
            .{
                .in = int.start_seconds,
                .out = int.start_seconds,
            },
        };
        pub const END_PT = curve.ControlPoint{
            .in = int.end_seconds,
            .out = int.end_seconds * 4,
        };
        pub const CENTER_PT = (
            END_PT.sub(START_PT).div(2)
        );

        pub const INT = int;
        pub const AFF = mapping_affine.MappingAffine {
            .input_bounds_val = int,
            .input_to_output_xform = .{
                .offset_seconds = 4,
                .scale = 2,
            },
        };
        pub const LIN = mapping_curve_linear.MappingCurveLinear {
            .input_to_output_curve = .{
                .knots = &.{ .{ START_PT, END_PT, }, },
            },
        };
        pub const BEZ = mapping_curve_bezier.MappingCurveBezier {
            .input_to_output_curve = .{
                .segments = &.{
                    .{
                        curve.Bezier.Segment.init_from_start_end(
                            START_PT,
                            END_PT
                        )
                    }
                },
            },
        };
    };
}

const LEFT = test_structs(
    .{
        .start_seconds = -2,
        .end_seconds = 2,
    }
);
const MIDDLE = test_structs(
    .{
        .start_seconds = 0,
        .end_seconds = 10,
    }
);
const RIGHT = test_structs(
    .{
        .start_seconds = 8,
        .end_seconds = 12,
    }
);

pub fn join_aff_aff(
    args: struct{
        a2b: mapping_affine.MappingAffine,
        b2c: mapping_affine.MappingAffine,
    },
) mapping_affine.MappingAffine
{
    return .{
        .input_to_output_xform = (
            args.b2c.input_to_output_xform.applied_to_transform(
                args.a2b.input_to_output_xform,
            )
        ),
    };
}

test "join_aff_aff"
{
    // because of the boundary condition, this should return empty
    // @TODO: enforce the boundary condition!
    const left_right = join_aff_aff(
        .{
            .a2b = LEFT.AFF,
            .b2c = RIGHT.AFF,
        },
    ).mapping();
    try std.testing.expectEqual(
        .empty,
        std.meta.activeTag(left_right),
    );
}

pub fn join_aff_lin(
    allocator: std.mem.Allocator,
    args: struct{
        a2b: mapping_affine.MappingAffine,
        b2c: mapping_curve_linear.MappingCurveLinear,
    },
) !mapping_curve_linear.MappingCurveLinear
{
    return .{
        .input_to_output_curve = (
            try args.b2c.input_to_output_curve.project_affine(
                allocator,
                args.a2b.input_to_output_xform,
                args.a2b.input_bounds_val,
            )
        ),
    };
}

pub fn join_lin_aff(
    allocator: std.mem.Allocator,
    args: struct{
        a2b: mapping_curve_linear.MappingCurveLinear,
        b2c: mapping_affine.MappingAffine,
    },
) !mapping_curve_linear.MappingCurveLinear
{
    const a2c_curve = (
        try args.a2b.input_to_output_curve.clone(allocator)
    );

    for (a2c_curve.knots)
        |*k|
    {
        k.*.out = try args.b2c.project_instantaneous_cc(k.out);
    }

    return .{
        .input_to_output_curve =  a2c_curve,
    };
}

pub fn join_aff_bez(
    allocator: std.mem.Allocator,
    args: struct{
        a2b: mapping_affine.MappingAffine,
        b2c: mapping_curve_bezier.MappingCurveBezier,
    },
) !mapping_curve_bezier.MappingCurveBezier
{
    return .{
        .input_to_output_curve = (
            try args.b2c.input_to_output_curve.project_affine(
                allocator,
                args.a2b.input_to_output_xform,
            )
        ),
    };
}

pub fn join_bez_aff(
    allocator: std.mem.Allocator,
    args: struct{
        a2b: mapping_curve_bezier.MappingCurveBezier,
        b2c: mapping_affine.MappingAffine,
    },
) !mapping_curve_bezier.MappingCurveBezier
{
    const a2c_crv = try args.a2b.input_to_output_curve.clone(allocator);

    const b2a = try curve.inverted(
        allocator,
        args.a2b.input_to_output_curve
    );

    const b_bounds = args.b2c.input_bounds();

    const bounds_in_a:opentime.ContinuousTimeInterval = .{
        .start_seconds = try b2a.output_at_input(
            b_bounds.start_seconds
        ),
        .end_seconds =  try b2a.output_at_input(
            b_bounds.end_seconds,
        ),
    };

    const a2c_trimmed = try a2c_crv.trimmed_in_input_space(
        allocator,
        bounds_in_a
    );


    return .{
        .input_to_output_curve = try curve.join_bez_aff_unbounded(
            allocator,
             .{ 
                .a2b = a2c_trimmed,
                .b2c = args.b2c.input_to_output_xform,
            },
        ),
    };
}

pub fn join_lin_lin(
    allocator: std.mem.Allocator,
    args: struct{
        a2b: mapping_curve_linear.MappingCurveLinear,
        b2c: mapping_curve_linear.MappingCurveLinear,
    },
) !mapping_curve_linear.MappingCurveLinear
{
    return .{
        .input_to_output_curve = (
            (
             try args.b2c.input_to_output_curve.project_curve(
                 allocator,
                 args.a2b.input_to_output_curve
             )
            )[0]
        )
    };
}

pub fn join_bez_lin(
    allocator: std.mem.Allocator,
    args: struct{
        a2b: mapping_curve_bezier.MappingCurveBezier,
        b2c: mapping_curve_linear.MappingCurveLinear,
    },
) !mapping_curve_linear.MappingCurveLinear
{
    // @TOOD: promote the linearization to the Mapping
    const a2b_lin = mapping_curve_linear.MappingCurveLinear{
        .input_to_output_curve =  (
            try args.a2b.input_to_output_curve.linearized(allocator)
        ),
    };

    return join_lin_lin(
        allocator,
        .{
            .a2b = a2b_lin,
            .b2c = args.b2c,
        }
    );
}

pub fn join_lin_bez(
    allocator: std.mem.Allocator,
    args: struct{
        a2b: mapping_curve_linear.MappingCurveLinear,
        b2c: mapping_curve_bezier.MappingCurveBezier,
    },
) !mapping_curve_linear.MappingCurveLinear
{
    const b2c_lin = mapping_curve_linear.MappingCurveLinear{
        .input_to_output_curve =  (
            try args.b2c.input_to_output_curve.linearized(allocator)
        ),
    };

    return join_lin_lin(
        allocator,
        .{
            .a2b = args.a2b,
            .b2c = b2c_lin,
        }
    );
}

pub fn join_bez_bez(
    allocator: std.mem.Allocator,
    args: struct{
        a2b: mapping_curve_bezier.MappingCurveBezier,
        b2c: mapping_curve_bezier.MappingCurveBezier,
    },
) !mapping_curve_linear.MappingCurveLinear
{
    const a2b_lin = try args.a2b.linearized(allocator);
    const b2c_lin = try args.b2c.linearized(allocator);

    return try join_lin_lin(
        allocator,
        .{
            .a2b = a2b_lin,
            .b2c = b2c_lin,
        }
    );
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
///     .    a2b ->
/// b2c v  | empty | affine | linear | bezier |
/// -------|-------|--------|--------|--------|
/// empty  | empty | empty  | empty  | empty  | 
/// affine | empty | affine | linear | bezier |
/// linear | empty | linear | linear | linear |
/// bezier | empty | bezier | linear | linear |
/// -------|-------|--------|--------|--------|
///
/// (return value is always a `Mapping`)
///
pub fn join(
    allocator: std.mem.Allocator,
    args: struct{
        a2b: Mapping,
        b2c: Mapping,
    },
) !Mapping
{
    const a2b = args.a2b;
    const b2c = args.b2c;

    if (a2b == .empty or b2c == .empty) {
        return mapping_empty.EMPTY;
    }

    return switch (b2c) {
        .affine => |b2c_aff| switch (a2b) {
            .affine => |a2b_aff| join_aff_aff(
                .{ .a2b = a2b_aff, .b2c = b2c_aff, },
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
            .bezier => |a2b_bez| (
                try join_bez_aff(
                    allocator,
                    .{ .a2b = a2b_bez, .b2c = b2c_aff }
                )
            ).mapping(),
            .empty => mapping_empty.EMPTY,
        },
        .linear => |b2c_lin| switch (a2b) {
            .affine => |a2b_aff| ( 
                try join_aff_lin(
                    allocator,
                    .{ .a2b = a2b_aff, .b2c = b2c_lin, },
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
            .bezier => |a2b_bez| (
                try join_bez_lin(
                    allocator,
                    .{ .a2b = a2b_bez, .b2c = b2c_lin }
                )
            ).mapping(),
            .empty => mapping_empty.EMPTY,
        },
        .bezier => |b2c_bez| switch (a2b) {
            .affine => |a2b_aff| (
                try join_aff_bez(
                allocator,
                .{
                    .a2b = a2b_aff,
                    .b2c = b2c_bez, 
                },
                )
            ).mapping(),
            .linear => |a2b_lin| (
                try join_lin_bez(
                    allocator,
                    .{ 
                        .a2b = a2b_lin,
                        .b2c = b2c_bez 
                    }
                )
            ).mapping(),
            .bezier => |a2b_bez| (
                try join_bez_bez(
                    allocator,
                    .{
                        .a2b = a2b_bez,
                        .b2c = b2c_bez 
                    }
                )
            ).mapping(),
            .empty => mapping_empty.EMPTY,
        },
        .empty => mapping_empty.EMPTY,
    };
}
