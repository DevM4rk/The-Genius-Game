"""십이장기 — 3×4 판에서 왕(王)·장(將)·상(相)·자(子)로 두는 1:1 장기.

- 왕: 8방향 1칸 / 장: 앞뒤좌우 1칸 / 상: 대각선 1칸 / 자: 앞으로 1칸.
- 자가 이동해서 상대 진영(맨 끝줄)에 들어가면 후(侯)가 된다. 후는 대각선 뒤를
  뺀 6방향 1칸.
- 잡은 말은 내 포로가 되고(후는 자로 돌아감), 내 차례에 이동 대신 빈칸에 내려놓을
  수 있다. 상대 진영에는 내려놓을 수 없다.
- 상대 왕을 잡거나, 내 왕이 상대 진영에 들어가 상대 차례를 한 번 버티면 승리.

판 좌표는 (col, row). 0번 플레이어 진영은 row 3, 1번 플레이어 진영은 row 0이다.
모든 정보가 공개된 게임이라 숨길 정보는 없다.
"""

from __future__ import annotations

import random
from dataclasses import dataclass, field
from typing import Any

COLS = 3
ROWS = 4
MAX_PLIES = 200

# (앞으로 몇 칸, 옆으로 몇 칸). 앞 방향은 플레이어마다 다르다.
DIRECTIONS: dict[str, list[tuple[int, int]]] = {
    "king": [(f, s) for f in (-1, 0, 1) for s in (-1, 0, 1) if (f, s) != (0, 0)],
    "rook": [(1, 0), (-1, 0), (0, 1), (0, -1)],
    "bishop": [(1, 1), (1, -1), (-1, 1), (-1, -1)],
    "pawn": [(1, 0)],
    "gold": [(1, 0), (1, 1), (1, -1), (0, 1), (0, -1), (-1, 0)],
}
DROPPABLE = ("rook", "bishop", "pawn")


def forward(owner: int) -> int:
    return -1 if owner == 0 else 1


def home_row(owner: int) -> int:
    return ROWS - 1 if owner == 0 else 0


@dataclass
class Piece:
    owner: int
    kind: str


def initial_board() -> list[list[Piece | None]]:
    board: list[list[Piece | None]] = [[None] * COLS for _ in range(ROWS)]
    board[3] = [Piece(0, "rook"), Piece(0, "king"), Piece(0, "bishop")]
    board[2][1] = Piece(0, "pawn")
    board[0] = [Piece(1, "bishop"), Piece(1, "king"), Piece(1, "rook")]
    board[1][1] = Piece(1, "pawn")
    return board


@dataclass
class TwelveState:
    board: list[list[Piece | None]] = field(default_factory=initial_board)
    hands: list[dict[str, int]] = field(
        default_factory=lambda: [{k: 0 for k in DROPPABLE}, {k: 0 for k in DROPPABLE}]
    )
    to_act: int = 0
    ply: int = 0
    over: bool = False
    winner: int = -1
    reason: str = ""
    last_move: dict[str, Any] | None = None
    moves: list[dict[str, Any]] = field(default_factory=list)

    def at(self, col: int, row: int) -> Piece | None:
        return self.board[row][col]

    def king_pos(self, owner: int) -> tuple[int, int] | None:
        for row in range(ROWS):
            for col in range(COLS):
                p = self.board[row][col]
                if p is not None and p.owner == owner and p.kind == "king":
                    return col, row
        return None


