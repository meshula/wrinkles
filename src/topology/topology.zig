//! Topology implementation

const std = @import("std");

const opentime = @import("opentime");
const curve = @import("curve");

pub const mapping = @import("mapping.zig");

/// A Topology binds regions of a one dimensional space to a sequence of right
/// met monotonic mappings, separated by a list of end points.  There are
/// implicit "Empty" mappings outside of the end points which map to no values
/// before and after the mappings contained by the Topology.
pub const Topology = struct {
    /// Mappings that compose the topology.  Memory owned by the topology.
    mappings: []const mapping.Mapping,

    /// An Empty Topology.
    pub const empty = Topology{ .mappings = &.{} };

    /// A Topology with a single, infinite identity mapping.
    pub const identity_infinite = Topology{
        .mappings = &.{ .identity_infinite, }
    };

    pub fn init(
        allocator: std.mem.Allocator,
        in_mappings: []const mapping.Mapping,
    ) !Topology
    {
        if (in_mappings.len == 0)
        {
            return .empty;
        }

        return .{
            // @TODO: should clone() mappings as well
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

        var result_mappings: std.ArrayList(mapping.Mapping) = .{};
        defer result_mappings.deinit(allocator);

        for (mono_crvs)
            |mc|
        {
            try result_mappings.append(
                allocator,
                (
                 mapping.MappingCurveLinearMonotonic{
                     .input_to_output_curve = try mc.clone(allocator),
                 }
                ).mapping()
            );
        }

        return .{
            .mappings = try result_mappings.toOwnedSlice(
                allocator,
            ),
        };
    }

    /// Construct a topology from a cubic Bezier `curve.Bezier`.
    ///
    /// Linearizes and splits at critical points.
    pub fn init_bezier(
        allocator: std.mem.Allocator,
        crv: curve.Bezier,
    ) !Topology
    {
        const lin = try crv.linearized(allocator);
        defer lin.deinit(allocator);

        const lin_split = try lin.split_at_critical_points(
            allocator
        );
        // Free the outer slice, not the inner mappings.
        defer allocator.free(lin_split);

        const new_mappings = try allocator.alloc(
            mapping.Mapping,
            lin_split.len,
        );

        for (lin_split, new_mappings)
            |mono_lin, *dst_mapping|
        {
            dst_mapping.* = (
                mapping.MappingCurveLinearMonotonic {
                    .input_to_output_curve = mono_lin,
                }
            ).mapping();
        }

        return .{ .mappings = new_mappings, };
    }

    /// initialize an affine with a single affine transformation in its mapping
    /// slice.  Requires an allocator because still requires that the mapping
    /// slice be allocated.
    pub fn init_affine(
        allocator: std.mem.Allocator,
        aff: mapping.MappingAffine,
    ) !Topology
    {
        return Topology{
            .mappings = try allocator.dupe(
                mapping.Mapping,
                &.{ aff.mapping() }
            )
        };
    }

    /// build a topology with a single identittopologyover the range
    /// specified
    pub fn init_identity(
        allocator: std.mem.Allocator,
        range: opentime.ContinuousInterval,
    ) error{OutOfMemory}!Topology
    {
        return .{
            .mappings = try allocator.dupe(
                mapping.Mapping,
                &.{
                    (
                     mapping.MappingAffine{
                         .input_bounds_val = range,
                         .input_to_output_xform = .identity,
                     }
                    ).mapping(),
                },
            )
        };
    }

    /// custom formatter for std.fmt
    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
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
            try writer.print(
                "({s}, {f})",
                .{
                    @tagName(m),
                    m.input_bounds(),
                },
            );
        }

        if (self.mappings.len > 0) {
            try writer.print(
                "] -> output space: {f} }}",
                .{ self.output_bounds() }
            );
        }
        else {
            try writer.print("] -> output space: (null) }}", .{});
        }
    }

    pub fn clone(
        self: @This(),
        allocator: std.mem.Allocator,
    ) !Topology
    {
        var new_mappings: std.ArrayList(mapping.Mapping,) = .{};
        try new_mappings.ensureTotalCapacity(
            allocator,
            self.mappings.len
        );
        for (self.mappings)
            |m|
        {
            new_mappings.appendAssumeCapacity(
                try m.clone(allocator),
            );
        }

        return .{
            .mappings = (
                try new_mappings.toOwnedSlice(allocator)
            ),
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
        if (self.mappings.len > 0) 
        {
            allocator.free(self.mappings);
        }
    }

    pub fn input_bounds(
        self: @This(),
    ) ?opentime.ContinuousInterval
    {
        if (self.mappings.len == 0)
        {
            return null;
        }

        return .{
            .start = (
                self.mappings[0].input_bounds() 
                orelse return null
            ).start,
            .end = (
                (
                 self.mappings[self.mappings.len - 1].input_bounds() 
                 orelse return null
                ).end
            ),
        };
    }

    /// compute the bounds in the output space of this topology
    pub fn output_bounds(
        self: @This(),
    ) ?opentime.ContinuousInterval
    {
        if (self.mappings.len == 0) {
            return null;
        }

        var maybe_bounds:?opentime.ContinuousInterval = null;

        for (self.mappings)
            |m|
        {
            switch (m) {
                .empty => continue,
                else => {
                    if (maybe_bounds)
                        |b|
                    {
                        maybe_bounds = opentime.interval.extend(
                            b,
                            m.output_bounds()
                            orelse return null,
                        );
                    }
                    else {
                        maybe_bounds = m.output_bounds() orelse return null;
                    }
                }
            }
        }

        return maybe_bounds;
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

        var result: std.ArrayList(opentime.Ordinate) = .{};
        defer result.deinit(allocator);
        try result.ensureTotalCapacity(
            allocator,
            1 + self.mappings.len,
        );

        result.appendAssumeCapacity(
            (
             self.mappings[0].input_bounds()
             orelse return error.InvalidMapping
            ).start,
        );

        for (self.mappings)
            |m|
        {
            const m_input_bounds = (
                m.input_bounds() orelse return error.InvalidMapping
            );
            result.appendAssumeCapacity(m_input_bounds.end);
        }

        return try result.toOwnedSlice(allocator);
    }

    pub fn trim_in_input_space(
        self: @This(),
        allocator: std.mem.Allocator,
        new_input_bounds: opentime.ContinuousInterval,
    ) !Topology
    {
        const ib = (
            self.input_bounds()
            orelse return .empty
        );

        var new_bounds = opentime.interval.intersect(
            new_input_bounds,
            ib,
        ) orelse return .empty;

        if (
            new_bounds.start.lteq(ib.start)
            and new_bounds.end.gteq(ib.end)
        ) 
        {
            return self.clone(allocator);
        }

        new_bounds.start = opentime.max(
            new_bounds.start,
            ib.start,
        );
        new_bounds.end = opentime.min(
            new_bounds.end,
            ib.end,
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
        )
            |left_pt, right_pt, left_ind |
        {
            if (
                left_pt.lt(new_bounds.start)
                and right_pt.gt(new_bounds.start)
            )
            {
                maybe_left_map_ind = left_ind;
            }

            if (
                left_pt.lt(new_bounds.end)
                and right_pt.gt(new_bounds.end)
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
                    new_bounds.start,
                )
            );

            left_splits[0].deinit(allocator);
            defer left_splits[1].deinit(allocator);

            var right_splits = (
                try left_splits[1].split_at_input_point(
                    allocator,
                    new_bounds.end,
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
        var trimmed_mappings: std.ArrayList(mapping.Mapping) = .{};
        defer trimmed_mappings.deinit(allocator);

        var middle_start:usize = 0;
        var middle_end:usize = self.mappings.len;

        if (maybe_left_map_ind)
            |left_ind|
        {
            const split_mapping_left = (
                try self.mappings[left_ind].split_at_input_point(
                    allocator,
                    new_bounds.start,
                )
            );
            try trimmed_mappings.append(
                allocator,
                split_mapping_left[1],
            );
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
            try trimmed_mappings.append(
                allocator,
                try m.clone(allocator),
            );
        }

         if (maybe_right_map_ind)
             |right_ind|
         {
             const split_mapping_right = (
                 try self.mappings[right_ind].split_at_input_point(
                     allocator,
                     new_bounds.end,
                 )
             );
             try trimmed_mappings.append(
                 allocator,
                 split_mapping_right[0],
             );
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
        target_output_range: opentime.interval.ContinuousInterval,
    ) !Topology
    {
        var new_mappings: std.ArrayList(mapping.Mapping) = .empty;
        defer new_mappings.deinit(allocator);
        try new_mappings.ensureTotalCapacity(
            allocator,
            self.mappings.len * 3,
        );

        const ob = (
            self.output_bounds()
            orelse return .empty
        );
        if (
            target_output_range.start.lteq(ob.start)
            and target_output_range.end.gteq(ob.end)
        ) {
            return try self.clone(allocator);
        }

        for (self.mappings, 0..)
            |m, m_ind|
        {
            const m_in_range = (
                m.input_bounds() 
                orelse return error.InvalidMapping
            );
            const m_out_range = (
                 m.output_bounds() 
                 orelse return error.InvalidMapping
            );

            const maybe_overlap = (
                opentime.interval.intersect(
                    target_output_range,
                    m_out_range,
                )
            );

            if (maybe_overlap != null)
            {
                // nothing to trim
                if (
                    m_out_range.start.gteq(target_output_range.start)
                    and m_out_range.end.lteq(target_output_range.end)
                )
                {
                    // nothing to trim
                    new_mappings.appendAssumeCapacity(try m.clone(allocator));
                    continue;
                }

                const shrunk_m = try m.shrink_to_output_interval(
                    allocator,
                    target_output_range,
                ) orelse return error.InvalidMapping;
                defer shrunk_m.deinit(allocator);

                // mapping should be correct, bounds should exist
                const shrunk_input_bounds = (
                    shrunk_m.input_bounds().?
                );

                if (
                    shrunk_input_bounds.start.gt(m_in_range.start)
                    and m_ind > 0

                ) 
                {
                    // empty left
                    new_mappings.appendAssumeCapacity(
                        (
                         mapping.MappingEmpty{
                             .defined_range = .{
                                 .start = m_in_range.start,
                                 .end = shrunk_input_bounds.start,
                             },
                         }
                        ).mapping(),
                    );
                }

                if (
                    shrunk_input_bounds.start.lt(shrunk_input_bounds.end)
                )
                {
                    // trimmed mapping
                    new_mappings.appendAssumeCapacity(
                        try shrunk_m.clone(allocator),
                    );
                }

                if (
                    shrunk_input_bounds.end.lt(m_in_range.end)
                    and m_ind < self.mappings.len-1
                )
                {
                    // empty right
                    new_mappings.appendAssumeCapacity(
                        (
                         mapping.MappingEmpty{
                             .defined_range = .{
                                 .start = shrunk_input_bounds.end,
                                 .end = m_in_range.end,
                             },
                         }
                        ).mapping()
                    );
                }
            }
            else 
            {
                // no intersection
                new_mappings.appendAssumeCapacity(
                    (
                     mapping.MappingEmpty{
                         .defined_range = m_in_range,
                     }
                    ).mapping(),
                );
            }
        }

        return .{
            .mappings = (
                try new_mappings.toOwnedSlice(allocator)
            ),
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
        const ib = (
            self.input_bounds()
            orelse return .empty
        );

        if (
            input_points.len == 0
            or (input_points[0].gteq(ib.end))
            or (input_points[input_points.len-1].lteq(ib.start))
        ) 
        {
            return self.clone(allocator);
        }

        var result_mappings: std.ArrayList(mapping.Mapping) = .{};
        defer result_mappings.deinit(allocator);

        try result_mappings.ensureTotalCapacity(
            allocator,
            self.mappings.len + input_points.len,
        );

        for (self.mappings)
            |m|
        {
            const new_result = try m.split_at_input_points(
                allocator,
                input_points,
            );
            defer allocator.free(new_result);

            result_mappings.appendSliceAssumeCapacity(new_result);
        }

        const result = Topology{
            .mappings = (
                try result_mappings.toOwnedSlice(allocator)
            ),
        };

        return result;
    }
    
    /// return a unique list of points in the output space, ascending sort
    pub fn end_points_output(
        self: @This(),
        allocator: std.mem.Allocator,
    ) ![]opentime.Ordinate
    {
        var result: std.ArrayList(opentime.Ordinate) = .{};

        var set = (
            std.HashMap(
                opentime.Ordinate,
                void,
                struct{
                    pub fn hash(
                        _: @This(),
                        key: opentime.Ordinate,
                    ) u64
                    {
                        return @bitCast(key.as(opentime.Ordinate.InnerType));
                    }

                    pub fn eql(
                        _: @This(),
                        fst: opentime.Ordinate,
                        snd: opentime.Ordinate,
                    ) bool
                    {
                        return fst.eql(snd);
                    }
                },
                std.hash_map.default_max_load_percentage,
            ).init(allocator)
        );
        try set.ensureTotalCapacity(@intCast(self.mappings.len*2));
        defer set.deinit();

        for (self.mappings)
            |m|
        {
            const b = (
                m.output_bounds() 
                orelse return error.InvalidMapping
            );

            for (&[_]opentime.Ordinate{ b.start, b.end })
                |new_point|
            {
                if (set.contains(new_point)) 
                {
                    try result.append(allocator,new_point);
                    try set.put(new_point, {});
                }
            }
        }

        std.mem.sort(
            opentime.Ordinate,
            result.items,
            {},
            opentime.sort.asc(opentime.Ordinate)
        );

        return try result.toOwnedSlice(allocator);
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

        var result_endpoints: std.ArrayList(opentime.Ordinate) = .{};
        defer result_endpoints.deinit(allocator);

        var result_mappings: std.ArrayList(mapping.Mapping) = .{};
        defer result_mappings.deinit(allocator);

        var input_points_in_bounds: std.ArrayList(opentime.Ordinate) = .{};
        try input_points_in_bounds.ensureTotalCapacity(
            allocator,
            output_points.len
        );
        defer input_points_in_bounds.deinit(allocator);

        for (self.mappings)
            |m|
        {
            const m_bounds_in = (
                m.input_bounds() 
                orelse return error.InvalidMapping
            );
            const m_bounds_out = (
                m.output_bounds() 
                orelse return error.InvalidMapping
            );

            switch (m) {
                .empty => {
                    try result_mappings.append(
                        allocator,
                        try m.clone(allocator),
                    );
                },
                else => {
                    input_points_in_bounds.clearRetainingCapacity();

                    for (output_points)
                        |out_pt|
                    {
                        if (
                            m_bounds_out.overlaps(out_pt)
                            and out_pt.gt(m_bounds_out.start)
                            and out_pt.lt(m_bounds_out.end)
                        )
                        {
                            const in_pt = (
                                try m.project_instantaneous_cc_inv(
                                    out_pt
                                ).ordinate()
                            );

                            if (
                                in_pt.gt(m_bounds_in.start) 
                                and in_pt.lt(m_bounds_in.end)
                            )
                            {
                                try input_points_in_bounds.append(
                                    allocator,
                                    in_pt,
                                );
                            }
                        }
                    }

                    // none of the input points are in bounds
                    if (input_points_in_bounds.items.len == 0)
                    {
                        // just append the mapping as is
                        try result_mappings.append(
                            allocator,
                            try m.clone(allocator),
                        );
                        continue;
                    }

                    std.mem.sort(
                        opentime.Ordinate,
                        input_points_in_bounds.items,
                        {},
                        opentime.sort.asc(opentime.Ordinate),
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
                            allocator,
                            try new_mappings[0].clone(allocator)
                        );
                        
                        m_clone.deinit(allocator);
                        m_clone = try new_mappings[1].clone(allocator);
                    }

                    try result_mappings.append(allocator,m_clone);
                    try result_endpoints.appendSlice(
                        allocator,
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
        input_ord: opentime.Ordinate,
    ) opentime.ProjectionResult
    {
        const ib = (
            self.input_bounds()
            orelse return .OUTOFBOUNDS
        );
        if (ib.is_instant()) 
        {
            if (ib.start.eql(input_ord)) {
                return .{ 
                    // already checked that input bounds are valid, so can
                    // access output bounds directly
                    .SuccessInterval = self.output_bounds().?,
                };
            }
            return .OUTOFBOUNDS;
        }

        return self.project_instantaneous_cc_assume_in_bounds(
            input_ord,
        );
    }

    pub fn project_instantaneous_cc_assume_in_bounds(
        self: @This(),
        input_ord: opentime.Ordinate,
    ) opentime.ProjectionResult
    {
        for (self.mappings)
            |m|
        {
            if (
                (
                 m.input_bounds() 
                 orelse return .OUTOFBOUNDS
                ).overlaps(input_ord)
            )
            {
                return m.project_instantaneous_cc_assume_in_bounds(input_ord);
            }
        }

        return .{
            .OutOfBounds = null,
        };
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
        var input_ordinates: std.ArrayList(opentime.Ordinate) = .{};
        errdefer input_ordinates.deinit(allocator);

        for (self.mappings)
            |m|
        {
            const m_output_bounds = (
                m.output_bounds()
                orelse return error.InvalidMapping
            );

            if (
                m_output_bounds.overlaps(output_ord)
                or output_ord.eql(m_output_bounds.end)
            )
            {
                try input_ordinates.append(
                    allocator,
                    try m.project_instantaneous_cc_inv(output_ord).ordinate()
                );
            }
        }

        return try input_ordinates.toOwnedSlice(allocator);
    }

    /// Topology guarantees a monotonic, continuous input space.  When
    /// inverting, the output space must be split at critical points and put
    /// into different Topologies for the caller to manage.
    pub fn inverted(
        self: @This(),
        allocator: std.mem.Allocator,
    ) ![]const Topology
    {
        if (self.mappings.len == 0) {
            return try allocator.dupe(Topology, &.{ .empty });
        }

        var result: std.ArrayList(Topology) = .empty;

        var current_mappings:std.ArrayList(mapping.Mapping) = .empty;
        defer current_mappings.deinit(allocator);

        var maybe_input_range: ?opentime.ContinuousInterval = null;

        for (self.mappings)
            |m|
        {
            // mappings are 1:1, can always invert
            const m_inverted = try m.inverted(allocator);

            if (maybe_input_range)
                |current_range|
            {
                if (
                    opentime.interval.intersect(
                        current_range,
                        (
                              m_inverted.input_bounds() 
                              orelse return error.InvalidMapping
                        ),
                    ) != null
                    and current_mappings.items.len > 0
                )
                {
                    try result.append(
                        allocator,
                        .{
                            .mappings = (
                                try current_mappings.toOwnedSlice(allocator)
                            ),
                        },
                    );
                }
                else 
                {
                    // continue the current topology
                    maybe_input_range = opentime.interval.extend(
                        current_range,
                        (
                         m_inverted.input_bounds()
                         orelse return error.InvalidMapping
                        ),
                    );
                    try current_mappings.append(allocator,m_inverted);
                }
            }
            else {
                try current_mappings.append(allocator,m_inverted);
                maybe_input_range = m_inverted.input_bounds();
            }
        }

        try result.append(
            allocator,
            .{
                .mappings = (
                    try current_mappings.toOwnedSlice(allocator)
                ),
            },
        );

        return try result.toOwnedSlice(allocator);
    }
};

test "Topology.split_at_input_points"
{
    const m_split = try MIDDLE.AFF_TOPO.split_at_input_points(
        std.testing.allocator,
        &.{ 
            opentime.Ordinate.init(0), 
            opentime.Ordinate.init(2), 
            opentime.Ordinate.init(3), 
            opentime.Ordinate.init(15),
        },
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
        range: opentime.ContinuousInterval_BaseType,
        expected: opentime.ContinuousInterval_BaseType,
        mapping_count: usize,
    };

    const tests = [_]TestCase{
        .{
            .name = "no trim",
            .range = .{
                .start = -1,
                .end = 11,
            },
            .expected = .{
                .start = 0,
                .end = 10,
            },
            .mapping_count = 1,
        },
        .{
            .name = "left",
            .range = .{
                .start = 3,
                .end = 11,
            },
            .expected = .{
                .start = 3,
                .end = 10,
            },
            .mapping_count = 1,
        },
        .{
            .name = "right trim",
            .range = .{
                .start = -1,
                .end = 7,
            },
            .expected = .{
                .start = 0,
                .end = 7,
            },
            .mapping_count = 1,
        },
        .{
            .name = "both",
            .range = .{
                .start = 3,
                .end = 7,
            },
            .expected = .{
                .start = 3,
                .end = 7,
            },
            .mapping_count = 1,
        },
    };

    for (topos)
        |tp|
    {
        errdefer opentime.dbg_print(@src(), 
            "over topology: {s}",
            .{ tp.name },
        );

        for (tests)
            |t|
        {
            // trim left but not right
            const tm = try tp.topo.trim_in_input_space(
                allocator,
                opentime.ContinuousInterval.init(t.range),
            );
            defer tm.deinit(allocator);

            errdefer opentime.dbg_print(@src(), 
                "error with test name: {s}",
                .{ t.name },
            );

            try opentime.expectOrdinateEqual(
                t.expected.start,
                (
                          tm.input_bounds() 
                          orelse return error.InvalidBounds
                ).start,
            );
            try opentime.expectOrdinateEqual(
                t.expected.end,
                (
                  tm.input_bounds() 
                  orelse return error.InvalidBounds
                ).end,
            );

            try opentime.expectOrdinateEqual(
                (
                      tm.mappings[0].input_bounds()
                      orelse return error.InvalidBounds
                ).duration(), 
                (
                 tm.input_bounds() 
                 orelse return error.InvalidBounds
                ).duration(),
            );

            try std.testing.expectEqual(
                t.mapping_count,
                tm.mappings.len,
            );
        }

        // separate "no overlap" test
        const tm = try tp.topo.trim_in_input_space(
            allocator,
            opentime.ContinuousInterval.init(
                .{ .start = 11, .end = 13, },
            ),
        );
        defer tm.deinit(allocator);

        try std.testing.expectEqualSlices(
            mapping.Mapping,
            Topology.empty.mappings,
            tm.mappings,
        );
    }
}

/// build a topological mapping from a to c
pub fn join(
    parent_allocator: std.mem.Allocator,
    topologies: struct{
        a2b: Topology, // split on output
        b2c: Topology, // split in input
    },
) !Topology
{
    var arena = std.heap.ArenaAllocator.init(parent_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const a2b = topologies.a2b;
    const b2c = topologies.b2c;

    const a2b_output_bounds = (
        a2b.output_bounds() 
        orelse return .empty
    );

    if (a2b_output_bounds.is_instant())
    {
        // compute the projected flat value
        const maybe_output_value = (
            b2c.project_instantaneous_cc(
                a2b_output_bounds.start
            )
        );

        const output_value = switch (maybe_output_value) {
            .OutOfBounds,  => {
                return .empty;
            },
            .SuccessInterval => unreachable,
            .SuccessOrdinate => |val| val,
        };

        const input_range = a2b.input_bounds().?;

        return try (
            Topology{
                .mappings = &.{
                    (
                     mapping.MappingCurveLinearMonotonic{
                         .input_to_output_curve = .{
                             .knots = &.{
                                 .{
                                     .in = input_range.start,
                                     .out = output_value,
                                 },
                                 .{
                                     .in = input_range.end,
                                     .out = output_value,
                                 },
                             },
                         },
                     }
                    ).mapping(),
                },
            }
        ).clone(parent_allocator);
    }

    // first trim both to the intersection range
    const b_range = opentime.interval.intersect(
        a2b_output_bounds,
        b2c.input_bounds() orelse return .empty,
        // or return an empty topology
    ) orelse return .empty;

    const a2b_trimmed_in_b = try a2b.trim_in_output_space(
        allocator,
        b_range,
    );
    const b2c_trimmed_in_b = try b2c.trim_in_input_space(
        allocator,
        b_range,
    );

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
        opentime.sort.asc(opentime.Ordinate),
    );
    defer allocator.free(a2b_split_endpoints_b);

    const b2c_split = (
        try b2c_trimmed_in_b.split_at_input_points(
            allocator,
            a2b_split_endpoints_b,
        )
    );

    var a2c_mappings: std.ArrayList(mapping.Mapping) = .empty;
    try a2c_mappings.ensureTotalCapacity(
        parent_allocator,
        a2b_split.mappings.len + b2c_split.mappings.len,
    );

    // at this point the start and end points are the same and there are the
    // same number of endpoints
    for (a2b_split.mappings)
        |a2b_m|
    {
        const a2b_m_ob = (
            a2b_m.output_bounds()
            orelse return error.InvalidMapping
        );
        for (b2c_split.mappings)
            |b2c_m|
        {
            const b2c_m_ib = (
                b2c_m.input_bounds()
                orelse return error.InvalidMapping
            );
            if (
                opentime.interval.intersect(
                    a2b_m_ob,
                    b2c_m_ib,
                ) != null
                or (
                    a2b_m_ob.is_instant()
                    and b2c_m_ib.start.lteq(a2b_m_ob.start)
                    and b2c_m_ib.end.gteq(a2b_m_ob.end)
                )
            ) 
            {
                const a2c_m = try mapping.join(
                    parent_allocator,
                    .{ 
                        .a2b = a2b_m,
                        .b2c = b2c_m,
                    },
                );

                a2c_mappings.appendAssumeCapacity(a2c_m);
                break;
            }
        }
    }

    const result= Topology{
        .mappings = try a2c_mappings.toOwnedSlice(
            parent_allocator,
        ),
    };
    return result;
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
            .{
                .segments = &.{
                    .{
                        .p0 = .init(.{ .in = 1, .out = 0 }),
                        .p1 = .init(.{ .in = 1, .out = 5 }),
                        .p2 = .init(.{ .in = 5, .out = 5 }),
                        .p3 = .init(.{ .in = 5, .out = 1 }),
                    },
                },
            }
        )
    );

    // b2c mapping and topology
    const m_b2c_left = (
        mapping.MappingCurveLinearMonotonic{
            .input_to_output_curve = .{
                .knots = &.{
                    curve.ControlPoint.init(.{ .in = 0, .out = 0, }),
                    curve.ControlPoint.init(.{ .in = 2, .out = 4, }),
                },
            }
        }
    ).mapping();

    const m_b2c_middle = (
        mapping.MappingCurveLinearMonotonic{
            .input_to_output_curve = .{
                .knots = &.{
                    curve.ControlPoint.init(.{ .in = 2, .out = 2, }),
                    curve.ControlPoint.init(.{ .in = 4, .out = 2, }),
                },
            }
        }
    ).mapping();

    const m_b2c_right = (
        mapping.MappingCurveLinearMonotonic{
            .input_to_output_curve = .{
                .knots = &.{
                    curve.ControlPoint.init(.{ .in = 4, .out = 2, }),
                    curve.ControlPoint.init(.{ .in = 6, .out = 0, }),
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

test "Topology: join (slides)" 
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
    
    const a2c_ib = (
        a2c.input_bounds() orelse return error.InvalidBounds
    );
    try opentime.expectOrdinateEqual(
        1,
        a2c_ib.start,
    );
    try opentime.expectOrdinateEqual(
        5,
        a2c_ib.end,
    );

    const a2c_ob = (
        a2c.output_bounds()
        orelse return error.InvalidBounds
    );
    try opentime.expectOrdinateEqual(
        // 0.123208,
        0,
        a2c_ob.start,
    );
    try opentime.expectOrdinateEqual(
        3.999999995,
        a2c_ob.end,
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
    comptime int_in: opentime.ContinuousInterval_BaseType,
) type
{
    return struct {
        const MAPPINGS = mapping.test_structs(int_in);

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

// const LEFT = test_structs(
//     .{
//         .start = -2,
//         .end = 2,
//     }
// );
const MIDDLE = test_structs(
    .{
        .start = 0,
        .end = 10,
    }
);
// const RIGHT = test_structs(
//     .{
//         .start = 8,
//         .end = 12,
//     }
// );
//
test "Topology: trim_in_output_space"
{
    const allocator = std.testing.allocator;

    const TestCase = struct {
        name: []const u8,
        target: opentime.ContinuousInterval_BaseType,
        expected: opentime.ContinuousInterval_BaseType,
    };
    const tests = [_]TestCase{
        .{
            .name = "no trim",
            .target = .{
                .start = -1,
                .end = 41 
            },
            .expected = .{
                .start = 0,
                .end = 40,
            },
        },
        .{
            .name = "left trim",
            .target = .{
                .start = 3,
                .end = 41 
            },
            .expected = .{
                .start = 3,
                .end = 40,
            },
        },
        .{
            .name = "right trim",
            .target = .{
                .start = -1,
                .end = 7 
            },
            .expected = .{
                .start = 0,
                .end = 7,
            },
        },
        .{
            .name = "both trim",
            .target = .{
                .start = 3,
                .end = 7 
            },
            .expected = .{
                .start = 3,
                .end = 7,
            },
        },
        // all trimmed
    };

    const INPUT_TOPO = MIDDLE.LIN_TOPO;
    try std.testing.expect(
        (
         INPUT_TOPO.output_bounds() 
         orelse return error.ShouldHaveBounds
        ).start.is_finite()
    );
    try std.testing.expect(
        // already checked that output_bounds is not null
        INPUT_TOPO.output_bounds().?.end.is_finite()
    );

    for (tests)
        |t|
    {
        const trimmed = (
            try INPUT_TOPO.trim_in_output_space(
                allocator,
                opentime.ContinuousInterval.init(t.target),
            )
        );
        defer trimmed.deinit(allocator);

        errdefer {
            opentime.dbg_print(@src(), 
                (
                      "error with test: {s}\n"
                      ++ " input: {f} / output range: {f}\n"
                      ++ " target range: {f}\n"
                      ++ " trimmed: {f} / output range: {f}\n"
                      ++ " expected: {f}"
                ),
               .{
                   t.name,
                   INPUT_TOPO,
                   INPUT_TOPO.output_bounds(),
                   opentime.ContinuousInterval.init(t.target),
                   trimmed,
                   trimmed.output_bounds(),
                   opentime.ContinuousInterval.init(t.expected),
               }
            );
        }

        try std.testing.expectEqual(
            1,
            trimmed.mappings.len,
        );

        const trimmed_output_bounds = (
            trimmed.output_bounds()
            orelse return error.InvalidBounds
        );
        try opentime.expectOrdinateEqual(
            t.expected.start,
            trimmed_output_bounds.start,
        );
        try opentime.expectOrdinateEqual(
            t.expected.end,
            trimmed_output_bounds.end,
        );
    }

    const rising = (
        mapping.MappingCurveLinearMonotonic{
            .input_to_output_curve = curve.Linear.Monotonic {
                .knots = &.{
                    curve.ControlPoint.init(.{ .in = 0, .out = 0, }),
                    curve.ControlPoint.init(.{ .in =10, .out = 10, }),
                },
            },
        }
    ).mapping();
    const falling = (
        mapping.MappingCurveLinearMonotonic{
            .input_to_output_curve = curve.Linear.Monotonic {
                .knots = &.{
                    curve.ControlPoint.init(.{ .in =10, .out = 10, }),
                    curve.ControlPoint.init(.{ .in = 20, .out = 0, }),
                },
            },
        }
    ).mapping();

    const rf_topo = Topology{
        .mappings = &.{ rising, falling },
    };

    const rf_topo_trimmed = try rf_topo.trim_in_output_space(
        allocator,
        opentime.ContinuousInterval.init(
            .{ .start = 1, .end = 8, }
        ),
    );
    defer rf_topo_trimmed.deinit(allocator);

    {
        const result = (
            rf_topo_trimmed.output_bounds()
            orelse return error.InvalidBounds
        );

        try opentime.expectOrdinateEqual(
            1,
            result.start,
        );
        try opentime.expectOrdinateEqual(
            8,
            result.end,
        );
    }
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
        a2b.output_bounds().?,
        b2c.input_bounds().?,
    ) orelse return error.OutOfBounds;

    const a2b_trimmed = (
        try a2b.trim_in_output_space(
            allocator,
            b_range,
        )
    );
    defer a2b_trimmed.deinit(allocator);

    const a2b_output_bounds = (
        a2b_trimmed.output_bounds()
        orelse return error.InvalidBounds
    );
    try std.testing.expectEqual(
        b_range.start,
        a2b_output_bounds.start,
    );
    try std.testing.expectEqual(
        b_range.end,
        a2b_output_bounds.end,
    );
}

test "Topology: trim_in_output_space (trim to multiple split bug)"
{
    const allocator = std.testing.allocator;

    const a2b = try Topology.init_from_linear_monotonic(
        allocator,
        .{
            .knots = &.{
                curve.ControlPoint.init(.{ .in = 0, .out = 0}),
                curve.ControlPoint.init(.{ .in = 2, .out = 2}),
            }
        }
    );
    defer a2b.deinit(allocator);

    const a2b_trimmed = try a2b.trim_in_output_space(
        allocator, 
        opentime.ContinuousInterval.init(.{ .start = 0.5, .end = 1 }),
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
    const ib = (
        a2b_trimmed.mappings[0].input_bounds() 
        orelse return error.InvalidBounds
    );
    try opentime.expectOrdinateEqual(
        0.5,
        ib.start,
    );
    try opentime.expectOrdinateEqual(
        1,
        ib.end,
    );
}

test "Topology: Bezier construction/leak"
{
    const allocator = std.testing.allocator;
    
    const tm_a2b = (
        try Topology.init_bezier(
            allocator, 
            .{
                .segments = &.{
                    .{
                        .p0 = .init(.{ .in = 1, .out = 0 }),
                        .p1 = .init(.{ .in = 1, .out = 5 }),
                        .p2 = .init(.{ .in = 5, .out = 5 }),
                        .p3 = .init(.{ .in = 5, .out = 1 }),
                    },
                },
            }
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
                    curve.ControlPoint.init(.{ .in = 0, .out = 0, }),
                    curve.ControlPoint.init(.{ .in =10, .out = 10, }),
                },
            },
        }
    ).mapping();
    const falling = (
        mapping.MappingCurveLinearMonotonic{
            .input_to_output_curve = curve.Linear.Monotonic {
                .knots = &.{
                    curve.ControlPoint.init(.{ .in = 10, .out = 10, }),
                    curve.ControlPoint.init(.{ .in = 20, .out = 0, }),
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
        &.{ 
            opentime.Ordinate.init(0), 
            opentime.Ordinate.init(3), 
            opentime.Ordinate.init(7), 
            opentime.Ordinate.init(11),
        }
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
                 .defined_range = (
                     opentime.ContinuousInterval.init(
                         .{ .start = -2, .end = 0, }
                     )
                 ),
             }
            ).mapping(),
            .{ .linear = MIDDLE.MAPPINGS.LIN},
        },
    };
    const expected = MIDDLE.MAPPINGS.LIN.output_bounds().?;

    try std.testing.expectEqual(
        expected.start,
        tm.output_bounds().?.start,
    );

    try std.testing.expectEqual(
        expected.end,
        tm.output_bounds().?.end,
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
                curve.ControlPoint.init(.{ .in = 0, .out = 0 }),
                curve.ControlPoint.init(.{ .in = 2, .out = 16 }),
                curve.ControlPoint.init(.{ .in = 4, .out = 32 }),
                curve.ControlPoint.init(.{ .in = 5, .out = 40 }),
                curve.ControlPoint.init(.{ .in = 6, .out = 32 }),
                curve.ControlPoint.init(.{ .in = 8, .out = 16 }),
            },
            .test_pts_inv = &.{
                .{ 
                    opentime.Ordinate.init(32), 
                    opentime.Ordinate.init(4),
                    opentime.Ordinate.init(6), 
                },
                .{ 
                    opentime.Ordinate.init(16), 
                    opentime.Ordinate.init(2), 
                    opentime.Ordinate.init(8), 
                },
            },
            .out_of_bounds_pts = &.{
                opentime.Ordinate.init(-1),
                opentime.Ordinate.init(11),
            },
        },
    };

    for (tests)
        |t|
    {
        errdefer opentime.dbg_print(@src(), 
            "topo: {f}",
            .{ t.input_to_output_topo }
        );
        for (t.test_pts_fwd)
            |pt|
        {
            errdefer {
                opentime.dbg_print(@src(), 
                    "error with test: {s} pt: {f}",
                    .{
                        t.name,
                        pt,
                    }
                );
            }

            // forward
            const measured_out = (
                t.input_to_output_topo.project_instantaneous_cc(pt.in)
            );

            try opentime.expectOrdinateEqual(
                pt.out,
                measured_out.SuccessOrdinate,
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

test "Topology: init_affine"
{
    const allocator = std.testing.allocator;

    const t_aff = try Topology.init_affine(
        allocator,
        .{
            .input_bounds_val = (
                opentime.ContinuousInterval.init(
                    .{ .start = 0, .end = 10, }
                )
            ),
            .input_to_output_xform = .{
                .offset = opentime.Ordinate.init(12),
                .scale = opentime.Ordinate.init(2),
            },
        },
    );
    defer t_aff.deinit(allocator);

    try opentime.expectOrdinateEqual(
        20,
        t_aff.project_instantaneous_cc(
            opentime.Ordinate.init(4)
        ).ordinate(),
    );
}

test "Topology: join affine with ident"
{
    const allocator = std.testing.allocator;

    const aff = try Topology.init_affine(
        allocator,
        .{
            .input_bounds_val = (
                opentime.ContinuousInterval.init(
                    .{ .start = 0, .end = 8, }
                )
            ),
            .input_to_output_xform = .{
                .offset = .one,
                .scale = .one,
            },
        },
    );
    defer aff.deinit(allocator);

    const result = try join(
        allocator,
        .{
            .a2b = .identity_infinite,
            .b2c = aff,
        },
    );
    defer result.deinit(allocator);

    try std.testing.expect(result.mappings.len > 0);
    try std.testing.expectEqual(
        .affine,
        std.meta.activeTag(result.mappings[0]),
    );
    try opentime.expectOrdinateEqual(
        4,
        try result.project_instantaneous_cc(
            opentime.Ordinate.init(3)
        ).ordinate(),
    );
}

test "Topology output_bounds are sorted after negative scale"
{
    const allocator = std.testing.allocator;

    // offset = 0
    {
        const aff = try Topology.init_affine(
            allocator,
            .{
                .input_bounds_val = (
                    opentime.ContinuousInterval.init(
                        .{ .start = 0, .end = 8, }
                    )
                ),
                .input_to_output_xform = .{
                    .offset = opentime.Ordinate.zero,
                    .scale = opentime.Ordinate.init(-1),
                },
            },
        );
        defer aff.deinit(allocator);

        const output_bounds = aff.output_bounds();

        try std.testing.expectEqual(
            opentime.ContinuousInterval{
                .start = opentime.Ordinate.init(-8),
                .end = .zero,
            }, 
            output_bounds,
        );
    }

    // offset = 1
    {
        const aff = try Topology.init_affine(
            allocator,
            .{
                .input_bounds_val = (
                    opentime.ContinuousInterval.init(
                        .{ .start = 0, .end = 8, }
                    )
                ),
                .input_to_output_xform = .{
                    .offset = opentime.Ordinate.init(1),
                    .scale = opentime.Ordinate.init(-1),
                },
            },
        );
        defer aff.deinit(allocator);

        const output_bounds = aff.output_bounds();

        try std.testing.expectEqual(
            opentime.ContinuousInterval{
                .start = opentime.Ordinate.init(-7),
                .end = .one,
            }, 
            output_bounds,
        );
    }
}

test "Topology: init_bezier"
{
    const allocator = std.testing.allocator;

    const bez = curve.Bezier{
        .segments = &.{ 
            .init_from_start_end(
                .init(.{ .in = 0, .out = 0 }),
                .init(.{ .in = 10, .out = 20 }),
            ),
        }
    };

    const topo_bez = try Topology.init_bezier(
        allocator,
        bez,
    );
    defer topo_bez.deinit(std.testing.allocator);

    try opentime.expectOrdinateEqual(
        10,
        topo_bez.project_instantaneous_cc(.init(5)).ordinate(),
    );
}
