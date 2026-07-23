# game_session.gd — 로비 ↔ 보드 사이 세션 상태 (Autoload)
extends Node

enum Mode { LOCAL, ONLINE, QUICK, AI }

var mode: Mode = Mode.LOCAL
var game_id: String = ""
var room_id: String = ""
var my_color: int = -1  # GomokuBoardExt.STONE_* 와 동일 값, 온라인에서만 의미
## true = 선(흑), false = 후(백). AI 대전에서 사용.
var prefer_first: bool = true
var server_http: String = "http://127.0.0.1:8000"
var server_ws: String = "ws://127.0.0.1:8000"

## 랜덤매치 대기열에서 보드로 넘기는 살아 있는 WS 클라이언트
var net: Node = null
## 대기열에서 받은 game_start 등 (보드 진입 시 적용)
var pending_net_messages: Array[Dictionary] = []


func reset_to_local(p_game_id: String = "gomoku", p_prefer_first: bool = true) -> void:
	mode = Mode.LOCAL
	game_id = p_game_id
	prefer_first = p_prefer_first
	room_id = ""
	my_color = -1
	clear_net()


func start_online(p_room_id: String, p_game_id: String = "gomoku") -> void:
	mode = Mode.ONLINE
	game_id = p_game_id
	room_id = p_room_id
	my_color = -1
	clear_net()


func start_quick_match(p_game_id: String = "") -> void:
	mode = Mode.QUICK
	game_id = p_game_id
	room_id = ""
	my_color = -1
	pending_net_messages.clear()
	clear_net()


func start_ai_match(p_game_id: String = "gomoku", p_prefer_first: bool = true) -> void:
	mode = Mode.AI
	game_id = p_game_id
	prefer_first = p_prefer_first
	room_id = ""
	my_color = -1
	clear_net()


func ws_url() -> String:
	return "%s/ws/%s" % [server_ws, room_id]


func quick_ws_url() -> String:
	var g := game_id.strip_edges()
	if g.is_empty():
		return "%s/ws/quick?game=any" % server_ws
	return "%s/ws/quick?game=%s" % [server_ws, g.uri_encode()]


func apply_server_urls() -> void:
	# 데스크톱: 기본 127.0.0.1 유지. 웹: 같은 오리진.
	if not OS.has_feature("web"):
		return
	var origin := str(JavaScriptBridge.eval("window.location.origin", true)).strip_edges().trim_suffix("/")
	if origin.is_empty() or origin == "null":
		return
	server_http = origin
	if origin.begins_with("https://"):
		server_ws = "wss://" + origin.substr(8)
	elif origin.begins_with("http://"):
		server_ws = "ws://" + origin.substr(7)


func adopt_net(node: Node) -> void:
	if net != null and is_instance_valid(net) and net != node:
		if net.has_method("disconnect_from_room"):
			net.disconnect_from_room()
		net.queue_free()
	net = node
	if node.get_parent() != self:
		if node.get_parent() != null:
			node.get_parent().remove_child(node)
		add_child(node)


func clear_net() -> void:
	pending_net_messages.clear()
	if net != null and is_instance_valid(net):
		if net.has_method("disconnect_from_room"):
			net.disconnect_from_room()
		net.queue_free()
	net = null


func take_pending_messages() -> Array[Dictionary]:
	var out: Array[Dictionary] = pending_net_messages.duplicate()
	pending_net_messages.clear()
	return out
