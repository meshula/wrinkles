const std = @import("std");
const debug_panic = @import("std").debug.panic;

const assert = std.debug.assert;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
const expectError = std.testing.expectError;
const expect = std.testing.expect;

// const opentime = @import("opentime");
const opentime = @import("../opentime.zig");
const bezier_math = @import("./bezier_math.zig");
const generic_curve = @import("./generic_curve.zig");
const linear_curve = @import("./linear_curve.zig");
const interval = opentime.interval;
const ContinuousTimeInterval = opentime.ContinuousTimeInterval;
const control_point = @import("./control_point.zig");
const ControlPoint = control_point.ControlPoint;

const stdout = std.io.getStdOut().writer();

const inf = std.math.inf(f32);
const nan = std.math.nan(f32);

const  util = @import("util");

const otio_allocator = @import("../allocator.zig");
const ALLOCATOR = otio_allocator.ALLOCATOR;

const string_stuff = @import("../string_stuff.zig");
const latin_s8 = string_stuff.latin_s8;

// hodographs c-library
const hodographs = @cImport(
    {
        @cInclude("hodographs.h");
    }
);

fn expectApproxEql(expected: anytype, actual: @TypeOf(expected)) !void {
    return std.testing.expectApproxEqAbs(expected, actual, generic_curve.EPSILON);
}


// Time curves are functions mapping a time to a value.
// Time curves are a sequence of right met 2d Bezier curve segments
// closed on the left and open on the right.
// If the first formal segment does not start at -inf, there is an
// implicit interval spanning -inf to the first formal segment.
// If there final formal segment does not end at +inf, there is an
// implicit interval spanning the last point in the final formal
// segment to +inf.
//
// It is a formal requirement that an application supply control
// points that satistfy the rules of a function, in other words,
// a Time Curve cannot contain a 2d Bezier curve segment that has
// a cusp or a loop.
//
// We name the parameterization of the time coordinate system t,
// and we name the parameterization of the Bezier curves u.
// The parameter t can be any legal timeline value, u must be
// within the closed interval of [0,1].
//
// The value of a Bezier at u is B(u). The value of a time curve at
// t is T(t). If M(x) maps t into u, then the evaluation of B(t) is
// B(M(C(t))).
// 

// A Time Curve with a single segment spanning t1 to t2
// therefore looks like this:
//
// -inf ------[---------)------- inf+
//            t1        t2               time parameterization
//            p0 p1 p2 p3                curve parameterization
//

// Each Bezier curve in a TimeCurve is a Bezier segment with
// four control points. Here we name the components of the
// control point ordinates time and value, and these axes
// correspond to the time metric the TimeCurve is embedded in.
// Note that when the Bezier curve is evaluated, the Bezier
// parameterization u will be used to evaluate the function
// nto the time metric space.

// Note that continuity between segments is not dictated by
// the TimeCurve class. Interested applications should make
// their own data structure that records continuity data, and
// are responsible for constraining the control points to 
// satisfy those continuity constraints. In the future, this
// library may provide helper functions that aid in the
// computation of common constraints, such as colinear
// tangents on end points, and so on.

/// compute the linear distance between two points
pub fn distance(
    from: ControlPoint,
    to: ControlPoint
) f32 
{
    const dist = to.sub(from);

    return std.math.sqrt((dist.time*dist.time) + (dist.value*dist.value));
}

test "distance: 345 triangle" {
    try expectEqual( @as(f32, 5),
        distance(
            .{ .time = 3, .value = -3 },
            .{ .time = 6, .value = 1 }
        )
    );
}

/// @TODO: time should be an ordinate

