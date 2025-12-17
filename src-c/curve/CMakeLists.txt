cmake_minimum_required(VERSION 3.17)

# Curve C Library
project(curve_c
    VERSION 0.1.0
    LANGUAGES C
    DESCRIPTION "Curve library - 2D bezier and linear curves (C port)"
)

# C17 standard
set(CMAKE_C_STANDARD 17)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS OFF)

# Compiler flags: all warnings, warnings are fatal
if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang")
    add_compile_options(
        -Wall -Wextra -Wpedantic -Werror
        -Wformat=2 -Wconversion -Wsign-conversion
        -Wdouble-promotion -Wcast-qual -Wcast-align
        -Wmissing-include-dirs -Wundef -Wshadow
    )
elseif(CMAKE_C_COMPILER_ID MATCHES "MSVC")
    add_compile_options(/W4 /WX)
endif()

# Curve library (header-only)
add_library(curve INTERFACE)
target_include_directories(curve INTERFACE
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}>
    $<INSTALL_INTERFACE:include>
)

# Link dependencies
target_link_libraries(curve INTERFACE opentime hodographs)

# Link math library on Unix-like systems
if(UNIX)
    target_link_libraries(curve INTERFACE m)
endif()

# Install headers
install(
    FILES
        control_point.h
        epsilon.h
        bezier_math.h
        linear_curve.h
        bezier_curve.h
        curve_lib.h
    DESTINATION include/curve
)

# Install library target
install(TARGETS curve
    EXPORT curveTargets
    INCLUDES DESTINATION include
)

install(EXPORT curveTargets
    FILE curveTargets.cmake
    NAMESPACE curve::
    DESTINATION lib/cmake/curve
)

# Enable testing
enable_testing()

# Test executables
add_executable(test_control_point tests/test_control_point.c)
target_link_libraries(test_control_point PRIVATE curve opentime)
target_include_directories(test_control_point PRIVATE ${CMAKE_SOURCE_DIR}/opentime/tests)

add_executable(test_bezier_math tests/test_bezier_math.c)
target_link_libraries(test_bezier_math PRIVATE curve opentime)
target_include_directories(test_bezier_math PRIVATE ${CMAKE_SOURCE_DIR}/opentime/tests)

add_executable(test_linear_curve tests/test_linear_curve.c)
target_link_libraries(test_linear_curve PRIVATE curve opentime)
target_include_directories(test_linear_curve PRIVATE ${CMAKE_SOURCE_DIR}/opentime/tests)

add_executable(test_bezier_curve tests/test_bezier_curve.c)
target_link_libraries(test_bezier_curve PRIVATE curve opentime)
target_include_directories(test_bezier_curve PRIVATE ${CMAKE_SOURCE_DIR}/opentime/tests)

# Register tests with CTest
add_test(NAME control_point_tests COMMAND test_control_point)
add_test(NAME bezier_math_tests COMMAND test_bezier_math)
add_test(NAME linear_curve_tests COMMAND test_linear_curve)
add_test(NAME bezier_curve_tests COMMAND test_bezier_curve)
