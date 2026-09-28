# twelve_janggi_board.gd — 십이장기 (온라인 전용)
#
# 서버 판 좌표는 0번 플레이어 진영이 아래(row 3)다. 1번 플레이어 화면에서는
# 판을 180도 돌려 그려서, 누구든 자기 진영이 아래에 오게 한다.
# 둘 수 있는 수는 서버가 legal 목록으로 보내 주고, 화면은 그 안에서만 고른다.
extends "res://scripts/duel_board.gd"

const COLS := 3
const ROWS := 4
const CELL_SIZE := Vector2(96, 96)
const GLYPHS := {"king": "王", "rook": "將", "bishop": "相", "pawn": "子", "gold": "侯"}
const KIND_NAMES := {"king": "왕", "rook": "장", "bishop": "상", "pawn": "자", "gold": "후"}
const DROP_ORDER := ["rook", "bishop", "pawn"]
const REASON_TEXT := {
	"king_captured": "왕을 잡았습니다",
	"king_reached": "왕이 상대 진영에서 한 차례를 버텼습니다",
	"move_limit": "수 제한에 도달해 무승부입니다",
	"no_moves": "둘 수 있는 수가 없습니다",
}
const BOARD_BG := Color(0.86, 0.74, 0.52, 1)
const HOME_BG := Color(0.80, 0.66, 0.44, 1)
const TARGET_BG := Color(0.62, 0.84, 0.52, 1)
const SELECT_BG := Color(0.98, 0.80, 0.36, 1)
const MINE_FG := Color(0.12, 0.22, 0.52, 1)
const OPP_FG := Color(0.66, 0.12, 0.10, 1)

var _grid: GridContainer
var _cells: Array[Button] = []
var _opp_hand_label: Label
var _my_hand_row: HBoxContainer
var _last_label: Label
var _sel_from := Vector2i(-1, -1)
var _sel_drop: String = ""


func _game_id() -> String:
	return "twelve_janggi"


func _build_content() -> void:
	_opp_hand_label = make_label("", 14, OPP_FG)
	content.add_child(_opp_hand_label)

	var holder := CenterContainer.new()
	content.add_child(holder)
	_grid = GridContainer.new()
	_grid.columns = COLS
	_grid.add_theme_constant_override("h_separation", 4)
	_grid.add_theme_constant_override("v_separation", 4)
	holder.add_child(_grid)
	for i in COLS * ROWS:
		var btn := Button.new()
		btn.custom_minimum_size = CELL_SIZE
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_size_override("font_size", 24)
		btn.pressed.connect(_on_cell_pressed.bind(i))
		_grid.add_child(btn)
		_cells.append(btn)

	_my_hand_row = make_row(8)
	content.add_child(_my_hand_row)
	_last_label = make_label("", 14, INK)
	content.add_child(_last_label)


func _to_board(display_index: int) -> Vector2i:
	var dcol := display_index % COLS
	var drow := floori(display_index / float(COLS))
	if my_index == 1:
		return Vector2i(COLS - 1 - dcol, ROWS - 1 - drow)
	return Vector2i(dcol, drow)


func _home_row(owner: int) -> int:
	return ROWS - 1 if owner == 0 else 0


func _cell_at(board: Array, pos: Vector2i) -> Variant:
	if pos.y < 0 or pos.y >= board.size():
		return null
	var row: Array = board[pos.y]
	return row[pos.x] if pos.x < row.size() else null


func _targets() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for a: Dictionary in state.get("legal", []):
		var matches := false
		if str(a.get("kind", "")) == "move" and _sel_from.x >= 0:
			var f: Array = a.get("from", [])
			matches = Vector2i(int(f[0]), int(f[1])) == _sel_from
		elif str(a.get("kind", "")) == "drop" and not _sel_drop.is_empty():
			matches = str(a.get("piece", "")) == _sel_drop
		if matches:
			var t: Array = a.get("to", [])
			out.append(Vector2i(int(t[0]), int(t[1])))
	return out


