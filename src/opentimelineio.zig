//! Slim OpenTimelineIO Reimplementation for testing high level API
//!
//! Uses the rest of the wrinkles library to implement high level functions
//! that might eventually get ported to 'real' OTIO.
//!

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
const sampling = @import("sampling");

const otio_json = @import("opentimelineio_json.zig");

test {
    _ = otio_json;
}

/// annotate the graph algorithms
// const GRAPH_CONSTRUCTION_TRACE_MESSAGES = true;
const GRAPH_CONSTRUCTION_TRACE_MESSAGES = false;

/// for VERY LARGE files, turn this off so that dot can process the graphs
const LABEL_HAS_BINARY_TREECODE = true;

// @TODO: nick and stephan start here
//
// clip intrinsic space -> continuous space of the media -> discrete sample
// indices of the underlying data
//
// 1. EXR frame on disk: discretely sampled, noninterpolating
// 2. Variable bitrate media: indexed with continuous time
// 3. Audio: discretely sampled, reconstructable/interpolatable
// ------
// 4. no such thing as continuous non-interpolating
//
// The implementation options are a bool for discrete and one for
// interpolating, or a single enum that encodes both dimensions.  Because
// continuous non-interpolating doesn't make sense, and because all three most
// likely require distinct codepaths, an enum makes the most sense.
//
///////////////////////////////////////////////////////////////////////////////
pub const SignalSpace = struct {
    // A sampling represents a continuous cartesian interval with samples at 
    // ordinates within the interval.  Need enough information to feed a
    // sampler/reconstruction algorithm, which is implemented outside of OTIO.

    // probably an enum - "Audio" "Picture" "Fireworks", etc
    signal_domain : []string.latin_s8,

    // regular cyclical sampling
    //   * sampling hz
    //   * start index
    //   * interval in continuous time
    //   * values need to be interpolated to be reconstructed
    // continuous signal
};

/// clip with an implied media reference
pub const Clip = struct {
    name: ?string.latin_s8 = null,

    /// a trim on the media space
    media_temporal_bounds: ?opentime.ContinuousTimeInterval = null,

    /// transformation of the media space to the presentation space
    transform: ?time_topology.TimeTopology = null,

    discrete_info: struct{
        media:  ?sampling.DiscreteDatasourceIndexGenerator = null,
    } = .{},

    pub const SPACES = enum(i8) {
        media = 0,
        presentation = 1,
    };

    /// compute the bounds of the specified target space
    pub fn bounds_of(
        self: @This(),
        target_space: SpaceLabel,
    ) !opentime.ContinuousTimeInterval 
    {
        const presentation_to_media_topo = try self.topology();

        return switch (target_space) {
            .media => presentation_to_media_topo.output_bounds(),
            .presentation => presentation_to_media_topo.input_bounds(),
            else => error.UnsupportedSpaceError,
        };
    }

    pub fn space(
        self: @This(),
        label: SpaceLabel,
    ) !SpaceReference 
    {
        return .{
            .item = ItemPtr{ .clip_ptr = &self },
            .label= label,
        };
    }

    pub fn topology(
        self: @This(),
    ) !time_topology.TimeTopology 
    {
        if (self.media_temporal_bounds) 
            |range| 
        {
            return time_topology.TimeTopology.init_identity(
                .{.bounds=range}
            );
        } else {
            return error.NotImplemented;
        }
    }
};

