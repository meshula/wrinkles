const std = @import("std");
const expectApproxEqAbs= std.testing.expectApproxEqAbs;
const expectEqual = std.testing.expectEqual;
const expectError= std.testing.expectError;

const opentime = @import("opentime/opentime.zig");
const Duration = f32;

const interval = @import("opentime/interval.zig");
const transform = @import("opentime/transform.zig");
const curve = @import("opentime/curve/curve.zig");
const time_topology = @import("opentime/time_topology.zig");
const string = opentime.string;

const util = @import("opentime/util.zig");

const allocator = @import("opentime/allocator.zig");
const ALLOCATOR = allocator.ALLOCATOR;

const GRAPH_CONSTRUCTION_TRACE_MESSAGES = false;

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

    pub fn topology(self: @This()) !time_topology.TimeTopology {
        if (self.source_range) |range| {
            return time_topology.TimeTopology.init_identity(.{.bounds=range});
        } else {
            return error.NotImplemented;
        }
    }

    pub const SPACES = enum(i8) {
        media = 0,
        output = 1,
    };
};

pub const Gap = struct {
    name: ?string.latin_s8 = null,
    duration: opentime.Ordinate,

    pub fn topology(self: @This()) !time_topology.TimeTopology {
        _ = self;
        return error.NotImplemented;
    }
};

pub const Item = union(enum) {
    clip: Clip,
    gap: Gap,
    track: Track,
    stack: Stack,

    pub fn topology(self: @This()) error{NotImplemented}!time_topology.TimeTopology {
        return switch (self) {
            inline else => |it| try it.topology(),
        };
    }

    pub fn duration(
        self: @This()
    ) error{NotImplemented,NoSourceRangeSet}!Duration 
    {
        return switch (self) {
            .gap => error.NotImplemented,
            .clip => |cl| (try cl.trimmed_range()).duration_seconds(),
            .track => |tr| try tr.duration(),
        };
    }
};

pub const ItemPtr = union(enum) {
    clip_ptr: *const Clip,
    gap_ptr: *const Gap,
    track_ptr: *const Track,
    timeline_ptr: *const Timeline,
    stack_ptr: *const Stack,

    pub fn init_Item(item: *Item) ItemPtr {
        return switch (item.*) {
            .clip  => |*cp| .{ .clip_ptr = cp  },
            .gap   => |*gp| .{ .gap_ptr= gp    },
            .track => |*tr| .{ .track_ptr = tr },
            .stack => |*st| .{ .stack_ptr = st },
        };
    }

    pub fn topology(self: @This()) !time_topology.TimeTopology {
        return switch (self) {
            inline else => |it_ptr| try it_ptr.toplogy(),
        };
    }

    /// == impl
    pub fn equivalent_to(self: @This(), other: ItemPtr) bool {
        return switch(self) {
            .clip_ptr => |cl| cl == other.clip_ptr,
            .gap_ptr => |gp| gp == other.gap_ptr,
            .track_ptr => |tr| tr == other.track_ptr,
            .stack_ptr => |st| st == other.stack_ptr,
            .timeline_ptr => |tl| tl == other.timeline_ptr,
        };
    }

    /// fetch the contained parent pointer
    pub fn parent(self: @This()) ?ItemPtr {
        return switch(self) {
            .clip_ptr => self.clip_ptr.parent,
            .gap_ptr => null,
            .track_ptr => null,
            .stack_ptr => null,
            .timeline_ptr => null,
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
            .clip_ptr, => {
                try result.append( .{ .item = self, .label = SpaceLabel.output});
                try result.append( .{ .item = self, .label = SpaceLabel.media});
            },
            .track_ptr, .timeline_ptr, .stack_ptr => {
                try result.append( .{ .item = self, .label = SpaceLabel.output});
                try result.append( .{ .item = self, .label = SpaceLabel.intrinsic});
            },
            .gap_ptr => {
                try result.append( .{ .item = self, .label = SpaceLabel.output});
            },
            // else => { return error.NotImplemented; }
        }

        return result.items;
    }

    pub fn space(self: @This(), label: SpaceLabel) !SpaceReference {
        return .{ .item = self, .label = label };
    }

    pub fn build_transform(
        self: @This(),
        from_space: SpaceLabel,
        to_space: SpaceReference,
        current_hash: TopologicalPathHash,
        step: u1
    ) !time_topology.TimeTopology 
    {
        // for now are implicit, will need them for the child scope traversal
        _ = to_space;

        if (GRAPH_CONSTRUCTION_TRACE_MESSAGES) {
            std.debug.print(
                "transform from space: {s}\n",
                .{ @tagName(from_space) }
            );
        }

        return switch (self) {
            .track_ptr => |*tr| {
                switch (from_space) {
                    SpaceLabel.output => (
                        return opentime.TimeTopology.init_identity_infinite()
                    ),
                    SpaceLabel.child => {
                        if (GRAPH_CONSTRUCTION_TRACE_MESSAGES) {
                            std.debug.print("CHILD {b}\n", .{ step});
                        }

                        if (step == 0) {
                            return (
                                opentime.TimeTopology.init_identity_infinite()
                            );
                        } 
                        else {
                            return try tr.*.transform_to_child(current_hash);
                        }

                    },
                    else => return opentime.TimeTopology.init_identity_infinite(),
                }
            },
            .clip_ptr => |*cl| {
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

                return switch (from_space) {
                    SpaceLabel.output => {
                        // goes to media
                        const output_to_post_transform = (
                            opentime.TimeTopology.init_identity_infinite()
                        );

                        const post_transform_to_intrinsic = (
                            cl.*.transform 
                            orelse opentime.TimeTopology.init_identity_infinite()
                        );

                        const output_to_intrinsic = (
                            post_transform_to_intrinsic.project_topology(
                                output_to_post_transform
                            )
                        );

                        const media_bounds = try cl.*.trimmed_range();
                        const intrinsic_to_media_xform = transform.AffineTransform1D{
                            .offset_seconds = media_bounds.start_seconds,
                            .scale = 1,
                        };
                        const intrinsic_bounds = .{
                            .start_seconds = 0,
                            .end_seconds = media_bounds.duration_seconds()
                        };
                        const intrinsic_to_media = (
                            opentime.TimeTopology.init_affine(
                                .{
                                    .transform = intrinsic_to_media_xform,
                                    .bounds = intrinsic_bounds,
                                }
                            )
                        );

                        const output_to_media = intrinsic_to_media.project_topology(
                            output_to_intrinsic
                        );

                        return output_to_media;
                    },
                    else => time_topology.TimeTopology.init_identity(
                        .{
                            .bounds = try cl.*.trimmed_range()
                        }
                    ),
                };
            },
            // wrapped as identity
            .gap_ptr, .timeline_ptr, .stack_ptr => opentime.TimeTopology.init_identity_infinite(),
            // else => |case| { 
            //     std.log.err("Not Implemented: {any}\n", .{ case });
            //
            //     // return error.NotImplemented;
            //     return opentime.TimeTopology.init_identity_infinite();
            // },
        };
    }
};

