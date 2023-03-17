const std = @import("std");
const expectApproxEqAbs= std.testing.expectApproxEqAbs;
const expectError= std.testing.expectError;

const opentime = @import("opentime/opentime.zig");
const time_topology = @import("opentime/time_topology.zig");
const string = opentime.string;

const util = @import("opentime/util.zig");

const allocator = @import("opentime/allocator.zig");
const ALLOCATOR = allocator.ALLOCATOR;


// just for roughing tests in
pub const Clip = struct {
    name: ?string = null,
    source_range: ?opentime.ContinuousTimeInterval = null,

    pub fn space(self: *Clip, label: string.latin_s8) !SpaceReference {
        return .{
            .target = ItemPtr{ .clip_ptr = self },
            .label= label,
        };
    }

    pub fn topology(self: @This()) time_topology.TimeTopology {
        if (self.source_range) |range| {
            return time_topology.TimeTopology.init_identity(range);
        } else {
            return .{};
        }
    }
};

pub const Gap = struct {
    name: ?string = null,

    pub fn topology(self: @This()) time_topology.TimeTopology {
        _ = self;
        return .{};
    }
};

pub const Item = union(enum) {
    clip: Clip,
    gap: Gap,
    track: Track,

    pub fn topology(self: @This()) time_topology.TimeTopology {
        return switch (self) {
            .clip => |cl| cl.topology(),
            .gap => |gp| gp.topology(),
            .track => |tr| tr.topology(),
        };
    }
};

pub const ItemPtr = union(enum) {
    clip_ptr: *Clip,
    gap_ptr: *Gap,
    track_ptr: *Track,

    pub fn topology(self: @This()) time_topology.TimeTopology {
        return switch (self) {
            .clip_ptr => |cl| cl.topology(),
            .gap_ptr => |gp| gp.topology(),
            .track_ptr => |tr| tr.topology(),
        };
    }
};

pub const Track = struct {
    name: ?string = null,

    children: std.ArrayList(Item) = std.ArrayList(Item).init(ALLOCATOR),

    pub fn append(self: *Track, item: Item) !void {
        try self.children.append(item);
    }

    pub fn space(self: *Track, label: string.latin_s8) !SpaceReference {
        return .{
            .target = ItemPtr{ .track_ptr = self },
            .label= label,
        };
    }

    pub fn topology(self: @This()) time_topology.TimeTopology {
        _  = self;
        return .{};
    }
};

const SpaceReference = struct {
    target: ItemPtr,
    label: string.latin_s8 = "output",
};

const ProjectionOperatorArgs = struct {
    source: SpaceReference,
    destination: SpaceReference,
};

const ProjectionOperator = struct {
    args: ProjectionOperatorArgs,
    topology: opentime.TimeTopology,

    pub fn project_ordinate(self: @This(), ord_to_project: f32) !f32 {
        return self.topology.project_seconds(ord_to_project);
    }
};

pub fn build_projection_operator(
    args: ProjectionOperatorArgs
) !ProjectionOperator
{
    const source_topology = args.source.target.topology();
    const destination_topology = args.destination.target.topology();

    const source_to_dest_topo = source_topology.project_topology(destination_topology);

    return .{
        .args = args,
        .topology = source_to_dest_topo,
    };
}

test "Track with clip with identity transform" {
    var tr = Track {};
    var cl = Clip {};
    try tr.append(.{ .clip = cl });

    const track_to_clip = try build_projection_operator(
        .{
            .source = try tr.space("output"),
            .destination =  try cl.space("media")
        }
    );

    try expectApproxEqAbs(
        @as(f32, 3),
        try track_to_clip.project_ordinate(3),
        util.EPSILON,
    );
}

test "Track with clip with identity transform and bounds" {
    var tr = Track {};
    var cl = Clip { .source_range = .{ .start_seconds = 0, .end_seconds = 2 } };
    try tr.append(.{ .clip = cl });

    const track_to_clip = try build_projection_operator(
        .{
            .source = try tr.space("output"),
            .destination =  try cl.space("media")
        }
    );

    try expectError(
        time_topology.TimeTopology.ProjectionError.OutOfBounds,
        track_to_clip.project_ordinate(3)
    );
}

// test "Single Clip With Transform" {
//     // add an xform
//     const topology = opentime.curve.read_curve_json(
//         "curves/reverse_identity.curve.json"
//     );
//     var cl = Clip { .topology = topology };
//
//     var tr = Track {};
//     try tr.append(.{ .clip = cl });
//
//     const track_to_clip = ProjectionOperator.init(
//         try Track.space("output"),
//         try Clip.space("media")
//     );
//
//     cl.topology_from_curve(topology);
//
//     try expectApproxEqAbs(@as(f32, 5), try track_to_clip.project_ordinate(3));
// }
