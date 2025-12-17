cmake_minimum_required(VERSION 3.17)

project(wrinkles_c
    VERSION 0.1.0
    LANGUAGES C
    DESCRIPTION "Wrinkles C port - time math and topology for multimedia applications"
)

# C17 standard
set(CMAKE_C_STANDARD 17)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS OFF)

# Enable testing at top level
enable_testing()

# Add subdirectories
add_subdirectory(opentime)
add_subdirectory(treecode)
add_subdirectory(hodographs)
add_subdirectory(curve)
