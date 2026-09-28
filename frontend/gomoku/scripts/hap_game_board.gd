# hap_game_board.gd — 결! 합! (온라인 전용)
#
# 공개된 그림 9장에서 세 장을 골라 "합!", 남은 합이 없으면 "결!"을 부른다.
# 두 사람이 동시에 부를 수 있고, 서버가 먼저 도착한 요청부터 판정한다.
extends "res://scripts/duel_board.gd"

const TILE_SIZE := Vector2(104, 104)
const SHAPE_GLYPHS := {"circle": "●", "triangle": "▲", "square": "■"}
const SHAPE_COLORS := {
	"red": Color(0.86, 0.20, 0.18, 1),
	"blue": Color(0.18, 0.40, 0.86, 1),
	"yellow": Color(0.98, 0.80, 0.16, 1),
}
const BG_COLORS := {
	"black": Color(0.10, 0.10, 0.11, 1),
	"gray": Color(0.55, 0.55, 0.57, 1),
	"white": Color(0.96, 0.96, 0.95, 1),
}
const SELECT_BORDER := Color(0.98, 0.62, 0.10, 1)

var _grid: GridContainer
var _tiles: Array[Button] = []
var _selected: Array[int] = []
var _board_segment: int = -1
var _event_label: Label
var _found_label: Label
var _hap_button: Button
var _gyeol_button: Button
var _last_event_seq: int = 0


func _game_id() -> String:
	return "hap_game"


func _build_content() -> void:
	var holder := CenterContainer.new()
	content.add_child(holder)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	holder.add_child(_grid)

	_event_label = make_label("", 16, INK)
	content.add_child(_event_label)

	var buttons := make_row(14)
	content.add_child(buttons)
	_hap_button = make_button("합!", 140)
	_hap_button.pressed.connect(_on_hap_pressed)
	buttons.add_child(_hap_button)
	_gyeol_button = make_button("결!", 140)
	_gyeol_button.pressed.connect(_on_gyeol_pressed)
	buttons.add_child(_gyeol_button)

	_found_label = make_label("", 13, MUTED)
	content.add_child(_found_label)


func _tile_style(bg: Color, selected: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.set_corner_radius_all(10)
	style.border_color = SELECT_BORDER if selected else Color(0.35, 0.30, 0.24, 1)
	style.set_border_width_all(5 if selected else 1)
	return style


func _build_board(board: Array) -> void:
	clear_children(_grid)
	_tiles.clear()
	_selected.clear()
	for i in board.size():
		var card: Dictionary = board[i]
		var bg: Color = BG_COLORS.get(str(card.get("bg", "white")), Color.WHITE)
		var btn := Button.new()
		btn.custom_minimum_size = TILE_SIZE
		btn.toggle_mode = true
		btn.focus_mode = Control.FOCUS_NONE
		var normal := _tile_style(bg, false)
		var picked := _tile_style(bg, true)
		btn.add_theme_stylebox_override("normal", normal)
		btn.add_theme_stylebox_override("hover", normal)
		btn.add_theme_stylebox_override("disabled", normal)
		btn.add_theme_stylebox_override("pressed", picked)
		btn.add_theme_stylebox_override("hover_pressed", picked)
		btn.toggled.connect(_on_tile_toggled.bind(i))

		var glyph := Label.new()
		glyph.text = SHAPE_GLYPHS.get(str(card.get("shape", "circle")), "?")
		glyph.add_theme_font_size_override("font_size", 54)
		glyph.add_theme_color_override("font_color", SHAPE_COLORS.get(str(card.get("color", "red")), Color.RED))
		glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(glyph)
		glyph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

		var num := Label.new()
		num.text = str(i + 1)
		num.add_theme_font_size_override("font_size", 13)
		num.add_theme_color_override("font_color", Color(0.55, 0.55, 0.58, 1) if str(card.get("bg")) != "gray" else Color(0.15, 0.15, 0.16, 1))
		num.mouse_filter = Control.MOUSE_FILTER_IGNORE
		num.position = Vector2(8, 4)
		btn.add_child(num)

		_grid.add_child(btn)
		_tiles.append(btn)


func _on_tile_toggled(pressed: bool, index: int) -> void:
	if pressed:
		if _selected.size() >= 3:
			_tiles[index].set_pressed_no_signal(false)
			return
		_selected.append(index)
	else:
		_selected.erase(index)
	_refresh_buttons()


func _clear_selection() -> void:
	for i in _selected:
		_tiles[i].set_pressed_no_signal(false)
	_selected.clear()


func _refresh_buttons() -> void:
	var over := bool(state.get("is_over", false))
	_hap_button.disabled = over or _selected.size() != 3
	_gyeol_button.disabled = over
	for tile in _tiles:
		tile.disabled = over


func _on_hap_pressed() -> void:
	if _selected.size() != 3:
		return
	send_action({"kind": "hap", "cards": _selected.duplicate()})
	_clear_selection()
	_refresh_buttons()


func _on_gyeol_pressed() -> void:
	send_action({"kind": "gyeol"})


func _render_state(data: Dictionary) -> void:
	var seg := int(data.get("segment", 0))
	if seg != _board_segment:
		_board_segment = seg
		_last_event_seq = 0
		_build_board(data.get("board", []))

	score_label.text = "점수  나 %d : %d 상대" % [int(data.get("my_score", 0)), int(data.get("opp_score", 0))]

	var seq := int(data.get("event_seq", 0))
	var ev: Variant = data.get("last_event", null)
	if seq != _last_event_seq:
		_last_event_seq = seq
		_event_label.text = _event_text(ev) if typeof(ev) == TYPE_DICTIONARY else ""
	elif seq == 0:
		_event_label.text = ""

	var found_parts := PackedStringArray()
	for f: Dictionary in data.get("found", []):
		found_parts.append("%s(%s)" % [_combo_text(f.get("cards", [])), who(int(f.get("by", -1)))])
	_found_label.text = "찾은 합: " + (", ".join(found_parts) if not found_parts.is_empty() else "없음")

	if bool(data.get("is_over", false)):
		prompt_label.text = "게임 종료"
	else:
		prompt_label.text = "그림 3장을 골라 합!을 부르세요. 남은 합이 없다고 생각하면 결!"
	_refresh_buttons()


func _combo_text(cards: Array) -> String:
	var parts := PackedStringArray()
	for c in cards:
		parts.append(str(int(c) + 1))
	return "-".join(parts)


func _event_text(ev: Dictionary) -> String:
	var by := who(int(ev.get("by", -1)))
	var ok := bool(ev.get("ok", false))
	if str(ev.get("kind", "")) == "gyeol":
		return "%s: 결! → %s" % [by, "성공 (+3)" if ok else "실패 (-1)"]
	var combo := _combo_text(ev.get("cards", []))
	if ok:
		return "%s: 합! %s → 정답 (+1)" % [by, combo]
	var why := "이미 나온 합" if str(ev.get("reason", "")) == "already_found" else "합이 아님"
	return "%s: 합! %s → %s (-1)" % [by, combo, why]


func _end_lines(data: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray([
		"점수  나 %d : %d 상대" % [int(data.get("my_score", 0)), int(data.get("opp_score", 0))]
	])
	var ev: Variant = data.get("last_event", null)
	if typeof(ev) == TYPE_DICTIONARY:
		lines.append(_event_text(ev))
	return lines


func _history_lines(data: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	for f: Dictionary in data.get("found", []):
		lines.append("합 %s — %s" % [_combo_text(f.get("cards", [])), who(int(f.get("by", -1)))])
	return lines
