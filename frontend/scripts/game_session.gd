## Autoload: session state shared across lobby / play scenes.
extends Node

enum Mode { NONE, AI, PRIVATE, RANK }

var mode: Mode = Mode.NONE
var access_token: String = ""
var user_id: String = ""
var display_name: String = ""
var room_id: String = ""
var game_id: String = "omok"

## Parsed from browser URL `/play/{code}` when running as HTML5 export.
var url_room_code: String = ""


func reset_match() -> void:
	mode = Mode.NONE
	room_id = ""


func parse_browser_room_code() -> void:
	# Godot 4 web: JavaScriptBridge can read window.location.pathname.
	# Phase 1 wires this; Phase 0 keeps a placeholder.
	url_room_code = ""
	if OS.has_feature("web"):
		# TODO: JavaScriptBridge.eval("window.location.pathname")
		pass
