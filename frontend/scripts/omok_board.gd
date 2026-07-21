extends Control
## Omok board scene — UI shell. Stone logic goes through C++ GDExtension in Phase 1.

const BOARD_SIZE := 15

@onready var board_grid: GridContainer = %BoardGrid
@onready var info_label: Label = %InfoLabel
@onready var back_button: Button = %BackButton

## Placeholder 2D board until GDExtension `OmokEngine` is linked.
var _cells: Array[int] = []
var _turn: int = 1  # 1 black, 2 white


func _ready() -> void:
	_cells.resize(BOARD_SIZE * BOARD_SIZE)
	_cells.fill(0)
	_build_grid()
	_update_info()
	if GameSession.mode == GameSession.Mode.AI:
		info_label.text = "AI 모드 — NetClient 차단됨. Phase 1에서 GDExtension AI 호출."
	elif GameSession.mode in [GameSession.Mode.PRIVATE, GameSession.Mode.RANK]:
		info_label.text = "온라인 모드 — Phase 2/3에서 WebSocket 착수 동기화."


func _build_grid() -> void:
	for child in board_grid.get_children():
		child.queue_free()
	board_grid.columns = BOARD_SIZE
	for y in BOARD_SIZE:
		for x in BOARD_SIZE:
			var btn := Button.new()
			btn.custom_minimum_size = Vector2(36, 36)
			btn.focus_mode = Control.FOCUS_NONE
			btn.pressed.connect(_on_cell_pressed.bind(x, y, btn))
			board_grid.add_child(btn)


func _on_cell_pressed(x: int, y: int, btn: Button) -> void:
	var idx := y * BOARD_SIZE + x
	if _cells[idx] != 0:
		return
	_cells[idx] = _turn
	btn.text = "●" if _turn == 1 else "○"
	# Phase 1: OmokEngine.place_stone(x, y) / check win / ai_move()
	if GameSession.mode == GameSession.Mode.AI and _turn == 1:
		_turn = 2
		_ai_stub_move()
	else:
		_turn = 3 - _turn
	_update_info()


func _ai_stub_move() -> void:
	# Temporary GDScript AI until C++ module is bound.
	for y in BOARD_SIZE:
		for x in BOARD_SIZE:
			var idx := y * BOARD_SIZE + x
			if _cells[idx] == 0:
				_cells[idx] = 2
				var btn: Button = board_grid.get_child(idx) as Button
				if btn:
					btn.text = "○"
				_turn = 1
				return


func _update_info() -> void:
	var side := "흑" if _turn == 1 else "백"
	info_label.text = "차례: %s | mode=%s | room=%s" % [side, GameSession.mode, GameSession.room_id]


func _on_back_pressed() -> void:
	GameSession.reset_match()
	NetClient.disconnect_server()
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")
