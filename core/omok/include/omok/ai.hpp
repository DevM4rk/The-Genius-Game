#pragma once

#include "omok/board.hpp"
#include <optional>

namespace omok {

/// Offline AI — runs entirely in the browser via GDExtension (no server).
class Ai {
public:
    explicit Ai(int strength = 1);

    /// Returns best coord for the side to move, or nullopt if board full.
    std::optional<Coord> choose_move(const Board& board) const;

private:
    int strength_;
};

}  // namespace omok
