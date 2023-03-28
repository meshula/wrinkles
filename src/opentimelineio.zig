const std = @import("std");
const expectApproxEqAbs= std.testing.expectApproxEqAbs;
const expectEqual = std.testing.expectEqual;
const expectError= std.testing.expectError;

const opentime = @import("opentime/opentime.zig");
const interval = @import("opentime/interval.zig");
const time_topology = @import("opentime/time_topology.zig");
const string = opentime.string;

const util = @import("opentime/util.zig");

const allocator = @import("opentime/allocator.zig");
const ALLOCATOR = allocator.ALLOCATOR;


// just for roughing tests in
pub const Clip = struct {
    name: ?string.latin_s8 = null,
    parent: ?ItemPtr = null,

    source_range: ?opentime.ContinuousTimeInterval = null,
    transform: ?time_topology.TimeTopology = null,

    pub fn trimmed_range(self: @This()) !opentime.ContinuousTimeInterval {
        if (self.source_range) |rng| {
            return rng;
        }

        // normally the available range check would go here
        return error.NoSourceRangeSet;
    }

    pub fn space(self: @This(), label: string.latin_s8) !SpaceReference {
        return .{
            .item = ItemPtr{ .clip_ptr = &self },
            .label= label,
        };
    }

    pub fn topology(self: @This()) time_topology.TimeTopology {
        if (self.source_range) |range| {
            return time_topology.TimeTopology.init_identity_finite(range);
        } else {
            return .{};
        }
    }

    pub const SPACES = enum(i8) {
        media = 0,
        output = 1,
    };

    pub fn build_projection_operator(
        self: @This(),
        source_label: string.latin_s8,
        destination_label: string.latin_s8,
    ) !ProjectionOperator {
        const source = std.meta.stringToEnum(SPACES, source_label);
        const destin = std.meta.stringToEnum(SPACES, destination_label);
        const proj_args = ProjectionOperatorArgs{
            .source = .{.item = ItemPtr{ .clip_ptr = &self}, .label = source_label},
            .destination = .{.item = ItemPtr{ .clip_ptr =&self}, .label = destination_label},
        };

        // Clip spaces and transformations
        //
        // key: 
        //   + space
        //   * transformation
        //
        // +--- OUTPUT
        // |
        // *--- (implicit) post transform->OUTPUT space (reset start time to 0)
        // |
        // +--- (implicit) post effects space
        // |
        // *--- .transform field (in real OTIO this would be relevant EFFECTS)
        // |
        // +--- (implicit) intrinsic
        // |
        // *--- (implicit) media->intrinsic xform: set the start time to 0
        // |
        // +--- MEDIA
        //
        // initially only exposing the MEDIA and OUTPUT spaces
        //

        // no projection
        if (source == destin) {
            return .{
                .args = proj_args,
                .topology = opentime.TimeTopology.init_inf_identity() 
            };
        }

        const output_to_post_transform = (
            opentime.TimeTopology.init_inf_identity()
        );

        const post_transform_to_intrinsic = (
            self.transform 
            orelse opentime.TimeTopology.init_inf_identity()
        );

        const output_to_intrinsic = (
            post_transform_to_intrinsic.project_topology(
                output_to_post_transform
            )
        );

        const intrinsic_bounds = try self.trimmed_range();
        const intrinsic_to_media = opentime.TimeTopology.init_identity_finite(
            intrinsic_bounds
        );

        const output_to_media = intrinsic_to_media.project_topology(
            output_to_intrinsic
        );

        if (source == SPACES.output) {
            return .{ .args = proj_args, .topology = output_to_media};
        } else {
            return .{
                .args = proj_args,
                .topology = try output_to_media.inverted(), 
            };
        }
    }
};

