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

const Ordinate = f32;

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
        result.ordinate_seconds = try self.project_ordinate(sample.ordinate_seconds);
        return result;
    }

    pub fn project_ordinate(self: @This(), ordinate: Ordinate) !Ordinate {
        if (!self.bounds.overlaps_seconds(ordinate)) {
            return TimeTopology.ProjectionError.OutOfBounds;
        }

        return self.transform.applied_to_seconds(ordinate);
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

    // @TODO: turn these on
    // linear_curve: curve.TimeCurveLinear,
    // bezier_curve: curve.TimeCurve,

    // linear_holodrome_curve: curve.TimeCurveLinearHolodrome,
    // bezier_holodrome_curve: curve.TimeCurveBezierHolodrome,

    pub fn is_holodrome(self: @This()) bool {
        return switch (self) {
            .affine, => true,
            // @NICK: this can tell if things are already holodromes or need to
            //        be converted
            // .affine, .linear_holodrome_curve, .bezier_holodrome_curve => true,
            // else => false
        };
    }

    // default to an infinite identity
    const IdentityArgs = struct {
        // @NICK: no bounds = unbounded?  or use INF_CTI as a comparison
        bounds: interval.ContinuousTimeInterval = interval.INF_CTI,
        transform: transform.AffineTransform1D = .{},
    };

    // @{ Initializers
    pub fn init_identity(
        args: IdentityArgs,
    ) TimeTopology 
    {
        return .{ .affine = .{ .bounds = args.bounds } };
    }

    pub fn init_affine(topo: AffineTopology) TimeTopology {
        return .{ .affine = topo };
    }
    // @}

    // @NICK: I think we had this discussion already but what is your position
    //        on maybe bounds vs interval.INF_CTI for handling infinite bounds?
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
    // @}

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
            // @NICK: should we express bounds in the input space?  Or the
            //        output space?
            //        if so, I wonder if the .bounds field should be named
            //        "input bounds" (my guess: yes and yes)
            .bounds = .{ .start_seconds = 0, .end_seconds = 10 },
            .transform = .{ .offset_seconds = 10, .scale = 1 },
        }
    );

    const TestData = struct {
        seconds: f32,
        expected: f32,
        err: bool,
    };

    const tests = [_]TestData{
        .{ .seconds = 0, .expected=10, .err = false },
        .{ .seconds = 5, .expected=15, .err = false },
        .{ .seconds = -1, .expected=-1, .err = true },
        .{ .seconds = 10, .expected=10, .err = true },
        .{ .seconds = 100, .expected=100, .err = true },
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
                try tp.project_ordinate(t.seconds),
                t.expected,
                util.EPSILON
            );
        }
    }

}
