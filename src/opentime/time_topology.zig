const std = @import("std"); 

const interval = @import("interval.zig"); 
const transform = @import("transform.zig"); 
const curve = @import("curve/curve.zig"); 
const sample_lib = @import("sample.zig");
const Sample = sample_lib.Sample; 
const util = @import("util.zig"); 


// assertions
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;
const expectApproxEqAbs = std.testing.expectApproxEqAbs;

pub const Ordinate = f32;

const AffineTopology = struct {
    // defaults to an infinite identity
    bounds: interval.ContinuousTimeInterval = interval.INF_CTI,
    transform: transform.AffineTransform1D = .{
        .offset_seconds = 0,
        .scale = 1,
    },

    pub fn compute_bounds(self: @This()) interval.ContinuousTimeInterval {
        return self.bounds;
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

    pub fn inverted(self: @This()) !TimeTopology {
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

    pub fn project_topology(self: @This(), other: TimeTopology) TimeTopology {
        return switch (other) {
           .affine => |other_aff| {
               // A->B (bounds are in A
               // B->C (bounds are in B
               // B->C.project(A->B) => A->C, bounds are in A
               //
               // self: self.input -> self.output
               // other:other.input -> other.output
               //
               // self.project_topology(other) => other.input -> self.output
               // result.bounds -> other.input
               //
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
           else => .{ .empty = .{} },
        };
    }
};

pub const BezierTopology = struct {
    bezier_curve: curve.TimeCurve,

    pub fn compute_bounds(self: @This()) interval.ContinuousTimeInterval {
        const extents = self.bezier_curve.extents();

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
        return self.bezier_curve.evaluate(ordinate);
    }

    pub fn inverted(self: @This()) !TimeTopology {
        _ = self;
        return error.NotImplemented;
    }

    pub fn project_topology(self: @This(), other: TimeTopology) TimeTopology {
        _ = self;
        _ = other;
        return error.NotImplemented;
        // return switch (other) {
        //    .affine => |other_aff| {
        //        // A->B (bounds are in A
        //        // B->C (bounds are in B
        //        // B->C.project(A->B) => A->C, bounds are in A
        //        //
        //        // self: self.input -> self.output
        //        // other:other.input -> other.output
        //        //
        //        // self.project_topology(other) => other.input -> self.output
        //        // result.bounds -> other.input
        //        //
        //         const inv_xform = other_aff.transform.inverted();
        //
        //        const self_bounds_in_input_space = (
        //            inv_xform.applied_to_bounds(self.bounds)
        //        );
        //
        //        const bounds = interval.intersect(
        //            self_bounds_in_input_space,
        //            other_aff.bounds,
        //        );
        //
        //        if (bounds) |b| {
        //            return .{
        //                .affine = .{ 
        //                    .bounds = b,
        //                    .transform = (
        //                        self.transform.applied_to_transform(
        //                            other_aff.transform
        //                        )
        //                    )
        //                },
        //            };
        //        }
        //        else {
        //            return .{ .empty = .{} };
        //        }
        //    },
        //    else => .{ .empty = .{} },
        // };
    }
};

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
// ////////////////////////////////////////////////////////////////////////////
pub const TimeTopology = union (enum) {
    affine: AffineTopology,
    empty: EmptyTopology,

    // linear_curve: curve.TimeCurveLinear,
    bezier_curve: BezierTopology,

    // linear_holodrome_curve: curve.TimeCurveLinearHolodrome,
    // bezier_holodrome_curve: curve.TimeCurveBezierHolodrome,

    // default to an infinite identity
    const IdentityArgs = struct {
        bounds: interval.ContinuousTimeInterval = interval.INF_CTI,
        transform: transform.AffineTransform1D = .{},
    };

    // @{ Initializers
    pub fn init_identity_infinite() TimeTopology {
        return init_identity(.{});
    }

    pub fn init_identity(
        args: IdentityArgs,
    ) TimeTopology 
    {
        return .{ .affine = .{ .bounds = args.bounds } };
    }

    pub fn init_affine(topo: AffineTopology) TimeTopology {
        return .{ .affine = topo };
    }

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
    
    pub fn init_bezier_cubic(btc: curve.TimeCurve) TimeTopology {
        return .{.bezier_curve = .{.bezier_curve = btc}};
    }
    
    pub fn init_empty() TimeTopology {
        return .{ .empty = EmptyTopology{} };
    }
    // @}

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
    ) TimeTopology 
    {
        return switch(self) {
            .affine => |other_aff| other_aff.project_topology(other),
            .empty => .{ .empty = .{} },
            inline else => .{ .empty = .{} },
            // others: might require promotion into curves
        };
    }
    // @}
    
    pub fn inverted(self: @This()) !TimeTopology {
        return switch (self) {
            inline else => |contained| try contained.inverted(),
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

    for (times) 
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

    for (tests) |t, index| {
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

    const tp_inv = try tp.inverted();

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


    const tp_through_tp_inf = tp_inf.project_topology(tp);

    const tp_inf_through_tp = tp.project_topology(tp_inf);

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

    const output_to_media = intrinsic_to_media.project_topology(
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

    for (output_to_media_tests) |t, index| {
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
