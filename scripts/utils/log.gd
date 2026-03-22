extends Node

# File-based logger — autoloaded as Log.
# Writes to <project_root>/debug.log, overwriting on each run.
# Usage:  Log.write("some message")

var _file: FileAccess = null
var _path: String = ""


func _ready() -> void:
	_path = ProjectSettings.globalize_path("res://debug.log")
	_file = FileAccess.open(_path, FileAccess.WRITE)
	if _file == null:
		push_error("Log: cannot open %s  err=%s" % [_path, str(FileAccess.get_open_error())])
		return
	_write("=== session started %s ===" % Time.get_datetime_string_from_system())


func write(msg: String) -> void:
	_write("[%s] %s" % [Time.get_time_string_from_system(), msg])


func _write(line: String) -> void:
	if _file == null:
		return
	_file.store_line(line)
	_file.flush()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _file != null:
		_file.close()
		_file = null