pub const Segment = struct {
    // time coordinate of each control point is expressed in the coordinate
    // system of the embedding space, ie a clip's intrinsic space.
    p0: ControlPoint = .{
        .time = 0,
        .value = 0,
    },
    p1: ControlPoint = .{
        .time = 0,
        .value = 0,
    },
    p2: ControlPoint = .{
        .time = 1,
        .value = 1,
    },
    p3: ControlPoint = .{
        .time = 1,
        .value = 1,
    },

    pub fn points(self: @This()) [4]ControlPoint {
        return .{ self.p0, self.p1, self.p2, self.p3 };
    }

    pub fn from_pt_array(pts: [4]ControlPoint) Segment {
        return .{ .p0 = pts[0], .p1 = pts[1], .p2 = pts[2], .p3 = pts[3], };
    }

    /// evaluate the segment at parameter unorm, [0, 1)
    pub fn eval_at(
        self: @This(),
        unorm:f32
    ) ControlPoint
    {
        const use_reducer = true;
        if (use_reducer) {
            const seg3 = bezier_math.segment_reduce4(unorm, self);
            const seg2 = bezier_math.segment_reduce3(unorm, seg3);
            const result = bezier_math.segment_reduce2(unorm, seg2);
            return result.p0;
        }
        else {
            const z = unorm;
            const z2 = z*z;
            const z3 = z2*z;

            const zmo = z-1.0;
            const zmo2 = zmo*zmo;
            const zmo3 = zmo2*zmo;

            const p1: ControlPoint = self.p0;
            const p2: ControlPoint = self.p1;
            const p3: ControlPoint = self.p2;
            const p4: ControlPoint = self.p3;

            const l_p4: ControlPoint = (
                (p4.mul(z3)).sub(p3.mul(3.0*z2*zmo)).add(p2.mul(3.0*z*zmo2)).sub(p1.mul(zmo3))
            );

            return l_p4;
        }

    }

    pub fn overlaps_time(self:@This(), t:f32) bool {
        return (self.p0.time <= t and self.p3.time > t);
    }

    pub fn split_at(self: @This(), unorm:f32) [2]Segment 
    {
        const z = unorm;
        const z2 = z*z;
        const z3 = z2*z;

        const zmo = z-1.0;
        const zmo2 = zmo*zmo;
        const zmo3 = zmo2*zmo;

        // const unorm_2 = unorm*unorm;
        // const unorm_3 = unorm_2*unorm;
        //
        // const un_sub = unorm - 1;
        // const un_sub_2 = un_sub * un_sub;
        // const un_sub_3 = un_sub_2 * un_sub;
        //
        const p1: ControlPoint = self.p0;
        const p2: ControlPoint = self.p1;
        const p3: ControlPoint = self.p2;
        const p4: ControlPoint = self.p3;

        const l_p1: ControlPoint = p1;
        const l_p2: ControlPoint = (p2.mul(z)).sub(p1.mul(zmo));
        const l_p3: ControlPoint = (p3.mul(z2)).sub(p2.mul(2.0*z*zmo)).add(p1.mul(zmo2));
        const l_p4: ControlPoint = (p4.mul(z3)).sub(p3.mul(3.0*z2*zmo)).add(p2.mul(3.0*z*zmo2)).sub(p1.mul(zmo3));

        const r_p1: ControlPoint = l_p4;
        const r_p2: ControlPoint = (p4.mul(z2)).sub(p3.mul(2.0*z*zmo)).add(p2.mul(zmo2));
        const r_p3: ControlPoint = (p4.mul(z)).sub(p3.mul(zmo));
        const r_p4: ControlPoint = p4;

        return .{
            //left 
            .{
                .p0 = l_p1,
                .p1 = l_p2,
                .p2 = l_p3,
                .p3 = l_p4,
            },

            //right
            .{
                .p0 = r_p1,
                .p1 = r_p2,
                .p2 = r_p3,
                .p3 = r_p4,
            }

        };

        // return .{
        //
        //     // left ('earlier') segment
        //     .{
        //         .p0 = self.p0,
        //         .p1 = (self.p1.mul(unorm)  ).sub(self.p0.mul(un_sub)),
        //         .p2 = (self.p2.mul(unorm_2)).sub(self.p1.mul(2*unorm*un_sub)  ).add(self.p0.mul(un_sub_2)),
        //         .p3 = (self.p3.mul(unorm_3)).sub(self.p2.mul(3*unorm_2*un_sub)).add(self.p1.mul(3*unorm*un_sub_2)).sub(self.p0.mul(un_sub_3)),
        //     },
        //     
        //     // right segment (later)
        //     .{
        //         .p0 = (self.p3.mul(unorm_3)).sub(self.p2.mul(3*unorm_2*un_sub)).add(self.p1.mul(3*unorm*un_sub_2)).sub(self.p0.mul(un_sub_3)),
        //         .p1 = (self.p3.mul(unorm_2)).sub(self.p2.mul(2*unorm*un_sub)  ).add(self.p1.mul(un_sub_2)), 
        //         .p2 = (self.p3.mul(unorm)  ).sub(self.p2.mul(un_sub)),
        //         .p3 = self.p3,
        //
        //    }
        // };
    }

    pub fn control_hull(self: @This()) [3][2]ControlPoint {
        return .{
            .{ self.p0, self.p1 },
            .{ self.p1, self.p2 },
            .{ self.p2, self.p3 },
            // .{ self.p3, self.p0 },
        };
    }

    pub fn extents(self: @This()) [2]ControlPoint {
        var min: ControlPoint = self.p0;
        var max: ControlPoint = self.p0;

        inline for ([3][]const u8{"p1", "p2", "p3"}) |field| {
            const pt = @field(self, field);
            min = .{
                .time = std.math.min(min.time, pt.time),
                .value = std.math.min(min.value, pt.value),
            };
            max = .{
                .time = std.math.max(max.time, pt.time),
                .value = std.math.max(max.value, pt.value),
            };
        }

        return .{ min, max };
    }

    pub fn linear_length(self: @This()) f32 
    {
        return distance(self.p0, self.p3);
    }

    pub fn can_project(
        self: @This(),
        segment_to_project: Segment
    ) bool {
        const my_extents = self.extents();
        const other_extents = segment_to_project.extents();
        //
        // var fst_test = other_extents[0].value >= my_extents[0].time - generic_curve.EPSILON;
        // _ = fst_test;
        //
        // var snd_test = other_extents[1].value < my_extents[1].time + generic_curve.EPSILON;
        // _ = snd_test;
        //
        return (
            other_extents[0].value >= my_extents[0].time - generic_curve.EPSILON
            and other_extents[1].value < my_extents[1].time + generic_curve.EPSILON
        );
    }

    /// assuming that segment_to_project is contained by self, project the 
    /// points of segment_to_project through self
    pub fn project_segment(
        self: @This(),
        segment_to_project: Segment
    ) Segment
    {
        var result: Segment = undefined;

        inline for ([4][]const u8{"p0", "p1", "p2", "p3"}) |field| {
            const pt = @field(segment_to_project, field);
            @field(result, field) = .{
                .time = pt.time,
                .value = self.eval_at_x(pt.value),
            };
        }

        return result;
    }

    /// @TODO: this function only works if the value is increasing over the 
    ///        segment.  The monotonicity and increasing -ness of a segment
    ///        is guaranteed for time, but not for the value coordinate.
    pub fn findU_value(self:@This(), tgt_value: f32) f32 {
        return bezier_math.findU(
            tgt_value,
            self.p0.value,
            self.p1.value,
            self.p2.value,
            self.p3.value,
        );
    }

    pub fn findU_input(self:@This(), input_ordinate: f32) f32 {
        return bezier_math.findU(
            input_ordinate,
            self.p0.time,
            self.p1.time,
            self.p2.time,
            self.p3.time,
        );
    }

    // returns the y-value for the given x-value
    pub fn eval_at_x(self: @This(), x:f32) f32 {
        const u:f32 = bezier_math.findU(
            x,
            self.p0.time,
            self.p1.time,
            self.p2.time,
            self.p3.time
        );
        return self.eval_at(u).value;
    }

    pub fn debug_json_str(
        self: @This()
    ) []const u8 
    {
        return std.fmt.allocPrint(
            ALLOCATOR,
            \\
            \\{{
            \\    "p0": {{ "time": {d:.6}, "value": {d:.6} }},
            \\    "p1": {{ "time": {d:.6}, "value": {d:.6} }},
            \\    "p2": {{ "time": {d:.6}, "value": {d:.6} }},
            \\    "p3": {{ "time": {d:.6}, "value": {d:.6} }}
            \\}}
            \\
            ,
            .{
                self.p0.time, self.p0.value,
                self.p1.time, self.p1.value,
                self.p2.time, self.p2.value,
                self.p3.time, self.p3.value,
            }
        ) catch unreachable;
    }

    pub fn debug_print_json(
        self: @This()
    ) void 
    {
        std.debug.print("\ndebug_print_json] p0: {}\n", .{ self.p0});
        std.debug.print("{s}", .{ self.debug_json_str()});
    }
};

