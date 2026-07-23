# board.gd
# 로컬: 클릭 → C++ place_stone (기존 Phase 1)
# 온라인: 클릭 → 서버 place 요청 → move/game_start 메시지에 맞춰 로컬 보드 동기화

extends Node2D

const BOARD_SIZE := 15
const BOARD_PIXEL := 600.0
const NetworkClientScript := preload("res://scripts/network_client.gd")

var logic: GomokuBoardExt
var cell_size: float = 0.0
var board_origin: Vector2 = Vector2.ZERO

var result_layer: CanvasLayer
var result_panel: Panel
var result_label: Label
var restart_button: Button

var status_label: Label
var back_button: Button
var room_label: Label

var net: Node = null  # network_client.gd
var online: bool = false
var my_color: int = -1
var input_locked: bool = false
var turn_deadline_msec: int = -1

var vs_ai: bool = false
var ai_color: int = -1
var human_color: int = -1
const AI_THINK_SECONDS := 0.35


func _ready() -> void:
	logic = GomokuBoardExt.new()
	cell_size = BOARD_PIXEL / float(BOARD_SIZE - 1)

	var viewport_size := get_viewport_rect().size
	board_origin = Vector2(
		(viewport_size.x - BOARD_PIXEL) * 0.5,
		(viewport_size.y - BOARD_PIXEL) * 0.5
	)

	_create_hud()
	_create_result_popup()

	online = GameSession.mode == GameSession.Mode.ONLINE or GameSession.mode == GameSession.Mode.QUICK
	vs_ai = GameSession.mode == GameSession.Mode.AI

	if online:
		if GameSession.mode == GameSession.Mode.QUICK and GameSession.room_id != "":
			room_label.text = "방: %s" % GameSession.room_id
		elif GameSession.mode == GameSession.Mode.QUICK:
			room_label.text = "빠른 대전 매칭 중…"
		else:
			room_label.text = "방: %s" % GameSession.room_id
		status_label.text = "서버 연결 중…"
		input_locked = true
		restart_button.text = "재경기 요청"
		_start_network()
	elif vs_ai:
		if GameSession.prefer_first:
			human_color = GomokuBoardExt.STONE_BLACK
			ai_color = GomokuBoardExt.STONE_WHITE
		else:
			human_color = GomokuBoardExt.STONE_WHITE
			ai_color = GomokuBoardExt.STONE_BLACK
		room_label.text = "AI 대전 · 당신은 %s" % _color_label(human_color)
		status_label.text = _turn_text()
		restart_button.text = "다시 시작"
		if logic.get_current_turn() == ai_color:
			_take_ai_turn()
	else:
		room_label.text = "로컬 대전"
		status_label.text = "흑 차례"
		restart_button.text = "다시 시작"

	queue_redraw()


func _process(_delta: float) -> void:
	if not online or turn_deadline_msec < 0:
		return
	if logic.get_state() != GomokuBoardExt.STATE_PLAYING:
		return
	var left := maxi(0, int(ceil((turn_deadline_msec - Time.get_ticks_msec()) / 1000.0)))
	var turn_txt := _turn_text()
	status_label.text = "%s · 남은 시간 %d초" % [turn_txt, left]


func _start_network() -> void:
	if GameSession.net != null and is_instance_valid(GameSession.net):
		net = GameSession.net
		net.message.connect(_on_net_message)
		net.disconnected.connect(_on_net_disconnected)
		if GameSession.room_id != "":
			room_label.text = "방: %s" % GameSession.room_id
		status_label.text = "동기화 중…"
		for pending in GameSession.take_pending_messages():
			_on_net_message(pending)
		return

	net = NetworkClientScript.new()
	add_child(net)
	net.message.connect(_on_net_message)
	net.disconnected.connect(_on_net_disconnected)
	net.connected.connect(func() -> void:
		status_label.text = "연결됨 — 상대 대기 중…"
	)
	var url := GameSession.quick_ws_url() if GameSession.mode == GameSession.Mode.QUICK else GameSession.ws_url()
	net.connect_to_room(url)


