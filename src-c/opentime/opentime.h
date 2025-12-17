// opentime.h - Main header for the opentime library (C port)
// Ported from src/opentime/root.zig
//
// The opentime library has tools for dealing with points, intervals and
// affine transforms in a continuous 1d metric space.
//
// It also has some tools for doing dual-arithmetic based implicit
// differentiation.

#pragma once

// Core utilities
#include "util.h"

// Ordinate type and operations
#include "ordinate.h"

// Interval type and operations
#include "interval.h"

// Affine transform type and operations
#include "transform.h"

// Linear interpolation functions
#include "lerp.h"

// Projection result type
#include "projection_result.h"

// Dual numbers for automatic differentiation
#include "dual.h"

// Debug printing utilities
#include "dbg_print.h"

// Version information
#define OPENTIME_VERSION_MAJOR 0
#define OPENTIME_VERSION_MINOR 1
#define OPENTIME_VERSION_PATCH 0
