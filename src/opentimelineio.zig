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

    pub fn space(self: @This(), label: SpaceLabel) !SpaceReference {
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
        source_label: SpaceLabel,
        destination_label: SpaceLabel,
    ) !ProjectionOperator {
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
        if (source_label == destination_label) {
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

        if (source_label == SpaceLabel.output) {
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
        source_label: SpaceLabel,
        destination_label: SpaceLabel,
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
        source_label: SpaceLabel,
        destination_label: SpaceLabel,
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

    // return list of SpaceReference for this object
    pub fn spaces(self: @This()) ![]SpaceReference {
        var result = std.ArrayList(SpaceReference).init(allocator.ALLOCATOR);

        switch (self) {
            .clip_ptr => {
                try result.append( .{ .item = self, .label = SpaceLabel.output});
                try result.append( .{ .item = self, .label = SpaceLabel.media});
            },
            .track_ptr => {
                try result.append( .{ .item = self, .label = SpaceLabel.output});
                try result.append( .{ .item = self, .label = SpaceLabel.intrinsic});
                try result.append( .{ .item = self, .label = SpaceLabel.child});
            },
            else => {}
        }

        return result.items;
    }

    pub fn space(self: @This(), label: SpaceLabel) !SpaceReference {
        return .{ .item = self, .label = label };
    }
};

pub const Track = struct {
    name: ?string = null,

    children: std.ArrayList(Item) = std.ArrayList(Item).init(ALLOCATOR),

    pub fn append(self: *Track, item: Item) !void {
        try self.children.append(item);
        // item.set_parent(self);
    }

    pub fn space(self: *Track, label: SpaceLabel) !SpaceReference {
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
        source_label: SpaceLabel,
        destination_label: SpaceLabel,
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

const SpaceLabel = enum(i8) {
    output = 0,
    intrinsic,
    media,
    child,
};

const SpaceReference = struct {
    item: ItemPtr,
    label: SpaceLabel,
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
    map_space_to_hash:std.AutoHashMap(SpaceReference, TopologicalPathHash),
    map_hash_to_space:std.AutoHashMap(TopologicalPathHash, SpaceReference),

    pub fn root(self: @This()) SpaceReference {
        return self.map_hash_to_space.get(0b10) orelse unreachable;
    }

    pub fn build_projection_operator(
        self: @This(),
        args: ProjectionOperatorArgs,
    ) !ProjectionOperator {
        const source_hash = if (self.map_space_to_hash.get(args.source)) |hash| hash else return error.SourceNotInMap;
        const destination_hash = if (self.map_space_to_hash.get(args.destination)) |hash| hash else return error.DestinationNotInMap;

        if (path_exists_hash(source_hash, destination_hash) == false) {
            return error.NoPathBetweenSpaces;
        }

        // only supporting forward projection at the moment
        if (source_hash > destination_hash) {
            return error.ReverseProjectionNotYetSupported;
        }

        return error.NotImplemented;
    }

    fn label_for_node(
        ref: SpaceReference,
        hash: TopologicalPathHash
    ) !string.latin_s8 
    {
        const item_kind = switch(ref.item) {
            .track_ptr => "track",
            .clip_ptr => "clip",
            .gap_ptr => "gap",
        };
        return std.fmt.allocPrint(
            allocator.ALLOCATOR,
            "{s}_{s}_{b}", 
            .{
                item_kind,
                @tagName(ref.label),
                hash
            }
        );
    }

    pub fn write_dot_graph(self:@This(), filepath: string.latin_s8) !void {
        const root_space = self.root(); 

        // open the file
        const file = try std.fs.createFileAbsolute(filepath,.{});
        defer file.close();

        try file.writeAll("digraph OTIO_TopologicalMap {\n");

        const Node = struct { space: SpaceReference, hash: TopologicalPathHash };

        var stack = std.ArrayList(Node).init(allocator.ALLOCATOR);

        try stack.append(.{ .space = root_space, .hash = 0b10});

        while (stack.items.len > 0) {
            const current = stack.pop();
            const current_label = try label_for_node(current.space, current.hash);

            const left = current.hash << 1;

            if (self.map_hash_to_space.get(left)) |next| {
                const next_label = try label_for_node(next, left);
                try file.writeAll(
                    try std.fmt.allocPrint(
                        allocator.ALLOCATOR,
                        "  {s} -> {s}\n",
                        .{current_label, next_label}
                    )
                );
                try stack.append(.{.space = next, .hash = left});
            } else {
                try file.writeAll(
                    try std.fmt.allocPrint(
                        allocator.ALLOCATOR,
                        "  {b} \n  [shape=point]{s} -> {b}\n",
                        .{left, current_label, left }
                    )
                );
            }

            const right = ((current.hash << 1) + 1) << 1;
            if (self.map_hash_to_space.get(right)) |next| {
                const next_label = try label_for_node(next, right);
                try file.writeAll(
                    try std.fmt.allocPrint(
                        allocator.ALLOCATOR,
                        "  {s} -> {s}\n",
                        .{current_label, next_label}
                    )
                );
                try stack.append(.{.space = next, .hash = right});
            } else {
                try file.writeAll(
                    try std.fmt.allocPrint(
                        allocator.ALLOCATOR,
                        "  {b} [shape=point]\n  {s} -> {b}\n",
                        .{right, current_label, right }
                    )
                );
            }
        }

        try file.writeAll("}\n");
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

fn depth_child_hash(
    parent_hash: TopologicalPathHash,
    child_index:usize
) TopologicalPathHash
{
    const ind_offset = child_index + 1;
    return std.math.shl(TopologicalPathHash, parent_hash, ind_offset);
}

test "depth_child_hash: math" {
    const start_hash:TopologicalPathHash = 0b1;
    
    try expectEqual(@as(TopologicalPathHash, 0b10), depth_child_hash(start_hash, 0));
    try expectEqual(@as(TopologicalPathHash, 0b100), depth_child_hash(start_hash, 1));
    try expectEqual(@as(TopologicalPathHash, 0b1000), depth_child_hash(start_hash, 2));
    try expectEqual(@as(TopologicalPathHash, 0b10000), depth_child_hash(start_hash, 3));
}

pub fn build_topological_map(
    root_item: ItemPtr
) !TopologicalMap 
{
    var map_space_to_hash = std.AutoHashMap(
        SpaceReference,
        TopologicalPathHash,
    ).init(allocator.ALLOCATOR);
    var map_hash_to_space = std.AutoHashMap(
        TopologicalPathHash,
        SpaceReference,
    ).init(allocator.ALLOCATOR);

    const Node = struct {
        path_hash: TopologicalPathHash,
        object: ItemPtr,
    };

    var stack = std.ArrayList(Node).init(allocator.ALLOCATOR);
    defer stack.deinit();

    const start_hash = 0b1;

    // root node
    try stack.append(.{.object = root_item, .path_hash = start_hash});

    while (stack.items.len > 0) {
        const current = stack.pop();

        var current_hash = current.path_hash;

        // object intermediate spaces
        const spaces = try current.object.spaces();
        defer ALLOCATOR.free(spaces);

        for (spaces) |space_ref, index| {
            const child_hash = depth_child_hash(current_hash, index);
            std.debug.print(
                "[{d}] adding space: '{s}' with hash {b}\n",
                .{index, @tagName(space_ref.label), child_hash }
            );
            try map_space_to_hash.put(space_ref, child_hash);
            try map_hash_to_space.put(child_hash, space_ref);

            if (index == (spaces.len - 1)) {
                current_hash = child_hash;
            }
        }

        // transforms to children
        switch (current.object) {
            .track_ptr => |tr| { 
                for (tr.children.items) 
                    |*child, index| 
                {
                    const child_hash = sequential_child_hash(
                        current_hash,
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
        .map_space_to_hash = map_space_to_hash,
        .map_hash_to_space = map_hash_to_space,
    };
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

    var i:i32 = 0;
    while (i < 10) {
        var cl2 = Clip {
            .source_range = .{
                .start_seconds = start_seconds,
                .end_seconds = end_seconds 
            }
        };
        try tr.append(.{ .clip = cl2 });
        i+=1;
    }

    const map = try build_topological_map(.{ .track_ptr = &tr });

    try map.write_dot_graph("/var/tmp/test.dot");

    try util.skip_test();
    const track_to_clip = try map.build_projection_operator(
        .{
            .source = try tr.space(SpaceLabel.output),
            .destination =  try cl.space(SpaceLabel.media)
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

pub fn path_between_hash(
    in_a: TopologicalPathHash,
    in_b: TopologicalPathHash,
) !TopologicalPathHash
{
    var a = in_a;
    var b = in_b;
    
    if (a < b) {
        a = in_b;
        b = in_a;
    }

    if (path_exists_hash(a, b) == false) {
        return error.NoPathBetweenSpaces;
    }

    const r = @clz(b) - @clz(a);
    if (r == 0) {
        return 0;
    }

    // line b up with a
    // eg: b=101 and a1010, b -> 1010
    b <<= @intCast(u7,r);

    const path = a ^ b;

    return path;
}

test "path_between_hash: math" {
    const TestData = struct{
        source: TopologicalPathHash,
        dest: TopologicalPathHash,
        expect: TopologicalPathHash,
    };

    const test_data = [_]TestData{
        .{ .source = 0b10, .dest = 0b101, .expect = 0b1 },
        .{ .source = 0b101, .dest = 0b10, .expect = 0b1 },
        .{ .source = 0b10, .dest = 0b10, .expect = 0b0 },
        .{ .source = 0b10, .dest = 0b1011, .expect = 0b11 },
        .{ .source = 0b1011, .dest = 0b10, .expect = 0b11 },
        .{ .source = 0b10, .dest = 0b10111010101110001111111, .expect = 0b111010101110001111111 },
    };

    for (test_data) |t, i| {
        errdefer std.log.err(
            "[{d}] source: {b} dest: {b} expected: {b}",
            .{ i, t.source, t.dest, t.expect }
        );

        try expectEqual(t.expect, try path_between_hash(t.source, t.dest));
    }
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

    try expectEqual(@as(usize, 5), map.map_hash_to_space.count());
    try expectEqual(@as(usize, 5), map.map_space_to_hash.count());

    try expectEqual(root, map.root().item);

    const root_hash = map.map_space_to_hash.get(try root.space(SpaceLabel.output)) orelse 0;

    try expectEqual(@as(TopologicalPathHash, 0b10), root_hash);

    const clip = tr.child_ptr_from_index(0);
    const clip_hash = map.map_space_to_hash.get(try clip.space(SpaceLabel.media)) orelse 0;

    try expectEqual(@as(TopologicalPathHash, 0b1000100), clip_hash);

    try expectEqual(true, path_exists_hash(clip_hash, root_hash));

    const root_output_to_clip_media = try map.build_projection_operator(
        .{
            .source = try root.space(SpaceLabel.output),
            .destination = try clip.space(SpaceLabel.media)
        }
    );

    try expectError(
        time_topology.TimeTopology.ProjectionError.OutOfBounds,
        root_output_to_clip_media.project_ordinate(3)
    );

    try expectApproxEqAbs(
        @as(f32, 1),
        try root_output_to_clip_media.project_ordinate(1),
        util.EPSILON,
    );
}

test "Projection: Track with clip with identity transform and bounds" {
    // not ready yet
    try util.skip_test();
    //
    // var tr = Track {};
    // var cl = Clip { .source_range = .{ .start_seconds = 0, .end_seconds = 2 } };
    // try tr.append(.{ .clip = cl });
    //
    // const map = try build_topological_map(root);
    //
    // const root_output_to_clip_media = try map.build_projection_operator(
    //     try root.space(SpaceLabel.output),
    //     try clip.space(SpaceLabel.media)
    // );
    //
    // const track_to_clip = try root_output_to_clip_media.build_projection_operator(
    //     .{
    //         .source = try tr.space(SpaceLabel.output),
    //         .destination =  try tr.children.items[0].clip.space(SpaceLabel.media)
    //     }
    // );
    //
    // // check the bounds
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

    const map = try build_topological_map(.{ .clip_ptr = &cl});

    // output->media
    {
        const clip_output_to_media = try map.build_projection_operator(
            .{
                .source =  try cl.space(SpaceLabel.output),
                .destination = try cl.space(SpaceLabel.media),
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