func _create_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var top := HBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 16
	top.offset_right = -16
	top.offset_top = 12
	top.offset_bottom = 48
	top.add_theme_constant_override("separation", 12)
	layer.add_child(top)

	back_button = Button.new()
	back_button.text = "← 로비"
	back_button.pressed.connect(_on_back_pressed)
	top.add_child(back_button)

	room_label = Label.new()
	room_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	room_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(room_label)

	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_label.custom_minimum_size = Vector2(280, 0)
	top.add_child(status_label)


func _create_result_popup() -> void:
	result_layer = CanvasLayer.new()
	add_child(result_layer)

	result_panel = Panel.new()
	result_panel.custom_minimum_size = Vector2(280, 160)
	result_layer.add_child(result_panel)
	result_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	result_panel.add_child(vbox)

	result_label = Label.new()
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.add_theme_font_size_override("font_size", 28)
	vbox.add_child(result_label)

	restart_button = Button.new()
	restart_button.text = "다시 시작"
	restart_button.pressed.connect(_on_restart_pressed)
	vbox.add_child(restart_button)

	result_layer.hide()


func _show_result_popup(state: int) -> void:
	match state:
		GomokuBoardExt.STATE_BLACK_WIN:
			result_label.text = "BLACK WINS!"
		GomokuBoardExt.STATE_WHITE_WIN:
			result_label.text = "WHITE WINS!"
		GomokuBoardExt.STATE_DRAW:
			result_label.text = "DRAW!"
		_:
			return
	result_layer.show()


func _on_restart_pressed() -> void:
	if online:
		if net:
			net.send_restart()
		return
	logic.reset()
	result_layer.hide()
	input_locked = false
	status_label.text = _turn_text() if vs_ai else "흑 차례"
	queue_redraw()
	if vs_ai and logic.get_current_turn() == ai_color:
		_take_ai_turn()


func _on_back_pressed() -> void:
	if net != null and is_instance_valid(net) and net != GameSession.net:
		net.disconnect_from_room()
	GameSession.reset_to_local()
	get_tree().change_scene_to_file("res://ui/genius_lobby.tscn")


func _draw() -> void:
	var bg := Rect2(board_origin, Vector2(BOARD_PIXEL, BOARD_PIXEL))
	draw_rect(bg, Color(0.86, 0.70, 0.45))

	var line_color := Color(0.15, 0.10, 0.05)
	for i in BOARD_SIZE:
		var offset := i * cell_size
		draw_line(
			board_origin + Vector2(offset, 0),
			board_origin + Vector2(offset, BOARD_PIXEL),
			line_color, 1.5
		)
		draw_line(
			board_origin + Vector2(0, offset),
			board_origin + Vector2(BOARD_PIXEL, offset),
			line_color, 1.5
		)

	var stone_radius := cell_size * 0.42
	for y in BOARD_SIZE:
		for x in BOARD_SIZE:
			var stone: int = logic.get_stone(x, y)
			if stone == GomokuBoardExt.STONE_NONE:
				continue
			var center := _grid_to_pixel(x, y)
			var color := Color.BLACK if stone == GomokuBoardExt.STONE_BLACK else Color.WHITE
			draw_circle(center, stone_radius, color)
			if stone == GomokuBoardExt.STONE_WHITE:
				draw_arc(center, stone_radius, 0, TAU, 32, Color.BLACK, 1.5)


