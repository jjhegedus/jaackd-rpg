extends Node

signal low_disk_warning(free_fraction: float)
signal write_refused(reason: String)
signal save_dir_needed   # Emitted when a save path is required but none is configured.
						 # UI should respond by calling set_save_dir().

const MIN_FREE_FRACTION := 0.25
const CONFIG_FILENAME   := "jaackd_rpg.cfg"
const CONFIG_SECTION    := "storage"
const CONFIG_KEY_DIR    := "save_directory"

var _save_dir: String = ""   # Absolute path, trailing slash. Empty = not yet configured.


# -----------------------------------------------------------------------
# Lifecycle
# -----------------------------------------------------------------------

func _ready() -> void:
	_estimate_total_disk()
	_load_config()


# -----------------------------------------------------------------------
# Save directory
# -----------------------------------------------------------------------

func has_save_dir() -> bool:
	return not _save_dir.is_empty()


## Set and persist the user's chosen save directory.
## Creates the directory if it does not yet exist.
func set_save_dir(path: String) -> Error:
	var normalised := path.rstrip("/\\") + "/"
	var err := DirAccess.make_dir_recursive_absolute(normalised)
	if err != OK:
		push_error("DiskManager: could not create save directory '%s': %s" % [normalised, error_string(err)])
		return err
	_save_dir = normalised
	_save_config()
	return OK


## Returns the worlds root directory, or emits save_dir_needed and returns ""
## if no save directory has been configured yet.
func worlds_dir() -> String:
	if _save_dir.is_empty():
		save_dir_needed.emit()
		return ""
	return _save_dir + "worlds/"


func world_dir(world_name: String) -> String:
	var base := worlds_dir()
	if base.is_empty():
		return ""
	return base + world_name + "/"


func chunks_dir(world_name: String) -> String:
	var base := world_dir(world_name)
	if base.is_empty():
		return ""
	return base + "chunks/"


func manifest_path(world_name: String) -> String:
	var base := world_dir(world_name)
	if base.is_empty():
		return ""
	return base + "world_manifest.tres"


func ensure_world_dir(world_name: String) -> Error:
	var path := chunks_dir(world_name)
	if path.is_empty():
		return ERR_UNCONFIGURED
	if not DirAccess.dir_exists_absolute(path):
		return DirAccess.make_dir_recursive_absolute(path)
	return OK


# -----------------------------------------------------------------------
# Disk space checks
# -----------------------------------------------------------------------

func get_free_bytes() -> int:
	# TODO: Godot 4 has no cross-platform free-space API in GDScript.
	# Return a large sentinel value until a GDExtension solution is added.
	return 100 * 1024 * 1024 * 1024  # 100 GB placeholder


func get_total_bytes() -> int:
	return _estimated_total


var _estimated_total: int = 0


func _estimate_total_disk() -> void:
	var free := get_free_bytes()
	_estimated_total = free + 10 * 1024 * 1024 * 1024


func get_free_fraction() -> float:
	if _estimated_total <= 0:
		return 1.0
	return float(get_free_bytes()) / float(_estimated_total)


func can_write(estimated_bytes: int) -> bool:
	var free := get_free_bytes()
	var after_write := free - estimated_bytes
	if _estimated_total <= 0:
		if after_write < 1 * 1024 * 1024 * 1024:
			write_refused.emit("Less than 1 GB remaining after write.")
			return false
		return true
	var fraction_after := float(after_write) / float(_estimated_total)
	if fraction_after < MIN_FREE_FRACTION:
		write_refused.emit(
			"Write would reduce free disk space below %.0f%%. Aborting." % (MIN_FREE_FRACTION * 100)
		)
		return false
	if fraction_after < MIN_FREE_FRACTION + 0.05:
		low_disk_warning.emit(fraction_after)
	return true


# -----------------------------------------------------------------------
# World enumeration
# -----------------------------------------------------------------------

class WorldEntry:
	var name: String
	var manifest_path: String
	var disk_bytes: int
	var created_at: int
	var is_valid: bool
	var forge_version: int = 0


func list_worlds() -> Array[WorldEntry]:
	var entries: Array[WorldEntry] = []
	var base := worlds_dir()
	if base.is_empty():
		return entries
	var dir := DirAccess.open(base)
	if dir == null:
		return entries
	dir.list_dir_begin()
	var item := dir.get_next()
	while item != "":
		if dir.current_is_dir() and not item.begins_with("."):
			var entry := WorldEntry.new()
			entry.name = item
			entry.manifest_path = manifest_path(item)
			entry.disk_bytes = _dir_size_bytes(world_dir(item))
			var manifest := WorldManifest.load_from(entry.manifest_path)
			if manifest:
				entry.created_at = manifest.created_at
				entry.is_valid = manifest.is_valid
				entry.forge_version = manifest.forge_version
			entries.append(entry)
		item = dir.get_next()
	dir.list_dir_end()
	return entries


func delete_world(world_name: String) -> Error:
	var path := world_dir(world_name)
	if path.is_empty():
		return ERR_UNCONFIGURED
	return _delete_dir_recursive(path)


# -----------------------------------------------------------------------
# Config persistence (stored next to the executable, not in AppData)
# -----------------------------------------------------------------------

func _config_path() -> String:
	if OS.is_debug_build():
		return ProjectSettings.globalize_path("res://") + CONFIG_FILENAME
	return OS.get_executable_path().get_base_dir() + "/" + CONFIG_FILENAME


func _load_config() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_config_path()) != OK:
		return
	var val: String = cfg.get_value(CONFIG_SECTION, CONFIG_KEY_DIR, "")
	if not val.is_empty():
		_save_dir = val.rstrip("/\\") + "/"


func _save_config() -> void:
	var cfg := ConfigFile.new()
	cfg.load(_config_path())   # preserve any other keys that may exist
	cfg.set_value(CONFIG_SECTION, CONFIG_KEY_DIR, _save_dir)
	var err := cfg.save(_config_path())
	if err != OK:
		push_error("DiskManager: could not write config to '%s': %s" % [_config_path(), error_string(err)])


# -----------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------

func _dir_size_bytes(path: String) -> int:
	var total := 0
	var dir := DirAccess.open(path)
	if dir == null:
		return 0
	dir.list_dir_begin()
	var item := dir.get_next()
	while item != "":
		var full := path + item
		if dir.current_is_dir() and not item.begins_with("."):
			total += _dir_size_bytes(full + "/")
		else:
			total += FileAccess.get_file_as_bytes(full).size()
		item = dir.get_next()
	dir.list_dir_end()
	return total


func _delete_dir_recursive(path: String) -> Error:
	var dir := DirAccess.open(path)
	if dir == null:
		return ERR_DOES_NOT_EXIST
	# Collect all entries first — deleting while iterating skips items on Windows.
	var subdirs: Array[String] = []
	var files:   Array[String] = []
	dir.list_dir_begin()
	var item := dir.get_next()
	while item != "":
		if not item.begins_with("."):
			if dir.current_is_dir():
				subdirs.append(item)
			else:
				files.append(item)
		item = dir.get_next()
	dir.list_dir_end()
	for f in files:
		dir.remove(f)
	for sub in subdirs:
		_delete_dir_recursive(path + sub + "/")
		dir.remove(sub)
	return DirAccess.remove_absolute(path)
