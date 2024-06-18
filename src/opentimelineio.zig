const std = @import("std");
const expectApproxEqAbs= std.testing.expectApproxEqAbs;
const expectEqual = std.testing.expectEqual;
const expectError= std.testing.expectError;

const opentime = @import("opentime");
const Duration = f32;

const interval = opentime.interval;
const transform = opentime.transform;
const curve = @import("curve");
const time_topology = @import("time_topology");
const string = @import("string_stuff");

const util = opentime.util;

const treecode = @import("treecode");

const otio_json = @import("opentimelineio_json.zig");

test {
    _ = otio_json;
}

// const GRAPH_CONSTRUCTION_TRACE_MESSAGES = true;
const GRAPH_CONSTRUCTION_TRACE_MESSAGES = false;

// for VERY LARGE files, turn this off so that dot can process the graphs
const LABEL_HAS_BINARY_TREECODE = true;


pub const Clip = struct {
    name: ?string.latin_s8 = null,

    /// a trim on the media space
    source_range: ?opentime.ContinuousTimeInterval = null,

    /// transformation of the media space to the output space
    transform: ?time_topology.TimeTopology = null,

    pub fn trimmed_range(
        self: @This()
    ) !opentime.ContinuousTimeInterval 
    {
        if (self.source_range) |rng| {
            return rng;
        }

        // normally the available range check would go here
        return error.NoSourceRangeSet;
    }

    pub fn space(
        self: @This(),
        label: SpaceLabel
    ) !SpaceReference 
    {
        return .{
            .item = ItemPtr{ .clip_ptr = &self },
            .label= label,
        };
    }

    pub fn topology(
        self: @This()
    ) !time_topology.TimeTopology 
    {
        if (self.source_range) |range| {
            return time_topology.TimeTopology.init_identity(
                .{.bounds=range}
            );
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
    duration: time_topology.Ordinate,

    pub fn topology(
        self: @This()
    ) !time_topology.TimeTopology 
    {
        _ = self;
        return error.NotImplemented;
    }
};

/// anything that can be composed in a track or stack
pub const Item = union(enum) {
    clip: Clip,
    gap: Gap,
    track: Track,
    stack: Stack,

    pub fn topology(
        self: @This()
    ) error{NotImplemented}!time_topology.TimeTopology 
    {
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

    pub fn recursively_deinit(
        self: @This(),
        allocator: std.mem.Allocator,
    ) void
    {
        switch (self) {
            .track => |tr| {
                tr.recursively_deinit();
            },
            .stack => |st| {
                st.recursively_deinit();
            },
            inline else => |o| {
                if (o.name)
                    |n|
                {
                    allocator.free(n);
                }
            },
        }
    }
};

pub const ItemPtr = union(enum) {
    clip_ptr: *const Clip,
    gap_ptr: *const Gap,
    track_ptr: *const Track,
    timeline_ptr: *const Timeline,
    stack_ptr: *const Stack,

    pub fn init_Item(
        item: *Item
    ) ItemPtr 
    {
        return switch (item.*) {
            .clip  => |*cp| .{ .clip_ptr = cp  },
            .gap   => |*gp| .{ .gap_ptr= gp    },
            .track => |*tr| .{ .track_ptr = tr },
            .stack => |*st| .{ .stack_ptr = st },
        };
    }

    pub fn topology(
        self: @This()
    ) !time_topology.TimeTopology 
    {
        return switch (self) {
            inline else => |it_ptr| try it_ptr.toplogy(),
        };
    }

    /// pointer equivalence
    pub fn equivalent_to(
        self: @This(),
        other: ItemPtr
    ) bool 
    {
        return switch(self) {
            .clip_ptr => |cl| cl == other.clip_ptr,
            .gap_ptr => |gp| gp == other.gap_ptr,
            .track_ptr => |tr| tr == other.track_ptr,
            .stack_ptr => |st| st == other.stack_ptr,
            .timeline_ptr => |tl| tl == other.timeline_ptr,
        };
    }

    /// fetch the contained parent pointer
    pub fn parent(
        self: @This()
    ) ?ItemPtr 
    {
        return switch(self) {
            .clip_ptr => self.clip_ptr.parent,
            .gap_ptr => null,
            .track_ptr => null,
            .stack_ptr => null,
            .timeline_ptr => null,
        };
    }

    pub fn child_index_of(
        self: @This(),
        child: ItemPtr
    ) !i32 
    {
        return switch(self) {
            .track_ptr => self.track_ptr.child_index_of(child),
            else => error.NotAContainer,
        };
    }

    /// return list of SpaceReference for this object
    pub fn spaces(
        self: @This(),
        allocator: std.mem.Allocator,
    ) ![]const SpaceReference 
    {
        var result = std.ArrayList(SpaceReference).init(allocator);

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

        return result.toOwnedSlice();

    }

    pub fn space(
        self: @This(),
        label: SpaceLabel
    ) !SpaceReference 
    {
        return .{ .item = self, .label = label };
    }

    pub fn build_transform(
        self: @This(),
        allocator: std.mem.Allocator,
        from_space: SpaceLabel,
        to_space: SpaceReference,
        step: u1
    ) !time_topology.TimeTopology 
    {
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
                        return time_topology.TimeTopology.init_identity_infinite()
                    ),
                    SpaceLabel.intrinsic => (
                        return time_topology.TimeTopology.init_identity_infinite()
                    ),
                    SpaceLabel.child => {
                        if (GRAPH_CONSTRUCTION_TRACE_MESSAGES) {
                            std.debug.print("CHILD {b}\n", .{ step});
                        }

                        if (step == 0) {
                            return (
                                time_topology.TimeTopology.init_identity_infinite()
                            );
                        } 
                        else {
                            return try tr.*.transform_to_child(to_space);
                        }

                    },
                    // track supports no other spaces
                    else => unreachable,
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
                            time_topology.TimeTopology.init_identity_infinite()
                        );

                        const post_transform_to_intrinsic = (
                            cl.*.transform 
                            orelse time_topology.TimeTopology.init_identity_infinite()
                        );

                        const output_to_intrinsic = (
                            try post_transform_to_intrinsic.project_topology(
                                allocator,
                                output_to_post_transform,
                            )
                        );
                        defer output_to_intrinsic.deinit(allocator);

                        const media_bounds = try cl.*.trimmed_range();
                        const intrinsic_to_media_xform = (
                            transform.AffineTransform1D{
                                .offset_seconds = media_bounds.start_seconds,
                                .scale = 1,
                            }
                        );
                        const intrinsic_bounds = .{
                            .start_seconds = 0,
                            .end_seconds = media_bounds.duration_seconds()
                        };
                        const intrinsic_to_media = (
                            time_topology.TimeTopology.init_affine(
                                .{
                                    .transform = intrinsic_to_media_xform,
                                    .bounds = intrinsic_bounds,
                                }
                            )
                        );

                        const output_to_media = try intrinsic_to_media.project_topology(
                            allocator,
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
            .gap_ptr, .timeline_ptr, .stack_ptr => (
                time_topology.TimeTopology.init_identity_infinite()
            ),
            // else => |case| { 
            //     std.log.err("Not Implemented: {any}\n", .{ case });
            //
            //     // return error.NotImplemented;
            //     return time_topology.TimeTopology.init_identity_infinite();
            // },
        };
    }
};

pub const Track = struct {
    name: ?string.latin_s8 = null,
    children: std.ArrayList(Item),

    pub fn init(
        allocator: std.mem.Allocator
    ) Track 
    {
        return .{
            .children = std.ArrayList(
                Item
            ).init(allocator),
        };
    }

    pub fn recursively_deinit(self: @This()) void {
        for (self.children.items)
            |c|
        {
            c.recursively_deinit(self.children.allocator);
        }

        self.deinit();
    }

    pub fn deinit(
        self: @This()
    ) void 
    {
        if (self.name)
            |n|
        {
            self.children.allocator.free(n);
        }
        self.children.deinit();
    }

    pub fn duration(
        self: @This()
    ) !Duration  
    {
        var total_duration: Duration = 0;
        for (self.children.items) 
            |c| 
        {
            total_duration += try c.duration();
        }

        return total_duration;
    }

    pub fn append(
        self: *Track,
        item: Item
    ) !void 
    {
        try self.children.append(item);
    }

    pub fn space(
        self: *Track,
        label: SpaceLabel
    ) !SpaceReference 
    {
        return .{
            .item = ItemPtr{ .track_ptr = self },
            .label= label,
        };
    }

    pub fn topology(
        self: @This()
    ) !time_topology.TimeTopology 
    {
        // build the maybe_bounds
        var maybe_bounds: ?interval.ContinuousTimeInterval = null;
        for (self.children.items) 
            |it| 
        {
            const it_bound = (try it.topology()).bounds();
            if (maybe_bounds) 
                |b| 
            {
                maybe_bounds = interval.extend(b, it_bound);
            } else {
                maybe_bounds = it_bound;
            }
        }

        // unpack the optional
        const result_bound:interval.ContinuousTimeInterval = maybe_bounds orelse .{
            .start_seconds = 0,
            .end_seconds = 0,
        };

        return time_topology.TimeTopology.init_identity(
            .{
                .bounds=result_bound
            }
        );
    }

    pub fn child_index_of(
        self: @This(),
        child_to_find: ItemPtr
    ) !i32 
    {
        return for (self.children.items, 0..) 
                   |current, index| 
        {
            if (std.meta.eql(current, child_to_find)) {
                break index;
            }
        } else null;
    }

    pub fn child_ptr_from_index(
        self: @This(),
        index: usize
    ) ItemPtr 
    {
        return ItemPtr.init_Item(&self.children.items[index]);
    }

    pub fn transform_to_child(
        self: @This(),
        child_space_reference: SpaceReference,
    ) !time_topology.TimeTopology 
    {
        // [child 1][child 2]
        const child_index = (
            child_space_reference.child_index 
            orelse return error.NoChildIndexOnChildSpaceReference
        );

        const child = self.child_ptr_from_index(child_index);
        const child_range = try child.clip_ptr.trimmed_range();
        const child_duration = child_range.duration_seconds();

        return time_topology.TimeTopology.init_affine(
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

pub const SpaceLabel = enum(i8) {
    output = 0,
    intrinsic,
    media,
    child,
};

pub const SpaceReference = struct {
    item: ItemPtr,
    label: SpaceLabel,
    child_index: ?usize = null,
};

const ProjectionOperatorArgs = struct {
    source: SpaceReference,
    destination: SpaceReference,
};

// @TODO: might boil out over time
const ProjectionOperator = struct {
    args: ProjectionOperatorArgs,
    topology: time_topology.TimeTopology,

    pub fn project_ordinate(
        self: @This(),
        ord_to_project: f32
    ) !f32 
    {
        return self.topology.project_ordinate(ord_to_project);
    }

    pub fn deinit(
        self: @This(),
        allocator: std.mem.Allocator,
    ) void
    {
        self.topology.deinit(allocator);
    }
};

/// Topological Map of a Timeline.  Can be used to build projection operators
/// to transform between various coordinate spaces within the map.
const TopologicalMap = struct {
    map_space_to_code:std.AutoHashMap(
          SpaceReference,
          treecode.Treecode,
    ),
    map_code_to_space:treecode.TreecodeHashMap(SpaceReference),

    pub fn init(
        allocator: std.mem.Allocator,
    ) !TopologicalMap 
    {
        return .{ 
            .map_space_to_code = std.AutoHashMap(
                SpaceReference,
                treecode.Treecode,
            ).init(allocator),
            .map_code_to_space = treecode.TreecodeHashMap(
                SpaceReference,
            ).init(allocator),
        };
    }

    pub fn deinit(
        self: @This()
    ) void 
    {
        // build a mutable alias of self
        var mutable_self = self;

        var keyIter = (
            mutable_self.map_code_to_space.keyIterator()
        );
        while (keyIter.next())
            |code|
        {
            code.deinit();
        }

        var valueIter = (
            mutable_self.map_space_to_code.valueIterator()
        );
        while (valueIter.next())
            |code|
        {
            code.deinit();
        }

        // free the guts
        mutable_self.map_space_to_code.deinit();
        mutable_self.map_code_to_space.deinit();
    }

    pub const ROOT_TREECODE:treecode.TreecodeWord = 0b1;

    /// return the root space of this topological map
    pub fn root(
        self: @This()
    ) SpaceReference 
    {
        const tree_word = treecode.Treecode{
            .sz = 1,
            .treecode_array = blk: {
                var output = [_]treecode.TreecodeWord{ ROOT_TREECODE };
                break :blk &output;
            },
            .allocator = undefined,
        };

        // should always have a root object
        return self.map_code_to_space.get(tree_word) orelse unreachable;
    }

    /// build a projection operator that projects from the args.source to
    /// args.destination spaces
    pub fn build_projection_operator(
        self: @This(),
        allocator: std.mem.Allocator,
        args: ProjectionOperatorArgs,
    ) !ProjectionOperator 
    {
        var source_code = (
            if (self.map_space_to_code.get(args.source)) 
            |code| 
            code
            else return error.SourceNotInMap
        );

        var destination_code = (
            if (self.map_space_to_code.get(args.destination)) 
            |code| 
            code
            else return error.DestinationNotInMap
        );

        if (path_exists(source_code, destination_code) == false) 
        {
            errdefer std.debug.print(
                "\nERROR\nsource: {b} dest: {b}\n",
                .{
                    source_code.treecode_array[0],
                    destination_code.treecode_array[0] 
                }
            );
            return error.NoPathBetweenSpaces;
        }

        const needs_inversion = (
            source_code.code_length() > destination_code.code_length()
        );

        var current = args.source;

        // path builder walks from the root towards the leaf nodes, and cannot
        // handle paths that go between siblings
        if (needs_inversion) {
            const tmp = source_code;
            source_code = destination_code;
            destination_code = tmp;

            current = args.destination;
        }

        var current_code = try source_code.clone();
        defer current_code.deinit();

        var proj = (
            time_topology.TimeTopology.init_identity_infinite()
        );

        if (GRAPH_CONSTRUCTION_TRACE_MESSAGES) {
            std.debug.print(
                "starting walk from: {b} to: {b}\n",
                .{
                    current_code.treecode_array[0],
                    destination_code.treecode_array[0] 
                }
            );
        }

        // walk from current_code towards destination_code
        while (current_code.eql(destination_code) == false) 
        {
            const next_step = try current_code.next_step_towards(
                destination_code
            );

            try current_code.append(next_step);

            // path has already been verified
            const next = self.map_code_to_space.get(
                current_code
            ) orelse return error.TreeCodeNotInMap;

            if (GRAPH_CONSTRUCTION_TRACE_MESSAGES) { 
                std.debug.print(
                    "  step {b} to next code: {d}\n",
                    .{ next_step, current_code.hash() }
                );
            }

            var next_proj = try current.item.build_transform(
                allocator,
                current.label,
                next,
                next_step
            );
            defer next_proj.deinit(allocator);

            // transformation spaces:
            // proj:         input   -> current
            // next_proj:    current -> next
            // current_proj: input   -> next
            const current_proj = try next_proj.project_topology(
                allocator,
                proj,
            );
            proj.deinit(allocator);

            current = next;
            proj = current_proj;
        }

        if (needs_inversion) {
            const old_proj = proj;
            proj = try proj.inverted(allocator);
            old_proj.deinit(allocator);
        }

        return .{
            .args = args,
            .topology = proj,
        };
    }

    // @TODO: add a print for the enum of the transform on the node
    //        that at least lets you spot empty/bezier/affine etc
    //        transforms
    //
    fn label_for_node_leaky(
        allocator: std.mem.Allocator,
        ref: SpaceReference,
        code: treecode.Treecode,
    ) !string.latin_s8 
    {
        const item_kind = switch(ref.item) {
            .track_ptr => "track",
            .clip_ptr => "clip",
            .gap_ptr => "gap",
            .timeline_ptr => "timeline",
            .stack_ptr => "stack",
        };


        if (LABEL_HAS_BINARY_TREECODE) {
            var buf = std.ArrayList(u8).init(allocator);
            defer buf.deinit();

            try code.to_str(&buf);

            const args = .{
                item_kind,
                @tagName(ref.label),
                buf.items,
            };
            return std.fmt.allocPrint(allocator, "{s}_{s}_{s}", args);
        } 
        else {
            const args = .{ item_kind, @tagName(ref.label), code.hash(), };

            return std.fmt.allocPrint(allocator, "{s}_{s}_{any}", args);
        }

    }

    // @TODO: doesn't need an allocator
    pub fn write_dot_graph(
        self:@This(),
        allocator_: std.mem.Allocator,
        filepath: string.latin_s8
    ) !void 
    {
        const root_space = self.root(); 
        _ = allocator_;
        
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const allocator = arena.allocator();

        var buf = std.ArrayList(u8).init(allocator);

        // open the file
        const file = try std.fs.createFileAbsolute(filepath,.{});
        defer file.close();
        errdefer file.close();

        try file.writeAll("digraph OTIO_TopologicalMap {\n");


        const Node = struct {
            space: SpaceReference,
            code: treecode.Treecode 
        };

        var stack = std.ArrayList(Node).init(allocator);

        try stack.append(
            .{
                .space = root_space,
                .code = try treecode.Treecode.init_word(
                    allocator,
                    0b1
                )
            }
        );

        while (stack.items.len > 0) 
        {
            const current = stack.pop();
            const current_label = try label_for_node_leaky(
                allocator,
                current.space,
                current.code
            );

            // left
            {
                var left = try current.code.clone();
                try left.append(0);

                if (self.map_code_to_space.get(left)) 
                    |next| 
                {
                    const next_label = try label_for_node_leaky(
                        allocator,
                        next,
                        left
                    );
                    try file.writeAll(
                        try std.fmt.allocPrint(
                            allocator,
                            "  {s} -> {s}\n",
                            .{current_label, next_label}
                        )
                    );
                    try stack.append(
                        .{
                            .space = next,
                            .code = left
                        }
                    );
                } else {
                    buf.clearAndFree();
                    try left.to_str(&buf);

                    try file.writeAll(
                        try std.fmt.allocPrint(
                            allocator,
                            "  {s} \n  [shape=point]{s} -> {s}\n",
                            .{buf.items, current_label, buf.items }
                        )
                    );
                }
            }

            // right
            {
                var right = try current.code.clone();
                try right.append(1);

                if (self.map_code_to_space.get(right)) 
                    |next| 
                {
                    const next_label = try label_for_node_leaky(
                        allocator,
                        next,
                        right
                    );
                    try file.writeAll(
                        try std.fmt.allocPrint(
                            allocator,
                            "  {s} -> {s}\n",
                            .{current_label, next_label}
                        )
                    );
                } else 
                {
                    buf.clearAndFree();
                    try right.to_str(&buf);
                    try file.writeAll(
                        try std.fmt.allocPrint(
                            allocator,
                            "  {s} [shape=point]\n  {s} -> {s}\n",
                            .{buf.items, current_label, buf.items}
                        )
                    );
                }
            }
        }

        try file.writeAll("}\n");
    }
};

pub fn path_exists(
    fst: treecode.Treecode,
    snd: treecode.Treecode
) bool 
{
    return (
        fst.eql(snd) 
        or (
            fst.is_superset_of(snd) 
            or snd.is_superset_of(fst)
        )
    );
}

pub fn depth_child_code_leaky(
    parent_code:treecode.Treecode,
    index: usize
) !treecode.Treecode 
{
    var result = try parent_code.clone();
    var i:usize = 0;
    while (i < index):(i+=1) {
        try result.append(0);
    }
    return result;
}

test "depth_child_hash: math" 
{
    var root = try treecode.Treecode.init_word(
        std.testing.allocator,
        0b1000
    );
    defer root.deinit();

    var i:usize = 0;

    const expected_root:treecode.TreecodeWord = 0b1000;

    while (i<4) 
        : (i+=1) 
    {
        var result = try depth_child_code_leaky(root, i);
        defer result.deinit();

        const expected = std.math.shl(treecode.TreecodeWord, expected_root, i); 

        errdefer std.debug.print(
            "iteration: {d}, expected: {b} got: {b}\n",
            .{ i, expected, result.treecode_array[0] }
        );

        try expectEqual(expected, result.treecode_array[0]);
    }
}

pub fn build_topological_map(
    allocator: std.mem.Allocator,
    root_item: ItemPtr
) !TopologicalMap 
{
    var tmp_topo_map = try TopologicalMap.init(allocator);

    const Node = struct {
        path_code: treecode.Treecode,
        object: ItemPtr,
    };

    var stack = std.ArrayList(Node).init(allocator);
    defer {
        for (stack.items)
            |n|
        {
            n.path_code.deinit();
        }
        stack.deinit();
    }

    // 1a
    const start_code = try treecode.Treecode.init_word(
        allocator,
        TopologicalMap.ROOT_TREECODE,
    );

    // root node
    try stack.append(
        .{
            .object = root_item,
            .path_code = start_code
        }
    );

    if (GRAPH_CONSTRUCTION_TRACE_MESSAGES) {
        std.debug.print("\nstarting graph...\n", .{});
    }

    while (stack.items.len > 0) 
    {
        const current = stack.pop();

        const code_from_stack = current.path_code;
        defer code_from_stack.deinit();

        var current_code = try current.path_code.clone();

        // push the spaces for the current object into the map/stack
        {
            const spaces = try current.object.spaces(
                allocator
            );
            defer allocator.free(spaces);

            for (0.., spaces) 
                |index, space_ref| 
            {
                const child_code = try depth_child_code_leaky(
                    current_code,
                    index
                );
                defer child_code.deinit();

                if (GRAPH_CONSTRUCTION_TRACE_MESSAGES) {
                    std.debug.assert(
                        tmp_topo_map.map_code_to_space.get(child_code) == null
                    );
                    std.debug.assert(
                        tmp_topo_map.map_space_to_code.get(space_ref) == null
                    );
                    std.debug.print(
                        (
                         "[{d}] code: {b} hash: {d} adding local space: "
                         ++ "'{s}.{s}'\n"
                        ),
                        .{
                            index,
                            child_code.treecode_array[0],
                            child_code.hash(), 
                            @tagName(space_ref.item),
                            @tagName(space_ref.label)
                        }
                    );
                }
                try tmp_topo_map.map_space_to_code.put(
                    space_ref,
                    try child_code.clone(),
                );
                try tmp_topo_map.map_code_to_space.put(
                    try child_code.clone(),
                    space_ref
                );

                if (index == (spaces.len - 1)) {
                    current_code.deinit();
                    current_code = try child_code.clone();
                }
            }
        }

        // transforms to children
        const children = switch (current.object) 
        {
            inline .track_ptr, .stack_ptr => |st_or_tr| (
                st_or_tr.children.items
            ),
            .timeline_ptr => |tl|  &[_]Item{
                .{ 
                    .stack = tl.tracks 
                } 
            },
            else => &[_]Item{},
        };

        for (children, 0..) 
            |*child, index| 
        {
            const item_ptr:ItemPtr = switch (child.*) {
                .clip => |*cl| .{ .clip_ptr = cl },
                .gap => |*gp| .{ .gap_ptr = gp },
                .track => |*tr_p| .{ .track_ptr = tr_p },
                .stack => |*st_p| .{ .stack_ptr = st_p },
            };

            const child_space_code = try sequential_child_code_leaky(
                current_code,
                index
            );
            defer child_space_code.deinit();

            // insert the child scope
            const space_ref = SpaceReference{
                .item = current.object,
                .label = SpaceLabel.child,
                .child_index = index,
            };

            if (GRAPH_CONSTRUCTION_TRACE_MESSAGES) 
            {
                std.debug.assert(tmp_topo_map.map_code_to_space.get(child_space_code) == null);

                if (tmp_topo_map.map_space_to_code.get(space_ref)) 
                    |other_code| 
                {
                    std.debug.print(
                        "\n ERROR SPACE ALREADY PRESENT[{d}] code: {b} other_code: {b} adding child space: '{s}.{s}.{d}'\n",
                        .{
                            index,
                            child_space_code.treecode_array[0],
                            other_code.treecode_array[0],
                            @tagName(space_ref.item),
                            @tagName(space_ref.label),
                            space_ref.child_index.?,
                        }
                    );

                    std.debug.assert(false);
                }
                std.debug.print(
                    "[{d}] code: {b} hash: {d} adding child space: '{s}.{s}.{d}'\n",
                    .{
                        index,
                        child_space_code.treecode_array[0],
                        child_space_code.hash(),
                        @tagName(space_ref.item),
                        @tagName(space_ref.label),
                        space_ref.child_index.?,
                    }
                );
            }
            try tmp_topo_map.map_space_to_code.put(
                space_ref,
                try child_space_code.clone()
            );
            try tmp_topo_map.map_code_to_space.put(
                try child_space_code.clone(),
                space_ref
            );

            // creates a cone of the child_space_code
            const child_code = try depth_child_code_leaky(
                child_space_code,
                1
            );
            defer child_code.deinit();

            try stack.insert(
                0,
                .{ 
                    .object= item_ptr,
                    .path_code = try child_code.clone()
                }
            );
        }

        current_code.deinit();
    }

    // return result;
    return tmp_topo_map;
}

test "clip topology construction" 
{
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

test "track topology construction" 
{
    var tr = Track.init(std.testing.allocator);
    defer tr.deinit();

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

test "build_topological_map: leak sentinel test - single clip"
{
    const start_seconds:f32 = 1;
    const end_seconds:f32 = 10;

    const cl = Clip {
        .source_range = .{
            .start_seconds = start_seconds,
            .end_seconds = end_seconds 
        }
    };

    const map = try build_topological_map(
        std.testing.allocator,
        .{ 
            .clip_ptr =  &cl 
        },
    );
    defer map.deinit();
}

test "build_topological_map: leak sentinel test track w/ clip"
{
    var tr = Track.init(std.testing.allocator);
    defer tr.deinit();

    const start_seconds:f32 = 1;
    const end_seconds:f32 = 10;

    const cl = Clip {
        .source_range = .{
            .start_seconds = start_seconds,
            .end_seconds = end_seconds 
        }
    };
    try tr.append(.{ .clip = cl });

    const map = try build_topological_map(
        std.testing.allocator,
        .{ 
            .track_ptr = &tr 
        },
    );
    defer map.deinit();
}

test "build_topological_map check root node" 
{
    var tr = Track.init(std.testing.allocator);
    defer tr.deinit();

    const start_seconds:f32 = 1;
    const end_seconds:f32 = 10;

    const cl = Clip {
        .source_range = .{
            .start_seconds = start_seconds,
            .end_seconds = end_seconds 
        }
    };
    try tr.append(.{ .clip = cl });

    var i:i32 = 0;
    while (i < 10) 
        : (i += 1)
    {
        const cl2 = Clip {
            .source_range = .{
                .start_seconds = start_seconds,
                .end_seconds = end_seconds 
            }
        };
        try tr.append(.{ .clip = cl2 });
    }

    try std.testing.expectEqual(
        @as(usize, 11),
        tr.children.items.len
    );

    const map = try build_topological_map(
        std.testing.allocator,
        .{ 
            .track_ptr = &tr 
        },
    );
    defer map.deinit();

    try expectEqual(
        tr.space(.output),
        map.root(),
    );

}

test "path_code: graph test" 
{
    var tr = Track.init(std.testing.allocator);
    defer tr.deinit();

    const start_seconds:f32 = 1;
    const end_seconds:f32 = 10;

    const cl = Clip {
        .source_range = .{
            .start_seconds = start_seconds,
            .end_seconds = end_seconds 
        }
    };
    try tr.append(.{ .clip = cl });

    var i:i32 = 0;
    while (i < 10) 
        : (i+=1)
    {
        const cl2 = Clip {
            .source_range = .{
                .start_seconds = start_seconds,
                .end_seconds = end_seconds 
            }
        };
        try tr.append(.{ .clip = cl2 });
    }

    try std.testing.expectEqual(11, tr.children.items.len);

    const map = try build_topological_map(
        std.testing.allocator,
        .{ .track_ptr = &tr },
    );
    defer map.deinit();

    try expectEqual(
        tr.space(.output),
        map.root(),
    );

    try map.write_dot_graph(
        std.testing.allocator,
        "/var/tmp/graph_test_output.dot"
    );

    // should be the same length
    try std.testing.expectEqual(
        map.map_space_to_code.count(),
        map.map_code_to_space.count(),
    );
    try std.testing.expectEqual(
        @as(usize, 35),
        map.map_space_to_code.count()
    );

    try map.write_dot_graph(
        std.testing.allocator,
        "/var/tmp/current.dot",
    );

    const TestData = struct {
        ind: usize,
        expect: treecode.TreecodeWord, 
    };

    const test_data = [_]TestData{
        .{.ind = 0, .expect= 0b1010 },
        .{.ind = 1, .expect= 0b10110 },
        .{.ind = 2, .expect= 0b101110 },
    };
    for (0.., test_data)
        |t_i, t| 
    {
        const space = (
            try tr.child_ptr_from_index(t.ind).space(SpaceLabel.output)
        );
        const result = (
            map.map_space_to_code.get(space) 
            orelse return error.NoSpaceForCode
        );

        errdefer std.log.err(
            "\n[iteration: {d}] index: {d} expected: {b} result: {b} \n",
            .{t_i, t.ind, t.expect, result.treecode_array[0]}
        );

        const expect = try treecode.Treecode.init_word(
            std.testing.allocator,
            t.expect
        );
        defer expect.deinit();

        try std.testing.expect(expect.eql(result));
    }
}

test "Track with clip with identity transform projection" 
{
    var tr = Track.init(std.testing.allocator);
    defer tr.deinit();

    const start_seconds:f32 = 1;
    const end_seconds:f32 = 10;
    const range = interval.ContinuousTimeInterval{
        .start_seconds = start_seconds,
        .end_seconds = end_seconds,
    };

    const cl = Clip{.source_range = range};
    try tr.append(.{ .clip = cl });

    var i:i32 = 0;
    while (i < 10) 
        : (i+=1)
    {
        const cl2 = Clip {.source_range = range};
        try tr.append(.{ .clip = cl2 });
    }

    const map = try build_topological_map(
        std.testing.allocator,
        .{ .track_ptr = &tr },
    );
    defer map.deinit();

    const clip = tr.child_ptr_from_index(0);
    const track_to_clip = try map.build_projection_operator(
        std.testing.allocator,
        .{
            .source = try tr.space(SpaceLabel.output),
            .destination =  try clip.space(SpaceLabel.media)
        }
    );
    defer track_to_clip.deinit(std.testing.allocator);

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


test "TopologicalMap: Track with clip with identity transform topological" 
{
    var tr = Track.init(std.testing.allocator);
    defer tr.deinit();

    const cl = Clip {
        .source_range = .{
            .start_seconds = 0,
            .end_seconds = 2 
        } 
    };

    // a copy -- which is why we can't use `cl` in our searches.
    try tr.append(.{ .clip = cl });

    const root = ItemPtr{ .track_ptr = &tr };

    const map = try build_topological_map(
        std.testing.allocator,
        root,
    );
    defer map.deinit();

    try expectEqual(5, map.map_code_to_space.count());
    try expectEqual(5, map.map_space_to_code.count());

    try expectEqual(root, map.root().item);

    const maybe_root_code = map.map_space_to_code.get(map.root());
    try std.testing.expect(maybe_root_code != null);
    const root_code = maybe_root_code.?;

    // root object code
    {
        var tc = try treecode.Treecode.init_word(
            std.testing.allocator,
            0b1
        );
        defer tc.deinit();
        try std.testing.expect(tc.eql(root_code));
        try expectEqual(0, tc.code_length());
    }

    const clip = tr.child_ptr_from_index(0);
    const maybe_clip_code = map.map_space_to_code.get(
        try clip.space(SpaceLabel.media)
    );
    try std.testing.expect(maybe_clip_code != null);
    const clip_code = maybe_clip_code.?;

    // clip object code
    {
        var tc = try treecode.Treecode.init_word(
            std.testing.allocator,
            0b10010
        );
        defer tc.deinit();
        errdefer std.debug.print(
            "\ntc: {b}, clip_code: {b}\n",
            .{
                tc.treecode_array[0],
                clip_code.treecode_array[0] 
            },
        );
        try expectEqual(4, tc.code_length());
        try std.testing.expect(tc.eql(clip_code));
    }

    try std.testing.expect(path_exists(clip_code, root_code));

    const root_output_to_clip_media = (
        try map.build_projection_operator(
            std.testing.allocator,
            .{
                .source = try root.space(SpaceLabel.output),
                .destination = try clip.space(SpaceLabel.media)
            }
        )
    );

    try expectError(
        time_topology.TimeTopology.ProjectionError.OutOfBounds,
        root_output_to_clip_media.project_ordinate(3)
    );

    try expectApproxEqAbs(
        1,
        try root_output_to_clip_media.project_ordinate(1),
        util.EPSILON,
    );
}

test "Projection: Track with single clip with identity transform and bounds" 
{
    var tr = Track.init(std.testing.allocator);
    defer tr.deinit();

    const root = ItemPtr{ .track_ptr = &tr };

    const cl = Clip { .source_range = .{ .start_seconds = 0, .end_seconds = 2 } };
    try tr.append(.{ .clip = cl });

    const clip = tr.child_ptr_from_index(0);

    const map = try build_topological_map(
        std.testing.allocator,
        root,
    );
    defer map.deinit();

    try expectEqual(
        @as(usize, 5),
        map.map_code_to_space.count()
    );
    try expectEqual(
        @as(usize, 5),
        map.map_space_to_code.count()
    );

    const root_output_to_clip_media = try map.build_projection_operator(
        std.testing.allocator,
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

test "Projection: Track with multiple clips with identity transform and bounds" 
{
    //
    //                          0               3             6
    // track.output space       [---------------*-------------)
    // track.intrinsic space    [---------------*-------------)
    // child.clip output space  [--------)[-----*---)[-*------)
    //                          0        2 0    1   2 0       2 
    //
    var tr = Track.init(std.testing.allocator);
    defer tr.deinit();
    const track_ptr = ItemPtr{ .track_ptr = &tr };

    const cl = Clip { .source_range = .{ .start_seconds = 0, .end_seconds = 2 } };

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

    const map = try build_topological_map(
        std.testing.allocator,
        track_ptr,
    );
    defer map.deinit();

    const tests = [_]TestData{
        .{ .ind = 1, .t_ord = 3, .m_ord = 1, .err = false},
        .{ .ind = 0, .t_ord = 1, .m_ord = 1, .err = false },
        .{ .ind = 2, .t_ord = 5, .m_ord = 1, .err = false },
        .{ .ind = 0, .t_ord = 7, .m_ord = 1, .err = true },
    };

    for (tests, 0..) 
        |t, t_i| 
    {
        const child = tr.child_ptr_from_index(t.ind);

        const tr_output_to_clip_media = try map.build_projection_operator(
        std.testing.allocator,
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
        std.testing.allocator,
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

test "Single Clip Media to Output Identity transform" 
{
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

    const map = try build_topological_map(
        std.testing.allocator,
        cl_ptr,
    );
    defer map.deinit();

    try expectEqual(
        @as(usize, 2),
        map.map_code_to_space.count()
    );
    try expectEqual(
        @as(usize, 2),
        map.map_space_to_code.count()
    );

    // output->media
    {
        const clip_output_to_media = try map.build_projection_operator(
            std.testing.allocator,
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
            std.testing.allocator,
            .{
                .source =  try cl_ptr.space(SpaceLabel.media),
                .destination = try cl_ptr.space(SpaceLabel.output),
            }
        );

        try expectApproxEqAbs(
            @as(f32, 3),
            try clip_output_to_media.project_ordinate(103),
            util.EPSILON,
        );
    }
}

test "Single Clip reverse transform" {
    //
    // xform: reverse (linear w/ -1 slope)
    // note: transforms map from the _output_ space to the _media_ space
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

    const map = try build_topological_map(
        std.testing.allocator,
        cl_ptr,
    );
    defer map.deinit();

    // output->media (forward projection)
    {
        const clip_output_to_media_topo = try map.build_projection_operator(
            std.testing.allocator,
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
            std.testing.allocator,
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
    //
    // xform: s-curve read from sample curve file
    //        curves map from the output space to the intrinsic space for clips
    //
    //              0                             10
    // output       [-----------------------------)
    //                               _,-----------x
    // transform                   _/
    // (curve)                   ,/
    //              x-----------'
    // intrinsic    [-----------------------------)
    //              0                             10 (seconds)
    // media        100                          110 (seconds)
    //
    // the media space is defined by the source range
    //

    const base_curve = try curve.read_curve_json(
        "curves/scurve.curve.json",
        std.testing.allocator,
    );
    defer base_curve.deinit(std.testing.allocator);

    // this curve is [-0.5, 0.5), rescale it into test range
    const xform_curve = try curve.rescaled_curve(
        std.testing.allocator,
        base_curve,
        //  the range of the clip for testing - rescale factors
        .{
            .{ .time = 0, .value = 0, },
            .{ .time = 10, .value = 10, },
        }
    );
    defer xform_curve.deinit(std.testing.allocator);
    const curve_topo = time_topology.TimeTopology.init_bezier_cubic(
        xform_curve
    );

    // test the input space range
    const curve_bounds_input = curve_topo.bounds();
    try expectApproxEqAbs(
        @as(f32, 0),
        curve_bounds_input.start_seconds, util.EPSILON
    );
    try expectApproxEqAbs(
        @as(f32, 10),
        curve_bounds_input.end_seconds, util.EPSILON
    );

    // test the output space range (the media space of the clip)
    const curve_bounds_output = xform_curve.extents_value();
    try expectApproxEqAbs(
        @as(f32, 0),
        curve_bounds_output.start_seconds, util.EPSILON
    );
    try expectApproxEqAbs(
        @as(f32, 10),
        curve_bounds_output.end_seconds, util.EPSILON
    );

    try std.testing.expect(
        std.meta.activeTag(curve_topo) != time_topology.TimeTopology.empty
    );

    const source_range:interval.ContinuousTimeInterval = .{
        .start_seconds = 100,
        .end_seconds = 110,
    };
    const cl = Clip {
        .source_range = source_range,
        .transform = curve_topo 
    };
    const cl_ptr : ItemPtr = .{ .clip_ptr = &cl };

    const map = try build_topological_map(
        std.testing.allocator,
        cl_ptr
    );
    defer map.deinit();

    // output->media (forward projection)
    {
        const clip_output_to_media_proj = (
            try map.build_projection_operator(
                std.testing.allocator,
                .{
                    .source =  try cl_ptr.space(SpaceLabel.output),
                    .destination = try cl_ptr.space(SpaceLabel.media),
                }
            )
        );
        defer clip_output_to_media_proj.deinit(std.testing.allocator);

        // note that the clips output space is the curve's input space
        const output_bounds = (
            clip_output_to_media_proj.topology.bounds()
        );
        try expectApproxEqAbs(
            curve_bounds_output.start_seconds, 
            output_bounds.start_seconds,
            util.EPSILON
        );
        try expectApproxEqAbs(
            curve_bounds_output.end_seconds, 
            output_bounds.end_seconds,
            util.EPSILON
        );

        // invert it back and check it against the inpout curve bounds
        const clip_media_to_output = (
            try clip_output_to_media_proj.topology.inverted(
                std.testing.allocator
            )
        );
        defer clip_media_to_output.deinit(std.testing.allocator);
        const clip_media_to_output_bounds = (
            clip_media_to_output.bounds()
        );
        try expectApproxEqAbs(
            @as(f32, 100),
            clip_media_to_output_bounds.start_seconds, util.EPSILON
        );
        try expectApproxEqAbs(
            @as(f32, 110),
            clip_media_to_output_bounds.end_seconds, util.EPSILON
        );

        try std.testing.expect(
            std.meta.activeTag(clip_output_to_media_proj.topology) 
            != time_topology.TimeTopology.empty
        );

        // walk over the output space of the curve
        const o_s_time = output_bounds.start_seconds;
        const o_e_time = output_bounds.end_seconds;
        var output_time = o_s_time;
        while (output_time < o_e_time) 
            : (output_time += 0.01) 
        {
            // output time -> media time
            const media_time = (
                try clip_output_to_media_proj.project_ordinate(output_time)
            );
            
            errdefer std.log.err(
        "\nERR1\n  output_time: {d} \n"
                ++ "  topology output_bounds: {any} \n"
                ++ "  topology curve bounds: {any} \n ",
                .{
                    output_time,
                    clip_output_to_media_proj.topology.bounds(),
                    clip_output_to_media_proj.topology.bezier_curve.compute_bounds(),
                }
            );

            // media time -> output time
            const computed_output_time = (
                try clip_media_to_output.project_ordinate(media_time)
            ); 

            errdefer std.log.err(
                "\nERR\n  output_time: {d} \n"
                ++ "  computed_output_time: {d} \n"
                ++ " source_range: {any}\n"
                ++ "  output_bounds: {any} \n",
                .{
                    output_time,
                    computed_output_time,
                    source_range,
                    output_bounds,
                }
            );

            try expectApproxEqAbs(
                computed_output_time,
                output_time,
                util.EPSILON
            );
        }
    }

    // media->output (reverse projection)
    {
        const clip_media_to_output = (
            try map.build_projection_operator(
                std.testing.allocator,
                .{
                    .source =  try cl_ptr.space(SpaceLabel.media),
                    .destination = try cl_ptr.space(SpaceLabel.output),
                }
            )
        );
        defer clip_media_to_output.deinit(std.testing.allocator);

        try expectApproxEqAbs(
            @as(f32, 6.5745),
            try clip_media_to_output.project_ordinate(107),
            util.EPSILON,
        );
    }
}

// @TODO: this needs to be init/deinit()
/// top level object
pub const Timeline = struct {
    tracks:Stack = Stack.init(std.testing.allocator),

    pub fn recursively_deinit(self: @This()) void {
        self.tracks.recursively_deinit();
    }
};

/// children of a stack are simultaneous in time
pub const Stack = struct {
    name: ?string.latin_s8 = null,
    children: std.ArrayList(Item),

    pub fn init(allocator: std.mem.Allocator) Stack { 
        return .{
            .children = std.ArrayList(Item).init(allocator)
        };
    }

    pub fn deinit(
        self: @This()
    ) void 
    {
        if (self.name)
            |n|
        {
            self.children.allocator.free(n);
        }
        self.children.deinit();
    }

    pub fn recursively_deinit(self: @This()) void {
        for (self.children.items)
            |c|
        {
            c.recursively_deinit(self.children.allocator);
        }

        self.deinit();
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

fn sequential_child_code_leaky(
    src: treecode.Treecode,
    index: usize
) !treecode.Treecode 
{
    var result = try src.clone();
    var i:usize = 0;
    while (i <= index)
        :(i+=1) 
    {
        try result.append(1);
    }
    return result;
}

test "sequential_child_hash: math" 
{
    var root = try treecode.Treecode.init_word(
        std.testing.allocator,
        0b1000
    );
    defer root.deinit();

    var i:usize = 0;

    var test_code = try root.clone();
    defer test_code.deinit();

    while (i<4) : (i+=1) {
        var result = try sequential_child_code_leaky(root, i);
        defer result.deinit();

        try test_code.append(1);

        errdefer std.debug.print(
            "iteration: {d}, expected: {b} got: {b}\n",
            .{ i, test_code.treecode_array[0], result.treecode_array[0] }
        );

        try std.testing.expect(test_code.eql(result));
    }

}

test "label_for_node_leaky" {
    var tr = Track.init(std.testing.allocator);
    const sr = SpaceReference{
        .label = SpaceLabel.output,
        .item = .{ .track_ptr = &tr } 
    };

    var tc = try treecode.Treecode.init_word(
        std.testing.allocator,
        0b1101001
    );
    defer tc.deinit();

    const result = try TopologicalMap.label_for_node_leaky(
        std.testing.allocator,
        sr,
        tc
    );
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("track_output_1101001", result);
}

test "test spaces list" 
{
    const cl = Clip{};
    const it = ItemPtr{ .clip_ptr = &cl };
    const spaces = try it.spaces(std.testing.allocator);
    defer std.testing.allocator.free(spaces);

    try expectEqual(
       SpaceLabel.output, spaces[0].label, 
    );
    try expectEqual(
       SpaceLabel.media, spaces[1].label, 
    );
    try expectEqual(
       "output", @tagName(SpaceLabel.output)
    );
    try expectEqual(
       "media", @tagName(SpaceLabel.media),
    );
}
