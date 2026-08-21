# number_janggi_match.gd — 숫자장기 판정 엔진 (2~7단계: 배치·이동·대결·승리·부활·아이템·타임아웃)
#
# UI 없는 순수 로직 클래스. 말은 Dictionary로 표현하며, 이후 온라인 대전에서
# Python 서버로 그대로 옮겨 적기 쉽도록(직렬화 용이) 커스텀 클래스 대신
# Dictionary를 사용한다.
#
# 흐름: start_new_match() → place_piece() 반복 → mark_ready() 양쪽 다 →
#       start_move_phase() → move_piece() → (대결 있으면, 이동한 쪽만)
#       declare_item()/decline_item() → resolve_duels() → (맨끝줄 도달 시)
#       perform_revive()/decline_reward() → 다음 턴.
#
# 아이템은 "그 대결을 유발한 쪽"(방금 말을 옮긴 사람)만 쓸 수 있다. 가만히
# 있던 상대는 그 대결에 개입할 수 없고, 자기 차례에 자기가 이동을 유발했을
# 때만 자기 아이템을 쓸 기회를 얻는다.
class_name NumberJanggiMatch
extends RefCounted

enum Phase { ARRANGE, MOVE, AWAITING_ITEMS, AWAITING_REWARD, GAME_OVER }
enum ItemType { BLIND, PLUS_ONE, MINUS_ONE }

var pieces: Dictionary = {}  # id(int) -> {id,side,type,value,alive,col,row,revealed}
var board: Array = []  # board[row][col] = piece id, -1 = empty
var next_piece_id: int = 0

var phase: Phase = Phase.ARRANGE
var ready_flags: Array = [false, false]
var current_turn: int = -1
var winner: int = -1
var win_reason: String = ""

var graveyard: Array = [[], []]  # graveyard[side] = 제거된 자기 말 id 목록 (부활 후보)
var used_items: Array = [
	{"blind": false, "plus1": false, "minus1": false},
	{"blind": false, "plus1": false, "minus1": false},
]

var pending_duels: Array = []
var mover_item_choice = null  # {"piece_id":id,"item":ItemType} 또는 null — 이동한 쪽만 선택 가능
var mover_responded: bool = false
var pending_reward: Dictionary = {}  # {"side":int,"piece_id":int} 또는 비어있음

var _pending_mover_side: int = -1
var _pending_mover_piece: int = -1


# ── 초기화 (2단계: 배치) ────────────────────────────────────────
func start_new_match() -> void:
	pieces.clear()
	board = []
	for _r in NumberJanggiRules.BOARD_ROWS:
		var row_cells: Array = []
		for _c in NumberJanggiRules.BOARD_COLS:
			row_cells.append(-1)
		board.append(row_cells)
	next_piece_id = 0
	for side in [0, 1]:
		for v in range(1, NumberJanggiRules.NUMBER_COUNT + 1):
			_create_piece(side, NumberJanggiRules.PieceType.NUMBER, v)
		for _i in NumberJanggiRules.MINE_COUNT:
			_create_piece(side, NumberJanggiRules.PieceType.MINE, 0)
		_create_piece(side, NumberJanggiRules.PieceType.KING, 0)
	phase = Phase.ARRANGE
	ready_flags = [false, false]
	current_turn = -1
	winner = -1
	win_reason = ""
	graveyard = [[], []]
	used_items = [
		{"blind": false, "plus1": false, "minus1": false},
		{"blind": false, "plus1": false, "minus1": false},
	]
	pending_duels = []
	mover_item_choice = null
	mover_responded = false
	pending_reward = {}
	_pending_mover_side = -1
	_pending_mover_piece = -1


func _create_piece(side: int, type: int, value: int) -> int:
	var id := next_piece_id
	next_piece_id += 1
	pieces[id] = {
		"id": id,
		"side": side,
		"type": type,
		"value": value,
		"alive": true,
		"col": -1,
		"row": -1,
		"revealed": false,
	}
	return id


func side_piece_ids(side: int) -> Array:
	return pieces.keys().filter(func(id): return pieces[id].side == side)


func unplaced_piece_ids(side: int) -> Array:
	return pieces.keys().filter(func(id): return pieces[id].side == side and pieces[id].col == -1)


