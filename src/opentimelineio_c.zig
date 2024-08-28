const std = @import("std");

const otio = @import("opentimelineio");

const c = @cImport(
    {
        @cInclude("opentimelineio_c.h");
    }
);

var raw = std.heap.GeneralPurposeAllocator(.{}){};
const ALLOCATOR:std.mem.Allocator = raw.allocator();

/// constant to represent an error (nullpointer)
const ERR_REF : c.otio_ComposedValueRef = .{
    .kind = c.otio_ct_err,
    .ref = null 
};

pub export fn foo(
    msg: [*:0]const u8
) void
{
    std.log.debug("hello, {s}\n", .{ msg });
}

pub export fn otio_read_from_file(
    filepath_c: [*:0]const u8,
) c.otio_ComposedValueRef
{
    const filepath : []const u8 = std.mem.span(filepath_c);

    const parsed_tl = otio.read_from_file(
        ALLOCATOR, 
        filepath,
    ) catch |err| {
        std.log.err(
            "couldn't read file: '{s}', error: {any}\n",
            .{filepath, err},
        );
        return ERR_REF;
    };

    const result = ALLOCATOR.create(otio.Timeline) catch {
        return ERR_REF;
    };

    result.* = parsed_tl;

    return .{ .kind = c.otio_ct_timeline, .ref = @as(*anyopaque, result) };
}

fn ptrCast(
    t: type,
    ptr: *anyopaque,
) *t
{
    return @as(*t, @ptrCast(@alignCast(ptr)));
}

fn init_ComposedValueRef(
    input: c.otio_ComposedValueRef,
) !otio.ComposedValueRef
{
    if (input.ref)
        |ptr|
    {
        return switch (input.kind) {
            c.otio_ct_timeline => otio.ComposedValueRef.init(ptrCast(otio.Timeline, ptr)),
            c.otio_ct_stack => otio.ComposedValueRef.init(ptrCast(otio.Stack, ptr)),
            c.otio_ct_track => otio.ComposedValueRef.init(ptrCast(otio.Track, ptr)),
            c.otio_ct_clip =>  otio.ComposedValueRef.init(ptrCast(otio.Clip, ptr)),
            c.otio_ct_gap =>   otio.ComposedValueRef.init(ptrCast(otio.Gap, ptr)),
            c.otio_ct_warp =>  otio.ComposedValueRef.init(ptrCast(otio.Warp, ptr)),
            else => return error.ErrorReference,
        };
    }

    return error.ErrorReference;
}

pub fn to_c_ref(
    input: otio.ComposedValueRef,
) c.otio_ComposedValueRef
{
    return switch (input) {
        .timeline_ptr => |t| .{ .kind = c.otio_ct_timeline, .ref = @ptrCast(@constCast(t)) },
        .stack_ptr => |t|       .{ .kind = c.otio_ct_stack,    .ref = @ptrCast(@constCast(t)) },
        .track_ptr => |t|       .{ .kind = c.otio_ct_track,    .ref = @ptrCast(@constCast(t)) },
        .clip_ptr =>  |t|        .{ .kind = c.otio_ct_clip,     .ref = @ptrCast(@constCast(t)) },
        .gap_ptr =>   |t|         .{ .kind = c.otio_ct_gap,      .ref = @ptrCast(@constCast(t)) },
        .warp_ptr =>  |t|        .{ .kind = c.otio_ct_warp,     .ref = @ptrCast(@constCast(t)) },
    };
}

pub export fn otio_child_count_cvr(
    input: c.otio_ComposedValueRef,
) c_int
{
    const ref: otio.ComposedValueRef = init_ComposedValueRef(input) catch { 
        return -1;
    };

    return switch (ref) {
        .timeline_ptr => |*tl| @intCast(tl.*.tracks.children.items.len),
        inline .stack_ptr, .track_ptr => |*t|  @intCast(t.*.children.items.len),
        inline else => 0,
    };
}

pub export fn otio_fetch_child_cvr_ind(
    input: c.otio_ComposedValueRef,
    c_index: c_int,
) c.otio_ComposedValueRef
{
    const ref: otio.ComposedValueRef = init_ComposedValueRef(input) catch { 
        return ERR_REF; 
    };

    const index: usize = @intCast(c_index);

    const result = switch (ref) {
        .timeline_ptr => |*tl| res: {
            break :res to_c_ref(tl.*.tracks.child_ptr_from_index(index));
        },
        inline .stack_ptr, .track_ptr => |*t|  res: {
            break :res to_c_ref(t.*.child_ptr_from_index(index));
        },
        inline else => return ERR_REF,
    };

    return result;
}

