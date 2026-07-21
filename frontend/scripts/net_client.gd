## Autoload: WebSocket client talking to FastAPI `/ws`.
## AI singleplayer must NOT call this — GameSession.mode == AI blocks connect.
extends Node

signal connected
signal disconnected
signal message_received(msg: Dictionary)

var _peer: WebSocketPeer = WebSocketPeer.new()
var _url: String = "ws://127.0.0.1:8000/ws"
var _active: bool = false


func set_server_url(url: String) -> void:
	_url = url


func connect_server() -> Error:
	if GameSession.mode == GameSession.Mode.AI:
		push_warning("NetClient: AI mode — server connection blocked")
		return ERR_UNAUTHORIZED
	if GameSession.access_token.is_empty():
		push_warning("NetClient: missing access_token")
		return ERR_UNAUTHORIZED
	var err := _peer.connect_to_url(_url)
	if err != OK:
		return err
	_active = true
	set_process(true)
	return OK


func disconnect_server() -> void:
	_active = false
	_peer.close()
	set_process(false)
	disconnected.emit()


func send_msg(type: String, payload: Dictionary = {}, request_id: String = "") -> void:
	var envelope := {"type": type, "payload": payload}
	if not request_id.is_empty():
		envelope["request_id"] = request_id
	_peer.send_text(JSON.stringify(envelope))


func authenticate() -> void:
	send_msg("auth.hello", {"token": GameSession.access_token})


func _process(_delta: float) -> void:
	if not _active:
		return
	_peer.poll()
	var state := _peer.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		while _peer.get_available_packet_count() > 0:
			var raw := _peer.get_packet().get_string_from_utf8()
			var parsed: Variant = JSON.parse_string(raw)
			if typeof(parsed) == TYPE_DICTIONARY:
				var msg: Dictionary = parsed
				if msg.get("type", "") == "auth.ok" and not connected.get_connections().is_empty():
					pass
				message_received.emit(msg)
	elif state == WebSocketPeer.STATE_CLOSED:
		_active = false
		set_process(false)
		disconnected.emit()
