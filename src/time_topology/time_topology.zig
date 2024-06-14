const std = @import("std"); 

const opentime = @import("opentime"); 
const interval = opentime.interval;
const transform = opentime.transform;
const sample_lib = opentime.sample;
const Sample = sample_lib.Sample; 
const util = opentime.util;

const curve = @import("curve"); 
const control_point = curve.control_point; 

const otio_allocator = @import("otio_allocator"); 
const ALLOCATOR = otio_allocator.ALLOCATOR;


// assertions
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;
const expectApproxEqAbs = std.testing.expectApproxEqAbs;

pub const Ordinate = f32;

const IDENTITY_TRANSFORM = transform.AffineTransform1D{
    .offset_seconds = 0,
    .scale = 1,
};


pub const AffineTopology = struct {
    // defaults to an infinite identity
    bounds: interval.ContinuousTimeInterval = interval.INF_CTI,
    transform: transform.AffineTransform1D =IDENTITY_TRANSFORM, 

    pub fn compute_bounds(self: @This()) interval.ContinuousTimeInterval {
        return self.bounds;
    }

    pub fn as_linear_curve_over_output_range(
        self: @This(),
        output_interval: interval.ContinuousTimeInterval
    ) !curve.TimeCurveLinear 
    {
        const self_inverted = self.transform.inverted();

        const other_bounds_in_input_space = self_inverted.applied_to_bounds(
            output_interval
        );

        const result_bounds = interval.intersect(
            other_bounds_in_input_space,
            self.bounds
        );

        if (result_bounds) |b| 
        {
            const bound_points = [2]control_point.ControlPoint{
                .{
                    .time = b.start_seconds,
                    .value = try self.project_ordinate(b.start_seconds) 
                },
                .{ 
                    .time = b.end_seconds,
                    .value = try self.project_ordinate(b.end_seconds) 
                },
            };

            return curve.TimeCurveLinear.init(&bound_points);
        } else {
            return curve.TimeCurveLinear.init(&[_]control_point.ControlPoint{});
        }
    }

    pub fn project_sample(self: @This(), sample: Sample) !Sample {
        var result = sample;
        result.ordinate_seconds = try self.project_ordinate(
            sample.ordinate_seconds
        );
        return result;
    }

    pub fn project_ordinate(self: @This(), ordinate: Ordinate) !Ordinate {
        if (!self.bounds.overlaps_seconds(ordinate)) {
            return TimeTopology.ProjectionError.OutOfBounds;
        }

        return self.transform.applied_to_seconds(ordinate);
    }

    pub fn inverted(
        self: @This(),
    ) !TimeTopology 
    {
        var start = self.bounds.start_seconds;
        if (start != interval.INF_CTI.start_seconds) {
            start = try self.project_ordinate(start);
        }
        var end = self.bounds.end_seconds;
        if (end != interval.INF_CTI.end_seconds) {
            end = self.transform.applied_to_seconds(end);
        }

        if (start > end) {
            const tmp = start;
            start = end;
            end = tmp;
        }

        return .{
            .affine = .{
                .bounds = .{ .start_seconds = start, .end_seconds = end },
                .transform = self.transform.inverted()
            },
        };
    }

    /// project a topology through self (affine transform)
    ///
    /// -> means "is projected through"
    /// A->B (bounds are in A)
    /// B->C (bounds are in B)
    /// B->C.project(A->B) => A->C, bounds are in A
    ///
    /// self: self.input -> self.output
    /// other:other.input -> other.output
    ///
    /// self.project_topology(other) => other.input -> self.output
    /// result.bounds -> other.input
    ///
    pub fn project_topology(self: @This(), other: TimeTopology) !TimeTopology {
        return switch (other) {
            .bezier_curve => |other_bez| .{ 
                .bezier_curve = .{
                    .curve = try curve.affine_project_curve(
                        self.transform,
                        other_bez.curve,
                        otio_allocator.ALLOCATOR
                    )
                }
            },
           .linear_curve => |lin| {
               var result = try curve.TimeCurveLinear.init(
                   otio_allocator.ALLOCATOR,
                   lin.curve.knots,
               );
               for (lin.curve.knots, 0..) |knot, knot_index| {
                    result.knots[knot_index] = .{
                        .time = knot.time,
                        .value = self.transform.applied_to_seconds(knot.value),
                    };
               }
               return .{ .linear_curve = .{ .curve = result }};
           },
           .affine => |other_aff| {
               const inv_xform = other_aff.transform.inverted();

               const self_bounds_in_input_space = (
                   inv_xform.applied_to_bounds(self.bounds)
               );

               const bounds = interval.intersect(
                   self_bounds_in_input_space,
                   other_aff.bounds,
               );

               if (bounds) |b| {
                   return .{
                       .affine = .{ 
                           .bounds = b,
                           .transform = (
                               self.transform.applied_to_transform(
                                   other_aff.transform
                               )
                           )
                       },
                   };
               }
               else {
                   return .{ .empty = .{} };
               }
           },
           .empty => .{ .empty = .{} },
        };
    }
};

