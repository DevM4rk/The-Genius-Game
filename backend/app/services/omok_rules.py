"""Omok rules facade on the server.

Phase 2: port or FFI the C++ core for authoritative validation.
Phase 0: lightweight Python stub so WS handlers have a place to call.
"""

from __future__ import annotations

BOARD_SIZE = 15
EMPTY, BLACK, WHITE = 0, 1, 2
DIRECTIONS = ((1, 0), (0, 1), (1, 1), (1, -1))


def index(x: int, y: int) -> int:
    return y * BOARD_SIZE + x


def in_bounds(x: int, y: int) -> bool:
    return 0 <= x < BOARD_SIZE and 0 <= y < BOARD_SIZE


def can_place(board: list[int], x: int, y: int) -> bool:
    return in_bounds(x, y) and board[index(x, y)] == EMPTY


def place(board: list[int], x: int, y: int, stone: int) -> None:
    board[index(x, y)] = stone


def count_line(board: list[int], x: int, y: int, dx: int, dy: int, stone: int) -> int:
    n = 0
    cx, cy = x + dx, y + dy
    while in_bounds(cx, cy) and board[index(cx, cy)] == stone:
        n += 1
        cx += dx
        cy += dy
    return n


def is_five(board: list[int], x: int, y: int, stone: int) -> bool:
    for dx, dy in DIRECTIONS:
        total = 1 + count_line(board, x, y, dx, dy, stone) + count_line(
            board, x, y, -dx, -dy, stone
        )
        if total >= 5:
            return True
    return False
