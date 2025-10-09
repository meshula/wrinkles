
const opentime = @import("opentime");

// TEST STRUCTS
pub const T_INT_1_TO_9 = opentime.ContinuousInterval{
    .start = .ONE,
    .end = opentime.Ordinate.init(9),
};
pub const T_INT_1_TO_4 = opentime.ContinuousInterval{
    .start = .ONE,
    .end = opentime.Ordinate.init(4),
};
pub const T_INT_0_TO_2 = opentime.ContinuousInterval{
    .start = .ZERO,
    .end = opentime.Ordinate.init(2),
};

pub const T_O_0 = opentime.Ordinate.ZERO;
pub const T_O_2 = opentime.Ordinate.init(2);
pub const T_O_4 = opentime.Ordinate.init(4);
pub const T_O_6 = opentime.Ordinate.init(6);

pub const T_ORD_ARR_0_8_16_21 = [_]opentime.Ordinate{
            .ZERO,
            opentime.Ordinate.init(8),
            opentime.Ordinate.init(16),
            opentime.Ordinate.init(21),
};
pub const T_ORD_ARR_0_8_13_21 = [_]opentime.Ordinate{
            .ZERO,
            opentime.Ordinate.init(8),
            opentime.Ordinate.init(13),
            opentime.Ordinate.init(21),
};

