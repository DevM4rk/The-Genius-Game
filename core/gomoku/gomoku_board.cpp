// gomoku_board.cpp
// GomokuBoard 구현부. 각 함수 위 주석은 "무슨 순서로 처리하는지"를 설명함.

#include "gomoku_board.h"

#include <cstdlib>

namespace {
// 패턴별 점수표. "열린 끝(open end)"이 양쪽 다 비어있으면 다음 수에 더 위협적이므로 훨씬 높은 점수.
// total>=5는 이미 승리 상태라 여기까지 오지 않지만 방어적으로 남겨둠.
constexpr int SCORE_FIVE = 100000;
constexpr int SCORE_OPEN_FOUR = 10000;    // 양끝 열린 4개 -> 다음 수에 거의 확정 승리
constexpr int SCORE_SIMPLE_FOUR = 5000;   // 한쪽만 열린 4개 -> 막지 않으면 승리
constexpr int SCORE_DEAD_FOUR = 50;       // 양끝 막힌 4개 -> 더 이상 위협 아님
constexpr int SCORE_OPEN_THREE = 1000;    // 양끝 열린 3개 -> 다음 수에 열린 4 위협
constexpr int SCORE_BLOCKED_THREE = 200;
constexpr int SCORE_DEAD_THREE = 10;
constexpr int SCORE_OPEN_TWO = 100;
constexpr int SCORE_BLOCKED_TWO = 20;
constexpr int SCORE_DEAD_TWO = 2;
constexpr int SCORE_SINGLE = 5;

// 방어 점수는 공격 점수보다 살짝 낮게 쳐서, 내가 이길 수 있는 상황에선 항상 공격을 우선한다.
constexpr double DEFENSE_WEIGHT = 0.9;
} // namespace

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

int GomokuBoard::score_axis(int x, int y, int dx, int dy, Stone stone) const {
    // (x, y)는 실제로는 비어있는 칸이지만, 여기에 stone을 놓았다고 가정하고 평가한다.
    // count_in_direction은 (x,y) 자신을 보지 않고 다음 칸부터 세므로 그대로 재사용 가능.
    int forward = count_in_direction(x, y, dx, dy, stone);
    int backward = count_in_direction(x, y, -dx, -dy, stone);
    int total = 1 + forward + backward;

    int fx = x + dx * (forward + 1);
    int fy = y + dy * (forward + 1);
    bool forward_open = is_in_bounds(fx, fy) && board[fy][fx] == Stone::NONE;

    int bx = x - dx * (backward + 1);
    int by = y - dy * (backward + 1);
    bool backward_open = is_in_bounds(bx, by) && board[by][bx] == Stone::NONE;

    int open_ends = (forward_open ? 1 : 0) + (backward_open ? 1 : 0);

    if (total >= 5) {
        return SCORE_FIVE;
    }
    if (total == 4) {
        if (open_ends == 2) return SCORE_OPEN_FOUR;
        if (open_ends == 1) return SCORE_SIMPLE_FOUR;
        return SCORE_DEAD_FOUR;
    }
    if (total == 3) {
        if (open_ends == 2) return SCORE_OPEN_THREE;
        if (open_ends == 1) return SCORE_BLOCKED_THREE;
        return SCORE_DEAD_THREE;
    }
    if (total == 2) {
        if (open_ends == 2) return SCORE_OPEN_TWO;
        if (open_ends == 1) return SCORE_BLOCKED_TWO;
        return SCORE_DEAD_TWO;
    }
    return SCORE_SINGLE;
}

int GomokuBoard::score_candidate(int x, int y, Stone stone) const {
    // 검사할 축은 4개(가로/세로/대각선 2개) - check_five_in_a_row와 동일한 축 구성.
    static const int axes[4][2] = { {1, 0}, {0, 1}, {1, 1}, {1, -1} };
    int total = 0;
    for (const auto& axis : axes) {
        total += score_axis(x, y, axis[0], axis[1], stone);
    }
    return total;
}

std::pair<int, int> GomokuBoard::suggest_move() const {
    constexpr int center = BOARD_SIZE / 2;

    // 1. 후보 좌표 수집: 기존 돌 주변(체비쇼프 거리 2 이내)의 빈 칸만 본다.
    //    보드 전체(15x15=225칸)를 매번 평가하면 느려질 뿐 아니라, 돌에서 먼 칸은 어차피
    //    의미있는 패턴 점수가 나올 수 없어서 후보에서 제외해도 결과가 같다.
    bool any_stone = false;
    std::array<std::array<bool, BOARD_SIZE>, BOARD_SIZE> is_candidate{};
    for (int y = 0; y < BOARD_SIZE; ++y) {
        for (int x = 0; x < BOARD_SIZE; ++x) {
            if (board[y][x] == Stone::NONE) {
                continue;
            }
            any_stone = true;
            for (int ny = y - 2; ny <= y + 2; ++ny) {
                for (int nx = x - 2; nx <= x + 2; ++nx) {
                    if (is_in_bounds(nx, ny) && board[ny][nx] == Stone::NONE) {
                        is_candidate[ny][nx] = true;
                    }
                }
            }
        }
    }

    // 2. 보드가 완전히 비어있으면(첫 수) 중앙이 이론상 최선이므로 바로 리턴.
    if (!any_stone) {
        return { center, center };
    }

    // 3. 후보 중 "공격 점수 + 방어 점수*가중치"가 최대인 좌표 선택.
    //    동점이면 중앙에 더 가까운 좌표를 우선해서, 초반에 형태가 흩어지지 않게 한다.
    Stone me = current_turn;
    Stone opp = (me == Stone::BLACK) ? Stone::WHITE : Stone::BLACK;

    int best_x = -1;
    int best_y = -1;
    double best_score = -1.0;

    for (int y = 0; y < BOARD_SIZE; ++y) {
        for (int x = 0; x < BOARD_SIZE; ++x) {
            if (!is_candidate[y][x]) {
                continue;
            }

            int my_score = score_candidate(x, y, me);
            int opp_score = score_candidate(x, y, opp);
            double total = static_cast<double>(my_score) + static_cast<double>(opp_score) * DEFENSE_WEIGHT;

            int dist = std::abs(x - center) + std::abs(y - center);
            total -= dist * 0.01; // tie-break용 미세 보정, 패턴 점수 차이를 뒤집지 않음

            if (total > best_score) {
                best_score = total;
                best_x = x;
                best_y = y;
            }
        }
    }

    return { best_x, best_y };
}