test "Segment: can_project test" {
    const half = create_linear_segment(
        .{ .time = -0.5, .value = -0.25, },
        .{ .time = 0.5, .value = 0.25, },
    );
    const double = create_linear_segment(
        .{ .time = -0.5, .value = -1, },
        .{ .time = 0.5, .value = 1, },
    );

    try expectEqual(true, double.can_project(half));
    try expectEqual(false, half.can_project(double));
}

test "Segment: debug_str test" {
    const seg = create_linear_segment(
        .{.time = -0.5, .value = -0.5},
        .{.time =  0.5, .value = 0.5},
    );

    const result: []const u8=
        \\
        \\{
        \\    "p0": { "time": -0.500000, "value": -0.500000 },
        \\    "p1": { "time": -0.166667, "value": -0.166667 },
        \\    "p2": { "time": 0.166667, "value": 0.166667 },
        \\    "p3": { "time": 0.500000, "value": 0.500000 }
        \\}
        \\
    ;

    try expectEqualStrings(result, seg.debug_json_str());
}

fn _is_approximately_linear(
    segment: Segment,
    tolerance: f32
) bool 
{
    const u = (segment.p1.mul(3.0)).sub(segment.p0.mul(2.0)).sub(segment.p3);
    var ux = u.time * u.time;
    var uy = u.value * u.value;

    const v = (segment.p2.mul(3.0)).sub(segment.p3.mul(2.0)).sub(segment.p0);
    const vx = v.time * v.time;
    const vy = v.value * v.value;

    if (ux < vx) {
        ux = vx;
    }
    if (uy < vy) {
        uy = vy;
    }

    return (ux+uy <= tolerance);

}

const LinearizeError = error { OutOfMemory };

/// Based on this paper:
/// https://citeseerx.ist.psu.edu/viewdoc/download?doi=10.1.1.86.162&rep=rep1&type=pdf
/// return a list of segments that approximate the segment with the given tolerance
///
/// ASSUMES THAT ALL POINTS ARE FINITE
pub fn linearize_segment(
    segment: Segment,
    tolerance:f32,
    // @TODO this shouldn't return an arraylist
) error{OutOfMemory}!std.ArrayList(ControlPoint) 
{
    // @TODO: this function should compute and preserve the derivatives on the
    //        bezier segments
    var result: std.ArrayList(ControlPoint) = (
        std.ArrayList(ControlPoint).init(ALLOCATOR)
    );

    // terminal condition
    if (_is_approximately_linear(segment, tolerance)) {
        try result.append(segment.p0);
        try result.append(segment.p3);

        return result;
    }

    const subsegments = segment.split_at(0.5);

    try result.appendSlice((try linearize_segment(subsegments[0], tolerance)).items);
    try result.appendSlice((try linearize_segment(subsegments[1], tolerance)).items);

    return result;
}

test "segment: linearize basic test" {
    const segment = try read_segment_json("segments/upside_down_u.json");
    var linearized_knots = try linearize_segment(segment, 0.01);

    try expectEqual(@as(usize, 8*2), linearized_knots.items.len);

    linearized_knots = try linearize_segment(segment, 0.000001);
    try expectEqual(@as(usize, 68*2), linearized_knots.items.len);

    linearized_knots = try linearize_segment(segment, 0.00000001);
    try expectEqual(@as(usize, 256*2), linearized_knots.items.len);
}

test "segment from point array" {

    const original_knots_ident: [4]ControlPoint = .{
            .{ .time = -0.5,     .value = -0.5},
            .{ .time = -0.16666, .value = -0.16666},
            .{ .time = 0.166666, .value = 0.16666},
            .{ .time = 0.5,      .value = 0.5}
    };
    const ident = Segment.from_pt_array(original_knots_ident);

    try expectApproxEql(@as(f32, 0), ident.eval_at(0.5).value);

    const linearized_ident_knots = try linearize_segment(ident, 0.01);
    try expectEqual(@as(usize, 2), linearized_ident_knots.items.len);

    try expectApproxEql(
        original_knots_ident[0].time,
        linearized_ident_knots.items[0].time
    );
    try expectApproxEql(
        original_knots_ident[0].value,
        linearized_ident_knots.items[0].value
    );

    try expectApproxEql(
        original_knots_ident[3].time,
        linearized_ident_knots.items[1].time
    );
    try expectApproxEql(
        original_knots_ident[3].value,
        linearized_ident_knots.items[1].value
    );
}

test "segment: linearize already linearized curve" {
    const segment = try read_segment_json("segments/linear.json");
    const linearized_knots = try linearize_segment(segment, 0.01);

    // already linear!
    try expectEqual(@as(usize, 2), linearized_knots.items.len);
}

pub fn read_segment_json(file_path: latin_s8) !Segment {
    const fi = try std.fs.cwd().openFile(file_path, .{});
    defer fi.close();

    const source = try fi.readToEndAlloc(ALLOCATOR, std.math.maxInt(u32));
    var stream = std.json.TokenStream.init(source);

    return try std.json.parse(Segment, &stream, .{});
}

test "segment: eval_at_x and findU test over linear curve" {
    const seg = create_linear_segment(
        .{.time = 2, .value = 2},
        .{.time = 3, .value = 3},
    );

    inline for ([_]f32{2.1, 2.2, 2.3, 2.5, 2.7}) |coord| {
        try expectApproxEql(coord, seg.eval_at_x(coord));
    }
}


pub fn create_linear_segment(p0: ControlPoint, p1: ControlPoint) Segment {
    if (p1.time >= p0.time) {
        return .{
            .p0 = p0,
            .p1 = bezier_math.lerp_cp(1.0/3.0, p0, p1),
            .p2 = bezier_math.lerp_cp(2.0/3.0, p0, p1),
            .p3 = p1,
        };
    }

    debug_panic(
        "Create bezier segment failed, {}, {}\n",
        .{p0.time, p1.time}
    );
}

pub fn create_identity_segment(t0: f32, t1: f32) Segment {
    return create_linear_segment(
        .{ .time = t0, .value = t0 },
        .{ .time = t1, .value = t1 }
    );
}

test "create_identity_segment check cubic spline" {
    // ensure that points are along line even for linear case
    const seg = create_identity_segment(0, 1);

    try expectEqual(@as(f32, 0), seg.p0.time);
    try expectEqual(@as(f32, 0), seg.p0.value);
    try expectEqual(@as(f32, 1.0/3.0), seg.p1.time);
    try expectEqual(@as(f32, 1.0/3.0), seg.p1.value);
    try expectEqual(@as(f32, 2.0/3.0), seg.p2.time);
    try expectEqual(@as(f32, 2.0/3.0), seg.p2.value);
    try expectEqual(@as(f32, 1), seg.p3.time);
    try expectEqual(@as(f32, 1), seg.p3.value);
}

