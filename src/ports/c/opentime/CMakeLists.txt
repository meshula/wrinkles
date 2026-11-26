cmake_minimum_required(VERSION 3.17)

# OpenTime C Library
project(opentime_c
    VERSION 0.1.0
    LANGUAGES C
    DESCRIPTION "OpenTime library - continuous 1D metric space tools (C port)"
)

# C17 standard
set(CMAKE_C_STANDARD 17)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS OFF)

# All warnings, warnings are fatal
if(MSVC)
    add_compile_options(/W4 /WX)
else()
    add_compile_options(-Wall -Wextra -Wpedantic -Werror)
endif()

# Header-only library interface
add_library(opentime INTERFACE)
target_include_directories(opentime INTERFACE
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}>
    $<INSTALL_INTERFACE:include>
)

# Link math library (required for sqrt, cos, etc.)
target_link_libraries(opentime INTERFACE m)

# Installation
install(TARGETS opentime
    EXPORT opentimeTargets
    INCLUDES DESTINATION include
)

install(FILES
    opentime.h
    util.h
    ordinate.h
    interval.h
    transform.h
    lerp.h
    projection_result.h
    dual.h
    dbg_print.h
    DESTINATION include/opentime
)

# Export targets
install(EXPORT opentimeTargets
    FILE opentimeTargets.cmake
    NAMESPACE opentime::
    DESTINATION lib/cmake/opentime
)

# Enable testing
enable_testing()

# Test executables
add_executable(test_ordinate tests/test_ordinate.c)
target_link_libraries(test_ordinate opentime)

add_executable(test_interval tests/test_interval.c)
target_link_libraries(test_interval opentime)

add_executable(test_transform tests/test_transform.c)
target_link_libraries(test_transform opentime)

# Register tests with CTest
add_test(NAME test_ordinate COMMAND test_ordinate)
add_test(NAME test_interval COMMAND test_interval)
add_test(NAME test_transform COMMAND test_transform)
