// test_gomoku_board.cpp
// Godot/GDExtension 없이 콘솔에서 GomokuBoard 로직만 테스트하는 용도.
// 필요할 때마다 케이스를 자유롭게 추가하세요.

#include "../gomoku_board.h"
#include <cassert>
#include <iostream>

static void print_result(const char* name, bool passed) {
    std::cout << (passed ? "[PASS] " : "[FAIL] ") << name << std::endl;
}

int main() {
    // 1. 초기 상태 확인
    {
        GomokuBoard bd;
        bool ok = bd.get_current_turn() == Stone::BLACK
               && bd.get_state() == GameState::PLAYING
               && bd.get_stone(0, 0) == Stone::NONE;
        print_result("initial_state", ok);
    }

    // 2. 정상 착수 + 턴 전환 확인
    {
        GomokuBoard bd;
        MoveResult r = bd.place_stone(7, 7);
        bool ok = r == MoveResult::OK
               && bd.get_stone(7, 7) == Stone::BLACK
               && bd.get_current_turn() == Stone::WHITE;
        print_result("place_stone_basic", ok);
    }

    // 3. 중복 착수 방지 확인
    {
        GomokuBoard bd;
        bd.place_stone(3, 3);
        MoveResult r = bd.place_stone(3, 3);
        print_result("cell_occupied_rejected", r == MoveResult::CELL_OCCUPIED);
    }

    // 4. 보드 밖 좌표 확인
    {
        GomokuBoard bd;
        MoveResult r = bd.place_stone(-1, 20);
        print_result("out_of_bounds_rejected", r == MoveResult::OUT_OF_BOUNDS);
    }

    // 5. 가로 5목 승리 확인 (Black이 (0,0)~(4,0)에 착수)
    {
        GomokuBoard bd;
        // Black, White가 번갈아 두므로 White는 관련없는 자리에 둠
        bd.place_stone(0, 0); // Black
        bd.place_stone(0, 1); // White
        bd.place_stone(1, 0); // Black
        bd.place_stone(1, 1); // White
        bd.place_stone(2, 0); // Black
        bd.place_stone(2, 1); // White
        bd.place_stone(3, 0); // Black
        bd.place_stone(3, 1); // White
        bd.place_stone(4, 0); // Black -> 5목 완성
        print_result("horizontal_five_win", bd.get_state() == GameState::BLACK_WIN);
    }

    std::cout << "Done." << std::endl;
    return 0;
}
