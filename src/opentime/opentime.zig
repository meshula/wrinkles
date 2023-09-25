//
// Exports for the `opentime` library
//

// interval @{
pub const interval = @import("interval.zig");
pub const ContinuousTimeInterval = interval.ContinuousTimeInterval;
// @}

// Domain @{
pub const Domain = @import("domain.zig").Domain;
// @}

// transform
pub const transform = @import("transform.zig");

pub const dual = @import("dual.zig");
pub const Dual_t = dual.Dual_t;

test "all opentime tests" {
    _ = interval;
    _ = Domain;
    _ = transform;
    _ = dual;
}