pub fn create_bezier_segment(
    p0: ControlPoint,
    p1: ControlPoint,
    p2: ControlPoint,
    p3: ControlPoint
) Segment {
    if (p3.time >= p2.time and p2.time >= p1.time and p1.time >= p0.time) {
        return .{
            .p0 = p0,
            .p1 = p1,
            .p2 = p2,
            .p3 = p3,
        };
    }

    debug_panic(
        "Create bezier segment failed, {}, {}, {}, {}\n",
        .{p0.time, p1.time, p2.time, p3.time}
    );
}

/// TimeCurve maps an input time to an output time.
///
/// The TimeCurve is a sequence of 2d cubic bezier segments,
/// closed at the start, and open at the end, where each
/// segment is met by the previous one.
///
/// The evaluation of a TimeCurve (S0, S1, ... Sn) at t, is
/// therefore t if t < S0.p0.time or t >= S0.p3.time. Otherwise,
/// the segment S whose interval [S.p0.time, S.p3.time) contains t
/// is evaluated according to the cubic Bezier equations.
///
/// @TODO: we would like to break this down by curve parameterization
///             - CubicBezierCurve1d/CubicBezierSegment1d (current implementation)
///                 - can be linearized into a LinearBezierCurve1d
///                 - can be projected _through_ but not itself projected
///                   without linearization
///             - LinearBezierCurve1d/LinearBezierSegment1d
///                 - optimization, but also invertible and projectible!
///             - IdentityCurve1d
///                 - defined over the entire continuum, or within given bounds
///                 - convienent for interval->timecurve
///             - NullCurve1d
///                 - out of bounds everywhere
///                 - so that topologies can have "holes"
///            IdentityCurve1d and NullCurve1d
///            ... but it isn't urgent, I think this can wait
///
///            ... there are other procedural curves that we may want to encode:
///            - mono hermite
///            - step function
///
pub const TimeCurve = struct {
    // according to the evaluation specification, an empty
    // timecurve evaluates t as t, everywhere.
    segments: []Segment = &.{},

    pub fn init(
        segments: []const Segment
    ) error{OutOfMemory}!TimeCurve 
    {
        return TimeCurve{ .segments = try ALLOCATOR.dupe(Segment, segments) };
    }

    pub fn deinit(self: @This(), allocator: std.mem.Allocator) void {
        allocator.free(self.segments);
    }

    pub fn init_from_linear_curve(crv: linear_curve.TimeCurveLinear) TimeCurve {
        var result = std.ArrayList(Segment).init(ALLOCATOR);

        for (crv.knots[0..crv.knots.len-1]) 
            |knot, index| 
        {
            const next_knot = crv.knots[index+1];
            result.append(create_linear_segment(knot, next_knot)) catch unreachable;
        }

        return TimeCurve{ .segments = result.items };
    }

    /// evaluate the curve at time t in the space of the curve
    pub fn evaluate(self: @This(), t_arg: f32) error{OutOfBounds}!f32 {
        const seg_ptr = self.find_segment(t_arg);
        if (seg_ptr) |seg| {
            return seg.eval_at_x(t_arg);
        }
        return error.OutOfBounds;
    }

    pub fn find_segment_index(self: @This(), t_arg: f32) ?usize {
        if (self.segments.len == 0 or
            t_arg < self.segments[0].p0.time or
            t_arg >= self.segments[self.segments.len - 1].p3.time)
        {
            return null;
        }

        // quick check if it is exactly the start time of the first segment
        if (t_arg == self.segments[0].p0.time) {
            return 0;
        }

        for (self.segments) |seg, index| {
            if (seg.p0.time <= t_arg and t_arg < seg.p3.time) {
                // exactly in a segment
                return index;
            }
        }

        // between segments, identity
        return null;
    }

    pub fn find_segment(self: @This(), t_arg: f32) ?*Segment {
        if (self.find_segment_index(t_arg)) |ind| {
            return &self.segments[ind];
        }

        return null;
    }

    pub fn insert(self: @This(), seg: Segment) void {
        const conflict = find_segment(seg.p0.time);
        if (conflict != null)
            unreachable;

        self.segments.append(seg);
        std.sort(
            Segment,
            self.segments.to_slice(),
            generic_curve.cmpSegmentsByStart
        );
    }

    pub fn linearized(self: @This()) linear_curve.TimeCurveLinear {
        var linearized_knots = std.ArrayList(ControlPoint).init(ALLOCATOR);

        // @NOTE NICK: this is a good place to start adding in the holodromes

        // @TODO: find the holodromes first, then linearize the holodromes
        //        ...because any critical point will want a linearized knot

        for (self.segments) |seg| {
            // @TODO: expose the tolerance as a parameter(?)
            linearized_knots.appendSlice(
                (
                 linearize_segment(seg, 0.000001) catch unreachable
                ).items
            ) catch unreachable;
        }

        return .{
            .knots = linearized_knots.items
        };
    }

    /// project another curve through this one.  A curve maps 'time' to 'value'
    /// parameters.  if curve self is v_self(t_self), and curve other is 
    /// v_other(t_other) and other is being projected through self, the result
    /// function is v_self(v_other(t_other)).  This maps the the v_other value
    /// to the t_self parameter.
    ///
    /// curve self:
    /// 
    /// v_self
    /// |  /
    /// | /
    /// |/
    /// +--- t_self
    ///
    /// curve other:
    ///   
    ///  v_other
    /// |      ,-'
    /// |   ,-'
    /// |,-'
    /// +---------- t_other
    ///
    /// @TODO finish this doc
    ///
    pub fn project_curve(
        self: @This(),
        other: TimeCurve
        // should return []TimeCurve
    ) []linear_curve.TimeCurveLinear
    {
        // @TODO: should use holodromes for projection rather than
        //        linearization
        const l_proj_thru = self.linearized();
        const l_to_proj = other.linearized();

        return l_proj_thru.project_curve(l_to_proj);
    }

    pub fn debug_json_str(self:@This()) []const u8
    {
        var str = std.ArrayList(u8).init(ALLOCATOR);
        std.json.stringify(self, .{}, str.writer()) catch unreachable; 
        return str.items;
    }

    pub fn extents_time(self:@This()) ContinuousTimeInterval {
        return .{
            .start_seconds = self.segments[0].p0.time,
            .end_seconds = self.segments[self.segments.len - 1].p3.time,
        };
    }

    pub fn extents(self:@This()) [2]ControlPoint {
        var min:ControlPoint = self.segments[0].p0;
        var max:ControlPoint = self.segments[0].p3;

        for (self.segments) |seg| {
            const seg_extents = seg.extents();
            min = .{
                .time = std.math.min(min.time, seg_extents[0].time),
                .value = std.math.min(min.value, seg_extents[0].value),
            };
            max = .{
                .time = std.math.max(min.time, seg_extents[1].time),
                .value = std.math.max(min.value, seg_extents[1].value),
            };
        }
        return .{ min, max };
    }

    /// returns a copy of self which is split in the segment which overlaps
    /// the ordinate at the ordinate in the input space.
    ///
    /// Example:
    /// Curve has three segments [0, 3)[0, 10)[0, 4)
    /// ordinate: 5
    ///
    /// result:
    /// [0, 3)[0, 5)[5, 10)[0, 4)
    pub fn split_at_input_ordinate(
        self:@This(),
        ordinate:f32,
        allocator: std.mem.Allocator,
    ) !TimeCurve 
    {
        const maybe_seg_to_split_index = self.find_segment_index(ordinate);
        if (maybe_seg_to_split_index == null) {
            return error.OutOfBounds;
        }
        const seg_to_split_index = maybe_seg_to_split_index.?;

        var split_segments = self.segments[seg_to_split_index].split_at(ordinate);

        var new_segments = try allocator.alloc(Segment, self.segments.len + 1);

        var before_split_src = self.segments[0..seg_to_split_index];
        var after_split_src = self.segments[seg_to_split_index+1..];

        var before_split_dest = new_segments[0..seg_to_split_index];
        var after_split_dest = new_segments[seg_to_split_index+2..];

         std.mem.copy(Segment, before_split_dest, before_split_src);
         new_segments[seg_to_split_index] = split_segments[0];
         new_segments[seg_to_split_index+1] = split_segments[1];
         std.mem.copy(Segment, after_split_dest, after_split_src);

        return .{ .segments = new_segments };
    }

    const TrimDir = enum {
        trim_before,
        trim_after,
    };

    pub fn trimmed_from_input_ordinate(
        self: @This(),
        ordinate: f32,
        direction: TrimDir,
        allocator: std.mem.Allocator,
    ) !TimeCurve {
        const seg_to_split_index = (
            self.find_segment_index(ordinate)
        ) orelse {
            return error.OutOfBounds;
        };

        const seg_to_split = self.segments[seg_to_split_index]; 

        {
            const is_bounding_point = (
                std.math.approxEqAbs(
                    @TypeOf(ordinate),
                    seg_to_split.p0.time, 
                    ordinate,
                    0.00001,
                )
                or std.math.approxEqAbs(
                    @TypeOf(ordinate),
                    seg_to_split.p3.time, 
                    ordinate,
                    0.00001,
                )
            );

            if (is_bounding_point) {
                return .{
                    .segments =  try allocator.dupe(Segment, self.segments) 
                };
            }
        }

        const unorm = seg_to_split.findU_input(ordinate);

        const split_segments = seg_to_split.split_at(unorm);

        var new_segments:[]Segment = undefined;

        switch (direction) {
            // keep later stuff
            .trim_before => {
                const new_split = split_segments[1];
                const segments_to_copy = self.segments[seg_to_split_index+1..];

                new_segments = try allocator.alloc(
                    Segment,
                    segments_to_copy.len + 1
                );

                new_segments[0] = new_split;
                std.mem.copy(Segment, new_segments[1..], segments_to_copy);
            },
            // keep earlier stuff
            .trim_after => {
                const new_split = split_segments[0];
                const segments_to_copy = self.segments[0..seg_to_split_index];

                new_segments = try allocator.alloc(
                    Segment,
                    segments_to_copy.len + 1
                );

                std.mem.copy(
                    Segment,
                    new_segments[0..segments_to_copy.len],
                    segments_to_copy
                );
                new_segments[new_segments.len - 1] = new_split;
            },
        }

        return .{ .segments = new_segments };
    }

    /// returns a copy of self, trimmed by bounds.  If bounds are greater than 
    /// the bounds of the existing curve, an unaltered copy is returned.  
    /// Otherwise the curve is copied, and trimmed to fit the bounds.
    pub fn trimmed_in_input_space(
        self: @This(),
        bounds: ContinuousTimeInterval,
        allocator: std.mem.Allocator,
    ) !TimeCurve {
        // @TODO; implement this using slices of a larger segment buffer to
        //        reduce the number of allocations/copies
        var front_split = try self.trimmed_from_input_ordinate(
            bounds.start_seconds,
            .trim_before,
            allocator
        );
        defer front_split.deinit(allocator);

        // todo - does the above trim reset the origin on the input space?
        var result = try front_split.trimmed_from_input_ordinate(
            bounds.end_seconds,
            .trim_after,
            allocator,
        );

        return result;
    }

    /// split the segments on their first derivative roots, return a new curve
    /// with all the split segments and copies of the segments that were not
    /// split, memory is owned by the caller
    pub fn split_on_critical_points(
        self: @This(),
        allocator: std.mem.Allocator
    ) !TimeCurve 
    {
        var cSeg : hodographs.BezierSegment = .{
            .order = 3,
            .p = .{},
        };

        var split_segments = std.ArrayList(Segment).init(allocator);

        for (self.segments) |seg, seg_index| {
            errdefer std.debug.print("seg_index: {}\n", .{seg_index});
            const ind = seg_index;
            _ = ind;
            for (seg.points()) |pt, index| {
                cSeg.p[index].x = pt.time;
                cSeg.p[index].y = pt.value;
            }

            // XXX: HACK
            // hodographs algorithm is sensitive to end points y-coordinate 
            // being equivalent, needs to drop to a lower order of the curve
            // to compute the root correctly in this case
            if (cSeg.p[0].y == cSeg.p[3].y) {
                cSeg.p[0].y += 0.0001;
            }

            var hodo = hodographs.compute_hodograph(&cSeg);
            const roots = hodographs.bezier_roots(&hodo);

            if (roots.x > 0 and roots.x < 1) {
                const xsplits = seg.split_at(roots.x);
                try split_segments.appendSlice(&xsplits);

                if (roots.y > 0 and roots.y < 1) {
                    const ysplits = seg.split_at(roots.y);
                    try split_segments.appendSlice(&ysplits);
                }
            } else {
                try split_segments.append(seg);
            }
        }

        return .{ .segments = split_segments.items };
    }
};

