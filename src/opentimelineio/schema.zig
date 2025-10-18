const std = @import("std");

const opentime = @import("opentime");
const sampling = @import("sampling");
const string = @import("string_stuff");
const topology_m = @import("topology");
const curve = @import("curve");

const references = @import("references.zig");
const test_data = @import("test_structures.zig");

/// a reference that points at some reference via a string address
pub const ExternalReference = struct {
    target_uri : []const u8,
};

/// a procedural signal
pub const SignalReference = struct {
    signal_generator: sampling.SignalGenerator,
};

/// an opaque reference
pub const EmptyReference = struct {
};

/// information about the media that this clip is cutting into the timeline
pub const MediaDataReference = union(enum) {
    external: ExternalReference,
    signal: SignalReference,
    empty: EmptyReference,

    pub const EMPTY_REF = MediaDataReference{
        .empty = .{} 
    };

};

pub const MediaReference = struct {
    ref: MediaDataReference = .EMPTY_REF,

    /// bounds of the media space continuous time
    bounds_s: ?opentime.ContinuousInterval = null,
    // @TODO: should there also be a bounds in sample index space?  Or one or
    //        the other?

    discrete_info: ?sampling.SampleIndexGenerator = null,
    // should be part of the transform?
    interpolating: bool = false,
};

/// clip with an implied media reference
pub const Clip = struct {
    /// identifier name
    name: ?string.latin_s8 = null,

    /// a trim on the media space, in the media coordinate system
    bounds_s: ?opentime.ContinuousInterval = null,

    /// Information about the media this clip cuts into the track
    media: MediaReference = .{},

    parameters: ?ParameterMap = null,

    pub const internal_spaces: []const references.SpaceLabel = (
        &.{ .presentation, .media }
    );

    const Domain = enum {
        time,
        picture,
        audio,
        metadata,
    };
    pub const ParameterVarying = struct {
        domain: Domain,
        mapping: topology_m.Topology,

        pub fn parameter(
            self: *const @This()
        ) Parameter
        {
            return .{
                .value = self,
            };
        }
    };
    pub const Parameter = union(enum) {
        dictionary: *const ParameterMap,
        value: *const ParameterVarying,
    };
    pub const ParameterMap = std.StringHashMap(Parameter);

    pub fn to_param(m: *ParameterMap) Parameter {
        return .{
            .dictionary = m,
        };
    }

    /// copy values from argument and allocate as necessary
    pub fn init(
        allocator: std.mem.Allocator,
        copy_from: Clip,
    ) !Clip
    {
        var result = copy_from;
        
        if (copy_from.name)
            |n|
        {
            result.name = try allocator.dupe(u8, n);
        }
        if (copy_from.parameters)
            |params|
        {
            result.parameters = try params.clone();
        } else {
            result.parameters = ParameterMap.init(allocator);
        }

        return result;
    }

    /// compute the bounds of the specified target space
    pub fn bounds_of(
        self: @This(),
        _: std.mem.Allocator,
        target_space: references.SpaceLabel,
    ) !opentime.ContinuousInterval 
    {
        const maybe_bounds_s = (
            self.bounds_s orelse self.media.bounds_s
        );

        if (maybe_bounds_s)
            |bounds|
        {
            return switch (target_space) {
                .presentation, .media => bounds,
                else => error.UnsupportedSpaceError,
            };
        }

        return error.NotImplementedFetchTopology;

    }

    /// build a topology that maps from the presentation space to the media
    /// space of the clip
    pub fn topology(
        self: @This(),
        allocator: std.mem.Allocator,
    ) !topology_m.Topology 
    {
        if (self.bounds_s) 
            |range| 
        {
            const media_bounds = (
                try topology_m.Topology.init_identity(
                    allocator,
                    range
                )
            );

            return media_bounds;
        } 
        else 
        {
            return error.NotImplementedFetchTopology;
        }
    }

    pub fn destroy(
        self: *@This(),
        allocator: std.mem.Allocator,
    ) void
    {
        if (self.name)
            |n|
        {
            allocator.free(n);
        }
    }

    /// Build a reference to this Clip
    pub fn reference(
        self: *@This(),
    ) references.ComposedValueRef
    {
        return .{ .clip = self };
    }
};

/// represents a space in the timeline without media
pub const Gap = struct {
    name: ?string.latin_s8 = null,
    duration_seconds: opentime.Ordinate,

    pub const internal_spaces: []const references.SpaceLabel = (
        &.{ .presentation, }
    );

    pub fn topology(
        self: @This(),
        allocator: std.mem.Allocator,
    ) !topology_m.Topology 
    {
        return try topology_m.Topology.init_identity(
            allocator,
            .{
                .start = opentime.Ordinate.ZERO,
                .end = self.duration_seconds 
            },
        );
    }
};

