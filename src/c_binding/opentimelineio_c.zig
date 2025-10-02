const std = @import("std");

const opentime = @import("opentime");
const otio = @import("opentimelineio");
const topology = @import("topology");

const c = @cImport(
    {
        @cInclude("opentimelineio_c.h");
    }
);

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const ALLOCATOR:std.mem.Allocator = gpa.allocator();

/// constant to represent an error (nullpointer)
const ERR_REF : c.otio_ComposedValueRef = .{
    .kind = c.otio_ct_err,
    .ref = null 
};

const ERR_ALLOCATOR = c.otio_Allocator{ .ref = null };
const ERR_ARENA = c.otio_Arena{ .arena = null, .allocator = ERR_ALLOCATOR };
pub export fn otio_fetch_allocator_gpa() c.otio_Allocator
{
    return .{ .ref = @ptrCast(@constCast(&ALLOCATOR)) };
}
pub export fn otio_fetch_allocator_new_arena(
) c.otio_Arena
{
    // set up the allocator
    var arena = std.heap.ArenaAllocator.init(
        std.heap.page_allocator
    );
    const allocator = arena.allocator();

    // build the longer lifetime pointers
    const arena_ptr = (
        allocator.create(std.heap.ArenaAllocator) catch return ERR_ARENA
    );
    const alloc_ptr = (
        allocator.create(std.mem.Allocator) catch return ERR_ARENA
    );
    const vtable = (
        allocator.create(std.mem.Allocator.VTable) catch return ERR_ARENA
    );
    vtable.alloc = allocator.vtable.alloc;
    vtable.resize = allocator.vtable.resize;
    vtable.free = allocator.vtable.free;

    // build out the result
    arena_ptr.* = arena;
    alloc_ptr.* = .{
        .ptr = arena_ptr,
        .vtable = vtable,
    };

    return c.otio_Arena{
        .arena = arena_ptr,
        .allocator = .{ .ref = alloc_ptr },
    };
}
pub export fn otio_arena_deinit(
    ref_c: c.otio_Arena,
) void
{
    if (ref_c.arena == null)
    {
        return;
    }

    const ref = ptrCast(
        std.heap.ArenaAllocator,
        ref_c.arena.?
    );

    ref.*.deinit();
}

pub export fn otio_read_from_file(
    allocator_c: c.otio_Allocator,
    filepath_c: [*:0]const u8,
) c.otio_ComposedValueRef
{
    const filepath : []const u8 = std.mem.span(filepath_c);
    const allocator = fetch_allocator(
        allocator_c
    ) catch return ERR_REF;

    const result = allocator.create(otio.Timeline) catch {
        std.log.err("Problem making thing.\n", .{});
        return ERR_REF;
    };

    result.* = otio.read_from_file(
        allocator,
        filepath,
    ) catch |err| {
        std.log.err(
            "couldn't read file: '{s}', error: {any}\n",
            .{filepath, err},
        );
        return ERR_REF;
    };

    return .{
        .kind = c.otio_ct_timeline,
        .ref = @ptrCast(result),
    };
}

fn ptrCast(
    t: type,
    ptr: *anyopaque,
) *t
{
    return @as(*t, @ptrCast(@alignCast(ptr)));
}

fn fetch_allocator(
    input: c.otio_Allocator
) !std.mem.Allocator
{
    if (input.ref == null) {
        std.log.err("Null allocator argument\n",.{});
        return error.InvalidAllocatorError;
    }

    return ptrCast(std.mem.Allocator, input.ref.?).*;
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
    allocator_c: c.otio_Allocator,
    timeline: c.otio_ComposedValueRef,
) c.otio_TopologicalMap
{
    const ref = init_ComposedValueRef(
        timeline
    ) catch return ERR_TOPO_MAP;
    const allocator = fetch_allocator(
        allocator_c
    ) catch return ERR_TOPO_MAP;

    const result = allocator.create(
        otio.TopologicalMap
    ) catch return ERR_TOPO_MAP;

    result.* = otio.build_topological_map(
        allocator,
        ref,
    ) catch return ERR_TOPO_MAP;

    return .{ .ref = result };
}

const ERR_PO_MAP = c.otio_ProjectionOperatorMap{ .ref = null };

