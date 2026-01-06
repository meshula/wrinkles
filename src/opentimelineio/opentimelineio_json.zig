//! First-pass JSON parser that reads "appoximately" OTIO V1.
//!
//! Omits support for Effects, Transitions since that format has diverged.
//! Infers discrete partitions.

const std = @import("std");
const expectEqual = std.testing.expectEqual;

const otio = @import("root.zig");
const opentime = @import("opentime");
const curve = @import("curve");
const interval = opentime.interval;
const string = @import("string_stuff");
const topology = @import("topology");
const sampling = @import("sampling");
const serialization = @import("serialization.zig");

const SerializableObjectTypes = enum {
    Timeline,
    Stack,
    Track,
    Clip,
    Gap,
    Warp,
    Transition,
};

/// Options for controlling what content is read from OTIO files.
/// Files are split into two chunks: the temporal hierarchy and the
/// metadata. This enum controls which parts of the file are read.
/// For operations that only need temporal data, this can speed up file
/// reads because production files can contain significant amounts of
/// metadata.
pub const FileContentsToRead = enum {
    /// Read everything (current behavior)
    all,
    /// Read everything except the metadata_map field of the top level
    /// timeline, setting it to null, but skipping the bits.
    all_except_metadata,
};

/// Read options for file parsing
pub const ReadOptions = struct {
    file_contents_to_read: FileContentsToRead = .all,
};

const TransformTypes = enum {
    AffineTransform1D,
    LinearCurve1D,
    BezierCurve1D,
};

// in case you need to dump json object
// fn debug_print() void
// {
//     const fmt = std.json.fmt(my_struct, .{ .whitespace = .indent_2 });
//
//     var writer = std.Io.Writer.Allocating.init(allocator);
//     try fmt.format(&writer.writer);
//
//     const json_string = try writer.toOwnedSlice();
// }

fn maybe_object(
    maybe_obj: ?std.json.Value
) ?std.json.ObjectMap
{
    if (maybe_obj)
        |obj|
    {
        if (std.meta.activeTag(obj) == .object)
        {
            return obj.object;
        }
    }

    return null;
}

fn maybe_string(
    allocator: std.mem.Allocator,
    obj: std.json.ObjectMap,
    key: []const u8,
) !?[]const u8
{
    return (
        if (obj.get(key)) 
        |n| 
        switch (n) 
        {
            .string => |s| try allocator.dupe(u8, s),
            else => null
        } 
        else null
    );
}

fn maybe_object_child(
    object: std.json.Value,
    key: []const u8,
) ?std.json.ObjectMap
{
    return (
        if (maybe_object(object)) 
            |obj| 
        maybe_object(obj.get(key)) orelse null
        else null
    );
}

fn maybe_range(
    object: std.json.ObjectMap,
    key: []const u8,
) ?opentime.ContinuousInterval
{
    return (
        if (maybe_object(object.get(key))) 
            |range_container| 
        _read_range(range_container) 
        else null
    );
}