pub const LinearTopology = struct {
    curve: curve.TimeCurveLinear,
    
    pub fn deinit(self: @This(), allocator: std.mem.Allocator) void {
        self.curve.deinit(allocator);
    }

    pub fn compute_bounds(self: @This()) interval.ContinuousTimeInterval {
        const extents = self.curve.extents();

        return .{
            .start_seconds = extents[0].time,
            .end_seconds = extents[1].time,
        };
    }

    pub fn project_sample(self: @This(), sample: Sample) !Sample {
        var result = sample;
        result.ordinate_seconds = try self.project_ordinate(
            sample.ordinate_seconds
        );
        return result;
    }

    pub fn project_ordinate(self: @This(), ordinate: Ordinate) !Ordinate {
        return self.curve.evaluate(ordinate);
    }

    pub fn inverted(
        self: @This(),
        allocator: std.mem.Allocator,
    ) !TimeTopology 
    {
        const result = TimeTopology{
            .linear_curve = .{
                .curve = try curve.inverted_linear(
                    allocator,
                    self.curve
                )
            }
        };
        return result;
    }

    // @TODO: needs to return a list of topologies (imagine a line projected
    //        through a u)
    pub fn project_topology(
        self: @This(),
        other: TimeTopology,
        // @TODO: should fill a list of TimeTopology
        // out: *std.ArrayList(TimeTopology),
    ) !TimeTopology 
    {
        return switch (other) {
            .affine => |aff| {
                const projected_curve = try self.curve.project_affine(
                    aff.transform,
                    otio_allocator.ALLOCATOR
                );

                return .{
                    .linear_curve = .{ .curve = projected_curve }
                };
            },
            .bezier_curve => |bez| .{
                .linear_curve = .{
                    .curve = (
                        try self.curve.project_curve(
                            ALLOCATOR,
                            try bez.curve.linearized(
                                ALLOCATOR
                            )
                        )
                    )[0]
                }
            },
            .linear_curve => |lin| .{
                .linear_curve = .{ 
                    .curve = (
                        try self.curve.project_curve(
                            ALLOCATOR,
                            lin.curve
                        )
                    )[0] 
                }
            },
            .empty => .{ .empty = EmptyTopology{} },
        };
    }
};

test "LinearTopology: invert" {
    const crv = try curve.TimeCurveLinear.init(
        std.testing.allocator,
        &.{ 
            .{ .time = 0, .value = 10 },
            .{ .time = 10, .value = 20 },
        },
    );
    defer crv.deinit(std.testing.allocator);
    const topo = TimeTopology{
        .linear_curve = .{ .curve = crv }
    };

    const topo_bounds = topo.bounds();
    try expectEqual(0, topo_bounds.start_seconds);
    try expectEqual(10, topo_bounds.end_seconds);

    const topo_inv = try topo.inverted(std.testing.allocator);
    defer topo_inv.deinit(std.testing.allocator);
    const topo_inv_bounds = topo_inv.bounds();
    try expectEqual(10, topo_inv_bounds.start_seconds);
    try expectEqual(20, topo_inv_bounds.end_seconds);

}

