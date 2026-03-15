extends Node

signal low_disk_warning(free_fraction: float)
signal write_refused(reason: String)

const MIN_FREE_FRACTION := 0.25
const WORLDS_BASE_PATH := "user://worlds/"

# --- Disk space checks ---

func get_free_bytes() -> int:
	# TODO: Godot 4 has no cross-platform free-space API in GDScript.
	# Return a large sentinel value until a GDExtension solution is added.
	return 100 * 1024 * 1024 * 1024  # 100 GB placeholder


func get_total_bytes() -> int:
	return _estimated_total


var _estimated_total: int = 0


func _ready() -> void:
	_estimate_total_disk()


func _estimate_total_disk() -> void:
	# Godot 4 has no cross-platform API for total disk size.
	# Heuristic: assume at least 10 GB is used on the drive beyond current free space.
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
		# Unknown total — only refuse if free space itself is very low (< 1 GB)
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


# --- World directory helpers ---

func worlds_dir() -> String:
	return WORLDS_BASE_PATH


func world_dir(world_name: String) -> String:
	return WORLDS_BASE_PATH + world_name + "/"


func chunks_dir(world_name: String) -> String:
	return world_dir(world_name) + "chunks/"


func manifest_path(world_name: String) -> String:
	return world_dir(world_name) + "world_manifest.tres"


func ensure_world_dir(world_name: String) -> Error:
	var path := chunks_dir(world_name)
	if not DirAccess.dir_exists_absolute(path):
		return DirAccess.make_dir_recursive_absolute(path)
	return OK


# --- World enumeration ---

class WorldEntry:
	var name: String
	var manifest_path: String
	var disk_bytes: int
	var created_at: int
	var is_valid: bool
	var forge_version: int = 0


func list_worlds() -> Array[WorldEntry]:
	var entries: Array[WorldEntry] = []
	var dir := DirAccess.open(WORLDS_BASE_PATH)
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
	return _delete_dir_recursive(path)


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
	dir.list_dir_begin()
	var item := dir.get_next()
	while item != "":
		if not item.begins_with("."):
			var full := path + item
			if dir.current_is_dir():
				_delete_dir_recursive(full + "/")
				dir.remove(item)
			else:
				dir.remove(item)
		item = dir.get_next()
	dir.list_dir_end()
	return DirAccess.remove_absolute(path)
