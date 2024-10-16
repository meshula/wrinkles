//! TopologyMapping implementation

const std = @import("std");

const opentime = @import("opentime");
const mapping = @import("mapping.zig");
const curve = @import("curve");

/// A Topology binds regions of a one dimensional space to a sequence of right
/// met monotonic mappings, separated by a list of end points.  There are
/// implicit "Empty" mappings outside of the end points which map to no values
/// before and after the segments defined by the Topology.
pub const TopologyMapping = struct {
    /// matches the boundaries of each of the child mappings, which are right
    /// met and not sparse
    end_points_input: []const opentime.Ordinate,
    mappings: []const mapping.Mapping,

    pub fn init(
        allocator: std.mem.Allocator,
        in_mappings: []const mapping.Mapping,
    ) !TopologyMapping
    {
        if (in_mappings.len == 0)
        {
            return EMPTY;
        }

        var end_points = (
            std.ArrayList(opentime.Ordinate).init(allocator)
        );
        try end_points.ensureTotalCapacity(in_mappings.len + 1);
        errdefer end_points.deinit();

        try end_points.append(in_mappings[0].input_bounds().start_seconds);

        for (in_mappings)
            |m|
        {
            try end_points.append(m.input_bounds().end_seconds);
        }

        return .{
            .mappings = try allocator.dupe(
                mapping.Mapping,
                in_mappings
            ),
            .end_points_input = try end_points.toOwnedSlice(),
        };
    }

    /// custom formatter for std.fmt
    pub fn format(
        self: @This(),
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void 
    {
        try writer.print(
            "TopologyMapping{{ end_points_input: {any}, mappings: {d} }}",
            .{
                self.end_points_input,
                self.mappings.len,
            }
        );
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
            switch (m) {
                .empty => continue,
                else => {
                    bounds = opentime.interval.extend(
                        bounds,
                        m.output_bounds()
                    );
                }
            }
        }

        return bounds;
    }

    // pub fn mapping_at_input(
    //     self: @This(),
    //     input_ord: opentime.Ordinate,
    // ) !usize
    // {
    //     if (self.input_bounds().overlaps_seconds(input_ord) == false)
    //     {
    //         return error.OutOfBounds;
    //     }
    //
    //     return self.mapping_at_input_assume_overlap(input_ord);
    // }
    //
    // pub fn mapping_at_input_assume_overlap(
    //     self: @This(),
    //     input_ord: opentime.Ordinate,
    // ) usize
    // {
    //     for (self.end_points_input[1..], 0..)
    //         |right_knot, m_ind|
    //     {
    //         if (right_knot > input_ord)
    //         {
    //             return m_ind;
    //         }
    //     }
    //
    //     return self.mappings.len-1;
    // }

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

        var maybe_left_map_ind: ?usize = null;
        var maybe_right_map_ind: ?usize = null;

        const n_pts = self.end_points_input.len;

        // find the segments that need to be trimmed
        for (
            self.end_points_input[0..n_pts-1],
            self.end_points_input[1..],
            0..n_pts-1,
            // 1..
        )
            |left_pt, right_pt, left_ind |//, right_ind|
        {
            if (
                left_pt < new_bounds.start_seconds 
                and right_pt > new_bounds.start_seconds
            )
            {
                maybe_left_map_ind = left_ind;
            }

            if (
                left_pt < new_bounds.end_seconds 
                and right_pt > new_bounds.end_seconds
            )
            {
                maybe_right_map_ind = left_ind;
            }
        }

        // trim the same mapping, toss the rest
        if (
            maybe_left_map_ind != null 
            and maybe_right_map_ind != null 
            and maybe_left_map_ind.? == maybe_right_map_ind.?
        )
        {
            var mapping_to_trim = self.mappings[maybe_left_map_ind.?];

            var left_splits = (
                try mapping_to_trim.split_at_input_point(
                    allocator,
                    new_bounds.start_seconds,
                )
            );

            left_splits[0].deinit(allocator);
            defer left_splits[1].deinit(allocator);

            var right_splits = (
                try left_splits[1].split_at_input_point(
                    allocator,
                    new_bounds.end_seconds,
                )
            );
            right_splits[1].deinit(allocator);

            return .{
                .end_points_input = try allocator.dupe(
                    opentime.Ordinate,
                    &.{ new_bounds.start_seconds, new_bounds.end_seconds },
                ),
                .mappings = try allocator.dupe(
                    mapping.Mapping,
                    &.{ right_splits[0] }
                ),
            };
        }

        // either only one side is being trimmed, or different mappings are
        // being trimmed
        var trimmed_mappings = (
            std.ArrayList(mapping.Mapping).init(allocator)
        );
        defer trimmed_mappings.deinit();

        var middle_start:usize = 0;
        var middle_end:usize = self.mappings.len;

        if (maybe_left_map_ind)
            |left_ind|
        {
            const split_mapping_left = (
                try self.mappings[left_ind].split_at_input_point(
                    allocator,
                    new_bounds.start_seconds,
                )
            );
            try trimmed_mappings.append(split_mapping_left[1]);
            defer {
                split_mapping_left[0].deinit(allocator);
            }

            middle_start = left_ind + 1;
        }

        if (maybe_right_map_ind)
            |right_ind|
        {
            middle_end = right_ind;
        }

        for (self.mappings[middle_start..middle_end])
            |m|
        {
            try trimmed_mappings.append(try m.clone(allocator));
        }

         if (maybe_right_map_ind)
             |right_ind|
         {
             const split_mapping_right = (
                 try self.mappings[right_ind].split_at_input_point(
                     allocator,
                     new_bounds.end_seconds,
                 )
             );
             try trimmed_mappings.append(split_mapping_right[0]);
             defer {
                 split_mapping_right[1].deinit(allocator);
             }
         }

         return try TopologyMapping.init(
             allocator,
             trimmed_mappings.items,
         );
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

        for (self.mappings)
            |m|
        {
            const m_input_range = m.input_bounds();
            const m_output_range = m.output_bounds();

            const maybe_overlap = opentime.interval.intersect(
                target_output_range,
                m_output_range
            );

            if (maybe_overlap != null)
            {
                // nothing to trim
                if (
                    m_output_range.start_seconds <= target_output_range.start_seconds
                    and m_output_range.end_seconds >= target_output_range.end_seconds
                )
                {
                    try new_mappings.append(m);
                    try new_endpoints.append(m_input_range.start_seconds);
                    try new_endpoints.append(m_input_range.end_seconds);
                    continue;
                }

                const shrunk_m = try m.shrink_to_output_interval(
                    allocator,
                    target_output_range,
                );

                const shrunk_input_bounds = (
                    shrunk_m.input_bounds()
                );

                // insert an "empty" mapping in the new gap
                if (
                    shrunk_input_bounds.start_seconds 
                    > m_input_range.start_seconds
                ) 
                {
                    try new_mappings.append(mapping.EMPTY);
                    try new_endpoints.append(m_input_range.start_seconds);
                }

                try new_endpoints.append(shrunk_input_bounds.start_seconds);
                try new_endpoints.append(shrunk_input_bounds.end_seconds);
                try new_mappings.append(shrunk_m);

                if (shrunk_input_bounds.end_seconds < m_input_range.end_seconds)
                {
                    try new_endpoints.append(shrunk_input_bounds.end_seconds);
                    try new_mappings.append(shrunk_m);
                }
            }
            else 
            {
                // no intersection
                try new_endpoints.append(m_input_range.start_seconds);
                try new_endpoints.append(m_input_range.end_seconds);
                try new_mappings.append(mapping.EMPTY);
            }
        }

        return .{
            .mappings = try new_mappings.toOwnedSlice(),
            .end_points_input = try new_endpoints.toOwnedSlice(),
        };
    }

    /// split the topology at the specified points in the input domain, does
    /// not trim.  If points is empty or none of the points are in bounds,
    /// returns a clone of self.
    pub fn split_at_input_points(
        self: @This(),
        allocator: std.mem.Allocator,
        input_points: []const opentime.Ordinate,
    ) !TopologyMapping
    {
        if (
            input_points.len == 0
            or (input_points[0] > self.end_points_input[self.end_points_input.len-1])
            or (input_points[input_points.len-1] < self.end_points_input[0])
        ) 
        {
                return self.clone(allocator);
        }

        var mappings_to_split = (
            std.ArrayList(mapping.Mapping).init(allocator)
        );

        // seed the queue
        try mappings_to_split.appendSlice(self.mappings);
        defer mappings_to_split.deinit();

        // zig 0.13.0: std.ArrayList only has "pop" and not "popfront", so
        // reverse the list first in order to pop the mappings in the same
        // order as the input_points
        std.mem.reverse(mapping.Mapping, mappings_to_split.items);

        var current_pt_index:usize = 0;

        var result_mappings = (
            std.ArrayList(mapping.Mapping).init(allocator)
        );
        defer result_mappings.deinit();

        while (
            mappings_to_split.items.len > 0 
            and current_pt_index < input_points.len
        )
        {
            const current_mapping = mappings_to_split.pop();
            const current_range = current_mapping.input_bounds();

            const current_pt = input_points[current_pt_index];

            if (current_pt < current_range.end_seconds)
            {
                if (current_pt > current_range.start_seconds)
                {
                    const new_mappings = try current_mapping.split_at_input_point(
                        allocator,
                        current_pt,
                    );

                    try result_mappings.append(new_mappings[0]);
                    try mappings_to_split.append(new_mappings[1]);
                }
                else {
                    try mappings_to_split.append(current_mapping);
                }

                current_pt_index += 1;
            }
            else 
            {
                try result_mappings.append(current_mapping);
            }
        }

        return TopologyMapping.init(
            allocator,
            result_mappings.items,
        );
    }
    
    pub fn end_points_output(
        self: @This(),
        allocator: std.mem.Allocator,
    ) ![]opentime.Ordinate
    {
        var result = (
            std.ArrayList(opentime.Ordinate).init(allocator)
        );

        try result.append(self.mappings[0].output_bounds().start_seconds);

        for (self.mappings)
            |m|
        {
            try result.append(m.output_bounds().end_seconds);
        }

        return try result.toOwnedSlice();
    }
    

    /// split the topology at points in its output space.  If none of the
    /// points are in bounds, returns a clone of self.
    pub fn split_at_output_points(
        self: @This(),
        allocator: std.mem.Allocator,
        output_points: []const opentime.Ordinate,
    ) !TopologyMapping
    {
        if (output_points.len == 0) {
            return self.clone(allocator);
        }

        var result_mappings = (
            std.ArrayList(mapping.Mapping).init(allocator)
        );
        defer result_mappings.deinit();

        var input_points_in_bounds = (
            std.ArrayList(opentime.Ordinate).init(allocator)
        );
        try input_points_in_bounds.ensureTotalCapacity(output_points.len);
        defer input_points_in_bounds.deinit();

        for (self.mappings)
            |m|
        {
            switch (m) {
                .empty => try result_mappings.append(try m.clone(allocator)),
                else => {
                    const m_bounds_out = m.output_bounds();
                    const m_bounds_in = m.input_bounds();

                    input_points_in_bounds.clearRetainingCapacity();

                    for (output_points)
                        |pt|
                    {
                        if (
                            m_bounds_out.overlaps_seconds(pt)
                            and pt > m_bounds_out.start_seconds
                            and pt < m_bounds_out.end_seconds
                        )
                        {
                            const in_pt = (
                                try m.project_instantaneous_cc_inv(pt)
                            );

                            if (
                                in_pt > m_bounds_in.start_seconds 
                                and in_pt < m_bounds_in.end_seconds
                            )
                            {
                                try input_points_in_bounds.append(in_pt);
                            }
                        }
                    }

                    // none of the input points are in bounds
                    if (input_points_in_bounds.items.len == 0)
                    {
                        // just append the mapping as is
                        try result_mappings.append(try m.clone(allocator));
                        continue;
                    }

                    std.mem.sort(
                        opentime.Ordinate,
                        input_points_in_bounds.items,
                        {},
                        std.sort.asc(opentime.Ordinate),
                    );

                    var m_clone = try m.clone(allocator);
                    for (input_points_in_bounds.items)
                        |pt|
                    {
                        const new_mappings = (
                            try m_clone.split_at_input_point(
                                allocator,
                                pt,
                            )
                        );
                        defer new_mappings[0].deinit(allocator);
                        defer new_mappings[1].deinit(allocator);

                        try result_mappings.append(
                            try new_mappings[0].clone(allocator)
                        );
                        m_clone.deinit(allocator);
                        m_clone = try new_mappings[1].clone(allocator);
                    }

                    try result_mappings.append(m_clone);
                },
            }
        }

        return try TopologyMapping.init(
            allocator,
            result_mappings.items,
        );
    }
};

