# network_client.gd
# Godot 4 WebSocketPeer로 서버와 JSON 메시지를 주고습니다.
# board.gd가 시그널을 받아 화면/로직을 갱신합니다.

extends Node

signal connected
signal disconnected
signal message(data: Dictionary)

var _peer: WebSocketPeer = WebSocketPeer.new()
var _url: String = ""
var _wanted: bool = false


func connect_to_room(url: String) -> void:
	disconnect_from_room()
	_url = url
	_wanted = true
	var err := _peer.connect_to_url(url)
	if err != OK:
		push_error("WebSocket connect failed: %s (%s)" % [url, err])
		_wanted = false


func disconnect_from_room() -> void:
	_wanted = false
	if _peer.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		_peer.close()
	_peer = WebSocketPeer.new()


func send_dict(data: Dictionary) -> void:
	if _peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
		push_warning("WS not open; drop send: %s" % data)
		return
	_peer.send_text(JSON.stringify(data))


func send_place(x: int, y: int) -> void:
	send_dict({"type": "place", "x": x, "y": y})


func send_restart() -> void:
	send_dict({"type": "restart"})


func send_bw_arrange(arrangement: Array) -> void:
	send_dict({"type": "bw_arrange", "arrangement": arrangement})


func send_bw_play(slot: int) -> void:
	send_dict({"type": "bw_play", "slot": slot})


func send_bw_rematch() -> void:
	send_dict({"type": "bw_rematch"})


func send_nj_arrange_move(piece_id: int, col: int, row: int) -> void:
	send_dict({"type": "nj_arrange_move", "piece_id": piece_id, "col": col, "row": row})


func send_nj_arrange_swap(piece_id_a: int, piece_id_b: int) -> void:
	send_dict({"type": "nj_arrange_swap", "piece_id_a": piece_id_a, "piece_id_b": piece_id_b})


func send_nj_arrange_reset() -> void:
	send_dict({"type": "nj_arrange_reset"})


func send_nj_ready() -> void:
	send_dict({"type": "nj_ready"})


func send_nj_move(piece_id: int, col: int, row: int) -> void:
	send_dict({"type": "nj_move", "piece_id": piece_id, "col": col, "row": row})


func send_nj_item(item_type: int) -> void:
	send_dict({"type": "nj_item", "item_type": item_type})


func send_nj_item_decline() -> void:
	send_dict({"type": "nj_item_decline"})


func send_nj_revive(piece_id: int) -> void:
	send_dict({"type": "nj_revive", "piece_id": piece_id})


func send_nj_decline_reward() -> void:
	send_dict({"type": "nj_decline_reward"})


func send_nj_rematch() -> void:
	send_dict({"type": "nj_rematch"})


var _was_open: bool = false


func _process(_delta: float) -> void:
	_peer.poll()
	var state := _peer.get_ready_state()
	var open := state == WebSocketPeer.STATE_OPEN

	if open and not _was_open:
		_was_open = true
		connected.emit()
	elif not open and _was_open:
		_was_open = false

	match state:
		WebSocketPeer.STATE_OPEN:
			while _peer.get_available_packet_count() > 0:
				var raw := _peer.get_packet().get_string_from_utf8()
				var parsed: Variant = JSON.parse_string(raw)
				if typeof(parsed) == TYPE_DICTIONARY:
					message.emit(parsed)
				else:
					push_warning("Invalid WS JSON: %s" % raw)
		WebSocketPeer.STATE_CLOSED:
			if _wanted:
				_wanted = false
				disconnected.emit()
		_:
			pass
