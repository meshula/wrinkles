//! TopologyMapping implementation

const std = @import("std");

const opentime = @import("opentime");
const mapping = @import("mapping.zig");

/// A Topology binds regions of a one dimensional space to a sequence of right
/// met mappings, separated by a list of end points.  There are implicit
/// "Empty" mappings outside of the end points which map to no values before
/// and after the segments defined by the Topology.
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

    pub fn intervals_output(
        self: @This(),
        allocator: std.mem.Allocator,
    ) ![]const opentime.ContinuousTimeInterval
    {
        const result = std.ArrayList(
            opentime.ContinuousTimeInterval
        ).init(allocator);

        for (self.mappings)
            |m|
        {
            try result.append(m.output_bounds());
        }

        return try result.toOwnedSlice();
    }

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
                if (m.input_bounds().overlaps_seconds(pt)) {
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

test "TopologyMapping.split_at_input_point"
{
    const m_split = try MIDDLE.AFF_TOPO.split_at_input_points(
        std.testing.allocator,
        &.{ 0, 2, 3, 15 },
    );

    try std.testing.expectEqual(3, m_split.mappings.len);
}

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

    const a2b_split: TopologyMapping = a2b.split_at_output_points(
        b2c.end_points_input
    );

    const b2c_split: TopologyMapping = b2c.split_at_input_points(
        a2b.end_points_output // <- this will need a function to generate
    );

    const result = (
        std.ArrayList(mapping.Mapping).init(allocator)
    );

    for (b2c_split.mappings)
        |b2c_m|
    {
        const b2c_m_input_bounds = b2c_m.input_bounds();

        for (a2b_split.mappings)
            |a2b_m|
        {
            if (
                opentime.interval.intersect(
                   a2b_m.output_bounds(),
                   b2c_m_input_bounds,
                ) != null
            ) {
                try result.append(
                    mapping.join(
                        parent_allocator,
                        .{
                            .a2b = a2b_m,
                            .b2c = b2c_m,
                        },
                    )
                );
            }
            else {
                // need to set the input duration
                try result.append(mapping.EMPTY);
            }
        }
    }

    return TopologyMapping.init(parent_allocator, result);
}

test "TopologyMapping" 
{
    const allocator = std.testing.allocator;

    // b2c mappings & topology

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

    const a2c = try join(
        allocator,
        .{
            .a2b = tm_a2b,
            .b2c = tm_b2c,
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