func find_piece_id(side: int, type: int, value: int = -1) -> int:
	for id in pieces:
		var p: Dictionary = pieces[id]
		if p.side == side and p.type == type and (value == -1 or p.value == value):
			return id
	return -1


func place_piece(side: int, piece_id: int, col: int, row: int) -> Dictionary:
	if phase != Phase.ARRANGE:
		return {"ok": false, "error": "wrong_phase"}
	if not pieces.has(piece_id) or pieces[piece_id].side != side:
		return {"ok": false, "error": "not_your_piece"}
	if not NumberJanggiRules.is_own_camp(col, row, side):
		return {"ok": false, "error": "not_own_camp"}
	var occupant: int = board[row][col]
	if occupant != -1 and occupant != piece_id:
		return {"ok": false, "error": "cell_occupied"}
	var p: Dictionary = pieces[piece_id]
	if p.col != -1:
		board[p.row][p.col] = -1
	board[row][col] = piece_id
	p.col = col
	p.row = row
	return {"ok": true}


func unplace_piece(side: int, piece_id: int) -> Dictionary:
	if phase != Phase.ARRANGE:
		return {"ok": false, "error": "wrong_phase"}
	if not pieces.has(piece_id) or pieces[piece_id].side != side:
		return {"ok": false, "error": "not_your_piece"}
	var p: Dictionary = pieces[piece_id]
	if p.col != -1:
		board[p.row][p.col] = -1
		p.col = -1
		p.row = -1
	return {"ok": true}


func auto_arrange(side: int) -> void:
	var ids := unplaced_piece_ids(side)
	var rows: Array = [0, 1, 2]
	if side == 0:
		rows = [
			NumberJanggiRules.BOARD_ROWS - 3,
			NumberJanggiRules.BOARD_ROWS - 2,
			NumberJanggiRules.BOARD_ROWS - 1,
		]
	var idx := 0
	for r in rows:
		for c in range(NumberJanggiRules.BOARD_COLS):
			if idx >= ids.size():
				return
			place_piece(side, ids[idx], c, r)
			idx += 1


func is_arrangement_complete(side: int) -> bool:
	return unplaced_piece_ids(side).is_empty()


func mark_ready(side: int) -> Dictionary:
	if phase != Phase.ARRANGE:
		return {"ok": false, "error": "wrong_phase"}
	if not is_arrangement_complete(side):
		return {"ok": false, "error": "not_fully_arranged"}
	ready_flags[side] = true
	return {"ok": true}


func both_ready() -> bool:
	return ready_flags[0] and ready_flags[1]


func start_move_phase(starter_side: int) -> Dictionary:
	if not both_ready():
		return {"ok": false, "error": "not_both_ready"}
	phase = Phase.MOVE
	current_turn = starter_side
	return {"ok": true}


# ── 이동 (3단계) ────────────────────────────────────────────────
func legal_moves(piece_id: int) -> Array:
	if phase != Phase.MOVE or not pieces.has(piece_id):
		return []
	var p: Dictionary = pieces[piece_id]
	if not p.alive or p.side != current_turn:
		return []
	if p.type == NumberJanggiRules.PieceType.MINE:
		return []
	var fwd := NumberJanggiRules.forward_dir(p.side)
	var out: Array = []
	var single_steps: Array = [
		[p.col - 1, p.row],
		[p.col + 1, p.row],
		[p.col, p.row + fwd],
		[p.col - 1, p.row + fwd],
		[p.col + 1, p.row + fwd],
	]
	for cand in single_steps:
		if NumberJanggiRules.is_in_bounds(cand[0], cand[1]) and board[cand[1]][cand[0]] == -1:
			out.append(cand)
	var mid_row: int = p.row + fwd
	var far_row: int = p.row + 2 * fwd
	if (
		NumberJanggiRules.is_in_bounds(p.col, far_row)
		and board[far_row][p.col] == -1
		and NumberJanggiRules.is_in_bounds(p.col, mid_row)
		and board[mid_row][p.col] == -1
	):
		out.append([p.col, far_row])
	return out


