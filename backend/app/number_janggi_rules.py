"""숫자장기 보드 좌표 · 마이너스 줄 판정 — number_janggi_rules.gd(Godot)의 Python 포트.

좌표계: col은 0~5(가로 6칸), row는 0~8(세로 9칸). side 0 = "아래" 진영
(row 6,7,8), side 1 = "위" 진영(row 0,1,2). 프론트엔드의 동일 파일과 값이
반드시 일치해야 하므로, 규칙을 바꿀 때는 두 파일을 함께 수정한다.
"""

from __future__ import annotations

BOARD_COLS = 6
BOARD_ROWS = 9
CAMP_ROWS = 3

# 마이너스 줄이 지나가는 좌우 col 경계쌍 (각 9칸씩, 총 18개).
MINUS_COLUMN_GAPS = [(1, 2), (3, 4)]

# PieceType — Godot enum과 값을 맞춘다.
NUMBER = 0
MINE = 1
KING = 2

NUMBER_COUNT = 10
MINE_COUNT = 3
TOTAL_PIECE_COUNT = NUMBER_COUNT + MINE_COUNT + 1  # 14


def is_in_bounds(col: int, row: int) -> bool:
    return 0 <= col < BOARD_COLS and 0 <= row < BOARD_ROWS


def is_own_camp(col: int, row: int, side: int) -> bool:
    if not is_in_bounds(col, row):
        return False
    if side == 0:
        return row >= BOARD_ROWS - CAMP_ROWS
    return row < CAMP_ROWS


def forward_dir(side: int) -> int:
    return -1 if side == 0 else 1


def enemy_back_row(side: int) -> int:
    return 0 if side == 0 else BOARD_ROWS - 1


def own_back_row(side: int) -> int:
    return BOARD_ROWS - 1 if side == 0 else 0


def own_back_row_plus_one(side: int) -> int:
    return own_back_row(side) + forward_dir(side)


def is_orthogonal_adjacent(col_a: int, row_a: int, col_b: int, row_b: int) -> bool:
    dc = abs(col_a - col_b)
    dr = abs(row_a - row_b)
    return (dc == 1 and dr == 0) or (dc == 0 and dr == 1)


def orthogonal_neighbors(col: int, row: int) -> list[tuple[int, int]]:
    out: list[tuple[int, int]] = []
    for dc, dr in ((0, -1), (0, 1), (-1, 0), (1, 0)):
        nc, nr = col + dc, row + dr
        if is_in_bounds(nc, nr):
            out.append((nc, nr))
    return out


def is_minus_boundary(col_a: int, row_a: int, col_b: int, row_b: int) -> bool:
    if row_a != row_b:
        return False
    if abs(col_a - col_b) != 1:
        return False
    lo, hi = min(col_a, col_b), max(col_a, col_b)
    return (lo, hi) in MINUS_COLUMN_GAPS


def is_minus_duel(col_a: int, row_a: int, col_b: int, row_b: int) -> bool:
    return is_minus_boundary(col_a, row_a, col_b, row_b)
