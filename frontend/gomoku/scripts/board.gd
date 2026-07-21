# board.gd
# 순서 요약:
# 1) _ready: GomokuBoardExt(C++ 로직) 생성, 셀 크기 계산, 보드 중앙 배치, 승리 팝업 UI 생성(숨김)
# 2) _draw: 15x15 격자 + 놓인 돌 그리기 (돌 상태는 logic.get_stone()에서 읽어옴)
# 3) _input: 마우스 클릭 → 픽셀을 (x,y)로 변환 → logic.place_stone() 호출 → 결과로 승패/반칙 판단
#    → 게임이 끝나면 팝업 표시
# 4) _on_restart_pressed: 팝업의 "다시 시작" 버튼 → logic.reset() 후 팝업 숨기고 다시 그림
# ※ 실제 오목 규칙(승패 판정 등)은 전부 C++(GomokuBoard)에 있고, 여긴 화면/입력만 담당함.

extends Node2D

const BOARD_SIZE := 15
const BOARD_PIXEL := 600.0  # 보드 한 변 픽셀 크기

var logic: GomokuBoardExt  # C++ GDExtension 인스턴스 (실제 보드 상태 + 판정 로직)
var cell_size: float = 0.0
var board_origin: Vector2 = Vector2.ZERO  # 보드 왼쪽 위 모서리 (화면 좌표)

# 승리 팝업용 UI 노드들 (코드로 생성, board.tscn을 직접 안 건드려도 되게)
var result_layer: CanvasLayer
var result_panel: Panel
var result_label: Label

func _ready() -> void:
	# 1) C++ 오목 로직 인스턴스 생성 (여기서부터가 GDExtension 연결 지점)
	logic = GomokuBoardExt.new()

	# 2) 셀 크기 = 보드픽셀 / (칸 수 - 1)  ← 오목은 "교차점"에 돌을 둠
	cell_size = BOARD_PIXEL / float(BOARD_SIZE - 1)

	# 3) 화면 중앙에 보드가 오도록 origin 계산
	var viewport_size := get_viewport_rect().size
	board_origin = Vector2(
		(viewport_size.x - BOARD_PIXEL) * 0.5,
		(viewport_size.y - BOARD_PIXEL) * 0.5
	)

	# 4) 승리/무승부 팝업 UI를 미리 만들어두고 숨겨둠 (게임 끝날 때만 보여줄 것)
	_create_result_popup()

	queue_redraw()


# CanvasLayer(화면 고정 레이어) 위에 패널+텍스트+재시작 버튼을 코드로 생성.
# 카메라/보드 좌표와 상관없이 항상 화면 정중앙에 뜨게 하려고 CanvasLayer를 씀.
func _create_result_popup() -> void:
	result_layer = CanvasLayer.new()
	add_child(result_layer)

	result_panel = Panel.new()
	result_panel.custom_minimum_size = Vector2(280, 160)
	result_layer.add_child(result_panel)
	# 자식(라벨/버튼) 추가 후에 anchors_and_offsets_preset을 호출해야
	# custom_minimum_size 기준으로 정확히 중앙 정렬됨
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

	var restart_button := Button.new()
	restart_button.text = "다시 시작"
	restart_button.pressed.connect(_on_restart_pressed)
	vbox.add_child(restart_button)

	result_layer.hide()


# 게임 상태(state)에 맞는 문구로 팝업을 보여줌
func _show_result_popup(state: int) -> void:
	match state:
		GomokuBoardExt.STATE_BLACK_WIN:
			result_label.text = "BLACK WINS!"
		GomokuBoardExt.STATE_WHITE_WIN:
			result_label.text = "WHITE WINS!"
		GomokuBoardExt.STATE_DRAW:
			result_label.text = "DRAW!"
		_:
			return  # PLAYING이면 보여줄 게 없음

	result_layer.show()


func _on_restart_pressed() -> void:
	logic.reset()
	result_layer.hide()
	queue_redraw()


