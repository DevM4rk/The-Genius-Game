// gomoku_board.h
// 순수 C++ - Godot 헤더 include 없음 (의도적으로 분리)
// 자유오목(금수 없음) 기준. Phase 1: 로컬 2인 대전용 핵심 로직.

#pragma once
#include <array>
#include <cstdint>
#include <utility>

enum class Stone : uint8_t {
    NONE  = 0,
    BLACK = 1,
    WHITE = 2
};

enum class MoveResult : uint8_t {
    OK,                 // 정상적으로 착수됨
    OUT_OF_BOUNDS,      // 보드 밖 좌표
    CELL_OCCUPIED,      // 이미 돌이 있음
    GAME_ALREADY_OVER   // 이미 게임이 끝난 상태에서 착수 시도
};

enum class GameState : uint8_t {
    PLAYING,
    BLACK_WIN,
    WHITE_WIN,
    DRAW
};

class GomokuBoard {
public:
    static constexpr int BOARD_SIZE = 15;

    GomokuBoard();

    // 초기화 (재시작용)
    void reset();

    // 핵심 진입점: (x, y)에 현재 턴 플레이어가 착수 시도
    // 성공 시 내부적으로 턴 전환 + 승패 판정까지 수행
    MoveResult place_stone(int x, int y);

    // 조회용 (읽기 전용)
    Stone get_stone(int x, int y) const;
    Stone get_current_turn() const { return current_turn; }
    GameState get_state() const { return state; }

    // 규칙 기반 AI: 현재 차례(current_turn) 기준으로 다음 착수 좌표를 추천.
    // 미니맥스/탐색 없이 1수 앞만 평가하는 휴리스틱(공격 점수 + 방어 점수)이라
    // 즉시 이기는 수/막아야 하는 수는 잘 찾지만 장기 전략은 없음.
    // 보드가 비어있으면 중앙을 리턴. 후보가 없으면 {-1, -1} 리턴(보드가 가득 찬 경우).
    std::pair<int, int> suggest_move() const;

private:
    // board[y][x] 형태로 저장 (2차원 배열)
    std::array<std::array<Stone, BOARD_SIZE>, BOARD_SIZE> board;

    Stone current_turn;
    GameState state;

    // 좌표 유효성만 체크 (범위 밖인지)
    bool is_in_bounds(int x, int y) const;

    // 방금 놓인 자리 (x, y) 기준으로 5목 완성됐는지 검사
    // 4개 축(가로/세로/대각선 2개)만 검사하면 충분 - 전체 보드 스캔 불필요
    bool check_five_in_a_row(int x, int y, Stone stone) const;

    // (x, y)에서 (dx, dy) 방향으로 같은 돌이 몇 개 연속되는지 카운트 (자기 자신 제외)
    // check_five_in_a_row 내부에서 각 축마다 양방향으로 두 번 호출해서 합산
    int count_in_direction(int x, int y, int dx, int dy, Stone stone) const;

    // 무승부(보드 다 찼는지) 체크
    bool is_board_full() const;

    void switch_turn();

    // (x, y)가 비어있다고 가정하고 거기에 stone을 놓았을 때 4축 패턴 점수를 합산.
    // suggest_move()의 후보 평가에서 공격 점수(내 돌 기준)/방어 점수(상대 돌 기준) 계산에 재사용.
    int score_candidate(int x, int y, Stone stone) const;

    // 한 축(dx, dy)에서 (x, y)에 stone을 놓았을 때: 연속 개수 + 열린 끝 개수를 보고 점수 리턴.
    int score_axis(int x, int y, int dx, int dy, Stone stone) const;
};
