const std = @import("std");
const expectEqual = std.testing.expectEqual;

const otio  = @import("root.zig");
const opentime = @import("opentime");
const curve = @import("curve");
const interval = opentime.interval;
const string = @import("string_stuff");
const topology = @import("topology");

pub const SerializableObjectTypes = enum {
    Timeline,
    Stack,
    Track,
    Clip,
    Gap,
    Warp,
    Transition,
};

pub const TransformTypes = enum {
    AffineTransform1D,
    LinearCurve1D,
    BezierCurve1D,
};

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
                        read_ordinate_from_rt(offset_json) orelse .ZERO
                        else .ZERO
                    ),
                    .scale = (
                        if (maybe_object_child(xform_json, "scale")) 
                            |scale_json| 
                        read_ordinate_from_rt(scale_json) 
                        orelse .ONE
                        else .ONE
                    ),
                } 
                else .IDENTITY
            );

            const range: opentime.ContinuousInterval = (
                maybe_range(obj, "input_bounds_val")
                orelse .INF
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

            const result = try topology.Topology.init(
                allocator,
                &.{ 
                    (
                     try topology.MappingCurveLinearMonotonic.init_knots(
                         allocator,
                         try buffer.toOwnedSlice(allocator)
                     )
                    ).mapping(),
                }
            );

            std.debug.print("Topo Curve: {f}\n", .{result});
            for (result.mappings)
                |m|
            {
                std.debug.print(
                    "  m ({s}): {f}\n",
                    .{@tagName(m), m},
                );

                switch (m) {
                    .linear => |lin| {
                        std.debug.print("    knots: \n", .{});
                        for (lin.input_to_output_curve.knots)
                            |knot|
                        {
                            std.debug.print("      {f}\n", .{knot});
                        }
                    },
                    else => {},
                }
            }

            return result;
        },
        .BezierCurve1D => {
            var buffer: std.ArrayList(curve.ControlPoint) = .empty;

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
                &.{
                    .{
                        .p0 = buffer.items[0],
                        .p1 = buffer.items[1],
                        .p2 = buffer.items[2],
                        .p3 = buffer.items[3],
                    }
                },
            );

            std.debug.print("Topo Curve: {f}\n", .{result});
            for (result.mappings)
                |m|
            {
                std.debug.print(
                    "  m ({s}): {f}\n",
                    .{@tagName(m), m},
                );

                switch (m) {
                    .linear => |lin| {
                        std.debug.print("    knots: \n", .{});
                        for (lin.input_to_output_curve.knots)
                            |knot|
                        {
                            std.debug.print("      {f}\n", .{knot});
                        }
                    },
                    else => {},
                }
            }

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

pub fn read_float(
    obj:std.json.Value
) opentime.Ordinate.BaseType 
{
    return switch (obj) {
        .integer => |i| @floatFromInt(i),
        .float => |f| @floatCast(f),
        else => 0,
    };
}

pub fn read_ordinate(
    obj:std.json.Value
) opentime.Ordinate 
{
    return switch (obj) {
        inline .integer, .float => |v| opentime.Ordinate.init(v),
        else => .ZERO,
    };
}

