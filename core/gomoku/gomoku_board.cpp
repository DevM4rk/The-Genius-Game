// gomoku_board.cpp
// GomokuBoard 구현부. 각 함수 위 주석은 "무슨 순서로 처리하는지"를 설명함.

#include "gomoku_board.h"

GomokuBoard::GomokuBoard() {
    reset();
}

void GomokuBoard::reset() {
    // board 전체를 NONE(0)으로 채움. NONE == 0 이라서 {{Stone::NONE}}으로 첫 칸만 지정해도
    // std::array 값초기화 규칙상 나머지 칸도 0(NONE)으로 채워짐.
    board.fill(std::array<Stone, BOARD_SIZE>{{Stone::NONE}});
    current_turn = Stone::BLACK; // 오목은 항상 흑이 선공
    state = GameState::PLAYING;
}

bool GomokuBoard::is_in_bounds(int x, int y) const {
    return x >= 0 && x < BOARD_SIZE && y >= 0 && y < BOARD_SIZE;
}

MoveResult GomokuBoard::place_stone(int x, int y) {
    // 착수 처리 순서:
    // 1. state가 PLAYING이 아니면 GAME_ALREADY_OVER 리턴
    if (state != GameState::PLAYING) {
        return MoveResult::GAME_ALREADY_OVER;
    }
    // 2. is_in_bounds 체크 -> 아니면 OUT_OF_BOUNDS 리턴
    if (!is_in_bounds(x, y)) {
        return MoveResult::OUT_OF_BOUNDS;
    }
    // 3. 이미 돌이 있으면 CELL_OCCUPIED 리턴
    if (board[y][x] != Stone::NONE) {
        return MoveResult::CELL_OCCUPIED;
    }
    // 4. board[y][x] = current_turn 으로 착수
    board[y][x] = current_turn;
    // 5. check_five_in_a_row(x, y, current_turn) -> true면 state를 BLACK_WIN/WHITE_WIN으로 설정
    if (check_five_in_a_row(x, y, current_turn)) {
        state = (current_turn == Stone::BLACK) ? GameState::BLACK_WIN : GameState::WHITE_WIN;
    }
    // 6. 승리가 아닐 때만 무승부 체크
    //    (수정: 원래 무조건 체크해서 "마지막 칸에 둬서 이긴 경우" WIN이 DRAW로 덮어써지는 버그가 있었음
    //     -> else if로 승리와 무승부가 동시에 겹칠 때 승리를 우선하도록 함)
    else if (is_board_full()) {
        state = GameState::DRAW;
    }
    // 7. 게임이 안 끝났을 때만 턴 전환
    //    (수정: 원래 무조건 switch_turn()을 호출해서 승리/무승부 이후에도 턴이 넘어가는 버그가 있었음
    //     -> get_current_turn()이 게임 종료 후에도 정확한 값을 유지하도록 조건 추가)
    if (state == GameState::PLAYING) {
        switch_turn();
    }
    // 8. OK 리턴
    return MoveResult::OK;
}

Stone GomokuBoard::get_stone(int x, int y) const {
    // 범위 밖 좌표는 예외 던지지 않고 NONE으로 처리 (호출부에서 매번 bounds 체크 안 해도 되게)
    if (!is_in_bounds(x, y)) {
        return Stone::NONE;
    }
    return board[y][x];
}

bool GomokuBoard::check_five_in_a_row(int x, int y, Stone stone) const {
    // 검사할 축은 4개뿐 (가로 / 세로 / 대각선 \ / 대각선 /).
    // (수정: 원래 8방향 전체를 돌면서 count를 리셋 없이 계속 누적시켜서
    //  1) 가로(1,0)와 (-1,0)이 같은 축인데 두 번 더해지고
    //  2) 서로 관련 없는 방향(가로+세로+대각선)의 개수가 섞여서 합산되는 버그가 있었음
    //  -> 축 4개로 줄이고, 축마다 total을 새로 계산하도록 수정)
    static const int axes[4][2] = { {1, 0}, {0, 1}, {1, 1}, {1, -1} };

    for (const auto& axis : axes) {
        int dx = axis[0];
        int dy = axis[1];
        // 이 축의 총 연속 개수 = 자기 자신(1) + 정방향 개수 + 역방향 개수
        int total = 1 + count_in_direction(x, y, dx, dy, stone)
                      + count_in_direction(x, y, -dx, -dy, stone);
        if (total >= 5) {
            return true;
        }
    }
    return false;
}

int GomokuBoard::count_in_direction(int x, int y, int dx, int dy, Stone stone) const {
    // (x, y) 자기 자신은 포함하지 않고, (x+dx, y+dy)부터 시작해서
    // 같은 stone이 계속 이어지는 동안만 카운트. 범위 밖이거나 다른 돌/빈칸이면 즉시 중단.
    int count = 0;
    while (is_in_bounds(x + dx, y + dy) && board[y + dy][x + dx] == stone) {
        count++;
        x += dx;
        y += dy;
    }
    return count;
}

bool GomokuBoard::is_board_full() const {
    // 전체 순회하다가 NONE을 하나라도 만나면 바로 false (조기 종료로 불필요한 순회 방지)
    for (const auto& row : board) {
        for (const auto& stone : row) {
            if (stone == Stone::NONE) {
                return false;
            }
        }
    }
    return true;
}

void GomokuBoard::switch_turn() {
    current_turn = current_turn == Stone::BLACK ? Stone::WHITE : Stone::BLACK;
}
