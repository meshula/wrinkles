//
// Exports for the `opentime` library
//

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
pub const Dual_t = dual.Dual_t;

pub const util = @import("util.zig");

test "all opentime tests" {
    _ = interval;
    // _ = Domain;
    _ = transform;
    _ = dual;
}
