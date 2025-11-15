const std = @import("std");

/// mutable topology
pub const TopologyBuilder = struct {
    mappings: std.ArrayList(mapping.Mapping) = .empty,

    pub fn init(
        allocator: std.mem.Allocator,
        source: Topology,
    ) !TopologyBuilder
    {
        var self = TopologyBuilder{};

        for (source.mappings)
            |m|
        {
            try self.mappings.append(
                allocator,
                try m.clone(allocator),
            );
        }

        return self;
    }

    pub fn input_bounds(
        self: @This(),
    ) opentime.ContinuousInterval
    {
        return (
            Topology{ .mappings = self.mappings.items }
        ).output_bounds();
    }

    pub fn output_bounds(
        self: @This(),
    ) opentime.ContinuousInterval
    {
        return (
            Topology{ .mappings = self.mappings.items }
        ).output_bounds();
    }

    pub fn project_instantaneous_cc(
        self: @This(),
        input_ord: opentime.Ordinate,
    ) opentime.ProjectionResult
    {
        return (
            Topology{ .mappings = self.mappings.items }
        ).project_instantaneous_cc(input_ord);
    }

    pub fn trimmed_in_input_space(
        self: *@This(),
        allocator: std.mem.Allocator,
        new_input_bounds: opentime.ContinuousInterval,
    ) !void
    {
        const ib = self.input_bounds();
        var new_bounds = opentime.interval.intersect(
            new_input_bounds,
            ib,
        ) orelse {
            for (self.mappings.items)
                |m|
            {
                m.deinit(allocator);
            }

            self.mappings.deinit(allocator);
            return;
        };

        if (
            new_bounds.start.lteq(ib.start)
            and new_bounds.end.gteq(ib.end)
        ) 
        {
            return;
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

    pub fn trimmed_in_output_space(
        self: @This(),
        allocator: std.mem.Allocator,
        target_output_range: opentime.interval.ContinuousInterval,
    ) !void
    {
        var new_mappings: std.ArrayList(mapping.Mapping) = .{};

        const ob = self.output_bounds();
        if (
            target_output_range.start.lteq(ob.start)
            and target_output_range.end.gteq(ob.end)
        ) {
            return;
        }

        for (self.mappings.items, 0..)
            |m, m_ind|
        {
            const m_in_range = m.input_bounds();
            const m_out_range = m.output_bounds();

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
                    try new_mappings.append(
                        allocator,
                        try m.clone(allocator),
                    );
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
                    shrunk_input_bounds.start.gt(m_in_range.start)
                    and m_ind > 0

                ) 
                {
                    // empty left
                    try new_mappings.append(
                        allocator,
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
                    try new_mappings.append(
                        allocator,
                        try shrunk_m.clone(allocator),
                    );
                }

                if (
                    shrunk_input_bounds.end.lt(m_in_range.end)
                    and m_ind < self.mappings.items.len-1
                )
                {
                    // empty right
                    try new_mappings.append(
                        allocator,
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
                try new_mappings.append(
                    allocator,
                    (
                     mapping.MappingEmpty{
                         .defined_range = m_in_range,
                     }
                    ).mapping(),
                );
            }
        }

        return;
        // return .{
        //     .mappings = try new_mappings.toOwnedSlice(allocator),
        // };
    }
};
