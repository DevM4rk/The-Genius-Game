cmake_minimum_required(VERSION 3.20)
project(omok_core LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

add_library(omok_core STATIC
    src/board.cpp
    src/rules.cpp
    src/ai.cpp
)

target_include_directories(omok_core PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/include
)

option(OMOK_BUILD_TESTS "Build omok_core tests" ON)
if(OMOK_BUILD_TESTS)
    enable_testing()
    add_executable(omok_tests tests/test_rules.cpp)
    target_link_libraries(omok_tests PRIVATE omok_core)
    add_test(NAME omok_rules COMMAND omok_tests)
endif()