pub const Track = struct {
    name: ?string.latin_s8 = null,
    children: std.ArrayList(Item),

    pub fn init() Track { 
        return .{
            .children = std.ArrayList(Item).init(ALLOCATOR)
        };
    }

    pub fn duration(
        self: @This()
    ) !Duration  {
        var total_duration: Duration = 0;
        for (self.children.items) |c| {
            total_duration += try c.duration();
        }

        return total_duration;
    }

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

    pub fn topology(self: @This()) !time_topology.TimeTopology {
        // build the bounds
        var bounds: ?interval.ContinuousTimeInterval = null;
        for (self.children.items) |it| {
            const it_bound = (try it.topology()).bounds();
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

        return time_topology.TimeTopology.init_identity(.{.bounds=result_bound});
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

    pub fn transform_to_child(
        self: @This(),
        child_hash:TopologicalPathHash
    ) !time_topology.TimeTopology {
        // [child 1][child 2]
        const child_index = track_child_index_from_hash(child_hash);
        const child = self.child_ptr_from_index(child_index);
        const child_range = try child.clip_ptr.trimmed_range();
        const child_duration = child_range.duration_seconds();

        return opentime.TimeTopology.init_affine(
            .{
                .bounds = .{
                    .start_seconds = child_range.start_seconds + child_duration,
                    .end_seconds = util.inf
                },
                .transform = .{
                    .offset_seconds = -child_duration,
                    .scale = 1,
                }
            }
        );
    }
};

test "add clip to track and check parent pointer" {
    try util.skip_test();

    var tr = Track.init();
    const start_seconds:f32 = 1;
    const end_seconds:f32 = 10;
    var cl = Clip {
        .source_range = .{
            .start_seconds = start_seconds,
            .end_seconds = end_seconds 
        }
    };

    try tr.append(.{ .clip = cl });

    try expectEqual(ItemPtr.init_Item(&tr.children.items[0]), ItemPtr{ .track_ptr = &tr});
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
        return self.topology.project_ordinate(ord_to_project);
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
        var source_hash = (
            if (self.map_space_to_hash.get(args.source)) |hash| hash 
            else return error.SourceNotInMap
        );
        var destination_hash = (
            if (self.map_space_to_hash.get(args.destination)) |hash| hash 
            else return error.DestinationNotInMap
        );

        if (path_exists_hash(source_hash, destination_hash) == false) {
            return error.NoPathBetweenSpaces;
        }

        const needs_inversion = (source_hash > destination_hash);

        var current = args.source;

        // only supporting forward projection at the moment
        if (needs_inversion) {
            const tmp = source_hash;
            source_hash = destination_hash;
            destination_hash = tmp;

            current = args.destination;
        }

        var current_hash = source_hash;

        var proj = time_topology.TimeTopology.init_identity_infinite();

        if (GRAPH_CONSTRUCTION_TRACE_MESSAGES) {
            std.debug.print(
                "starting walk from: {b} to: {b}\n",
                .{ current_hash, destination_hash }
            );
        }
        while (current_hash != destination_hash) {
            const next_step = next_branch_along_path_hash(
                current_hash,
                destination_hash
            );
            const next_hash = (current_hash << 1) + next_step;

            // path has already been verified
            var next = self.map_hash_to_space.get(next_hash) orelse unreachable;
            if (GRAPH_CONSTRUCTION_TRACE_MESSAGES) { 
                std.debug.print(
                    "  step {b} to next hash: {b}\n",
                    .{ next_step, next_hash }
                );
            }

            var next_proj = try current.item.build_transform(
                current.label,
                next,
                // identifies the current child
                current_hash,
                next_step
            );


            // transformation spaces:
            // proj:         input   -> current
            // next_proj:    current -> next
            // current_proj: input   -> next
            const current_proj = next_proj.project_topology(proj);

            current_hash = next_hash;
            current = next;
            proj = current_proj;
        }

        if (needs_inversion) {
            proj = try proj.inverted();
        }

        return .{
            .args = args,
            .topology = proj,
        };
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
            .timeline_ptr => "timeline",
            .stack_ptr => "stack",
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

            {
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
            }

            {
                // @TODO: why does this need the extra 1?
                const right = ((current.hash << 1) + 1);
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
    const ind_offset = child_index;
    return std.math.shl(TopologicalPathHash, parent_hash, ind_offset);
}

test "depth_child_hash: math" {
    const start_hash:TopologicalPathHash = 0b10;

    const TPH = TopologicalPathHash;
    
    try expectEqual(@as(TPH, 0b10), depth_child_hash(start_hash, 0));
    try expectEqual(@as(TPH, 0b100), depth_child_hash(start_hash, 1));
    try expectEqual(@as(TPH, 0b1000), depth_child_hash(start_hash, 2));
    try expectEqual(@as(TPH, 0b10000), depth_child_hash(start_hash, 3));
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

    const start_hash = 0b10;

    // root node
    try stack.append(.{.object = root_item, .path_hash = start_hash});

    if (GRAPH_CONSTRUCTION_TRACE_MESSAGES) {
        std.debug.print("starting graph...\n", .{});
    }

    while (stack.items.len > 0) {
        const current = stack.pop();

        var current_hash = current.path_hash;

        // object intermediate spaces
        const spaces = try current.object.spaces();
        defer ALLOCATOR.free(spaces);

        for (spaces) |space_ref, index| {
            const child_hash = depth_child_hash(current_hash, index);
            if (GRAPH_CONSTRUCTION_TRACE_MESSAGES) {
                std.debug.print(
                    "[{d}] hash: {b} adding space: '{s}'\n",
                    .{index, child_hash, @tagName(space_ref.label)}
                );
            }
            try map_space_to_hash.put(space_ref, child_hash);
            try map_hash_to_space.put(child_hash, space_ref);

            if (index == (spaces.len - 1)) {
                current_hash = child_hash;
            }
        }

        // transforms to children
        const children = switch (current.object) {
            inline .track_ptr, .stack_ptr => |st_or_tr|  st_or_tr.children.items,
            .timeline_ptr => |tl|  &[_]Item{ .{ .stack = tl.tracks } },
            else => &[_]Item{},
        };

        for (children) 
            |*child, index| 
        {
            const item_ptr:ItemPtr = switch (child.*) {
                .clip => |*cl| .{ .clip_ptr = cl },
                .gap => |*gp| .{ .gap_ptr = gp },
                .track => |*tr_p| .{ .track_ptr = tr_p },
                .stack => |*st_p| .{ .stack_ptr = st_p },
            };


            const child_space_hash = sequential_child_hash(
                current_hash,
                index
            );

            // insert the child scope
            const space_ref = SpaceReference{
                .item = current.object,
                .label = SpaceLabel.child,
            };

            if (GRAPH_CONSTRUCTION_TRACE_MESSAGES) {
                std.debug.print(
                    "[{d}] hash: {b} adding child space: '{s}'\n",
                    .{
                        index,
                        child_space_hash,
                        @tagName(space_ref.label)
                    }
                );
            }
            try map_space_to_hash.put(space_ref, child_space_hash);
            try map_hash_to_space.put(child_space_hash, space_ref);

            const child_hash = depth_child_hash(child_space_hash, 1);

            try stack.insert(
                0,
                .{ .object= item_ptr, .path_hash = child_hash}
            );
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

    const topo = try cl.topology();

    try expectApproxEqAbs(
        start_seconds,
        topo.bounds().start_seconds,
        util.EPSILON,
    );

    try expectApproxEqAbs(
        end_seconds,
        topo.bounds().end_seconds,
        util.EPSILON,
    );
}

test "track topology construction" {
    var tr = Track.init();
    const start_seconds:f32 = 1;
    const end_seconds:f32 = 10;
    const cl = Clip {
        .source_range = .{
            .start_seconds = start_seconds,
            .end_seconds = end_seconds 
        }
    };
    try tr.append(.{ .clip = cl });

    const topo =  try tr.topology();

    try expectApproxEqAbs(
        start_seconds,
        topo.bounds().start_seconds,
        util.EPSILON,
    );

    try expectApproxEqAbs(
        end_seconds,
        topo.bounds().end_seconds,
        util.EPSILON,
    );
}

test "path_hash: graph test" {
    var tr = Track.init();
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

    const TestData = struct { ind: usize, expect: TopologicalPathHash };
    const test_data = [_]TestData{
        .{.ind = 0, .expect= 0b10010 },
        .{.ind = 1, .expect= 0b100110 },
    };
    for (test_data) 
        |t, t_i| 
    {
        const space = (
            try tr.child_ptr_from_index(t.ind).space(SpaceLabel.output)
        );
        const result = map.map_space_to_hash.get(space) orelse 0;

        const alternate = map.map_hash_to_space.get(0b10001);

        errdefer std.log.err(
            "[{d}] index: {d} expected: {b} result: {b} alternate: {any}",
            .{t_i, t.ind, t.expect, result, alternate}
        );
        try expectEqual(t.expect, result);
    }
}

test "Track with clip with identity transform projection" {

    var tr = Track.init();
    const start_seconds:f32 = 1;
    const end_seconds:f32 = 10;
    const range = interval.ContinuousTimeInterval{
        .start_seconds = start_seconds,
        .end_seconds = end_seconds,
    };

    var cl = Clip{.source_range = range};
    try tr.append(.{ .clip = cl });

    var i:i32 = 0;
    while (i < 10) {
        var cl2 = Clip {.source_range = range};
        try tr.append(.{ .clip = cl2 });
        i+=1;
    }

    const map = try build_topological_map(.{ .track_ptr = &tr });

    const clip = tr.child_ptr_from_index(0);
    const track_to_clip = try map.build_projection_operator(
        .{
            .source = try tr.space(SpaceLabel.output),
            .destination =  try clip.space(SpaceLabel.media)
        }
    );

    // check the bounds
    try expectApproxEqAbs(
        @as(f32, 0),
        track_to_clip.topology.bounds().start_seconds,
        util.EPSILON,
    );

    try expectApproxEqAbs(
        end_seconds - start_seconds,
        track_to_clip.topology.bounds().end_seconds,
        util.EPSILON,
    );

    // check the projection
    try expectApproxEqAbs(
        @as(f32, 4),
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
        .{ .source = 0b10, .dest = 0b100, .expect = 0b0 },
        .{ .source = 0b10, .dest = 0b1011, .expect = 0b11 },
        .{ .source = 0b1011, .dest = 0b10, .expect = 0b11 },
        .{ 
            .source = 0b10,
            .dest = 0b10111010101110001111111,
            .expect = 0b111010101110001111111 
        },
    };

    for (test_data) |t, i| {
        errdefer std.log.err(
            "[{d}] source: {b} dest: {b} expected: {b}",
            .{ i, t.source, t.dest, t.expect }
        );

        try expectEqual(t.expect, try path_between_hash(t.source, t.dest));
    }
}

pub fn track_child_index_from_hash(hash: TopologicalPathHash) usize {
    var index: usize = 0;
    var current_hash = hash;

    // count the trailing 1s
    while (current_hash > 0 and 0b1 & current_hash == 1) {
        index += 1;
        current_hash >>= 1;
    }

    return index;
}

test "track_child_index_from_hash: math" {
    const TestData = struct{source: TopologicalPathHash, expect: usize };

    const test_data = [_]TestData{
        .{ .source = 0b10, .expect = 0 },
        .{ .source = 0b101, .expect = 1 },
        .{ .source = 0b1011, .expect = 2 },
        .{ .source = 0b10111101111, .expect = 4 },
    };

    for (test_data) |t, i| {
        errdefer std.log.err(
            "[{d}] source: {b} expected: {b}",
            .{ i, t.source, t.expect }
        );

        try expectEqual(t.expect, track_child_index_from_hash(t.source));
    }
}

pub fn next_branch_along_path_hash(
    source: TopologicalPathHash,
    destination: TopologicalPathHash,
) u1 
{
    var start = source;
    var end = destination;

    if (start < end) {
        start = destination;
        end = source;
    }

    const r = @clz(end) - @clz(start);
    if (r == 0) {
        return 0;
    }

    // line b up with a
    // eg: b=101 and a1010, b -> 1010
    end <<= @intCast(u7,r);

    const path = start ^ end;

    return @truncate(u1, path >> @intCast(u7, (r - 1)) );
}

test "next_branch_along_path_hash: math" {
    const TestData = struct{
        source: TopologicalPathHash,
        dest: TopologicalPathHash,
        expect: u1,
    };

    const test_data = [_]TestData{
        .{ .source = 0b10, .dest = 0b101, .expect = 0b1 },
        .{ .source = 0b10, .dest = 0b100, .expect = 0b0 },
        .{ .source = 0b10, .dest = 0b10011101, .expect = 0b0 },
        .{ .source = 0b10, .dest = 0b10001101, .expect = 0b0 },
        .{ .source = 0b10, .dest = 0b10111101, .expect = 0b1 },
        .{ .source = 0b10, .dest = 0b10101101, .expect = 0b1 },
        .{ .source = 0b101, .dest = 0b10111101, .expect = 0b1 },
        .{ .source = 0b101, .dest = 0b10101101, .expect = 0b0 },
    };

    for (test_data) |t, i| {
        errdefer std.log.err(
            "[{d}] source: {b} dest: {b} expected: {b}",
            .{ i, t.source, t.dest, t.expect }
        );

        try expectEqual(
            t.expect,
            next_branch_along_path_hash(t.source, t.dest)
        );
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
    var tr = Track.init();
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

    try expectEqual(@as(TopologicalPathHash, 0b100100), clip_hash);

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

test "Projection: Track with single clip with identity transform and bounds" {
    var tr = Track.init();
    const root = ItemPtr{ .track_ptr = &tr };

    var cl = Clip { .source_range = .{ .start_seconds = 0, .end_seconds = 2 } };
    try tr.append(.{ .clip = cl });

    const clip = tr.child_ptr_from_index(0);

    const map = try build_topological_map(root);

    const root_output_to_clip_media = try map.build_projection_operator(
        .{ 
            .source = try root.space(SpaceLabel.output),
            .destination = try clip.space(SpaceLabel.media),
        }
    );

    // check the bounds
    try expectApproxEqAbs(
        (cl.source_range orelse interval.ContinuousTimeInterval{}).start_seconds,
        root_output_to_clip_media.topology.bounds().start_seconds,
        util.EPSILON,
    );

    try expectApproxEqAbs(
        (cl.source_range orelse interval.ContinuousTimeInterval{}).end_seconds,
        root_output_to_clip_media.topology.bounds().end_seconds,
        util.EPSILON,
    );

    try expectError(
        time_topology.TimeTopology.ProjectionError.OutOfBounds,
        root_output_to_clip_media.project_ordinate(3)
    );
}

test "Projection: Track with multiple clips with identity transform and bounds" {
    //
    //                          0               3             6
    // track.output space       [---------------*-------------)
    // track.intrinsic space    [---------------*-------------)
    // child.clip output space  [--------)[-----*---)[-*------)
    //                          0        2 0    1   2 0       2 
    //
    var tr = Track.init();
    const track_ptr = ItemPtr{ .track_ptr = &tr };

    var cl = Clip { .source_range = .{ .start_seconds = 0, .end_seconds = 2 } };

    // add three copies
    try tr.append(.{ .clip = cl });
    try tr.append(.{ .clip = cl });
    try tr.append(.{ .clip = cl });

    const TestData = struct {
        ind: usize,
        t_ord: f32,
        m_ord: f32,
        err: bool
    };

    const map = try build_topological_map(track_ptr);

    const tests = [_]TestData{
        .{ .ind = 1, .t_ord = 3, .m_ord = 1, .err = false},
        .{ .ind = 0, .t_ord = 1, .m_ord = 1, .err = false },
        .{ .ind = 2, .t_ord = 5, .m_ord = 1, .err = false },
        .{ .ind = 0, .t_ord = 7, .m_ord = 1, .err = true },
    };

    for (tests) |t, t_i| {
        const child = tr.child_ptr_from_index(t.ind);

        const tr_output_to_clip_media = try map.build_projection_operator(
            .{
                .source = try track_ptr.space(SpaceLabel.output),
                .destination = try child.space(SpaceLabel.media),
            }
        );

        errdefer std.log.err(
            "[{d}] index: {d} track ordinate: {d} expected: {d} error: {any}\n",
            .{t_i, t.ind, t.t_ord, t.m_ord, t.err}
        );
        if (t.err)
        {
            try expectError(
                time_topology.TimeTopology.ProjectionError.OutOfBounds,
                tr_output_to_clip_media.project_ordinate(t.t_ord)
            );
        }
        else{
            const result = try tr_output_to_clip_media.project_ordinate(t.t_ord);

            try expectApproxEqAbs(result, t.m_ord, util.EPSILON);
        }
    }

    const clip = tr.child_ptr_from_index(0);

    const root_output_to_clip_media = try map.build_projection_operator(
        .{ 
            .source = try track_ptr.space(SpaceLabel.output),
            .destination = try clip.space(SpaceLabel.media),
        }
    );

    // check the bounds
    try expectApproxEqAbs(
        (cl.source_range orelse interval.ContinuousTimeInterval{}).start_seconds,
        root_output_to_clip_media.topology.bounds().start_seconds,
        util.EPSILON,
    );

    try expectApproxEqAbs(
        (cl.source_range orelse interval.ContinuousTimeInterval{}).end_seconds,
        root_output_to_clip_media.topology.bounds().end_seconds,
        util.EPSILON,
    );

    try expectError(
        time_topology.TimeTopology.ProjectionError.OutOfBounds,
        root_output_to_clip_media.project_ordinate(3)
    );
}

test "Single Clip Media to Output Identity transform" {
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
    const cl_ptr : ItemPtr = .{ .clip_ptr = &cl};

    const map = try build_topological_map(cl_ptr);

    // output->media
    {
        const clip_output_to_media = try map.build_projection_operator(
            .{
                .source =  try cl_ptr.space(SpaceLabel.output),
                .destination = try cl_ptr.space(SpaceLabel.media),
            }
        );

        try expectApproxEqAbs(
            @as(f32, 103),
            try clip_output_to_media.project_ordinate(3),
            util.EPSILON,
        );

        try expectApproxEqAbs(
            @as(f32,0),
            clip_output_to_media.topology.bounds().start_seconds,
            util.EPSILON,
        );

        try expectApproxEqAbs(
            source_range.duration_seconds(),
            clip_output_to_media.topology.bounds().end_seconds,
            util.EPSILON,
        );
    }

    // media->output
    {
        const clip_output_to_media = try map.build_projection_operator(
            .{
                .source =  try cl_ptr.space(SpaceLabel.output),
                .destination = try cl_ptr.space(SpaceLabel.media),
            }
        );

        try expectApproxEqAbs(
            @as(f32, 103),
            try clip_output_to_media.project_ordinate(3),
            util.EPSILON,
        );
    }
}

test "Single Clip reverse transform" {
    //
    // xform: reverse (linear w/ -1 slope)
    //
    //              0                 7           10
    // output       [-----------------*-----------)
    // (transform)  10                3           0
    // media        [-----------------*-----------)
    //              110               103         100 (seconds)
    //

    const start = curve.ControlPoint{ .time = 0, .value = 10 };
    const end = curve.ControlPoint{ .time = 10, .value = 0 };
    const inv_tx = time_topology.TimeTopology.init_linear_start_end(start, end);

    const source_range:interval.ContinuousTimeInterval = .{
        .start_seconds = 100,
        .end_seconds = 110,
    };

    const cl = Clip { .source_range = source_range, .transform = inv_tx };
    const cl_ptr : ItemPtr = .{ .clip_ptr = &cl};

    const map = try build_topological_map(cl_ptr);

    // output->media (forward projection)
    {
        const clip_output_to_media_topo = try map.build_projection_operator(
            .{
                .source =  try cl_ptr.space(SpaceLabel.output),
                .destination = try cl_ptr.space(SpaceLabel.media),
            }
        );
        
        try expectApproxEqAbs(
            start.time,
            clip_output_to_media_topo.topology.bounds().start_seconds,
            util.EPSILON,
        );

        try expectApproxEqAbs(
            end.time,
            clip_output_to_media_topo.topology.bounds().end_seconds,
            util.EPSILON,
        );

        try expectApproxEqAbs(
            @as(f32, 107),
            try clip_output_to_media_topo.project_ordinate(3),
            util.EPSILON,
        );
    }

    // media->output (reverse projection)
    {
        const clip_media_to_output = try map.build_projection_operator(
            .{
                .source =  try cl_ptr.space(SpaceLabel.media),
                .destination = try cl_ptr.space(SpaceLabel.output),
            }
        );

        try expectApproxEqAbs(
            @as(f32, 3),
            try clip_media_to_output.project_ordinate(107),
            util.EPSILON,
        );
    }
}

test "Single Clip bezier transform" {
    try util.skip_test();

    //
    // xform: reverse (linear w/ -1 slope)
    //
    //              0                 7           10
    // output       [-----------------*-----------)
    // (transform)  10                3           0
    // media        [-----------------*-----------)
    //              110               103         100 (seconds)
    //

    const xform_curve = try curve.read_curve_json("curves/scurve.curve.json");

    const curve_topo = time_topology.TimeTopology.init_bezier_cubic(xform_curve);

    const source_range:interval.ContinuousTimeInterval = .{
        .start_seconds = 100,
        .end_seconds = 110,
    };

    const cl = Clip { .source_range = source_range, .transform = curve_topo };
    const cl_ptr : ItemPtr = .{ .clip_ptr = &cl};

    const map = try build_topological_map(cl_ptr);

    // output->media (forward projection)
    {
        const clip_output_to_media_topo = try map.build_projection_operator(
            .{
                .source =  try cl_ptr.space(SpaceLabel.output),
                .destination = try cl_ptr.space(SpaceLabel.media),
            }
        );

        // @TODO this should work
        var time = source_range.start_seconds;
        while (time < source_range.end_seconds) : (time += 0.01) {
            try expectApproxEqAbs(
                try curve_topo.bezier_curve.bezier_curve.evaluate(time),
                try clip_output_to_media_topo.project_ordinate(time),
                util.EPSILON
            );
        }
    }

    // media->output (reverse projection)
    {
        const clip_media_to_output = try map.build_projection_operator(
            .{
                .source =  try cl_ptr.space(SpaceLabel.media),
                .destination = try cl_ptr.space(SpaceLabel.output),
            }
        );

        try expectApproxEqAbs(
            @as(f32, 3),
            try clip_media_to_output.project_ordinate(107),
            util.EPSILON,
        );
    }
}

// top level object
pub const Timeline = struct {
    tracks:Stack = Stack.init(),
};

pub const Stack = struct {
    name: ?string.latin_s8 = null,
    children: std.ArrayList(Item),

    pub fn init() Stack { 
        return .{
            .children = std.ArrayList(Item).init(ALLOCATOR)
        };
    }

    pub fn topology(self: @This()) !time_topology.TimeTopology {
        // build the bounds
        var bounds: ?interval.ContinuousTimeInterval = null;
        for (self.children.items) |it| {
            const it_bound = (try it.topology()).bounds();
            if (bounds) |b| {
                bounds = interval.extend(b, it_bound);
            } else {
                bounds = it_bound;
            }
        }

        if (bounds) |b| {
            return time_topology.TimeTopology.init_affine(.{ .bounds = b });
        } else {
            return time_topology.TimeTopology.init_empty();
        }
    }
};

pub const SerializableObjectTypes = enum {
    Timeline,
    Stack,
    Track,
    Clip,
    Gap,
};

pub const SerializableObject = union(SerializableObjectTypes) {
    Timeline:Timeline,
    Stack:Stack,
    Track:Track,
    Clip:Clip,
    Gap:Gap,
};

pub const IntrinsicSchema = enum {
    TimeRange,
    RationalTime,
};

pub fn read_float(obj:std.json.Value) opentime.Ordinate {
    return switch (obj) {
        .Integer => |i| @intToFloat(opentime.Ordinate, i),
        .Float => |f| @floatCast(opentime.Ordinate, f),
        else => 0,
    };
}

pub fn read_ordinate_from_rt(obj:?std.json.ObjectMap) ?opentime.Ordinate {
    if (obj) |o| {
        const value = read_float(o.get("value").?);
        const rate = read_float(o.get("rate").?);

        return opentime.Ordinate{ .rational = .{ .numerator = value, .denominator = rate } };
    } else {
        return null;
    }
}

pub fn read_time_range(obj:?std.json.ObjectMap) ?interval.ContinuousTimeInterval {
    if (obj) |o| {
        const start_time = read_ordinate_from_rt(o.get("start_time").?.Object).?;
        const duration = read_ordinate_from_rt(o.get("duration").?.Object).?;
        return .{ .start_seconds = start_time, .end_seconds = start_time + duration };
    } else {
        return null;
    }
}

pub fn read_otio_object(
    obj:std.json.ObjectMap
) !SerializableObject 
{
    const maybe_schema_and_version_str = obj.get("OTIO_SCHEMA");

    if (maybe_schema_and_version_str == null) {
        return error.NotAnOtioSchemaObject;
    }

    const full_string = maybe_schema_and_version_str.?.String;

    var split_schema_string = std.mem.split(
        u8,
        full_string,
        "."
    );

    const maybe_schema_str = split_schema_string.next();
    if (maybe_schema_str == null) {
        return error.MalformedSchemaString;
    }
    const schema_str = maybe_schema_str.?;

    const maybe_schema_enum = std.meta.stringToEnum(
        SerializableObjectTypes,
        schema_str
    );
    if (maybe_schema_enum == null) {
        errdefer std.log.err("No schema: {s}\n", .{schema_str});
        return error.NoSuchSchema;
    }

    const schema_enum = maybe_schema_enum.?;

    const name = if (obj.get("name")) |n| switch (n) {
        .String => |s| s,
        else => null
    } else null;

    switch (schema_enum) {
        .Timeline => { 
            var st_json = try read_otio_object(obj.get("tracks").?.Object);
            const st = Stack{
                .name = st_json.Stack.name,
                .children = try st_json.Stack.children.clone(),
            };
            var tl = Timeline{ .tracks = st };
            return .{ .Timeline = tl };
        },
        .Stack => {

            var st = Stack.init();
            st.name = name;

            for (obj.get("children").?.Array.items) |track| {
                try st.children.append(
                    .{ .track = (try read_otio_object(track.Object)).Track }
                );
            }

            return .{ .Stack = st };
        },
        .Track => {
            var tr = Track.init();
            tr.name = name;

            for (obj.get("children").?.Array.items) |child| {
                switch (try read_otio_object(child.Object)) {
                    .Clip => |cl| { try tr.children.append( .{ .clip = cl }); },
                    .Gap => |gp| { try tr.children.append( .{ .gap = gp }); },
                    else => return error.NotImplemented,
                }
            }

            return .{ .Track = tr };
        },
        .Clip => {
            const source_range = (
                if (obj.get("source_range")) 
                |sr| switch (sr) {
                    .Object => |o| read_time_range(o),
                    else => null,
                }
                else null
            );

            var cl = Clip{
                .name=name,
                .source_range = source_range,
            };

            return .{ .Clip = cl };
        },
        .Gap => {
            const source_range = (
                if (obj.get("source_range")) 
                |sr| switch (sr) {
                    .Object => |o| read_time_range(o),
                    else => null,
                }
                else null
            );

            var gp = Gap{
                .name=name,
                .duration = source_range.?.duration_seconds(),
            };

            return .{ .Gap = gp };
        },
        // else => { 
        //     errdefer std.log.err("Not implemented yet: {s}\n", .{ schema_str });
        //     return error.NotImplemented; 
        // }
    }

    return error.NotImplemented;
}

pub fn read_from_file(file_path: string.latin_s8) !Timeline {
    var parser = std.json.Parser.init(allocator.ALLOCATOR, false);
    defer parser.deinit();

    const fi = try std.fs.cwd().openFile(file_path, .{});
    defer fi.close();

    const source = try fi.readToEndAlloc(ALLOCATOR, std.math.maxInt(u32));

    var tree = try parser.parse(source);
    defer tree.deinit();

    const tl_json = tree.root.Object;

    const hopefully_timeline = try read_otio_object(tl_json);

    if (hopefully_timeline == SerializableObject.Timeline) {
        return hopefully_timeline.Timeline;
    }

    // could be some other kind of top level object -- for now zig only reads
    // things that are topped with the timeline.

    return error.NotImplemented;
}

test "read_from_file test" {
    const root = "simple_cut";
    // const root = "multiple_track";
    const otio_fpath = root ++ ".otio";
    const dot_fpath = root ++ ".dot";

    const tl = try read_from_file("sample_otio_files/"++otio_fpath);

    const track0 = tl.tracks.children.items[0].track;

    if (std.mem.eql(u8, root, "simple_cut"))
    {
        try expectEqual(@as(usize, 1), tl.tracks.children.items.len);

        try expectEqual(@as(usize, 4), track0.children.items.len);
        try std.testing.expectEqualStrings(
            "Clip-001",
            track0.children.items[0].clip.name.?
        );
    }

    const tl_ptr = ItemPtr{ .timeline_ptr = &tl };
    const target_clip_ptr = (
        track0.child_ptr_from_index(0)
    );

    const map = try build_topological_map(tl_ptr);

    const tl_output_to_clip_media = try map.build_projection_operator(
        .{
            .source = try tl_ptr.space(SpaceLabel.output),
            .destination = try target_clip_ptr.space(SpaceLabel.media),
        }
    );
    
    try map.write_dot_graph("/var/tmp/" ++ dot_fpath);

    try expectApproxEqAbs(
        @as(std.meta.TagPayload(opentime.Ordinate, opentime.Ordinate.f32),  0.175),
        try tl_output_to_clip_media.project_ordinate(0.05),
        util.EPSILON
    );
}