/// a warp is an additional nonlinear transformation between the warp.parent
/// and and warp.child.presentation spaces.
pub const Warp = struct {
    name: ?string.latin_s8 = null,
    child: references.ComposedValueRef,
    transform: topology_m.Topology,
    interpolating: bool = false,

    pub const internal_spaces: []const references.SpaceLabel = (
        &.{ .presentation }
    );

    pub fn reference(
        self: *@This(),
    ) references.ComposedValueRef
    {
        return .{ .warp = self };
    }
};

/// a container in which each contained item is right-met over time
pub const Track = struct {
    name: ?string.latin_s8 = null,
    children: []references.ComposedValueRef = &.{},

    pub const internal_spaces: []const references.SpaceLabel = (
        &.{ .presentation, .intrinsic }
    );

    pub const EMPTY = Track{
        .name = null,
        .children = &.{},
    };

    pub fn recursively_deinit(
        self: *@This(),
        allocator: std.mem.Allocator,
    ) void 
    {
        for (self.children)
            |*c|
        {
            c.recursively_deinit(allocator);
        }

        self.deinit(allocator);
    }

    pub fn deinit(
        self: *@This(),
        allocator: std.mem.Allocator,
    ) void 
    {
        if (self.name)
            |n|
        {
            allocator.free(n);
            self.name = null;
        }
        allocator.free(self.children);
    }

    /// construct the topology mapping the output to the intrinsic space
    pub fn topology(
        self: @This(),
        allocator: std.mem.Allocator,
    ) !topology_m.Topology 
    {
        // build the maybe_bounds
        var maybe_bounds: ?opentime.ContinuousInterval = null;
        for (self.children) 
            |it| 
        {
            const topo = try it.topology(allocator);
            defer topo.deinit(allocator);
            const it_bound = (topo).input_bounds();
            if (maybe_bounds) 
                |b| 
            {
                maybe_bounds = opentime.interval.extend(b, it_bound);
            } else {
                maybe_bounds = it_bound;
            }
        }

        // unpack the optional
        const result_bound:opentime.ContinuousInterval = (
            maybe_bounds orelse opentime.ContinuousInterval.ZERO
        );

        return try topology_m.Topology.init_identity(
            allocator,
            result_bound,
        );
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
        allocator: std.mem.Allocator,
        // @TODO: this is super confusing for what it does and should be
        //        renamed
        child_space_reference: references.SpaceReference,
    ) !topology_m.Topology 
    {
        // [child 1][child 2]
        const child_index = (
            child_space_reference.child_index 
            orelse return error.NoChildIndexOnChildSpaceReference
        );

        // XXX should probably check the index before calling this and call
        //     this with index - 1 rather than have it do the offset here.
        const child = self.children[child_index - 1];
        const child_range = try child.bounds_of(
            allocator,
            .media
        );
        const child_duration = child_range.duration();

        // the transform to the next child space, compensates for this duration
        return try topology_m.Topology.init_affine(
            allocator,
            .{
                .input_bounds_val = .{
                    .start = child_duration,
                    .end = opentime.Ordinate.INF,
                },
                .input_to_output_xform = .{
                    .offset = child_duration.neg(),
                    .scale = opentime.Ordinate.ONE,
                }
            }
        );
    }

    pub fn reference(
        self: *@This(),
    ) references.ComposedValueRef
    {
        return .{ .track = self };
    }
};

/// children of a stack are simultaneous in time
pub const Stack = struct {
    name: ?string.latin_s8 = null,
    children: []references.ComposedValueRef = &.{},

    pub const internal_spaces: []const references.SpaceLabel = (
        &.{ .presentation, .intrinsic }
    );

    pub fn deinit(
        self: *@This(),
        allocator: std.mem.Allocator,
    ) void 
    {
        if (self.name)
            |n|
        {
            allocator.free(n);
            self.name = null;
        }
        allocator.free(self.children);
    }

    pub fn recursively_deinit(
        self: *@This(),
        allocator: std.mem.Allocator,
    ) void 
    {
        for (self.children)
            |*c|
        {
            c.recursively_deinit(allocator);
        }

        self.deinit(allocator);
    }

    pub fn topology(
        self: @This(),
        allocator: std.mem.Allocator,
    ) !topology_m.Topology 
    {
        // build the bounds
        var bounds: ?opentime.ContinuousInterval = null;
        for (self.children) 
            |it| 
        {
            const it_bound = (
                (try it.topology(allocator)).input_bounds()
            );
            if (bounds) 
                |b| 
            {
                bounds = opentime.interval.extend(b, it_bound);
            } else {
                bounds = it_bound;
            }
        }

        if (bounds) 
            |b| 
        {
            return try topology_m.Topology.init_affine(
                allocator,
                .{ 
                    .input_bounds_val = b,
                    .input_to_output_xform = .IDENTITY,
                }
            );
        } else {
            return .EMPTY;
        }
    }

    pub fn reference(
        self: *@This(),
    ) references.ComposedValueRef
    {
        return .{ .stack = self };
    }
};