func _cell_style(bg: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.set_corner_radius_all(6)
	style.border_color = Color(0.40, 0.28, 0.14, 1)
	style.set_border_width_all(1)
	return style


func _render_state(data: Dictionary) -> void:
	var my_turn := bool(data.get("my_turn", false))
	if not my_turn:
		_sel_from = Vector2i(-1, -1)
		_sel_drop = ""

	var board: Array = data.get("board", [])
	var targets := _targets()
	for i in _cells.size():
		var pos := _to_board(i)
		var btn := _cells[i]
		var cell: Variant = _cell_at(board, pos)
		var bg := BOARD_BG
		if pos.y == _home_row(0) or pos.y == _home_row(1):
			bg = HOME_BG
		if pos == _sel_from:
			bg = SELECT_BG
		elif targets.has(pos):
			bg = TARGET_BG
		var style := _cell_style(bg)
		for key in ["normal", "hover", "pressed", "disabled"]:
			btn.add_theme_stylebox_override(key, style)

		if typeof(cell) == TYPE_DICTIONARY:
			var kind := str(cell.get("kind", ""))
			var mine := int(cell.get("owner", -1)) == my_index
			btn.text = "%s %s" % [GLYPHS.get(kind, "?"), KIND_NAMES.get(kind, "")]
			var fg := MINE_FG if mine else OPP_FG
			for key in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color"]:
				btn.add_theme_color_override(key, fg)
		else:
			btn.text = ""
		btn.disabled = bool(data.get("is_over", false))

	_opp_hand_label.text = "상대 포로: " + _hand_text(data.get("opp_hand", {}))
	_render_my_hand(data.get("my_hand", {}), my_turn)

	var last: Variant = data.get("last_move", null)
	_last_label.text = "마지막 수 — " + _move_text(last) if typeof(last) == TYPE_DICTIONARY else ""

	score_label.text = "%d수 / 최대 %d수" % [int(data.get("ply", 0)), int(data.get("max_plies", 200))]
	if bool(data.get("is_over", false)):
		prompt_label.text = "게임 종료"
	elif my_turn:
		prompt_label.text = "내 차례입니다. 말이나 포로를 고르고, 초록 칸에 두세요."
	else:
		prompt_label.text = "상대 차례입니다…"


func _hand_text(hand: Dictionary) -> String:
	var parts := PackedStringArray()
	for kind: String in DROP_ORDER:
		var n := int(hand.get(kind, 0))
		if n > 0:
			parts.append("%s×%d" % [GLYPHS[kind], n])
	return "없음" if parts.is_empty() else " ".join(parts)


func _render_my_hand(hand: Dictionary, my_turn: bool) -> void:
	clear_children(_my_hand_row)
	_my_hand_row.add_child(make_label("내 포로:", 14, MINE_FG, false))
	var any := false
	for kind: String in DROP_ORDER:
		var n := int(hand.get(kind, 0))
		if n <= 0:
			continue
		any = true
		var btn := make_button("%s %s ×%d" % [GLYPHS[kind], KIND_NAMES[kind], n], 96)
		btn.toggle_mode = true
		btn.button_pressed = _sel_drop == kind
		btn.disabled = not my_turn
		btn.pressed.connect(_on_hand_pressed.bind(kind))
		_my_hand_row.add_child(btn)
	if not any:
		_my_hand_row.add_child(make_label("없음", 14, MUTED, false))


func _on_hand_pressed(kind: String) -> void:
	_sel_drop = "" if _sel_drop == kind else kind
	_sel_from = Vector2i(-1, -1)
	_render_state(state)


func _on_cell_pressed(display_index: int) -> void:
	if not bool(state.get("my_turn", false)):
		return
	var pos := _to_board(display_index)
	if _targets().has(pos):
		if not _sel_drop.is_empty():
			send_action({"kind": "drop", "piece": _sel_drop, "to": [pos.x, pos.y]})
		else:
			send_action({"kind": "move", "from": [_sel_from.x, _sel_from.y], "to": [pos.x, pos.y]})
		_sel_from = Vector2i(-1, -1)
		_sel_drop = ""
		return

	var cell: Variant = _cell_at(state.get("board", []), pos)
	_sel_drop = ""
	if typeof(cell) == TYPE_DICTIONARY and int(cell.get("owner", -1)) == my_index and pos != _sel_from:
		_sel_from = pos
	else:
		_sel_from = Vector2i(-1, -1)
	_render_state(state)


func _move_text(m: Dictionary) -> String:
	var by := who(int(m.get("by", -1)))
	var kind := str(m.get("piece", ""))
	var text := ""
	if str(m.get("kind", "")) == "drop":
		text = "%s: %s 내려놓기" % [by, KIND_NAMES.get(kind, "?")]
	else:
		text = "%s: %s 이동" % [by, KIND_NAMES.get(kind, "?")]
	var captured: Variant = m.get("captured", null)
	if captured != null:
		text += ", %s 잡음" % KIND_NAMES.get(str(captured), "?")
	if bool(m.get("promoted", false)):
		text += ", 후로 승급"
	return text


func _end_lines(data: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	var reason := str(data.get("win_reason", ""))
	if REASON_TEXT.has(reason):
		lines.append(REASON_TEXT[reason])
	lines.append("총 %d수" % int(data.get("ply", 0)))
	return lines


func _history_lines(data: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	var n := 0
	for m: Dictionary in data.get("moves", []):
		n += 1
		lines.append("%d. %s" % [n, _move_text(m)])
	return lines