func _input(event: InputEvent) -> void:
	if input_locked:
		return
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if logic.get_state() != GomokuBoardExt.STATE_PLAYING:
		return

	var grid := _pixel_to_grid(event.position)
	if grid.x < 0:
		return

	var x := int(grid.x)
	var y := int(grid.y)

	if online:
		if my_color < 0:
			return
		if logic.get_current_turn() != my_color:
			status_label.text = "상대 차례입니다"
			return
		net.send_place(x, y)
		return

	if vs_ai and logic.get_current_turn() != human_color:
		return  # AI 차례엔 클릭 무시 (input_locked로도 막히지만 이중 안전장치)

	var just_placed := logic.get_current_turn()
	var result: int = logic.place_stone(x, y)
	match result:
		GomokuBoardExt.MOVE_CELL_OCCUPIED:
			return
		GomokuBoardExt.MOVE_GAME_ALREADY_OVER:
			return
		GomokuBoardExt.MOVE_OUT_OF_BOUNDS:
			return

	print("place ", ("BLACK" if just_placed == GomokuBoardExt.STONE_BLACK else "WHITE"), " at (", x, ", ", y, ")")
	_show_result_popup(logic.get_state())
	status_label.text = _turn_text() if logic.get_state() == GomokuBoardExt.STATE_PLAYING else status_label.text
	queue_redraw()

	if vs_ai and logic.get_state() == GomokuBoardExt.STATE_PLAYING and logic.get_current_turn() == ai_color:
		_take_ai_turn()


func _take_ai_turn() -> void:
	input_locked = true
	status_label.text = "AI 생각 중…"
	await get_tree().create_timer(AI_THINK_SECONDS).timeout

	# 대기 중 재시작 등으로 게임이 바뀌었을 수 있으니 다시 확인
	if logic.get_state() != GomokuBoardExt.STATE_PLAYING or logic.get_current_turn() != ai_color:
		input_locked = false
		return

	var move: Vector2i = logic.suggest_move()
	if move.x >= 0 and move.y >= 0:
		logic.place_stone(move.x, move.y)
		print("AI place at (", move.x, ", ", move.y, ")")

	_show_result_popup(logic.get_state())
	queue_redraw()
	input_locked = false
	if logic.get_state() == GomokuBoardExt.STATE_PLAYING:
		status_label.text = _turn_text()


func _on_net_message(data: Dictionary) -> void:
	var t: String = str(data.get("type", ""))
	match t:
		"queued":
			status_label.text = "상대를 찾는 중…"
			input_locked = true
		"matched":
			GameSession.room_id = str(data.get("room_id", ""))
			room_label.text = "방: %s" % GameSession.room_id
			status_label.text = "매칭 완료! 입장 중…"
		"joined":
			my_color = _color_from_name(str(data.get("color", "")))
			GameSession.my_color = my_color
			_apply_board_snapshot(data.get("board", []))
			status_label.text = "당신은 %s · 상대 대기 중…" % _color_label(my_color)
			input_locked = true
		"waiting":
			status_label.text = "상대 입장 대기 중… (방 코드: %s)" % GameSession.room_id
			input_locked = true
		"game_start":
			if data.has("your_color"):
				my_color = _color_from_name(str(data["your_color"]))
				GameSession.my_color = my_color
			logic.reset()
			_apply_board_snapshot(data.get("board", []))
			result_layer.hide()
			input_locked = false
			_set_turn_timer(data.get("turn_seconds", 30))
			status_label.text = "게임 시작! 당신은 %s" % _color_label(my_color)
			queue_redraw()
		"move":
			_apply_server_move(data)
		"timeout":
			_apply_board_snapshot(data.get("board", []))
			_sync_state_name(str(data.get("state", "")))
			turn_deadline_msec = -1
			input_locked = true
			status_label.text = "시간 초과 — %s" % str(data.get("loser", ""))
			_show_result_popup(logic.get_state())
			queue_redraw()
		"opponent_left":
			input_locked = true
			turn_deadline_msec = -1
			status_label.text = "상대가 나갔습니다. 새 상대를 기다리거나 로비로 돌아가세요."
		"error":
			status_label.text = "오류: %s" % str(data.get("message", ""))
		"pong":
			pass
		_:
			print("WS unhandled: ", data)


func _on_net_disconnected() -> void:
	input_locked = true
	turn_deadline_msec = -1
	status_label.text = "서버 연결이 끊겼습니다."


