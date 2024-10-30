//! Topology implementation

const std = @import("std");

const opentime = @import("opentime");
const curve = @import("curve");

pub const mapping = @import("mapping.zig");


// Questions for 10/25 @Nick
//
// - project_instantaneous_cc -- I like that it connects up with the discrete
//   transformations, but I also like output_at_input_cc, since that connects
//   up with the curve.  Thoughts?
// - Topology{} right now contains a list of mappings, but I could see also
//   precomputing the input endpoints. If we needed to improve the performance
//   we could also have a binary tree for finding the mappings over the input
//   domain (or some other spatial subdivision)... but I'm not sure it'll
//   matter
// - for the retiming functions in sampling, which operate over a single curve,
//   I think having a linearize() function that returns a Topology where each
//   mapping is either empty or LinearMonotonic would be the way to go.  The
//   resampling algorithm would stil need to be reworked to walk across all the
//   mappings, but it would be otherwise largely the same
// - in particular, `retimed` takes a bezier curve and retimes the argument
//   in_samples accordingly.  I think this either needs a flavor that uses a
//   topology rather than a single curve to retime.  I _think_ then that it has
//   Mapping-specific types.
// - what does it mean in a retime if a mapping is empty? The samples are
//   valued at 0?
// - sampling.zig also refers to time, but I think we also want to move that
//   language to "ordinate", following the practice of the new topology/mapping
// - in `signal_generator.rasterized`, the count field of sampling.init is
//   promoted to f64 - is that right?  I think that should be opentime.Ordinate
// - mapping.join and assuming that mappings are aligned/bounded already


