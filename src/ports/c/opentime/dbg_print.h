// dbg_print.h - Debug print utility with compile-time switch
// Ported from src/opentime/dbg_print.zig

#pragma once

#include <stdio.h>

// Debug message flag - set to 1 to enable debug prints, 0 to disable
#ifndef OPENTIME_DEBUG_MESSAGES
#define OPENTIME_DEBUG_MESSAGES 0
#endif

// Debug print macro that includes file, function, and line information
#define opentime_dbg_print(fmt, ...) \
    do { \
        if (OPENTIME_DEBUG_MESSAGES) { \
            fprintf(stderr, "[%s:%s:%d] " fmt "\n", \
                    __FILE__, __func__, __LINE__, ##__VA_ARGS__); \
        } \
    } while(0)
