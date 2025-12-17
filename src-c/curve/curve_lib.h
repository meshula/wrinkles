// curve_lib.h - Main entry point for curve library
// Ported from src/curve/root.zig

#pragma once

#include "control_point.h"
#include "epsilon.h"
#include "bezier_math.h"
#include "linear_curve.h"
#include "bezier_curve.h"

// Note: Advanced bezier_curve features not yet ported:
// - Projection algorithms (project_segment, project_linear_curve)
// - Linearization (adaptive subdivision)
// - Critical point splitting (requires hodographs C library)
// - Three-point approximation
// - JSON I/O
