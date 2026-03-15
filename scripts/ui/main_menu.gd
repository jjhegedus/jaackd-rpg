class_name MainMenu
extends Control

# Entry point for the application.
#
# On launch:
#   - Checks whether any valid world exists in user://worlds/
#   - If no world: Play is disabled; only World Forge is available
#   - If a world exists: both options are available
#
# Play launches the session setup screen (character selection).
# World Forge opens the world creation tool.

@onready var title_label: Label          = $VBox/TitleLabel
@onready var play_btn: Button            = $VBox/PlayBtn
@onready var forge_btn: Button           = $VBox/ForgeBtn
@onready var edit_btn: Button            = $VBox/EditBtn
@onready var quit_btn: Button            = $VBox/QuitBtn
@onready var world_list: ItemList        = $VBox/WorldList
@onready var world_status: Label         = $VBox/WorldStatusLabel
@onready var delete_btn: Button          = $VBox/DeleteBtn

const WORLD_FORGE_SCENE := "res://scenes/world_forge/world_forge.tscn"
const GAME_WORLD_SCENE  := "res://scenes/world/game_world.tscn"

var _worlds: Array = []   # Array of DiskManager.WorldEntry
var _selected_world: String = ""


func _ready() -> void:
	play_btn.pressed.connect(_on_play)
	forge_btn.pressed.connect(_on_forge)
	edit_btn.pressed.connect(_on_edit)
	quit_btn.pressed.connect(_on_quit)
	delete_btn.pressed.connect(_on_delete)
	world_list.item_selected.connect(_on_world_selected)

	_refresh_world_list()


func _notify_screen_ready() -> void:
	if OS.is_debug_build():
		DebugBridge.screen_ready("MainMenu", "", [
			{"id": "PlayBtn",   "node": play_btn},
			{"id": "ForgeBtn",  "node": forge_btn},
			{"id": "EditBtn",   "node": edit_btn},
			{"id": "DeleteBtn", "node": delete_btn},
			{"id": "QuitBtn",   "node": quit_btn},
			{"id": "WorldList", "node": world_list},
		])


func _refresh_world_list() -> void:
	world_list.clear()
	_worlds = DiskManager.list_worlds()
	_selected_world = ""

	for entry in _worlds:
		var e: DiskManager.WorldEntry = entry
		var size_mb: float = e.disk_bytes / (1024.0 * 1024.0)
		var label: String = "%s  (%.1f MB)" % [e.name, size_mb]
		if not e.is_valid:
			label += "  [incomplete]"
		elif e.forge_version < WorldManifest.CURRENT_FORGE_VERSION:
			label += "  [outdated]"
		world_list.add_item(label)

	var has_valid: bool = _worlds.any(func(e): return e.is_valid)
	play_btn.disabled = not has_valid
	edit_btn.disabled = true
	delete_btn.disabled = true

	if _worlds.is_empty():
		world_status.text = "No worlds found. Use World Forge to create one."
	else:
		world_status.text = "Select a world to play."

	# Auto-select first valid world.
	for i in _worlds.size():
		if _worlds[i].is_valid:
			world_list.select(i)
			_on_world_selected(i)
			break

	_notify_screen_ready()


func _on_world_selected(idx: int) -> void:
	if idx < 0 or idx >= _worlds.size():
		return
	var entry: DiskManager.WorldEntry = _worlds[idx]
	_selected_world = entry.name
	play_btn.disabled = not entry.is_valid
	edit_btn.disabled = false
	delete_btn.disabled = false
	var size_mb: float = entry.disk_bytes / (1024.0 * 1024.0)
	var status: String = "%s — %.1f MB on disk" % [entry.name, size_mb]
	if entry.is_valid and entry.forge_version < WorldManifest.CURRENT_FORGE_VERSION:
		status += "  (outdated — use Edit World to update)"
	world_status.text = status


func _on_play() -> void:
	if _selected_world == "":
		return
	var manifest_path := DiskManager.manifest_path(_selected_world)
	var manifest := WorldManifest.load_from(manifest_path)
	if manifest == null or not manifest.is_valid:
		world_status.text = "Error: world data is invalid or missing."
		return
	WorldManager.initialize(manifest)
	get_tree().change_scene_to_file(GAME_WORLD_SCENE)


func _on_forge() -> void:
	WorldManager.edit_world_name = ""
	get_tree().change_scene_to_file(WORLD_FORGE_SCENE)


func _on_edit() -> void:
	if _selected_world == "":
		return
	WorldManager.edit_world_name = _selected_world
	get_tree().change_scene_to_file(WORLD_FORGE_SCENE)


func _on_quit() -> void:
	get_tree().quit()


func _on_delete() -> void:
	if _selected_world == "":
		return
	var err := DiskManager.delete_world(_selected_world)
	if err == OK:
		_refresh_world_list()
	else:
		world_status.text = "Failed to delete world (error %d)." % err