func _detect_duels_at(col: int, row: int, mover_side: int) -> Array:
	var mover_id: int = board[row][col]
	var out: Array = []
	for nb in NumberJanggiRules.orthogonal_neighbors(col, row):
		var nid: int = board[nb[1]][nb[0]]
		if nid != -1 and pieces[nid].side != mover_side and pieces[nid].alive:
			out.append({
				"a_id": mover_id,
				"a_col": col,
				"a_row": row,
				"b_id": nid,
				"b_col": nb[0],
				"b_row": nb[1],
				"is_minus": NumberJanggiRules.is_minus_boundary(col, row, nb[0], nb[1]),
			})
	return out


func move_piece(side: int, piece_id: int, to_col: int, to_row: int) -> Dictionary:
	if phase != Phase.MOVE:
		return {"ok": false, "error": "wrong_phase"}
	if side != current_turn:
		return {"ok": false, "error": "not_your_turn"}
	if not pieces.has(piece_id) or pieces[piece_id].side != side or not pieces[piece_id].alive:
		return {"ok": false, "error": "not_your_piece"}
	var legal := legal_moves(piece_id)
	var is_legal := false
	for m in legal:
		if m[0] == to_col and m[1] == to_row:
			is_legal = true
			break
	if not is_legal:
		return {"ok": false, "error": "illegal_move"}
	var p: Dictionary = pieces[piece_id]
	board[p.row][p.col] = -1
	board[to_row][to_col] = piece_id
	p.col = to_col
	p.row = to_row
	return _begin_combat_or_finish(side, piece_id)


func _begin_combat_or_finish(side: int, piece_id: int) -> Dictionary:
	var p: Dictionary = pieces[piece_id]
	var duels := _detect_duels_at(p.col, p.row, side)
	if duels.is_empty():
		return _finish_action(side, piece_id)
	pending_duels = duels
	_pending_mover_side = side
	_pending_mover_piece = piece_id
	phase = Phase.AWAITING_ITEMS
	mover_item_choice = null
	mover_responded = false
	return {"ok": true, "pending_duels": duels}


# ── 대결 판정 (4단계) + 아이템 (6단계) ──────────────────────────
func _item_key(item_type: int) -> String:
	match item_type:
		ItemType.BLIND:
			return "blind"
		ItemType.PLUS_ONE:
			return "plus1"
		ItemType.MINUS_ONE:
			return "minus1"
	return ""


## 이번 대결을 유발한 쪽(방금 이동한 side)만 호출할 수 있다. 가만히 있던
## 상대는 이 대결에 아이템을 쓸 수 없다.
func declare_item(side: int, item_type: int) -> Dictionary:
	if phase != Phase.AWAITING_ITEMS:
		return {"ok": false, "error": "wrong_phase"}
	if side != _pending_mover_side:
		return {"ok": false, "error": "not_mover_side"}
	if mover_responded:
		return {"ok": false, "error": "already_responded"}
	if used_items[side][_item_key(item_type)]:
		return {"ok": false, "error": "item_already_used"}
	mover_item_choice = {"piece_id": _pending_mover_piece, "item": item_type}
	mover_responded = true
	return {"ok": true}


func decline_item(side: int) -> Dictionary:
	if phase != Phase.AWAITING_ITEMS:
		return {"ok": false, "error": "wrong_phase"}
	if side != _pending_mover_side:
		return {"ok": false, "error": "not_mover_side"}
	if mover_responded:
		return {"ok": false, "error": "already_responded"}
	mover_responded = true
	return {"ok": true}


