const std = @import("std");
const expectApproxEqAbs= std.testing.expectApproxEqAbs;

const opentime = @import("opentime/opentime.zig");
pub const string = opentime.string;

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

    pub fn project_ordinate(self: @This(), ord_to_project: f32) !f32 {
        _ = self;
        _ = ord_to_project;
        return error.NotImplemented;
    }
};

pub fn build_projection_operator(
    args: ProjectionOperatorArgs
) !ProjectionOperator
{
    return .{ .args = args };
}

test "Basic" {
    // sketching
    var cl = Clip {};

    var tr = Track {};
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
