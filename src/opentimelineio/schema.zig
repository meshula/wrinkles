const std = @import("std");

const opentime = @import("opentime");
const sampling = @import("sampling");
const string = @import("string_stuff");
const topology_m = @import("topology");
const curve = @import("curve");
const domain = @import("domain.zig");

const references = @import("references.zig");
const test_data = @import("test_structures.zig");

// Schema Iteration Notes
// ----------------------
//
// To start with embededd spaces are explicit and fixed
// * On everything but Clips, the spaces for parameters and bounds and so on
//   is the presentation space
// * On Clips the embedding space is the media space
// * Clips need to have room for multiple media references
// * Serialized bounds can be discrete or continuous - in-memory bounds are
//   strictly continuous, but can be set either discrete or continuous
// * Sequences have a singular domain.  This eliminates fuzzyness like things
//   that don't have the domain are gaps, etc.  (hopefully)
// * Stacks (eventually) probably want a compositing rule per domain, but for
//   now lets not worry about that
// * Discrete info is currently only present on the top level timeline and on
//   root clips (is there a better name than "Discrete Info"?
//   "DiscreteParameterization"?  The sampling library calls this a
//   `SampleIndexGenerator`.  Maybe thats better?

/// Indicates whether samples should be interpolated when the parameter space
/// (usually time) is warped.  Examples include audio (interpolated) vs picture
/// (snapped, typically)
const ResamplingBehavior = enum {
    interpolate,
    snap,
    default_from_domain,
};

/// a reference that points at some reference via a string address
pub const ExternalReference = struct {
    target_uri : []const u8,
};

/// a procedural signal
pub const SignalReference = struct {
    signal_generator: sampling.SignalGenerator,
};

/// an opaque reference
pub const EmptyReference = void;

/// The way to get to the media
pub const MediaDataReference = union(enum) {
    /// Usually a file or URI somewhere
    external: ExternalReference,
    /// A Procedurally defined signal (A tone, a color, etc.)
    signal: SignalReference,
    /// An opaque unknown reference
    empty: EmptyReference,

    pub const EMPTY_REF = MediaDataReference{
        .empty = {},
    };
};

/// Refers to a piece of media or signal that is being cut into a composition
pub const MediaReference = struct {
    /// the specific kind of media reference.  By default an opaque reference.
    ref: MediaDataReference,

    /// bounds of the media space continuous time, the interval of media time
    /// in which the media is defined
    maybe_bounds_s: ?opentime.ContinuousInterval,

    /// Media domain for this reference
    domain: domain.Domain,

    /// If the media has a discrete partition
    maybe_discrete_partition: ?sampling.SampleIndexGenerator = null,

    /// Media that is interpolating can be resampled when under time warps.
    interpolating: ResamplingBehavior = .default_from_domain,

    pub const null_picture: MediaReference = .{
        .ref = .EMPTY_REF,
        .maybe_bounds_s = null,
        .domain = .picture,
    };
};

