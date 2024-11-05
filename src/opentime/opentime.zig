//! Exports for the `opentime` library

// ordinate @{
const ordinate = @import("ordinate.zig");
pub const Ordinate = ordinate.Ordinate;
// @}

// interval @{
pub const interval = @import("interval.zig");
pub const ContinuousTimeInterval = interval.ContinuousTimeInterval;
pub const INF_CTI = interval.INF_CTI;
// @}

// Domain @{
// pub const Domain = @import("domain.zig").Domain;
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

const projection_result = @import("projection_result.zig");
pub const ProjectionResult = projection_result.ProjectionResult;
pub const OUTOFBOUNDS = projection_result.OUTOFBOUNDS;

test "all opentime tests" {
    _ = interval;
    // _ = Domain;
    _ = transform;
    _ = dual;
}