pub fn read_curve_json(
    file_path: latin_s8,
    allocator_:std.mem.Allocator
) !TimeCurve 
{
    const fi = try std.fs.cwd().openFile(file_path, .{});
    defer fi.close();

    const source = try fi.readToEndAlloc(allocator_, std.math.maxInt(u32));
    defer allocator_.free(source);

    var stream = std.json.TokenStream.init(source);

    return try std.json.parse(TimeCurve, &stream, .{ .allocator = allocator_ });
}

test "Curve: read_curve_json" {
    const curve = try read_curve_json("curves/linear.curve.json", std.testing.allocator);
    defer std.testing.allocator.free(curve.segments);

    try expectEqual(@as(usize, 1), curve.segments.len);

    // first segment should already be linear
    const segment = curve.segments[0];

    const linearized_knots = try linearize_segment(segment, 0.01);

    // already linear!
    try expectEqual(@as(usize, 2), linearized_knots.items.len);
}

test "Segment: projected_segment to 1/2" {
    const half = create_linear_segment(
        .{ .time = -0.5, .value = -0.25, },
        .{ .time = 0.5, .value = 0.25, },
    );
    const double = create_linear_segment(
        .{ .time = -0.5, .value = -1, },
        .{ .time = 0.5, .value = 1, },
    );

    const half_through_double = double.project_segment(half);

    var u:f32 = 0.0;
    while (u<1) {
        try expectApproxEql(u-0.5, half_through_double.eval_at(u).value);
        u+=0.1;
    }
}