pub const BezierTopology = struct {
    curve: curve.TimeCurve,

    pub fn deinit(self: @This(), allocator: std.mem.Allocator) void {
        self.curve.deinit(allocator);
    }

    pub fn compute_bounds(self: @This()) interval.ContinuousTimeInterval {
        const extents = self.curve.extents();

        return .{
            .start_seconds = extents[0].time,
            .end_seconds = extents[1].time,
        };
    }

    pub fn project_sample(self: @This(), sample: Sample) !Sample {
        var result = sample;
        result.ordinate_seconds = try self.project_ordinate(
            sample.ordinate_seconds
        );
        return result;
    }

    pub fn project_ordinate(self: @This(), ordinate: Ordinate) !Ordinate {
        return self.curve.evaluate(ordinate);
    }

    pub fn inverted(
        self: @This(),
        allocator: std.mem.Allocator
    ) !TimeTopology 
    {
         return TimeTopology{
            .linear_curve = .{ 
                .curve = try curve.inverted(
                    allocator,
                    self.curve
                ) 
            }
        };
    }

    // pub fn project_topology(
    //     self: @This(),
    //     other: TimeTopology
    // ) TimeTopology 
    // {
    //     if (other.kind == Kind.empty) {
    //         // if other is empty, it doesn't matter what self is, the result is
    //         // an empty topology
    //         return other;
    //     }
    //
    //     if (self.kind == Kind.empty) {
    //         return .{ .kind = Kind.empty };
    //     }
    //
    //     if (self.kind == Kind.infinite_identity) {
    //         return other;
    //     }
    //
    //     // if (self.kind == Kind.finite) 
    //     const other_wrapped = (
    //         if (other.kind == Kind.infinite_identity) (
    //             TimeTopology.init_identity_finite(self.bounds)
    //         ) else (
    //             other
    //         )
    //     );
    //
    //     var result = (
    //         std.ArrayList(curve.TimeCurve).init(allocator.ALLOCATOR)
    //     );
    //
    //     // @TODO: these curves need to have their respective
    //     //        transformations applied (if we stick with that model)
    //     for (other_wrapped.mapping) 
    //         |other_crv|
    //     {
    //         for (self.mapping) 
    //             |self_crv|
    //         {
    //             const resulting_curves = (
    //                 self_crv.project_curve(other_crv)
    //             );
    //             for (resulting_curves) 
    //                 |crv| 
    //             {
    //                 result.append(
    //                     curve.TimeCurve.init_from_linear_curve(crv)
    //                 ) catch unreachable;
    //             }
    //         }
    //     }
    //
    //     const result_bounds = interval.intersect(
    //         self.bounds,
    //         other_wrapped.bounds
    //     ) orelse interval.ContinuousTimeInterval{};
    //
    //     return .{
    //         .transform = .{
    //             .offset_seconds = result_bounds.start_seconds,
    //             .scale = 1
    //         },
    //         .bounds = result_bounds,
    //         .mapping = result.items,
    //         // if its finite, even if other has no segments, is empty
    //         .kind = Kind.finite,
    //     };
    // }

    // @TODO: needs to return a list of topologies (imagine a line projected
    //        through a u)
    pub fn project_topology(
        self: @This(),
        other: TimeTopology,
        // @TODO: should fill a list of TimeTopology
        // out: *std.ArrayList(TimeTopology),
    ) !TimeTopology 
    {
        return switch (other) {
            .affine => |aff| {
                const projected_curve = try self.curve.project_affine(
                    aff.transform,
                    otio_allocator.ALLOCATOR
                );

                return .{
                    .bezier_curve = .{ .curve = projected_curve }
                };
            },
            .bezier_curve => |bez| switch (curve.bezier_curve.project_algo) {
                .three_point_approx, .two_point_approx => .{
                    .bezier_curve = .{
                        .curve = try self.curve.project_curve(
                            ALLOCATOR,
                            bez.curve
                        )
                    }
                },
                .linearized => .{ 
                    .linear_curve = .{
                        .curve = (
                            try (
                             try self.curve.linearized(
                                 ALLOCATOR
                             )
                            ).project_curve(
                            ALLOCATOR,
                            try bez.curve.linearized(ALLOCATOR),
                            )
                        )[0]
                    }
                },
            },
            .linear_curve => |lin| .{
                .linear_curve = .{
                    .curve = (
                        try (
                            try self.curve.linearized(
                                ALLOCATOR
                            )
                        ).project_curve(
                        ALLOCATOR,
                        lin.curve,
                        )
                    )[0]
                }
            },
            .empty => .{ .empty = EmptyTopology{} },
        };
    }
};

