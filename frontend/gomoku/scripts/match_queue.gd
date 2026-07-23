# match_queue.gd — 랜덤매치 대기 / 매칭 카운트다운
extends Control

const NetworkClientScript := preload("res://scripts/network_client.gd")
const COUNTDOWN_FROM := 5

@onready var status_label: Label = $RootMargin/Center/VBox/StatusLabel
@onready var detail_label: Label = $RootMargin/Center/VBox/DetailLabel
@onready var cancel_button: Button = $RootMargin/Center/VBox/CancelButton

var _net: Node
var _matched := false
var _countdown_done := false
var _ready_for_board := false
var _entering := false


func _ready() -> void:
	status_label.text = "상대를 찾는 중…"
	var pref := GameSession.game_id.strip_edges()
	if pref.is_empty():
		detail_label.text = "완전 랜덤 대기"
	else:
		detail_label.text = "%s 대기" % GameCatalog.display_name(pref)

	_net = NetworkClientScript.new()
	add_child(_net)
	_net.message.connect(_on_net_message)
	_net.disconnected.connect(_on_net_disconnected)
	_net.connected.connect(func() -> void:
		if not _matched:
			status_label.text = "상대를 찾는 중…"
	)
	_net.connect_to_room(GameSession.quick_ws_url())


func _on_net_message(data: Dictionary) -> void:
	var t := str(data.get("type", ""))
	match t:
		"queued":
			status_label.text = "상대를 찾는 중…"
		"matched":
			_matched = true
			GameSession.room_id = str(data.get("room_id", ""))
			var gid := str(data.get("game_id", ""))
			if not gid.is_empty():
				GameSession.game_id = gid
			detail_label.text = "방 %s · %s" % [
				GameSession.room_id,
				GameCatalog.display_name(GameSession.game_id),
			]
			GameSession.pending_net_messages.append(data)
			_run_countdown()
		"joined", "waiting", "game_start", "move", "timeout", "opponent_left", "error":
			GameSession.pending_net_messages.append(data)
			if t == "game_start":
				_ready_for_board = true
				_try_enter_board()
			elif t == "error":
				status_label.text = "오류: %s" % str(data.get("message", ""))
		"bw_joined", "bw_waiting", "bw_wait_arrange", "bw_state", "bw_opponent_left":
			# 흑과백은 game_start가 없다 — 양쪽 모두 방에 들어오면 오는
			# bw_state가 오목의 game_start와 같은 "준비 완료" 신호다.
			GameSession.pending_net_messages.append(data)
			if t == "bw_state":
				_ready_for_board = true
				_try_enter_board()
		_:
			GameSession.pending_net_messages.append(data)


func _run_countdown() -> void:
	cancel_button.disabled = true
	for n in range(COUNTDOWN_FROM, 0, -1):
		status_label.text = "매칭되었습니다. %d" % n
		await get_tree().create_timer(1.0).timeout
		if not is_instance_valid(self):
			return
	status_label.text = "시작합니다"
	await get_tree().create_timer(0.35).timeout
	_countdown_done = true
	_try_enter_board()


func _try_enter_board() -> void:
	if _entering:
		return
	if not (_matched and _countdown_done and _ready_for_board):
		if _matched and _countdown_done and not _ready_for_board:
			status_label.text = "게임 준비 중…"
		return
	_entering = true
	var game := GameCatalog.by_id(GameSession.game_id)
	var scene_path := str(game.get("scene_path", "res://board.tscn"))
	GameSession.adopt_net(_net)
	_net = null
	get_tree().change_scene_to_file(scene_path)


func _on_net_disconnected() -> void:
	if _entering:
		return
	status_label.text = "연결이 끊어졌습니다."
	cancel_button.disabled = false


func _on_cancel_pressed() -> void:
	if _matched:
		return
	if _net:
		_net.disconnect_from_room()
	GameSession.clear_net()
	GameSession.reset_to_local()
	get_tree().change_scene_to_file("res://ui/genius_lobby.tscn")
