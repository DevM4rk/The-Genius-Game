"""WebSocket JSON 메시지 스키마 (클라이언트 ↔ 서버)."""

from __future__ import annotations

from typing import Any

from .board import GameState, MoveResult, Stone

STONE_NAME = {Stone.NONE: "none", Stone.BLACK: "black", Stone.WHITE: "white"}
STATE_NAME = {
    GameState.PLAYING: "playing",
    GameState.BLACK_WIN: "black_win",
    GameState.WHITE_WIN: "white_win",
    GameState.DRAW: "draw",
}
MOVE_RESULT_NAME = {
    MoveResult.OK: "ok",
    MoveResult.OUT_OF_BOUNDS: "out_of_bounds",
    MoveResult.CELL_OCCUPIED: "cell_occupied",
    MoveResult.GAME_ALREADY_OVER: "game_already_over",
}


def stone_name(stone: Stone) -> str:
    return STONE_NAME[stone]


def state_name(state: GameState) -> str:
    return STATE_NAME[state]


def move_result_name(result: MoveResult) -> str:
    return MOVE_RESULT_NAME[result]


def msg(type_: str, **payload: Any) -> dict[str, Any]:
    return {"type": type_, **payload}
