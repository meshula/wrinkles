cmake_minimum_required(VERSION 3.17)

# Hodographs C Library
project(hodographs_c
    VERSION 1.0.0
    LANGUAGES C
    DESCRIPTION "Hodograph computation for Bezier curves"
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

# Hodographs library
add_library(hodographs STATIC
    hodographs.c
)

target_include_directories(hodographs PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}>
    $<INSTALL_INTERFACE:include>
)

# Link math library on Unix-like systems
if(UNIX)
    target_link_libraries(hodographs PUBLIC m)
endif()

# Install headers
install(
    FILES
        hodographs.h
    DESTINATION include/hodographs
)

# Install library target
install(TARGETS hodographs
    EXPORT hodographsTargets
    ARCHIVE DESTINATION lib
    LIBRARY DESTINATION lib
    RUNTIME DESTINATION bin
    INCLUDES DESTINATION include
)

install(EXPORT hodographsTargets
    FILE hodographsTargets.cmake
    NAMESPACE hodographs::
    DESTINATION lib/cmake/hodographs
)
