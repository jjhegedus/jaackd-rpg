extends Node

# File-based automation bridge for scripted testing and debugging.
#
# Activated only when the GODOT_DEBUG_BRIDGE environment variable is set to "1"
# AND the build is a debug build.  Release builds are always inactive.
#
# Protocol:
#   debug/events.jsonl  — game appends one JSON line per event (seq, t, type, ...)
#   debug/commands.json — test runner writes a single command object; game reads, executes, clears
#
# Activate from the command line by setting the environment variable before launching:
#   GODOT_DEBUG_BRIDGE=1 godot --path /path/to/project
#
# Or via run_test.py which sets it automatically.

const EVENTS_FILE   := "events.jsonl"
const COMMANDS_FILE := "commands.json"

var _root: String = ""          # absolute path to debug/ dir (with trailing slash)
var _seq: int = 0
var _poll_timer: Timer
var _registered: Dictionary = {}  # id (String) → Node


func _ready() -> void:
	if not _is_active():
		return

	_root = ProjectSettings.globalize_path("res://").path_join("debug") + "/"
	DirAccess.make_dir_recursive_absolute(_root)

	# Clear events file at session start so old runs don't pollute results.
	var f := FileAccess.open(_root + EVENTS_FILE, FileAccess.WRITE)
	if f:
		f.close()

	_poll_timer = Timer.new()
	_poll_timer.wait_time = 0.2
	_poll_timer.autostart = true
	_poll_timer.timeout.connect(_poll_commands)
	add_child(_poll_timer)

	_append_event({"type": "bridge_ready"})


# ---------------------------------------------------------------------------
# Public API — call from each scene/panel when it becomes interactive.
# nodes is an Array of Dictionaries: [{"id": "PlayBtn", "node": play_btn}, ...]
# ---------------------------------------------------------------------------

func screen_ready(scene: String, panel: String, nodes: Array, extra: Dictionary = {}) -> void:
	if not _is_active():
		return

	_registered.clear()
	var actions: Array = []

	for entry in nodes:
		var node_id: String = entry.get("id", "")
		var node: Node = entry.get("node")
		if node_id == "" or node == null:
			continue
		_registered[node_id] = node

		var action: Dictionary = {"id": node_id, "type": "unknown", "enabled": true}
		if node is Button:
			action["type"] = "button"
			action["text"] = (node as Button).text
			action["enabled"] = not (node as Button).disabled
		elif node is LineEdit:
			action["type"] = "line_edit"
			action["text"] = (node as LineEdit).text
		elif node is SpinBox:
			action["type"] = "spinbox"
			action["value"] = (node as SpinBox).value
		elif node is OptionButton:
			action["type"] = "option_button"
			action["selected"] = (node as OptionButton).selected
		elif node is ItemList:
			action["type"] = "item_list"
			var items: Array = []
			var list := node as ItemList
			for i in list.item_count:
				items.append(list.get_item_text(i))
			action["items"] = items
		elif node is Label:
			action["type"] = "label"
			var lbl := node as Label
			action["text"]    = lbl.text
			action["visible"] = lbl.visible
			action["size"]    = {"x": lbl.size.x, "y": lbl.size.y}
			action["color"]   = lbl.get_theme_color("font_color").to_html()
		actions.append(action)

	var event := {"type": "screen_ready", "scene": scene, "panel": panel, "actions": actions}
	event.merge(extra)
	_append_event(event)


func log_progress(fraction: float, status: String) -> void:
	if not _is_active():
		return
	_append_event({"type": "progress", "fraction": fraction, "status": status})


func log_error(msg: String) -> void:
	if not _is_active():
		return
	_append_event({"type": "error", "msg": msg})


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

func _is_active() -> bool:
	return OS.is_debug_build() and OS.get_environment("GODOT_DEBUG_BRIDGE") == "1"


