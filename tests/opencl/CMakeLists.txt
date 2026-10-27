cmake_minimum_required(VERSION 3.20)
project(arc_a770_opencl_harness CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

add_compile_options(-Wall -Wextra -Wpedantic)

# OpenCL is required to BUILD the full harness. If the headers/loader are not present
# (e.g. a bare scaffolding host), configure with -DARC_REQUIRE_OPENCL=OFF to skip it.
option(ARC_REQUIRE_OPENCL "Require the OpenCL loader to build the harness" ON)

find_package(OpenCL QUIET)

if(OpenCL_FOUND)
  add_executable(large_buffer large_buffer.cpp)
  target_link_libraries(large_buffer PRIVATE OpenCL::OpenCL)
  target_include_directories(large_buffer PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
  message(STATUS "OpenCL found: building large_buffer harness.")
elseif(ARC_REQUIRE_OPENCL)
  message(FATAL_ERROR
    "OpenCL not found. Install an OpenCL ICD loader + headers, or reconfigure with "
    "-DARC_REQUIRE_OPENCL=OFF to skip the harness on a scaffolding host.")
else()
  message(STATUS "OpenCL not found; skipping harness (ARC_REQUIRE_OPENCL=OFF).")
endif()

# Oracle self-check always builds — it has no OpenCL dependency and is CI-green offline.
add_executable(oracle_selfcheck oracle_selfcheck.cpp)
target_include_directories(oracle_selfcheck PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})

enable_testing()
add_test(NAME oracle_selfcheck COMMAND oracle_selfcheck)
