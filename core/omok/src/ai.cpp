#include "omok/ai.hpp"

#include <limits>
#include <vector>

namespace omok {

Ai::Ai(int strength) : strength_(strength < 0 ? 0 : strength) {}

std::optional<Coord> Ai::choose_move(const Board& board) const {
    // Phase 0 stub: first empty cell near center, expanding outward.
    // Phase 1: replace with pattern scoring + iterative deepening.
    static constexpr int ORDER[] = {7, 6, 8, 5, 9, 4, 10, 3, 11, 2, 12, 1, 13, 0, 14};
    for (int yi = 0; yi < BOARD_SIZE; ++yi) {
        for (int xi = 0; xi < BOARD_SIZE; ++xi) {
            const int x = ORDER[xi];
            const int y = ORDER[yi];
            if (board.can_place(x, y)) {
                (void)strength_;
                return Coord{x, y};
            }
        }
    }
    return std::nullopt;
}

}  // namespace omok