/// top level object
pub const Timeline = struct {
    name: ?string.latin_s8 = null,
    tracks:Stack = .{},

    /// currently there is a single discrete_info struct for the "presentation
    /// space" - this should probably be broken down by domain, and then by
    /// target space
    ///
    ///currently organized by target space / domain
    time_spaces: struct{
        presentation: struct{
            picture: ?sampling.SampleIndexGenerator
            // picture: ?sampling.TimeSampleIndexGenerator(
                         // sampling.DiscreteTimeSampleSpec(24),
                         // sampling.ImageSampleSpec(.{1024, 768}, .rec709)
            = null,
            // audio: ?sampling.TimeSampleIndexGenerator(
            audio: ?sampling.SampleIndexGenerator
                // sampling.DiscreteTimeSampleSpec(192000),
                // sampling.AudioSampleSpec(f32, .normalized, .aifc),
            = null,
        } = .{},
    } = .{},

    ///
    discrete_info: struct{
        presentation:  ?sampling.SampleIndexGenerator = null,
    } = .{},

    pub const internal_spaces: []const references.SpaceLabel = (
        &.{ .presentation, .intrinsic }
    );

    pub fn recursively_deinit(
        self: *@This(),
        allocator: std.mem.Allocator,
    ) void 
    {
        if (self.name)
            |n|
        {
            allocator.free(n);
            self.name = null;
        }
        self.tracks.recursively_deinit(allocator);
    }

    pub fn topology(
        self: @This(),
        allocator: std.mem.Allocator,
    ) !topology_m.Topology
    {
        return try self.tracks.topology(allocator);
    }

    pub fn reference(
        self: *@This(),
    ) references.ComposedValueRef
    {
        return .{ .timeline = self };
    }
};

test "clip topology construction" 
{
    const allocator = std.testing.allocator;

    var cl = Clip {
        .bounds_s = test_data.T_INT_1_TO_9,
    };

    const topo = try cl.topology(allocator);
    defer topo.deinit(allocator);

    try opentime.expectOrdinateEqual(
        test_data.T_INT_1_TO_9.start,
        topo.input_bounds().start,
    );

    try opentime.expectOrdinateEqual(
        test_data.T_INT_1_TO_9.end,
        topo.input_bounds().end,
    );
}

test "track topology construction" 
{
    const allocator = std.testing.allocator;

    var cl = Clip {
        .bounds_s = test_data.T_INT_1_TO_9, 
    };

    var tr_children = [_]references.ComposedValueRef{
        references.ComposedValueRef.init(&cl)
    };
    var tr: Track = .{
        .children = &tr_children,
    };

    const topo = try tr.topology(allocator);
    defer topo.deinit(allocator);

    try opentime.expectOrdinateEqual(
        test_data.T_INT_1_TO_9.start,
        topo.input_bounds().start,
    );

    try opentime.expectOrdinateEqual(
        test_data.T_INT_1_TO_9.end,
        topo.input_bounds().end,
    );
}

test "Clip: Animated Parameter example"
{
    const root_allocator = std.testing.allocator;

    var arena = std.heap.ArenaAllocator.init(root_allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    const media_source_range = test_data.T_INT_1_TO_9;
    const media_discrete_info = (
        sampling.SampleIndexGenerator{
            .sample_rate_hz = .{ .Int = 4 },
            .start_index = 0,
        }
    );

    var cl = try Clip.init(
        allocator,
        .{ 
            .media = .{
                .bounds_s = media_source_range,
                .discrete_info = media_discrete_info 
            },
        }
    );
    defer cl.destroy(allocator);

    const focus_distance = (
        Clip.ParameterVarying{
            .domain = .time,
            .mapping = try topology_m.Topology.init_from_linear(
                allocator,
                try curve.Linear.init(
                    allocator,
                    &.{ 
                        curve.ControlPoint.init(.{ .in = 0, .out = 1 }),
                        curve.ControlPoint.init(.{ .in = 1, .out = 1.25 }),
                        curve.ControlPoint.init(.{ .in = 5, .out = 8}),
                        curve.ControlPoint.init(.{ .in = 8, .out = 10}),
                    },
                )
            ),
        }
    ).parameter();

    var lens_data = Clip.ParameterMap.init(allocator);
    try lens_data.put("focus_distance", focus_distance);

    const param = Clip.to_param(&lens_data);
    try cl.parameters.?.put( "lens",param );
}
