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

    pub fn space(self: *Clip, label: string.latin_s8) !SpaceReference {
        return .{
            .target = ItemPtr{ .clip_ptr = self },
            .label= label,
        };
    }
};

pub const Gap = struct {
    name: ?string = null,
};

pub const Item = union(enum) {
    clip: Clip,
    gap: Gap,
    track: Track,
};

pub const ItemPtr = union(enum) {
    clip_ptr: *Clip,
    gap_ptr: *Gap,
    track_ptr: *Track,
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
    crv: opentime.TimeTopology,

    pub fn project_ordinate(self: @This(), ord_to_project: f32) !f32 {
        return self.crv.project_seconds(ord_to_project);
    }
};

pub fn build_projection_operator(
    args: ProjectionOperatorArgs
) !ProjectionOperator
{
    return .{
        .args = args,
        .crv = time_topology.TimeTopology.init_identity(
            .{.start_seconds = 0, .end_seconds = 10}
        )
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

// test "Track with clip with identity transform and bounds" {
//     var tr = Track {};
//     var cl = Clip { .source_range = .{ .start_seconds = 0, .end_seconds = 2 } };
//     try tr.append(.{ .clip = cl });
//
//     const track_to_clip = try build_projection_operator(
//         .{
//             .source = try tr.space("output"),
//             .destination =  try cl.space("media")
//         }
//     );
//
//     try expectError(
//         time_topology.TimeTopology.ProjectionError.OutOfBounds,
//         track_to_clip.project_ordinate(3)
//     );
// }

// test "Single Clip With Transform" {
//     // add an xform
//     const crv = opentime.curve.read_curve_json(
//         "curves/reverse_identity.curve.json"
//     );
//     var cl = Clip { .topology = crv };
//
//     var tr = Track {};
//     try tr.append(.{ .clip = cl });
//
//     const track_to_clip = ProjectionOperator.init(
//         try Track.space("output"),
//         try Clip.space("media")
//     );
//
//     cl.topology_from_curve(crv);
//
//     try expectApproxEqAbs(@as(f32, 5), try track_to_clip.project_ordinate(3));
// }
