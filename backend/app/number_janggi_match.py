"""숫자장기 판정 엔진 — number_janggi_match.gd(Godot)의 Python 포트.

로컬(패스앤플레이) 버전과 동일한 규칙을 그대로 따른다. 온라인 대전에서는
이 클래스가 유일한 권위자이며, 서버(number_janggi.py)가 뷰어(시점)별로
정보를 가려서 클라이언트에 내려보낸다 — 이 파일 자체는 숨김 처리를 하지
않고, 항상 "완전한 진실"을 담고 있다.

말은 dict로 표현한다: {id, side, type, value, alive, col, row, revealed}.
좌표/보드 판정은 number_janggi_rules 모듈을 그대로 쓴다.
"""

from __future__ import annotations

from typing import Any

from . import number_janggi_rules as rules

ARRANGE = "arrange"
MOVE = "move"
AWAITING_ITEMS = "awaiting_items"
AWAITING_REWARD = "awaiting_reward"
GAME_OVER = "game_over"

# ItemType — Godot enum(BLIND=0, PLUS_ONE=1, MINUS_ONE=2)과 값을 맞춘다.
BLIND = 0
PLUS_ONE = 1
MINUS_ONE = 2

_ITEM_KEYS = {BLIND: "blind", PLUS_ONE: "plus1", MINUS_ONE: "minus1"}


def _err(message: str) -> dict[str, Any]:
    return {"ok": False, "error": message}


def _ok(**extra: Any) -> dict[str, Any]:
    return {"ok": True, **extra}


