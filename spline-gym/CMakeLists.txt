cmake_minimum_required(VERSION 3.10)

project(bezier_spline_visualizer)

set(CMAKE_CXX_STANDARD 11)

#add_subdirectory(external/motive)
add_subdirectory(external/raylib)

add_executable(bezier_spline_visualizer src/main.cpp)

target_link_libraries(bezier_spline_visualizer raylib)