pub const Gap = struct {
    name: ?string.latin_s8 = null,
    duration: time_topology.Ordinate,

    pub fn topology(
        self: @This()
    ) !time_topology.TimeTopology 
    {
        return time_topology.TimeTopology.init_identity(
            .{ 
                .bounds = .{
                    .start_seconds = 0,
                    .end_seconds = self.duration 
                },
            }
        );
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
            .clip => |cl| (try cl.bounds_of(.media)).duration_seconds(),
            inline .track, .stack, => |tr| try tr.duration(),
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
            inline else => |it_ptr| try it_ptr.topology(),
        };
    }

    pub fn bounds_of(
        self: @This(),
        target_space: SpaceLabel,
    ) !opentime.ContinuousTimeInterval 
    {
        const presentation_to_intrinsic_topo = try self.topology();

        return switch (target_space) {
            .media, .intrinsic => presentation_to_intrinsic_topo.output_bounds(),
            .presentation => presentation_to_intrinsic_topo.input_bounds(),
            else => error.UnsupportedSpaceError,
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
                try result.append( .{ .item = self, .label = SpaceLabel.presentation});
                try result.append( .{ .item = self, .label = SpaceLabel.media});
            },
            .track_ptr, .timeline_ptr, .stack_ptr => {
                try result.append( .{ .item = self, .label = SpaceLabel.presentation});
                try result.append( .{ .item = self, .label = SpaceLabel.intrinsic});
            },
            .gap_ptr => {
                try result.append( .{ .item = self, .label = SpaceLabel.presentation});
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
                "    transform from space: {s} to space: {s} ",
                .{ @tagName(from_space), @tagName(to_space.label) }
            );

            if (to_space.child_index)
                |ind|
            {
                std.debug.print(
                    " index: {d}",
                    .{ind}
                );

            }
            std.debug.print( "\n", .{});
        }

        return switch (self) {
            .track_ptr => |*tr| {
                switch (from_space) {
                    SpaceLabel.presentation => (
                        return time_topology.TimeTopology.init_identity_infinite()
                    ),
                    SpaceLabel.intrinsic => (
                        return time_topology.TimeTopology.init_identity_infinite()
                    ),
                    SpaceLabel.child => {
                        if (GRAPH_CONSTRUCTION_TRACE_MESSAGES) {
                            std.debug.print("     CHILD STEP: {b}\n", .{ step});
                        }

                        // no further transformation INTO the child
                        if (step == 0) {
                            return (
                                time_topology.TimeTopology.init_identity_infinite()
                            );
                        } 
                        else 
                        {
                            // transform to the next child
                            return try tr.*.transform_to_child(to_space);
                        }

                    },
                    // track supports no other spaces
                    else => return error.UnsupportedSpaceError,
                }
            },
            .clip_ptr => |*cl| {
                // Clip spaces and transformations
                //
                // key: 
                //   + space
                //   * transformation
                //
                // +--- presentation
                // |
                // *--- (implicit) post transform->presentation space (reset start time to 0)
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
                // initially only exposing the MEDIA and presentation spaces
                //

                return switch (from_space) {
                    SpaceLabel.presentation => {
                        // goes to media
                        const presentation_to_post_transform = (
                            time_topology.TimeTopology.init_identity_infinite()
                        );

                        const post_transform_to_intrinsic = (
                            cl.*.transform 
                            orelse time_topology.TimeTopology.init_identity_infinite()
                        );

                        const presentation_to_intrinsic = (
                            try post_transform_to_intrinsic.project_topology(
                                allocator,
                                presentation_to_post_transform,
                            )
                        );
                        defer presentation_to_intrinsic.deinit(allocator);

                        const media_bounds = try cl.*.bounds_of(.media);
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

                        const presentation_to_media = try intrinsic_to_media.project_topology(
                            allocator,
                            presentation_to_intrinsic
                        );

                        return presentation_to_media;
                    },
                    else => time_topology.TimeTopology.init_identity(
                        .{
                            .bounds = try cl.*.bounds_of(.media)
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

    pub fn continuous_ordinate_to_discrete_index(
        self: @This(),
        ord_continuous: f32,
        in_space: SpaceLabel,
    ) !usize
    {
        const maybe_discrete_info = (
            try self.discrete_info_for_space(in_space)
        );
        if (maybe_discrete_info)
            |discrete_info|
        {
            return sampling.project_instantaneous_cd(
                discrete_info,
                ord_continuous
            );
        }

        return error.SpaceOnObjectHasNoDiscreteSpecification;
    }
   
    pub fn continuous_to_discrete_topology(
        self: @This(),
        allocator: std.mem.Allocator,
        in_space: SpaceLabel,
    ) !time_topology.TimeTopology
    {
        const maybe_discrete_info = (
            try self.discrete_info_for_space(in_space)
        );
        if (maybe_discrete_info == null)
        {
            return error.SpaceOnObjectHasNoDiscreteSpecification;
        }

        const discrete_info = maybe_discrete_info.?;

        const target_topo = try self.topology();
        const extents = target_topo.input_bounds();

        return try time_topology.TimeTopology.init_step_mapping(
            allocator,
            extents,
            // start
            @floatFromInt(discrete_info.start_index),
            // held durations
            1.0 / @as(f32, @floatFromInt(discrete_info.sample_rate_hz)),
            // increment -- @TODO: support other increments ("on twos", etc)
            1.0,
        );
    }

    pub fn discrete_info_for_space(
        self: @This(),
        in_space: SpaceLabel,
    ) !?sampling.DiscreteDatasourceIndexGenerator
    {
        return switch (self) {
            .timeline_ptr => |tl| switch (in_space) {
                .presentation => tl.discrete_info.presentation,
                inline else => error.SpaceOnObjectCannotBeDiscrete,
            },
            .clip_ptr => |cl| switch (in_space) {
                .media => cl.discrete_info.media,
                inline else => error.SpaceOnObjectCannotBeDiscrete,
            },
            inline else => error.ObjectDoesNotSupportDiscretespaces,
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
            const it_bound = (try it.topology()).input_bounds();
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

    /// builds a transform from the previous child spce to the one passed in the
    /// child_space_reference
    ///
    /// because graphs are constructed:
    ///         track
    ///           |
    ///           child 0
    ///           |     \
    /// child 0.presentation   child 1
    ///                   |   \
    ///       child.1.presentation   child 2
    ///                         ...
    ///
    ///  if called on child space child 1, will make a transform to child
    ///  space 1 from child space 0
    /// 
    pub fn transform_to_child(
        self: @This(),
        // @TODO: this is super confusing for what it does and should be
        //        renamed
        child_space_reference: SpaceReference,
    ) !time_topology.TimeTopology 
    {
        // [child 1][child 2]
        const child_index = (
            child_space_reference.child_index 
            orelse return error.NoChildIndexOnChildSpaceReference
        );

        // XXX should probably check the index before calling this and call this
        //     with index - 1 rather than have it do the offset here.
        const child = self.child_ptr_from_index(child_index - 1);
        const child_range = try child.bounds_of(.media);
        const child_duration = child_range.duration_seconds();

        // the transform to the next child space, compensates for this duration
        return time_topology.TimeTopology.init_affine(
            .{
                .bounds = .{
                    // .start_seconds = child_range.start_seconds + child_duration,
                    .start_seconds = child_duration,
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
    presentation = 0,
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

/// Combines a source, destination and transformation from the source to the
/// destination.  Allows continuous and discrete transformations.
const ProjectionOperator = struct {
    args: ProjectionOperatorArgs,
    topology: time_topology.TimeTopology,

    // options:
    //  instant
    //   project_instantaneous_cc -> ordinate -> ordinate
    //   project_instantaneous_cd -> ordinate -> index
    //  topology-based
    //   project_topology_cc -> topology -> topology
    //   project_topology_cd -> topology -> index array
    //
    //   derivatives:
    //
    //    project_range_cc -> range -> topology
    //    project_range_cd -> range -> index array
    //    project_index_dc -> index -> topology
    //    project_index_dd -> index -> index array
    //    project_indices_dc -> index array -> topology
    //    project_indices_dd -> index array -> index array

    ///project a continuous ordinate to the continuous destination space
    pub fn project_instantaneous_cc(
        self: @This(),
        ordinate_in_source_space: f32
    ) !f32 
    {
        return self.topology.project_ordinate(ordinate_in_source_space);
    }

    // @TODO: remove this alias
    pub const project_ordinate = project_instantaneous_cc;

    /// project a continuous ordinate to the destination discrete sample index
    pub fn project_instantaneous_cd(
        self: @This(),
        ordinate_in_source_space: f32,
    ) !usize 
    {
        const continuous_in_destination_space =  (
            try self.topology.project_ordinate(ordinate_in_source_space)
        );

        return try self.args.destination.item.continuous_ordinate_to_discrete_index(
            continuous_in_destination_space,
            self.args.destination.label,
        );
    }

    /// project a topology from the continuous source space into the continuous
    /// destination space
    pub fn project_topology_cc(
        self: @This(),
        allocator: std.mem.Allocator,
        topology_in_source: time_topology.TimeTopology,
    ) !time_topology.TimeTopology
    {
        // project the source range into the destination space
        const topology_in_destination = (
            try self.topology.project_topology(
                allocator,
                topology_in_source
            )
        );
        
        return topology_in_destination;
    }

    /// project a topology from the continuous source space into the discrete
    /// destination space
    pub fn project_topology_cd(
        self: @This(),
        allocator: std.mem.Allocator,
        topology_in_source: time_topology.TimeTopology,
    ) ![]usize
    {
        // project the source range into the destination space
        const topology_in_destination_c = (
            try self.project_topology_cc(
                allocator,
                topology_in_source
            )
        );
        defer topology_in_destination_c.deinit(allocator);

        // XXX @TODO BARF HACK: current state of the world requires linearizing
        //                      explicitly here.  Obviously it would be better
        //                      to not need to do that.

        const topology_in_destination_c_lin = (
            try topology_in_destination_c.linearized(allocator)
        );
        defer topology_in_destination_c_lin.deinit(allocator);

        // build a topology of the sampling in the destination space
        const destination_c2d = (
            try self.args.destination.item.continuous_to_discrete_topology(
                allocator,
                self.args.destination.label,
            )
        );
        defer destination_c2d.deinit(allocator);

        const destination_c2d_lin = try destination_c2d.linearized(allocator);
        defer destination_c2d_lin.deinit(allocator);

        // project the range through the continuous->discrete function
        const range_in_destination_d = (
            try topology_in_destination_c_lin.project_topology(
                allocator,
                destination_c2d_lin,
            )
        );
        defer range_in_destination_d.deinit(allocator);

        const discrete_info = (
            try self.args.destination.item.discrete_info_for_space(
                self.args.destination.label
            )
        ).?;

        var index_buffer_destination_discrete = (
            std.ArrayList(usize).init(allocator)
        );
        defer index_buffer_destination_discrete.deinit();

        const range_in_destination_d_extents = (
            range_in_destination_d.output_bounds()
        );
        const duration:f32 = (
            1.0 / @as(f32, @floatFromInt(discrete_info.sample_rate_hz))
        );

        // convert the range in the discrete space to sample indices
        var t = range_in_destination_d_extents.start_seconds;
        while (t < range_in_destination_d_extents.end_seconds)
            : (t += duration)
        {
            try index_buffer_destination_discrete.append(
                try self.args.destination.item.continuous_ordinate_to_discrete_index(
                    t,
                    self.args.destination.label,
                )
            );
        }

        return index_buffer_destination_discrete.toOwnedSlice();
    }

    /// project a continuous range into the continuous destination space
    pub fn project_range_cc(
        self: @This(),
        allocator: std.mem.Allocator,
        range_in_source: opentime.ContinuousTimeInterval,
    ) !time_topology.TimeTopology
    {
        // build a topology over the range in the source space
        const topology_in_source = (
            time_topology.TimeTopology.init_affine(
                .{ 
                    .transform = .{ 
                        .offset_seconds = range_in_source.start_seconds,
                        .scale = 1.0,
                    },
                    .bounds = .{
                        .start_seconds = 0,
                        .end_seconds = range_in_source.duration_seconds(),
                    },
                }
            )
        );

        return try self.project_topology_cc(
            allocator,
            topology_in_source,
        );
    }

    /// project a continuous range into the discrete index space
    pub fn project_range_cd(
        self: @This(),
        allocator: std.mem.Allocator,
        range_in_source: opentime.ContinuousTimeInterval,
    ) ![]usize
    {
        // build a topology over the range in the source space
        const range_in_source_c_topo = (
            time_topology.TimeTopology.init_identity(
                .{ 
                    .bounds = range_in_source,
                }
            )
        );

        return try self.project_topology_cd(
            allocator,
            range_in_source_c_topo,
        );
    }


    /// project a discete sample index to the destination discrete sample index
    // pub fn project_instantaneous_dd(
    //     self: @This(),
    //     sample_index_in_source_space: usize,
    // ) !f32 
    // {
        //source discrete -> source continuous

        // source continuous -> destination continuous
        // const continuous_in_destination_space =  (
        //     try self.topology.project_ordinate(ordinate_in_source_space)
        // );
        //
        // // destination continuous -> destinatino discrete
        // return self.args.destination.continuous_ordinate_to_discrete_index(
        //     continuous_in_destination_space
        // );
    // }

    pub fn deinit(
        self: @This(),
        allocator: std.mem.Allocator,
    ) void
    {
        self.topology.deinit(allocator);
    }

    /// return true if lhs.topology.input_bounds().start_time < rhs...
    pub fn less_than_input_space_start_point(
        lhs: @This(),
        rhs: @This(),
    ) bool
    {
        return (
            lhs.topology.input_bounds().start_time 
            < rhs.topology.input_bounds().start_time
        );
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
            const args = .{ 
                item_kind,
                @tagName(ref.label), code.hash(), 
            };

            return std.fmt.allocPrint(allocator, "{s}_{s}_{any}", args);
        }
    }

    /// write a graphviz (dot) format serialization of this TopologicalMap
    pub fn write_dot_graph(
        self:@This(),
        parent_allocator: std.mem.Allocator,
        filepath: string.latin_s8
    ) !void 
    {
        const root_space = self.root(); 
        
        // note that this function is pretty sloppy with allocations.  it
        // doesn't do any cleanup until the function ends, when the entire var
        // arena is cleared in one shot.
        var arena = std.heap.ArenaAllocator.init(
            parent_allocator
        );
        defer arena.deinit();
        const allocator = arena.allocator();

        var buf = std.ArrayList(u8).init(allocator);

        // open the file
        const file = try std.fs.createFileAbsolute(
            filepath,
            .{}
        );
        defer file.close();

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
                } 
                else 
                {
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
                    try stack.append(
                        .{
                            .space = next,
                            .code = right
                        }
                    );
                } 
                else 
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

        const pngfilepath = try std.fmt.allocPrint(
            allocator,
            "{s}.png",
            .{ filepath }
        );
        defer allocator.free(pngfilepath);

        // @TODO: gate the dot/png render on if dot is installed

        // render to png
        const result = try std.process.Child.run(
            .{
                .allocator = std.heap.page_allocator,
                .argv = &[_][]const u8{
                    "dot",
                    "-Tpng",
                    filepath,
                    "-o",
                    pngfilepath
                },
            }
        );
        _ = result;
        // std.debug.print("{s}\n", .{result.stdout});
    }
};

/// maps projections to clip.media spaces to regions of whatever space is
/// the source space
pub fn projection_map_to_media_from(
    allocator: std.mem.Allocator,
    topological_map: TopologicalMap,
    source: SpaceReference,
) !ProjectionOperatorMap
{
    var iter = (
        try TreenodeWalkingIterator.init_at(
            allocator,
            &topological_map, 
            source,
        )
    );
    defer iter.deinit();

    var result = ProjectionOperatorMap{
        .allocator = allocator,
    };

    var proj_args = ProjectionOperatorArgs{
        .source = source,
        .destination = source,
    };
    while (try iter.next())
    {
        const current = iter.maybe_current.?;

        // skip all spaces that are not media spaces
        if (current.space.label != .media) {
            continue;
        }

        proj_args.destination = current.space;

        const child_op = (
            try topological_map.build_projection_operator(
                allocator,
                proj_args
            )
        );

        const child_op_map = (
            try ProjectionOperatorMap.init_operator(
                allocator,
                child_op,
            )
        );
        defer child_op_map.deinit();

        const last = result;
        defer last.deinit();

        result = try ProjectionOperatorMap.merge_composite(
            allocator,
            .{
                .over = result,
                .under = child_op_map,
            }
        );
    }

    return result;
}

test "ProjectionOperatorMap: init_operator leak test"
{
    const cl = Clip{};
    const cl_ptr = ItemPtr{ .clip_ptr = &cl };
    const child_op_map = (
        try ProjectionOperatorMap.init_operator(
            std.testing.allocator,
            .{
                .args = .{
                    .source = try cl_ptr.space(.presentation),
                    .destination = try cl_ptr.space(.media),
                },
                .topology = time_topology.TimeTopology.init_empty(),
            },
        )
    );
    defer child_op_map.deinit();

    const clone = try child_op_map.clone();
    clone.deinit();
}

test "ProjectionOperatorMap: projection_map_to_media_from leak test"
{
    const cl = Clip {
        .media_temporal_bounds = .{
            .start_seconds = 1,
            .end_seconds = 9 
        }
    };
    const cl_ptr = ItemPtr{ .clip_ptr = &cl };

    const map = try build_topological_map(
        std.testing.allocator,
        cl_ptr,
    );
    defer map.deinit();

    const m = try projection_map_to_media_from(
        std.testing.allocator,
        map,
        try cl_ptr.space(.presentation),
    );
    defer m.deinit();
}

/// maps a timeline to sets of projection operators, one set per temporal slice
const ProjectionOperatorMap = struct {
    allocator: std.mem.Allocator,

    /// segment endpoints
    end_points: []f32 = &.{},
    /// segment projection operators 
    operators : [][]ProjectionOperator = &.{},

    pub fn init_operator(
        allocator: std.mem.Allocator,
        op: ProjectionOperator,
    ) !ProjectionOperatorMap
    {

        const input_bounds = op.topology.input_bounds();
        const end_points = try allocator.dupe(
            f32,
            &.{ input_bounds.start_seconds, input_bounds.end_seconds } 
        );

        var operators = try allocator.alloc(
            []ProjectionOperator,
            1
        );
        operators[0] = try allocator.dupe(ProjectionOperator, &.{ op });
        
        return .{
            .allocator = allocator,
            .end_points = end_points,
            .operators = operators,
        };
    }

    pub fn deinit(
        self: @This()
    ) void
    {
        self.allocator.free(self.end_points);
        for (self.operators)
            |segment_ops|
        {
            for (segment_ops)
                |op|
            {
                op.deinit(self.allocator);
            }
            self.allocator.free(segment_ops);
        }
        self.allocator.free(self.operators);
    }

    const OverlayArgs = struct{
        over: ProjectionOperatorMap,
        under: ProjectionOperatorMap,
    };
    pub fn merge_composite(
        parent_allocator: std.mem.Allocator,
        args: OverlayArgs
    ) !ProjectionOperatorMap
    {
        if (args.over.is_empty() and args.under.is_empty())
        {
            return .{ .allocator = parent_allocator, };
        }
        if (args.over.is_empty())
        {
            return try args.under.clone();
        }
        if (args.under.is_empty())
        {
            return try args.over.clone();
        }

        var arena = std.heap.ArenaAllocator.init(
            parent_allocator
        );
        defer arena.deinit();
        const arena_allocator = arena.allocator();

        const over = args.over;
        const undr = args.under;

        const full_range = opentime.ContinuousTimeInterval{
            .start_seconds = @min(over.end_points[0], undr.end_points[0]),
            .end_seconds = @max(
                over.end_points[over.end_points.len - 1],
                undr.end_points[undr.end_points.len - 1],
            ),
        };

        const over_extended = try over.extend_to(
            arena_allocator,
            full_range,
        );
        const undr_extended = try undr.extend_to(
            arena_allocator,
            full_range,
        );

        // project all splits from over to undr
        const over_conformed = try over_extended.split_at_each(
            arena_allocator,
            undr_extended.end_points
        );
        const undr_conformed = try undr_extended.split_at_each(
            arena_allocator,
            over_conformed.end_points
        );

        var end_points = std.ArrayList(f32).init(
            parent_allocator,
        );
        var operators = std.ArrayList(
            []ProjectionOperator
        ).init(parent_allocator);

        var current_segment = (
            std.ArrayList(ProjectionOperator).init(arena_allocator)
        );

        // both end point arrays are the same
        for (over_conformed.end_points[0..over_conformed.end_points.len - 1], 0..)
            |p, ind|
        {
            try end_points.append(p);
            try current_segment.appendSlice(over_conformed.operators[ind]);
            try current_segment.appendSlice(undr_conformed.operators[ind]);
            try operators.append(
                try parent_allocator.dupe(
                    ProjectionOperator,
                    current_segment.items,
                )
            );

            current_segment.clearAndFree();
        }

        try end_points.append(
            over_conformed.end_points[over_conformed.end_points.len - 1]
        );

        return .{
            .allocator = parent_allocator,
            .end_points  = try end_points.toOwnedSlice(),
            .operators  = try operators.toOwnedSlice(),
        };
    }

    pub fn is_empty(
        self: @This(),
    ) bool
    {
        return self.end_points.len == 0 or self.operators.len == 0;
    }

    pub fn clone(
        self: @This(),
    ) !ProjectionOperatorMap
    {
        return .{
            .allocator = self.allocator,
            .end_points = try self.allocator.dupe(
                f32,
                self.end_points
            ),
            .operators = ops: {
                const outer = (
                    try self.allocator.alloc(
                        []ProjectionOperator,
                        self.operators.len,
                    )
                );
                for (outer, self.operators)
                    |*inner, source|
                {
                    inner.* = try self.allocator.dupe(
                        ProjectionOperator,
                        source,
                    );
                }
                break :ops outer;
            }
        };
    }

    pub fn extend_to(
        self: @This(),
        allocator: std.mem.Allocator,
        range: opentime.ContinuousTimeInterval,
    ) !ProjectionOperatorMap
    {
        var tmp_pts = std.ArrayList(f32).init(allocator);
        defer tmp_pts.deinit();
        var tmp_ops = std.ArrayList([]ProjectionOperator).init(allocator);
        defer tmp_ops.deinit();

        if (self.end_points[0] > range.start_seconds) {
            try tmp_pts.append(range.start_seconds);
            try tmp_ops.append(
                &.{}
            );
        }

        try tmp_pts.appendSlice(self.end_points);

        for (self.operators) 
            |self_ops|
        {
            try tmp_ops.append(
                try allocator.dupe(ProjectionOperator, self_ops)
            );
        }

        if (range.end_seconds > self.end_points[self.end_points.len - 1]) 
        {
            try tmp_pts.append(range.end_seconds);
            try tmp_ops.append(
                &.{}
            );
        }

        return .{
            .allocator = allocator,
            .end_points = try tmp_pts.toOwnedSlice(),
            .operators = try tmp_ops.toOwnedSlice(),
        };
    }

    pub fn split_at_each(
        self: @This(),
        allocator: std.mem.Allocator,
        /// pts should have the same start and end point as self
        pts: []const f32,
    ) !ProjectionOperatorMap
    {
        var tmp_pts = std.ArrayList(f32).init(allocator);
        var tmp_ops = std.ArrayList([]ProjectionOperator).init(allocator);

        var ind_self:usize = 0;
        var ind_other:usize = 0;

        var t_next_self = self.end_points[1];
        var t_next_other = pts[1];

        // append origin
        try tmp_pts.append(self.end_points[0]);

        while (
            ind_self < self.end_points.len - 1
            and ind_other < pts.len - 1 
        )
        {
            try tmp_ops.append(
                try allocator.dupe(
                    ProjectionOperator,
                    self.operators[ind_self],
                )
            );

            t_next_self = self.end_points[ind_self+1];
            t_next_other = pts[ind_other+1];

            if (
                std.math.approxEqAbs(
                    f32,
                    t_next_self,
                    t_next_other,
                    util.EPSILON
                )
            )
            {
                try tmp_pts.append(t_next_self);
                if (ind_self < self.end_points.len - 1) {
                    ind_self += 1;
                }
                if (ind_other < pts.len - 1) {
                    ind_other += 1;
                }
            }
            else if (t_next_self < t_next_other)
            {
                try tmp_pts.append(t_next_self);
                ind_self += 1;
            }
            else 
            {
                try tmp_pts.append(t_next_other);
                ind_other += 1;
            }
        }

        return .{
            .allocator = allocator,
            .end_points = try tmp_pts.toOwnedSlice(),
            .operators = try tmp_ops.toOwnedSlice(),
        };
    }

};

test "ProjectionOperatorMap: extend_to"
{
    const cl = Clip {
        .media_temporal_bounds = .{
            .start_seconds = 1,
            .end_seconds = 9 
        }
    };
    const cl_ptr = ItemPtr{ .clip_ptr = &cl };

    const map = try build_topological_map(
        std.testing.allocator,
        cl_ptr,
    );
    defer map.deinit();

    const cl_presentation_pmap = (
        try projection_map_to_media_from(
            std.testing.allocator,
            map,
            try cl_ptr.space(.presentation),
        )
    );
    defer cl_presentation_pmap.deinit();

    // extend_to no change
    {
        const result = try cl_presentation_pmap.extend_to(
            std.testing.allocator,
            .{
                .start_seconds = cl_presentation_pmap.end_points[0],
                .end_seconds = cl_presentation_pmap.end_points[1],
            },
        );
        defer result.deinit();

        try std.testing.expectEqualSlices(
            f32,
            cl_presentation_pmap.end_points,
            result.end_points,
        );
        try std.testing.expectEqual(
            cl_presentation_pmap.operators.len,
            result.operators.len,
        );
    }

    // add before
    {
        const result = try cl_presentation_pmap.extend_to(
            std.testing.allocator,
            .{
                .start_seconds = -10,
                .end_seconds = 8,
            },
        );
        defer result.deinit();

        try std.testing.expectEqualSlices(
            f32,
            &.{-10, 0, 8},
            result.end_points,
        );

        try std.testing.expectEqual(
            2,
            result.operators.len,
        );
    }

    // add after
    {
        const result = try cl_presentation_pmap.extend_to(
            std.testing.allocator,
            .{
                .start_seconds = 0,
                .end_seconds = 18,
            },
        );
        defer result.deinit();

        try std.testing.expectEqualSlices(
            f32,
            &.{0, 8, 18},
            result.end_points,
        );

        try std.testing.expectEqual(
            2,
            result.operators.len,
        );
    }
}

test "ProjectionOperatorMap: split_at_each"
{
    const cl = Clip {
        .media_temporal_bounds = .{
            .start_seconds = 1,
            .end_seconds = 9 
        }
    };
    const cl_ptr = ItemPtr{ .clip_ptr = &cl };

    const map = try build_topological_map(
        std.testing.allocator,
        cl_ptr,
    );
    defer map.deinit();

    const cl_presentation_pmap = (
        try projection_map_to_media_from(
            std.testing.allocator,
            map,
            try cl_ptr.space(.presentation),
        )
    );
    defer cl_presentation_pmap.deinit();

    // split_at_each -- no change
    {
        const result = try cl_presentation_pmap.split_at_each(
            std.testing.allocator,
            cl_presentation_pmap.end_points,
        );
        defer result.deinit();

        try std.testing.expectEqualSlices(
            f32,
            cl_presentation_pmap.end_points,
            result.end_points,
        );
        try std.testing.expectEqual(
            cl_presentation_pmap.operators.len,
            result.operators.len,
        );
    }

    // split_at_each -- end points are same, split in middle
    {
        const pts = [_]f32{ 0, 4, 8 };

        const result = try cl_presentation_pmap.split_at_each(
            std.testing.allocator,
            &pts,
        );
        defer result.deinit();

        try std.testing.expectEqualSlices(
            f32,
            &pts,
            result.end_points,
        );

        try std.testing.expectEqual(
            cl_presentation_pmap.operators.len + 1,
            result.operators.len,
        );
    }

    // split_at_each -- end points are same, split in middle twice
    {
        const pts = [_]f32{ 0, 1, 4, 8 };

        const result = try cl_presentation_pmap.split_at_each(
            std.testing.allocator,
            &pts,
        );
        defer result.deinit();

        try std.testing.expectEqualSlices(
            f32,
            &pts,
            result.end_points,
        );

        try std.testing.expectEqual(
            3,
            result.operators.len,
        );
    }

    // split_at_each -- end points are same, split offset
    {
        const pts1 = [_]f32{ 0, 4, 8 };
        const pts2 = [_]f32{ 0, 4, 8 };

        const inter = try cl_presentation_pmap.split_at_each(
            std.testing.allocator,
            &pts1,
        );
        defer inter.deinit();

        const result = try inter.split_at_each(
            std.testing.allocator,
            &pts2,
        );
        defer result.deinit();

        try std.testing.expectEqualSlices(
            f32,
            &.{0,4,8},
            result.end_points,
        );

        try std.testing.expectEqual(
            2,
            result.operators.len,
        );
    }
}

test "ProjectionOperatorMap: merge_composite"
{
    const cl = Clip {
        .media_temporal_bounds = .{
            .start_seconds = 1,
            .end_seconds = 9 
        }
    };
    const cl_ptr = ItemPtr{ .clip_ptr = &cl };

    const map = try build_topological_map(
        std.testing.allocator,
        cl_ptr,
    );
    defer map.deinit();

    const cl_presentation_pmap = (
        try projection_map_to_media_from(
            std.testing.allocator,
            map,
            try cl_ptr.space(.presentation),
        )
    );
    defer cl_presentation_pmap.deinit();

    {
        const result = (
            try ProjectionOperatorMap.merge_composite(
                std.testing.allocator,
                .{
                    .over = cl_presentation_pmap,
                    .under = cl_presentation_pmap,
                }
            )
        );
        defer result.deinit();

        try std.testing.expectEqualSlices(
            f32,
            cl_presentation_pmap.end_points,
            result.end_points,
        );
        try std.testing.expectEqual(
            1,
            result.operators.len
        );
    }
}

test "ProjectionOperatorMap: clip"
{
    const cl = Clip {
        .media_temporal_bounds = .{
            .start_seconds = 1,
            .end_seconds = 9 
        }
    };
    const cl_ptr = ItemPtr{ .clip_ptr = &cl };

    const map = try build_topological_map(
        std.testing.allocator,
        cl_ptr,
    );
    defer map.deinit();

    const cl_presentation_pmap = (
        try projection_map_to_media_from(
            std.testing.allocator,
            map,
            try cl_ptr.space(.presentation),
        )
    );
    defer cl_presentation_pmap.deinit();

    try expectEqual(1, cl_presentation_pmap.operators.len);
    try expectEqual(2, cl_presentation_pmap.end_points.len);

    const known_presentation_to_media = (
        try map.build_projection_operator(
            std.testing.allocator,
            .{
                .source = try cl_ptr.space(.presentation),
                .destination = try cl_ptr.space(.media),
            },
        )
    );
    const known_input_bounds = known_presentation_to_media.topology.input_bounds();

    const guess_presentation_to_media = (
        cl_presentation_pmap.operators[0][0]
    );
    const guess_input_bounds = guess_presentation_to_media.topology.input_bounds();

    // topology input bounds match
    try expectApproxEqAbs(
        known_input_bounds.start_seconds,
        guess_input_bounds.start_seconds,
        util.EPSILON
    );
    try expectApproxEqAbs(
        known_input_bounds.end_seconds,
        guess_input_bounds.end_seconds,
        util.EPSILON
    );

    // end points match topology
    try expectApproxEqAbs(
        cl_presentation_pmap.end_points[0],
        guess_input_bounds.start_seconds,
        util.EPSILON
    );
    try expectApproxEqAbs(
        cl_presentation_pmap.end_points[1],
        guess_input_bounds.end_seconds,
        util.EPSILON
    );

    // known input bounds matches end point
    try expectApproxEqAbs(
        known_input_bounds.start_seconds,
        cl_presentation_pmap.end_points[0],
        util.EPSILON
    );
    try expectApproxEqAbs(
        known_input_bounds.end_seconds,
        cl_presentation_pmap.end_points[1],
        util.EPSILON
    );
}

test "ProjectionOperatorMap: track with single clip"
{
    var tr = Track.init(std.testing.allocator);
    defer tr.deinit();

    const cl = Clip {
        .media_temporal_bounds = .{
            .start_seconds = 1,
            .end_seconds = 9 
        }
    };
    try tr.append(.{ .clip = cl });
    const tr_ptr = ItemPtr{ .track_ptr = &tr };
    const cl_ptr = tr.child_ptr_from_index(0);

    const map = try build_topological_map(
        std.testing.allocator,
        tr_ptr,
    );
    defer map.deinit();

    const source_space = try tr_ptr.space(.presentation);

    const test_maps = &[_]ProjectionOperatorMap{
        // try build_projection_operator_map(
        //     std.testing.allocator,
        //     map,
        //     try cl_ptr.space(.presentation),
        // ),
        try projection_map_to_media_from(
            std.testing.allocator,
            map,
            source_space,
        ),
    };

    for (test_maps)
        |projection_operator_map|
    {
        defer projection_operator_map.deinit();

        try expectEqual(1, projection_operator_map.operators.len);
        try expectEqual(2, projection_operator_map.end_points.len);

        const known_presentation_to_media = try map.build_projection_operator(
            std.testing.allocator,
            .{
                .source = try tr_ptr.space(.presentation),
                .destination = try cl_ptr.space(.media),
            },
        );
        const known_input_bounds = known_presentation_to_media.topology.input_bounds();

        const guess_presentation_to_media = projection_operator_map.operators[0][0];
        const guess_input_bounds = guess_presentation_to_media.topology.input_bounds();

        // topology input bounds match
        try expectApproxEqAbs(
            known_input_bounds.start_seconds,
            guess_input_bounds.start_seconds,
            util.EPSILON
        );
        try expectApproxEqAbs(
            known_input_bounds.end_seconds,
            guess_input_bounds.end_seconds,
            util.EPSILON
        );

        // end points match topology
        try expectApproxEqAbs(
            projection_operator_map.end_points[0],
            guess_input_bounds.start_seconds,
            util.EPSILON
        );
        try expectApproxEqAbs(
            projection_operator_map.end_points[1],
            guess_input_bounds.end_seconds,
            util.EPSILON
        );

        // known input bounds matches end point
        try expectApproxEqAbs(
            known_input_bounds.start_seconds,
            projection_operator_map.end_points[0],
            util.EPSILON
        );
        try expectApproxEqAbs(
            known_input_bounds.end_seconds,
            projection_operator_map.end_points[1],
            util.EPSILON
        );
    }
}

test "transform: track with two clips"
{
    var tr = Track.init(std.testing.allocator);
    defer tr.deinit();

    const cl1 = Clip {
        .media_temporal_bounds = .{
            .start_seconds = 1,
            .end_seconds = 9 
        }
    };
    const cl2 = Clip {
        .media_temporal_bounds = .{
            .start_seconds = 1,
            .end_seconds = 4 
        }
    };
    try tr.append(.{ .clip = cl1 });
    try tr.append(.{ .clip = cl2 });
    const tr_ptr = ItemPtr{ .track_ptr = &tr };
    const cl_ind1_ptr = tr.child_ptr_from_index(1);

    const map = try build_topological_map(
        std.testing.allocator,
        tr_ptr,
    );
    defer map.deinit();

    const track_presentation_space = try tr_ptr.space(.presentation);

    {
        const child_code = (
            try treecode.Treecode.init_word(std.testing.allocator, 0b1110)
        );
        defer child_code.deinit();

        const child_space = map.map_code_to_space.get(child_code).?;

        const xform = try tr.transform_to_child(child_space);

        const b = xform.input_bounds();

        try std.testing.expectEqualSlices(
            f32,
            &.{8},
            &.{b.start_seconds},
        );
    }

    {
        const xform = try map.build_projection_operator(
            std.testing.allocator,
            .{
                .source = track_presentation_space,
                .destination = try cl_ind1_ptr.space(.media),
            }
        );
        const b = xform.topology.input_bounds();

        const cl1_range = try cl1.bounds_of(.media);
        const cl2_range = try cl2.bounds_of(.media);

        try std.testing.expectEqualSlices(
            f32,
            &.{
                cl1_range.duration_seconds(),
                cl1_range.duration_seconds() + cl2_range.duration_seconds() 
            },
            &.{b.start_seconds, b.end_seconds},
        );
    }
}

test "ProjectionOperatorMap: track with two clips"
{
    var tr = Track.init(std.testing.allocator);
    defer tr.deinit();

    const cl = Clip {
        .media_temporal_bounds = .{
            .start_seconds = 1,
            .end_seconds = 9 
        }
    };
    try tr.append(.{ .clip = cl });
    try tr.append(.{ .clip = cl });
    const tr_ptr = ItemPtr{ .track_ptr = &tr };
    const cl_ptr = tr.child_ptr_from_index(1);

    const map = try build_topological_map(
        std.testing.allocator,
        tr_ptr,
    );
    defer map.deinit();

    const source_space = try tr_ptr.space(.presentation);

    const p_o_map = (
        try projection_map_to_media_from(
            std.testing.allocator,
            map,
            source_space,
        )
    );

    defer p_o_map.deinit();

    try std.testing.expectEqualSlices(
        f32,
        &.{0,8,16},
        p_o_map.end_points,
    );
    try expectEqual(2, p_o_map.operators.len);

    const known_presentation_to_media = (
        try map.build_projection_operator(
            std.testing.allocator,
            .{
                .source = try tr_ptr.space(.presentation),
                .destination = try cl_ptr.space(.media),
            },
        )
    );
    const known_input_bounds = (
        known_presentation_to_media.topology.input_bounds()
    );

    const guess_presentation_to_media = p_o_map.operators[1][0];
    const guess_input_bounds = (
        guess_presentation_to_media.topology.input_bounds()
    );

    // topology input bounds match
    try expectApproxEqAbs(
        known_input_bounds.start_seconds,
        guess_input_bounds.start_seconds,
        util.EPSILON
    );
    try expectApproxEqAbs(
        known_input_bounds.end_seconds,
        guess_input_bounds.end_seconds,
        util.EPSILON
    );

    // end points match topology
    try expectApproxEqAbs(
        8.0,
        guess_input_bounds.start_seconds,
        util.EPSILON
    );
    try expectApproxEqAbs(
        16,
        guess_input_bounds.end_seconds,
        util.EPSILON
    );
}

test "ProjectionOperatorMap: track [c1][gap][c2]"
{
    var tr = Track.init(std.testing.allocator);
    defer tr.deinit();

    const cl = Clip {
        .media_temporal_bounds = .{
            .start_seconds = 1,
            .end_seconds = 9 
        }
    };
    const gp = Gap{
        .duration = 5,
    };
    try tr.append(.{ .clip = cl });
    try tr.append(.{ .gap = gp });
    try tr.append(.{ .clip = cl });

    const tr_ptr = ItemPtr{ .track_ptr = &tr };
    const cl_ptr = tr.child_ptr_from_index(2);

    const map = try build_topological_map(
        std.testing.allocator,
        tr_ptr,
    );
    defer map.deinit();

    const source_space = try tr_ptr.space(.presentation);

    const p_o_map = (
        try projection_map_to_media_from(
            std.testing.allocator,
            map,
            source_space,
        )
    );

    defer p_o_map.deinit();

    try std.testing.expectEqualSlices(
        f32,
        &.{0,8,13, 21},
        p_o_map.end_points,
    );
    try expectEqual(3, p_o_map.operators.len);

    const known_presentation_to_media = (
        try map.build_projection_operator(
            std.testing.allocator,
            .{
                .source = try tr_ptr.space(.presentation),
                .destination = try cl_ptr.space(.media),
            },
        )
    );
    const known_input_bounds = (
        known_presentation_to_media.topology.input_bounds()
    );

    const guess_presentation_to_media = p_o_map.operators[2][0];
    const guess_input_bounds = (
        guess_presentation_to_media.topology.input_bounds()
    );

    // topology input bounds match
    try expectApproxEqAbs(
        known_input_bounds.start_seconds,
        guess_input_bounds.start_seconds,
        util.EPSILON
    );
    try expectApproxEqAbs(
        known_input_bounds.end_seconds,
        guess_input_bounds.end_seconds,
        util.EPSILON
    );

    // end points match topology
    try expectApproxEqAbs(
        13,
        guess_input_bounds.start_seconds,
        util.EPSILON
    );
    try expectApproxEqAbs(
        21,
        guess_input_bounds.end_seconds,
        util.EPSILON
    );
}

pub fn path_exists(
    fst: treecode.Treecode,
    snd: treecode.Treecode,
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
                    "[{d}] code: {b} hash: {d} adding child space: '{s}.{s}.{d}' with offset: {d}\n",
                    .{
                        index,
                        child_space_code.treecode_array[0],
                        child_space_code.hash(),
                        @tagName(space_ref.item),
                        @tagName(space_ref.label),
                        space_ref.child_index.?,
                        space_ref.previous_child_offset.?,
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
        .media_temporal_bounds = .{
            .start_seconds = start_seconds,
            .end_seconds = end_seconds 
        }
    };

    const topo = try cl.topology();

    try expectApproxEqAbs(
        start_seconds,
        topo.input_bounds().start_seconds,
        util.EPSILON,
    );

    try expectApproxEqAbs(
        end_seconds,
        topo.input_bounds().end_seconds,
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
        .media_temporal_bounds = .{
            .start_seconds = start_seconds,
            .end_seconds = end_seconds 
        }
    };
    try tr.append(.{ .clip = cl });

    const topo =  try tr.topology();

    try expectApproxEqAbs(
        start_seconds,
        topo.input_bounds().start_seconds,
        util.EPSILON,
    );

    try expectApproxEqAbs(
        end_seconds,
        topo.input_bounds().end_seconds,
        util.EPSILON,
    );
}

test "build_topological_map: leak sentinel test - single clip"
{
    const start_seconds:f32 = 1;
    const end_seconds:f32 = 10;

    const cl = Clip {
        .media_temporal_bounds = .{
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
        .media_temporal_bounds = .{
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
        .media_temporal_bounds = .{
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
            .media_temporal_bounds = .{
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
        tr.space(.presentation),
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
        .media_temporal_bounds = .{
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
            .media_temporal_bounds = .{
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
        tr.space(.presentation),
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
            try tr.child_ptr_from_index(t.ind).space(SpaceLabel.presentation)
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

    const cl = Clip{.media_temporal_bounds = range};
    try tr.append(.{ .clip = cl });

    var i:i32 = 0;
    while (i < 10) 
        : (i+=1)
    {
        const cl2 = Clip {.media_temporal_bounds = range};
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
            .source = try tr.space(SpaceLabel.presentation),
            .destination =  try clip.space(SpaceLabel.media)
        }
    );
    defer track_to_clip.deinit(std.testing.allocator);

    // check the bounds
    try expectApproxEqAbs(
        @as(f32, 0),
        track_to_clip.topology.input_bounds().start_seconds,
        util.EPSILON,
    );

    try expectApproxEqAbs(
        end_seconds - start_seconds,
        track_to_clip.topology.input_bounds().end_seconds,
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
        .media_temporal_bounds = .{
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

    const root_presentation_to_clip_media = (
        try map.build_projection_operator(
            std.testing.allocator,
            .{
                .source = try root.space(SpaceLabel.presentation),
                .destination = try clip.space(SpaceLabel.media)
            }
        )
    );

    try expectError(
        time_topology.TimeTopology.ProjectionError.OutOfBounds,
        root_presentation_to_clip_media.project_ordinate(3)
    );

    try expectApproxEqAbs(
        1,
        try root_presentation_to_clip_media.project_ordinate(1),
        util.EPSILON,
    );
}

test "Projection: Track with single clip with identity transform and bounds" 
{
    var tr = Track.init(std.testing.allocator);
    defer tr.deinit();

    const root = ItemPtr{ .track_ptr = &tr };

    const cl = Clip { .media_temporal_bounds = .{ .start_seconds = 0, .end_seconds = 2 } };
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

    const root_presentation_to_clip_media = try map.build_projection_operator(
        std.testing.allocator,
        .{ 
            .source = try root.space(SpaceLabel.presentation),
            .destination = try clip.space(SpaceLabel.media),
        }
    );

    // check the bounds
    try expectApproxEqAbs(
        (cl.media_temporal_bounds orelse interval.ContinuousTimeInterval{}).start_seconds,
        root_presentation_to_clip_media.topology.input_bounds().start_seconds,
        util.EPSILON,
    );

    try expectApproxEqAbs(
        (cl.media_temporal_bounds orelse interval.ContinuousTimeInterval{}).end_seconds,
        root_presentation_to_clip_media.topology.input_bounds().end_seconds,
        util.EPSILON,
    );

    try expectError(
        time_topology.TimeTopology.ProjectionError.OutOfBounds,
        root_presentation_to_clip_media.project_ordinate(3)
    );
}

test "Projection: Track with multiple clips with identity transform and bounds" 
{
    //
    //                          0               3             6
    // track.presentation space       [---------------*-------------)
    // track.intrinsic space    [---------------*-------------)
    // child.clip presentation space  [--------)[-----*---)[-*------)
    //                          0        2 0    1   2 0       2 
    //
    var tr = Track.init(std.testing.allocator);
    defer tr.deinit();
    const track_ptr = ItemPtr{ .track_ptr = &tr };

    const cl = Clip { .media_temporal_bounds = .{ .start_seconds = 0, .end_seconds = 2 } };

    // add three copies
    try tr.append(.{ .clip = cl });
    try tr.append(.{ .clip = cl });
    try tr.append(.{ .clip = cl });

    const TestData = struct {
        index: usize,
        track_ord: f32,
        expected_ord: f32,
        err: bool
    };

    const map = try build_topological_map(
        std.testing.allocator,
        track_ptr,
    );
    defer map.deinit();

    const tests = [_]TestData{
        .{ .index = 1, .track_ord = 3, .expected_ord = 1, .err = false},
        .{ .index = 0, .track_ord = 1, .expected_ord = 1, .err = false },
        .{ .index = 2, .track_ord = 5, .expected_ord = 1, .err = false },
        .{ .index = 0, .track_ord = 7, .expected_ord = 1, .err = true },
    };


    // check that the child transform is correctly built
    {
        const po = try map.build_projection_operator(
            std.testing.allocator,
            .{
                .source = try track_ptr.space(.presentation),
                .destination = (
                    try tr.child_ptr_from_index(2).space(.media)
                ),
            }
        );
        defer po.deinit(std.testing.allocator);

        const b = po.topology.input_bounds();

        try std.testing.expectEqualSlices(
            f32,
            &.{ 4, 6 },
            &.{ b.start_seconds, b.end_seconds },
        );
    }

    const po_map = try projection_map_to_media_from(
        std.testing.allocator,
        map,
        try track_ptr.space(.presentation),
    );
    defer po_map.deinit();

    try expectEqual(
        3,
        po_map.operators.len,
    );

    // 1
    for (po_map.operators, &[_][2]f32{ .{ 0, 2}, .{ 2, 4 }, .{ 4, 6 } })
        |ops, expected|
    {
        const b = (
            ops[0].topology.input_bounds()
        );
        try std.testing.expectEqualSlices(
            f32,
            &expected,
            &.{ b.start_seconds, b.end_seconds },
        );
    }

    try std.testing.expectEqualSlices(
        f32,
        &.{ 0, 2, 4, 6},
        po_map.end_points,
    );


    for (tests, 0..) 
        |t, t_i| 
    {
        const child = tr.child_ptr_from_index(t.index);

        const tr_presentation_to_clip_media = try map.build_projection_operator(
        std.testing.allocator,
            .{
                .source = try track_ptr.space(SpaceLabel.presentation),
                .destination = try child.space(SpaceLabel.media),
            }
        );

        errdefer std.log.err(
            "[{d}] index: {d} track ordinate: {d} expected: {d} error: {any}\n",
            .{t_i, t.index, t.track_ord, t.expected_ord, t.err}
        );
        if (t.err)
        {
            try expectError(
                time_topology.TimeTopology.ProjectionError.OutOfBounds,
                tr_presentation_to_clip_media.project_ordinate(t.track_ord)
            );
        }
        else{
            const result = try tr_presentation_to_clip_media.project_ordinate(t.track_ord);

            try expectApproxEqAbs(result, t.expected_ord, util.EPSILON);
        }
    }

    const clip = tr.child_ptr_from_index(0);

    const root_presentation_to_clip_media = try map.build_projection_operator(
        std.testing.allocator,
        .{ 
            .source = try track_ptr.space(SpaceLabel.presentation),
            .destination = try clip.space(SpaceLabel.media),
        }
    );

    // check the bounds
    try expectApproxEqAbs(
        (cl.media_temporal_bounds orelse interval.ContinuousTimeInterval{}).start_seconds,
        root_presentation_to_clip_media.topology.input_bounds().start_seconds,
        util.EPSILON,
    );

    try expectApproxEqAbs(
        (cl.media_temporal_bounds orelse interval.ContinuousTimeInterval{}).end_seconds,
        root_presentation_to_clip_media.topology.input_bounds().end_seconds,
        util.EPSILON,
    );

    try expectError(
        time_topology.TimeTopology.ProjectionError.OutOfBounds,
        root_presentation_to_clip_media.project_ordinate(3)
    );
}

test "Single Clip Media to presentation Identity transform" 
{
    //
    //              0                 7           10
    // presentation space [-----------------*-----------)
    // media space  [-----------------*-----------)
    //              100               107         110 (seconds)
    //              
    const media_temporal_bounds = interval.ContinuousTimeInterval{
        .start_seconds = 100,
        .end_seconds = 110 
    };

    const cl = Clip { .media_temporal_bounds = media_temporal_bounds };
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

    // presentation->media
    {
        const clip_presentation_to_media = try map.build_projection_operator(
            std.testing.allocator,
            .{
                .source =  try cl_ptr.space(SpaceLabel.presentation),
                .destination = try cl_ptr.space(SpaceLabel.media),
            }
        );

        try expectApproxEqAbs(
            @as(f32, 103),
            try clip_presentation_to_media.project_ordinate(3),
            util.EPSILON,
        );

        try expectApproxEqAbs(
            @as(f32,0),
            clip_presentation_to_media.topology.input_bounds().start_seconds,
            util.EPSILON,
        );

        try expectApproxEqAbs(
            media_temporal_bounds.duration_seconds(),
            clip_presentation_to_media.topology.input_bounds().end_seconds,
            util.EPSILON,
        );
    }

    // media->presentation
    {
        const clip_presentation_to_media = try map.build_projection_operator(
            std.testing.allocator,
            .{
                .source =  try cl_ptr.space(SpaceLabel.media),
                .destination = try cl_ptr.space(SpaceLabel.presentation),
            }
        );

        try expectApproxEqAbs(
            @as(f32, 3),
            try clip_presentation_to_media.project_ordinate(103),
            util.EPSILON,
        );
    }
}

test "Single Clip reverse transform" 
{
    //
    // xform: reverse (linear w/ -1 slope)
    // note: transforms map from the _presentation_ space to the _media_ space
    //
    //              0                 7           10
    // presentation       [-----------------*-----------)
    // (transform)  10                3           0
    // media        [-----------------*-----------)
    //              110               103         100 (seconds)
    //

    const start = curve.ControlPoint{ .time = 0, .value = 10 };
    const end = curve.ControlPoint{ .time = 10, .value = 0 };
    const inv_tx = time_topology.TimeTopology.init_linear_start_end(start, end);

    const media_temporal_bounds:interval.ContinuousTimeInterval = .{
        .start_seconds = 100,
        .end_seconds = 110,
    };

    const cl = Clip { .media_temporal_bounds = media_temporal_bounds, .transform = inv_tx };
    const cl_ptr : ItemPtr = .{ .clip_ptr = &cl};

    const map = try build_topological_map(
        std.testing.allocator,
        cl_ptr,
    );
    defer map.deinit();

    // presentation->media (forward projection)
    {
        const clip_presentation_to_media_topo = try map.build_projection_operator(
            std.testing.allocator,
            .{
                .source =  try cl_ptr.space(SpaceLabel.presentation),
                .destination = try cl_ptr.space(SpaceLabel.media),
            }
        );
        
        try expectApproxEqAbs(
            start.time,
            clip_presentation_to_media_topo.topology.input_bounds().start_seconds,
            util.EPSILON,
        );

        try expectApproxEqAbs(
            end.time,
            clip_presentation_to_media_topo.topology.input_bounds().end_seconds,
            util.EPSILON,
        );

        try expectApproxEqAbs(
            @as(f32, 107),
            try clip_presentation_to_media_topo.project_ordinate(3),
            util.EPSILON,
        );
    }

    // media->presentation (reverse projection)
    {
        const clip_media_to_presentation = try map.build_projection_operator(
            std.testing.allocator,
            .{
                .source =  try cl_ptr.space(SpaceLabel.media),
                .destination = try cl_ptr.space(SpaceLabel.presentation),
            }
        );

        try expectApproxEqAbs(
            @as(f32, 3),
            try clip_media_to_presentation.project_ordinate(107),
            util.EPSILON,
        );
    }
}

test "Single Clip bezier transform" 
{
    //
    // xform: s-curve read from sample curve file
    //        curves map from the presentation space to the intrinsic space for clips
    //
    //              0                             10
    // presentation       [-----------------------------)
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
    const curve_bounds_input = curve_topo.input_bounds();
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

    const media_temporal_bounds:interval.ContinuousTimeInterval = .{
        .start_seconds = 100,
        .end_seconds = 110,
    };
    const cl = Clip {
        .media_temporal_bounds = media_temporal_bounds,
        .transform = curve_topo 
    };
    const cl_ptr : ItemPtr = .{ .clip_ptr = &cl };

    const map = try build_topological_map(
        std.testing.allocator,
        cl_ptr
    );
    defer map.deinit();

    // presentation->media (forward projection)
    {
        const clip_presentation_to_media_proj = (
            try map.build_projection_operator(
                std.testing.allocator,
                .{
                    .source =  try cl_ptr.space(SpaceLabel.presentation),
                    .destination = try cl_ptr.space(SpaceLabel.media),
                }
            )
        );
        defer clip_presentation_to_media_proj.deinit(std.testing.allocator);

        // note that the clips presentation space is the curve's input space
        const input_bounds = (
            clip_presentation_to_media_proj.topology.input_bounds()
        );
        try expectApproxEqAbs(
            curve_bounds_output.start_seconds, 
            input_bounds.start_seconds,
            util.EPSILON
        );
        try expectApproxEqAbs(
            curve_bounds_output.end_seconds, 
            input_bounds.end_seconds,
            util.EPSILON
        );

        // invert it back and check it against the inpout curve bounds
        const clip_media_to_output = (
            try clip_presentation_to_media_proj.topology.inverted(
                std.testing.allocator
            )
        );
        defer clip_media_to_output.deinit(std.testing.allocator);
        const clip_media_to_presentation_input_bounds = (
            clip_media_to_output.input_bounds()
        );
        try expectApproxEqAbs(
            @as(f32, 100),
            clip_media_to_presentation_input_bounds.start_seconds, util.EPSILON
        );
        try expectApproxEqAbs(
            @as(f32, 110),
            clip_media_to_presentation_input_bounds.end_seconds, util.EPSILON
        );

        try std.testing.expect(
            std.meta.activeTag(clip_presentation_to_media_proj.topology) 
            != time_topology.TimeTopology.empty
        );

        // walk over the presentation space of the curve
        const o_s_time = input_bounds.start_seconds;
        const o_e_time = input_bounds.end_seconds;
        var output_time = o_s_time;
        while (output_time < o_e_time) 
            : (output_time += 0.01) 
        {
            // output time -> media time
            const media_time = (
                try clip_presentation_to_media_proj.project_ordinate(output_time)
            );
            const topo = clip_presentation_to_media_proj.topology;
            
            errdefer std.log.err(
        "\nERR1\n  output_time: {d} \n"
                ++ "  topology input_bounds: {any} \n"
                ++ "  topology curve bounds: {any} \n ",
                .{
                    output_time,
                    topo.input_bounds(),
                    topo.bezier_curve.compute_input_bounds(),
                }
            );

            // media time -> output time
            const computed_output_time = (
                try clip_media_to_output.project_ordinate(media_time)
            ); 

            errdefer std.log.err(
                "\nERR\n  output_time: {d} \n"
                ++ "  computed_output_time: {d} \n"
                ++ " media_temporal_bounds: {any}\n"
                ++ "  output_bounds: {any} \n",
                .{
                    output_time,
                    computed_output_time,
                    media_temporal_bounds,
                    input_bounds,
                }
            );

            try expectApproxEqAbs(
                computed_output_time,
                output_time,
                util.EPSILON
            );
        }
    }

    // media->presentation (reverse projection)
    {
        const clip_media_to_presentation = (
            try map.build_projection_operator(
                std.testing.allocator,
                .{
                    .source =  try cl_ptr.space(SpaceLabel.media),
                    .destination = try cl_ptr.space(SpaceLabel.presentation),
                }
            )
        );
        defer clip_media_to_presentation.deinit(std.testing.allocator);

        try expectApproxEqAbs(
            @as(f32, 6.5745),
            try clip_media_to_presentation.project_ordinate(107),
            util.EPSILON,
        );
    }
}

/// top level object
pub const Timeline = struct {
    tracks:Stack,

    discrete_info: struct{
        presentation:  ?sampling.DiscreteDatasourceIndexGenerator = null,
    } = .{},

    pub fn init(
        allocator: std.mem.Allocator
    ) !Timeline
    {
        return .{
            .tracks = Stack.init(allocator),
        };
    }

    pub fn recursively_deinit(self: @This()) void {
        self.tracks.recursively_deinit();
    }

    pub fn topology(
        self: @This()
    ) !time_topology.TimeTopology
    {
        return try self.tracks.topology();
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

    pub fn duration(
        self: @This(),
    ) !f32
    {
        const t = try self.topology();
        return t.input_bounds().duration_seconds();
    }


    pub fn topology(
        self: @This()
    ) !time_topology.TimeTopology 
    {
        // build the bounds
        var bounds: ?interval.ContinuousTimeInterval = null;
        for (self.children.items) 
            |it| 
        {
            const it_bound = (try it.topology()).input_bounds();
            if (bounds) 
                |b| 
            {
                bounds = interval.extend(b, it_bound);
            } else {
                bounds = it_bound;
            }
        }

        if (bounds) 
            |b| 
        {
            return time_topology.TimeTopology.init_affine(
                .{ .bounds = b }
            );
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

test "label_for_node_leaky" 
{
    var tr = Track.init(std.testing.allocator);
    const sr = SpaceReference{
        .label = SpaceLabel.presentation,
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

    try std.testing.expectEqualStrings("track_presentation_1101001", result);
}

test "test spaces list" 
{
    const cl = Clip{};
    const it = ItemPtr{ .clip_ptr = &cl };
    const spaces = try it.spaces(std.testing.allocator);
    defer std.testing.allocator.free(spaces);

    try expectEqual(
       SpaceLabel.presentation,
       spaces[0].label, 
    );
    try expectEqual(
       SpaceLabel.media,
       spaces[1].label, 
    );
    try expectEqual(
       "presentation",
       @tagName(SpaceLabel.presentation),
    );
    try expectEqual(
       "media",
       @tagName(SpaceLabel.media),
    );
}

test "otio projection: track with single clip"
{
    var tr = Track.init(std.testing.allocator);
    defer tr.deinit();

    // media is 9 seconds long and runs at 4 hz.
    const media_source_range = opentime.ContinuousTimeInterval{
        .start_seconds = 1,
        .end_seconds = 10,
    };
    const media_discrete_info = (
        sampling.DiscreteDatasourceIndexGenerator{
            .sample_rate_hz = 4,
            .start_index = 0,
        }
    );

    // construct the clip and add it to the track
    const cl = Clip {
        .media_temporal_bounds = media_source_range,
        .discrete_info = .{
            .media = media_discrete_info 
        },
    };
    try tr.append(.{ .clip = cl });
    const tr_ptr : ItemPtr = .{ .track_ptr = &tr };
    const cl_ptr = tr.child_ptr_from_index(0);

    const map = try build_topological_map(
        std.testing.allocator,
        tr_ptr
    );
    defer map.deinit();

    try map.write_dot_graph(
        std.testing.allocator,
        "/var/tmp/sampling_test.dot"
    );

    const track_to_media = (
        try map.build_projection_operator(
            std.testing.allocator,
            .{
                .source = try tr_ptr.space(SpaceLabel.presentation),
                // does the discrete / continuous need to be disambiguated?
                .destination = try cl_ptr.space(SpaceLabel.media),
            },
        )
    );

    // instantaneous projection tests
    {
        // continuous time projection to the continuous intrinsic space for
        // continuous or interpolated samples
        try expectApproxEqAbs(
            4.5,
            try track_to_media.project_instantaneous_cc(3.5),
            util.EPSILON,
        );

        // for discrete non-interpolated data sources, allow projection to a
        // discrete index space
        try expectEqual(
            // ??? - can't be prescriptive about how data sources are indexed, ie
            // paths to EXR frames or something
            (3 + 1) * 4,
            try track_to_media.project_instantaneous_cd(3),
        );
    }

    // range projection tests
    {
        const test_range_in_track:opentime.ContinuousTimeInterval = .{
            .start_seconds = 3.5,
            .end_seconds = 4.5,
        };

        // continuous
        {
            const result_range_in_media = (
                try track_to_media.project_range_cc(
                    std.testing.allocator,
                    test_range_in_track,
                )
            );
            defer result_range_in_media.deinit(std.testing.allocator);

            const r = try cl.bounds_of(.media);
            const b = result_range_in_media.output_bounds();
            errdefer {
                std.debug.print(
                    "clip trimmed range: [{d}, {d})\n",
                    .{
                        r.start_seconds,
                        r.end_seconds,
                    },
                );
                std.debug.print(
                    "result range: [{d}, {d})\n",
                    .{
                        b.start_seconds,
                        b.end_seconds,
                    },
                );
            }

            try std.testing.expectApproxEqAbs(
                4.5,
                b.start_seconds,
                util.EPSILON,
            );

            try std.testing.expectApproxEqAbs(
                5.5,
                b.end_seconds,
                util.EPSILON,
            );
        }

        // discrete
        {
            //                                   3.5s + 1s
            const expected = [_]usize{ 18, 19, 20, 21 };

            const result_media_indices = try track_to_media.project_range_cd(
                std.testing.allocator,
                test_range_in_track,
            );
            defer std.testing.allocator.free(result_media_indices);

            try std.testing.expectEqualSlices(
                usize,
                &expected,
                result_media_indices,
            );
        }
    }
}

test "otio projection: track with single clip with transform"
{
    var tr = Track.init(std.testing.allocator);
    defer tr.deinit();

    // media is 9 seconds long and runs at 4 hz.
    const media_source_range = opentime.ContinuousTimeInterval{
        .start_seconds = 1,
        .end_seconds = 10,
    };
    const media_discrete_info = (
        sampling.DiscreteDatasourceIndexGenerator{
            .sample_rate_hz = 4,
            .start_index = 0,
        }
    );

    var clip_post_transform_to_intrinsic_transform = (
        time_topology.TimeTopology.init_identity_infinite()
    );
    clip_post_transform_to_intrinsic_transform.affine.transform.scale = 2;

    // construct the clip and add it to the track
    const cl = Clip {
        .media_temporal_bounds = media_source_range,
        .discrete_info = .{
            .media = media_discrete_info 
        },
        .transform = clip_post_transform_to_intrinsic_transform,
    };
    try tr.append(.{ .clip = cl });
    const tr_ptr : ItemPtr = .{ .track_ptr = &tr };
    const cl_ptr = tr.child_ptr_from_index(0);

    const map = try build_topological_map(
        std.testing.allocator,
        tr_ptr
    );
    defer map.deinit();

    try map.write_dot_graph(
        std.testing.allocator,
        "/var/tmp/sampling_test.dot"
    );

    const track_to_media = (
        try map.build_projection_operator(
            std.testing.allocator,
            .{
                .source = try tr_ptr.space(SpaceLabel.presentation),
                // does the discrete / continuous need to be disambiguated?
                .destination = try cl_ptr.space(SpaceLabel.media),
            },
        )
    );

    // instantaneous projection tests
    {
        // continuous time projection to the continuous intrinsic space for
        // continuous or interpolated samples
        try expectApproxEqAbs(
            // (3.5*2 + 1),
            8,
            try track_to_media.project_instantaneous_cc(3.5),
            util.EPSILON,
        );

        // for discrete non-interpolated data sources, allow projection to a
        // discrete index space
        try expectEqual(
            // ??? - can't be prescriptive about how data sources are indexed, ie
            // paths to EXR frames or something
            (3*2 + 1) * 4,
            try track_to_media.project_instantaneous_cd(3),
        );
    }

    // range projection tests
    {
        const test_range_in_track:opentime.ContinuousTimeInterval = .{
            .start_seconds = 3.5,
            .end_seconds = 4.5,
        };

        // continuous
        {
            const result_range_in_media = (
                try track_to_media.project_range_cc(
                    std.testing.allocator,
                    test_range_in_track,
                )
            );
            defer result_range_in_media.deinit(std.testing.allocator);

            const r = try cl.bounds_of(.media);
            const b = result_range_in_media.output_bounds();
            errdefer {
                std.debug.print(
                    "clip trimmed range: [{d}, {d})\n",
                    .{
                        r.start_seconds,
                        r.end_seconds,
                    },
                );
                std.debug.print(
                    "result range: [{d}, {d})\n",
                    .{
                        b.start_seconds,
                        b.end_seconds,
                    },
                );
            }

            try std.testing.expectApproxEqAbs(
                8,
                b.start_seconds,
                util.EPSILON,
            );

            try std.testing.expectApproxEqAbs(
                // (4.5 * 2 + 1)
                10,
                b.end_seconds,
                util.EPSILON,
            );
        }

        // discrete
        {
            //                                   (3.5s*2 + 1s)*4
            const expected = [_]usize{ 
                32, 33, 34, 35, 36, 37, 38, 39 
            };

            const result_media_indices = try track_to_media.project_range_cd(
                std.testing.allocator,
                test_range_in_track,
            );
            defer std.testing.allocator.free(result_media_indices);

            try std.testing.expectEqualSlices(
                usize,
                &expected,
                result_media_indices,
            );
        }
    }
}

/// iterator that walks over the graph, returning the node at each step
const TreenodeWalkingIterator = struct{
    const Node = struct {
        space: SpaceReference,
        code: treecode.Treecode 
    };

    stack: std.ArrayList(Node),
    maybe_current: ?Node,
    maybe_previous: ?Node,
    map: *const TopologicalMap,
    allocator: std.mem.Allocator,

    pub fn init(
        allocator: std.mem.Allocator,
        map: *const TopologicalMap,
    ) !TreenodeWalkingIterator
    {
        var result = .{
            .stack = std.ArrayList(Node).init(allocator),
            .maybe_current = null,
            .maybe_previous = null,
            .map = map,
            .allocator = allocator,
        };
        try result.stack.append(
            .{
                .space = map.root(),
                .code = try treecode.Treecode.init_word(
                    allocator,
                    0b1,
                )
            }
        );

        return result;
    }

    pub fn init_at(
        allocator: std.mem.Allocator,
        map: *const TopologicalMap,
        /// a source in the map to start the map from
        source: SpaceReference,
    ) !TreenodeWalkingIterator
    {
        var result = TreenodeWalkingIterator{
            .stack = std.ArrayList(Node).init(allocator),
            .maybe_current = null,
            .maybe_previous = null,
            .map = map,
            .allocator = allocator,
        };

        const start_code = (
            map.map_space_to_code.get(source) 
            orelse return error.NotInMapError
        );

        try result.stack.append(
            .{
                .space = source,
                .code = try start_code.clone(),
            }
        );

        return result;
    }

    pub fn deinit(
        self: *@This()
    ) void
    {
        if (self.maybe_previous)
            |n|
        {
            n.code.deinit();
        }
        if (self.maybe_current)
            |n|
        {
            n.code.deinit();
        }
        for (self.stack.items)
            |n|
        {
            n.code.deinit();
        }
        self.stack.deinit();
    }

    pub fn next(
        self: *@This()
    ) !bool
    {
        if (self.stack.items.len == 0) {
            return false;
        }

        if (self.maybe_previous)
            |prev|
        {
            prev.code.deinit();
        }
        self.maybe_previous = self.maybe_current;

        self.maybe_current = self.stack.pop();
        const current = self.maybe_current.?;

        for (0..2)
            |next_step|
        {
            var next_code = try current.code.clone();
            try next_code.append(@intCast(next_step));

            if (self.map.map_code_to_space.get(next_code))
                |next_node|
            {
                try self.stack.append(
                    .{
                        .space = next_node,
                        .code = next_code,
                    }
                );
            }
            else {
                next_code.deinit();
            }
        }

        return self.maybe_current != null;
    }
};

test "TestWalkingIterator: clip"
{
    // media is 9 seconds long and runs at 4 hz.
    const media_source_range = opentime.ContinuousTimeInterval{
        .start_seconds = 1,
        .end_seconds = 10,
    };

    const cl = Clip {
        .media_temporal_bounds = media_source_range,
    };
    const cl_ptr = ItemPtr{ .clip_ptr = &cl };

    const map = try build_topological_map(
        std.testing.allocator,
        cl_ptr,
    );
    defer map.deinit();

    try map.write_dot_graph(std.testing.allocator, "/var/tmp/walk.dot");

    var node_iter = try TreenodeWalkingIterator.init(
        std.testing.allocator,
        &map,
    );
    defer node_iter.deinit();

    var count:usize = 0;
    while (try node_iter.next())
    {
        count += 1;
    }

    // 5: clip presentation, clip media
    try expectEqual(2, count);
}

test "TestWalkingIterator: track with clip"
{
    var tr = Track.init(std.testing.allocator);
    defer tr.deinit();

    // media is 9 seconds long and runs at 4 hz.
    const media_source_range = opentime.ContinuousTimeInterval{
        .start_seconds = 1,
        .end_seconds = 10,
    };

    // construct the clip and add it to the track
    const cl = Clip {
        .media_temporal_bounds = media_source_range,
    };
    try tr.append(.{ .clip = cl });
    const tr_ptr : ItemPtr = .{ .track_ptr = &tr };
    // const cl_ptr = tr.child_ptr_from_index(0);

    const map = try build_topological_map(
        std.testing.allocator,
        tr_ptr
    );
    defer map.deinit();

    try map.write_dot_graph(std.testing.allocator, "/var/tmp/walk.dot");

    var count:usize = 0;

    // from the top
    {
        var node_iter = try TreenodeWalkingIterator.init(
            std.testing.allocator,
            &map,
        );
        defer node_iter.deinit();

        while (try node_iter.next())
        {
            count += 1;
        }

        // 5: track presentation, input, child, clip presentation, clip media
        try expectEqual(5, count);
    }

    // from the clip
    {
        const cl_ptr = tr.child_ptr_from_index(0);

        var node_iter = try TreenodeWalkingIterator.init_at(
            std.testing.allocator,
            &map,
            try cl_ptr.space(.presentation),
        );
        defer node_iter.deinit();

        count = 0;
        while (try node_iter.next())
        {
            count += 1;
        }

        // 2: clip presentation, clip media
        try expectEqual(2, count);
    }
}

