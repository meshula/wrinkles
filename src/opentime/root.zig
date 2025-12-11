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
pub const expectOrdinateEqual = ordinate.expectOrdinateEqual;
// unary
pub const abs = ordinate.abs;

// binary
pub const min = ordinate.min;
pub const max = ordinate.max;
pub const eql = ordinate.eql;
pub const lt = ordinate.lt;
pub const lteq = ordinate.lteq;
pub const gt = ordinate.gt;
pub const gteq = ordinate.gteq;

// sorting
pub const sort = ordinate.sort;

// comath interface
const comath_wrapper = @import("comath_wrapper.zig");
pub const eval = comath_wrapper.eval;
// @}

// interval @{
pub const interval = @import("interval.zig");
pub const ContinuousInterval = interval.ContinuousInterval;
pub const ContinuousInterval_BaseType = interval.ContinuousInterval_InnerType;
// @}

// transform @{
pub const transform = @import("transform.zig");
pub const AffineTransform1D = transform.AffineTransform1D;
// @}

pub const dual = @import("dual.zig");
pub const Dual_Ord = dual.Dual_Ord;
pub const dual_ctx = dual.dual_ctx{};

pub const util = @import("util.zig");
pub const EPSILON_F = util.EPSILON_F;

const projection_result = @import("projection_result.zig");
pub const ProjectionResult = projection_result.ProjectionResult;

const dbg_print_mod = @import("dbg_print.zig");
pub const dbg_print = dbg_print_mod.dbg_print;

/// Clone return a new slice with each thing in the slice having been .cloned()
/// from the thing in the original list.  Assumes that clone takes an allocator
/// argument and returns in the same order.
pub fn slice_with_cloned_contents_allocator(
    allocator: std.mem.Allocator,
    comptime T: type,
    slice_to_clone: []const T,
) ![]const T
{
    var result: std.ArrayList(T) = .empty;
    defer result.deinit(allocator);
    try result.ensureTotalCapacity(
        allocator,
        slice_to_clone.len,
    );

    for (slice_to_clone)
        |thing|
    {
        result.appendAssumeCapacity(try thing.clone(allocator));
    }

    return try result.toOwnedSlice(allocator);
}

/// Call .deinit(allocator) on all the items in the slice, then free the slice.
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

test {
    _ = ordinate;
    _ = interval;
    _ = transform;
    _ = dual;
    _ = comath_wrapper;
    _ = projection_result;
}