test "BezierTopology: inverted" {
    const base_curve = try curve.read_curve_json(
        "curves/scurve.curve.json",
        std.testing.allocator,
    );
    defer base_curve.deinit(std.testing.allocator);

    // this curve is [-0.5, 0.5), rescale it into test range
    const xform_curve = try curve.rescaled_curve(
        std.testing.allocator,
        base_curve,
        //  the range of the clip for testing - rescale factors
        .{
            .{ .time = 100, .value = 0, },
            .{ .time = 110, .value = 10, },
        }
    );
    defer xform_curve.deinit(std.testing.allocator);
    const curve_topo = TimeTopology.init_bezier_cubic(
        xform_curve
    );
    const curve_topo_bounds = curve_topo.bounds();
    try expectEqual(100, curve_topo_bounds.start_seconds);
    try expectEqual(110, curve_topo_bounds.end_seconds);
    
    const curve_topo_inverted = try curve_topo.inverted(
        std.testing.allocator
    );
    defer curve_topo_inverted.deinit(std.testing.allocator);
    const topo_inv_bounds = curve_topo_inverted.bounds();
    try expectEqual(0, topo_inv_bounds.start_seconds);
    try expectEqual(10, topo_inv_bounds.end_seconds);
}

pub const EmptyTopology = struct {
    pub fn project_ordinate(_: @This(), _: Ordinate) !Ordinate {
        return error.OutOfBounds;
    }
    pub fn inverted(_: @This()) !TimeTopology {
        return .{ .empty = .{} };
    }
    pub fn compute_bounds(_: @This()) interval.ContinuousTimeInterval {
        return .{ .start_seconds = 0, .end_seconds = 0 };
    }
    pub fn project_sample(_: @This(), _: Sample) !Sample {
        return error.OutOfBounds;
    }
};

