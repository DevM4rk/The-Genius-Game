// gomoku_board_ext.h
//
// 이 클래스는 "순수 C++ 오목 로직(GomokuBoard)"을 Godot에 노출하는 얇은 래퍼임.
// 실제 규칙/판정은 전부 core/gomoku/gomoku_board.h,cpp 안에 있고,
// 여긴 그 함수들을 그대로 호출해서 결과를 int로 바꿔주기만 함 (Godot 바인딩은 기본 타입만 다루기 쉬워서).

#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/vector2i.hpp>

#include "../../gomoku/gomoku_board.h"

namespace godot {

class GomokuBoardExt : public RefCounted {
    GDCLASS(GomokuBoardExt, RefCounted)

private:
    GomokuBoard board;

protected:
    // Godot에 메서드/상수를 등록하는 곳. GomokuBoardExt.cpp에서 구현.
    static void _bind_methods();

public:
    // GDScript에서 GomokuBoardExt.new()로 이 상수 그대로 쓸 수 있게 노출.
    // 값은 gomoku_board.h의 enum과 반드시 같아야 함 (아래 함수들이 static_cast<int>로 그대로 리턴하기 때문).
    enum {
        // Stone
        STONE_NONE = 0,
        STONE_BLACK = 1,
        STONE_WHITE = 2,
        // MoveResult
        MOVE_OK = 0,
        MOVE_OUT_OF_BOUNDS = 1,
        MOVE_CELL_OCCUPIED = 2,
        MOVE_GAME_ALREADY_OVER = 3,
        // GameState
        STATE_PLAYING = 0,
        STATE_BLACK_WIN = 1,
        STATE_WHITE_WIN = 2,
        STATE_DRAW = 3,
    };

    GomokuBoardExt();

    void reset();

    // (x, y)에 착수 시도 -> MOVE_* 상수 리턴
    int place_stone(int x, int y);

    // (x, y)의 돌 상태 -> STONE_* 상수 리턴
    int get_stone(int x, int y) const;

    // 지금 차례 -> STONE_BLACK / STONE_WHITE
    int get_current_turn() const;

    // 게임 진행 상태 -> STATE_* 상수 리턴
    int get_state() const;

    // 규칙 기반 AI 착수 추천 (현재 차례 기준). 후보가 없으면 Vector2i(-1, -1).
    Vector2i suggest_move() const;
};

} // namespace godot
