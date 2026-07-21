// register_types.cpp
// 순서:
// 1) initialize_gomoku_module: Godot 로드 시 우리 클래스(GomokuBoardExt)를 ClassDB에 등록
//    -> 이걸 해야 GDScript에서 GomokuBoardExt.new()로 생성 가능해짐
// 2) gomoku_library_init: Godot가 .dll을 로드할 때 실제로 호출하는 최초 진입점
//    (.gdextension 파일의 entry_symbol과 이름이 반드시 일치해야 함)

#include "register_types.h"

#include <gdextension_interface.h>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

#include "gomoku_board_ext.h"

using namespace godot;

void initialize_gomoku_module(ModuleInitializationLevel p_level) {
    if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
        return;
    }
    GDREGISTER_CLASS(GomokuBoardExt);
}

void uninitialize_gomoku_module(ModuleInitializationLevel p_level) {
    if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
        return;
    }
}

extern "C" {
GDExtensionBool GDE_EXPORT gomoku_library_init(
        GDExtensionInterfaceGetProcAddress p_get_proc_address,
        GDExtensionClassLibraryPtr p_library,
        GDExtensionInitialization *r_initialization) {
    godot::GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);

    init_obj.register_initializer(initialize_gomoku_module);
    init_obj.register_terminator(uninitialize_gomoku_module);
    init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);

    return init_obj.init();
}
}
