# Phase 1 전용: Godot/GDExtension 없이 core 로직만 빌드/테스트하기 위한 CMake.
# 나중에 GDExtension을 붙일 때는 이 파일 대신 godot-cpp 기반 빌드로 교체합니다.

cmake_minimum_required(VERSION 3.16)
project(gomoku_core CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_executable(test_gomoku_board
    gomoku_board.cpp
    tests/test_gomoku_board.cpp
)
