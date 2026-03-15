class_name TacticalCamera
extends Node3D

# Overhead tactical camera — always sits directly above the selected entity.
#
# Three degrees of freedom:
#   Scroll wheel   — zoom (Y height above entity)
#   A / D          — yaw (rotate around world Y axis)
#   W / S          — pitch (tilt from overhead toward isometric)
#
# No free panning; the camera tracks the selected entity automatically.

signal ground_chunk_changed(face: int, chunk_x: int, chunk_y: int)

const MIN_HEIGHT   := 30.0
const MAX_HEIGHT   := 4000.0
const MIN_PITCH    := -85.0   # near-overhead
const MAX_PITCH    :=  80.0   # looking up past horizontal
const DEFAULT_PITCH := -75.0
const ZOOM_FACTOR  := 0.15    # fraction of current height per scroll step
const YAW_SPEED    := 90.0    # degrees per second
const PITCH_SPEED  := 45.0    # degrees per second
const SMOOTH_FACTOR := 8.0

enum Mode { GLOBAL, ZOOMED }

var mode: Mode = Mode.GLOBAL

var _camera: Camera3D

var _target_pos: Vector3   = Vector3.ZERO
var _target_base_y: float  = 0.0
var _target_height: float  = 500.0
var _yaw_deg: float        = 0.0
var _pitch_deg: float      = DEFAULT_PITCH

var _last_chunk_x: int = -9999
var _last_chunk_y: int = -9999
var _active: bool = false
var _input_enabled: bool = true


func _ready() -> void:
	_camera = Camera3D.new()
	add_child(_camera)
	EntityRegistry.selection_changed.connect(_on_selection_changed)
	EntityRegistry.position_updated.connect(_on_entity_moved)


func activate() -> void:
	_active = true
	_camera.current = true
	_snap_to_selected()


func deactivate() -> void:
	_active = false
	_camera.current = false


func get_camera() -> Camera3D:
	return _camera


func snap_to_entities() -> void:
	_snap_to_selected()


# -----------------------------------------------------------------------
# Frame loop
# -----------------------------------------------------------------------

func _process(delta: float) -> void:
	if not _active:
		return
	_handle_input(delta)
	_smooth_move(delta)
	_check_chunk_change()


func set_input_enabled(enabled: bool) -> void:
	_input_enabled = enabled


func _handle_input(delta: float) -> void:
	if not _input_enabled:
		return
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		_yaw_deg -= YAW_SPEED * delta
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		_yaw_deg += YAW_SPEED * delta
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		_pitch_deg = clampf(_pitch_deg + PITCH_SPEED * delta, MIN_PITCH, MAX_PITCH)
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		_pitch_deg = clampf(_pitch_deg - PITCH_SPEED * delta, MIN_PITCH, MAX_PITCH)


func _unhandled_input(event: InputEvent) -> void:
	if not _active or not _input_enabled:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			match mb.button_index:
				MOUSE_BUTTON_WHEEL_UP:
					_target_height = clampf(
						_target_height * (1.0 - ZOOM_FACTOR), MIN_HEIGHT, MAX_HEIGHT)
				MOUSE_BUTTON_WHEEL_DOWN:
					_target_height = clampf(
						_target_height * (1.0 + ZOOM_FACTOR), MIN_HEIGHT, MAX_HEIGHT)


func _smooth_move(delta: float) -> void:
	var t := clampf(SMOOTH_FACTOR * delta, 0.0, 1.0)
	var cam_pos := Vector3(_target_pos.x, _target_base_y + _target_height, _target_pos.z)
	global_position = global_position.lerp(cam_pos, t)
	_camera.rotation_degrees = Vector3(_pitch_deg, _yaw_deg, 0.0)


func _check_chunk_change() -> void:
	var manifest := WorldManager._manifest
	if manifest == null:
		return
	var chunk_size_m := float(manifest.chunk_cells_local) * manifest.cell_size_local_m
	var cx := int(_target_pos.x / chunk_size_m)
	var cy := int(_target_pos.z / chunk_size_m)
	if cx != _last_chunk_x or cy != _last_chunk_y:
		_last_chunk_x = cx
		_last_chunk_y = cy
		ground_chunk_changed.emit(0, cx, cy)


# -----------------------------------------------------------------------
# Entity tracking
# -----------------------------------------------------------------------

func _snap_to_selected() -> void:
	var sel_id := EntityRegistry.get_selected_id()
	if sel_id < 0:
		return
	var pos := EntityRegistry.get_entity_pos(sel_id)
	_target_pos   = Vector3(pos.x, 0.0, pos.z)
	_target_base_y = pos.y
	global_position = Vector3(_target_pos.x, _target_base_y + _target_height, _target_pos.z)
	_camera.rotation_degrees = Vector3(_pitch_deg, _yaw_deg, 0.0)


func _on_selection_changed(_id: int, _is_selected: bool) -> void:
	if _active:
		_snap_to_selected()


func _on_entity_moved(id: int, pos: Vector3) -> void:
	if not _active:
		return
	if id != EntityRegistry.get_selected_id():
		return
	_target_pos    = Vector3(pos.x, 0.0, pos.z)
	_target_base_y = pos.y
