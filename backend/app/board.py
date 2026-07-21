"""순수 Python 오목 보드 — C++ GomokuBoard와 동일 규칙(자유오목, 금수 없음)."""

from __future__ import annotations

from enum import IntEnum


class Stone(IntEnum):
    NONE = 0
    BLACK = 1
    WHITE = 2


class MoveResult(IntEnum):
    OK = 0
    OUT_OF_BOUNDS = 1
    CELL_OCCUPIED = 2
    GAME_ALREADY_OVER = 3


class GameState(IntEnum):
    PLAYING = 0
    BLACK_WIN = 1
    WHITE_WIN = 2
    DRAW = 3


class GomokuBoard:
    BOARD_SIZE = 15

    def __init__(self) -> None:
        self.reset()

    def reset(self) -> None:
        n = self.BOARD_SIZE
        self.board: list[list[Stone]] = [[Stone.NONE] * n for _ in range(n)]
        self.current_turn = Stone.BLACK
        self.state = GameState.PLAYING

    def is_in_bounds(self, x: int, y: int) -> bool:
        return 0 <= x < self.BOARD_SIZE and 0 <= y < self.BOARD_SIZE

    def place_stone(self, x: int, y: int) -> MoveResult:
        if self.state != GameState.PLAYING:
            return MoveResult.GAME_ALREADY_OVER
        if not self.is_in_bounds(x, y):
            return MoveResult.OUT_OF_BOUNDS
        if self.board[y][x] != Stone.NONE:
            return MoveResult.CELL_OCCUPIED

        placed = self.current_turn
        self.board[y][x] = placed

        if self._check_five_in_a_row(x, y, placed):
            self.state = (
                GameState.BLACK_WIN if placed == Stone.BLACK else GameState.WHITE_WIN
            )
        elif self._is_board_full():
            self.state = GameState.DRAW
        else:
            self._switch_turn()

        return MoveResult.OK

    def get_stone(self, x: int, y: int) -> Stone:
        if not self.is_in_bounds(x, y):
            return Stone.NONE
        return self.board[y][x]

    def snapshot(self) -> list[list[int]]:
        return [[int(cell) for cell in row] for row in self.board]

    def _check_five_in_a_row(self, x: int, y: int, stone: Stone) -> bool:
        axes = ((1, 0), (0, 1), (1, 1), (1, -1))
        for dx, dy in axes:
            total = (
                1
                + self._count_in_direction(x, y, dx, dy, stone)
                + self._count_in_direction(x, y, -dx, -dy, stone)
            )
            if total >= 5:
                return True
        return False

    def _count_in_direction(
        self, x: int, y: int, dx: int, dy: int, stone: Stone
    ) -> int:
        count = 0
        cx, cy = x, y
        while True:
            cx += dx
            cy += dy
            if not self.is_in_bounds(cx, cy) or self.board[cy][cx] != stone:
                break
            count += 1
        return count

    def _is_board_full(self) -> bool:
        return all(cell != Stone.NONE for row in self.board for cell in row)

    def _switch_turn(self) -> None:
        self.current_turn = (
            Stone.WHITE if self.current_turn == Stone.BLACK else Stone.BLACK
        )