test "TopologyMapping.split_at_input_points"
{
    const m_split = try MIDDLE.AFF_TOPO.split_at_input_points(
        std.testing.allocator,
        &.{ 0, 2, 3, 15 },
    );
    defer m_split.deinit(std.testing.allocator);

    try std.testing.expectEqual(3, m_split.mappings.len);
}

test "TopologyMapping trim_in_input_space"
{
    const allocator = std.testing.allocator;

    const TopoTypes = struct {
        name : []const u8,
        topo: TopologyMapping,
    };
    const topos= [_]TopoTypes{
        .{
            .name = "linear",
            .topo = MIDDLE.LIN_TOPO,
        },
        .{
            .name = "affine",
            .topo = MIDDLE.AFF_TOPO,
        },
    };

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

    for (topos)
        |tp|
    {
        errdefer std.debug.print(
            "over topology: {s}\n",
            .{ tp.name },
        );

        for (tests)
            |t|
        {
            // trim left but not right
            const tm = try tp.topo.trim_in_input_space(
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
        const tm = try tp.topo.trim_in_input_space(
            allocator,
            .{ .start_seconds = 11, .end_seconds = 13 },
        );
        defer tm.deinit(allocator);

        try std.testing.expectEqualSlices(
            mapping.Mapping,
            EMPTY.mappings,
            tm.mappings,
        );
    }
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

    std.debug.print(
        "b_range: {s}, a2b.output_bounds: {s}\n",
        .{ b_range, a2b.output_bounds(), },
    );

    const a2b_trimmed_in_b = try a2b.trim_in_output_space(
        allocator,
        b_range,
    );
    std.debug.print(
        "a2b_trimmed: {s} output: {s}\n",
        .{ a2b_trimmed_in_b, a2b_trimmed_in_b.output_bounds() }
    );
    const b2c_trimmed_in_b = try b2c.trim_in_input_space(
        allocator,
        b_range,
    );
    std.debug.print(
        "b2c_trimmed: {s} input (b): {s}\n",
        .{ b2c_trimmed_in_b, b2c_trimmed_in_b.input_bounds() });

    // split in common points in b
    const a2b_split: TopologyMapping = (
        try a2b_trimmed_in_b.split_at_output_points(
            allocator,
            b2c.end_points_input
        )
    );

    std.debug.print(
        "a2b_split: {s} output (b): {s}\n",
        .{ a2b_split, a2b_split.output_bounds() });

    const b2c_split: TopologyMapping = try b2c_trimmed_in_b.split_at_input_points(
        allocator,
        try a2b.end_points_output(allocator),
    );
    std.debug.print(
        "b2c_split: {s} input (b): {s}\n",
        .{ b2c_split, b2c_split.input_bounds() });

    var a2c_endpoints = (
        std.ArrayList(opentime.Ordinate).init(parent_allocator)
    );
    var a2c_mappings = (
        std.ArrayList(mapping.Mapping).init(parent_allocator)
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
        try a2c_mappings.append(try a2c_m.clone(parent_allocator));

        std.debug.print(
            "adding: {s} with endpoint {d} \n",
            .{ a2c_m, a2b_p },
        );
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
        &.{
            try m_b2c_left.clone(allocator),
            try m_b2c_middle.clone(allocator),
            try m_b2c_right.clone(allocator), 
        },
    );

    // b2c mapping and topology
    const tm_a2b = (
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
    );

    return .{
        .a2b = tm_a2b,
        .b2c = tm_b2c,
    };
}

test "TopologyMapping: join" 
{
    const allocator = std.testing.allocator;

    const slides_test_data = (
        try build_test_topo_from_slides(allocator)
    );
    defer slides_test_data.deinit(allocator);

    const a2c = try join(
        allocator,
        .{
            .a2b = slides_test_data.a2b,
            .b2c = slides_test_data.b2c,
        },
    );
    defer a2c.deinit(allocator);

    try std.testing.expect(a2c.end_points_input.len > 0);
    
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
    std.debug.print("result: {s}\n", .{ a2c.output_bounds() });
    try std.testing.expectApproxEqAbs(
        0.123208,
        a2c.output_bounds().start_seconds,
        opentime.util.EPSILON,
    );
    try std.testing.expectApproxEqAbs(
        3.999999995,
        a2c.output_bounds().end_seconds,
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
}

/// stitch topology test structures onto mapping ones
fn test_structs(
    comptime int: opentime.ContinuousTimeInterval,
) type
{
    return struct {
        const MAPPINGS = mapping.test_structs(int);

        pub const AFF_TOPO = TopologyMapping {
            .end_points_input = &.{
                int.start_seconds,
                int.end_seconds,
            },
            .mappings = &.{ MAPPINGS.AFF.mapping() },
        };
        pub const LIN_TOPO = TopologyMapping {
            .end_points_input = &.{
                int.start_seconds,
                int.end_seconds,
            },
            .mappings = &.{ MAPPINGS.LIN.mapping() },
        };
        pub const BEZ_TOPO = TopologyMapping {
            .end_points_input = &.{
                int.start_seconds,
                int.end_seconds,
            },
            .mappings = &.{ MAPPINGS.BEZ.mapping() },
        };
        pub const BEZ_U_TOPO = TopologyMapping {
            .end_points_input = &.{
                int.start_seconds,
                int.end_seconds,
            },
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

test "TopologyMapping: trim_in_output_space"
{
    const allocator = std.testing.allocator;

    const TestCase = struct {
        name: []const u8,
        target: opentime.ContinuousTimeInterval,
        expected: opentime.ContinuousTimeInterval,
        result_mappings: usize,
    };
    const tests = [_]TestCase{
        .{
            .name = "no trim",
            .target = .{
                .start_seconds = -1,
                .end_seconds = 11 
            },
            .expected = .{
                .start_seconds = 0,
                .end_seconds = 10,
            },
            .result_mappings = 1,
        },
        .{
            .name = "left trim",
            .target = .{
                .start_seconds = 3,
                .end_seconds = 11 
            },
            .expected = .{
                .start_seconds = 3,
                .end_seconds = 10,
            },
            .result_mappings = 2,
        },
        .{
            .name = "right trim",
            .target = .{
                .start_seconds = 0,
                .end_seconds = 7 
            },
            .expected = .{
                .start_seconds = 3,
                .end_seconds = 7,
            },
            .result_mappings = 2,
        },
        .{
            .name = "both trim",
            .target = .{
                .start_seconds = 3,
                .end_seconds = 7 
            },
            .expected = .{
                .start_seconds = 3,
                .end_seconds = 7,
            },
            .result_mappings = 3,
        },
        //       all trimmed
    };

    for (tests)
        |t|
    {
        const trimmed = (
            try MIDDLE.LIN_TOPO.trim_in_output_space(
                allocator,
                t.target,
            )
        );
        defer trimmed.deinit(allocator);

        errdefer {
            std.debug.print(
                "error with test: {s}\n trimmed: {s}\n",
               .{ t.name, trimmed }
            );
        }

        try std.testing.expectEqual(
            t.result_mappings,
            trimmed.mappings.len,
        );

        try std.testing.expectEqual(
            t.expected.start_seconds,
            trimmed.output_bounds().start_seconds,
        );
        try std.testing.expectEqual(
            t.expected.end_seconds,
            trimmed.output_bounds().end_seconds,
        );
    }

    const rising = (
        mapping.MappingCurveLinearMonotonic{
            .input_to_output_curve = curve.Linear.Monotonic {
                .knots = &.{
                    .{ .in = 0, .out = 0, },
                    .{ .in =10, .out = 10, },
                },
            },
        }
    ).mapping();
    const falling = (
        mapping.MappingCurveLinearMonotonic{
            .input_to_output_curve = curve.Linear.Monotonic {
                .knots = &.{
                    .{ .in =10, .out = 10, },
                    .{ .in = 20, .out = 0, },
                },
            },
        }
    ).mapping();

    const rf_topo = try TopologyMapping.init(
        allocator,
        &.{ rising, falling }
    );
    defer rf_topo.deinit(allocator);

    const rf_topo_trimmed = try rf_topo.trim_in_output_space(
        allocator,
        .{ 
            .start_seconds = 1,
            .end_seconds = 8,
        }
    );
    defer rf_topo_trimmed.deinit(allocator);

    const result = rf_topo_trimmed.output_bounds();

    try std.testing.expectEqual(
        1,
        result.start_seconds,
    );
    try std.testing.expectEqual(
        8,
        result.end_seconds,
    );
}

test "TopologyMapping: Bezier construction/leak"
{
    const allocator = std.testing.allocator;
    
    const tm_a2b = (
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
    );
    defer tm_a2b.deinit(allocator);

    std.debug.print("num mappings: {d}\n", .{ tm_a2b.mappings.len });
    for (tm_a2b.mappings, 0..)
        |m, m_ind|
    {
        std.debug.print(
            "  {d}: segments: {d}\n",
            .{ m_ind, m.linear.input_to_output_curve.knots.len },
        );
    }
}

test "TopologyMapping: split_at_output_points"
{
    const allocator = std.testing.allocator;

    const rising = (
        mapping.MappingCurveLinearMonotonic{
            .input_to_output_curve = curve.Linear.Monotonic {
                .knots = &.{
                    .{ .in = 0, .out = 0, },
                    .{ .in =10, .out = 10, },
                },
            },
        }
    ).mapping();
    const falling = (
        mapping.MappingCurveLinearMonotonic{
            .input_to_output_curve = curve.Linear.Monotonic {
                .knots = &.{
                    .{ .in =10, .out = 10, },
                    .{ .in = 20, .out = 0, },
                },
            },
        }
    ).mapping();

    const rf_topo = try TopologyMapping.init(
        allocator,
        &.{ 
            try rising.clone(allocator),
            try falling.clone(allocator),
        }
    );
    defer rf_topo.deinit(allocator);

    const split_topo = try rf_topo.split_at_output_points(
        allocator,
        &.{ 0, 3, 7, 11 }
    );
    defer split_topo.deinit(allocator);

    try std.testing.expectEqual(6, split_topo.mappings.len);
}