pub fn read_ordinate_from_rt(
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

pub fn read_time_range(
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

pub fn _read_range(
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

pub fn _read_rate(
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
}![]otio.ComposedValueRef
{
    const child_count = children.array.items.len;

    if (child_count == 0)
    {
        return &.{};
    }

    var new_children = try allocator.alloc(
        otio.ComposedValueRef,
        child_count,
    );

    var current_index: usize = 0;
    for (children.array.items) 
        |track| 
    {
        const new_value = read_otio_object(
            allocator,
            track.object,
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

pub fn read_otio_object(
    allocator: std.mem.Allocator,
    obj:std.json.ObjectMap
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
} !otio.ComposedValueRef 
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
                    obj.get("tracks").?.object
                )
            );
            const st = otio.Stack{
                .name = so_stack.stack.name,
                .children = so_stack.stack.children,
            };
            const tl = try allocator.create(otio.Timeline);
            tl.* = .{
                .name = maybe_name,
                .tracks = st,
                .discrete_info = .{
                    .presentation = null,
                },
            };
            allocator.destroy(so_stack.stack);
            return .{ .timeline = tl };
        },
        .Stack => {
            // @TODO: add stack init that takes a name string and copies it in 
            var st = try allocator.create(otio.Stack);
            st.name = maybe_name;

            if (obj.get("children"))
                |children|
            {
                st.children = try read_children(
                    allocator,
                    children,
                );
            }

            return .{ .stack = st };
        },
        .Track => {
            var tr = try allocator.create(otio.Track);
            tr.name = maybe_name;

            if (obj.get("children"))
                |children|
            {
                const child_len = children.array.items.len;
                if (child_len > 0)
                {
                    tr.children = try read_children(
                        allocator,
                        children,
                    );
                }
            }

            return .{ .track = tr };
        },
        .Clip => {
            const range = _read_range(obj);

            const maybe_rate = _read_rate(obj);

            var cl = try allocator.create(otio.Clip);
            cl.* = .{
                .name = maybe_name,
                .bounds_s  = range,
            };

            // @TODO: read more of the media reference
            // @TODO: read metadata

            if (maybe_rate)
                |rate|
            {
                cl.media.discrete_info = .{
                    .sample_rate_hz = .{ .Int = rate },
                };
            }

            return .{ .clip = cl };
        },
        .Gap => {
            const source_range = _read_range(obj);
            const gp = try allocator.create(otio.Gap);
            gp.* = .{
                .name= maybe_name,
                .duration_seconds = source_range.?.duration(),
            };

            return .{ .gap = gp };
        },
        .Warp => {
            const wp = try allocator.create(otio.Warp);
            wp.* = .{
                .name = maybe_name,
                .child = try read_otio_object(allocator, obj.get("child").?.object),
                .transform = try read_transform(allocator,obj.get("transform").?.object),
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
            const container_json = try read_otio_object(
                allocator,
                obj.get("container").?.object,
            );
            const container = otio.Stack {
                .name = container_json.stack.name,
                .children = container_json.stack.children,
            };
            tx.* = .{
                .name = maybe_name,
                .container = container,
                .kind = (try maybe_string(allocator, obj, "kind")) orelse "None",
                .range = null,
            };

            return .{ .transition = tx };
        },
    }

    return error.NotImplemented;
}

/// deserialize OTIO json to the in-memory structure
pub fn read_from_file(
    in_allocator: std.mem.Allocator,
    file_path: string.latin_s8
) !otio.ComposedValueRef
{
    const fi = try std.fs.cwd().openFile(file_path, .{});
    defer fi.close();

    var arena = std.heap.ArenaAllocator.init(in_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const source = try fi.readToEndAlloc(
        allocator,
        std.math.maxInt(u32)
    );

    const result = try std.json.parseFromSliceLeaky(
        std.json.Value,
        allocator,
        source,
        .{}
    );

    const hopefully_timeline = try read_otio_object(
        in_allocator,
        result.object
    );

    if (hopefully_timeline == otio.ComposedValueRef.timeline) {
        return hopefully_timeline;
    }

    return hopefully_timeline;

    // return error.NotImplemented;
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
    );
    defer  tl_ref.recursively_deinit(allocator); 

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
            track0.children[0].clip.name.?
        );
    }

    const target_clip_ptr = track0.children[0];

    var tl_pres_projection_builder = (
        try otio.TemporalProjectionBuilder.init_from(
            allocator,
            tl_ref.space(.presentation),
        )
    );
    defer tl_pres_projection_builder.deinit(allocator);

    const tl_output_to_clip_media = (
        try tl_pres_projection_builder.projection_operator_to(
            allocator,
            target_clip_ptr.space(otio.SpaceLabel.media),
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
    );
    defer  tl.recursively_deinit(allocator); 
}
