//! Exports for the `opentime` library
//!
//! The opentime library has tools for dealing with points, intervals and
//! affine transforms in a continuous 1d metric space.
//!
//! It also has some tools for doing dual-arithmetic based implicit
//! differentiation.

const std = @import("std");

// ordinate @{
const ordinate = @import("ordinate.zig");
pub const Ordinate = ordinate.Ordinate;
// @}

// interval @{
pub const interval = @import("interval.zig");
pub const ContinuousInterval = interval.ContinuousInterval;
pub const INF_INTERVAL = interval.INFINITE_INTERVAL;
// @}

// transform @{
pub const transform = @import("transform.zig");
pub const AffineTransform1D = transform.AffineTransform1D;
pub const IDENTITY_TRANSFORM = transform.IDENTITY_TRANSFORM;
// @}

pub const dual = @import("dual.zig");
pub const Dual_Ord = dual.Dual_Ord;
pub const dual_ctx = dual.dual_ctx{};

pub const util = @import("util.zig");
pub const EPSILON_ORD = util.EPSILON_ORD;
pub const INF_ORD = util.INF_ORD;

const projection_result = @import("projection_result.zig");
pub const ProjectionResult = projection_result.ProjectionResult;
pub const OUTOFBOUNDS = projection_result.OUTOFBOUNDS;

test "all opentime tests" {
    _ = interval;
    _ = transform;
    _ = dual;
}

const dbg_print_mod = @import("dbg_print.zig");
pub const dbg_print = dbg_print_mod.dbg_print;

/// clone return a new slice with each thing in the slice having been .cloned()
/// from the thing in the original list.  Assumes that clone takes an allocator
/// argument and returns in the same order.
pub fn slice_with_cloned_contents_allocator(
    allocator: std.mem.Allocator,
    comptime T: type,
    slice_to_clone: []const T,
) ![]const T
{
    var result = std.ArrayList(T).init(allocator);

    for (slice_to_clone)
        |thing|
    {
        try result.append(try thing.clone(allocator));
    }

    return try result.toOwnedSlice();
}

/// call .deinit(allocator) on all the items in the slice, then free the slice
pub fn deinit_slice(
    allocator: std.mem.Allocator,
    comptime T:type,
    slice_to_deinit: []const T,
) void
{
    for (slice_to_deinit)
        |it|
    {
        it.deinit(allocator);
    }
    allocator.free(slice_to_deinit);
}