func _append_event(data: Dictionary) -> void:
	data["seq"] = _seq
	data["t"] = Time.get_unix_time_from_system()
	_seq += 1

	var path := _root + EVENTS_FILE
	# Ensure file exists before opening READ_WRITE.
	if not FileAccess.file_exists(path):
		var fw := FileAccess.open(path, FileAccess.WRITE)
		if fw:
			fw.close()

	var f := FileAccess.open(path, FileAccess.READ_WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line(JSON.stringify(data))
	f.close()


func _poll_commands() -> void:
	var path := _root + COMMANDS_FILE
	if not FileAccess.file_exists(path):
		return

	var content := FileAccess.get_file_as_string(path).strip_edges()
	if content == "":
		return

	# Clear immediately so we don't re-process on the next poll.
	var fc := FileAccess.open(path, FileAccess.WRITE)
	if fc:
		fc.close()

	var parsed = JSON.parse_string(content)
	if parsed == null or not parsed is Dictionary:
		_append_event({"type": "cmd_error", "msg": "Failed to parse command: " + content})
		return

	_execute_command(parsed as Dictionary)


func _execute_command(cmd: Dictionary) -> void:
	var cmd_id: int = cmd.get("id", -1)
	var cmd_type: String = cmd.get("cmd", "")

	match cmd_type:
		"click":
			var target: String = cmd.get("target", "")
			var node: Node = _registered.get(target)
			if node == null:
				_ack(cmd_id, false, "Node not found: " + target)
				return
			if not node is Button:
				_ack(cmd_id, false, target + " is not a Button")
				return
			(node as Button).pressed.emit()
			_ack(cmd_id, true)

		"set_text":
			var target: String = cmd.get("target", "")
			var value: String = cmd.get("value", "")
			var node: Node = _registered.get(target)
			if node == null:
				_ack(cmd_id, false, "Node not found: " + target)
				return
			if not node is LineEdit:
				_ack(cmd_id, false, target + " is not a LineEdit")
				return
			(node as LineEdit).text = value
			(node as LineEdit).text_changed.emit(value)
			(node as LineEdit).grab_focus()
			_ack(cmd_id, true)

		"set_value":
			var target: String = cmd.get("target", "")
			var value: float = cmd.get("value", 0.0)
			var node: Node = _registered.get(target)
			if node == null:
				_ack(cmd_id, false, "Node not found: " + target)
				return
			if not node is SpinBox:
				_ack(cmd_id, false, target + " is not a SpinBox")
				return
			(node as SpinBox).value = value
			_ack(cmd_id, true)

		"select_item":
			var target: String = cmd.get("target", "")
			var index: int = cmd.get("index", 0)
			var node: Node = _registered.get(target)
			if node == null:
				_ack(cmd_id, false, "Node not found: " + target)
				return
			if not node is ItemList:
				_ack(cmd_id, false, target + " is not an ItemList")
				return
			var list := node as ItemList
			list.select(index)
			list.item_selected.emit(index)
			_ack(cmd_id, true)

		"teleport":
			var x: float = cmd.get("x", 0.0)
			var y: float = cmd.get("y", 200.0)
			var z: float = cmd.get("z", 0.0)
			var players := get_tree().get_nodes_in_group("player")
			if players.is_empty():
				_ack(cmd_id, false, "No node in group 'player'")
				return
			(players[0] as Node3D).global_position = Vector3(x, y, z)
			_ack(cmd_id, true)

		"press_key":
			var keycode_str: String = cmd.get("keycode", "")
			var keycode: Key = OS.find_keycode_from_string(keycode_str)
			if keycode == KEY_NONE:
				_ack(cmd_id, false, "Unknown keycode: " + keycode_str)
				return
			var ev_down := InputEventKey.new()
			ev_down.keycode = keycode
			ev_down.physical_keycode = keycode
			ev_down.pressed = true
			Input.parse_input_event(ev_down)
			var ev_up := InputEventKey.new()
			ev_up.keycode = keycode
			ev_up.physical_keycode = keycode
			ev_up.pressed = false
			Input.parse_input_event(ev_up)
			_ack(cmd_id, true)

		"verify_groups":
			var manifest: WorldManifest = WorldManager._manifest
			if manifest == null:
				_append_event({"type": "groups_verified", "ok": false, "detail": "No manifest loaded"})
				_ack(cmd_id, true)
				return
			var groups := EntityRegistry.get_all_groups()
			var group_count := groups.size()
			var char_count: int = manifest.characters.size()
			var fail_detail := ""
			for c in manifest.characters:
				var ch := c as Character
				if EntityRegistry.get_group_for_entity(ch.character_id) == null:
					fail_detail = "Character %d (%s) has no group" % [ch.character_id, ch.display_name]
					break
			if fail_detail == "":
				for g in groups:
					var eg := g as EntityGroup
					if eg.member_ids.size() == 0:
						fail_detail = "Group %d has 0 members" % eg.group_id
						break
			if fail_detail != "":
				_append_event({"type": "groups_verified", "ok": false, "detail": fail_detail})
			else:
				_append_event({"type": "groups_verified", "ok": true,
					"group_count": group_count, "char_count": char_count,
					"detail": "%d groups for %d characters" % [group_count, char_count]})
			_ack(cmd_id, true)

		"verify_tactical_map":
			var maps := get_tree().get_nodes_in_group("tactical_map")
			if maps.is_empty():
				_append_event({"type": "tactical_map_verified", "ok": false,
					"detail": "No node in group 'tactical_map'"})
				_ack(cmd_id, true)
				return
			var tmv: TacticalMapView = maps[0]
			var chunk_count: int = tmv._chunk_textures.size()
			var contour_count: int = tmv._chunk_contours.size()
			var is_visible: bool = tmv.visible
			var ok := is_visible and chunk_count > 0
			var detail: String
			if not is_visible:
				detail = "TacticalMapView is not visible"
			elif chunk_count == 0:
				detail = "No chunks rendered"
			else:
				detail = "%d chunks, %d with contours" % [chunk_count, contour_count]
			_append_event({"type": "tactical_map_verified", "ok": ok,
				"visible": is_visible, "chunk_count": chunk_count,
				"contour_count": contour_count, "detail": detail})
			_ack(cmd_id, true)

		"quit":
			_ack(cmd_id, true)
			get_tree().call_deferred("quit")

		_:
			_ack(cmd_id, false, "Unknown command: " + cmd_type)


func _ack(cmd_id: int, ok: bool, error: String = "") -> void:
	var data: Dictionary = {"type": "cmd_ack", "id": cmd_id, "ok": ok}
	if error != "":
		data["error"] = error
	_append_event(data)
