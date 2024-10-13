//! TopologyMapping implementation

const std = @import("std");

const opentime = @import("opentime");
const mapping = @import("mapping.zig");

/// A Topology binds regions of a one dimensional space to a sequence of right
/// met monotonic mappings, separated by a list of end points.  There are
/// implicit "Empty" mappings outside of the end points which map to no values
/// before and after the segments defined by the Topology.
pub const TopologyMapping = struct {
    end_points_input: []const opentime.Ordinate,
    mappings: []const mapping.Mapping,

    pub fn init(
        allocator: std.mem.Allocator,
        in_mappings: []const mapping.Mapping,
    ) !TopologyMapping
    {
        var cursor : opentime.Ordinate = 0;

        var end_points = (
            std.ArrayList(opentime.Ordinate).init(allocator)
        );
        try end_points.ensureTotalCapacity(in_mappings.len + 1);
        errdefer end_points.deinit();

        try end_points.append(cursor);

        // validate mappings
        for (in_mappings)
            |in_m|
        {
            const d = in_m.input_bounds().duration_seconds();
            if (d <= 0) {
                return error.InvalidMappingForTopology;
            }

            cursor += d;

            try end_points.append(d);
        }

        return .{
            .mappings = try allocator.dupe(
                mapping.Mapping,
                in_mappings
            ),
            .end_points_input = try end_points.toOwnedSlice(),
        };
    }

    pub fn deinit(
        self: @This(),
        allocator: std.mem.Allocator,
    ) void
    {
        allocator.free(self.end_points_input);
        allocator.free(self.mappings);
    }

    // pub fn intervals_output(
    //     self: @This(),
    //     allocator: std.mem.Allocator,
    // ) ![]const opentime.ContinuousTimeInterval
    // {
    //     const result = std.ArrayList(
    //         opentime.ContinuousTimeInterval
    //     ).init(allocator);
    //
    //     for (self.mappings)
    //         |m|
    //     {
    //         try result.append(m.output_bounds());
    //     }
    //
    //     return try result.toOwnedSlice();
    // }

    pub fn input_bounds(
        self: @This(),
    ) opentime.ContinuousTimeInterval
    {
        return .{
            .start_seconds = self.end_points_input[0],
            .end_seconds = self.end_points_input[self.end_points_input.len - 1],
        };
    }

    pub fn output_bounds(
        self: @This(),
    ) opentime.ContinuousTimeInterval
    {
        // @TODO: handle this case
        if (self.mappings.len == 0) {
            unreachable;
        }

        var bounds = self.mappings[0].output_bounds();

        for (self.mappings[1..])
            |m|
        {
            bounds = opentime.interval.extend(
                bounds,
                m.output_bounds()
            );
        }

        return bounds;
    }

    pub fn trim_in_input_space(
        self: @This(),
        allocator: std.mem.Allocator,
        new_input_bounds: opentime.ContinuousTimeInterval,
    ) !TopologyMapping
    {
        const new_bounds = opentime.interval.intersect(
            new_input_bounds,
            self.input_bounds(),
        ) orelse return EMPTY;

        var trimmed_endpoints = (
            std.ArrayList(opentime.Ordinate).init(allocator)
        );
        var trimmed_mappings = (
            std.ArrayList(mapping.Mapping).init(allocator)
        );

        // trim left
        var start_ind : usize = self.mappings.len;

        for (self.end_points_input[1..], 0..,)
            |right, ind|
        {
            if (right > new_bounds.start_seconds) 
            {
                start_ind = ind;
                try self.trimmed_endpoints.append(
                    new_bounds.start_seconds
                );
                break;
            }
        }

        try trimmed_mappings.append(
            self.mappings[start_ind].split_at_input_point(
                new_bounds.start_seconds
            )
        );

        if (start_ind < self.mappings.len - 1) 
        {
            trimmed_mappings.appendSlice(self.mappings[start_ind+1..]);
        }

        // trim right
        var end_ind : usize = trimmed_mappings.len;
        while (end_ind > 0)
            : (end_ind -= 1)
        {
            if (self.end_points_input[end_ind] < new_bounds.end_seconds)
            {
                break;
            }
        }

        if (end_ind > 0)
        {
            trimmed_mappings.shrinkAndFree(trimmed_mappings.items.len - end_ind);
        }

        try trimmed_mappings.itmes[trimmed_mappings.items.len-1].split_at_input_point(
            new_bounds.end_seconds
        );

        // @TOOD: split the mappings on either end

        try trimmed_endpoints.append(new_bounds.start_seconds);
        try trimmed_endpoints.appendSlice(
            self.end_points_input[start_ind+1..end_ind-1]
        );
        try trimmed_endpoints.append(new_bounds.end_seconds);

        try trimmed_mappings.appendSlice(
            self.end_points_input[start_ind..end_ind]
        );

        return .{
            .end_points_input = try trimmed_endpoints.toOwnedSlice(),
            .mappings = try trimmed_mappings.toOwnedSlice(),
        };
    }

    // pub fn trim_in_output_space(
    //     self: @This(),
    //     allocator: std.mem.Allocator,
    //     new_input_bounds: opentime.ContinuousTimeInterval,
    // ) !TopologyMapping
    // {
    // }

    pub fn split_at_input_points(
        self: @This(),
        allocator: std.mem.Allocator,
        input_points: []const opentime.Ordinate,
    ) !TopologyMapping
    {
        var result_mappings = (
            std.ArrayList(mapping.Mapping).init(allocator)
        );

        var result_endpoints = (
            std.ArrayList(opentime.Ordinate).init(allocator)
        );

        try result_endpoints.append(self.mappings[0].input_bounds().start_seconds);

        var q = std.ArrayList(mapping.Mapping).init(allocator);
        std.mem.reverse(mapping.Mapping, q.items);

        while (q.items.len > 0)
        {
            const m = q.pop();
            const m_b = m.input_bounds();

            for (input_points)
                |pt|
            {
                if (m.input_bounds().overlaps_seconds(pt)) 
                {
                    // [2]Mapping
                    const m_split = try m.split_at_input_point(pt);
                    try result_mappings.append(m_split[0]);
                    try q.append(m_split[1]);
                    try result_endpoints.append(pt);
                } 
                else 
                {
                    try result_mappings.append(m);
                    try result_endpoints.append(m_b.end_seconds);
                }
            }
        }

        return .{
            .mappings = try result_mappings.toOwnedSlice(),
            .end_points_input = try result_endpoints.toOwnedSlice(),
        };
    }
};

