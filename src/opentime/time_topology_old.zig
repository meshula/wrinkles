const std = @import("std"); 

const transform = @import("transform.zig"); 
const curve = @import("curve/curve.zig"); 
const interval = @import("interval.zig"); 

const sample_lib = @import("sample.zig");
const Sample = sample_lib.Sample; 

const util = @import("util.zig"); 
const allocator = @import("allocator.zig"); 

// assertions
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;
const expectApproxEqAbs = std.testing.expectApproxEqAbs;

// TEMPORAL TOPOLOGY PROTOTYPE @{
// ////////////////////////////////////////////////////////////////////////////
// The time topology maps an external temporal coordinate system to an internal
// one.  Coordinates in the external coordinate system can be projected through
// the topology to retrieve values in the internal coordinate system.
//
// The time toplogy is a piecewise-linear function with an additional transform
// and bounds.
//
// The outer coordinate system is an intrinsic one, defined as having an origin
// of 0 with a duration equivalent to the duration of the bounds of the 
// TimeTopology.
//
// There are several special cases of Topology that are implemented by Kind.
// Empty: a topology that maps nowhere on the timeline
// Identity_infinite: a topology that is identity everywhere on the timeline
// finite: a topology with finite bounds
//
// @QUESTION: should a TimeTopology have a local origin for the intrinsic
//            coordinate system of some kind?  That would allow someone to
//            specify that the external coordinate system starts at 86400, for
//            example.  Also lets discuss this diagram below!
//
// # Example
//
// For:
//   .transform  = { offset = 10, scale = 2 }
//   .bounds = 100, 200
//   .mapping = indentity
//   .kind = finite
// 
// maybe its just a scale, bounds and a mapping?  and the `transform' is 
// transient?
//
// or maybe the transform is LOCKED to -bounds.start_seconds?
//
//              0                 36          50 (duration of the bounds)
// output       |-----------------*-----------|
// internal     |-----------------*-----------|
//              100               176         200
//
pub const TimeTopology = struct {

    const Kind = enum(i8) {
        empty,  // any evaluation returns none (no bounds, transform or mapping)
        finite, // evaluation uses the segments and curves (bounds, transform, mapping)
        infinite_identity, // any evaluation returns the parameter (mapping and transform)
    };

    // @TODO: should this be a tree rather than a sequence?
    // represents the basis of the topology
    transform: transform.AffineTransform1D = .{},

    // in the space of the topology
    bounds: interval.ContinuousTimeInterval = .{},

    // @TODO: the default should maybe not be finite? 
    kind:Kind = Kind.finite,

    // @QUESTION: I think this should be a list of TimeCurves possibly?  or do 
    //            we only keep one?  How do we map a section of a topology to a
    //            given media reference unless there are separate objects?
    mapping: []curve.TimeCurve = &.{},

    pub fn from_sample(
        s: Sample
    ) TimeTopology
    {
        return TimeTopology.init_identity_finite(
            .{
                .start_seconds=s.ordinate_seconds - s.support_negative_seconds,
                .end_seconds=s.ordinate_seconds + s.support_positive_seconds
            }
        );
    }

    pub fn init(mappings: []curve.TimeCurve) TimeTopology {
        return .{ .mapping = mappings, .kind=Kind.finite };
    }

    pub fn init_empty() TimeTopology {
        return .{ .kind = Kind.empty };
    }

    pub fn init_inf_identity() TimeTopology {
        return TimeTopology{
            .kind = Kind.infinite_identity,
        };
    }

    /// generate a Topology with a single segment identity curve in it that is
    /// defined over the finite bounds
    pub fn init_identity_finite(
        bounds: interval.ContinuousTimeInterval
    ) TimeTopology 
    {
        const identity_curve: curve.TimeCurve = curve.TimeCurve.init(
            &.{ 
                curve.create_identity_segment(
                    bounds.start_seconds,
                    bounds.end_seconds
                )
            }
        ) catch curve.TimeCurve{};

        const mapping: []curve.TimeCurve = allocator.ALLOCATOR.dupe(
            curve.TimeCurve,
            &.{ identity_curve }
        ) catch &.{};

        return TimeTopology{
            .transform = .{
                .offset_seconds = bounds.start_seconds,
                .scale = 1,
            },
            .bounds = bounds,
            .mapping = mapping,
            .kind = Kind.finite,
        };
    }

    pub fn init_from_single_curve(crv: curve.TimeCurve) TimeTopology {
        const mapping: []curve.TimeCurve = allocator.ALLOCATOR.dupe(
            curve.TimeCurve,
            &.{ crv }
        ) catch &.{};

        const bounds = crv.extents_time();

        return TimeTopology{
            .transform = .{
                .offset_seconds = bounds.start_seconds,
                .scale = 1,
            },
            .bounds = bounds,
            .mapping = mapping,
            .kind = Kind.finite,
        };
    }

    /// build a topology with a single curve with a single lienar segment with
    /// the given slope
    pub fn init_linear(
        slope: f32,
        bounds: interval.ContinuousTimeInterval,
    ) TimeTopology
    {
        const end_value = (
            slope*(bounds.end_seconds - bounds.start_seconds) 
            + bounds.start_seconds
        );

        const crv: [1]curve.TimeCurve = .{
            curve.TimeCurve.init(
                &.{ 
                    curve.create_linear_segment(
                        .{ .time = bounds.start_seconds, .value = bounds.start_seconds },
                        .{ .time = bounds.end_seconds, .value = end_value }, 
                    )
                }
            ) catch curve.TimeCurve{}
        };

        const mapping : []curve.TimeCurve = allocator.ALLOCATOR.dupe(
                curve.TimeCurve,  
                &crv
        ) catch &.{};

        return TimeTopology{
            .transform = .{
                .offset_seconds = bounds.start_seconds,
                .scale = 1,
            },
            .bounds = bounds,
            .mapping = mapping,
            .kind = Kind.finite,
        };
    }

    /// build a topology with a single curve with a single lienar segment with
    /// the given slope
    pub fn init_linear_start_end(
        bounds: interval.ContinuousTimeInterval,
        start_value: f32,
        end_value: f32,
    ) TimeTopology
    {
        const crv: [1]curve.TimeCurve = .{
            curve.TimeCurve.init(
                &.{ 
                    curve.create_linear_segment(
                        .{ .time = bounds.start_seconds, .value = start_value },
                        .{ .time = bounds.end_seconds, .value = end_value }, 
                    )
                }
            ) catch curve.TimeCurve{}
        };

        const mapping : []curve.TimeCurve = allocator.ALLOCATOR.dupe(
                curve.TimeCurve,  
                &crv
        ) catch &.{};

        return TimeTopology{
            .transform = .{
                .offset_seconds = bounds.start_seconds,
                .scale = 1,
            },
            .bounds = bounds,
            .mapping = mapping,
            .kind = Kind.finite,
        };
    }

    pub fn intrinsic_space_bounds(self: @This()) interval.ContinuousTimeInterval {
        return .{
            // always starts at 0
            .start_seconds = 0,
            // ...and runs for the duration after applying the scaling factor
            .end_seconds = (
                self.transform.inverted().applied_to_seconds(
                    self.bounds.end_seconds
                )
            )
        };
    }

    // builds a TimeTopology out with a mapping that contains a step function
    // @TODO: should include a phase offset
    pub fn init_step_mapping(
        bounds: interval.ContinuousTimeInterval,
        // the value of the function at the initial sample (f(0))
        start_value: f32,
        held_duration: f32,
        increment: f32,
    ) !TimeTopology
    {
        var segments = std.ArrayList(curve.Segment).init(allocator.ALLOCATOR);
        var t_seconds = bounds.start_seconds;
        var current_value = start_value;
        while (t_seconds < bounds.end_seconds) {
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

        const crv = curve.TimeCurve.init(segments.items) catch curve.TimeCurve{};

        return TimeTopology.init_from_single_curve(crv);
    }

    pub const ProjectionError = error {
        OutOfBounds,
    };

    /// topology interface for projection
    pub fn project_topology(
        self: @This(),
        other: TimeTopology
    ) TimeTopology 
    {
        if (other.kind == Kind.empty) {
            // if other is empty, it doesn't matter what self is, the result is
            // an empty topology
            return other;
        }

        if (self.kind == Kind.empty) {
            return .{ .kind = Kind.empty };
        }

        if (self.kind == Kind.infinite_identity) {
            return other;
        }

        // if (self.kind == Kind.finite) 
        const other_wrapped = (
            if (other.kind == Kind.infinite_identity) (
                TimeTopology.init_identity_finite(self.bounds)
            ) else (
                other
            )
        );

        var result = (
            std.ArrayList(curve.TimeCurve).init(allocator.ALLOCATOR)
        );

        // @TODO: these curves need to have their respective
        //        transformations applied (if we stick with that model)
        for (other_wrapped.mapping) 
            |other_crv|
        {
            for (self.mapping) 
                |self_crv|
            {
                const resulting_curves = (
                    self_crv.project_curve(other_crv)
                );
                for (resulting_curves) 
                    |crv| 
                {
                    result.append(
                        curve.TimeCurve.init_from_linear_curve(crv)
                    ) catch unreachable;
                }
            }
        }

        const result_bounds = interval.intersect(
            self.bounds,
            other_wrapped.bounds
        ) orelse interval.ContinuousTimeInterval{};

        return .{
            .transform = .{
                .offset_seconds = result_bounds.start_seconds,
                .scale = 1
            },
            .bounds = result_bounds,
            .mapping = result.items,
            // if its finite, even if other has no segments, is empty
            .kind = Kind.finite,
        };
    }

    // @TODO: should this be `project_ordinate`?
    pub fn project_seconds(
        self: @This(),
        seconds: f32
    ) !f32 
    {
        return switch (self.kind) {
            Kind.empty => ProjectionError.OutOfBounds,
            // @TODO: what do you think of this?
            Kind.infinite_identity => self.transform.applied_to_seconds(seconds),
            Kind.finite => {
                const transformed_s = self.transform.applied_to_seconds(
                    seconds
                );

                if (!self.bounds.overlaps_seconds(transformed_s)) {
                    // @TODO if this is the only place where an error can
                    //       emerge, this should be an optional rather than an 
                    //       error.
                    return ProjectionError.OutOfBounds;
                }

                const relevant_curve = self.find_curve(transformed_s);

                if (relevant_curve) |crv| {
                    return crv.evaluate(transformed_s);
                }

                return ProjectionError.OutOfBounds;
            }
        };
    }

    pub fn project_sample(self: @This(), sample: Sample) !Sample {
        return switch (self.kind) {
            Kind.empty => ProjectionError.OutOfBounds,
            Kind.infinite_identity => sample,
            Kind.finite => {
                const t_seconds = try self.project_seconds(
                    sample.ordinate_seconds
                );

                // @TODO: what is the width?
                return Sample {
                    .ordinate_seconds = t_seconds,
                    .support_negative_seconds = sample.support_negative_seconds,
                    .support_positive_seconds = sample.support_positive_seconds,
                };
            }
        };
    }

    pub fn find_curve_index(self: @This(), t_arg: f32) ?usize {
        if (self.kind == Kind.empty or self.kind == Kind.infinite_identity) {
            return null;
        }

        // @TODO: better would be a specific start time accessor in curve
        const start_time = self.mapping[0].extents_time().start_seconds;

        if (self.mapping.len == 0 or
            t_arg < start_time or
            t_arg >= self.mapping[self.mapping.len-1].extents_time().end_seconds)
        {
            return null;
        }

        // quick check if it is exactly the start time of the first segment
        if (t_arg == start_time) {
            return 0;
        }

        for (self.mapping) |crv, index| {
            // @TODO: having an extents_time would be better, since those are
            //        known and do not need to be computed
            const extents = crv.extents_time();
            if (
                extents.start_seconds <= t_arg 
                and t_arg < extents.end_seconds
            ) {
                // exactly in a segment
                return index;
            }
        }

        // between segments, identity
        return null;
    }

    pub fn find_curve(self: @This(), t_arg: f32) ?*curve.TimeCurve {
        if (self.kind == Kind.empty or self.kind == Kind.infinite_identity) {
            return null;
        }

        if (self.find_curve_index(t_arg)) |ind| {
            return &self.mapping[ind];
        }

        return null;
    }

    pub fn inverted(self: @This()) !TimeTopology {
        var result = self;
        result.mapping = allocator.ALLOCATOR.dupe(
            curve.TimeCurve,
            self.mapping
        ) catch unreachable;

        for (self.mapping) |crv, index| {
            const inverted_crv = curve.inverted(crv);

            result.mapping[index] = curve.TimeCurve.init_from_linear_curve(
                inverted_crv
            );
        }

        result.transform = self.transform.inverted();

        return result;
    }
};

test "TimeTopology: coordinate space test" 
{
    const tp = TimeTopology.init_identity_finite(
         .{
            .start_seconds = 100,
            .end_seconds = 103
        },
    );

    try expectEqual(
        tp.intrinsic_space_bounds().end_seconds,
        3
    );

    try expectEqual(tp.intrinsic_space_bounds().end_seconds, 3);

    const times =           [_]f32 {   -1,     0,     1,    2,   -1,    -1, };
    const expected_result = [_]f32 {   99,   100,   101,  102,  103,   104, };
    const err =             [_]bool{ true, false, false, false, true, true, };

    for (times) 
        |t, index| 
    {
        const s = Sample {
            .ordinate_seconds = t,
        };

        if (err[index]) 
        {
            try expectError(
                TimeTopology.ProjectionError.OutOfBounds,
                tp.project_sample(s),
            );
        } 
        else 
        {
            expectApproxEqAbs(
                (try tp.project_sample(s)).ordinate_seconds,
                expected_result[index],
                util.EPSILON
            ) catch |this_err| {
                _ = (try tp.project_sample(s)).ordinate_seconds;
                return this_err;
        };
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
        tp.mapping[0].segments.len
    );

    var value:f32 = 0;
    for (tp.mapping[0].segments) |seg| {
        try expectEqual(value, seg.p0.value);
        value += increment;
    }

    // evaluate the curve via the external coordinate system
    try expectEqual(
        @as(f32, 10),
        tp.intrinsic_space_bounds().end_seconds
    );

    try expectEqual(
        @as(f32, 8),
        try tp.project_seconds(@as(f32, 9)),
    );
}

// @QUESTION: I've settled on this pattern for tests -- a grouping and then a 
//            label
test "TimeTopology: intrinsic_space_bounds test" 
{
    const tp = TimeTopology {
        .transform = .{
            .offset_seconds = 100,
            .scale = 0.5,
        },
        .bounds = .{
            .start_seconds = 100,
            .end_seconds = 106
        }
    };

    const tp_intrinsic_bounds = tp.intrinsic_space_bounds();

    try expectEqual(tp_intrinsic_bounds.start_seconds, 0);
    try expectEqual(tp_intrinsic_bounds.end_seconds, 12);
}

test "TimeTopology: curve length init test" {
    const tt= TimeTopology.init_identity_finite(
        .{ .start_seconds = 0, .end_seconds = 10 }
    );

    try expectEqual(tt.mapping.len, 1);
    try expectEqual(tt.mapping[0].segments.len, 1);
}

test "TimeTopology: single identity" 
{
    const identity_tp = TimeTopology.init_identity_finite(
        .{ .start_seconds = 0, .end_seconds = 103 }
    );

    const s = Sample {.ordinate_seconds = 10};

    const out = try identity_tp.project_sample(s);

    try expectApproxEqAbs(s.ordinate_seconds, out.ordinate_seconds, util.EPSILON);
    try expectApproxEqAbs(s.support_negative_seconds, out.support_negative_seconds, util.EPSILON);
    try expectApproxEqAbs(s.support_positive_seconds, out.support_positive_seconds, util.EPSILON);
}

test "TimeTopology: single linear" 
{
    const slope = 2;
    const identity_tp = TimeTopology.init_linear (
        slope,
        .{ .start_seconds = 0, .end_seconds = 103 }
    );

    const s = Sample {.ordinate_seconds = 10};

    // @breakpoint();
    const out = try identity_tp.project_sample(s);


    try expectApproxEqAbs(slope*s.ordinate_seconds, out.ordinate_seconds, util.EPSILON);
    try expectApproxEqAbs(s.support_negative_seconds, out.support_negative_seconds, util.EPSILON);
    try expectApproxEqAbs(s.support_positive_seconds, out.support_positive_seconds, util.EPSILON);
}

test "TimeTopology: single from sample"
{
    const s = .{
        .ordinate_seconds = 12,
        .support_negative_seconds = 6,
        .support_positive_seconds = 6
    };

    // @TODO: should this be init_from_sample()?
    const tp = TimeTopology.from_sample(s);

    try expectEqual(@as(f32, 6), tp.bounds.start_seconds,);
    try expectEqual(@as(f32, 18), tp.bounds.end_seconds,);
    try expectEqual(@as(f32, 1), tp.transform.scale,);
    try expectEqual(@as(f32, 6), tp.transform.offset_seconds,);
}

test "TimeTopology: infinite with transform" {
    var tp = TimeTopology.init_inf_identity();
    tp.transform = .{ .offset_seconds = -100, .scale = 1 };
    try expectEqual(
        @as(f32, 8),
        try tp.project_seconds(@as(f32, 108)),
    );

    // var tp2 = TimeTopology.init_inf_identity();
    // const result = tp.project_topology(tp2);
    // try expectEqual(
    //     @as(f32, 8),
    //     try tp.project_seconds(@as(f32, 108)),
    // );

}
// @}
