# number_janggi_board.gd — 9~10단계: 배치 UI + 이동/대결 UI (로컬 패스앤플레이)
#
# 보드는 화면 정중앙에 세로로, 들어가는 한 최대 크기로 그린다. 화면을 보는
# 사람(viewer_side)이 항상 아래쪽이 되도록, 플레이어 2 시점에서는 보드를 180도
# 뒤집는다(flip_h + flip_v). 마이너스 줄은 좌우 대칭이라 뒤집어도 그대로 맞다.
#
# 화면 상태(ui_state)로 흐름을 관리한다.
#   ARRANGE  배치 (말이 이미 깔려 있고, 옮기거나 맞바꿔서 고친다)
#   MOVE     내 말 골라서 이동
#   ITEM     대결 직전, 이동한 쪽만 아이템 하나를 쓸지 결정
#   DUEL     대결 결과 공개 (이동한 쪽 → 화면 넘긴 뒤 상대에게도 한 번)
#   REWARD   상대 끝줄 도달 보상: 죽은 말 부활
#   PASS     화면을 다음 사람에게 넘기는 중
#   OVER     승패 확정
extends Control

const Rules := preload("res://scripts/number_janggi_rules.gd")
const MatchScript := preload("res://scripts/number_janggi_match.gd")
const NetworkClientScript := preload("res://scripts/network_client.gd")

const ART_DIR := "res://art/number_janggi/"

# board.png 원본 크기와, 그 안에서 6x9 격자가 실제로 차지하는 영역.
# (격자 테두리 선의 중심을 픽셀 단위로 측정한 값)
const BOARD_TEX_SIZE := Vector2(491.0, 735.0)
const GRID_IN_TEX := Rect2(1.0, 1.0, 488.0, 732.0)

const BOARD_MARGIN := 20.0
const PANEL_WIDTH := 320.0
const GRAVE_PANEL_WIDTH := 210.0
const GRAVE_ICON := 38.0
const GRAVE_COLUMNS := 4
const TURN_SECONDS := 60.0

const SELECT_COLOR := Color(0.20, 0.95, 1.0, 1.0)
const TARGET_COLOR := Color(0.35, 0.85, 0.45, 0.34)
const DUEL_MARK_COLOR := Color(0.95, 0.25, 0.20, 0.55)
const TEXT_COLOR := Color(0.96, 0.93, 0.86, 1.0)
const SIDE_NAMES := ["Falso", "Verita"]

# 이미지 임포트 전이라 텍스처를 못 불러왔을 때만 쓰는 대체 색
const FALLBACK_NUMBER := Color(0.95, 0.86, 0.58, 1.0)
const FALLBACK_MINE := Color(0.28, 0.28, 0.30, 1.0)
const FALLBACK_KING := Color(0.74, 0.14, 0.14, 1.0)
const FALLBACK_BACK := Color(0.47, 0.48, 0.52, 1.0)

enum Ui { ARRANGE, MOVE, ITEM, DUEL, REWARD, PASS, OVER, WAIT_OPP }

var game_match: NumberJanggiMatch
var ui_state: Ui = Ui.ARRANGE
var viewer_side: int = 0
var selected_piece_id: int = -1

# ── 온라인(랜덤매칭) ────────────────────────────────────────────
# 온라인에서는 서버가 유일한 권위자다. game_match는 서버가 보내주는
# nj_state를 그대로 반영하는 "거울" 역할만 하고(직접 판정 메서드는
# 호출하지 않음), 클라이언트는 의도(이동/아이템/부활 등)만 전송한다.
var online: bool = false
var net: Node = null
var my_index: int = -1
var _online_segment_shown: int = -1
var _last_seen_event_seq: int = 0
var _post_duel_ui_state: Ui = Ui.MOVE
var _server_arrange_left: int = -1
var _server_move_left: int = -1
var _server_seconds_at_ms: int = 0

var _legal_targets: Array = []
var _turn_left: float = TURN_SECONDS
var _shown_seconds: int = -1

# 대결 연출용
var _duel_report: Array = []  # 지금 화면에 띄울 대결 내역
var _duel_hidden: Array = []  # 블라인드로 가려진 말 id
var _duel_masked: bool = false  # true면 블라인드 말을 "?"로 가림
var _duel_for_receiver: bool = false  # 화면 넘긴 뒤 상대에게 보여주는 중
var _duel_pending_result: Dictionary = {}  # 확인 누르면 이어서 처리할 결과
var _carry_duels: Array = []  # 상대에게 넘겨줄 대결 내역 (한 턴 누적)
var _carry_hidden: Array = []
var _temp_revealed: Dictionary = {}  # 연출 동안만 앞면으로 보여줄 말
var _event_pieces: Dictionary = {}  # 온라인: 대결 로그에만 등장하는 말 정보

# 화면 넘김
var _pass_target_side: int = 0
var _pass_next_state: Ui = Ui.MOVE

var _board_tex: TextureRect
var _highlight_layer: Control
var _pieces_layer: Control

var _panel_root: PanelContainer
var _status_label: Label
var _timer_label: Label
var _info_label: Label
var _dyn_box: VBoxContainer

var _grave_root: PanelContainer
var _grave_opp_title: Label
var _grave_opp_grid: GridContainer
var _grave_mine_title: Label
var _grave_mine_grid: GridContainer

var _modal: Control
var _modal_box: VBoxContainer

var _face_tex: Dictionary = {}  # piece_id -> Texture2D (앞면)
var _back_tex: Array = [null, null]  # side -> Texture2D (뒷면)

var _board_rect: Rect2 = Rect2()
var _grid_rect: Rect2 = Rect2()
var _cell: Vector2 = Vector2.ZERO


func _ready() -> void:
	_build_layers()
	_build_panel()
	_build_graveyard_panel()
	_build_modal()
	online = GameSession.mode == GameSession.Mode.ONLINE or GameSession.mode == GameSession.Mode.QUICK
	if online:
		_start_online()
	else:
		_start_new_game()
	resized.connect(_relayout)
	_relayout()


func _start_new_game() -> void:
	game_match = MatchScript.new()
	game_match.start_new_match()
	_load_art()
	_apply_default_arrangement(0)
	_apply_default_arrangement(1)

	ui_state = Ui.ARRANGE
	viewer_side = 0
	selected_piece_id = -1
	_legal_targets = []
	_turn_left = TURN_SECONDS
	_shown_seconds = -1
	_clear_duel_state()
	_carry_duels = []
	_carry_hidden = []


## 온라인 매치 시작 — 로컬 엔진을 돌리지 않고, 서버 상태를 기다린다.
func _start_online() -> void:
	game_match = MatchScript.new()
	game_match.board = []
	for _r in Rules.BOARD_ROWS:
		var row_cells: Array = []
		for _c in Rules.BOARD_COLS:
			row_cells.append(-1)
		game_match.board.append(row_cells)

	_load_art()
	ui_state = Ui.ARRANGE
	viewer_side = 0
	my_index = -1
	selected_piece_id = -1
	_legal_targets = []
	_clear_duel_state()
	_shown_seconds = -1
	_online_segment_shown = -1
	_last_seen_event_seq = 0

	_status_label.text = "서버 연결 중…"
	_timer_label.text = ""
	_info_label.text = ""
	_start_network()