test "TopologyMapping.split_at_input_points"
{
    const m_split = try MIDDLE.AFF_TOPO.split_at_input_points(
        std.testing.allocator,
        &.{ 0, 2, 3, 15 },
    );

    try std.testing.expectEqual(3, m_split.mappings.len);
}

test "TopologyMapping.trim_in_input_space"
{
}

// test "TopologyMapping.split_at_input_points perf test"
// {
//     // const SIZE = 20000000;
//     const SIZE = 2000000;
//
//     var t_setup = try std.time.Timer.start();
//
//     var rnd_split_points = (
//         std.ArrayList(opentime.Ordinate).init(std.testing.allocator)
//     );
//     try rnd_split_points.ensureTotalCapacity(SIZE);
//     defer rnd_split_points.deinit();
//
//     try rnd_split_points.append(0);
//
//     const m_bounds = MIDDLE.AFF_TOPO.input_bounds();
//
//     var rand_impl = std.rand.DefaultPrng.init(42);
//
//     for (0..SIZE)
//         |_|
//     {
//         const num = (
//             (
//              m_bounds.duration_seconds() 
//              * rand_impl.random().float(opentime.Ordinate)
//             )
//             + m_bounds.start_seconds
//         );
//         rnd_split_points.appendAssumeCapacity(num);
//     }
//     const t_start_v = t_setup.read();
//
//     var t_algo = try std.time.Timer.start();
//     const m_split = try MIDDLE.AFF_TOPO.split_at_input_points(
//         std.testing.allocator,
//         rnd_split_points.items,
//     );
//     const t_algo_v = t_algo.read();
//     defer m_split.deinit(std.testing.allocator);
//
//     std.debug.print("range: {any}", .{ m_bounds });
//     for (rnd_split_points.items[0..15])
//         |n|
//     {
//         std.debug.print("n: {d}\n", .{ n });
//     }
//
//     std.debug.print(
//         "Startup time: {d:.4}ms\n"
//         ++ "Time to process is: {d:.4}ms\n"
//         ++ "number of splits: {d}\n"
//         ,
//         .{
//             t_start_v/std.time.ns_per_ms,
//             t_algo_v / std.time.ns_per_ms,
//             m_split.end_points_input.len,
//         },
//     );
// }