const ERR_TOPO_MAP = c.otio_TopologicalMap{ .ref = null };

pub export fn otio_build_topo_map_cvr(
    timeline: c.otio_ComposedValueRef,
) c.otio_TopologicalMap
{
    const ref = init_ComposedValueRef(
        timeline
    ) catch return ERR_TOPO_MAP;

    const result = ALLOCATOR.create(
        otio.TopologicalMap
    ) catch return ERR_TOPO_MAP;

    result.* = otio.build_topological_map(
        ALLOCATOR,
        ref,
    ) catch return ERR_TOPO_MAP;

    return .{ .ref = result };
}

const ERR_PO_MAP = c.otio_ProjectionOperatorMap{ .ref = null };

pub export fn otio_build_projection_op_map_to_media_tp_cvr(
    in_map: c.otio_TopologicalMap,
    source: c.otio_ComposedValueRef,
) c.otio_ProjectionOperatorMap
{
    if (in_map.ref == null) {
        return ERR_PO_MAP;
    }

    const map_c = in_map.ref.?;

    const map = ptrCast(otio.TopologicalMap, map_c);

    const result = ALLOCATOR.create(
        otio.ProjectionOperatorMap
    ) catch return ERR_PO_MAP;

    const src = init_ComposedValueRef(
        source
    ) catch return ERR_PO_MAP;

    result.* = otio.projection_map_to_media_from(
        ALLOCATOR,
        map.*,
        try src.space(.presentation),
    ) catch |err| {
        std.log.err("Couldn't build map: {any}\n", .{ err});
        return ERR_PO_MAP;
    };

    return .{ .ref = result };
}

pub export fn otio_fetch_cvr_type_str(
    self: c.otio_ComposedValueRef,
    buf: [*]u8,
    len: usize,
) c_int
{
    const label: [:0]const u8 = switch (self.kind) {
        c.otio_ct_timeline => "timeline",
        c.otio_ct_stack => "stack",
        c.otio_ct_track => "track",
        c.otio_ct_clip => "clip",
        c.otio_ct_gap => "gap",
        c.otio_ct_warp => "warp",
        c.otio_ct_err => "err",
        else => "unknown",
    };

    const buf_slice = buf[0..len];

    _ = std.fmt.bufPrintZ(
        buf_slice,
        "{s}",
        .{ label },
    ) catch |err| {
        std.log.err("error printing to buffer: {any}\n", .{err});
        std.log.err("input buffer: '{s}'", .{buf_slice});

        return -1;
    };

    return 0;
}

pub export fn otio_fetch_cvr_name_str(
    self: c.otio_ComposedValueRef,
    buf: [*]u8,
    len: usize,
) c_int
{
    const ref = init_ComposedValueRef(self) catch return -1;

    const buf_slice = buf[0..len];

    const name = switch (ref) {
        .warp_ptr => "",
        inline else => |r| r.name,
    };

    _ = std.fmt.bufPrintZ(
        buf_slice,
        "{?s}",
        .{ name },
    ) catch |err| {
        std.log.err("error printing to buffer: {any}\n", .{err});
        std.log.err("input buffer: '{s}'", .{buf_slice});

        return -1;
    };

    return 0;
}

pub export fn otio_write_map_to_png(
    in_map: c.otio_TopologicalMap,
    filepath_c: [*:0]const u8,
) void 
{
    const t_map = ptrCast(otio.TopologicalMap, in_map.ref.?);

    t_map.write_dot_graph(
        ALLOCATOR,
        std.mem.span(filepath_c)
    ) catch {
        std.log.err("couldn't write map to: '{s}'\n", .{ filepath_c });
    };

    std.log.debug("wrote map to: '{s}'\n", .{ filepath_c });
}

pub export fn otio_po_map_fetch_num_endpoints(
    in_po_map: c.otio_ProjectionOperatorMap,
) usize
{
    const po_map = ptrCast(
        otio.ProjectionOperatorMap,
        in_po_map.ref.?
    );

    return po_map.end_points.len;
}

pub export fn otio_po_map_fetch_endpoints(
    in_po_map: c.otio_ProjectionOperatorMap,
) [*]f32
{
    const po_map = ptrCast(
        otio.ProjectionOperatorMap,
        in_po_map.ref.?
    );

    return po_map.end_points.ptr;
}