// test "TimeCurve: string json" {
//     const xform_curve: TimeCurve = .{
//         .segments = &.{
//             create_linear_segment(
//                 .{ .time = 1, .value = 0, },
//                 .{ .time = 2, .value = 1, },
//             )
//         }
//     };
//
//     std.debug.print("\n{s}\n", .{ xform_curve.debug_json_str()});
// }

test "TimeCurve: positive length 1 linear segment test" {
    const xform_curve: TimeCurve = .{
        .segments = &[1]Segment{
            create_linear_segment(
                .{ .time = 1, .value = 0, },
                .{ .time = 2, .value = 1, },
            )
        }
    };

    // out of range returns error.OutOfBounds
    try expectError(error.OutOfBounds, xform_curve.evaluate(2));
    try expectError(error.OutOfBounds, xform_curve.evaluate(3));
    try expectError(error.OutOfBounds, xform_curve.evaluate(0));

    // find segment
    try expect(xform_curve.find_segment(1) != null);
    try expect(xform_curve.find_segment(1.5) != null);
    try expectEqual(@as(?*Segment, null), xform_curve.find_segment(2));

    // within the range of the curve
    try expectEqual(@as(f32, 0),    try xform_curve.evaluate(1));
    try expectEqual(@as(f32, 0.25), try xform_curve.evaluate(1.25));
    try expectEqual(@as(f32, 0.5),  try xform_curve.evaluate(1.5));
    try expectEqual(@as(f32, 0.75), try xform_curve.evaluate(1.75));
}

test "TimeCurve: projection_test - compose to identity" {
    var seg_0_4 = [_]Segment{
        create_linear_segment(
            .{ .time = 0, .value = 0, },
            .{ .time = 4, .value = 8, },
        ) 
    };
    const fst: TimeCurve = .{ .segments = &seg_0_4 };

    var seg_0_8 = [_]Segment{
        create_linear_segment(
            .{ .time = 0, .value = 0, },
            .{ .time = 8, .value = 4, },
        )
    };
    const snd: TimeCurve = .{ .segments = &seg_0_8 };

    // check linearization first
    const fst_lin = fst.linearized();
    try expectEqual(@as(usize, 2), fst_lin.knots.len);
    const snd_lin = snd.linearized();
    try expectEqual(@as(usize, 2), snd_lin.knots.len);

    // @breakpoint();
    const results = fst.project_curve(snd);
    try expectEqual(@as(usize, 1), results.len);

    if (results.len > 0) {
        const result = results[0];
        try expectEqual(@as(usize, 1), result.segments.len);

        var x:f32 = 0;
        while (x < 1) {
            // @TODO: fails because evaluating a linear curve
            try expectApproxEql(x, try result.evaluate(x));
            x += 0.1;
        }
    }
}

test "TimeCurve: projection_test non-overlapping" {
    var seg_0_1 = [_]Segment{ create_identity_segment(0, 1) };
    const fst: TimeCurve = .{ .segments = &seg_0_1 };

    var seg_1_9 = [_]Segment{ 
        create_linear_segment(
            .{ .time = 1, .value = 1, },
            .{ .time = 9, .value = 5, },
        )
    };
    const snd: TimeCurve = .{ .segments = &seg_1_9 };

    const result = fst.project_curve(snd);

    try expectEqual(@as(usize, 0), result.len);
}

test "positive slope 2 linear segment test" {
    var test_segment_arr = [_]Segment{
        create_linear_segment(
            .{ .time = 1, .value = 0, },
            .{ .time = 2, .value = 2, },
        )
    };
    const xform_curve = TimeCurve{ .segments = &test_segment_arr };

    try expectEqual(@as(f32, 0),   try xform_curve.evaluate(1));
    try expectEqual(@as(f32, 0.5), try xform_curve.evaluate(1.25));
    try expectEqual(@as(f32, 1),   try xform_curve.evaluate(1.5));
    try expectEqual(@as(f32, 1.5), try xform_curve.evaluate(1.75));
}

test "negative length 1 linear segment test" {
    // declaring the segment here means that the memory management is handled
    // by stack unwinding
    var segments_xform = [_]Segment{
        create_linear_segment(
            .{ .time = -2, .value = 0, },
            .{ .time = -1, .value = 1, },
        )
    };
    const xform_curve = TimeCurve{ .segments = &segments_xform };

    // outside of the range should return the original result
    // (identity transform)
    try expectError(error.OutOfBounds, xform_curve.evaluate(0));
    try expectError(error.OutOfBounds, xform_curve.evaluate(-3));
    try expectError(error.OutOfBounds, xform_curve.evaluate(-1));

    // within the range
    try expectEqual(try xform_curve.evaluate(-2), 0);
    try expectApproxEql(try xform_curve.evaluate(-1.5), 0.5);
}

