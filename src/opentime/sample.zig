const std = @import("std");

const time_topology = @import("time_topology");
const util = @import("util.zig");
const curve = @import("curve");
const ALLOCATOR = @import("allocator.zig").ALLOCATOR;

const expectEqual = std.testing.expectEqual;
const expectApproxEqAbs = std.testing.expectApproxEqAbs;

// @{ Sample Interface
pub const Sample = struct {
    ordinate_seconds: f32 = 0,
    support_negative_seconds: f32 = 0,
    support_positive_seconds: f32 = 0,
};
// @}


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
        topology: time_topology.TimeTopology
    ) ![]Sample
    {
        var result: std.ArrayList(Sample) = (
            std.ArrayList(Sample).init(ALLOCATOR)
        );

        // @TODO:
        // I suspect a better way to do this is to project the numbers into a
        // space where integer math can be used.
        // -- Or the ratinoal time engine?
        var increment: f32 = 1/self.rate_hz;
        var current_coord = self.start_offset;
        const end_seconds = topology.bounds().end_seconds;

        // @breakpoint();

        while (current_coord < end_seconds - util.EPSILON) 
        {
            var next: Sample = .{
                .ordinate_seconds = current_coord,
                .support_negative_seconds = 0,
                .support_positive_seconds = increment
            };

            var tp_space: ?Sample = try topology.project_sample(next);

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
    var sample_rate: f32 = 24;

    const sample_generator = StepSampleGenerator{
        // should this be an absolute coordinate origin instead of an
        // offset?
        .start_offset = 100,
        .rate_hz = sample_rate,
    };

    // staircase with three steps in it
    var target_topology = try time_topology.TimeTopology.init_step_mapping(
        .{
            .start_seconds = 100,
            .end_seconds = 103,
        },
        100,
        1,
        1
    );

    var result = try sample_generator.sample_over(target_topology);
    var expected = target_topology.bounds().duration_seconds() * sample_rate;

    try expectApproxEqAbs(
        @as(f32, 102),
        result[result.len - 1].ordinate_seconds,
        util.EPSILON
    );

    try expectEqual(
        @intFromFloat(i32, @floor(expected)),
        @intCast(i32, result.len),
    );
}

test "StepSampleGenerator: sample over identity topology" 
{
    var sample_rate: f32 = 24;

    const sample_generator = StepSampleGenerator{
        .start_offset = 100,
        .rate_hz = sample_rate,
    };

    const target_topology = time_topology.TimeTopology.init_identity(
        .{ .bounds = .{ .start_seconds = 100, .end_seconds = 103 } }
    );
    var result = try sample_generator.sample_over(target_topology);

    var expected_last_coord = (
        target_topology.bounds().end_seconds 
        - 1/@as(f32, 24)
    );

    const result_s = result[result.len - 1];
    var actual_ordinate = result_s.ordinate_seconds;
    expectApproxEqAbs(
        expected_last_coord,
        actual_ordinate,
        util.EPSILON
    ) catch @breakpoint();

    var expected = target_topology.bounds().duration_seconds() * sample_rate;
    try expectEqual(
        @intFromFloat(i32, @floor(expected)),
        @intCast(i32, result.len),
    );
}
// @}