class NumberJanggiMatch:
    def __init__(self) -> None:
        self.pieces: dict[int, dict[str, Any]] = {}
        self.board: list[list[int]] = []
        self.next_piece_id = 0

        self.phase = ARRANGE
        self.ready_flags = [False, False]
        self.current_turn = -1
        self.winner = -1
        self.win_reason = ""

        self.graveyard: list[list[int]] = [[], []]
        self.used_items: list[dict[str, bool]] = [
            {"blind": False, "plus1": False, "minus1": False},
            {"blind": False, "plus1": False, "minus1": False},
        ]

        self.pending_duels: list[dict[str, Any]] = []
        self.mover_item_choice: dict[str, Any] | None = None
        self.mover_responded = False
        self.pending_reward: dict[str, Any] = {}

        self._pending_mover_side = -1
        self._pending_mover_piece = -1

    # ── 초기화 ────────────────────────────────────────────────────
    def start_new_match(self) -> None:
        self.pieces = {}
        self.board = [[-1] * rules.BOARD_COLS for _ in range(rules.BOARD_ROWS)]
        self.next_piece_id = 0
        for side in (0, 1):
            for v in range(1, rules.NUMBER_COUNT + 1):
                self._create_piece(side, rules.NUMBER, v)
            for _ in range(rules.MINE_COUNT):
                self._create_piece(side, rules.MINE, 0)
            self._create_piece(side, rules.KING, 0)
        self.phase = ARRANGE
        self.ready_flags = [False, False]
        self.current_turn = -1
        self.winner = -1
        self.win_reason = ""
        self.graveyard = [[], []]
        self.used_items = [
            {"blind": False, "plus1": False, "minus1": False},
            {"blind": False, "plus1": False, "minus1": False},
        ]
        self.pending_duels = []
        self.mover_item_choice = None
        self.mover_responded = False
        self.pending_reward = {}
        self._pending_mover_side = -1
        self._pending_mover_piece = -1

    def _create_piece(self, side: int, type_: int, value: int) -> int:
        pid = self.next_piece_id
        self.next_piece_id += 1
        self.pieces[pid] = {
            "id": pid,
            "side": side,
            "type": type_,
            "value": value,
            "alive": True,
            "col": -1,
            "row": -1,
            "revealed": False,
        }
        return pid

    def side_piece_ids(self, side: int) -> list[int]:
        return [pid for pid, p in self.pieces.items() if p["side"] == side]

    def unplaced_piece_ids(self, side: int) -> list[int]:
        return [pid for pid, p in self.pieces.items() if p["side"] == side and p["col"] == -1]

    def find_piece_id(self, side: int, type_: int, value: int = -1) -> int:
        for pid, p in self.pieces.items():
            if p["side"] == side and p["type"] == type_ and (value == -1 or p["value"] == value):
                return pid
        return -1

    def place_piece(self, side: int, piece_id: int, col: int, row: int) -> dict[str, Any]:
        if self.phase != ARRANGE:
            return _err("wrong_phase")
        p = self.pieces.get(piece_id)
        if p is None or p["side"] != side:
            return _err("not_your_piece")
        if not rules.is_own_camp(col, row, side):
            return _err("not_own_camp")
        occupant = self.board[row][col]
        if occupant != -1 and occupant != piece_id:
            return _err("cell_occupied")
        if p["col"] != -1:
            self.board[p["row"]][p["col"]] = -1
        self.board[row][col] = piece_id
        p["col"] = col
        p["row"] = row
        return _ok()

    def unplace_piece(self, side: int, piece_id: int) -> dict[str, Any]:
        if self.phase != ARRANGE:
            return _err("wrong_phase")
        p = self.pieces.get(piece_id)
        if p is None or p["side"] != side:
            return _err("not_your_piece")
        if p["col"] != -1:
            self.board[p["row"]][p["col"]] = -1
            p["col"] = -1
            p["row"] = -1
        return _ok()

    def swap_pieces(self, side: int, piece_id_a: int, piece_id_b: int) -> dict[str, Any]:
        """배치 단계 전용 — 이미 놓인 자기 말 두 개의 자리를 맞바꾼다."""
        if self.phase != ARRANGE:
            return _err("wrong_phase")
        a = self.pieces.get(piece_id_a)
        b = self.pieces.get(piece_id_b)
        if a is None or b is None or a["side"] != side or b["side"] != side:
            return _err("not_your_piece")
        if a["col"] == -1 or b["col"] == -1:
            return _err("not_placed")
        a_col, a_row = a["col"], a["row"]
        b_col, b_row = b["col"], b["row"]
        self.unplace_piece(side, piece_id_a)
        self.unplace_piece(side, piece_id_b)
        self.place_piece(side, piece_id_a, b_col, b_row)
        self.place_piece(side, piece_id_b, a_col, a_row)
        return _ok()

    def apply_default_arrangement(self, side: int) -> None:
        """자기 진영 3줄에 14개 말을 기본 배치한다.

        앞줄(적과 제일 가까운 줄)에 1~6, 가운뎃줄에 7~10, 맨 뒷줄에 지뢰
        3개와 왕. 두 진영 모두 "자기 시점에서" 1→6이 왼쪽부터 보이도록,
        위쪽(side 1) 진영은 열 순서를 좌우 반전한다 — 프론트엔드
        number_janggi_board.gd의 _apply_default_arrangement와 동일 로직.
        """
        for pid in self.side_piece_ids(side):
            self.unplace_piece(side, pid)

        back_row = rules.own_back_row(side)
        fwd = rules.forward_dir(side)
        mid_row = back_row + fwd
        front_row = back_row + 2 * fwd

        def default_col(view_col: int) -> int:
            return view_col if side == 0 else rules.BOARD_COLS - 1 - view_col

        for v in range(1, 7):
            self.place_piece(side, self.find_piece_id(side, rules.NUMBER, v), default_col(v - 1), front_row)
        for v in range(7, 11):
            self.place_piece(side, self.find_piece_id(side, rules.NUMBER, v), default_col(v - 6), mid_row)

        mine_ids = sorted(pid for pid in self.side_piece_ids(side) if self.pieces[pid]["type"] == rules.MINE)
        for i, pid in enumerate(mine_ids):
            self.place_piece(side, pid, default_col(i + 1), back_row)
        self.place_piece(side, self.find_piece_id(side, rules.KING), default_col(4), back_row)

    def is_arrangement_complete(self, side: int) -> bool:
        return len(self.unplaced_piece_ids(side)) == 0

    def mark_ready(self, side: int) -> dict[str, Any]:
        if self.phase != ARRANGE:
            return _err("wrong_phase")
        if not self.is_arrangement_complete(side):
            return _err("not_fully_arranged")
        self.ready_flags[side] = True
        return _ok()

    def unmark_ready(self, side: int) -> None:
        """배치를 다시 바꾸면 준비 상태를 해제한다(온라인 전용 안전장치)."""
        self.ready_flags[side] = False

    def both_ready(self) -> bool:
        return self.ready_flags[0] and self.ready_flags[1]

    def start_move_phase(self, starter_side: int) -> dict[str, Any]:
        if not self.both_ready():
            return _err("not_both_ready")
        self.phase = MOVE
        self.current_turn = starter_side
        return _ok()

    # ── 이동 ─────────────────────────────────────────────────────
    def legal_moves(self, piece_id: int) -> list[tuple[int, int]]:
        if self.phase != MOVE or piece_id not in self.pieces:
            return []
        p = self.pieces[piece_id]
        if not p["alive"] or p["side"] != self.current_turn:
            return []
        if p["type"] == rules.MINE:
            return []
        fwd = rules.forward_dir(p["side"])
        col, row = p["col"], p["row"]
        out: list[tuple[int, int]] = []
        for cc, cr in (
            (col - 1, row),
            (col + 1, row),
            (col, row + fwd),
            (col - 1, row + fwd),
            (col + 1, row + fwd),
        ):
            if rules.is_in_bounds(cc, cr) and self.board[cr][cc] == -1:
                out.append((cc, cr))
        mid_row = row + fwd
        far_row = row + 2 * fwd
        if (
            rules.is_in_bounds(col, far_row)
            and self.board[far_row][col] == -1
            and rules.is_in_bounds(col, mid_row)
            and self.board[mid_row][col] == -1
        ):
            out.append((col, far_row))
        return out

    def _detect_duels_at(self, col: int, row: int, mover_side: int) -> list[dict[str, Any]]:
        mover_id = self.board[row][col]
        out: list[dict[str, Any]] = []
        for nc, nr in rules.orthogonal_neighbors(col, row):
            nid = self.board[nr][nc]
            if nid != -1 and self.pieces[nid]["side"] != mover_side and self.pieces[nid]["alive"]:
                out.append(
                    {
                        "a_id": mover_id,
                        "a_col": col,
                        "a_row": row,
                        "b_id": nid,
                        "b_col": nc,
                        "b_row": nr,
                        "is_minus": rules.is_minus_boundary(col, row, nc, nr),
                    }
                )
        return out

    def move_piece(self, side: int, piece_id: int, to_col: int, to_row: int) -> dict[str, Any]:
        if self.phase != MOVE:
            return _err("wrong_phase")
        if side != self.current_turn:
            return _err("not_your_turn")
        p = self.pieces.get(piece_id)
        if p is None or p["side"] != side or not p["alive"]:
            return _err("not_your_piece")
        if (to_col, to_row) not in self.legal_moves(piece_id):
            return _err("illegal_move")
        self.board[p["row"]][p["col"]] = -1
        self.board[to_row][to_col] = piece_id
        p["col"], p["row"] = to_col, to_row
        return self._begin_combat_or_finish(side, piece_id)

    def _begin_combat_or_finish(self, side: int, piece_id: int) -> dict[str, Any]:
        p = self.pieces[piece_id]
        duels = self._detect_duels_at(p["col"], p["row"], side)
        if not duels:
            return self._finish_action(side, piece_id)
        self.pending_duels = duels
        self._pending_mover_side = side
        self._pending_mover_piece = piece_id
        self.phase = AWAITING_ITEMS
        self.mover_item_choice = None
        self.mover_responded = False
        return _ok(pending_duels=duels)

    # ── 대결 판정 + 아이템 ─────────────────────────────────────────
    ## 이번 대결을 유발한 쪽(방금 말을 옮긴 side)만 호출할 수 있다.
    def declare_item(self, side: int, item_type: int) -> dict[str, Any]:
        if self.phase != AWAITING_ITEMS:
            return _err("wrong_phase")
        if side != self._pending_mover_side:
            return _err("not_mover_side")
        if self.mover_responded:
            return _err("already_responded")
        if self.used_items[side][_ITEM_KEYS[item_type]]:
            return _err("item_already_used")
        self.mover_item_choice = {"piece_id": self._pending_mover_piece, "item": item_type}
        self.mover_responded = True
        return _ok()

    def decline_item(self, side: int) -> dict[str, Any]:
        if self.phase != AWAITING_ITEMS:
            return _err("wrong_phase")
        if side != self._pending_mover_side:
            return _err("not_mover_side")
        if self.mover_responded:
            return _err("already_responded")
        self.mover_responded = True
        return _ok()

    def resolve_duels(self) -> dict[str, Any]:
        if self.phase != AWAITING_ITEMS:
            return _err("wrong_phase")
        if not self.mover_responded:
            return _err("waiting_for_response")

        effective_value: dict[int, int] = {}
        hidden_from_opponent: dict[int, bool] = {}
        if self.mover_item_choice is not None:
            choice = self.mover_item_choice
            self.used_items[self._pending_mover_side][_ITEM_KEYS[choice["item"]]] = True
            if choice["item"] == PLUS_ONE:
                effective_value[choice["piece_id"]] = self.pieces[choice["piece_id"]]["value"] + 1
            elif choice["item"] == MINUS_ONE:
                effective_value[choice["piece_id"]] = self.pieces[choice["piece_id"]]["value"] - 1
            elif choice["item"] == BLIND:
                hidden_from_opponent[choice["piece_id"]] = True

        to_remove: dict[int, bool] = {}
        reports: list[dict[str, Any]] = []
        for d in self.pending_duels:
            a = self.pieces[d["a_id"]]
            b = self.pieces[d["b_id"]]
            a_val = effective_value.get(d["a_id"], a["value"])
            b_val = effective_value.get(d["b_id"], b["value"])
            report: dict[str, Any] = {
                "a_id": d["a_id"],
                "b_id": d["b_id"],
                "a_value": a_val,
                "b_value": b_val,
                "a_base_value": a["value"],
                "b_base_value": b["value"],
                "is_minus": d["is_minus"],
                "kind": "number",
                "score": 0,
                "winner_id": -1,
                "a_removed": False,
                "b_removed": False,
            }
            reports.append(report)

            if a["type"] == rules.KING or b["type"] == rules.KING:
                if a["type"] == rules.KING and b["type"] == rules.KING:
                    report["kind"] = "king_vs_king"  # 왕 vs 왕: 아무 일도 일어나지 않음
                elif a["type"] == rules.KING:
                    report["kind"] = "king"
                    report["winner_id"] = d["b_id"]
                    to_remove[d["a_id"]] = True
                else:
                    report["kind"] = "king"
                    report["winner_id"] = d["a_id"]
                    to_remove[d["b_id"]] = True
                continue

            if a["type"] == rules.MINE or b["type"] == rules.MINE:
                report["kind"] = "mine"
                to_remove[d["a_id"]] = True
                to_remove[d["b_id"]] = True
                continue

            if a_val == b_val:
                report["kind"] = "tie"
                report["score"] = a_val + b_val
                to_remove[d["a_id"]] = True
                to_remove[d["b_id"]] = True
                continue

            if d["is_minus"]:
                diff = abs(a_val - b_val)
                report["score"] = diff
                if diff >= 10:
                    winner_id = d["a_id"] if a_val > b_val else d["b_id"]
                else:
                    winner_id = d["a_id"] if a_val < b_val else d["b_id"]
            else:
                total = a_val + b_val
                report["score"] = total
                if total >= 10:
                    winner_id = d["a_id"] if a_val > b_val else d["b_id"]
                else:
                    winner_id = d["a_id"] if a_val < b_val else d["b_id"]
            report["winner_id"] = winner_id
            loser_id = d["b_id"] if winner_id == d["a_id"] else d["a_id"]
            to_remove[loser_id] = True

        removed_ids = list(to_remove.keys())
        for report in reports:
            report["a_removed"] = report["a_id"] in to_remove
            report["b_removed"] = report["b_id"] in to_remove

        for pid in removed_ids:
            if pid not in hidden_from_opponent:
                self.pieces[pid]["revealed"] = True
            self._remove_piece(pid)

        self.pending_duels = []
        self.mover_item_choice = None
        self.mover_responded = False

        mover_side = self._pending_mover_side
        mover_piece = self._pending_mover_piece
        result = self._finish_action(mover_side, mover_piece, removed_ids)
        result["duels"] = reports
        result["hidden_ids"] = list(hidden_from_opponent.keys())
        result["mover_side"] = mover_side
        return result

    def _remove_piece(self, pid: int) -> None:
        p = self.pieces[pid]
        if p["col"] != -1:
            self.board[p["row"]][p["col"]] = -1
        p["alive"] = False
        p["col"] = -1
        p["row"] = -1
        self.graveyard[p["side"]].append(pid)

    # ── 승리 조건 + 부활 ────────────────────────────────────────────
    def _has_alive(self, side: int, type_: int) -> bool:
        return any(p["side"] == side and p["type"] == type_ and p["alive"] for p in self.pieces.values())

    def _has_alive_non_king(self, side: int) -> bool:
        return any(
            p["side"] == side and p["type"] != rules.KING and p["alive"] for p in self.pieces.values()
        )

    def check_win(self) -> dict[str, Any]:
        for s in (0, 1):
            if not self._has_alive(s, rules.KING):
                return {"over": True, "winner": 1 - s, "reason": "king_captured"}
        for s in (0, 1):
            if not self._has_alive_non_king(s):
                return {"over": True, "winner": 1 - s, "reason": "all_non_king_captured"}
        return {"over": False}

    def _finish_action(
        self, mover_side: int, mover_piece_id: int, removed_ids: list[int] | None = None
    ) -> dict[str, Any]:
        removed_ids = removed_ids or []
        win = self.check_win()
        if win["over"]:
            self.phase = GAME_OVER
            self.winner = win["winner"]
            self.win_reason = win["reason"]
            return _ok(game_over=True, winner=self.winner, reason=self.win_reason, removed_ids=removed_ids)

        mp = self.pieces.get(mover_piece_id)
        if mp is not None and mp["alive"] and mp["row"] == rules.enemy_back_row(mp["side"]):
            if mp["type"] == rules.KING:
                self.phase = GAME_OVER
                self.winner = mp["side"]
                self.win_reason = "king_reached_end"
                return _ok(
                    game_over=True, winner=self.winner, reason=self.win_reason, removed_ids=removed_ids
                )
            self.phase = AWAITING_REWARD
            self.pending_reward = {"side": mp["side"], "piece_id": mover_piece_id}
            return _ok(awaiting_reward=True, removed_ids=removed_ids)

        self.phase = MOVE
        self.current_turn = 1 - mover_side
        return _ok(removed_ids=removed_ids)

    def graveyard_of(self, side: int) -> list[int]:
        return list(self.graveyard[side])

    def _find_empty_col_in_row(self, row: int) -> int:
        for c in range(rules.BOARD_COLS):
            if self.board[row][c] == -1:
                return c
        return -1

    def perform_revive(self, side: int, revive_piece_id: int) -> dict[str, Any]:
        if self.phase != AWAITING_REWARD or self.pending_reward.get("side", -1) != side:
            return _err("wrong_phase")
        arrived_id = self.pending_reward["piece_id"]
        arrived = self.pieces[arrived_id]

        if revive_piece_id == arrived_id:
            arrived["revealed"] = True
            self.pending_reward = {}
            return self._after_reward_placed(side, arrived_id)

        if revive_piece_id not in self.graveyard[side]:
            return _err("not_in_graveyard")

        self.board[arrived["row"]][arrived["col"]] = -1
        arrived["alive"] = False
        arrived["col"] = -1
        arrived["row"] = -1
        self.graveyard[side].append(arrived_id)

        row = rules.own_back_row(side)
        col_target = self._find_empty_col_in_row(row)
        if col_target == -1:
            row = rules.own_back_row_plus_one(side)
            col_target = self._find_empty_col_in_row(row)
        if col_target == -1:
            return _err("no_space_to_revive")

        revived = self.pieces[revive_piece_id]
        revived["alive"] = True
        revived["revealed"] = True
        revived["col"] = col_target
        revived["row"] = row
        self.board[row][col_target] = revive_piece_id
        self.graveyard[side].remove(revive_piece_id)

        self.pending_reward = {}
        return self._after_reward_placed(side, revive_piece_id)

    def decline_reward(self, side: int) -> dict[str, Any]:
        if self.phase != AWAITING_REWARD or self.pending_reward.get("side", -1) != side:
            return _err("wrong_phase")
        self.pending_reward = {}
        self.phase = MOVE
        self.current_turn = 1 - side
        return _ok()

    def _after_reward_placed(self, side: int, placed_piece_id: int) -> dict[str, Any]:
        p = self.pieces[placed_piece_id]
        duels = self._detect_duels_at(p["col"], p["row"], side)
        if not duels:
            self.phase = MOVE
            self.current_turn = 1 - side
            return _ok()
        self.pending_duels = duels
        self._pending_mover_side = side
        self._pending_mover_piece = placed_piece_id
        self.phase = AWAITING_ITEMS
        self.mover_item_choice = None
        self.mover_responded = False
        return _ok(pending_duels=duels)

    # ── 60초 타임아웃 ────────────────────────────────────────────
    def force_arrange_timeout(self, side: int) -> dict[str, Any]:
        if self.phase != ARRANGE:
            return _err("wrong_phase")
        self.phase = GAME_OVER
        self.winner = 1 - side
        self.win_reason = "arrange_timeout"
        return _ok(winner=self.winner, reason=self.win_reason)

    def force_move_timeout(self) -> dict[str, Any]:
        if self.phase != MOVE:
            return _err("wrong_phase")
        loser = self.current_turn
        self.phase = GAME_OVER
        self.winner = 1 - loser
        self.win_reason = "move_timeout"
        return _ok(winner=self.winner, reason=self.win_reason)