// TEMPORAL TOPOLOGY PROTOTYPE V2
// ////////////////////////////////////////////////////////////////////////////
// The time topology maps an external temporal coordinate system to an internal
// one.  Coordinates in the external coordinate system can be projected through
// the topology to retrieve values in the internal coordinate system.
//
// The time toplogy is a right met piecewise-linear function.
//
//              0                 36          50 (duration of the bounds)
// output       |-----------------*-----------|
// internal     |-----------------*-----------|
//              100               176         200
//
// The implementation of this mapping function can be one of a class of 
// functions.  This struct maps those functions to the same interface and
// handles rules for interoperation between them.
// ////////////////////////////////////////////////////////////////////////////
pub const TimeTopology = union (enum) {
    affine: AffineTopology,
    empty: EmptyTopology,

    bezier_curve: BezierTopology,
    linear_curve: LinearTopology,

    // linear_holodrome_curve: curve.TimeCurveLinearHolodrome,
    // bezier_holodrome_curve: curve.TimeCurveBezierHolodrome,

    /// default to an infinite identity
    const IdentityArgs = struct {
        bounds: interval.ContinuousTimeInterval = interval.INF_CTI,
        transform: transform.AffineTransform1D = .{},
    };

    // @{ Initializers
    /// initialize an infinite identity topology
    pub fn init_identity_infinite() TimeTopology {
        return init_identity(.{});
    }

    ///initialize an identity topology
    pub fn init_identity(
        args: IdentityArgs,
    ) TimeTopology 
    {
        return .{ .affine = .{ .bounds = args.bounds } };
    }

    /// initialize an affine topology
    pub fn init_affine(topo: AffineTopology) TimeTopology {
        return .{ .affine = topo };
    }

    /// initialize a topology with a single linear curve over [start, end)
    pub fn init_linear_start_end(
        start:curve.ControlPoint,
        end: curve.ControlPoint
    ) TimeTopology 
    {
        const slope = (end.value - start.value) / (end.time - start.time);
        const offset = start.value - start.time * slope;
        return init_affine(
            .{
                .bounds = .{
                    .start_seconds = start.time,
                    .end_seconds = end.time 
                },
                .transform = .{
                    .scale = slope,
                    .offset_seconds = offset,
                }
            }
        );
    }
    
    /// initialize a topology with the given bezier cubic
    pub fn init_bezier_cubic(btc: curve.TimeCurve) TimeTopology {
        return .{.bezier_curve = .{.curve = btc}};
    }
    
    /// initialize an empty time topology
    pub fn init_empty() TimeTopology {
        return .{ .empty = EmptyTopology{} };
    }

    pub fn deinit(self: @This(), allocator: std.mem.Allocator) void {
        switch (self) {
            inline .affine, .empty => {},
            inline else => |t| t.deinit(allocator),
        }
    }

    // @TODO: should include a phase offset
    /// builds a TimeTopology out with a mapping that contains a step function
    pub fn init_step_mapping(
        in_bounds: interval.ContinuousTimeInterval,
        // the value of the function at the initial sample (f(0))
        start_value: f32,
        held_duration: f32,
        increment: f32,
    ) !TimeTopology
    {
        var segments = std.ArrayList(curve.Segment).init(otio_allocator.ALLOCATOR);
        var t_seconds = in_bounds.start_seconds;
        var current_value = start_value;
        while (t_seconds < in_bounds.end_seconds) {
            try segments.append(
                curve.create_linear_segment(
                    .{
                        .time = t_seconds,
                        .value = current_value
                    },
                    .{
                        .time = t_seconds + held_duration,
                        .value = current_value
                    }
                )
            );

            t_seconds += held_duration;
            current_value += increment;
        }

        const crv = curve.TimeCurve.init(ALLOCATOR, segments.items) catch curve.TimeCurve{};

        return TimeTopology.init_bezier_cubic(crv);
    }
    // @}

    /// the bounding interval of the topology in its input space
    pub fn bounds(self: @This()) interval.ContinuousTimeInterval {
        return switch (self) {
            inline else => |contained| contained.compute_bounds(),
        };
    }

    // @{ Projections
    pub fn project_sample(self: @This(), sample: Sample) !Sample {
        return switch (self) {
            inline else => |contained| contained.project_sample(sample),
        };
    }
    pub fn project_ordinate(self: @This(), ordinate:Ordinate) !Ordinate {
        return switch (self) {
            inline else => |contained| contained.project_ordinate(ordinate),
        };
    }

    /// topology interface for projection
    pub fn project_topology(
        self: @This(),
        other: TimeTopology
    ) !TimeTopology 
    {
        const self_tag_is_empty = std.meta.activeTag(self) == .empty;
        const other_tag_is_empty = std.meta.activeTag(other) == .empty;

        if (self_tag_is_empty or other_tag_is_empty) 
        {
            return .{ .empty = .{} };
        }

        return switch(self) {
            .empty => .{ .empty = .{} },
            inline else =>|v| v.project_topology(other),
        };
    }
    // @}
    
    pub fn inverted(self: @This(), allocator: std.mem.Allocator) !TimeTopology {
        return switch (self) {
            inline .affine, .empty => |aff| try aff.inverted(),
            inline else => |contained| try contained.inverted(allocator),
        };
    }

    // @{ ERRORS
    pub const ProjectionError = error { OutOfBounds };
    // @}
};

test "TimeTopology: finite identity test" 
{
    const tp = TimeTopology.init_identity(
        .{
            .bounds = .{
                .start_seconds = 100,
                .end_seconds = 103
            }
        },
    );

    try expectEqual(tp.bounds().end_seconds, 103);

    const times =           [_]f32 {   99,   100,   101,  102,  103,   104, };
    const expected_result = [_]f32 {   99,   100,   101,  102,  103,   104, };
    const err =             [_]bool{ true, false, false, false, true, true, };

    for (times, 0..)
        |t, index| 
    {
        const s = Sample {
            .ordinate_seconds = t,
        };

        errdefer std.log.err(
            "[{d}] time: {d} expected: {d} err: {any}",
            .{index, t, expected_result[index], err[index]}
        );

        if (err[index]) 
        {
            try expectError(
                TimeTopology.ProjectionError.OutOfBounds,
                tp.project_sample(s),
            );

            try expectError(
                TimeTopology.ProjectionError.OutOfBounds,
                tp.project_ordinate(t),
            );
        } 
        else 
        {
            try expectApproxEqAbs(
                (try tp.project_sample(s)).ordinate_seconds,
                expected_result[index],
                util.EPSILON
            );

            try expectApproxEqAbs(
                try tp.project_ordinate(t),
                expected_result[index],
                util.EPSILON
            );
        }
    }
}

