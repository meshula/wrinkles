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

    pub fn clone(
        self: @This(),
        allocator: std.mem.Allocator,
    ) !TopologyMapping
    {
        var new_mappings = std.ArrayList(
            mapping.Mapping,
        ).init(allocator);
        for (self.mappings)
            |m|
        {
            try new_mappings.append(try m.clone(allocator));
        }

        return .{
            .end_points_input = try allocator.dupe(
                opentime.Ordinate,
                self.end_points_input,
            ),
            .mappings = try new_mappings.toOwnedSlice(),
        };
    }

    pub fn deinit(
        self: @This(),
        allocator: std.mem.Allocator,
    ) void
    {
        allocator.free(self.end_points_input);
        for (self.mappings)
            |m|
        {
            m.deinit(allocator);
        }
        allocator.free(self.mappings);
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

    pub fn trim_in_input_space(
        self: @This(),
        allocator: std.mem.Allocator,
        new_input_bounds: opentime.ContinuousTimeInterval,
    ) !TopologyMapping
    {
        const ib = self.input_bounds();
        var new_bounds = opentime.interval.intersect(
            new_input_bounds,
            ib,
        ) orelse return EMPTY;

        if (
            new_bounds.start_seconds <= ib.start_seconds
            and new_bounds.end_seconds >= ib.end_seconds
        ) 
        {
            return self.clone(allocator);
        }

        new_bounds.start_seconds = @max(
            new_bounds.start_seconds,
            ib.start_seconds,
        );
        new_bounds.end_seconds = @min(
            new_bounds.end_seconds,
            ib.end_seconds,
        );

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
                try trimmed_endpoints.append(
                    new_bounds.start_seconds
                );
                break;
            }
        }

        try trimmed_mappings.appendSlice(
            &(
                try self.mappings[start_ind].split_at_input_point(
                    allocator,
                    new_bounds.start_seconds
                )
            )
        );

        if (start_ind < self.mappings.len - 1) 
        {
            for (self.mappings[start_ind+1..])
                |m|
            {
                try trimmed_mappings.append(try m.clone(allocator));
            }
        }

        // trim right
        var end_ind : usize = trimmed_mappings.items.len - 1;
        while (end_ind > 1)
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

        // try trimmed_mappings.items[trimmed_mappings.items.len-1].split_at_input_point(
        //     new_bounds.end_seconds
        // );

        // @TOOD: split the mappings on either end

        // try trimmed_endpoints.append(new_bounds.start_seconds);
        // try trimmed_endpoints.appendSlice(
        //     self.end_points_input[start_ind+1..end_ind-1]
        // );
        // try trimmed_endpoints.append(new_bounds.end_seconds);
        //
        // try trimmed_endpoints.appendSlice(
        //     self.end_points_input[start_ind..end_ind]
        // );

        return .{
            .end_points_input = try trimmed_endpoints.toOwnedSlice(),
            .mappings = try trimmed_mappings.toOwnedSlice(),
        };
    }

    /// trims the mappings, inserting empty mappings where child mappings have
    /// been cut away
    pub fn trim_in_output_space(
        self: @This(),
        allocator: std.mem.Allocator,
        target_output_range: opentime.interval.ContinuousTimeInterval,
    ) !TopologyMapping
    {
        var new_endpoints = (
            std.ArrayList(opentime.Ordinate).init(allocator)
        );
        var new_mappings = (
            std.ArrayList(mapping.Mapping).init(allocator)
        );

        const last_ep = self.end_points_input.len - 1;

        for (
            self.mappings,
            self.end_points_input[0..last_ep-1],
            self.end_points_input[1..]
        )
            |m, tm_input_start, tm_input_end|
        {
            _ = tm_input_end;
            const m_input_range = m.input_bounds();
            const m_output_range = m.output_bounds();

            if (
                opentime.interval.intersect(
                    target_output_range,
                    m_output_range
                )
            ) |new_input_range|
            {
                _ = new_input_range;
                const shrunk_m = try m.shrink_to_output_interval(
                    allocator,
                    target_output_range,
                );

                const shrunk_input_bounds = (
                    shrunk_m.input_bounds()
                );

                if (
                    shrunk_input_bounds.start_seconds 
                    > m_input_range.start_seconds
                ) {
                }
            }
            else 
            {
                // no intersection
                try new_endpoints.append(tm_input_start);
                try new_mappings.append(mapping.EMPTY);
            }
        }
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

test "TopologyMapping trim_in_input_space"
{
    const allocator = std.testing.allocator;

    const TestCase = struct {
        name: []const u8,
        range: opentime.ContinuousTimeInterval,
        expected: opentime.ContinuousTimeInterval,
        mapping_count: usize,
    };

    const tests = [_]TestCase{
        .{
            .name = "no trim",
            .range = .{
                .start_seconds = -1,
                .end_seconds = 11,
            },
            .expected = .{
                .start_seconds = 0,
                .end_seconds = 10,
            },
            .mapping_count = 1,
        },
        .{
            .name = "left",
            .range = .{
                .start_seconds = 3,
                .end_seconds = 11,
            },
            .expected = .{
                .start_seconds = 3,
                .end_seconds = 10,
            },
            .mapping_count = 1,
        },
        .{
            .name = "right trim",
            .range = .{
                .start_seconds = -1,
                .end_seconds = 7,
            },
            .expected = .{
                .start_seconds = 0,
                .end_seconds = 7,
            },
            .mapping_count = 1,
        },
        .{
            .name = "both",
            .range = .{
                .start_seconds = 3,
                .end_seconds = 7,
            },
            .expected = .{
                .start_seconds = 3,
                .end_seconds = 7,
            },
            .mapping_count = 1,
        },
    };

    for (tests)
        |t|
    {
        // trim left but not right
        const tm = try MIDDLE.LIN_TOPO.trim_in_input_space(
            allocator,
            t.range,
        );
        defer tm.deinit(allocator);

        errdefer std.debug.print(
            "error with test name: {s}\n",
            .{ t.name },
        );

        try std.testing.expectEqual(
            t.expected.start_seconds,
            tm.input_bounds().start_seconds,
        );
        try std.testing.expectEqual(
            t.expected.end_seconds,
            tm.input_bounds().end_seconds,
        );

        try std.testing.expectEqual(
            tm.mappings[0].input_bounds().duration_seconds(), 
            tm.input_bounds().duration_seconds(),
        );

        try std.testing.expectEqual(
            t.mapping_count,
            tm.mappings.len,
        );
    }

    // separate "no overlap" test
    const tm = try MIDDLE.LIN_TOPO.trim_in_input_space(
        allocator,
        .{ .start_seconds = 11, .end_seconds = 13 },
    );
    defer tm.deinit(allocator);

    try std.testing.expectEqualSlices(
        mapping.Mapping,
        EMPTY.mappings,
        tm.mappings,
    );

    return error.Barf;
}

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

    const a2b_trimmed_in_b = a2b.trim_in_output_space(
        allocator,
        b_range,
    );
    const b2c_trimmed_in_b = b2c.trim_in_input_space(
        allocator,
        b_range,
    );

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

const TestToposFromSlides = struct{
    a2b: TopologyMapping,
    b2c: TopologyMapping,

    pub fn deinit(
        self: @This(),
        allocator: std.mem.Allocator,
    ) void
    {
        self.a2b.deinit(allocator);
        self.b2c.deinit(allocator);
    }
};

fn build_test_topo_from_slides(
    allocator: std.mem.Allocator,
) !TestToposFromSlides
{
    const m_b2c_left = (
        mapping.MappingCurveLinearMonotonic{
            .input_to_output_curve = .{
                .knots = &.{
                    .{ .in = 0, .out = 0, },
                    .{ .in = 2, .out = 4, },
                },
            }
        }
    ).mapping();

    const m_b2c_middle = (
        mapping.MappingCurveLinearMonotonic{
            .input_to_output_curve = .{
                .knots = &.{
                    .{ .in = 2, .out = 2, },
                    .{ .in = 4, .out = 2, },
                },
            }
        }
    ).mapping();

    const m_b2c_right = (
        mapping.MappingCurveLinearMonotonic{
            .input_to_output_curve = .{
                .knots = &.{
                    .{ .in = 4, .out = 2, },
                    .{ .in = 6, .out = 0, },
                },
            }
        }
    ).mapping();

    const tm_b2c = try TopologyMapping.init(
        allocator,
        &.{ m_b2c_left, m_b2c_middle, m_b2c_right, },
    );

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

    return .{
        .a2b = tm_a2b,
        .b2c = tm_b2c,
    };
}

test "TopologyMapping" 
{
    const allocator = std.testing.allocator;

    const slides_test_data = (
        build_test_topo_from_slides(allocator){}
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
}

test "TopologyMapping: LEFT/RIGHT -> EMPTY"
{
    const allocator = std.testing.allocator;

    const tm_left = try TopologyMapping.init(
        allocator,
         &.{ mapping.LEFT.AFF.mapping(),}
    );
    defer tm_left.deinit(allocator);

    const tm_right = try TopologyMapping.init(
        allocator,
        &.{ mapping.RIGHT.AFF.mapping(),}
    );
    defer tm_right.deinit(allocator);

    const should_be_empty = try join(
        allocator,
        .{
            .a2b =  tm_left,
            .b2c = tm_right,
        }
    );

    try std.testing.expectEqual(EMPTY, should_be_empty);
    return error.Barf;
}

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