func _clear_duel_state() -> void:
	_duel_report = []
	_duel_hidden = []
	_duel_masked = false
	_duel_for_receiver = false
	_duel_pending_result = {}
	_temp_revealed = {}
	_event_pieces = {}


# ── 리소스 ──────────────────────────────────────────────────────
## 로컬 모드에서는 28개(양쪽 14개씩) 전부 알고 있으니 한 번에 불러오고,
## 온라인 모드에서는 상대 말 정체를 모르니 알려질 때마다(_ensure_face_tex)
## 그때그때 불러온다. 텍스처 이름은 id로부터 결정적으로 계산되므로 두
## 경로가 항상 같은 결과를 낸다.
func _load_art() -> void:
	_board_tex.texture = _try_load("board")
	_back_tex[0] = _try_load("back_falso")
	_back_tex[1] = _try_load("back_verita")

	_face_tex.clear()
	for id in game_match.pieces.keys():
		_ensure_face_tex(id)


func _ensure_face_tex(id: int) -> void:
	if id < 0 or _face_tex.has(id) or not game_match.pieces.has(id):
		return
	var p: Dictionary = game_match.pieces[id]
	_face_tex[id] = _try_load(_texture_name_for(int(p.side), int(p.type), int(p.value), id))


## id는 생성 순서를 그대로 담고 있다(숫자 1~10 → 지뢰 3개 → 왕, side당 14개).
## 그래서 값을 몰라도 id만으로 "몇 번째 지뢰인지"를 계산할 수 있다.
func _texture_name_for(side: int, type: int, value: int, id: int) -> String:
	var prefix: String = "" if side == 0 else "opp_"
	if type == Rules.PieceType.MINE:
		var base_id: int = side * Rules.TOTAL_PIECE_COUNT + Rules.NUMBER_COUNT
		return "%smine%d" % [prefix, id - base_id + 1]
	if type == Rules.PieceType.KING:
		return "%sking" % prefix
	return "%sp%d" % [prefix, value]


func _try_load(base_name: String) -> Texture2D:
	var path := ART_DIR + base_name + ".png"
	if not ResourceLoader.exists(path):
		push_warning("숫자장기 이미지 없음: %s (고도 에디터를 한 번 열어 임포트하세요)" % path)
		return null
	return load(path) as Texture2D


# ── 기본 배치 ───────────────────────────────────────────────────
## 자기 진영 3줄에 14개 말을 미리 깔아둔다. 앞줄 1~6, 가운뎃줄 7~10,
## 맨 뒷줄에 지뢰 3개와 왕.
func _apply_default_arrangement(side: int) -> void:
	for id in game_match.side_piece_ids(side):
		game_match.unplace_piece(side, id)

	var back_row: int = Rules.own_back_row(side)
	var fwd: int = Rules.forward_dir(side)
	var mid_row: int = back_row + fwd
	var front_row: int = back_row + 2 * fwd

	for v in range(1, 7):
		game_match.place_piece(side, game_match.find_piece_id(side, Rules.PieceType.NUMBER, v), _default_col(side, v - 1), front_row)
	for v in range(7, 11):
		game_match.place_piece(side, game_match.find_piece_id(side, Rules.PieceType.NUMBER, v), _default_col(side, v - 6), mid_row)

	var mine_ids: Array = []
	for id in game_match.side_piece_ids(side):
		if game_match.pieces[id].type == Rules.PieceType.MINE:
			mine_ids.append(id)
	mine_ids.sort()
	for i in mine_ids.size():
		game_match.place_piece(side, mine_ids[i], _default_col(side, i + 1), back_row)
	game_match.place_piece(side, game_match.find_piece_id(side, Rules.PieceType.KING), _default_col(side, 4), back_row)


## 두 플레이어 모두 "자기 시점에서" 1→6이 왼쪽부터 보이도록, 위쪽 진영은
## 열 순서를 좌우 반전해서 깐다.
func _default_col(side: int, view_col: int) -> int:
	return view_col if side == 0 else Rules.BOARD_COLS - 1 - view_col


# ── 노드 구성 ───────────────────────────────────────────────────
func _build_layers() -> void:
	_board_tex = TextureRect.new()
	_board_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_board_tex.stretch_mode = TextureRect.STRETCH_SCALE
	_board_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_board_tex)

	_highlight_layer = Control.new()
	_highlight_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_highlight_layer)

	_pieces_layer = Control.new()
	_pieces_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_pieces_layer)


func _build_panel() -> void:
	_panel_root = PanelContainer.new()
	_panel_root.add_theme_stylebox_override("panel", _dark_panel_style())
	add_child(_panel_root)

	var margin := MarginContainer.new()
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 16)
	_panel_root.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)

	box.add_child(_make_label("숫자장기", 24))

	_status_label = _make_label("", 17)
	box.add_child(_status_label)

	_timer_label = _make_label("", 17)
	box.add_child(_timer_label)

	_info_label = _make_label("", 14)
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_label.custom_minimum_size = Vector2(PANEL_WIDTH - 40.0, 0)
	box.add_child(_info_label)

	_dyn_box = VBoxContainer.new()
	_dyn_box.add_theme_constant_override("separation", 8)
	box.add_child(_dyn_box)

	box.add_child(HSeparator.new())
	box.add_child(_make_button("로비로 나가기", _on_lobby_pressed))


## 보드 왼쪽에 제거된 말을 쌓아 보여준다. 화면 방향과 맞춰 위쪽이 상대가
## 잃은 말, 아래쪽이 내가 잃은 말.
func _build_graveyard_panel() -> void:
	_grave_root = PanelContainer.new()
	_grave_root.add_theme_stylebox_override("panel", _dark_panel_style())
	add_child(_grave_root)

	var margin := MarginContainer.new()
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 14)
	_grave_root.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)

	box.add_child(_make_label("잃은 말", 19))

	_grave_opp_title = _make_label("", 14)
	box.add_child(_grave_opp_title)
	_grave_opp_grid = _make_grave_grid()
	box.add_child(_grave_opp_grid)

	box.add_child(HSeparator.new())

	_grave_mine_title = _make_label("", 14)
	box.add_child(_grave_mine_title)
	_grave_mine_grid = _make_grave_grid()
	box.add_child(_grave_mine_grid)


func _make_grave_grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = GRAVE_COLUMNS
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	return grid


func _fill_graveyard() -> void:
	_grave_opp_title.text = "상대 (%s) 잃은 말 %d개" % [
		SIDE_NAMES[1 - viewer_side], game_match.graveyard_of(1 - viewer_side).size()
	]
	_grave_mine_title.text = "내가 (%s) 잃은 말 %d개" % [
		SIDE_NAMES[viewer_side], game_match.graveyard_of(viewer_side).size()
	]
	_fill_grave_grid(_grave_opp_grid, 1 - viewer_side)
	_fill_grave_grid(_grave_mine_grid, viewer_side)