test "TimeTopology: finite Affine" {
    const tp = TimeTopology.init_affine(
        .{ 
            .bounds = .{ .start_seconds = 0, .end_seconds = 10 },
            .transform = .{ .offset_seconds = 10, .scale = 2 },
        }
    );

    const TestData = struct {
        seconds: f32,
        expected: f32,
        err: bool,
    };

    const tests = [_]TestData{
        .{ .seconds = 0, .expected=10, .err = false },
        .{ .seconds = 5, .expected=20, .err = false },
        .{ .seconds = 9, .expected=28, .err = false },
        .{ .seconds = -1, .expected=-2, .err = true },
        .{ .seconds = 10, .expected=20, .err = true },
        .{ .seconds = 100, .expected=200, .err = true },
    };

    for (tests, 0..) |t, index| {
        errdefer std.log.err(
            "[{d}] time: {d} expected: {d} err: {any}",
            .{index, t.seconds, t.expected, t.err}
        );

        if (t.err) 
        {
            try expectError(
                TimeTopology.ProjectionError.OutOfBounds,
                tp.project_ordinate(t.seconds),
            );
        } 
        else 
        {
            try expectApproxEqAbs(
                t.expected,
                try tp.project_ordinate(t.seconds),
                util.EPSILON
            );
        }
    }
}

test "TimeTopology: Affine Projected Through inverted Affine" {
    const tp = TimeTopology.init_affine(
        .{ 
            .bounds = .{ .start_seconds = 0, .end_seconds = 10 },
            .transform = .{ .offset_seconds = 10, .scale = 2 },
        }
    );

    const tp_inv = try tp.inverted(std.testing.allocator);

    const expected_bounds = interval.ContinuousTimeInterval{
        .start_seconds = 10,
        .end_seconds = 30
    };
    try expectApproxEqAbs(
        expected_bounds.start_seconds,
        tp_inv.bounds().start_seconds,
        util.EPSILON
    );
    try expectApproxEqAbs(
        expected_bounds.end_seconds,
        tp_inv.bounds().end_seconds,
        util.EPSILON
    );

    // projecting ordinates through both should result in the original argument
    var time:Ordinate = 0;
    const end_point = tp.bounds().end_seconds;
    while (time < end_point) : (time += 0.1) {
        const result = try tp_inv.project_ordinate(try tp.project_ordinate(time));

        errdefer std.log.err("time: {any} result: {any}", .{time, result});

        try expectApproxEqAbs(time, result, util.EPSILON);
    }
}

test "TimeTopology: Affine Projected Through infinite Affine" {
    const tp = TimeTopology.init_affine(
        .{ 
            .bounds = .{ .start_seconds = 0, .end_seconds = 10 },
            .transform = .{ .offset_seconds = 10, .scale = 2 },
        }
    );
    const tp_inf = TimeTopology.init_identity_infinite();


    const tp_through_tp_inf = try tp_inf.project_topology(tp);

    const tp_inf_through_tp = try tp.project_topology(tp_inf);

    const expected_bounds = interval.ContinuousTimeInterval{
        .start_seconds = 0,
        .end_seconds = 10
    };

    try expectApproxEqAbs(
        expected_bounds.start_seconds,
        tp_through_tp_inf.bounds().start_seconds,
        util.EPSILON
    );
    try expectApproxEqAbs(
        expected_bounds.start_seconds,
        tp_inf_through_tp.bounds().start_seconds,
        util.EPSILON
    );

    try expectApproxEqAbs(
        expected_bounds.end_seconds,
        tp_through_tp_inf.bounds().end_seconds,
        util.EPSILON
    );
    try expectApproxEqAbs(
        expected_bounds.end_seconds,
        tp_inf_through_tp.bounds().end_seconds,
        util.EPSILON
    );

    // projecting ordinates through both should result in the original argument
    var time:Ordinate = expected_bounds.start_seconds;
    const end_point = expected_bounds.end_seconds;
    while (time < end_point) : (time += 0.1) {
        errdefer std.log.err(
            "time: {any}\n", 
            .{time}
        );
        const expected = try tp.project_ordinate(time);
        const result_inf = try tp_inf_through_tp.project_ordinate(time);
        const result_tp = try tp_through_tp_inf.project_ordinate(time);
        errdefer std.log.err(
            "time: {any} result_tp: {any} result_inf: {any}\n", 
            .{time, result_tp, result_inf}
        );

        try expectApproxEqAbs(expected, result_inf, util.EPSILON);
        try expectApproxEqAbs(expected, result_tp, util.EPSILON);
    }
}

