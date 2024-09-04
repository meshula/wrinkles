//! Ordinate type and support math for opentime

pub fn OrdinateOf(
    comptime t: type
) type
{
    return t;
}

/// ordinate type
pub const Ordinate = OrdinateOf(f32);