func _fill_grave_grid(grid: GridContainer, side: int) -> void:
	var ids: Array = game_match.graveyard_of(side)
	if ids.is_empty():
		grid.add_child(_make_label("없음", 14))
		return
	for id in ids:
		var p: Dictionary = game_match.pieces[id]
		var face_up := _is_face_up(p)
		var tex: Texture2D = _face_tex.get(id, null) if face_up else _back_tex[int(p.side)]
		if tex == null:
			grid.add_child(_make_label(_short_name(p) if face_up else "?", 14, true))
			continue
		var icon := TextureRect.new()
		icon.texture = tex
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_SCALE
		icon.custom_minimum_size = Vector2(GRAVE_ICON, GRAVE_ICON)
		icon.tooltip_text = _short_name(p) if face_up else "정체 불명 (블라인드)"
		grid.add_child(icon)


func _build_modal() -> void:
	_modal = Control.new()
	_modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	_modal.visible = false
	add_child(_modal)

	var dimmer := ColorRect.new()
	dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	dimmer.color = Color(0.03, 0.03, 0.04, 0.72)
	_modal.add_child(dimmer)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal.add_child(center)

	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", _dark_panel_style())
	center.add_child(frame)

	var margin := MarginContainer.new()
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 24)
	frame.add_child(margin)

	_modal_box = VBoxContainer.new()
	_modal_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_modal_box.custom_minimum_size = Vector2(420, 0)
	_modal_box.add_theme_constant_override("separation", 14)
	margin.add_child(_modal_box)


func _dark_panel_style() -> StyleBoxFlat:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.10, 0.09, 0.08, 0.90)
	bg.border_color = Color(0.85, 0.74, 0.48, 0.55)
	bg.set_border_width_all(2)
	bg.set_corner_radius_all(10)
	return bg


func _make_label(text: String, font_size: int, align_center: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", TEXT_COLOR)
	if align_center:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


func _make_button(text: String, callback: Callable, disabled: bool = false) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, 44)
	btn.disabled = disabled
	btn.add_theme_font_size_override("font_size", 16)
	btn.add_theme_stylebox_override("normal", _button_style(Color(0.24, 0.21, 0.17, 0.95)))
	btn.add_theme_stylebox_override("hover", _button_style(Color(0.35, 0.30, 0.23, 1.0)))
	btn.add_theme_stylebox_override("pressed", _button_style(Color(0.17, 0.15, 0.12, 1.0)))
	btn.add_theme_stylebox_override("disabled", _button_style(Color(0.15, 0.14, 0.13, 0.7)))
	btn.add_theme_color_override("font_color", TEXT_COLOR)
	btn.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.82, 1.0))
	btn.add_theme_color_override("font_disabled_color", Color(0.52, 0.49, 0.45, 1.0))
	btn.pressed.connect(callback)
	return btn


