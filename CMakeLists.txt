cmake_minimum_required(VERSION 3.18)
project(GeoEdge LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Optimization and SIMD flags
if(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
    add_compile_options(
        -O3
        -march=native
        -mavx2
        -mfma
        -fopenmp
        -Wall
        -Wextra
        -fPIC
    )
    add_link_options(-fopenmp)
endif()

# Find pybind11
find_package(pybind11 REQUIRED)

include_directories(
    src/cpp/include
)

pybind11_add_module(geoedge_core
    src/bindings/pybind_wrapper.cpp
    src/cpp/canny_core.cpp
)

target_include_directories(geoedge_core PRIVATE src/cpp/include)

# Install location
install(TARGETS geoedge_core DESTINATION ${CMAKE_CURRENT_SOURCE_DIR}/src/python)