def legal_actions(state: TwelveState, idx: int) -> list[dict[str, Any]]:
    actions: list[dict[str, Any]] = []
    fwd = forward(idx)
    for row in range(ROWS):
        for col in range(COLS):
            p = state.board[row][col]
            if p is None or p.owner != idx:
                continue
            for f, s in DIRECTIONS[p.kind]:
                c2, r2 = col + s, row + f * fwd
                if not (0 <= c2 < COLS and 0 <= r2 < ROWS):
                    continue
                target = state.board[r2][c2]
                if target is not None and target.owner == idx:
                    continue
                actions.append({"kind": "move", "from": [col, row], "to": [c2, r2]})

    enemy_row = home_row(1 - idx)
    for kind, count in state.hands[idx].items():
        if count <= 0:
            continue
        for row in range(ROWS):
            if row == enemy_row:
                continue
            for col in range(COLS):
                if state.board[row][col] is None:
                    actions.append({"kind": "drop", "piece": kind, "to": [col, row]})
    return actions


def _normalize(action: dict[str, Any]) -> dict[str, Any] | None:
    try:
        kind = action.get("kind")
        to = [int(v) for v in action.get("to", [])]
        if kind == "move":
            return {"kind": "move", "from": [int(v) for v in action.get("from", [])], "to": to}
        if kind == "drop":
            return {"kind": "drop", "piece": str(action.get("piece", "")), "to": to}
    except (TypeError, ValueError):
        return None
    return None


class TwelveJanggiRules:
    game_id = "twelve_janggi"

    def new_state(self, rng: random.Random) -> TwelveState:
        return TwelveState(to_act=rng.randint(0, 1))

    def apply(self, state: TwelveState, idx: int, action: dict[str, Any]) -> str | None:
        if state.over:
            return "game_already_over"
        if idx != state.to_act:
            return "not_your_turn"
        normalized = _normalize(action)
        if normalized is None or normalized not in legal_actions(state, idx):
            return "illegal_move"

        opp = 1 - idx
        col, row = normalized["to"]
        record: dict[str, Any] = {"by": idx, **normalized, "captured": None, "promoted": False}

        if normalized["kind"] == "move":
            fc, fr = normalized["from"]
            piece = state.board[fr][fc]
            assert piece is not None
            captured = state.board[row][col]
            state.board[fr][fc] = None
            if piece.kind == "pawn" and row == home_row(opp):
                piece = Piece(idx, "gold")
                record["promoted"] = True
            state.board[row][col] = piece
            record["piece"] = piece.kind
            if captured is not None:
                record["captured"] = captured.kind
                if captured.kind == "king":
                    self._end(state, idx, "king_captured")
                else:
                    back = "pawn" if captured.kind == "gold" else captured.kind
                    state.hands[idx][back] += 1
        else:
            state.hands[idx][normalized["piece"]] -= 1
            state.board[row][col] = Piece(idx, normalized["piece"])

        state.ply += 1
        state.last_move = record
        state.moves.append(record)
        if state.over:
            return None

        # 상대 왕이 내 진영에서 내 차례를 버텼으면 상대 승리.
        opp_king = state.king_pos(opp)
        if opp_king is not None and opp_king[1] == home_row(idx):
            self._end(state, opp, "king_reached")
            return None

        state.to_act = opp
        if state.ply >= MAX_PLIES:
            self._end(state, -1, "move_limit")
        elif not legal_actions(state, opp):
            self._end(state, idx, "no_moves")
        return None

    @staticmethod
    def _end(state: TwelveState, winner: int, reason: str) -> None:
        state.over = True
        state.winner = winner
        state.reason = reason

    def view(self, state: TwelveState, idx: int) -> dict[str, Any]:
        opp = 1 - idx
        my_turn = not state.over and state.to_act == idx
        return {
            "board": [
                [None if p is None else {"owner": p.owner, "kind": p.kind} for p in row]
                for row in state.board
            ],
            "my_hand": dict(state.hands[idx]),
            "opp_hand": dict(state.hands[opp]),
            "my_turn": my_turn,
            "legal": legal_actions(state, idx) if my_turn else [],
            "ply": state.ply,
            "max_plies": MAX_PLIES,
            "last_move": state.last_move,
            "moves": list(state.moves),
            "is_over": state.over,
            "winner": state.winner,
            "win_reason": state.reason,
        }