pub const Gap = struct {
    name: ?string = null,

    pub fn topology(self: @This()) time_topology.TimeTopology {
        _ = self;
        return .{};
    }

    pub fn build_projection_operator(
        self: @This(),
        source_label: string.latin_s8,
        destination_label: string.latin_s8,
    ) !ProjectionOperator {
        _ = self;
        _ = source_label;
        _ = destination_label;

        return error.NotImplemented;
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
    clip_ptr: *const Clip,
    gap_ptr: *const Gap,
    track_ptr: *const Track,

    pub fn init_Item(item: *Item) ItemPtr {
        return switch (item.*) {
            .clip => |*cp | .{ .clip_ptr = cp },
            .gap => |*gp| .{ .gap_ptr= gp },
            .track => |*tr| .{ .track_ptr = tr},
        };
    }

    pub fn topology(self: @This()) time_topology.TimeTopology {
        return switch (self) {
            .clip_ptr => |cl| cl.topology(),
            .gap_ptr => |gp| gp.topology(),
            .track_ptr => |tr| tr.topology(),
        };
    }

    /// builds a projection operator within a single item
    pub fn build_projection_operator(
        self: @This(),
        source_label: string.latin_s8,
        destination_label: string.latin_s8,
    ) !ProjectionOperator {
        return switch (self) {
            .clip_ptr => |cl| cl.build_projection_operator(
                source_label,
                destination_label
            ),
            .gap_ptr => |gp| gp.build_projection_operator(
                source_label,
                destination_label
            ),
            .track_ptr => |tr| tr.build_projection_operator(
                source_label,
                destination_label
            ),
        };
    }

    /// == impl
    pub fn equivalent_to(self: @This(), other: ItemPtr) bool {
        return switch(self) {
            .clip_ptr => |cl| cl == other.clip_ptr,
            .gap_ptr => |gp| gp == other.gap_ptr,
            .track_ptr => |tr| tr == other.track_ptr,
        };
    }

    /// fetch the contained parent pointer
    pub fn parent(self: @This()) ?ItemPtr {
        return switch(self) {
            .clip_ptr => self.clip_ptr.parent,
            .gap_ptr => null,
            .track_ptr => null,
        };
    }

    pub fn child_index_of(self: @This(), child: ItemPtr) !i32 {
        return switch(self) {
            .track_ptr => self.track_ptr.child_index_of(child),
            else => error.NotAContainer,
        };
    }
};

pub const Track = struct {
    name: ?string = null,

    children: std.ArrayList(Item) = std.ArrayList(Item).init(ALLOCATOR),

    pub fn append(self: *Track, item: Item) !void {
        try self.children.append(item);
        // item.set_parent(self);
    }

    pub fn space(self: *Track, label: string.latin_s8) !SpaceReference {
        return .{
            .item = ItemPtr{ .track_ptr = self },
            .label= label,
        };
    }

    pub fn topology(self: @This()) time_topology.TimeTopology {

        // build the bounds
        var bounds: ?interval.ContinuousTimeInterval = null;
        for (self.children.items) |it| {
            const it_bound = it.topology().bounds;
            if (bounds) |b| {
                bounds = interval.extend(b, it_bound);
            } else {
                bounds = it_bound;
            }
        }

        // unpack the optional
        const result_bound:interval.ContinuousTimeInterval = bounds orelse .{
            .start_seconds = 0,
            .end_seconds = 0,
        };

        return time_topology.TimeTopology.init_identity_finite(result_bound);
    }

    pub fn build_projection_operator(
        self: @This(),
        source_label: string.latin_s8,
        destination_label: string.latin_s8,
    ) !ProjectionOperator {
        _ = self;
        _ = source_label;
        _ = destination_label;

        return error.NotImplemented;
    }

    pub fn child_index_of(self: @This(), child_to_find: ItemPtr) !i32 {
        return for (self.children.items) |current, index| {
            if (std.meta.eql(current, child_to_find)) {
                break index;
            }
        } else null;
    }

    pub fn child_ptr_from_index(self: @This(), index: usize) ItemPtr {
        return ItemPtr.init_Item(&self.children.items[index]);
    }
};

test "add clip to track and check parent pointer" {
    var tr = Track {};
    const start_seconds:f32 = 1;
    const end_seconds:f32 = 10;
    var cl = Clip {
        .source_range = .{
            .start_seconds = start_seconds,
            .end_seconds = end_seconds 
        }
    };
    try tr.append(.{ .clip = cl });

    // try expectEqual(cl.parent.?, tr);
}

const SpaceReference = struct {
    item: ItemPtr,
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

const TopologicalMap = struct {
    map_itemptr_to_hash:std.AutoHashMap(ItemPtr, TopologicalPathHash),
    map_hash_to_itemptr:std.AutoHashMap(TopologicalPathHash, ItemPtr),

    pub fn root(self: @This()) ItemPtr {
        return self.map_hash_to_itemptr.get(0b10) orelse unreachable;
    }

    pub fn find_path(
        self: @This(),
        source: ItemPtr,
        destination: ItemPtr
    ) !TopologialPath {
        const source_hash = if (self.map_itemptr_to_hash.get(source)) |s| s else return error.NoPathAvailalbeInMap;
        const destination_hash = if (self.map_itemptr_to_hash.get(destination)) |d| d else return error.NoPathAvailalbeInMap;

        // @TODO:
        // only handle forward traversal at the moment
        if (source_hash > destination_hash) {
            return error.NotAForwardTraversal;
        }

        return error.NotImplemented;
    }
};

const TopologialPath = struct {
     map: TopologicalMap,
     hash: TopologicalPathHash,
     // probably needs a start and finish object?

     pub fn build_projection_operator(self: @This()) !ProjectionOperator {
         _ = self;
         return error.NotImplemented;
     }
 };

// for now using a u128 for encoded the paths
const TopologicalPathHash = u128;
const TopologicalPathHashMask = u64;
const TopologicalPathHashMaskTopBitCount = u8;

///
/// append (child_index + 1) 1's to the end of the parent_hash:
///
/// parent hash: 0b10 (the starting hash for the root node) 
/// child index 2:
/// result: 0b10111
///
///  parent hash: 0b100
///  child index: 0
///  result: 0b1001
///
///  each "0" means a stack (go _down_ the tree) each 1 means a sequential (go
///  across the tree)
///
fn sequential_child_hash(
    parent_hash:TopologicalPathHash,
    child_index:usize
) TopologicalPathHash 
{
    const ind_offset = child_index + 1;
    return (
        std.math.shl(TopologicalPathHash, parent_hash, ind_offset) 
        | (std.math.shl(TopologicalPathHash, 2 , ind_offset - 1) - 1)
    );
}

pub fn build_topological_map(
    root_item: ItemPtr
) !TopologicalMap 
{
    var map_itemptr_to_hash = std.AutoHashMap(
        ItemPtr,
        TopologicalPathHash,
    ).init(allocator.ALLOCATOR);
    var map_hash_to_itemptr = std.AutoHashMap(
        TopologicalPathHash,
        ItemPtr,
    ).init(allocator.ALLOCATOR);

    const Node = struct {
        path_hash: TopologicalPathHash,
        object: ItemPtr,
    };

    var stack = std.ArrayList(Node).init(allocator.ALLOCATOR);
    defer stack.deinit();

    const start_hash = 0b10;

    // root node
    try stack.append(.{.object = root_item, .path_hash = start_hash});

    while (stack.items.len > 0) {
        const current = stack.pop();

        try map_itemptr_to_hash.put(current.object, current.path_hash);
        try map_hash_to_itemptr.put(current.path_hash, current.object);

        // @TODO: internal spaces ? fine grained or no

        // children
        switch (current.object) {
            .track_ptr => |tr| { 
                for (tr.children.items) 
                    |*child, index| 
                {
                    const child_hash = sequential_child_hash(
                        current.path_hash,
                        index
                    );
                    const item_ptr:ItemPtr = switch (child.*) {
                        .clip => |*cl| .{ .clip_ptr = cl },
                        .gap => |*gp| .{ .gap_ptr = gp },
                        .track => |*tr_p| .{ .track_ptr = tr_p },
                    };
                    try stack.append(.{ .object= item_ptr, .path_hash = child_hash});
                }
            },
            else => {}
        }
    }

    return .{
        .map_itemptr_to_hash = map_itemptr_to_hash,
        .map_hash_to_itemptr = map_hash_to_itemptr,
    };
}

///
/// Forward Projection is from the output of the container (Track) to the input
/// space of the contained item (Clip).
///
/// This assertion is domain specific; the resulting document must be viewable
/// within the natural world in a monotonic temporal space.
///
/// example:
/// Track with a clip in it
/// Track has a 0.5 slowdown on it, clip has another 0.5 slowdown on it
///
/// Track.output: source
/// Clip.media: destination
///
///
pub fn build_projection_operator(
    args: ProjectionOperatorArgs
) !ProjectionOperator
{
    if (std.meta.eql(args.source.item, args.destination.item)) {
    // if (args.source.item.equivalent_to(args.destination.item)) {
        if (std.meta.eql(args.source.label, args.destination.label)) {
            // when the source space and destination space are identical,
            // should be some kind of bounded identity
            return error.APIUnavailable;
        }

        return args.source.item.build_projection_operator(
            args.source.label,
            args.destination.label
        );
    }

    // different objects
    const topological_map = try build_topological_map(args.source.item);

    // errors: can't find a path
    const topological_path = try topological_map.find_path(
        args.source.item, 
        args.destination.item
    );

    // errors: can't invert, not projectible path
    return try topological_path.build_projection_operator();
}

test "clip topology construction" {
    const start_seconds:f32 = 1;
    const end_seconds:f32 = 10;
    const cl = Clip {
        .source_range = .{
            .start_seconds = start_seconds,
            .end_seconds = end_seconds 
        }
    };

    const topo = cl.topology();

    try expectApproxEqAbs(
        start_seconds,
        topo.bounds.start_seconds,
        util.EPSILON,
    );

    try expectApproxEqAbs(
        end_seconds,
        topo.bounds.end_seconds,
        util.EPSILON,
    );
}

test "track topology construction" {
    try util.skip_test();

    var tr = Track {};
    const start_seconds:f32 = 1;
    const end_seconds:f32 = 10;
    const cl = Clip {
        .source_range = .{
            .start_seconds = start_seconds,
            .end_seconds = end_seconds 
        }
    };
    try tr.append(.{ .clip = cl });

    const topo =  tr.topology();

    try expectApproxEqAbs(
        start_seconds,
        topo.bounds.start_seconds,
        util.EPSILON,
    );

    try expectApproxEqAbs(
        end_seconds,
        topo.bounds.end_seconds,
        util.EPSILON,
    );
}

test "Track with clip with identity transform projection" {
    try util.skip_test();

    var tr = Track {};
    const start_seconds:f32 = 1;
    const end_seconds:f32 = 10;
    var cl = Clip {
        .source_range = .{
            .start_seconds = start_seconds,
            .end_seconds = end_seconds 
        }
    };
    try tr.append(.{ .clip = cl });

    const track_to_clip = try build_projection_operator(
        .{
            .source = try tr.space("output"),
            .destination =  try cl.space("media")
        }
    );

    // check the bounds
    try expectApproxEqAbs(
        start_seconds,
        track_to_clip.topology.bounds.start_seconds,
        util.EPSILON,
    );

    try expectApproxEqAbs(
        end_seconds,
        track_to_clip.topology.bounds.end_seconds,
        util.EPSILON,
    );

    // check the projection
    try expectApproxEqAbs(
        @as(f32, 3),
        try track_to_clip.project_ordinate(3),
        util.EPSILON,
    );
}

test "sequential_child_hash: math" {
    const start_hash:TopologicalPathHash = 0b10;

    try expectEqual(
        @as(TopologicalPathHash, 0b10111),
        sequential_child_hash(start_hash, 2)
    );

    try expectEqual(
        @as(TopologicalPathHash, 0b101),
        sequential_child_hash(start_hash, 0)
    );

    try expectEqual(
        @as(TopologicalPathHash, 0b10111111111111111111111),
        sequential_child_hash(start_hash, 20)
    );
}


fn top_bits(
    n: TopologicalPathHashMaskTopBitCount
) TopologicalPathHash
{
    // Handle edge cases
    const tmp:TopologicalPathHash = 0;
    if (n == 64) {
        return ~ tmp;
    }

    // Create a mask with all bits set
    var mask: TopologicalPathHash = ~tmp;

    // Shift the mask right by n bits

    mask = std.math.shl(TopologicalPathHash, mask, n);

    return ~mask;
}

pub fn path_exists_hash(
    in_a: TopologicalPathHash,
    in_b: TopologicalPathHash
) bool 
{
    var a = in_a;
    var b = in_b;

    if ((a == 0) or (b == 0)) {
        return false;
    }

    if (b>a) { 
        a = in_b;
        b = in_a;
    }

    const r = @clz(b) - @clz(a);
    if (r == 0) {
        return (a == b);
    }

    // line b up with a
    // eg: b=101 and a1010, b -> 1010
    b <<= @intCast(u7,r);

    var mask : TopologicalPathHash = 0;
    mask = ~mask;

    mask = std.math.shl(TopologicalPathHash, mask, r);

    return ((a & mask) == (b & mask));
}

test "sequential_child_hash: path tests" {
    // 0 never has a path
    try expectEqual(false, path_exists_hash(0b0, 0b101));

    // different bitwidths
    try expectEqual(true, path_exists_hash(0b10, 0b101));
    try expectEqual(true, path_exists_hash(0b101, 0b10));
    try expectEqual(true, path_exists_hash(0b101, 0b1011101010111000));
    try expectEqual(true, path_exists_hash(0b10111010101110001111111, 0b1011101010111000));

    // test maximum width
    var mask : TopologicalPathHash = 0;
    mask = ~mask;
    try expectEqual(false, path_exists_hash(0, mask));
    try expectEqual(true, path_exists_hash(mask, mask));
    try expectEqual(true, path_exists_hash(mask/2, mask));
    try expectEqual(true, path_exists_hash(mask, mask/2));
    try expectEqual(false, path_exists_hash(mask - 1, mask));
    try expectEqual(false, path_exists_hash(mask, mask - 1));

    // mismatch
    // same width
    try expectEqual(false, path_exists_hash(0b100, 0b101));
    // different width
    try expectEqual(false, path_exists_hash(0b10, 0b110));
    try expectEqual(false, path_exists_hash(0b11, 0b101));
    try expectEqual(false, path_exists_hash(0b100, 0b101110));
}

test "PathMap: Track with clip with identity transform topological" {
    var tr = Track {};
    var cl = Clip { .source_range = .{ .start_seconds = 0, .end_seconds = 2 } };

    // a copy -- which is why we can't use `cl` in our searches.
    try tr.append(.{ .clip = cl });

    const root = ItemPtr{ .track_ptr = &tr };

    const map = try build_topological_map(root);

    try expectEqual(root, map.root());

    try expectEqual(@as(usize, 2), map.map_hash_to_itemptr.count());
    try expectEqual(@as(usize, 2), map.map_itemptr_to_hash.count());

    const root_hash = map.map_itemptr_to_hash.get(root) orelse 0;

    try expectEqual(@as(TopologicalPathHash, 0b10), root_hash);

    const clip = tr.child_ptr_from_index(0);
    const clip_hash = map.map_itemptr_to_hash.get(clip) orelse 0;

    try expectEqual(@as(TopologicalPathHash, 0b101), clip_hash);

    try expectEqual(true, path_exists_hash(clip_hash, root_hash));

    // const items_on_path = try map.items_on_path(root, clip);
    //
    // try expectEqual([]ItemPtr{root,clip}, items_on_path);

    // @TODO debate here:
    // (track (track clip (track (clip clip))))

   //  const projector = try build_projection_operator_for_items(
   //      .{
   //          .source = try tr.space("output"),
   //          .destination =  try tr.children.items[0].clip.space("media")
   //      },
   //      items_on_path,
   // );

    // const track_to_clip = try build_projection_operator(
    //     .{
    //         .source = try tr.space("output"),
    //         .destination =  try tr.children.items[0].clip.space("media")
    //     }
    // );

    // check the bounds
    // try expectApproxEqAbs(
    //     (cl.source_range orelse interval.ContinuousTimeInterval{}).start_seconds,
    //     track_to_clip.topology.bounds.start_seconds,
    //     util.EPSILON,
    // );
    //
    // try expectApproxEqAbs(
    //     (cl.source_range orelse interval.ContinuousTimeInterval{}).end_seconds,
    //     track_to_clip.topology.bounds.end_seconds,
    //     util.EPSILON,
    // );
    //
    // try expectError(
    //     time_topology.TimeTopology.ProjectionError.OutOfBounds,
    //     track_to_clip.project_ordinate(3)
    // );
}

test "Projection: Track with clip with identity transform and bounds" {
    // not ready yet
    try util.skip_test();

    var tr = Track {};
    var cl = Clip { .source_range = .{ .start_seconds = 0, .end_seconds = 2 } };
    try tr.append(.{ .clip = cl });

    const track_to_clip = try build_projection_operator(
        .{
            .source = try tr.space("output"),
            .destination =  try tr.children.items[0].clip.space("media")
        }
    );

    // check the bounds
    try expectApproxEqAbs(
        (cl.source_range orelse interval.ContinuousTimeInterval{}).start_seconds,
        track_to_clip.topology.bounds.start_seconds,
        util.EPSILON,
    );

    try expectApproxEqAbs(
        (cl.source_range orelse interval.ContinuousTimeInterval{}).end_seconds,
        track_to_clip.topology.bounds.end_seconds,
        util.EPSILON,
    );

    try expectError(
        time_topology.TimeTopology.ProjectionError.OutOfBounds,
        track_to_clip.project_ordinate(3)
    );
}

test "Single Clip Media to Output Identity transform" {
    //
    //                  0                 7           10
    // output space       [-----------------*-----------)
    //                               ....n.....
    //
    //                  0                 7           10
    // output space       [-----------------*-----------)
    // intrinsic space    [-----------------*-----------)
    // clip output space  [---)[---------)[-*------)[---)
    //                    0   1 0        5 0       3 0  1
    //
    //
    //              0                 7           10
    // output space [-----------------*-----------)
    // media space  [-----------------*-----------)
    //              100               107         110 (seconds)
    //              
    const source_range = interval.ContinuousTimeInterval{
        .start_seconds = 100,
        .end_seconds = 110 
    };

    const cl = Clip { .source_range = source_range };

    // output->media
    {
        const clip_output_to_media = try build_projection_operator(
            .{
                .source =  try cl.space("output"),
                .destination = try cl.space("media"),
            }
        );

        // given only a boundary, expect an identity topology over the bounds
        // with a single segment
        try expectEqual(
            @as(usize, 1),
            clip_output_to_media.topology.mapping.len
        );

        try expectApproxEqAbs(
            @as(f32, 103),
            try clip_output_to_media.project_ordinate(3),
            util.EPSILON,
        );
    }

    // @TODO: NEXT HERE --- either inversion or cross-object projection

    // media->output
    // {
    //     const clip_media_to_output = try build_projection_operator(
    //         .{
    //             .source =  try cl.space("media"),
    //             .destination = try cl.space("output"),
    //         }
    //     );
    //
    //     try expectApproxEqAbs(
    //         @as(f32, 3),
    //         try clip_media_to_output.project_ordinate(103),
    //         util.EPSILON,
    //     );
    // }

}

// test "Single Clip Media to Output Inverse transform" {
//     //
//     // xform: reverse (linear w/ -1 slope)
//     //
//     //              0                 7           10
//     // output       [-----------------*-----------)
//     // media        [-----------------*-----------)
//     //              110               103         100 (seconds)
//     //              
//     const source_range = interval.ContinuousTimeInterval{
//         .start_seconds = 100,
//         .end_seconds = 110 
//     };
//
//     const inv_tx = time_topology.TimeTopology.init_linear_start_end(
//         source_range, 
//         source_range.end_seconds,
//         source_range.start_seconds,
//     );
//
//     const cl = Clip { .source_range = source_range, .transform = inv_tx };
//
//     // output->media
//     {
//         const clip_output_to_media = try build_projection_operator(
//             .{
//                 .source =  try cl.space("output"),
//                 .destination = try cl.space("media"),
//             }
//         );
//
//         std.debug.print("\n", .{});
//         try expectApproxEqAbs(
//             @as(f32, 107),
//             try clip_output_to_media.project_ordinate(3),
//             util.EPSILON,
//         );
//     }
//
//     // media->output
//     {
//         const clip_media_to_output = try build_projection_operator(
//             .{
//                 .source =  try cl.space("media"),
//                 .destination = try cl.space("output"),
//             }
//         );
//
//         try expectApproxEqAbs(
//             @as(f32, 3),
//             try clip_media_to_output.project_ordinate(107),
//             util.EPSILON,
//         );
//     }
// }

// @TODO: START HERE ---------------------------------------------vvvvvvvv-----
// test "Single Clip With Inverse Transform" {
    // const clip_output_to_media = try build_projection_operator(
    //     .{
    //         .source = try cl.space("output"),
    //         .destination =  try cl.space("media")
    //     }
    // );
    //
    //
    // // check the bounds
    // try expectApproxEqAbs(
    //     bounds.start_seconds,
    //     clip_output_to_media.topology.bounds.start_seconds,
    //     util.EPSILON,
    // );
    //
    // try expectApproxEqAbs(
    //     bounds.end_seconds,
    //     clip_output_to_media.topology.bounds.end_seconds,
    //     util.EPSILON,
    // );
    //
    // std.debug.print("\nPROJECTION\n", .{});
    //
    // try expectApproxEqAbs(
    //     @as(f32, 3),
    //     try clip_output_to_media.project_ordinate(7),
    //     util.EPSILON,
    // );
// }