fn read_transform(
    allocator: std.mem.Allocator,
    obj:std.json.ObjectMap,
) !topology.Topology
{
    const schema = try read_schema(
        TransformTypes,
        obj,
    );

    switch (schema) {
        .AffineTransform1D => {
            const transform:opentime.AffineTransform1D = (
                if (obj.get("input_to_output_xform")) 
                    |xform_json| 
                .{
                    .offset = (
                        if (maybe_object_child(xform_json, "offset")) 
                            |offset_json| 
                        read_ordinate_from_rt(offset_json) orelse .zero
                        else .zero
                    ),
                    .scale = (
                        if (maybe_object_child(xform_json, "scale")) 
                            |scale_json| 
                        read_ordinate_from_rt(scale_json) 
                        orelse .one
                        else .one
                    ),
                } 
                else .identity
            );

            const range: opentime.ContinuousInterval = (
                maybe_range(obj, "input_bounds_val")
                orelse .inf_neg_to_pos
            );
            return try topology.Topology.init_affine(
                allocator,
                .{
                    .input_to_output_xform = transform,
                    .input_bounds_val = range,
                },
            );
        },
        .LinearCurve1D => {
            var buffer: std.ArrayList(curve.ControlPoint) = .empty;
            // note that mapping inits tend to duplicate lists, so this buffer
            // gets read into and then freed because memory is duplicated into
            // the newly created mappings. (for better or for worse)
            defer buffer.deinit(allocator);

            if (obj.get("knots"))
                |knots_obj|
            {
                const schema_knots = try read_schema(
                    enum { ControlPoint2dOrdinateArray },
                    knots_obj.object,
                );
                if (schema_knots != .ControlPoint2dOrdinateArray)
                {
                    std.log.err(
                        "Expected knots schema: "
                        ++ "ControlPointOrdinateArray, got: {s}",
                        .{@tagName(schema)},
                    );
                    return error.InvalidKnotsSchema;
                }

                if (knots_obj.object.get("ControlPoints"))
                    |control_points|
                {
                    const arr = control_points.array;
                    for (arr.items)
                        |child|
                    {
                        // each point
                        const points: curve.ControlPoint = .{
                            .in = read_ordinate(
                                child.array.items[0],
                            ),
                            .out = read_ordinate(
                                child.array.items[1],
                            ),
                        };

                        try buffer.append(allocator, points);
                    }
                }
            }

            const result = topology.Topology {
                .mappings = &.{ 
                    topology.MappingCurveLinearMonotonic.init_knots(
                        try buffer.toOwnedSlice(allocator)
                    ).mapping(),
                }
            };

            return result;
        },
        .BezierCurve1D => {
            var buffer: std.ArrayList(curve.ControlPoint) = .empty;
            defer buffer.deinit(allocator);

            if (obj.get("knots"))
                |knots_obj|
            {
                const schema_knots = try read_schema(
                    enum { ControlPoint2dOrdinateArray },
                    knots_obj.object,
                );
                if (schema_knots != .ControlPoint2dOrdinateArray)
                {
                    std.log.err(
                        "Expected knots schema: "
                        ++ "ControlPointOrdinateArray, got: {s}",
                        .{@tagName(schema)},
                    );
                    return error.InvalidKnotsSchema;
                }

                if (knots_obj.object.get("ControlPoints"))
                    |control_points|
                {
                    const arr = control_points.array;
                    for (arr.items)
                        |child|
                    {
                        // each point
                        const points: curve.ControlPoint = .{
                            .in = read_ordinate(
                                child.array.items[0],
                            ),
                            .out = read_ordinate(
                                child.array.items[1],
                            ),
                        };

                        try buffer.append(allocator, points);
                    }
                }
            }

            const result = try topology.Topology.init_bezier(
                allocator,
                .{
                    .segments = &.{
                        .{
                            .p0 = buffer.items[0],
                            .p1 = buffer.items[1],
                            .p2 = buffer.items[2],
                            .p3 = buffer.items[3],
                        }
                    },
                }
            );

            return result;
        },
    }
}

fn read_schema(
    comptime EnumType: type,
    obj: std.json.ObjectMap,
) !EnumType
{
    const maybe_schema_and_version_str = obj.get("OTIO_SCHEMA");

    if (maybe_schema_and_version_str == null) {
        return error.NotAnOtioSchemaObject;
    }

    const full_string = maybe_schema_and_version_str.?.string;

    var split_schema_string = std.mem.splitSequence(
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
        EnumType,
        schema_str
    );
    if (maybe_schema_enum == null) {
        errdefer std.log.err("No schema: {s}\n", .{schema_str});
        return error.NoSuchSchema;
    }

    return maybe_schema_enum.?;
}

fn read_float(
    obj:std.json.Value
) opentime.Ordinate.InnerType 
{
    return switch (obj) {
        .integer => |i| @floatFromInt(i),
        .float => |f| @floatCast(f),
        else => 0,
    };
}

fn read_ordinate(
    obj:std.json.Value
) opentime.Ordinate 
{
    return switch (obj) {
        inline .integer, .float => |v| opentime.Ordinate.init(v),
        else => .zero,
    };
}

fn read_ordinate_from_rt(
    obj:?std.json.ObjectMap
) ?opentime.Ordinate 
{
    if (obj) 
        |o| 
    {
        const value = read_float(o.get("value").?);
        const rate = read_float(o.get("rate").?);

        return opentime.Ordinate.init(value / rate);
    } 
    else 
    {
        return null;
    }
}

fn read_rate(
    maybe_obj:?std.json.ObjectMap
) ?u32
{

    if (maybe_obj)
        |o|
    {
        if (o.get("rate")) 
            |r| 
        {
            return @intFromFloat(read_float(r));
        }
    }

    return null;
}