fn line_orientation(test_point: ControlPoint, segment: Segment) f32 {
    const v1 = ControlPoint {
        .time  = test_point.time  - segment.p0.time,
        .value = test_point.value - segment.p0.value,
    };

    const v2 = ControlPoint {
        .time  = segment.p3.time  - segment.p0.time,
        .value = segment.p3.value - segment.p0.value,
    };

    return (v1.time * v2.value - v1.value * v2.time);
}

fn sub(lhs: ControlPoint, rhs: ControlPoint) ControlPoint {
    return .{
        .time= rhs.time - lhs.time,
        .value= rhs.value - lhs.value,
    };
}

test "convex hull test" {
    const segment = create_bezier_segment(
        .{ .time = 1, .value = 0, },
        .{ .time = 1.25, .value = 1, },
        .{ .time = 1.75, .value = 0.65, },
        .{ .time = 2, .value = 0.24, },
    );

    const p0 = segment.p0;
    const p1 = segment.p1;
    var p2 = segment.p2;
    var p3 = segment.p3;

    const left_bound_segment = create_linear_segment(p0, p1);
    var right_bound_segment = create_linear_segment(p2, p3);

    // swizzle the right if necessary
    if (line_orientation(p0, right_bound_segment) < 0) {
        const tmp = p3;
        p3 = p2;
        p2 = tmp;
        right_bound_segment = create_linear_segment(p2, p3);
    }

    const top_bound_segment = create_linear_segment(p1, p2);

    // NOTE: reverse the winding order because linear segment requires the 
    //       second point be _after_ the first in time
    const bottom_bound_segment = create_linear_segment(p0, p3);

    var i: f32 = 0;
    while (i <= 1) {
        var test_point = segment.eval_at(i);

        try expect(line_orientation(test_point, left_bound_segment) >= 0);
        try expect(line_orientation(test_point, top_bound_segment) >= 0);
        try expect(line_orientation(test_point, right_bound_segment) >= 0);

        // because the winding order is reversed, this sign is reversed
        // the winding order is reversed on bottom_bound_segment because
        // we require that the points in the bezier be ordered, which
        // violates the winding order of the algorithm
        try expect(line_orientation(test_point, bottom_bound_segment) <= 0);

        i += 0.1;
    }
}


test "Segment: eval_at for out of range u" {
    var seg = [1]Segment{create_identity_segment(3, 4)};
    const tc = TimeCurve{ .segments = &seg};

    try expectError(error.OutOfBounds, tc.evaluate(0));
    // right open intervals means the end point is out
    try expectError(error.OutOfBounds, tc.evaluate(4));
    try expectError(error.OutOfBounds, tc.evaluate(5));
}

pub fn write_json_file(json_blob: []const u8, to_fpath: []const u8) !void {
    const file = try std.fs.cwd().createFile(
        to_fpath,
        .{ .read = true },
    );
    defer file.close();

    try file.writeAll(json_blob);
}

pub fn write_json_file_curve(curve: anytype, to_fpath: []const u8) !void {
    try write_json_file(curve.debug_json_str(), to_fpath);
}

test "json writer: curve" {
    const ident = try TimeCurve.init(
        &.{ create_identity_segment(-20, 30) }
    );
    const fpath = "/var/tmp/test.curve.json";

    try write_json_file_curve(ident, fpath);

    const file = try std.fs.cwd().openFile(fpath, .{ .mode = .read_only },);
    defer file.close();

    var buffer: [2048]u8 = undefined;
    try file.seekTo(0);
    const bytes_read = try file.readAll(&buffer);

    try expectEqualStrings(buffer[0..bytes_read], ident.debug_json_str());
}

test "segment: findU_value" {
    const test_segment = create_identity_segment(1,2);
    try expectEqual(@as(f32, 0.5), test_segment.findU_value(1.5));
    try expectEqual(@as(f32, 0), test_segment.findU_value(0.5));
    try expectEqual(@as(f32, 1), test_segment.findU_value(2.5));

    // const test_segment_inv = create_linear_segment(
    //     .{ .time = 1, .value = 2 },
    //     .{ .time = 2, .value = 1 }
    // );

    // @TODO: this might be a legit bug in the root finder?
    // try expectEqual(@as(f32, 0.5), test_segment_inv.findU_value(1.5));
    // try expectEqual(@as(f32, 1),   test_segment_inv.findU_value(0.5)); // returns 0?
    // try expectEqual(@as(f32, 0),   test_segment_inv.findU_value(2.5)); // returns 1?
}

test "TimeCurve: project u loop bug" {
    const simple_s_segments = [_]Segment{
        create_linear_segment(
            .{ .time = 0, .value = 0},
            .{ .time = 30, .value = 10},
        ),
        create_linear_segment(
            .{ .time = 30, .value = 10},
            .{ .time = 60, .value = 90},
        ),
        create_linear_segment(
            .{ .time = 60, .value = 90},
            .{ .time = 100, .value = 100},
        ),
    };
    const simple_s = try TimeCurve.init(&simple_s_segments);

    const u_seg = [_]Segment{
        Segment{
            .p0 = .{ .time = 0, .value = 0 },
            .p1 = .{ .time = 0, .value = 100 },
            .p2 = .{ .time = 100, .value = 100 },
            .p3 = .{ .time = 100, .value = 0 },
        },
    }; 
    const upside_down_u = try TimeCurve.init(&u_seg);

    const result : []TimeCurve = simple_s.project_curve(upside_down_u);

    _ = result;
}

test "TimeCurve: split_at_input_ordinate" {

    const test_curves = [_]TimeCurve{
        try TimeCurve.init(&.{ create_identity_segment(-20, 30) }),
        try read_curve_json("curves/upside_down_u.curve.json", std.testing.allocator), 
        try read_curve_json("curves/scurve.curve.json", std.testing.allocator), 
    };

    defer test_curves[1].deinit(std.testing.allocator);
    defer test_curves[2].deinit(std.testing.allocator);

    for (test_curves) |ident| {
        const extents = ident.extents();
        var split_loc:f32 = extents[0].time;

        while (split_loc < extents[1].time) : (split_loc += 1) {
            const split_ident = try ident.split_at_input_ordinate(
                split_loc,
                std.testing.allocator
            );
            defer split_ident.deinit(std.testing.allocator);

            try expectEqual(ident.segments.len + 1, split_ident.segments.len);

            // check that the end points are the same
            try expectEqual(
                ident.segments[0].p0.time,
                split_ident.segments[0].p0.time
            );
            try expectEqual(
                ident.segments[0].p3.time,
                split_ident.segments[1].p3.time
            );

            var i:f32 = extents[0].time;
            while (i < extents[1].time) : (i += 1) {
                const fst = try ident.evaluate(i);
                const snd = try split_ident.evaluate(i);
                errdefer std.log.err(
                    "Loop: {} orig: {} new: {}",
                    .{i, fst, snd}
                );
                try std.testing.expectApproxEqAbs(fst, snd, 0.001);
            }
        }
    }
}