func _draw() -> void:
	# --- 보드 배경 ---
	var bg := Rect2(board_origin, Vector2(BOARD_PIXEL, BOARD_PIXEL))
	draw_rect(bg, Color(0.86, 0.70, 0.45))  # 나무색

	# --- 격자선 (가로/세로 각 15줄) ---
	var line_color := Color(0.15, 0.10, 0.05)
	for i in BOARD_SIZE:
		var offset := i * cell_size
		# 세로선
		draw_line(
			board_origin + Vector2(offset, 0),
			board_origin + Vector2(offset, BOARD_PIXEL),
			line_color, 1.5
		)
		# 가로선
		draw_line(
			board_origin + Vector2(0, offset),
			board_origin + Vector2(BOARD_PIXEL, offset),
			line_color, 1.5
		)

	# --- 돌 그리기 (C++ 쪽 상태를 그대로 읽어서 그림) ---
	var stone_radius := cell_size * 0.42
	for y in BOARD_SIZE:
		for x in BOARD_SIZE:
			var stone: int = logic.get_stone(x, y)
			if stone == GomokuBoardExt.STONE_NONE:
				continue
			var center := _grid_to_pixel(x, y)
			var color := Color.BLACK if stone == GomokuBoardExt.STONE_BLACK else Color.WHITE
			draw_circle(center, stone_radius, color)
			# 흰돌은 테두리 없으면 배경에 묻히니까 얇은 테두리
			if stone == GomokuBoardExt.STONE_WHITE:
				draw_arc(center, stone_radius, 0, TAU, 32, Color.BLACK, 1.5)


func _input(event: InputEvent) -> void:
	# 왼쪽 클릭만 처리
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return

	var grid := _pixel_to_grid(event.position)
	if grid.x < 0:
		return  # 보드 밖 클릭

	var x := int(grid.x)
	var y := int(grid.y)

	# place_stone() 호출 전에 "지금 누구 차례인지" 먼저 저장해둠.
	# (place_stone() 이후에 current_turn을 보고 유추하면 승리로 게임이 끝났을 때
	#  턴이 안 넘어가는 경우와 헷갈리게 되므로, 호출 전 값을 그대로 쓰는 게 안전함)
	var just_placed := logic.get_current_turn()

	var result: int = logic.place_stone(x, y)
	match result:
		GomokuBoardExt.MOVE_CELL_OCCUPIED:
			print("occupied: (", x, ", ", y, ")")
			return
		GomokuBoardExt.MOVE_GAME_ALREADY_OVER:
			print("game already over")
			return
		GomokuBoardExt.MOVE_OUT_OF_BOUNDS:
			return  # 이론상 grid 체크에서 이미 걸러지므로 여긴 오지 않음

	print("place ", ("BLACK" if just_placed == GomokuBoardExt.STONE_BLACK else "WHITE"), " at (", x, ", ", y, ")")

	# 승패/무승부면 팝업 표시 (PLAYING이면 _show_result_popup 안에서 그냥 무시됨)
	_show_result_popup(logic.get_state())

	queue_redraw()


# 교차점 좌표 (x,y) → 화면 픽셀
func _grid_to_pixel(x: int, y: int) -> Vector2:
	return board_origin + Vector2(x * cell_size, y * cell_size)


# 화면 픽셀 → 가장 가까운 교차점 (x,y). 보드 밖이면 (-1,-1)
func _pixel_to_grid(pos: Vector2) -> Vector2i:
	var local := pos - board_origin
	# 가장 가까운 교차점으로 반올림
	var x := int(round(local.x / cell_size))
	var y := int(round(local.y / cell_size))

	# 클릭이 교차점에서 너무 멀면 무시 (셀 절반보다 멀면)
	var nearest := _grid_to_pixel(x, y)
	if pos.distance_to(nearest) > cell_size * 0.45:
		return Vector2i(-1, -1)

	if x < 0 or x >= BOARD_SIZE or y < 0 or y >= BOARD_SIZE:
		return Vector2i(-1, -1)

	return Vector2i(x, y)
