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

test "all opentime tests" {
    _ = interval;
    _ = Domain;
    _ = transform;
}