/// A Topology binds regions of a one dimensional space to a sequence of right
/// met monotonic mappings, separated by a list of end points.  There are
/// implicit "Empty" mappings outside of the end points which map to no values
/// before and after the segments defined by the Topology.
pub const Topology = struct {
    mappings: []const mapping.Mapping,

    pub fn init(
        allocator: std.mem.Allocator,
        in_mappings: []const mapping.Mapping,
    ) !Topology
    {
        if (in_mappings.len == 0)
        {
            return EMPTY;
        }

        return .{
            .mappings = try allocator.dupe(
                mapping.Mapping,
                in_mappings
            ),
        };
    }

    pub fn init_from_linear_monotonic(
        allocator: std.mem.Allocator,
        crv: curve.Linear.Monotonic,
    ) !Topology
    {
        return try Topology.init(
            allocator,
            &.{ 
                (
                 mapping.MappingCurveLinearMonotonic {
                     .input_to_output_curve = try crv.clone(
                         allocator,
                     ),
                 }
                ).mapping(),
            }
        );
    }

    pub fn init_from_linear(
        allocator: std.mem.Allocator,
        crv: curve.Linear,
    ) !Topology
    {
        const mono_crvs = (
            try crv.split_at_critical_points(allocator)
        );
        defer {
            for (mono_crvs)
                |mc|
            {
                mc.deinit(allocator);
            }
            allocator.free(mono_crvs);
        }

        var result_mappings = (
            std.ArrayList(mapping.Mapping).init(allocator)
        );
        defer result_mappings.deinit();

        for (mono_crvs)
            |mc|
        {
            try result_mappings.append(
                (
                 mapping.MappingCurveLinearMonotonic{
                    .input_to_output_curve = mc,
                }
                ).mapping()
            );
        }

        return .{
            .mappings = try result_mappings.toOwnedSlice(),
        };
    }

    pub fn init_affine(
        allocator: std.mem.Allocator,
        aff: mapping.MappingAffine,
    ) !Topology
    {
        return Topology.init(
            allocator,
            &.{ aff.mapping() }
        );
    }

    pub fn init_bezier(
        allocator: std.mem.Allocator,
        segments: []const curve.Bezier.Segment,
    ) !Topology
    {
        const crv = try curve.Bezier.init(
            allocator,
            segments
        );
        defer crv.deinit(allocator);

        return try mapping.MappingCurveBezier.init_curve(
            allocator,
            crv,
        );
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
            "Topology{{ mappings ({d}): [",
            .{self.mappings.len}
        );

        for (self.mappings, 0..)
            |m, ind|
        {
            if (ind > 0)
            {
                try writer.print(", ", .{});
            }
            try writer.print("({s}, {s})", .{ @tagName(m), m.input_bounds() });
        }

        try writer.print("] }}", .{});
    }

    pub fn clone(
        self: @This(),
        allocator: std.mem.Allocator,
    ) !Topology
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
            .mappings = try new_mappings.toOwnedSlice(),
        };
    }

    pub fn deinit(
        self: @This(),
        allocator: std.mem.Allocator,
    ) void
    {
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
            .start_seconds = self.mappings[0].input_bounds().start_seconds,
            .end_seconds = (
                self.mappings[
                    self.mappings.len - 1
                ].input_bounds().end_seconds
            ),
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

        var bounds:?opentime.ContinuousTimeInterval = null;

        for (self.mappings)
            |m|
        {
            switch (m) {
                .empty => continue,
                else => {
                    if (bounds)
                        |b|
                    {
                        bounds = opentime.interval.extend(
                            bounds orelse b,
                            m.output_bounds()
                        );
                    }
                    else {
                        bounds = m.output_bounds();
                    }
                }
            }
        }

        return bounds orelse opentime.INF_CTI;
    }

    pub fn end_points_input(
        self: @This(),
        allocator: std.mem.Allocator,
    ) ![]opentime.Ordinate
    {
        if (self.mappings.len == 0)
        {
            return &.{};
        }

        var result = (
            std.ArrayList(opentime.Ordinate).init(allocator)
        );

        try result.append(self.mappings[0].input_bounds().start_seconds);

        for (self.mappings)
            |m|
        {
            try result.append(m.input_bounds().end_seconds);
        }

        return try result.toOwnedSlice();
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
    ) !Topology
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

        const end_points = try self.end_points_input(allocator);
        defer allocator.free(end_points);

        const n_pts = end_points.len;

        // find the segments that need to be trimmed
        for (
            end_points[0..n_pts-1],
            end_points[1..],
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

         return try Topology.init(
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
    ) !Topology
    {
        var new_mappings = (
            std.ArrayList(mapping.Mapping).init(allocator)
        );

        for (self.mappings, 0..)
            |m, m_ind|
        {
            const m_in_range = m.input_bounds();
            const m_out_range = m.output_bounds();

            const maybe_overlap = opentime.interval.intersect(
                target_output_range,
                m_out_range
            );

            if (maybe_overlap != null)
            {
                // nothing to trim
                if (
                    m_out_range.start_seconds >= target_output_range.start_seconds
                    and m_out_range.end_seconds <= target_output_range.end_seconds
                )
                {
                    // nothing to trim
                    try new_mappings.append(try m.clone(allocator));
                    continue;
                }

                const shrunk_m = try m.shrink_to_output_interval(
                    allocator,
                    target_output_range,
                );
                defer shrunk_m.deinit(allocator);

                const shrunk_input_bounds = (
                    shrunk_m.input_bounds()
                );

                if (
                    shrunk_input_bounds.start_seconds > m_in_range.start_seconds
                    and m_ind > 0

                ) 
                {
                    // empty left
                    try new_mappings.append(
                        (
                         mapping.MappingEmpty{
                             .defined_range = .{
                                 .start_seconds = m_in_range.start_seconds,
                                 .end_seconds = shrunk_input_bounds.start_seconds,
                             },
                         }
                        ).mapping(),
                    );
                }

                if (
                    shrunk_input_bounds.start_seconds 
                    < shrunk_input_bounds.end_seconds
                )
                {
                    // trimmed mapping
                    try new_mappings.append(try shrunk_m.clone(allocator));
                }

                if (
                    shrunk_input_bounds.end_seconds < m_in_range.end_seconds
                    and m_ind < self.mappings.len-1
                )
                {
                    // empty right
                    try new_mappings.append(
                        (
                         mapping.MappingEmpty{
                             .defined_range = .{
                                 .start_seconds = shrunk_input_bounds.end_seconds,
                                 .end_seconds = m_in_range.end_seconds,
                             },
                         }
                        ).mapping()
                    );
                }
            }
            else 
            {
                // no intersection
                try new_mappings.append(
                    (
                     mapping.MappingEmpty{
                         .defined_range = m_in_range,
                     }
                    ).mapping(),
                );
            }
        }

        return .{
            .mappings = try new_mappings.toOwnedSlice(),
        };
    }

    /// split the topology at the specified points in the input domain, does
    /// not trim.  If points is empty or none of the points are in bounds,
    /// returns a clone of self.
    pub fn split_at_input_points(
        self: @This(),
        allocator: std.mem.Allocator,
        input_points: []const opentime.Ordinate,
    ) !Topology
    {
        const end_points = try self.end_points_input(allocator);
        defer allocator.free(end_points);

        if (
            input_points.len == 0
            or (input_points[0] > end_points[end_points.len-1])
            or (input_points[input_points.len-1] < end_points[0])
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
            const current_range = (
                current_mapping.input_bounds()
            );

            const current_pt = input_points[current_pt_index];

            if (current_pt < current_range.end_seconds)
            {
                if (current_pt > current_range.start_seconds)
                {
                    const new_mappings = (
                        try current_mapping.split_at_input_point(
                            allocator,
                            current_pt,
                        )
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

        return Topology.init(
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
    ) !Topology
    {
        if (output_points.len == 0) {
            return self.clone(allocator);
        }

        var result_endpoints = (
            std.ArrayList(opentime.Ordinate).init(allocator)
        );
        defer result_endpoints.deinit();

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

            const m_bounds_in = m.input_bounds();
            const m_bounds_out = m.output_bounds();

            switch (m) {
                .empty => {
                    try result_mappings.append(try m.clone(allocator));
                },
                else => {
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
                    try result_endpoints.appendSlice(
                        input_points_in_bounds.items
                    );
                },
            }
        }

        return try Topology.init(
            allocator,
            result_mappings.items,
        );
    }

    pub fn project_instantaneous_cc(
        self: @This(),
        input_ord: opentime.Ordinate
    ) !opentime.Ordinate
    {
        for (self.mappings)
            |m|
        {
            if (m.input_bounds().overlaps_seconds(input_ord))
            {
                return try m.project_instantaneous_cc(input_ord);
            }
        }

        return error.OutOfBounds;
    }

    /// project the output space ordinate into the input space.  Because
    /// monotonicity is only guaranteed in the forward direction, projects to a
    /// slice.
    pub fn project_instantaneous_cc_inv(
        self: @This(),
        allocator: std.mem.Allocator,
        output_ord: opentime.Ordinate
    ) ![]const opentime.Ordinate
    {
        var input_ordinates = (
            std.ArrayList(opentime.Ordinate).init(allocator)
        );
        errdefer input_ordinates.deinit();

        for (self.mappings)
            |m|
        {
            if (
                m.output_bounds().overlaps_seconds(output_ord)
                or output_ord == m.output_bounds().end_seconds
            )
            {
                try input_ordinates.append(
                    try m.project_instantaneous_cc_inv(output_ord)
                );
            }
        }

        return try input_ordinates.toOwnedSlice();
    }
};

test "Topology.split_at_input_points"
{
    const m_split = try MIDDLE.AFF_TOPO.split_at_input_points(
        std.testing.allocator,
        &.{ 0, 2, 3, 15 },
    );
    defer m_split.deinit(std.testing.allocator);

    try std.testing.expectEqual(3, m_split.mappings.len);
}

test "Topology trim_in_input_space"
{
    const allocator = std.testing.allocator;

    const TopoTypes = struct {
        name : []const u8,
        topo: Topology,
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
            .{ 
                .start_seconds = 11,
                .end_seconds = 13,
            },
        );
        defer tm.deinit(allocator);

        try std.testing.expectEqualSlices(
            mapping.Mapping,
            EMPTY.mappings,
            tm.mappings,
        );
    }
}

/// an empty topology
const EMPTY = Topology{
    .mappings = &.{}
};

/// build a topological mapping from a to c
pub fn join(
 parent_allocator: std.mem.Allocator,
 args: struct{
     a2b: Topology, // split on output
     b2c: Topology, // split in input
 },
) !Topology
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

    const a2b_trimmed_in_b = try a2b.trim_in_output_space(
        allocator,
        b_range,
    );
    const b2c_trimmed_in_b = try b2c.trim_in_input_space(
        allocator,
        b_range,
    );

    // @TODO: looks like splitting a2b is doing weird things

    const b2c_split_pts_b = try b2c.end_points_input(allocator);
    defer allocator.free(b2c_split_pts_b);

    // split in common points in b
    const a2b_split: Topology = (
        try a2b_trimmed_in_b.split_at_output_points(
            allocator,
            b2c_split_pts_b,
        )
    );

    const a2b_split_endpoints_b = try a2b_split.end_points_output(
        allocator
    );
    
    std.mem.sort(
        opentime.Ordinate,
        a2b_split_endpoints_b,
        {},
        std.sort.asc(opentime.Ordinate),
    );
    defer allocator.free(a2b_split_endpoints_b);

    std.debug.assert(std.math.isFinite(a2b_split_endpoints_b[0]));

    const b2c_split = (
        try b2c_trimmed_in_b.split_at_input_points(
            allocator,
            a2b_split_endpoints_b,
        )
    );

    ////// ASSERT
    //two problems currently: 1) a2b looks totally messed up
    //                        2) repeated identical knots (need epsilon checks)
    //                        in b2c
    // std.debug.assert(a2b_split_by_b.mappings.len == b2c_split.mappings.len);
    std.debug.assert(a2b_split.mappings.len == b2c_split.mappings.len);
    //////

    var a2c_mappings = (
        std.ArrayList(mapping.Mapping).init(parent_allocator)
    );

    // at this point the start and end points are the same and there are the
    // same number of endpoints
    for (
        // a2b_split_by_b.mappings,
        a2b_split.mappings,
        b2c_split.mappings,
    )
        |a2b_m, b2c_m|
    {
        const a2c_m = try mapping.join(
            allocator,
            .{ 
                .a2b = a2b_m,
                .b2c = b2c_m,
            },
        );

        try a2c_mappings.append(try a2c_m.clone(parent_allocator));
    }

    return Topology{
        .mappings = try a2c_mappings.toOwnedSlice(),
    };
}

const TestToposFromSlides = struct{
    a2b: Topology,
    b2c: Topology,

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
    const topo_a2b = (
        try Topology.init_bezier(
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

    // b2c mapping and topology
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

    const topo_b2c = try Topology.init(
        allocator,
        &.{
            try m_b2c_left.clone(allocator),
            try m_b2c_middle.clone(allocator),
            try m_b2c_right.clone(allocator), 
        },
    );

    return .{
        .a2b = topo_a2b,
        .b2c = topo_b2c,
    };
}

test "Topology: join" 
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

    const ep = try a2c.end_points_input(allocator);
    defer allocator.free(ep);

    try std.testing.expect(ep.len > 0);
    
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

test "Topology: LEFT/RIGHT -> EMPTY"
{
    const allocator = std.testing.allocator;

    const tm_left = try Topology.init(
        allocator,
         &.{ mapping.LEFT.AFF.mapping(),}
    );
    defer tm_left.deinit(allocator);

    const tm_right = try Topology.init(
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
    defer should_be_empty.deinit(allocator);

    try std.testing.expectEqual(
        0,
        should_be_empty.mappings.len
    );
}

/// stitch topology test structures onto mapping ones
fn test_structs(
    comptime int: opentime.ContinuousTimeInterval,
) type
{
    return struct {
        const MAPPINGS = mapping.test_structs(int);

        pub const AFF_TOPO = Topology {
            .mappings = &.{ MAPPINGS.AFF.mapping() },
        };
        pub const LIN_TOPO = Topology {
            .mappings = &.{ MAPPINGS.LIN.mapping() },
        };
        pub const LIN_V_TOPO = Topology {
            .mappings = &.{
                (
                 mapping.MappingCurveLinearMonotonic{
                     .input_to_output_curve = .{
                         .knots = &.{
                             MAPPINGS.START_PT,
                             .{
                                 .in = MAPPINGS.CENTER_PT.in,
                                 .out = MAPPINGS.END_PT.out,
                             },
                         },
                     },
                 }
                ).mapping(),
                (
                 mapping.MappingCurveLinearMonotonic{
                     .input_to_output_curve = .{
                         .knots = (
                             &.{
                                 .{
                                     .in = MAPPINGS.CENTER_PT.in,
                                     .out = MAPPINGS.END_PT.out,
                                 },
                                 .{
                                     .in = MAPPINGS.END_PT.in,
                                     .out = MAPPINGS.START_PT.in,  
                                 },
                             }
                         ),
                     },
                 }
                ).mapping()
            },
        };
        pub const BEZ_TOPO = Topology {
            .mappings = &.{ MAPPINGS.BEZ.mapping() },
        };
        pub const BEZ_U_TOPO = Topology {
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

test "Topology: trim_in_output_space"
{
    const allocator = std.testing.allocator;

    const TestCase = struct {
        name: []const u8,
        target: opentime.ContinuousTimeInterval,
        expected: opentime.ContinuousTimeInterval,
    };
    const tests = [_]TestCase{
        .{
            .name = "no trim",
            .target = .{
                .start_seconds = -1,
                .end_seconds = 41 
            },
            .expected = .{
                .start_seconds = 0,
                .end_seconds = 40,
            },
        },
        .{
            .name = "left trim",
            .target = .{
                .start_seconds = 3,
                .end_seconds = 41 
            },
            .expected = .{
                .start_seconds = 3,
                .end_seconds = 40,
            },
        },
        .{
            .name = "right trim",
            .target = .{
                .start_seconds = -1,
                .end_seconds = 7 
            },
            .expected = .{
                .start_seconds = 0,
                .end_seconds = 7,
            },
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
        },
        // all trimmed
    };

    const INPUT_TOPO = MIDDLE.LIN_TOPO;
    try std.testing.expect(
        std.math.isFinite(INPUT_TOPO.output_bounds().start_seconds)
    );
    try std.testing.expect(
        std.math.isFinite(INPUT_TOPO.output_bounds().end_seconds)
    );

    for (tests)
        |t|
    {
        const trimmed = (
            try INPUT_TOPO.trim_in_output_space(
                allocator,
                t.target,
            )
        );
        defer trimmed.deinit(allocator);

        errdefer {
            std.debug.print(
                (
                      "error with test: {s}\n"
                      ++ " input: {s} / output range: {s}\n"
                      ++ " target range: {s}\n"
                      ++ " trimmed: {s} / output range: {s}\n"
                      ++ " expected: {s}\n"
                ),
               .{
                   t.name,
                   INPUT_TOPO,
                   INPUT_TOPO.output_bounds(),
                   t.target,
                   trimmed,
                   trimmed.output_bounds(),
                   t.expected,
               }
            );
        }

        try std.testing.expectEqual(
            1,
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

    const rf_topo = Topology{
        .mappings = &.{ rising, falling },
    };

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

test "Topology: trim_in_output_space (slides)"
{

    const allocator = std.testing.allocator;

    const slides_test_data = (
        try build_test_topo_from_slides(allocator)
    );
    defer slides_test_data.deinit(allocator);
    const a2b = slides_test_data.a2b;
    const b2c = slides_test_data.b2c;

    const b_range = opentime.interval.intersect(
        a2b.output_bounds(),
        b2c.input_bounds(),
    ) orelse return error.OutOfBounds;

    const a2b_trimmed = (
        try a2b.trim_in_output_space(
            allocator,
            b_range,
        )
    );
    defer a2b_trimmed.deinit(allocator);

    try std.testing.expectEqual(
        b_range.start_seconds,
        a2b_trimmed.output_bounds().start_seconds,
    );
    try std.testing.expectEqual(
        b_range.end_seconds,
        a2b_trimmed.output_bounds().end_seconds,
    );
}

test "Topology: trim_in_output_space (trim to multiple split bug)"
{
    const allocator = std.testing.allocator;

    const a2b = try Topology.init_from_linear_monotonic(
        allocator,
        .{
            .knots = &.{
                .{ .in = 0, .out = 0},
                .{ .in = 2, .out = 2},
            }
        }
    );
    defer a2b.deinit(allocator);

    const a2b_trimmed = try a2b.trim_in_output_space(
        allocator, 
        .{ .start_seconds = 0.5, .end_seconds = 1 },
    );
    defer a2b_trimmed.deinit(allocator);

    try std.testing.expectEqual(
        1,
        a2b_trimmed.mappings.len
    );
    try std.testing.expectEqual(
        .linear,
        std.meta.activeTag(a2b_trimmed.mappings[0])
    );
    try std.testing.expectEqual(
        0.5,
        a2b_trimmed.mappings[0].input_bounds().start_seconds,
    );
    try std.testing.expectEqual(
        1,
        a2b_trimmed.mappings[0].input_bounds().end_seconds,
    );
}

test "Topology: Bezier construction/leak"
{
    const allocator = std.testing.allocator;
    
    const tm_a2b = (
        try Topology.init_bezier(
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
}

test "Topology: split_at_output_points"
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
                    .{ .in = 10, .out = 10, },
                    .{ .in = 20, .out = 0, },
                },
            },
        }
    ).mapping();

    const rf_topo = try Topology.init(
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

test "Topology: output_bounds w/ empty"
{
    const tm = Topology{
        .mappings = &.{
            (
             mapping.MappingEmpty{
                 .defined_range = .{
                     .start_seconds = -2,
                     .end_seconds = 0,
                 },
             }
            ).mapping(),
            .{ .linear = MIDDLE.MAPPINGS.LIN},
        },
    };
    const expected = MIDDLE.MAPPINGS.LIN.output_bounds();

    try std.testing.expectEqual(
        expected.start_seconds,
        tm.output_bounds().start_seconds,
    );

    try std.testing.expectEqual(
        expected.end_seconds,
        tm.output_bounds().end_seconds,
    );
}

test "Topology: project_instantaneous_cc and project_instantaneous_cc_inv"
{
    const allocator = std.testing.allocator;

    const TestFixture = struct {
        name: []const u8,
        input_to_output_topo: Topology,
        test_pts_fwd: []const curve.ControlPoint,
        test_pts_inv: []const [3]opentime.Ordinate,
        out_of_bounds_pts: []const opentime.Ordinate,
    };

    const tests = [_]TestFixture {
        .{
            .name = "v",
            .input_to_output_topo = MIDDLE.LIN_V_TOPO,
            .test_pts_fwd = &.{
                .{ .in = 0, .out = 0 },
                .{ .in = 2, .out = 16 },
                .{ .in = 4, .out = 32 },
                .{ .in = 5, .out = 40 },
                .{ .in = 6, .out = 32 },
                .{ .in = 8, .out = 16 },
            },
            .test_pts_inv = &.{
                .{ 32, 4, 6, },
                .{ 16, 2, 8, },
            },
            .out_of_bounds_pts = &.{
                -1, 11,
            },
        },
    };

    for (tests)
        |t|
    {
        errdefer std.debug.print(
            "topo: {s}\n",
            .{ t.input_to_output_topo }
        );
        for (t.test_pts_fwd)
            |pt|
        {
            errdefer {
                std.debug.print(
                    "error with test: {s} pt: {d}\n",
                    .{
                        t.name,
                        pt,
                    }
                );
            }

            // forward
            const measured_out = (
                try t.input_to_output_topo.project_instantaneous_cc(pt.in)
            );

            try std.testing.expectApproxEqAbs(
                pt.out,
                measured_out,
                opentime.util.EPSILON,
            );
        }

        for (t.test_pts_inv)
            |pts|
        {
            // reverse
            const measured_in = (
                try t.input_to_output_topo.project_instantaneous_cc_inv(
                    allocator,
                    pts[0],
                )
            );
            defer allocator.free(measured_in);

            try std.testing.expectEqualSlices(
                opentime.Ordinate,
                pts[1..],
                measured_in,
            );
        }
    }
}