/// clip with an implied media reference
pub const Clip = struct {
    /// identifier name
    maybe_name: ?string.latin_s8 = null,

    /// a trim on the media space, in the media coordinate system
    maybe_bounds_s: ?opentime.ContinuousInterval = null,

    /// Information about the media this clip cuts into the track
    media: MediaReference,

    maybe_parameters: ?ParameterMap = null,

    pub const internal_spaces: []const references.SpaceLabel = &.{
        .presentation,
        .media,
    };

    pub const null_picture: Clip = .{
        .media = .null_picture,
    };

    pub const ParameterVarying = struct {
        domain: domain.Domain,
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
    pub const ParameterMap = std.StringHashMapUnmanaged(Parameter);

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
        
        if (copy_from.maybe_name)
            |n|
        {
            result.maybe_name = try allocator.dupe(u8, n);
        }
        if (copy_from.maybe_parameters)
            |params|
        {
            result.maybe_parameters = try params.clone(allocator);
        } else {
            result.maybe_parameters = .empty;
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
            self.maybe_bounds_s orelse self.media.maybe_bounds_s
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
        const media_bounds = (
            self.maybe_bounds_s 
            orelse self.media.maybe_bounds_s 
            orelse return error.NotImplementedFetchTopology
        );

        const presentation_to_media_xform = (
            opentime.AffineTransform1D{
                .offset = media_bounds.start,
                .scale = opentime.Ordinate.ONE,
            }
        );

        const presentation_bounds = (
            opentime.ContinuousInterval{
                .start = opentime.Ordinate.ZERO,
                .end = media_bounds.duration()
            }
        );

        const presentation_to_media_topo = (
            try topology_m.Topology.init_affine(
                allocator,
                topology_m.MappingAffine {
                    .input_to_output_xform = presentation_to_media_xform,
                    .input_bounds_val = presentation_bounds,
                }
                ,
            )
        );

        return presentation_to_media_topo;
    }

    pub fn destroy(
        self: *@This(),
        allocator: std.mem.Allocator,
    ) void
    {
        if (self.maybe_name)
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

test "Clip: spaces list" 
{
    var cl: Clip = .null_picture;

    try std.testing.expectEqualSlices(
        references.SpaceLabel,
        &.{ .presentation, .media },
        cl.reference().spaces()
    );
}


/// represents a space in the timeline without media
pub const Gap = struct {
    maybe_name: ?string.latin_s8 = null,
    duration_seconds: opentime.Ordinate,

    pub const internal_spaces: []const references.SpaceLabel = (
        &.{ .presentation, .intrinsic }
    );

    pub fn topology(
        self: @This(),
        allocator: std.mem.Allocator,
    ) !topology_m.Topology 
    {
        const result = try topology_m.Topology.init_identity(
            allocator,
            .{
                .start = opentime.Ordinate.ZERO,
                .end = self.duration_seconds 
            },
        );
        return result;
    }
};

/// A transition is a specific object that associates a text "transition type"
/// with a stack of children
pub const Transition = struct {
    container: Stack,
    maybe_name: ?string.latin_s8,
    // for now, string tag the type (IE "crossdissolve")
    kind: string.latin_s8,
    range: ?opentime.ContinuousInterval,

    pub const internal_spaces: []const references.SpaceLabel = (
        &.{ .presentation }
    );

    pub fn reference(
        self: *@This(),
    ) references.ComposedValueRef
    {
        return .{ .transition = self };
    }

    pub fn topology(
        self: @This(),
        allocator: std.mem.Allocator,
    ) !topology_m.Topology
    {
        return self.container.topology(allocator);
    }

    pub fn recursively_deinit(
        self: *@This(),
        allocator: std.mem.Allocator,
    ) void 
    {
        self.container.recursively_deinit(allocator);
        if (self.maybe_name)
            |n|
        {
            allocator.free(n);
            self.maybe_name = null;
        }
        allocator.free(self.kind);
    }
};

/// a warp is an additional nonlinear transformation between the warp.parent
/// and and warp.child.presentation spaces.
pub const Warp = struct {
    maybe_name: ?string.latin_s8 = null,
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

    /// Presentation space of warp -> presentation space of child
    pub fn topology(
        self: @This(),
        allocator: std.mem.Allocator,
    ) !topology_m.Topology
    {
        const child_bounds = try self.child.bounds_of(
            allocator,
            .presentation,
        );

        const child_bounds_topo = try topology_m.Topology.init_affine(
            allocator,
            .{
                .input_bounds_val = .{
                    .start = .ZERO,
                    .end = child_bounds.duration(),
                },
                .input_to_output_xform = .{
                    .offset = child_bounds.start,
                    .scale = .ONE,
                },
            },
        );
        defer child_bounds_topo.deinit(allocator);

        const warped_to_child = try topology_m.join(
            allocator,
            .{
                .a2b = self.transform,
                .b2c = child_bounds_topo,
            }
        );
        defer warped_to_child.deinit(allocator);

        const warped_range = warped_to_child.input_bounds();

        const presentation_to_warped = try topology_m.Topology.init_affine(
            allocator,
            .{ 
                .input_bounds_val = .{
                    .start = .ZERO,
                    .end = warped_range.duration(),
                },
                .input_to_output_xform = .{
                    .offset = warped_range.start,
                    .scale = .ONE,
                },
            }
        );
        defer presentation_to_warped.deinit(allocator);

        return topology_m.join(
            allocator,
            .{
                .a2b = presentation_to_warped,
                .b2c = warped_to_child,
            },
        );
    }
};

/// a container in which each contained item is right-met over time
pub const Track = struct {
    maybe_name: ?string.latin_s8 = null,
    children: []references.ComposedValueRef = &.{},

    pub const internal_spaces: []const references.SpaceLabel = (
        &.{ .presentation, .intrinsic }
    );

    pub const empty = Track{
        .maybe_name = null,
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
        if (self.maybe_name)
            |n|
        {
            allocator.free(n);
            self.maybe_name = null;
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
    ///           track_child 0
    ///           |     \
    /// child 0.presentation   track_child 1
    ///                   |   \
    ///       child.1.presentation   track_child 2
    ///                         ...
    ///
    ///  if called on child space child 1, will make a transform to child
    ///  space 1 from child space 0
    /// 
    pub fn transform_to_next_child(
        self: @This(),
        allocator: std.mem.Allocator,
        current_child_index: usize,
    ) !topology_m.Topology 
    {
        // offset the next child by the duration of the previous child
        // presentation space (everything has a presentation space)
        const current_child_pres_range = (
            try self.children[current_child_index].bounds_of(
                allocator,
                .presentation,
            )
        );

        std.debug.assert(current_child_pres_range.is_infinite() == false);
        const current_child_duration = (
            current_child_pres_range.duration()
        );

        // the transform to the next child space, compensates for this duration
        return try topology_m.Topology.init_affine(
            allocator,
            .{
                .input_bounds_val = .{
                    .start = current_child_duration,
                    .end = opentime.Ordinate.INF,
                },
                .input_to_output_xform = .{
                    .offset = current_child_duration.neg(),
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
    maybe_name: ?string.latin_s8 = null,
    children: []references.ComposedValueRef = &.{},

    pub const internal_spaces: []const references.SpaceLabel = (
        &.{ .presentation, .intrinsic }
    );

    pub fn deinit(
        self: *@This(),
        allocator: std.mem.Allocator,
    ) void 
    {
        if (self.maybe_name)
            |n|
        {
            allocator.free(n);
            self.maybe_name = null;
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

/// A mapping of domain to a corresponding discrete partition for that domain
pub const DiscretePartitionDomainMap = struct {
    picture: ?sampling.SampleIndexGenerator,
    audio: ?sampling.SampleIndexGenerator,
    /// Non-picture/audio domain discretizations can be stored here, ie:
    ///   "Gyroscope"
    ///   "Fireworks"
    other: ?std.StringHashMapUnmanaged(sampling.SampleIndexGenerator) = null,

    /// no discrete partitions for any domains
    pub const no_discretizations : DiscretePartitionDomainMap = .{
        .picture = null,
        .audio = null,
        .other = null,
    };
};

/// top level object
///
/// Contains a stack called "tracks".
/// Also allows for a discretization of the "result" space for your timeline,
/// IE if it is intended for 24fps picture and 192khz audio, that is configured
/// on the timeline so that regardless of what the discretizations for the
/// various child objects might be, the output is fixed at that description.
pub const Timeline = struct {
    maybe_name: ?string.latin_s8 = null,
    tracks:Stack = .{},

    discrete_space_partitions: struct {
        presentation: DiscretePartitionDomainMap = .no_discretizations,
    } = .{},

    pub const internal_spaces: []const references.SpaceLabel = &.{
        .presentation,
        .intrinsic,
    };

    pub fn recursively_deinit(
        self: *@This(),
        allocator: std.mem.Allocator,
    ) void 
    {
        if (self.maybe_name)
            |n|
        {
            allocator.free(n);
            self.maybe_name = null;
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

    // setting the bounds on the clip
    {
        var cl = Clip {
            .media = .null_picture,
            .maybe_bounds_s = test_data.T_INT_1_TO_9,
        };

        const topo = try cl.topology(allocator);
        defer topo.deinit(allocator);

        const expected_input_bounds = (
            opentime.ContinuousInterval{
                .start = .ZERO,
                .end = test_data.T_INT_1_TO_9.duration(),
            }
        );

        try std.testing.expectEqual(
            expected_input_bounds,
            topo.input_bounds(),
        );

        try std.testing.expectEqual(
            test_data.T_INT_1_TO_9,
            topo.output_bounds(),
        );
    }

    // setting the bounds on the media
    {
        var cl = Clip {
            .media = .{
                .ref = .empty,
                .maybe_bounds_s = test_data.T_INT_1_TO_9,
                .domain = .picture,
                .interpolating = .snap,
            },
        };

        const topo = try cl.topology(allocator);
        defer topo.deinit(allocator);

        const expected_input_bounds = (
            opentime.ContinuousInterval{
                .start = .ZERO,
                .end = test_data.T_INT_1_TO_9.duration(),
            }
        );

        try std.testing.expectEqual(
            expected_input_bounds,
            topo.input_bounds(),
        );

        try std.testing.expectEqual(
            test_data.T_INT_1_TO_9,
            topo.output_bounds(),
        );
    }
}

test "track topology construction" 
{
    const allocator = std.testing.allocator;

    var cl = Clip {
        .media = .null_picture,
        .maybe_bounds_s = test_data.T_INT_1_TO_9, 
    };

    var tr_children = [_]references.ComposedValueRef{
        cl.reference()
    };
    var tr: Track = .{
        .children = &tr_children,
    };

    const topo = try tr.topology(allocator);
    defer topo.deinit(allocator);

    const expected_clip_input_bounds = (
        opentime.ContinuousInterval{
            .start = .ZERO,
            .end = test_data.T_INT_1_TO_9.duration(),
        }
    );

        try std.testing.expectEqual(
            expected_clip_input_bounds,
            topo.input_bounds(),
        );

        try std.testing.expectEqual(
            expected_clip_input_bounds,
            topo.output_bounds(),
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
                .ref = .empty,
                .domain = .picture,
                .interpolating = .snap,
                .maybe_bounds_s = media_source_range,
                .maybe_discrete_partition = media_discrete_info 
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

    var lens_data: Clip.ParameterMap = .empty;
    try lens_data.put(
        allocator,
        "focus_distance",
        focus_distance,
    );

    const param = Clip.to_param(&lens_data);
    try cl.maybe_parameters.?.put(
        allocator,
        "lens",
        param,
    );
}

test "warp topology"
{
    const allocator = std.testing.allocator;

    // setting the bounds on the clip
    {
        var cl = Clip {
            .media = .null_picture,
            .maybe_bounds_s = test_data.T_INT_1_TO_9,
        };

        const xform = opentime.AffineTransform1D {
            .offset = .ZERO,
            .scale = .{ .v = 2 },
        };

        const wp = Warp {
            .child = cl.reference(),
            .transform = try topology_m.Topology.init_affine(
                allocator, 
                .{
                    .input_to_output_xform = xform,
                    .input_bounds_val = .INF,
                },
            ),
        };
        defer wp.transform.deinit(allocator);

        const topo = try wp.topology(allocator);
        defer topo.deinit(allocator);

        const range = opentime.ContinuousInterval {
            .start = .ONE,
            .end = .{ .v = 5 },
        };

        const expected_input_bounds = (
            opentime.ContinuousInterval{
                .start = .ZERO,
                .end = range.duration(),
            }
        );

        try std.testing.expectEqual(
            expected_input_bounds,
            topo.input_bounds(),
        );

        try std.testing.expectEqual(
            opentime.ContinuousInterval{
                .start = .ZERO,
                .end = test_data.T_INT_1_TO_9.duration(),
        },
            topo.output_bounds(),
        );
    }

    // with an offset (no change)
    {
        var cl = Clip {
            .media = .null_picture,
            .maybe_bounds_s = test_data.T_INT_1_TO_9,
        };

        const xform = opentime.AffineTransform1D {
            .offset = .ONE,
            .scale = .{ .v = 2 },
        };

        const wp = Warp {
            .child = cl.reference(),
            .transform = try topology_m.Topology.init_affine(
                allocator, 
                .{
                    .input_to_output_xform = xform,
                    .input_bounds_val = .INF,
                },
            ),
        };
        defer wp.transform.deinit(allocator);

        const topo = try wp.topology(allocator);
        defer topo.deinit(allocator);

        const range = opentime.ContinuousInterval {
            .start = .ONE,
            .end = .{ .v = 5 },
        };

        const expected_input_bounds = (
            opentime.ContinuousInterval{
                .start = .ZERO,
                .end = range.duration(),
            }
        );

        try std.testing.expectEqual(
            expected_input_bounds,
            topo.input_bounds(),
        );

        try std.testing.expectEqual(
            opentime.ContinuousInterval{
                .start = .ZERO,
                .end = test_data.T_INT_1_TO_9.duration(),
        },
            topo.output_bounds(),
        );
    }

    // negative scale
    {
        var cl = Clip {
            .media = .null_picture,
            .maybe_bounds_s = test_data.T_INT_1_TO_9,
        };

        const xform = opentime.AffineTransform1D {
            .offset = .ZERO,
            .scale = opentime.Ordinate.init(-2),
        };

        const wp = Warp {
            .child = cl.reference(),
            .transform = try topology_m.Topology.init_affine(
                allocator, 
                .{
                    .input_to_output_xform = xform,
                    .input_bounds_val = .INF,
                },
            ),
        };
        defer wp.transform.deinit(allocator);

        const wp_pres_to_child = try wp.topology(allocator);
        defer wp_pres_to_child.deinit(allocator);

        const range = opentime.ContinuousInterval {
            .start = .ONE,
            .end = .{ .v = 5 },
        };

        const expected_input_bounds = (
            opentime.ContinuousInterval{
                .start = .ZERO,
                .end = range.duration(),
            }
        );

        try std.testing.expectEqual(
            expected_input_bounds,
            wp_pres_to_child.input_bounds(),
        );

        const child_bounds = (
            opentime.ContinuousInterval{
                .start = .ZERO,
                .end = test_data.T_INT_1_TO_9.duration(),
            }
        );

        try std.testing.expectEqual(
            child_bounds,
            wp_pres_to_child.output_bounds(),
        );

        // project the start and end points to see where they land
        try std.testing.expectEqual(
            child_bounds.end,
            wp_pres_to_child.project_instantaneous_cc(
                expected_input_bounds.start
            ).ordinate(),
        );

        const inverted = try wp_pres_to_child.inverted(
            allocator
        );
        const wp_child_to_pres = inverted[0];
        defer {
            wp_child_to_pres.deinit(allocator);
            allocator.free(inverted);
        }

        try std.testing.expectEqual(
            expected_input_bounds.end,
            wp_child_to_pres.project_instantaneous_cc(
                child_bounds.start
            ).ordinate(),
        );
    }
}