test "TimeTopology: Affine through Affine w/ negative scale" {
//
//                         0                 6           10 (duration of the bounds)
// output_to_intrinsic     |-----------------*-----------|
//                         10                4           0
//
//                         0                             10
// intrinsic_to_media      |-----------------*-----------|
//                         90                6           100
//
    const output_to_intrinsic = TimeTopology.init_affine(
        .{ 
            .bounds = .{ .start_seconds = 0, .end_seconds = 10 },

            // @TODO: why does this need an offset of 10? that seems weird
            .transform = .{ .offset_seconds = 10, .scale = -1 },
        }
    );

    const intrinsic_to_media = TimeTopology.init_affine(
        .{ 
            .bounds = .{ .start_seconds = 0, .end_seconds = 10 },
            .transform = .{ .offset_seconds = 90, .scale = 1 },
        }
    );

    const output_to_media = try intrinsic_to_media.project_topology(
        output_to_intrinsic
    );

    const TestData = struct {
        output_s: f32,
        media_s: f32,
        err: bool,
    };

    const output_to_media_tests = [_]TestData{
        .{ .output_s = 0, .media_s=100, .err = false },
        .{ .output_s = 3, .media_s=97, .err = false },
        .{ .output_s = 6, .media_s=94, .err = false },
        .{ .output_s = 9, .media_s=91, .err = false },
        .{ .output_s = 10, .media_s=100, .err = true },
    };

    for (output_to_media_tests, 0..) |t, index| {
        errdefer std.log.err(
            "[{d}] time: {d} expected: {d} err: {any}",
            .{index, t.output_s, t.media_s, t.err}
        );

        if (t.err) 
        {
            try expectError(
                TimeTopology.ProjectionError.OutOfBounds,
                output_to_media.project_ordinate(t.output_s),
            );
        } 
        else 
        {
            try expectApproxEqAbs(
                t.media_s,
                try output_to_media.project_ordinate(t.output_s),
                util.EPSILON
            );
        }
    }
}

test "TimeTopology: staircase constructor" {
    const increment:f32 = 2;
    const tp = try TimeTopology.init_step_mapping(
        .{
            .start_seconds = 10,
            .end_seconds = 20
        },
        0,
        2,
        increment
    );

    try expectEqual(
        @as(usize, 5),
        tp.bezier_curve.curve.segments.len
    );

    var value:f32 = 0;
    for (tp.bezier_curve.curve.segments) |seg| {
        try expectEqual(value, seg.p0.value);
        value += increment;
    }

    // evaluate the curve via the external coordinate system
    try expectEqual(
        @as(f32, 20),
        tp.bounds().end_seconds
    );

    try expectEqual(
        @as(f32, 8),
        try tp.project_ordinate(@as(f32, 19)),
    );
}

test "TimeTopology: project bezier through affine" {
    // affine topology
    //
    // output: [100, 110)
    // input:  [0, 10)
    //
    const aff_transform = (
        transform.AffineTransform1D{
            .offset_seconds = 100,
            .scale = 1,
        }
    );
    const aff_bounds = .{
        .start_seconds = 0,
        .end_seconds = 10,
    };
    const affine_topo = (
        TimeTopology.init_affine(
            .{
                .transform = aff_transform,
                .bounds = aff_bounds,
            }
        )
    );

    //
    // Bezier curve
    //
    // mapping:
    // output: [0,    10)
    // input:  [100, 110)
    //
    //   shape: (straight line)
    //
    //    |   /
    //    |  /
    //    | /
    //    +------
    //

    // this curve is [-0.5, 0.5), so needs to be rescaled into the space
    // of the test/data that we want to do.
    const crv = try curve.read_curve_json(
        "curves/linear.curve.json",
        std.testing.allocator,
    );
    defer crv.deinit(std.testing.allocator);
    const xform_curve = try curve.rescaled_curve(
        std.testing.allocator,
        //  the range of the clip for testing - rescale factors
        crv,
        .{
            .{ .time = 100, .value = 0, },
            .{ .time = 110, .value = 10, },
        }
    );
    defer xform_curve.deinit(std.testing.allocator);

    const curve_topo = TimeTopology.init_bezier_cubic(xform_curve);

    // bezier through affine
    {
        //
        // should result in a curve mapping:
        //
        // (identity curve, 1 segment)
        //
        // [100, 110)
        // [100, 110)
        //
        const result = try affine_topo.project_topology(curve_topo);

        try std.testing.expect(std.meta.activeTag(result) != TimeTopology.empty);
    }

    // affine through bezier
    {
        //
        // should result in a curve mapping:
        //
        // (identity curve, 1 segment)
        //
        // [0, 10)
        // [0, 10)
        //
        const result = try curve_topo.project_topology(affine_topo);

        try std.testing.expect(std.meta.activeTag(result) != TimeTopology.empty);
    }
}