func _button_style(bg_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = Color(0.85, 0.74, 0.48, 0.6)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	return style


# ── 레이아웃 (창 크기에 맞춰 보드를 정중앙 최대 크기로) ────────────
func _relayout() -> void:
	var avail := size - Vector2(BOARD_MARGIN, BOARD_MARGIN) * 2.0
	if avail.x <= 0.0 or avail.y <= 0.0:
		return
	var scale_f: float = min(avail.x / BOARD_TEX_SIZE.x, avail.y / BOARD_TEX_SIZE.y)
	var board_size := (BOARD_TEX_SIZE * scale_f).floor()
	_board_rect = Rect2(((size - board_size) * 0.5).floor(), board_size)
	_board_tex.position = _board_rect.position
	_board_tex.size = _board_rect.size

	_grid_rect = Rect2(
		_board_rect.position + GRID_IN_TEX.position * scale_f,
		GRID_IN_TEX.size * scale_f
	)
	_cell = Vector2(_grid_rect.size.x / Rules.BOARD_COLS, _grid_rect.size.y / Rules.BOARD_ROWS)

	var panel_x: float = _board_rect.position.x + _board_rect.size.x + 20.0
	panel_x = min(panel_x, size.x - PANEL_WIDTH - 12.0)
	_panel_root.position = Vector2(max(panel_x, 12.0), _board_rect.position.y)
	_panel_root.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	_panel_root.size = Vector2(PANEL_WIDTH, 0)

	var grave_x: float = _board_rect.position.x - 20.0 - GRAVE_PANEL_WIDTH
	_grave_root.position = Vector2(max(grave_x, 12.0), _board_rect.position.y)
	_grave_root.custom_minimum_size = Vector2(GRAVE_PANEL_WIDTH, 0)
	_grave_root.size = Vector2(GRAVE_PANEL_WIDTH, 0)

	_refresh()


# ── 좌표 변환 ───────────────────────────────────────────────────
## 보드 좌표 ↔ 화면(시점) 좌표. 화면을 보는 사람이 아래쪽이 되도록,
## 플레이어 2 시점에서는 180도 회전. 변환식이 양방향 같으므로 함수 하나로 쓴다.
func _flip(col: int, row: int) -> Vector2i:
	if viewer_side == 1:
		return Vector2i(Rules.BOARD_COLS - 1 - col, Rules.BOARD_ROWS - 1 - row)
	return Vector2i(col, row)


func _cell_rect(col: int, row: int) -> Rect2:
	var v := _flip(col, row)
	return Rect2(_grid_rect.position + Vector2(v.x * _cell.x, v.y * _cell.y), _cell)


func _cell_at(pos: Vector2) -> Vector2i:
	if _cell == Vector2.ZERO or not _grid_rect.has_point(pos):
		return Vector2i(-1, -1)
	var vcol: int = clampi(int((pos.x - _grid_rect.position.x) / _cell.x), 0, Rules.BOARD_COLS - 1)
	var vrow: int = clampi(int((pos.y - _grid_rect.position.y) / _cell.y), 0, Rules.BOARD_ROWS - 1)
	return _flip(vcol, vrow)


# ── 턴 타이머 ───────────────────────────────────────────────────
## 온라인에서는 서버가 유일하게 타임아웃을 판정한다(60초는 서버 쪽
## _arrange_task/_move_task). 여기서는 서버가 매 상태와 함께 보내주는
## "남은 초" 스냅샷을 기준으로 화면 카운트다운만 보여준다.
func _process(delta: float) -> void:
	if online:
		_process_online_timer()
		return
	if ui_state != Ui.MOVE and ui_state != Ui.ARRANGE:
		return
	_turn_left -= delta
	if _turn_left <= 0.0:
		_turn_left = 0.0
		_on_timeout()
		return
	var secs := int(ceil(_turn_left))
	if secs != _shown_seconds:
		_shown_seconds = secs
		_timer_label.text = "남은 시간 %d초" % secs


func _process_online_timer() -> void:
	var left: int = -1
	if ui_state == Ui.ARRANGE:
		left = _server_arrange_left
	elif ui_state == Ui.MOVE:
		left = _server_move_left
	if left < 0:
		if _shown_seconds != -1:
			_shown_seconds = -1
			_timer_label.text = ""
		return
	var elapsed: float = (Time.get_ticks_msec() - _server_seconds_at_ms) / 1000.0
	var remaining: int = int(max(0.0, ceil(left - elapsed)))
	if remaining != _shown_seconds:
		_shown_seconds = remaining
		_timer_label.text = "남은 시간 %d초" % remaining


func _on_timeout() -> void:
	if ui_state == Ui.ARRANGE:
		# 말은 이미 다 깔려 있으니 시간이 다 되면 그대로 준비완료 처리.
		_on_ready_pressed()
		return
	game_match.force_move_timeout()
	ui_state = Ui.OVER
	_refresh()


func _reset_timer() -> void:
	_turn_left = TURN_SECONDS
	_shown_seconds = -1


# ── 화면 갱신 ───────────────────────────────────────────────────
func _refresh() -> void:
	for holder in [_highlight_layer, _pieces_layer, _dyn_box, _modal_box, _grave_opp_grid, _grave_mine_grid]:
		for child in holder.get_children():
			holder.remove_child(child)
			child.queue_free()

	_board_tex.flip_h = viewer_side == 1
	_board_tex.flip_v = viewer_side == 1

	_update_panel()
	_fill_graveyard()
	_update_modal()

	if _cell == Vector2.ZERO:
		return
	_draw_highlights()
	for row in Rules.BOARD_ROWS:
		for col in Rules.BOARD_COLS:
			var piece_id: int = game_match.board[row][col]
			if piece_id != -1:
				_add_piece(piece_id, col, row)


func _update_panel() -> void:
	var who := ("나 (%s)" % SIDE_NAMES[viewer_side]) if online else (
		"플레이어 %d (%s)" % [viewer_side + 1, SIDE_NAMES[viewer_side]]
	)
	match ui_state:
		Ui.ARRANGE:
			_status_label.text = who + " 배치 중"
			if not online:
				_timer_label.text = "남은 시간 %d초" % int(ceil(_turn_left))
			_info_label.text = "말 14개가 이미 진영에 놓여 있습니다.\n· 내 말 클릭 → 선택\n· 빈 칸 클릭 → 그 자리로 이동\n· 다른 내 말 클릭 → 자리 맞바꾸기"
			_dyn_box.add_child(_make_button("기본 배치로 되돌리기", _on_reset_pressed))
			if online:
				var ready_done: bool = game_match.ready_flags[viewer_side]
				_dyn_box.add_child(_make_button(
					"준비완료 (상대 대기 중)" if ready_done else "준비완료",
					_on_ready_pressed,
					ready_done
				))
			else:
				_dyn_box.add_child(_make_button("준비완료", _on_ready_pressed))
		Ui.MOVE:
			if online:
				_status_label.text = who + (" 차례" if game_match.current_turn == viewer_side else " · 상대 차례 대기 중")
			else:
				_status_label.text = who + " 차례"
			if not online:
				_timer_label.text = "남은 시간 %d초" % int(ceil(_turn_left))
			_info_label.text = _board_info_text()
		Ui.WAIT_OPP:
			_status_label.text = "상대가 결정하는 중…"
			_timer_label.text = ""
			_info_label.text = _board_info_text()
		_:
			_status_label.text = who
			_timer_label.text = ""
			_info_label.text = _board_info_text()


func _board_info_text() -> String:
	var mine_alive := _alive_count(viewer_side)
	var opp_alive := _alive_count(1 - viewer_side)
	return "내 말 %d개 / 상대 말 %d개\n내 아이템: %s" % [
		mine_alive, opp_alive, _items_text(viewer_side)
	]


func _alive_count(side: int) -> int:
	var n := 0
	for id in game_match.side_piece_ids(side):
		if game_match.pieces[id].alive:
			n += 1
	return n


func _items_text(side: int) -> String:
	var used: Dictionary = game_match.used_items[side]
	var parts: Array = []
	parts.append("블라인드 " + ("사용" if used["blind"] else "가능"))
	parts.append("+1 " + ("사용" if used["plus1"] else "가능"))
	parts.append("-1 " + ("사용" if used["minus1"] else "가능"))
	return ", ".join(parts)


func _draw_highlights() -> void:
	if ui_state == Ui.ARRANGE and selected_piece_id != -1:
		for row in Rules.BOARD_ROWS:
			for col in Rules.BOARD_COLS:
				if Rules.is_own_camp(col, row, viewer_side) and game_match.board[row][col] == -1:
					_add_rect(_cell_rect(col, row), TARGET_COLOR, 0.16)
	elif ui_state == Ui.MOVE:
		for t in _legal_targets:
			_add_rect(_cell_rect(t[0], t[1]), TARGET_COLOR, 0.16)


func _add_rect(rect: Rect2, color: Color, inset_ratio: float) -> void:
	var box := ColorRect.new()
	box.color = color
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var inset := _cell * inset_ratio
	box.position = rect.position + inset
	box.size = rect.size - inset * 2.0
	_highlight_layer.add_child(box)


func _is_face_up(p: Dictionary) -> bool:
	return p.side == viewer_side or p.revealed or _temp_revealed.has(p.id)


func _add_piece(piece_id: int, col: int, row: int) -> void:
	var p: Dictionary = game_match.pieces[piece_id]
	var face_up := _is_face_up(p)
	var tex: Texture2D = _face_tex.get(piece_id, null) if face_up else _back_tex[int(p.side)]

	var rect := _cell_rect(col, row)
	var inset := _cell * 0.05
	var draw_rect := Rect2(rect.position + inset, rect.size - inset * 2.0)

	if tex != null:
		var node := TextureRect.new()
		node.texture = tex
		node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		node.stretch_mode = TextureRect.STRETCH_SCALE
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		node.position = draw_rect.position
		node.size = draw_rect.size
		_pieces_layer.add_child(node)
	else:
		_add_fallback_piece(p, face_up, draw_rect)

	if piece_id == selected_piece_id:
		_add_border(draw_rect, SELECT_COLOR)
	elif _temp_revealed.has(piece_id):
		_add_border(draw_rect, DUEL_MARK_COLOR)


func _add_border(rect: Rect2, color: Color) -> void:
	var border := Panel.new()
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.border_color = color
	style.set_border_width_all(4)
	style.set_corner_radius_all(4)
	border.add_theme_stylebox_override("panel", style)
	border.position = rect.position
	border.size = rect.size
	_pieces_layer.add_child(border)


## 이미지 임포트가 아직 안 된 상태에서도 판이 비어 보이지 않게 하는 대체 표시.
func _add_fallback_piece(p: Dictionary, face_up: bool, rect: Rect2) -> void:
	var tile := Panel.new()
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	if not face_up:
		style.bg_color = FALLBACK_BACK
	elif p.type == Rules.PieceType.MINE:
		style.bg_color = FALLBACK_MINE
	elif p.type == Rules.PieceType.KING:
		style.bg_color = FALLBACK_KING
	else:
		style.bg_color = FALLBACK_NUMBER
	style.set_corner_radius_all(4)
	tile.add_theme_stylebox_override("panel", style)
	tile.position = rect.position
	tile.size = rect.size
	_pieces_layer.add_child(tile)

	if not face_up:
		return
	var label := _make_label(_short_name(p), int(rect.size.y * 0.45), true)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", Color(0.12, 0.10, 0.08, 1))
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.position = rect.position
	label.size = rect.size
	_pieces_layer.add_child(label)


func _short_name(p: Dictionary) -> String:
	if p.type == Rules.PieceType.MINE:
		return "지뢰"
	if p.type == Rules.PieceType.KING:
		return "왕"
	return str(p.value)


# ── 모달 (아이템 / 대결 / 부활 / 화면넘김 / 종료) ─────────────────
func _update_modal() -> void:
	_modal.visible = (
		ui_state == Ui.ITEM or ui_state == Ui.DUEL or ui_state == Ui.REWARD
		or ui_state == Ui.PASS or ui_state == Ui.OVER or ui_state == Ui.WAIT_OPP
	)
	if not _modal.visible:
		return
	match ui_state:
		Ui.ITEM:
			_fill_item_modal()
		Ui.DUEL:
			_fill_duel_modal()
		Ui.REWARD:
			_fill_reward_modal()
		Ui.PASS:
			_fill_pass_modal()
		Ui.OVER:
			_fill_over_modal()
		Ui.WAIT_OPP:
			_fill_wait_modal()


## 온라인 전용 — 대결/부활 결정권이 상대에게 있는 동안 보여주는 대기 화면.
func _fill_wait_modal() -> void:
	_modal_box.add_child(_make_label("상대의 결정을 기다리는 중…", 22, true))
	var hint := (
		"상대가 아이템 사용 여부를 정하고 있습니다."
		if game_match.phase == MatchScript.Phase.AWAITING_ITEMS
		else "상대가 부활할 말을 고르고 있습니다."
	)
	_modal_box.add_child(_make_label(hint, 15, true))


func _fill_item_modal() -> void:
	_modal_box.add_child(_make_label("대결 발생! 아이템을 쓸까요?", 24, true))
	_modal_box.add_child(_make_label(
		"이동한 쪽만 쓸 수 있고, 한 번 쓴 아이템은 다시 못 씁니다.\n이번 대결에만 적용됩니다.", 15, true
	))
	var used: Dictionary = game_match.used_items[viewer_side]
	_modal_box.add_child(_make_button(
		"블라인드 (내 말 정체 숨기기)",
		_on_item_pressed.bind(MatchScript.ItemType.BLIND),
		used["blind"]
	))
	_modal_box.add_child(_make_button(
		"플러스 1 (내 숫자 +1)",
		_on_item_pressed.bind(MatchScript.ItemType.PLUS_ONE),
		used["plus1"]
	))
	_modal_box.add_child(_make_button(
		"마이너스 1 (내 숫자 -1)",
		_on_item_pressed.bind(MatchScript.ItemType.MINUS_ONE),
		used["minus1"]
	))
	_modal_box.add_child(_make_button("안 쓰고 대결", _on_item_declined))


func _fill_duel_modal() -> void:
	_modal_box.add_child(_make_label("대결 결과", 24, true))
	for report in _duel_report:
		_modal_box.add_child(_duel_row(report))
	_modal_box.add_child(_make_label(_duel_summary_text(), 15, true))
	_modal_box.add_child(_make_button("확인", _on_duel_confirm_pressed))


func _duel_row(report: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	row.add_child(_duel_piece_box(report.a_id, report.a_value, report.a_removed))
	row.add_child(_make_label(_duel_middle_text(report), 16, true))
	row.add_child(_duel_piece_box(report.b_id, report.b_value, report.b_removed))
	return row


func _duel_piece_box(piece_id: int, effective_value: int, removed: bool) -> Control:
	var p: Dictionary = game_match.pieces[piece_id]
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER

	var masked: bool = _duel_masked and _duel_hidden.has(piece_id)
	var tex: Texture2D = _back_tex[int(p.side)] if masked else _face_tex.get(piece_id, null)
	if tex != null:
		var icon := TextureRect.new()
		icon.texture = tex
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_SCALE
		icon.custom_minimum_size = Vector2(64, 64)
		box.add_child(icon)

	var name_text := "?" if masked else _short_name(p)
	if not masked and p.type == Rules.PieceType.NUMBER and effective_value != int(p.value):
		name_text = "%d → %d" % [int(p.value), effective_value]
	box.add_child(_make_label(name_text, 17, true))
	box.add_child(_make_label(
		"플레이어 %d" % (int(p.side) + 1) + ("\n제거" if removed else ""), 13, true
	))
	return box


## 블라인드가 걸린 대결은 상대에게 "결과만" 공개해야 하므로, 합·차 같은
## 계산 값을 보여주면 정체가 역산된다. 그래서 값을 가린다.
func _report_masked(report: Dictionary) -> bool:
	if not _duel_masked:
		return false
	return _duel_hidden.has(report.a_id) or _duel_hidden.has(report.b_id)


func _duel_middle_text(report: Dictionary) -> String:
	match String(report.kind):
		"king_vs_king":
			return "왕 vs 왕\n무사"
		"king":
			return "왕 잡힘"
		"mine":
			return "지뢰 자폭"
		"tie":
			return "같은 숫자"
	if _report_masked(report):
		return "대결\n(값 비공개)"
	if report.is_minus:
		return "마이너스\n차 %d" % int(report.score)
	return "합 %d" % int(report.score)


func _duel_summary_text() -> String:
	var lines: Array = []
	for report in _duel_report:
		match String(report.kind):
			"king_vs_king":
				lines.append("왕끼리 만나 아무 일도 없었습니다.")
			"king":
				lines.append("왕이 잡혔습니다.")
			"mine":
				lines.append("지뢰가 터져 두 말 모두 제거됐습니다.")
			"tie":
				lines.append("숫자가 같아 두 말 모두 제거됐습니다.")
			_:
				if _report_masked(report):
					lines.append("블라인드가 쓰여 정체와 계산 값은 공개되지 않습니다.")
				else:
					var rule := "10 이상이라 큰 수가 승리" if int(report.score) >= 10 else "10보다 낮아 작은 수가 승리"
					lines.append(rule + ".")
	return "\n".join(lines)


func _fill_reward_modal() -> void:
	_modal_box.add_child(_make_label("상대 진영 끝줄 도달!", 24, true))
	var graveyard: Array = game_match.graveyard_of(viewer_side)
	if graveyard.is_empty():
		_modal_box.add_child(_make_label(
			"되살릴 말이 없습니다.\n도달한 말을 숫자가 공개된 채로 그 자리에 둡니다.", 15, true
		))
		var arrived: int = int(game_match.pending_reward.piece_id)
		_modal_box.add_child(_make_button("도달한 말 공개하고 계속", _on_revive_pressed.bind(arrived)))
	else:
		_modal_box.add_child(_make_label(
			"도달한 말을 제거하고, 죽은 말 하나를 공개된 채로 내 진영 끝줄에 되살립니다.", 15, true
		))
		var grid := GridContainer.new()
		grid.columns = 5
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		for id in graveyard:
			var p: Dictionary = game_match.pieces[id]
			var btn := _make_button(_short_name(p), _on_revive_pressed.bind(int(id)))
			btn.custom_minimum_size = Vector2(76, 96)
			btn.icon = _face_tex.get(id, null)
			btn.expand_icon = true
			btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
			grid.add_child(btn)
		_modal_box.add_child(grid)
	_modal_box.add_child(_make_button("부활 안 받기", _on_decline_reward_pressed))


func _fill_pass_modal() -> void:
	_modal_box.add_child(_make_label(
		"화면을 플레이어 %d (%s)에게 넘겨주세요." % [
			_pass_target_side + 1, SIDE_NAMES[_pass_target_side]
		], 24, true
	))
	_modal_box.add_child(_make_label("다른 사람은 화면을 보지 마세요.", 15, true))
	_modal_box.add_child(_make_button("확인 (화면 넘김)", _on_pass_continue_pressed))


func _fill_over_modal() -> void:
	var reasons := {
		"king_captured": "상대 왕을 잡았습니다.",
		"all_non_king_captured": "왕을 제외한 상대 말을 모두 잡았습니다.",
		"king_reached_end": "왕이 상대 진영 끝줄에 도달했습니다.",
		"move_timeout": "상대가 제한시간 안에 말을 옮기지 못했습니다.",
		"arrange_timeout": "상대가 제한시간 안에 배치를 마치지 못했습니다.",
	}
	_modal_box.add_child(_make_label(
		"플레이어 %d (%s) 승리!" % [game_match.winner + 1, SIDE_NAMES[game_match.winner]], 28, true
	))
	_modal_box.add_child(_make_label(reasons.get(game_match.win_reason, game_match.win_reason), 16, true))
	_modal_box.add_child(_make_button("다시 시작", _on_restart_pressed))


# ── 입력 ────────────────────────────────────────────────────────
func _gui_input(event: InputEvent) -> void:
	if ui_state != Ui.ARRANGE and ui_state != Ui.MOVE:
		return
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var cell := _cell_at(event.position)
	if cell.x < 0:
		return
	accept_event()
	if ui_state == Ui.ARRANGE:
		_handle_arrange_click(cell.x, cell.y)
	else:
		_handle_move_click(cell.x, cell.y)


func _handle_arrange_click(col: int, row: int) -> void:
	var occupant: int = game_match.board[row][col]
	if occupant != -1 and game_match.pieces[occupant].side == viewer_side:
		if selected_piece_id == -1:
			selected_piece_id = occupant
		elif selected_piece_id == occupant:
			selected_piece_id = -1
		else:
			_swap_pieces(selected_piece_id, occupant)
			selected_piece_id = -1
	elif occupant == -1 and selected_piece_id != -1:
		if online:
			net.send_nj_arrange_move(selected_piece_id, col, row)
			selected_piece_id = -1
		elif game_match.place_piece(viewer_side, selected_piece_id, col, row).ok:
			selected_piece_id = -1
	_refresh()


func _handle_move_click(col: int, row: int) -> void:
	if game_match.current_turn != viewer_side:
		return
	var occupant: int = game_match.board[row][col]
	if occupant != -1 and game_match.pieces[occupant].side == viewer_side:
		if selected_piece_id == occupant:
			selected_piece_id = -1
			_legal_targets = []
		else:
			selected_piece_id = occupant
			_legal_targets = game_match.legal_moves(occupant)
		_refresh()
		return
	if selected_piece_id == -1 or not _is_legal_target(col, row):
		return
	var piece_id := selected_piece_id
	selected_piece_id = -1
	_legal_targets = []
	if online:
		net.send_nj_move(piece_id, col, row)
		_refresh()
		return
	var result: Dictionary = game_match.move_piece(viewer_side, piece_id, col, row)
	if not result.ok:
		_refresh()
		return
	_continue_flow(result)


func _is_legal_target(col: int, row: int) -> bool:
	for t in _legal_targets:
		if int(t[0]) == col and int(t[1]) == row:
			return true
	return false


func _swap_pieces(a_id: int, b_id: int) -> void:
	if online:
		net.send_nj_arrange_swap(a_id, b_id)
		return
	var a: Dictionary = game_match.pieces[a_id]
	var b: Dictionary = game_match.pieces[b_id]
	var a_col: int = a.col
	var a_row: int = a.row
	var b_col: int = b.col
	var b_row: int = b.row
	game_match.unplace_piece(viewer_side, a_id)
	game_match.unplace_piece(viewer_side, b_id)
	game_match.place_piece(viewer_side, a_id, b_col, b_row)
	game_match.place_piece(viewer_side, b_id, a_col, a_row)


# ── 흐름 제어 ───────────────────────────────────────────────────
## 이동/대결/부활 결과를 받아 다음 화면을 정한다.
func _continue_flow(result: Dictionary) -> void:
	if result.get("game_over", false):
		ui_state = Ui.OVER
		_refresh()
		return
	if result.get("awaiting_reward", false):
		ui_state = Ui.REWARD
		_refresh()
		return
	if game_match.phase == MatchScript.Phase.AWAITING_ITEMS:
		ui_state = Ui.ITEM
		_refresh()
		return
	_goto_pass(game_match.current_turn, Ui.MOVE)


func _goto_pass(target_side: int, next_state: Ui) -> void:
	_pass_target_side = target_side
	_pass_next_state = next_state
	selected_piece_id = -1
	_legal_targets = []
	_temp_revealed = {}
	ui_state = Ui.PASS
	_refresh()


func _on_pass_continue_pressed() -> void:
	viewer_side = _pass_target_side
	selected_piece_id = -1
	_legal_targets = []
	_reset_timer()

	# 넘겨받은 사람에게도 지난 턴의 대결 결과를 한 번 보여준다.
	if _pass_next_state == Ui.MOVE and not _carry_duels.is_empty():
		_duel_report = _carry_duels
		_duel_hidden = _carry_hidden
		_carry_duels = []
		_carry_hidden = []
		_duel_masked = true
		_duel_for_receiver = true
		_set_temp_revealed()
		ui_state = Ui.DUEL
		_refresh()
		return

	ui_state = _pass_next_state
	_refresh()


func _on_item_pressed(item_type: int) -> void:
	if online:
		net.send_nj_item(item_type)
		return
	if not game_match.declare_item(viewer_side, item_type).ok:
		return
	_resolve_and_show_duels()


func _on_item_declined() -> void:
	if online:
		net.send_nj_item_decline()
		return
	if not game_match.decline_item(viewer_side).ok:
		return
	_resolve_and_show_duels()


func _resolve_and_show_duels() -> void:
	var result: Dictionary = game_match.resolve_duels()
	if not result.ok:
		_refresh()
		return
	_duel_report = result.get("duels", [])
	_duel_hidden = result.get("hidden_ids", [])
	_duel_masked = false
	_duel_for_receiver = false
	_duel_pending_result = result
	for report in _duel_report:
		_carry_duels.append(report)
	for id in _duel_hidden:
		_carry_hidden.append(id)
	_set_temp_revealed()
	ui_state = Ui.DUEL
	_refresh()


## 대결에 참여한 말은 연출 동안 판에서도 앞면으로 보여준다.
func _set_temp_revealed() -> void:
	_temp_revealed = {}
	for report in _duel_report:
		if not (_duel_masked and _duel_hidden.has(report.a_id)):
			_temp_revealed[int(report.a_id)] = true
		if not (_duel_masked and _duel_hidden.has(report.b_id)):
			_temp_revealed[int(report.b_id)] = true


func _on_duel_confirm_pressed() -> void:
	_temp_revealed = {}
	if online:
		_clear_duel_state()
		ui_state = _post_duel_ui_state
		_refresh()
		return
	if _duel_for_receiver:
		_clear_duel_state()
		ui_state = Ui.MOVE
		_reset_timer()
		_refresh()
		return
	var result := _duel_pending_result
	_duel_report = []
	_duel_hidden = []
	_duel_pending_result = {}
	_continue_flow(result)


func _on_revive_pressed(revive_piece_id: int) -> void:
	if online:
		net.send_nj_revive(revive_piece_id)
		return
	var result: Dictionary = game_match.perform_revive(viewer_side, revive_piece_id)
	if not result.ok:
		return
	_continue_flow(result)


func _on_decline_reward_pressed() -> void:
	if online:
		net.send_nj_decline_reward()
		return
	if not game_match.decline_reward(viewer_side).ok:
		return
	_goto_pass(game_match.current_turn, Ui.MOVE)


func _on_reset_pressed() -> void:
	if online:
		net.send_nj_arrange_reset()
		selected_piece_id = -1
		_refresh()
		return
	_apply_default_arrangement(viewer_side)
	selected_piece_id = -1
	_refresh()


func _on_ready_pressed() -> void:
	if online:
		net.send_nj_ready()
		return
	if not game_match.mark_ready(viewer_side).ok:
		return
	if game_match.both_ready():
		game_match.start_move_phase(0)
		_goto_pass(0, Ui.MOVE)
	else:
		_goto_pass(1 - viewer_side, Ui.ARRANGE)


func _on_restart_pressed() -> void:
	if online:
		if net:
			net.send_nj_rematch()
		_status_label.text = "다음 판을 준비하는 중…"
		return
	_start_new_game()
	_refresh()


func _on_lobby_pressed() -> void:
	if online and net != null and is_instance_valid(net) and net != GameSession.net:
		net.disconnect_from_room()
	GameSession.reset_to_local()
	get_tree().change_scene_to_file("res://ui/genius_lobby.tscn")


# ── 온라인(랜덤매칭) ─────────────────────────────────────────────
# 서버가 상태의 유일한 권위자다. 클라이언트는 nj_state를 받아 game_match를
# "거울"처럼 다시 채워 넣기만 하고(판정 메서드는 부르지 않음), 사용자
# 입력은 net.send_nj_*로 서버에 의도만 전달한다. 상대 말은 서버가 이미
# 가려서 보내주므로(정체/좌표 없이 side만), 화면에 그릴 자리표시용으로
# 매번 새로 "유령 말"(음수 id)을 만들어 끼워 넣는다 — 실제 정체와는
# 무관하며, 대결 로그에서만 같은 방식으로 한 번 더 쓰인다(마스킹).
func _start_network() -> void:
	if GameSession.net != null and is_instance_valid(GameSession.net):
		net = GameSession.net
		net.message.connect(_on_net_message)
		net.disconnected.connect(_on_net_disconnected)
		_status_label.text = "동기화 중…"
		for pending in GameSession.take_pending_messages():
			_on_net_message(pending)
		return

	net = NetworkClientScript.new()
	add_child(net)
	net.message.connect(_on_net_message)
	net.disconnected.connect(_on_net_disconnected)
	net.connected.connect(func() -> void:
		_status_label.text = "연결됨 — 상대 대기 중…"
	)
	var url := GameSession.quick_ws_url() if GameSession.mode == GameSession.Mode.QUICK else GameSession.ws_url()
	net.connect_to_room(url)


func _on_net_message(data: Dictionary) -> void:
	var t := str(data.get("type", ""))
	match t:
		"queued":
			_status_label.text = "상대를 찾는 중…"
		"matched":
			_status_label.text = "매칭 완료! 입장 중…"
		"nj_joined":
			my_index = int(data.get("you", -1))
			viewer_side = my_index
			_status_label.text = "방 %s" % GameSession.room_id
		"nj_waiting":
			_status_label.text = "상대를 기다리는 중… (방 코드: %s)" % GameSession.room_id
		"nj_state":
			_apply_server_state(data)
		"nj_opponent_left":
			_status_label.text = "상대가 나갔습니다. 새 상대를 기다립니다…"
		"error":
			_status_label.text = "오류: %s" % str(data.get("message", ""))
		"pong":
			pass
		_:
			pass


func _on_net_disconnected() -> void:
	if not online:
		return
	_status_label.text = "서버 연결이 끊겼습니다."


func _phase_from_string(s: String) -> int:
	match s:
		"arrange":
			return MatchScript.Phase.ARRANGE
		"move":
			return MatchScript.Phase.MOVE
		"awaiting_items":
			return MatchScript.Phase.AWAITING_ITEMS
		"awaiting_reward":
			return MatchScript.Phase.AWAITING_REWARD
		"game_over":
			return MatchScript.Phase.GAME_OVER
	return MatchScript.Phase.ARRANGE


func _extract_int_or_neg1(data: Dictionary, key: String) -> int:
	var v = data.get(key, null)
	if v == null:
		return -1
	return int(v)


func _online_target_ui_state(pending_item_side: int, pending_reward_side: int) -> Ui:
	match game_match.phase:
		MatchScript.Phase.ARRANGE:
			return Ui.ARRANGE
		MatchScript.Phase.MOVE:
			return Ui.MOVE
		MatchScript.Phase.AWAITING_ITEMS:
			return Ui.ITEM if pending_item_side == my_index else Ui.WAIT_OPP
		MatchScript.Phase.AWAITING_REWARD:
			return Ui.REWARD if pending_reward_side == my_index else Ui.WAIT_OPP
		MatchScript.Phase.GAME_OVER:
			return Ui.OVER
	return Ui.MOVE


func _apply_server_state(data: Dictionary) -> void:
	my_index = int(data.get("you", my_index))
	viewer_side = my_index

	var seg: int = int(data.get("segment", 0))
	if seg != _online_segment_shown:
		_online_segment_shown = seg
		_last_seen_event_seq = 0
		_clear_duel_state()

	selected_piece_id = -1
	_legal_targets = []

	_sync_board_and_pieces(data)

	game_match.phase = _phase_from_string(str(data.get("phase", "arrange")))
	game_match.current_turn = int(data.get("current_turn", -1))
	game_match.winner = int(data.get("winner", -1))
	game_match.win_reason = str(data.get("win_reason", ""))
	game_match.ready_flags[my_index] = bool(data.get("my_ready", false))
	game_match.ready_flags[1 - my_index] = bool(data.get("opp_ready", false))
	var used_mine: Variant = data.get("used_items_mine", null)
	if typeof(used_mine) == TYPE_DICTIONARY:
		game_match.used_items[my_index] = used_mine

	var pending_item_side: int = int(data.get("pending_item_side", -1))
	var pending_reward_side: int = int(data.get("pending_reward_side", -1))
	if pending_reward_side == my_index:
		game_match.pending_reward = {
			"side": pending_reward_side,
			"piece_id": _extract_int_or_neg1(data, "pending_reward_piece_id"),
		}
	else:
		game_match.pending_reward = {}

	_server_arrange_left = _extract_int_or_neg1(data, "arrange_seconds_left")
	_server_move_left = _extract_int_or_neg1(data, "move_seconds_left")
	_server_seconds_at_ms = Time.get_ticks_msec()
	_shown_seconds = -1

	var next_ui := _online_target_ui_state(pending_item_side, pending_reward_side)
	_post_duel_ui_state = next_ui

	var event: Variant = data.get("event", null)
	if typeof(event) == TYPE_DICTIONARY and int(event.get("seq", 0)) > _last_seen_event_seq:
		_last_seen_event_seq = int(event.get("seq", 0))
		_show_online_duel_event(event)
	elif ui_state != Ui.DUEL:
		ui_state = next_ui

	_refresh()


## 서버 board/graveyard 스냅샷으로 game_match.pieces/board/graveyard를
## 다시 채운다. 상대의 가려진 말은 "유령 말"(음수 id, 정체 불명)로 채워
## 넣어 기존 렌더링 코드(_add_piece 등)를 그대로 재사용한다.
func _sync_board_and_pieces(data: Dictionary) -> void:
	var new_pieces: Dictionary = {}
	var new_board: Array = []
	var board_data: Array = data.get("board", [])

	for row in Rules.BOARD_ROWS:
		var row_cells: Array = []
		var src_row: Array = board_data[row] if row < board_data.size() else []
		for col in Rules.BOARD_COLS:
			var cell: Variant = src_row[col] if col < src_row.size() else null
			if cell == null:
				row_cells.append(-1)
				continue
			var cd: Dictionary = cell
			var pid: int
			if cd.has("id"):
				pid = int(cd.id)
				new_pieces[pid] = _piece_dict_from_server(cd, col, row)
			else:
				pid = _ghost_board_id(row, col)
				new_pieces[pid] = _ghost_piece_dict(pid, cd, col, row)
			row_cells.append(pid)
		new_board.append(row_cells)

	for s in [0, 1]:
		var arr: Array = data.get("graveyard_mine", []) if s == my_index else data.get("graveyard_opp", [])
		var ids: Array = []
		for i in arr.size():
			var entry: Dictionary = arr[i]
			var pid: int
			var pdict: Dictionary
			if entry.has("id"):
				pid = int(entry.id)
				pdict = _piece_dict_from_server(entry, -1, -1)
			else:
				pid = _ghost_grave_id(s, i)
				pdict = _ghost_piece_dict(pid, entry, -1, -1)
			pdict.alive = false
			new_pieces[pid] = pdict
			ids.append(pid)
		game_match.graveyard[s] = ids

	game_match.pieces = new_pieces
	game_match.board = new_board

	for id in new_pieces.keys():
		if id >= 0:
			_ensure_face_tex(id)
	_apply_event_pieces()


func _piece_dict_from_server(cell: Dictionary, col: int, row: int) -> Dictionary:
	return {
		"id": int(cell.id),
		"side": int(cell.side),
		"type": int(cell.type),
		"value": int(cell.value),
		"alive": true,
		"col": col,
		"row": row,
		"revealed": bool(cell.get("revealed", false)),
	}


## 정체를 모르는 상대 말 자리표시자. side만 알 뿐, 실제 종류/숫자는
## 담지 않는다(뒷면 텍스처로만 그려짐 — _is_face_up이 항상 false 리턴).
func _ghost_piece_dict(pid: int, cell: Dictionary, col: int, row: int) -> Dictionary:
	return {
		"id": pid,
		"side": int(cell.get("side", 0)),
		"type": Rules.PieceType.NUMBER,
		"value": 0,
		"alive": true,
		"col": col,
		"row": row,
		"revealed": false,
	}


func _ghost_board_id(row: int, col: int) -> int:
	return -(1 + row * Rules.BOARD_COLS + col)


func _ghost_grave_id(side: int, index: int) -> int:
	return -(1000 + side * 100 + index)


func _ghost_event_id(seq: int, index: int, slot: String) -> int:
	var slot_n: int = 0 if slot == "a" else 1
	return -(9000000 + seq * 100 + index * 2 + slot_n)


## 서버가 이미 뷰어별로 가려서 보내준 대결 로그(event)를, 기존 로컬
## _fill_duel_modal 계열 함수가 읽는 모양(_duel_report/_duel_hidden)으로
## 변환해서 그대로 재사용한다.
func _show_online_duel_event(event: Dictionary) -> void:
	var reports: Array = event.get("reports", [])
	var seq: int = int(event.get("seq", 0))
	_duel_report = []
	_duel_hidden = []
	_duel_masked = true
	_duel_for_receiver = false
	_duel_pending_result = {}
	_event_pieces = {}

	for i in reports.size():
		var r: Dictionary = reports[i]
		var a: Dictionary = r.get("a", {})
		var b: Dictionary = r.get("b", {})
		var a_id := _resolve_event_piece_id(a, seq, i, "a")
		var b_id := _resolve_event_piece_id(b, seq, i, "b")
		var score: Variant = r.get("score", null)
		_duel_report.append({
			"a_id": a_id,
			"b_id": b_id,
			"a_value": int(a.get("value", 0)),
			"b_value": int(b.get("value", 0)),
			"kind": str(r.get("kind", "number")),
			"score": int(score) if score != null else 0,
			"is_minus": bool(r.get("is_minus", false)),
			"a_removed": bool(a.get("removed", false)),
			"b_removed": bool(b.get("removed", false)),
		})

	_set_temp_revealed()
	ui_state = Ui.DUEL


## 대결은 두 말의 앞면을 공개하지만, 살아남은 상대 말은 보드 스냅샷에서는
## 다시 뒤집힌 채로(정체 없이) 내려온다 — 로컬 규칙과 같다(기억이 게임의
## 일부). 그래서 대결 로그가 알려준 실제 id가 game_match.pieces에 아예 없을
## 수 있어, 로그에 담긴 정보로 팝업 표시용 항목을 따로 만들어 둔다.
func _resolve_event_piece_id(entry: Dictionary, seq: int, index: int, slot: String) -> int:
	var masked := not entry.has("id")
	var piece_id: int = _ghost_event_id(seq, index, slot) if masked else int(entry.id)
	if masked:
		_duel_hidden.append(piece_id)

	# alive는 일부러 false로 둔다. 보드 위 말은 이미 보드 스냅샷이 따로
	# 들고 있어서, 여기에 살아있는 말을 또 넣으면 "상대 말 N개"가 부풀려진다.
	_event_pieces[piece_id] = {
		"id": piece_id,
		"side": int(entry.get("side", 0)),
		"type": int(entry.get("type", Rules.PieceType.NUMBER)),
		"value": int(entry.get("base_value", 0)),
		"alive": false,
		"col": -1,
		"row": -1,
		"revealed": false,
	}
	_apply_event_pieces()
	return piece_id


## 보드 스냅샷에 없는 대결 참가 말만 채워 넣는다. nj_state가 새로 올 때마다
## pieces가 통째로 교체되므로(팝업이 열린 채로도 온다), 매번 다시 부어준다.
func _apply_event_pieces() -> void:
	for id in _event_pieces.keys():
		if game_match.pieces.has(id):
			continue
		game_match.pieces[id] = _event_pieces[id]
		if id >= 0:
			_ensure_face_tex(id)
