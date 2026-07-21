// register_types.h
// Godot가 이 GDExtension을 로드/해제할 때 호출하는 진입점 선언.

#pragma once

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

void initialize_gomoku_module(ModuleInitializationLevel p_level);
void uninitialize_gomoku_module(ModuleInitializationLevel p_level);