fn read_time_range(
    maybe_obj:?std.json.ObjectMap
) ?interval.ContinuousInterval 
{
    if (maybe_obj) 
        |o| 
    {
        const start_time = (
            read_ordinate_from_rt(o.get("start_time").?.object).?
        );
        const duration = (
            read_ordinate_from_rt(o.get("duration").?.object).?
        );
        return .{ 
            .start = start_time, 
            .end = start_time.add(duration)
        };
    } 
    else 
    {
        return null;
    }
}

fn _read_range(
    maybe_obj: ?std.json.ObjectMap
) ?interval.ContinuousInterval
{
    if (maybe_obj == null) {
        return null;
    }

    const obj = maybe_obj.?;

    // prefer source range
    if (obj.get("source_range")) 
        |sr| 
    {
        switch (sr) {
            .object => |o| return read_time_range(o),
            else => {},
        }
    }

    // otherwise, fetch the media reference and try available range
    if (obj.get("media_reference"))
        |mr|
    {
        switch (mr) {
            .object => |mr_o| 
                if (mr_o.get("available_range")) 
                    |ar| 
                {
                    switch (ar) {
                        .object => |o| return read_time_range(o),
                        else => return null,
                    }
                },
                else => return null,
        }
    }

    return null;
}

fn _read_rate(
    maybe_obj: ?std.json.ObjectMap
) ?u32
{
    if (maybe_obj == null) {
        return null;
    }

    const obj = maybe_obj.?;

    if (obj.get("source_range")) 
        |sr| 
    {
        switch (sr) {
            .object => |o| {
                if (o.get("start_time")) 
                    |st| 
                {
                    switch (st){
                        .object => |sto| return read_rate(sto),
                        else => {},
                    }
                }
            },
            else => {},
        }
    } 
    else if (obj.get("media_reference")) 
        |mrv| 
    {
        switch (mrv) {
            .object => |mr| {
                if (mr.get("available_range")) 
                    |ar| 
                {
                    switch (ar) {
                        .object => |o| {
                            if (o.get("start_time")) 
                                |st| 
                            {
                                switch (st){
                                    .object => |sto| return read_rate(sto),
                                    else => {},
                                }
                            }
                        },
                        else => {},
                    }
                }
            },
            else =>{},
        }
    }

    return null;
}

inline fn read_children(
    allocator: std.mem.Allocator,
    children: std.json.Value,
    options: ReadOptions,
) error{
    OutOfMemory,
    NotAnOtioSchemaObject,
    NoSuchSchema,
    MalformedSchemaString,
    NotImplemented,
    NotImplementedFetchTopology,
    NotAnOrdinateResult,
    NoOverlap,
    OutOfBounds,
    UnsupportedSpaceError,
    NoSplitForLinearization,
    Overflow,
    InvalidCharacter,
    UnexpectedToken,
    InvalidNumber,
    InvalidEnumTag,
    UnknownField,
    MissingField,
    LengthMismatch,
    DuplicateField,
}![]otio.CompositionItemHandle
{
    const child_count = children.array.items.len;

    if (child_count == 0)
    {
        return &.{};
    }

    var new_children = try allocator.alloc(
        otio.CompositionItemHandle,
        child_count,
    );

    var current_index: usize = 0;
    for (children.array.items)
        |track|
    {
        const new_value = read_otio_object(
            allocator,
            track.object,
            options,
        ) catch |err|
        {
            switch (err) {
                error.NoSuchSchema => {
                    std.log.err(
                        "Skipping: {s}\n",
                        .{
                            (
                             track.object.get("OTIO_SCHEMA")
                             orelse std.json.Value{.string = ""}
                            ).string
                        }
                    );
                    continue;
                },
                else => {
                    return err;
                },
            }
        };
        new_children[current_index] = new_value;
        current_index += 1;
    }

    // true the allocated size of the slice to the number of children that were
    // readable -- schemas that aren't readable by the zig system get skipped
    if (current_index != new_children.len)
    {
        new_children = try allocator.realloc(
            new_children,
            current_index,
        );
    }

    return new_children;
}

