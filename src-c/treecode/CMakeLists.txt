cmake_minimum_required(VERSION 3.17)

# Treecode C Library
project(treecode_c
    VERSION 0.1.0
    LANGUAGES C
    DESCRIPTION "Treecode library - binary tree path encoding (C port)"
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

# Treecode library (header-only)
add_library(treecode INTERFACE)
target_include_directories(treecode INTERFACE
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}>
    $<INSTALL_INTERFACE:include>
)

# Link math library on Unix-like systems (not needed for treecode, but for consistency)
if(UNIX)
    target_link_libraries(treecode INTERFACE m)
endif()

# Install headers
install(
    FILES
        treecode.h
        binary_tree.h
        treecode_lib.h
    DESTINATION include/treecode
)

# Install library target
install(TARGETS treecode
    EXPORT treecodeTargets
    INCLUDES DESTINATION include
)

install(EXPORT treecodeTargets
    FILE treecodeTargets.cmake
    NAMESPACE treecode::
    DESTINATION lib/cmake/treecode
)

# Enable testing
enable_testing()

# Test executables
add_executable(test_treecode tests/test_treecode.c)
target_link_libraries(test_treecode PRIVATE treecode)
# Need to add the opentime tests directory for test_harness.h
target_include_directories(test_treecode PRIVATE ${CMAKE_SOURCE_DIR}/opentime/tests)

add_executable(test_binary_tree tests/test_binary_tree.c)
target_link_libraries(test_binary_tree PRIVATE treecode)
target_include_directories(test_binary_tree PRIVATE ${CMAKE_SOURCE_DIR}/opentime/tests)

# Register tests with CTest
add_test(NAME treecode_tests COMMAND test_treecode)
add_test(NAME binary_tree_tests COMMAND test_binary_tree)
