const std = @import("std");
const expectApproxEqAbs= std.testing.expectApproxEqAbs;

const opentime = @import("opentime/opentime.zig");
pub const string = opentime.string;

const allocator = @import("opentime/allocator.zig");
const ALLOCATOR = allocator.ALLOCATOR;


// just for roughing tests in
pub const Clip = struct {
    name: ?string = null,
};

pub const Gap = struct {
    name: ?string = null,
};

pub const Item = union(enum) {
    clip: Clip,
    gap: Gap,
};

pub const Track = struct {
    name: ?string = null,

    children: std.ArrayList(Item) = std.ArrayList(Item).init(ALLOCATOR),

    pub fn append(self: *Track, item: Item) !void {
        try self.children.append(item);
    }
};

test "Basic" {
    // sketching
    var cl = Clip {};

    var tr = Track {};
    try tr.append(.{ .clip = cl });

    const proj_track_to_clip = ProjectionOperator.init(
        try Track.space("output"),
        try Clip.space("media")
    );

    const track_to_clip = try build_projection_operator(
        .{
            .source = try Track.space("output"),
            .destination =  try Clip.space("media")
        }
    );

    const track_to_clip = Track.space("output").projected_to(Clip.space("media"))

    try expectApproxEqAbs(@as(f32, 3), try proj_track_to_clip.ordinate(3));
}

test "Single Clip With Transform" {
    // add an xform
    const crv = opentime.curve.read_curve_json(
        "curves/reverse_identity.curve.json"
    );
    var cl = Clip { .topology = crv };

    var tr = Track {};
    try tr.append(.{ .clip = cl });

    const track_to_clip = ProjectionOperator.init(
        try Track.space("output"),
        try Clip.space("media")
    );

    cl.topology_from_curve(crv);

    try expectApproxEqAbs(@as(f32, 5), try track_to_clip.project_ordinate(3));
}
