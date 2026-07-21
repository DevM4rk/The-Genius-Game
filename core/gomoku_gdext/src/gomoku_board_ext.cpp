// gomoku_board_ext.cpp
// 순서: 1) 메서드/상수 바인딩(_bind_methods)  2) 각 메서드는 GomokuBoard를 그대로 호출

#include "gomoku_board_ext.h"

#include <godot_cpp/core/class_db.hpp>

using namespace godot;

GomokuBoardExt::GomokuBoardExt() {
    // GomokuBoard 생성자가 이미 reset()을 호출하므로 여기선 할 일 없음
}

void GomokuBoardExt::reset() {
    board.reset();
}

int GomokuBoardExt::place_stone(int x, int y) {
    return static_cast<int>(board.place_stone(x, y));
}

int GomokuBoardExt::get_stone(int x, int y) const {
    return static_cast<int>(board.get_stone(x, y));
}

int GomokuBoardExt::get_current_turn() const {
    return static_cast<int>(board.get_current_turn());
}

int GomokuBoardExt::get_state() const {
    return static_cast<int>(board.get_state());
}

void GomokuBoardExt::_bind_methods() {
    // GDScript에서 호출할 메서드 등록
    ClassDB::bind_method(D_METHOD("reset"), &GomokuBoardExt::reset);
    ClassDB::bind_method(D_METHOD("place_stone", "x", "y"), &GomokuBoardExt::place_stone);
    ClassDB::bind_method(D_METHOD("get_stone", "x", "y"), &GomokuBoardExt::get_stone);
    ClassDB::bind_method(D_METHOD("get_current_turn"), &GomokuBoardExt::get_current_turn);
    ClassDB::bind_method(D_METHOD("get_state"), &GomokuBoardExt::get_state);

    // GDScript에서 매직 넘버 대신 GomokuBoardExt.STONE_BLACK 이런 식으로 쓸 수 있게 상수 등록
    BIND_CONSTANT(STONE_NONE);
    BIND_CONSTANT(STONE_BLACK);
    BIND_CONSTANT(STONE_WHITE);

    BIND_CONSTANT(MOVE_OK);
    BIND_CONSTANT(MOVE_OUT_OF_BOUNDS);
    BIND_CONSTANT(MOVE_CELL_OCCUPIED);
    BIND_CONSTANT(MOVE_GAME_ALREADY_OVER);

    BIND_CONSTANT(STATE_PLAYING);
    BIND_CONSTANT(STATE_BLACK_WIN);
    BIND_CONSTANT(STATE_WHITE_WIN);
    BIND_CONSTANT(STATE_DRAW);
}
