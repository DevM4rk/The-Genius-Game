#include "omok/board.hpp"

namespace omok {

Board::Board() { reset(); }

void Board::reset() {
    cells_.fill(Stone::Empty);
    turn_ = Stone::Black;
    move_count_ = 0;
}

Stone Board::at(int x, int y) const {
    if (!in_bounds(x, y)) {
        return Stone::Empty;
    }
    return cells_[static_cast<size_t>(index(x, y))];
}

bool Board::can_place(int x, int y) const {
    return in_bounds(x, y) && at(x, y) == Stone::Empty;
}

bool Board::place(int x, int y, Stone stone) {
    if (!can_place(x, y) || stone == Stone::Empty) {
        return false;
    }
    cells_[static_cast<size_t>(index(x, y))] = stone;
    ++move_count_;
    turn_ = (stone == Stone::Black) ? Stone::White : Stone::Black;
    return true;
}

}  // namespace omok
