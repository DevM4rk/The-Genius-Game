#include "omok/board.hpp"
#include "omok/rules.hpp"

#include <cstdio>

static int failures = 0;

#define EXPECT(cond)                                                                             \
    do {                                                                                         \
        if (!(cond)) {                                                                           \
            std::fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond);                 \
            ++failures;                                                                          \
        }                                                                                        \
    } while (0)

int main() {
    using namespace omok;

    Board board;
    for (int x = 0; x < 4; ++x) {
        EXPECT(apply_move(board, x, 7).accepted);
        EXPECT(apply_move(board, x, 8).accepted);  // white replies
    }
    auto last = apply_move(board, 4, 7);
    EXPECT(last.accepted);
    EXPECT(last.outcome == Outcome::BlackWin);

    Board full;
    // Illegal: out of turn place already filled — place black then try same cell.
    EXPECT(apply_move(full, 0, 0).accepted);
    auto illegal = apply_move(full, 0, 0);
    EXPECT(!illegal.accepted);
    EXPECT(illegal.outcome == Outcome::Illegal);

    if (failures == 0) {
        std::puts("omok_tests OK");
        return 0;
    }
    std::fprintf(stderr, "%d failure(s)\n", failures);
    return 1;
}
