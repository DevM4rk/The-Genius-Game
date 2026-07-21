#pragma once

#include "omok/board.hpp"

namespace omok {

enum class Outcome { None, BlackWin, WhiteWin, Draw, Illegal };

struct MoveResult {
    Outcome outcome = Outcome::None;
    bool accepted = false;
};

/// Apply move with win / (optional) renju forbidden-check.
MoveResult apply_move(Board& board, int x, int y, Ruleset ruleset = Ruleset::Freestyle);

bool is_five(const Board& board, int x, int y, Stone stone);

/// Renju black forbidden moves — stub returns false until Phase 1.
bool is_forbidden(const Board& board, int x, int y);

}  // namespace omok