func _apply_server_move(data: Dictionary) -> void:
	var x := int(data.get("x", -1))
	var y := int(data.get("y", -1))
	var result: int = logic.place_stone(x, y)
	if result != GomokuBoardExt.MOVE_OK:
		# 로컬이 어긋났으면 스냅샷으로 강제 동기화
		logic.reset()
		_apply_board_snapshot(data.get("board", []))
		_sync_state_name(str(data.get("state", "")))
	_show_result_popup(logic.get_state())
	if logic.get_state() == GomokuBoardExt.STATE_PLAYING:
		_set_turn_timer(data.get("turn_seconds", 30))
		input_locked = false
	else:
		turn_deadline_msec = -1
		input_locked = true
	status_label.text = _turn_text()
	queue_redraw()


func _apply_board_snapshot(board_variant: Variant) -> void:
	# C++ 쪽에 set_stone API가 없어, 빈 보드(game_start)만 reset으로 맞춘다.
	# 일반 진행은 move의 place_stone 순서로 동기화한다.
	if typeof(board_variant) != TYPE_ARRAY:
		return
	var empty := true
	for row in board_variant:
		if typeof(row) != TYPE_ARRAY:
			continue
		for cell in row:
			if int(cell) != 0:
				empty = false
				break
		if not empty:
			break
	if empty:
		logic.reset()


func _sync_state_name(state_name: String) -> void:
	# place_stone으로 이미 state가 맞춰진 경우가 대부분.
	# timeout 등에서 보드 스냅샷만 오고 로컬 state가 PLAYING이면 팝업용으로 강제 표시.
	match state_name:
		"black_win":
			if logic.get_state() == GomokuBoardExt.STATE_PLAYING:
				# C++에 set_state가 없으므로 팝업만 직접
				result_label.text = "BLACK WINS!"
				result_layer.show()
		"white_win":
			if logic.get_state() == GomokuBoardExt.STATE_PLAYING:
				result_label.text = "WHITE WINS!"
				result_layer.show()
		"draw":
			if logic.get_state() == GomokuBoardExt.STATE_PLAYING:
				result_label.text = "DRAW!"
				result_layer.show()


func _set_turn_timer(seconds: Variant) -> void:
	if seconds == null:
		turn_deadline_msec = -1
		return
	turn_deadline_msec = Time.get_ticks_msec() + int(seconds) * 1000


func _turn_text() -> String:
	if logic.get_state() != GomokuBoardExt.STATE_PLAYING:
		return status_label.text
	var turn := logic.get_current_turn()
	var name := _color_label(turn)
	if online and my_color >= 0:
		if turn == my_color:
			return "당신(%s) 차례" % name
		return "상대(%s) 차례" % name
	if vs_ai:
		if turn == human_color:
			return "당신(%s) 차례" % name
		return "AI(%s) 차례" % name
	return "%s 차례" % name


func _color_from_name(name: String) -> int:
	match name:
		"black":
			return GomokuBoardExt.STONE_BLACK
		"white":
			return GomokuBoardExt.STONE_WHITE
		_:
			return -1


func _color_label(color: int) -> String:
	match color:
		GomokuBoardExt.STONE_BLACK:
			return "흑"
		GomokuBoardExt.STONE_WHITE:
			return "백"
		_:
			return "?"


func _grid_to_pixel(x: int, y: int) -> Vector2:
	return board_origin + Vector2(x * cell_size, y * cell_size)


func _pixel_to_grid(pos: Vector2) -> Vector2i:
	var local := pos - board_origin
	var x := int(round(local.x / cell_size))
	var y := int(round(local.y / cell_size))
	var nearest := _grid_to_pixel(x, y)
	if pos.distance_to(nearest) > cell_size * 0.45:
		return Vector2i(-1, -1)
	if x < 0 or x >= BOARD_SIZE or y < 0 or y >= BOARD_SIZE:
		return Vector2i(-1, -1)
	return Vector2i(x, y)