test "TimeCurve: trimmed_from_input_ordinate" {
    const TestData = struct {
        // inputs
        ordinate:f32,
        direction: TimeCurve.TrimDir,

        // expected results
        result_extents:ContinuousTimeInterval,
        result_segment_count: usize,
    };

    const test_curves = [_]TimeCurve{
        try read_curve_json(
            "curves/linear_scurve_u.curve.json",
            std.testing.allocator
        ), 
        try TimeCurve.init(
            &.{
                create_identity_segment(-25, -5), 
                create_identity_segment(-5, 5), 
                create_identity_segment(5, 25), 
            }
        ),
    };

    defer test_curves[0].deinit(std.testing.allocator);

    for (test_curves) |ident, curve_index| {
        const extents = ident.extents();

        // assumes that curve is 0-centered
        const test_data = [_]TestData{
            // trim the first segment
            .{
                .ordinate = extents[0].time * 0.25,
                .direction = .trim_before,
                .result_extents = .{
                    .start_seconds = extents[0].time * 0.25,
                    .end_seconds = extents[1].time,
                },
                .result_segment_count = ident.segments.len,
            },
            .{
                .ordinate = extents[0].time * 0.25,
                .direction = .trim_after,
                .result_extents = .{
                    .start_seconds = extents[0].time,
                    .end_seconds = extents[0].time * 0.25,
                },
                .result_segment_count = 1,
            },
            // trim the last segment
            .{
                .ordinate = extents[1].time * 0.75,
                .direction = .trim_before,
                .result_extents = .{
                    .start_seconds = extents[1].time * 0.75,
                    .end_seconds = extents[1].time,
                },
                .result_segment_count = 1,
            },
            .{
                .ordinate = extents[1].time * 0.75,
                .direction = .trim_after,
                .result_extents = .{
                    .start_seconds = extents[0].time,
                    .end_seconds = extents[1].time * 0.75,
                },
                .result_segment_count = ident.segments.len,
            },
            // trim on an existing split
            .{
                .ordinate = ident.segments[0].p3.time,
                .direction = .trim_after,
                .result_extents = .{
                    .start_seconds = extents[0].time,
                    .end_seconds = extents[1].time,
                },
                .result_segment_count = ident.segments.len,
            },
        };

        for (test_data) |td, index| {
            errdefer std.debug.print(
                "\ncurve: {} / loop: {}\n",
                .{ curve_index, index }
            );

            const trimmed_curve = try ident.trimmed_from_input_ordinate(
                td.ordinate,
                td.direction,
                std.testing.allocator,
            );
            const trimmed_extents = trimmed_curve.extents();
            defer trimmed_curve.deinit(std.testing.allocator);

            errdefer std.debug.print(
                "\n test: {any}\n trimmed_extents: {any} \n\n",
                .{ td , trimmed_extents}
            );

            try std.testing.expectApproxEqAbs(
                td.result_extents.start_seconds,
                trimmed_extents[0].time,
                0.001
            );
            try std.testing.expectApproxEqAbs(
                td.result_extents.end_seconds,
                trimmed_extents[1].time,
                0.001
            );
        }
    }
}

test "TimeCurve: trimmed_in_input_space" {
    const TestData = struct {
        trim_range:ContinuousTimeInterval,
        result_extents:ContinuousTimeInterval,
    };

    const test_curves = [_]TimeCurve{
        try TimeCurve.init(&.{ create_identity_segment(-20, 30) }),
        try read_curve_json("curves/upside_down_u.curve.json", std.testing.allocator), 
        try read_curve_json("curves/scurve.curve.json", std.testing.allocator), 
    };

    defer test_curves[1].deinit(std.testing.allocator);
    defer test_curves[2].deinit(std.testing.allocator);

    for (test_curves) |ident| {
        const extents = ident.extents();

        const test_data = [_]TestData{
            // trim both
            .{
                .trim_range = .{
                    .start_seconds = extents[0].time * 0.25,
                    .end_seconds = extents[1].time * 0.75,
                },
                .result_extents = .{
                    .start_seconds = extents[0].time * 0.25,
                    .end_seconds = extents[1].time * 0.75,
                },
                },
            // trim start
            .{
                .trim_range = .{
                    .start_seconds = extents[0].time * 0.25,
                    .end_seconds = extents[1].time * 1.75,
                },
                .result_extents = .{
                    .start_seconds = extents[0].time * 0.25,
                    .end_seconds = extents[1].time,
                },
                },
            // trim end
            .{
                .trim_range = .{
                    .start_seconds = extents[0].time * 1.25,
                    .end_seconds = extents[1].time * 0.75,
                },
                .result_extents = .{
                    .start_seconds = extents[0].time,
                    .end_seconds = extents[1].time * 0.75,
                },
                },
            // trim neither
            .{
                .trim_range = .{
                    .start_seconds = extents[0].time * 1.25,
                    .end_seconds = extents[1].time * 1.75,
                },
                .result_extents = .{
                    .start_seconds = extents[0].time * 1.25,
                    .end_seconds = extents[1].time * 1.75,
                },
                },
            .{
                .trim_range = .{
                    .start_seconds = extents[0].time,
                    .end_seconds = extents[1].time,
                },
                .result_extents = .{
                    .start_seconds = extents[0].time,
                    .end_seconds = extents[1].time,
                },
                },
            };

        for (test_data) |td| {
            const trimmed_curve = try ident.trimmed_in_input_space(
                td.trim_range,
                std.testing.allocator
            );
            defer trimmed_curve.deinit(std.testing.allocator);

            const trimmed_extents = trimmed_curve.extents();

            try std.testing.expectApproxEqAbs(
                td.result_extents.start_seconds,
                trimmed_extents[0].time,
                0.001
            );
            try std.testing.expectApproxEqAbs(
                td.result_extents.end_seconds,
                trimmed_extents[1].time,
                0.001
            );
        }
    }
}
