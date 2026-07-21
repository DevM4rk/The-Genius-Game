#include "omok/rules.hpp"

namespace omok {
namespace {

int count_dir(const Board& board, int x, int y, int dx, int dy, Stone stone) {
    int n = 0;
    int cx = x + dx;
    int cy = y + dy;
    while (in_bounds(cx, cy) && board.at(cx, cy) == stone) {
        ++n;
        cx += dx;
        cy += dy;
    }
    return n;
}

}  // namespace

bool is_five(const Board& board, int x, int y, Stone stone) {
    static constexpr int DIRS[4][2] = {{1, 0}, {0, 1}, {1, 1}, {1, -1}};
    for (const auto& d : DIRS) {
        const int total = 1 + count_dir(board, x, y, d[0], d[1], stone) +
                          count_dir(board, x, y, -d[0], -d[1], stone);
        if (total >= 5) {
            return true;
        }
    }
    return false;
}

bool is_forbidden(const Board& /*board*/, int /*x*/, int /*y*/) {
    // TODO Phase 1: double-three / double-four / overline for Renju black.
    return false;
}

MoveResult apply_move(Board& board, int x, int y, Ruleset ruleset) {
    MoveResult result;
    const Stone stone = board.turn();
    if (!board.can_place(x, y)) {
        result.outcome = Outcome::Illegal;
        return result;
    }
    if (ruleset == Ruleset::Renju && stone == Stone::Black && is_forbidden(board, x, y)) {
        result.outcome = Outcome::Illegal;
        return result;
    }
    board.place(x, y, stone);
    result.accepted = true;
    if (is_five(board, x, y, stone)) {
        result.outcome = (stone == Stone::Black) ? Outcome::BlackWin : Outcome::WhiteWin;
    } else if (board.move_count() >= CELL_COUNT) {
        result.outcome = Outcome::Draw;
    }
    return result;
}

}  // namespace omok