// @{ Sample Generators
// the pattern for a python style generator is a struct with:
// pub fn next() ?f32 { // if still iterable return value, otherwise return null }
// while (iter.next()) |next_value| { // do stuff }
//
// for now generates a static array
//
/// A Sample generator generates samples in the intrinsic coordinate space of 
/// the timetopology, according to different functions.
pub const StepSampleGenerator = struct {
    start_offset: f32 = 0,
    rate_hz: f32,

    pub fn sample_over(
        self: @This(), 
        topology: TimeTopology
    ) ![]Sample
    {
        var result: std.ArrayList(Sample) = (
            std.ArrayList(Sample).init(ALLOCATOR)
        );

        // @TODO:
        // I suspect a better way to do this is to project the numbers into a
        // space where integer math can be used.
        // -- Or the ratinoal time engine?
        const increment: f32 = 1/self.rate_hz;
        var current_coord = self.start_offset;
        const end_seconds = topology.bounds().end_seconds;

        // @breakpoint();

        while (current_coord < end_seconds - util.EPSILON) 
        {
            const next: Sample = .{
                .ordinate_seconds = current_coord,
                .support_negative_seconds = 0,
                .support_positive_seconds = increment
            };

            const tp_space: ?Sample = try topology.project_sample(next);

            // if a sample has a valid projection, append it
            if (tp_space) |s| {
                try result.append(s);
            } 

            current_coord += increment;
        }

        return result.items;
    }
};

test "StepSampleGenerator: sample over step function topology" {
    const sample_rate: f32 = 24;

    const sample_generator = StepSampleGenerator{
        // should this be an absolute coordinate origin instead of an
        // offset?
        .start_offset = 100,
        .rate_hz = sample_rate,
    };

    // staircase with three steps in it
    var target_topology = try TimeTopology.init_step_mapping(
        .{
            .start_seconds = 100,
            .end_seconds = 103,
        },
        100,
        1,
        1
    );

    const result = try sample_generator.sample_over(target_topology);
    const expected = target_topology.bounds().duration_seconds() * sample_rate;

    try expectApproxEqAbs(
        @as(f32, 102),
        result[result.len - 1].ordinate_seconds,
        util.EPSILON
    );

    try expectEqual(
        @as(usize, @intFromFloat(@floor(expected))),
        result.len,
    );
}

test "StepSampleGenerator: sample over identity topology" 
{
    const sample_rate: f32 = 24;

    const sample_generator = StepSampleGenerator{
        .start_offset = 100,
        .rate_hz = sample_rate,
    };

    const target_topology = TimeTopology.init_identity(
        .{ .bounds = .{ .start_seconds = 100, .end_seconds = 103 } }
    );
    const result = try sample_generator.sample_over(target_topology);

    const expected_last_coord = (
        target_topology.bounds().end_seconds 
        - 1/@as(f32, 24)
    );

    const result_s = result[result.len - 1];
    const actual_ordinate = result_s.ordinate_seconds;
    expectApproxEqAbs(
        expected_last_coord,
        actual_ordinate,
        util.EPSILON
    ) catch @breakpoint();

    const expected = target_topology.bounds().duration_seconds() * sample_rate;
    try expectEqual(
        @as(usize, @intFromFloat(@floor(expected))),
        result.len,
    );
}
// @}