fn read_otio_object(
    allocator: std.mem.Allocator,
    obj: std.json.ObjectMap,
    options: ReadOptions,
) error{
    OutOfMemory,
    NoSuchSchema,
    NotAnOtioSchemaObject,
    MalformedSchemaString,
    NotImplemented,
    NotImplementedFetchTopology,
    NotAnOrdinateResult,
    NoOverlap,
    OutOfBounds,
    UnsupportedSpaceError,
    NoSplitForLinearization,
    Overflow,
    InvalidCharacter,
    UnexpectedToken,
    InvalidNumber,
    InvalidEnumTag,
    UnknownField,
    MissingField,
    LengthMismatch,
    DuplicateField,
} !otio.CompositionItemHandle
{
    const schema_enum = try read_schema(
        SerializableObjectTypes,
        obj,
    );

    const maybe_name = try maybe_string(allocator, obj, "name");

    switch (schema_enum) {
        .Timeline => {
            const so_stack = (
                try read_otio_object(
                    allocator,
                    obj.get("tracks").?.object,
                    options,
                )
            );
            const st = otio.Stack{
                .maybe_name = so_stack.stack.maybe_name,
                .children = so_stack.stack.children,
            };
            const tl = try allocator.create(otio.Timeline);

            // discrete information
            var ddp: otio.schema.DiscretePartitionDomainMap = .no_discretizations;

            // fetch parent object if it exists
            if (maybe_object(obj.get("discrete_space_partitions")))
                |json_ddp|
            {
                if (maybe_object(json_ddp.get("presentation")))
                    |json_ddp_pres|
                {
                    inline for (&[_][]const u8{"picture", "audio"})
                        |field|
                    {
                        if (json_ddp_pres.get(field))
                            |json_domain|
                        {
                            const discrete = &@field(
                                ddp,
                                field,
                            );

                            var json_blob = (
                                try std.json.parseFromValue(
                                    sampling.SampleIndexGenerator,
                                    allocator, 
                                    json_domain,
                                    .{
                                        .allocate = .alloc_if_needed,
                                        .ignore_unknown_fields = true,
                                        .parse_numbers = true,
                                        .duplicate_field_behavior = .use_last,
                                    },
                                )
                            );
                            defer json_blob.deinit();

                            discrete.* = json_blob.value;

                            std.debug.print(
                                "found: blah {?f}\n",
                                .{discrete.*}
                            );
                        }
                    }
                }
            }

            tl.* = .{
                .maybe_name = maybe_name,
                .tracks = st,
                .discrete_space_partitions = .{
                    .presentation = ddp,
                },
            };
            allocator.destroy(so_stack.stack);
            return .{ .timeline = tl };
        },
        .Stack => {
            var st = try allocator.create(otio.Stack);
            st.maybe_name = maybe_name;

            if (obj.get("children"))
                |children|
            {
                st.children = try read_children(
                    allocator,
                    children,
                    options,
                );
            }

            return .{ .stack = st };
        },
        .Track => {
            var tr = try allocator.create(otio.Track);
            tr.maybe_name = maybe_name;

            if (obj.get("children"))
                |children|
            {
                const child_len = children.array.items.len;
                if (child_len > 0)
                {
                    tr.children = try read_children(
                        allocator,
                        children,
                        options,
                    );
                }
            }

            return .{ .track = tr };
        },
        .Clip => {
            const range = _read_range(obj);

            const maybe_rate = _read_rate(obj);

            // Read metadata if present (store raw JSON value)
            // Skip if options specify all_except_metadata
            const maybe_metadata: ?std.json.Value = if (options.file_contents_to_read == .all_except_metadata)
                null
            else if (obj.get("metadata")) |meta_val| blk: {
                // Only store non-empty metadata objects
                if (std.meta.activeTag(meta_val) == .object and meta_val.object.count() > 0) {
                    break :blk meta_val;
                }
                break :blk null;
            } else null;

            var cl = try allocator.create(otio.Clip);
            cl.* = .{
                .maybe_name = maybe_name,
                .maybe_bounds_s  = range,
                .media = .null_picture,
                .maybe_metadata_json = maybe_metadata,
            };

            // @TODO: read more of the media reference

            if (maybe_rate)
                |rate|
            {
                cl.media.maybe_discrete_partition = .{
                    .sample_rate_hz = .{ .Int = rate },
                };
            }

            return .{ .clip = cl };
        },
        .Gap => {
            const source_range = _read_range(obj);
            const gp = try allocator.create(otio.Gap);
            gp.* = .{
                .maybe_name= maybe_name,
                .bounds_s = source_range.?,
            };

            return .{ .gap = gp };
        },
        .Warp => {
            const wp = try allocator.create(otio.Warp);
            wp.* = .{
                .maybe_name = maybe_name,
                .child = try read_otio_object(
                    allocator,
                    obj.get("child").?.object,
                    options,
                ),
                .transform = try read_transform(
                    allocator,
                    obj.get("transform").?.object
                ),
            };

            std.debug.assert(wp.transform.mappings.len != 0);

            return .{ .warp = wp };
        },
        // else => {
        //     errdefer std.log.err("Not implemented yet: {s}\n", .{ schema_str });
        //     return error.NotImplemented;
        // }
        .Transition => {
            const tx = try allocator.create(otio.Transition);

            // Handle missing container field (v0 -> v1 upgrade)
            const container = if (obj.get("container")) |container_value| blk: {
                const container_json = try read_otio_object(
                    allocator,
                    container_value.object,
                    options,
                );
                const result = otio.Stack {
                    .maybe_name = container_json.stack.maybe_name,
                    .children = container_json.stack.children,
                };
                allocator.destroy(container_json.stack);
                break :blk result;
            } else otio.Stack {
                .maybe_name = null,
                .children = &.{},
            };

            // Handle missing kind field (use transition_type or default)
            const kind = if (try maybe_string(allocator, obj, "kind")) |k|
                k
            else if (try maybe_string(allocator, obj, "transition_type")) |tt|
                tt
            else
                try allocator.dupe(u8, "SMPTE_Dissolve");

            tx.* = .{
                .maybe_name = maybe_name,
                .container = container,
                .kind = kind,
                .maybe_bounds_s = null,
            };

            return .{ .transition = tx };
        },
    }

    return error.NotImplemented;
}

