#pragma once

#include <array>
#include <cstdint>
#include <optional>
#include <vector>

namespace omok {

constexpr int BOARD_SIZE = 15;
constexpr int CELL_COUNT = BOARD_SIZE * BOARD_SIZE;

enum class Stone : uint8_t { Empty = 0, Black = 1, White = 2 };

enum class Ruleset { Freestyle, Renju };

struct Coord {
    int x = 0;
    int y = 0;
};

inline int index(int x, int y) { return y * BOARD_SIZE + x; }

inline bool in_bounds(int x, int y) {
    return x >= 0 && x < BOARD_SIZE && y >= 0 && y < BOARD_SIZE;
}

class Board {
public:
    Board();

    void reset();
    Stone at(int x, int y) const;
    bool can_place(int x, int y) const;
    bool place(int x, int y, Stone stone);

    Stone turn() const { return turn_; }
    void set_turn(Stone s) { turn_ = s; }
    int move_count() const { return move_count_; }

    const std::array<Stone, CELL_COUNT>& cells() const { return cells_; }

private:
    std::array<Stone, CELL_COUNT> cells_{};
    Stone turn_ = Stone::Black;
    int move_count_ = 0;
};

}  // namespace omok