func resolve_duels() -> Dictionary:
	if phase != Phase.AWAITING_ITEMS:
		return {"ok": false, "error": "wrong_phase"}
	if not mover_responded:
		return {"ok": false, "error": "waiting_for_response"}

	var effective_value: Dictionary = {}
	var hidden_from_opponent: Dictionary = {}
	if mover_item_choice != null:
		var choice = mover_item_choice
		used_items[_pending_mover_side][_item_key(choice.item)] = true
		if choice.item == ItemType.PLUS_ONE:
			effective_value[choice.piece_id] = pieces[choice.piece_id].value + 1
		elif choice.item == ItemType.MINUS_ONE:
			effective_value[choice.piece_id] = pieces[choice.piece_id].value - 1
		elif choice.item == ItemType.BLIND:
			hidden_from_opponent[choice.piece_id] = true

	var to_remove: Dictionary = {}
	var reports: Array = []
	for d in pending_duels:
		var a: Dictionary = pieces[d.a_id]
		var b: Dictionary = pieces[d.b_id]
		var a_val: int = effective_value.get(d.a_id, a.value)
		var b_val: int = effective_value.get(d.b_id, b.value)
		var report: Dictionary = {
			"a_id": d.a_id,
			"b_id": d.b_id,
			"a_value": a_val,
			"b_value": b_val,
			"a_base_value": a.value,
			"b_base_value": b.value,
			"is_minus": d.is_minus,
			"kind": "number",
			"score": 0,  # 숫자 대결에서 실제로 비교에 쓴 값(합 또는 차)
			"winner_id": -1,
			"a_removed": false,
			"b_removed": false,
		}
		reports.append(report)

		if a.type == NumberJanggiRules.PieceType.KING or b.type == NumberJanggiRules.PieceType.KING:
			if a.type == NumberJanggiRules.PieceType.KING and b.type == NumberJanggiRules.PieceType.KING:
				report.kind = "king_vs_king"  # 왕 vs 왕: 아무 일도 일어나지 않음
			elif a.type == NumberJanggiRules.PieceType.KING:
				report.kind = "king"
				report.winner_id = d.b_id
				to_remove[d.a_id] = true
			else:
				report.kind = "king"
				report.winner_id = d.a_id
				to_remove[d.b_id] = true
			continue

		if a.type == NumberJanggiRules.PieceType.MINE or b.type == NumberJanggiRules.PieceType.MINE:
			report.kind = "mine"
			to_remove[d.a_id] = true
			to_remove[d.b_id] = true
			continue

		if a_val == b_val:
			report.kind = "tie"
			report.score = a_val + b_val
			to_remove[d.a_id] = true
			to_remove[d.b_id] = true
			continue

		var winner_id: int
		if d.is_minus:
			var diff: int = abs(a_val - b_val)
			report.score = diff
			if diff >= 10:
				winner_id = d.a_id if a_val > b_val else d.b_id
			else:
				winner_id = d.a_id if a_val < b_val else d.b_id
		else:
			var total: int = a_val + b_val
			report.score = total
			if total >= 10:
				winner_id = d.a_id if a_val > b_val else d.b_id
			else:
				winner_id = d.a_id if a_val < b_val else d.b_id
		report.winner_id = winner_id
		var loser_id: int = d.b_id if winner_id == d.a_id else d.a_id
		to_remove[loser_id] = true

	var removed_ids := to_remove.keys()
	for report in reports:
		report.a_removed = to_remove.has(report.a_id)
		report.b_removed = to_remove.has(report.b_id)

	for id in removed_ids:
		if not hidden_from_opponent.has(id):
			pieces[id].revealed = true
		_remove_piece(id)

	pending_duels = []
	mover_item_choice = null
	mover_responded = false

	var mover_side := _pending_mover_side
	var mover_piece := _pending_mover_piece
	var result := _finish_action(mover_side, mover_piece, removed_ids)
	result["duels"] = reports
	result["hidden_ids"] = hidden_from_opponent.keys()
	result["mover_side"] = mover_side
	return result


func _remove_piece(id: int) -> void:
	var p: Dictionary = pieces[id]
	if p.col != -1:
		board[p.row][p.col] = -1
	p.alive = false
	p.col = -1
	p.row = -1
	graveyard[p.side].append(id)


# ── 승리 조건 + 부활 (5단계) ────────────────────────────────────
func _has_alive(side: int, type: int) -> bool:
	for id in pieces:
		var p: Dictionary = pieces[id]
		if p.side == side and p.type == type and p.alive:
			return true
	return false


func _has_alive_non_king(side: int) -> bool:
	for id in pieces:
		var p: Dictionary = pieces[id]
		if p.side == side and p.type != NumberJanggiRules.PieceType.KING and p.alive:
			return true
	return false


func check_win() -> Dictionary:
	for s in [0, 1]:
		if not _has_alive(s, NumberJanggiRules.PieceType.KING):
			return {"over": true, "winner": 1 - s, "reason": "king_captured"}
	for s in [0, 1]:
		if not _has_alive_non_king(s):
			return {"over": true, "winner": 1 - s, "reason": "all_non_king_captured"}
	return {"over": false}