/// Read a timeline from .otio (JSON), .ziggy, or .tlb (binary) file.
/// The file format is determined by the file extension.
pub fn read_from_file(
    in_allocator: std.mem.Allocator,
    file_path: string.latin_s8,
    options: ReadOptions,
) !otio.CompositionItemHandle
{
    // Check file extension to determine format
    const ext_start = std.mem.lastIndexOfScalar(u8, file_path, '.') orelse {
        return error.NoFileExtension;
    };
    const extension = file_path[ext_start..];

    if (std.mem.eql(u8, extension, ".ziggy"))
    {
        // Read ziggy format
        const file = try std.fs.cwd().openFile(file_path, .{});
        defer file.close();

        const source = try file.readToEndAllocOptions(
            in_allocator,
            std.math.maxInt(u32),
            null,
            .@"1",
            0,
        );
        defer in_allocator.free(source);

        const timeline = try serialization.deserialize_timeline(
            in_allocator,
            source,
            options,
        );

        return .{ .timeline = timeline };
    }

    if (std.mem.eql(u8, extension, ".tlb"))
    {
        // Read binary CBOR format
        const binary_serialization = @import("binary_serialization.zig");

        const file = try std.fs.cwd().openFile(file_path, .{});
        defer file.close();

        const source = try file.readToEndAlloc(
            in_allocator,
            std.math.maxInt(u32),
        );
        defer in_allocator.free(source);

        const timeline = try binary_serialization.deserialize_timeline_binary(
            in_allocator,
            source,
            options,
        );

        return .{ .timeline = timeline };
    }

    if (std.mem.eql(u8, extension, ".tlfb"))
    {
        // Read binary FlatBuffers format
        const flatbufs = @import("binary_serialization_flatbufs.zig");

        const file = try std.fs.cwd().openFile(file_path, .{});
        defer file.close();

        const source = try file.readToEndAlloc(
            in_allocator,
            std.math.maxInt(u32),
        );
        defer in_allocator.free(source);

        const timeline = try flatbufs.deserialize_timeline(
            in_allocator,
            source,
            options,
        );

        return .{ .timeline = timeline };
    }

    // Default to JSON format (.otio)
    const fi = try std.fs.cwd().openFile(file_path, .{});
    defer fi.close();

    var arena = std.heap.ArenaAllocator.init(in_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = try fi.readToEndAlloc(
        allocator,
        std.math.maxInt(u32),
    );

    const result = try std.json.parseFromSliceLeaky(
        std.json.Value,
        allocator,
        source,
        .{},
    );

    return try read_otio_object(
        in_allocator,
        result.object,
        options,
    );
}

/// Read OTIO JSON from string
pub fn read_from_string(
    in_allocator: std.mem.Allocator,
    json_source: []const u8,
    options: ReadOptions,
) !otio.CompositionItemHandle
{
    var arena = std.heap.ArenaAllocator.init(in_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const result = try std.json.parseFromSliceLeaky(
        std.json.Value,
        allocator,
        json_source,
        .{},
    );

    return read_otio_object(in_allocator, result.object, options);
}

test "read_from_file test (simple)"
{
    const allocator = std.testing.allocator;

    const root = "simple_cut";
    const otio_fpath = root ++ ".otio";
    const dot_fpath = root ++ ".dot";

    var tl_ref = try read_from_file(
        std.testing.allocator,
        "sample_otio_files/"++otio_fpath,
        .{},
    );
    defer  tl_ref.deinit(allocator); 

    const track0 = tl_ref.timeline.tracks.children[0].track;

    if (std.mem.eql(u8, root, "simple_cut"))
    {
        try expectEqual(
            @as(usize, 1),
            tl_ref.timeline.tracks.children.len,
        );

        try expectEqual(@as(usize, 4), track0.children.len);
        try std.testing.expectEqualStrings(
            "Clip-001",
            track0.children[0].clip.maybe_name.?
        );
    }

    const target_clip_ptr = track0.children[0];

    var tl_pres_projection_builder = (
        try otio.TemporalProjectionBuilder.init_from(
            allocator,
            tl_ref.space_node(.presentation),
        )
    );
    defer tl_pres_projection_builder.deinit(allocator);

    const tl_output_to_clip_media = (
        try tl_pres_projection_builder.projection_operator_to(
            allocator,
            target_clip_ptr.space_node(.media),
        )
    );
    
    try tl_pres_projection_builder.tree.write_dot_graph(
        allocator,
        "/var/tmp/" ++ dot_fpath,
        "read_from_file_test",
        .{},
    );

    try opentime.expectOrdinateEqual(
        0.175,
        try tl_output_to_clip_media.project_instantaneous_cc(
            opentime.Ordinate.init(0.05),
        ).ordinate(),
    );
}

test "read_from_file test (multiple, smoke)" 
{
    const allocator = std.testing.allocator;

    const root = "multiple_track";
    const otio_fpath = root ++ ".otio";

    var tl = try read_from_file(
        std.testing.allocator,
        "sample_otio_files/"++otio_fpath,
        .{},
    );
    defer  tl.deinit(allocator);
}

test "read_from_file with all_except_metadata option"
{
    const allocator = std.testing.allocator;

    // Test reading a ziggy file with metadata
    const ziggy_file = "otio_sample_data/simple_cut.ziggy";

    // Read with all content
    var tl_all = try read_from_file(
        allocator,
        ziggy_file,
        .{ .file_contents_to_read = .all },
    );
    defer tl_all.deinit(allocator);

    // Read with metadata skipped
    var tl_no_meta = try read_from_file(
        allocator,
        ziggy_file,
        .{ .file_contents_to_read = .all_except_metadata },
    );
    defer tl_no_meta.deinit(allocator);

    // Both should have the same structure
    try expectEqual(
        tl_all.timeline.tracks.children.len,
        tl_no_meta.timeline.tracks.children.len,
    );

    // Both timelines should have the same name
    if (tl_all.timeline.maybe_name) |name_all| {
        try std.testing.expect(tl_no_meta.timeline.maybe_name != null);
        try std.testing.expectEqualStrings(name_all, tl_no_meta.timeline.maybe_name.?);
    }
}

test "read_from_file with all_except_metadata on OTIO JSON file"
{
    const allocator = std.testing.allocator;

    const otio_file = "sample_otio_files/simple_cut.otio";

    // Read with all content
    var tl_all = try read_from_file(
        allocator,
        otio_file,
        .{ .file_contents_to_read = .all },
    );
    defer tl_all.deinit(allocator);

    // Read with metadata skipped
    var tl_no_meta = try read_from_file(
        allocator,
        otio_file,
        .{ .file_contents_to_read = .all_except_metadata },
    );
    defer tl_no_meta.deinit(allocator);

    // Both should have the same structure
    try expectEqual(
        tl_all.timeline.tracks.children.len,
        tl_no_meta.timeline.tracks.children.len,
    );

    // Check clips in both still have names
    const track_all = tl_all.timeline.tracks.children[0].track;
    const track_no_meta = tl_no_meta.timeline.tracks.children[0].track;

    try expectEqual(track_all.children.len, track_no_meta.children.len);

    // First clip should have the same name in both
    if (track_all.children[0].clip.maybe_name) |name| {
        try std.testing.expect(track_no_meta.children[0].clip.maybe_name != null);
        try std.testing.expectEqualStrings(name, track_no_meta.children[0].clip.maybe_name.?);
    }

    // However, for JSON files, the clip's metadata should be null when skipped
    // (Note: In this simple test file, clips may not have metadata anyway)
}
