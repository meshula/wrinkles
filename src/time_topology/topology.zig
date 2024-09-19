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

        const end_points = (
            std.ArrayList(opentime.Ordinate).init(allocator)
        );
        end_points.ensureTotalCapacity(in_mappings.len + 1);
        errdefer end_points.deinit();

        end_points.append(cursor);

        // validate mappings
        for (in_mappings)
            |in_m|
        {
            const d = in_m.input_bounds().duration;
            if (d <= 0) {
                return error.InvalidMappingForTopology;
            }

            cursor += d;

            try end_points.append(d);
        }

        return .{
            .mappings = try allocator.dupe(in_mappings),
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
};

const EMPTY = TopologyMapping{
    .end_points_input = &.{},
    .mappings = &.{}
};


/// build a topological mapping.Mapping from a to c
pub fn join(
    allocator: std.mem.Allocator,
    args: struct{
        a2b: TopologyMapping, // split on output
        b2c: TopologyMapping, // split in input
    },
) TopologyMapping
{
    const a2b_b_bounds = (
        try args.a2b.intervals_output(allocator)
    );

    var split_points = std.ArrayList(
        opentime.Ordinate
    ).init(allocator);

    for (a2b_b_bounds)
        |a2b_b_int|
    {

    }
}

test "TopologyMapping: LEFT/RIGHT -> EMPTY"
{
    if (true) {
        return error.SkipZigTest;
    }

    const allocator = std.testing.allocator;

    const tm_left = TopologyMapping.init(
        allocator,
        .{ mapping.LEFT.AFF,}
    );
    defer tm_left.deinit(allocator);

    const tm_right = TopologyMapping.init(
        allocator,
        .{ mapping.RIGHT.AFF,}
    );
    defer tm_right.deinit(allocator);

    const should_be_empty = join(
        allocator,
        .{
            .a2b =  tm_left,
            .b2c = tm_right,
        }
    );

    try std.testing.expectEqual(EMPTY, should_be_empty);
}