func _finish_action(mover_side: int, mover_piece_id: int, removed_ids: Array = []) -> Dictionary:
	var win := check_win()
	if win.over:
		phase = Phase.GAME_OVER
		winner = win.winner
		win_reason = win.reason
		return {"ok": true, "game_over": true, "winner": winner, "reason": win_reason, "removed_ids": removed_ids}

	var mp = pieces.get(mover_piece_id, null)
	if mp != null and mp.alive and mp.row == NumberJanggiRules.enemy_back_row(mp.side):
		if mp.type == NumberJanggiRules.PieceType.KING:
			phase = Phase.GAME_OVER
			winner = mp.side
			win_reason = "king_reached_end"
			return {"ok": true, "game_over": true, "winner": winner, "reason": win_reason, "removed_ids": removed_ids}
		else:
			phase = Phase.AWAITING_REWARD
			pending_reward = {"side": mp.side, "piece_id": mover_piece_id}
			return {"ok": true, "awaiting_reward": true, "removed_ids": removed_ids}

	phase = Phase.MOVE
	current_turn = 1 - mover_side
	return {"ok": true, "removed_ids": removed_ids}


func graveyard_of(side: int) -> Array:
	return graveyard[side].duplicate()


func _find_empty_col_in_row(row: int) -> int:
	for c in range(NumberJanggiRules.BOARD_COLS):
		if board[row][c] == -1:
			return c
	return -1


func perform_revive(side: int, revive_piece_id: int) -> Dictionary:
	if phase != Phase.AWAITING_REWARD or pending_reward.get("side", -1) != side:
		return {"ok": false, "error": "wrong_phase"}
	var arrived_id: int = pending_reward.piece_id
	var arrived: Dictionary = pieces[arrived_id]

	if revive_piece_id == arrived_id:
		arrived.revealed = true
		pending_reward = {}
		return _after_reward_placed(side, arrived_id)

	if not graveyard[side].has(revive_piece_id):
		return {"ok": false, "error": "not_in_graveyard"}

	board[arrived.row][arrived.col] = -1
	arrived.alive = false
	arrived.col = -1
	arrived.row = -1
	graveyard[side].append(arrived_id)

	var row := NumberJanggiRules.own_back_row(side)
	var col_target := _find_empty_col_in_row(row)
	if col_target == -1:
		row = NumberJanggiRules.own_back_row_plus_one(side)
		col_target = _find_empty_col_in_row(row)
	if col_target == -1:
		return {"ok": false, "error": "no_space_to_revive"}

	var revived: Dictionary = pieces[revive_piece_id]
	revived.alive = true
	revived.revealed = true
	revived.col = col_target
	revived.row = row
	board[row][col_target] = revive_piece_id
	graveyard[side].erase(revive_piece_id)

	pending_reward = {}
	return _after_reward_placed(side, revive_piece_id)


func decline_reward(side: int) -> Dictionary:
	if phase != Phase.AWAITING_REWARD or pending_reward.get("side", -1) != side:
		return {"ok": false, "error": "wrong_phase"}
	pending_reward = {}
	phase = Phase.MOVE
	current_turn = 1 - side
	return {"ok": true}


func _after_reward_placed(side: int, placed_piece_id: int) -> Dictionary:
	var p: Dictionary = pieces[placed_piece_id]
	var duels := _detect_duels_at(p.col, p.row, side)
	if duels.is_empty():
		phase = Phase.MOVE
		current_turn = 1 - side
		return {"ok": true}
	pending_duels = duels
	_pending_mover_side = side
	_pending_mover_piece = placed_piece_id
	phase = Phase.AWAITING_ITEMS
	mover_item_choice = null
	mover_responded = false
	return {"ok": true, "pending_duels": duels}


# ── 60초 타임아웃 (7단계) ────────────────────────────────────────
func force_arrange_timeout(side: int) -> Dictionary:
	if phase != Phase.ARRANGE:
		return {"ok": false, "error": "wrong_phase"}
	phase = Phase.GAME_OVER
	winner = 1 - side
	win_reason = "arrange_timeout"
	return {"ok": true, "winner": winner, "reason": win_reason}


func force_move_timeout() -> Dictionary:
	if phase != Phase.MOVE:
		return {"ok": false, "error": "wrong_phase"}
	var loser := current_turn
	phase = Phase.GAME_OVER
	winner = 1 - loser
	win_reason = "move_timeout"
	return {"ok": true, "winner": winner, "reason": win_reason}