// test "TopologyMapping: split_at_critical_points"
// {
//     const allocator = std.testing.allocator;
//
//     const u_split = try MIDDLE.BEZ_U_TOPO.split_at_critical_points(
//         allocator,
//     );
//
//     try std.testing.expectEqual(2, u_split.mappings.len);
//
//     return error.OutOfBounds;
// }

const EMPTY = TopologyMapping{
    .end_points_input = &.{},
    .mappings = &.{}
};


/// build a topological mapping from a to c
pub fn join(
 parent_allocator: std.mem.Allocator,
 args: struct{
     a2b: TopologyMapping, // split on output
     b2c: TopologyMapping, // split in input
 },
) !TopologyMapping
{
    var arena = std.heap.ArenaAllocator.init(parent_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const a2b = args.a2b;
    const b2c = args.b2c;

    // first trim both to the intersection range
    const b_range = opentime.interval.intersect(
        a2b.output_bounds(),
        b2c.input_bounds(),
        // or return an empty topology
    ) orelse return EMPTY;

    const a2b_trimmed_in_b = a2b.trim_in_output_space(b_range);
    const b2c_trimmed_in_b = b2c.trim_in_input_space(b_range);

    // split in common points in b
    const a2b_split: TopologyMapping = a2b_trimmed_in_b.split_at_output_points(
        b2c.end_points_input
    );

    const b2c_split: TopologyMapping = b2c_trimmed_in_b.split_at_input_points(
        a2b.end_points_output // <- this will need a function to generate
    );

    const a2c_endpoints = (
        std.ArrayList(opentime.Ordinate).init(allocator)
    );
    const a2c_mappings = (
        std.ArrayList(mapping.Mapping).init(allocator)
    );

    try a2c_endpoints.append(a2b_split.end_points_input[0]);

    // at this point the start and end points are the same and there are the
    // same number of endpoints
    for (
        a2b_split.end_points_input[1..],
        a2b_split.mappings,
        b2c_split.mappings,
    )
        |a2b_p, a2b_m, b2c_m|
    {
        const a2c_m = try mapping.join(
            allocator,
            .{ 
                .a2b = a2b_m,
                .b2c = b2c_m,
            },
        );

        try a2c_endpoints.append(a2b_p);
        try a2c_mappings.append(a2c_m);
    }

    return TopologyMapping{
        .end_points_input = try a2c_endpoints.toOwnedSlice(),
        .mappings = try a2c_mappings.toOwnedSlice(),
    };
}

fn build_test_topo_from_slides(
    allocator: std.mem.Allocator,
) !type
{
    const m_b2c_left = (
        try mapping.MappingCurveLinear.init_knots(
            allocator, 
            &.{
                .{ .in = 0, .out = 0, },
                .{ .in = 2, .out = 4, },
            },
        )
    ).mapping();
    defer m_b2c_left.deinit(allocator);

    const m_b2c_middle = (
        try mapping.MappingCurveLinear.init_knots(
        allocator, 
        &.{
            .{ .in = 2, .out = 2, },
            .{ .in = 4, .out = 2, },
        },
    )
    ).mapping();
    defer m_b2c_middle.deinit(allocator);

    const m_b2c_right = (
        try mapping.MappingCurveLinear.init_knots(
        allocator, 
        &.{
            .{ .in = 4, .out = 2, },
            .{ .in = 6, .out = 0, },
        },
    )
    ).mapping();
    defer m_b2c_right.deinit(allocator);

    const tm_b2c = try TopologyMapping.init(
        allocator,
        &.{ m_b2c_left, m_b2c_middle, m_b2c_right, },
    );
    tm_b2c.deinit(allocator);

    // b2c mapping and topology
    const m_a2b = (
        try mapping.MappingCurveBezier.init_segments(
            allocator, 
            &.{
                .{
                    .p0 = .{ .in = 1, .out = 0 },
                    .p1 = .{ .in = 1, .out = 5 },
                    .p2 = .{ .in = 5, .out = 5 },
                    .p3 = .{ .in = 5, .out = 1 },
                },
                },
            )
    ).mapping();
    defer m_a2b.deinit(allocator);

    const tm_a2b = try TopologyMapping.init(
        allocator,
        &.{ m_a2b },
    );
    tm_a2b.deinit(allocator);

    return struct{
        var a2b = tm_a2b;
        var b2c = tm_b2c;

        pub fn deinit(
            self: @This(),
        ) void
        {
            self.a2b.deinit(allocator);
            self.b2c.deinit(allocator);
        }
    };
}

test "TopologyMapping" 
{
    const allocator = std.testing.allocator;

    const slides_test_data = (
        build_test_topo_from_slides(std.testing.allocator){}
    );
    defer slides_test_data.deinit();

    const a2c = try join(
        allocator,
        .{
            .a2b = slides_test_data.tm_a2b,
            .b2c = slides_test_data.tm_b2c,
        },
    );
    
    try std.testing.expectApproxEqAbs(
        1,
        a2c.input_bounds().start_seconds,
        opentime.util.EPSILON,
    );
    try std.testing.expectApproxEqAbs(
        5,
        a2c.input_bounds().end_seconds,
        opentime.util.EPSILON,
    );
    try std.testing.expectApproxEqAbs(
        0,
        a2c.output_bounds().start_seconds,
        opentime.util.EPSILON,
    );

    // const tm_right = TopologyMapping.init(
    //     allocator,
    //                   .{ MIDDLE2.AFF.mapping(), RIGHT.AFF.mapping(), },
    // );
    //
    // const result = join(
    //     allocator,
    //     .{
    //         .a2b = tm_left,
    //         .b2c = tm_right,
    //     },
    // );
    //
    // mappings.join(
    //     allocator,
    //     .{
    //         .a2b = MIDDLE.AFF.mapping(),
    //         .b2c = MIDDLE.AFF.mapping(),
    //     },
    // );
}

test "TopologyMapping: trim_in_input_space"
{
    const allocator = std.testing.allocator;

    const slides_test_data = (
        build_test_topo_from_slides(allocator)
    );
    defer slides_test_data.deinit();

    const a2b_in_bounds = slides_test_data.a2b.input_bounds();
    var d = a2b_in_bounds.duration_seconds();
    d *= 0.15;
    const new_bounds: opentime.ContinuousTimeInterval = .{
        .start_seconds = a2b_in_bounds.start_seconds + d,
        .end_seconds = a2b_in_bounds.end_seconds + d,
    };

    const a2b_trimmed = slides_test_data.a2b.trim_in_input_space(
        allocator,
        new_bounds,
    );

    try std.testing.expectApproxEqAbs(
        new_bounds.start_seconds,
        a2b_trimmed.input_bounds().start_seconds,
        opentime.util.EPSILON,
    );
    try std.testing.expectApproxEqAbs(
        new_bounds.end_seconds,
        a2b_trimmed.input_bounds().end_seconds,
        opentime.util.EPSILON,
    );
}

// test "TopologyMapping: LEFT/RIGHT -> EMPTY"
// {
//     if (true) {
//         return error.SkipZigTest;
//     }
//
//     const allocator = std.testing.allocator;
//
//     const tm_left = TopologyMapping.init(
//         allocator,
//         .{ mapping.LEFT.AFF,}
//     );
//     defer tm_left.deinit(allocator);
//
//     const tm_right = TopologyMapping.init(
//         allocator,
//         .{ mapping.RIGHT.AFF,}
//     );
//     defer tm_right.deinit(allocator);
//
//     const should_be_empty = join(
//         allocator,
//         .{
//             .a2b =  tm_left,
//             .b2c = tm_right,
//         }
//     );
//
//     try std.testing.expectEqual(EMPTY, should_be_empty);
// }

/// stitch topology test structures onto mapping ones
fn test_structs(
    comptime int: opentime.ContinuousTimeInterval,
) type
{
    return struct {
        const MAPPINGS = mapping.test_structs(int);

        pub const AFF_TOPO = TopologyMapping {
            .end_points_input = &.{ int.start_seconds, int.end_seconds },
            .mappings = &.{ MAPPINGS.AFF.mapping() },
        };
        pub const LIN_TOPO = TopologyMapping {
            .end_points_input = &.{ int.start_seconds, int.end_seconds },
            .mappings = &.{ MAPPINGS.LIN.mapping() },
        };
        pub const BEZ_TOPO = TopologyMapping {
            .end_points_input = &.{ int.start_seconds, int.end_seconds },
            .mappings = &.{ MAPPINGS.BEZ.mapping() },
        };
        pub const BEZ_U_TOPO = TopologyMapping {
            .end_points_input = &.{ int.start_seconds, int.end_seconds },
            .mappings = &.{ MAPPINGS.BEZ_U.mapping() },
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
