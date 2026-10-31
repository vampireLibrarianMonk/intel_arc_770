cmake_minimum_required(VERSION 3.20)
project(arc_a770_l0_probe CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
add_compile_options(-Wall -Wextra -O2)

find_library(ZE_LOADER ze_loader)
find_path(ZE_INCLUDE level_zero/ze_api.h)

if(ZE_LOADER AND ZE_INCLUDE)
  add_executable(l0_large_buffer l0_large_buffer.cpp)
  target_include_directories(l0_large_buffer PRIVATE ${ZE_INCLUDE})
  target_link_libraries(l0_large_buffer PRIVATE ${ZE_LOADER})
  message(STATUS "Level Zero found: building l0_large_buffer.")
else()
  message(FATAL_ERROR "Level Zero loader/headers not found. Install libze-dev.")
endif()