pub export fn otio_build_projection_op_map_to_media_tp_cvr(
    allocator_c: c.otio_Allocator,
    in_map: c.otio_TopologicalMap,
    source: c.otio_ComposedValueRef,
) c.otio_ProjectionOperatorMap
{
    if (in_map.ref == null) {
        return ERR_PO_MAP;
    }
    const allocator = fetch_allocator(
        allocator_c
    ) catch return ERR_PO_MAP;

    const map_c = in_map.ref.?;

    const map = ptrCast(otio.TopologicalMap, map_c);

    const result = allocator.create(
        otio.ProjectionOperatorMap
    ) catch return ERR_PO_MAP;

    const src = init_ComposedValueRef(
        source
    ) catch return ERR_PO_MAP;

    result.* = otio.projection_map_to_media_from(
        allocator,
        map.*,
        src.space(.presentation) catch |err| {
            std.log.err("Couldn't fetch presentation space: {any}\n", .{err});
            return ERR_PO_MAP;
        },
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
    allocator_c: c.otio_Allocator,
    in_map: c.otio_TopologicalMap,
    filepath_c: [*:0]const u8,
) void 
{
    const t_map = ptrCast(otio.TopologicalMap, in_map.ref.?);
    const allocator = fetch_allocator(
        allocator_c
    ) catch  return ; 

    t_map.write_dot_graph(
        allocator,
        std.mem.span(filepath_c),
        .{},
    ) catch {
        std.log.err(
            "couldn't write map to: '{s}'\n",
            .{ filepath_c }
        );
        return;
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
    in_po_map_c: c.otio_ProjectionOperatorMap,
) [*]const f32
{
    const po_map = ptrCast(
        otio.ProjectionOperatorMap,
        in_po_map_c.ref.?
    );

    // because Ordinate is a boxed float, the ptr can be cast to a ptr to an
    // array of f32
    return @ptrCast(po_map.end_points.ptr);
}

pub export fn otio_po_map_fetch_num_operators_for_segment(
    in_po_map_c: c.otio_ProjectionOperatorMap,
    ind: usize,
) usize
{
    const po_map = ptrCast(
        otio.ProjectionOperatorMap,
        in_po_map_c.ref.?
    );

    return po_map.operators[ind].len;
}
pub export fn otio_po_map_fetch_op(
    in_po_map_c: c.otio_ProjectionOperatorMap,
    segment_ind: usize,
    operator_ind: usize,
    result: *c.otio_ProjectionOperator,
) c_int
{
    const po_map = ptrCast(
        otio.ProjectionOperatorMap,
        in_po_map_c.ref.?
    );

    const po = &po_map.operators[segment_ind][operator_ind];

    result.ref = @constCast(@ptrCast(po));

    return 0;
}

fn init_ProjectionOperator(
    maybe_in_po_c: c.otio_ProjectionOperator,
) !*otio.ProjectionOperator
{
    if (maybe_in_po_c.ref)
        |in_po_c|
    {
        return ptrCast(otio.ProjectionOperator, in_po_c);
    }
    else {
        return error.NullProjectionOperator;
    }
}

pub fn otio_po_fetch_topology_erroring(
    in_po_c: c.otio_ProjectionOperator,
    result: *c.otio_Topology,
) !c_int
{
    const po = try init_ProjectionOperator(in_po_c);

    result.* = .{ .ref = &po.src_to_dst_topo };

    return 0;
}

pub export fn otio_po_fetch_topology(
    in_po_c: c.otio_ProjectionOperator,
    result: *c.otio_Topology,
) c_int
{
    return otio_po_fetch_topology_erroring(
        in_po_c,
        result
    ) catch {
        return -1;
    };
}

fn otio_po_fetch_destination_erroring(
    in_po_c: c.otio_ProjectionOperator,
) !c.otio_ComposedValueRef
{
    const po = try init_ProjectionOperator(in_po_c);

    // note - returns a SpaceReference, not a ComposedValueRef
    return to_c_ref(po.destination.ref);
}

pub export fn otio_po_fetch_destination(
    in_po_c: c.otio_ProjectionOperator,
) c.otio_ComposedValueRef
{
    return otio_po_fetch_destination_erroring(in_po_c) catch {
        return ERR_REF;
    };
}

/// attempt to clean up the timeline/object
pub export fn otio_timeline_deinit(
    allocator_c: c.otio_Allocator,
    root_c : c.otio_ComposedValueRef,
) void
{
    const root = (
        init_ComposedValueRef(root_c) catch |err| {
            std.log.err(
                "Error converting to object: {any}\n",
                .{ err} ,
            );
            return;
        }
    );

    switch (root) {
        inline .timeline_ptr, .stack_ptr, .track_ptr => 
            |t| (
                // @TODO: remove the need for constCast
                //        constCast becuase ComposedValueRef is a const*
                //        wrapper
                @constCast(t).recursively_deinit(
                    fetch_allocator(allocator_c) catch @panic(
                        "Couldn't find allocator",
                    ),
                )

            ),
        inline else => {},
    }
}

const ERR_TOPO:c.otio_Topology = .{ .ref = null };

/// compute the topology for the ComposedValueRef
pub export fn otio_fetch_topology(
    allocator_c: c.otio_Allocator,
    ref_c: c.otio_ComposedValueRef,
) c.otio_Topology
{
    const ref = init_ComposedValueRef(ref_c) 
        catch return ERR_TOPO;
    const allocator = fetch_allocator(
        allocator_c
    ) catch return ERR_TOPO;

    const result = allocator.create(
        topology.Topology
    ) catch |err|
    {
        std.log.err("problem building topo: {any}\n", .{ err });
        return ERR_TOPO;
    };

    result.* = ref.topology(allocator) catch return ERR_TOPO;

    return .{ .ref = result };
}

pub export fn otio_topo_fetch_input_bounds(
    topo_c: c.otio_Topology,
    result: *c.otio_ContinuousInterval,
) i32
{
    if (topo_c.ref == null) {
        std.log.err("Null topo pointer\n", .{});

        return -1;
    }

    const ref = topo_c.ref.?;

    const topo = ptrCast(
        topology.Topology,
        ref,
    );

    const b = topo.input_bounds();

    result.*.start = b.start.as(@TypeOf(result.start));
    result.*.end = b.end.as(@TypeOf(result.end));

    return 0;
}

pub export fn otio_topo_fetch_output_bounds(
    topo_c: c.otio_Topology,
    result: *c.otio_ContinuousInterval,
) i32
{
    if (topo_c.ref == null) {
        std.log.err("Null topo pointer\n", .{});

        return -1;
    }

    const ref = topo_c.ref.?;

    const topo = ptrCast(
        topology.Topology,
        ref,
    );

    const b = topo.output_bounds();

    result.*.start = b.start.as(@TypeOf(result.start));
    result.*.end = b.end.as(@TypeOf(result.end));

    return 0;
}

fn init_SpaceLabel(
    in_c: c.otio_SpaceLabel
) !otio.SpaceLabel
{
    return switch (in_c) {
        c.otio_sl_presentation => .presentation,
        c.otio_sl_media => .media,
        else => error.InvalidSpaceLabel,
    };
}

fn otio_fetch_discrete_info_erroring(
    ref_c: c.otio_ComposedValueRef,
    space: c.otio_SpaceLabel,
    result: *c.otio_DiscreteDatasourceIndexGenerator,
) !c_int
{
    const ref = try init_ComposedValueRef(ref_c);
    const label = try init_SpaceLabel(space);

    const maybe_di = (
        try ref.discrete_info_for_space(label)
    );

    if (maybe_di)
        |di|
    {
        const rate : c.otio_Rational = switch (di.sample_rate_hz) {
            .Int => |i| .{ .num = i, .den = 1 },
            .Rat => |r| .{ .num = r.num, .den = r.den },
        };

        result.* = .{
            .sample_rate_hz = rate,
            .start_index = di.start_index,
        };
        return 0;
    }

    return -1;
}

pub export fn otio_fetch_discrete_info(
    ref_c: c.otio_ComposedValueRef,
    space: c.otio_SpaceLabel,
    result: *c.otio_DiscreteDatasourceIndexGenerator,
) c_int
{
    return otio_fetch_discrete_info_erroring(
        ref_c,
        space,
        result
    ) catch 
    {
        // std.log.err("couldn't fetch discrete info: {any}\n", .{err});
        return -1;
    };
}

fn otio_fetch_continuous_ordinate_to_discrete_index_erroring(
    ref_c: c.otio_ComposedValueRef,
    val: f32,
    space_c: c.otio_SpaceLabel,
) !usize
{
    const ref = try init_ComposedValueRef(ref_c);
    const space = try init_SpaceLabel(space_c);
    return try ref.continuous_ordinate_to_discrete_index(
        opentime.Ordinate.init(val),
        space
    );
}

pub export fn otio_fetch_continuous_ordinate_to_discrete_index(
    ref_c: c.otio_ComposedValueRef,
    val: f32,
    space_c: c.otio_SpaceLabel,
) usize
{
    return otio_fetch_continuous_ordinate_to_discrete_index_erroring(
        ref_c,
        val,
        space_c,
    ) catch |err| {
        std.log.err(
            "Error fetching the continuous value: {any}\n",
            .{err}
        );
        return 0;
    };
}
