class_name EntityCamController
extends Node3D

# Ghost camera that sits at a selected entity's eye position.
# Used for the full-screen first-person view in entity mode.
#
# Controls (when active):
#   W / Up    — look up
#   S / Down  — look down
#   A / Left  — look left
#   D / Right — look right
#   Scroll    — zoom FOV in / out
#   Tab       — return to tactical camera (via switch_requested signal)

signal switch_requested   # player wants to return to tactical view

const EYE_HEIGHT  := 1.7    # metres above entity ground position
const YAW_SPEED   := 90.0   # degrees per second
const PITCH_SPEED := 45.0   # degrees per second
const MIN_PITCH   := -80.0
const MAX_PITCH   :=  80.0
const ZOOM_FACTOR := 0.15
const MIN_FOV     := 20.0
const MAX_FOV     := 90.0

var _camera: Camera3D
var _pitch_deg: float = -10.0   # slight downward tilt by default
var _yaw_deg: float   = 0.0
var _entity_id: int = -1
var _active: bool = false


# -----------------------------------------------------------------------
# Lifecycle
# -----------------------------------------------------------------------

func _ready() -> void:
	_camera = Camera3D.new()
	add_child(_camera)

	EntityRegistry.selection_changed.connect(_on_selection_changed)
	EntityRegistry.position_updated.connect(_on_entity_moved)


func activate() -> void:
	_active = true
	_camera.current = true
	_entity_id = EntityRegistry.get_selected_id()
	_sync_position()


func deactivate() -> void:
	_active = false
	_camera.current = false


func get_camera() -> Camera3D:
	return _camera


# -----------------------------------------------------------------------
# Frame loop — WASD look, position sync
# -----------------------------------------------------------------------

func _process(delta: float) -> void:
	if not _active:
		return
	_handle_look_input(delta)
	_sync_position()


func _handle_look_input(delta: float) -> void:
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		_yaw_deg -= YAW_SPEED * delta
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		_yaw_deg += YAW_SPEED * delta
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		_pitch_deg = clampf(_pitch_deg + PITCH_SPEED * delta, MIN_PITCH, MAX_PITCH)
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		_pitch_deg = clampf(_pitch_deg - PITCH_SPEED * delta, MIN_PITCH, MAX_PITCH)
	_camera.rotation_degrees = Vector3(_pitch_deg, _yaw_deg, 0.0)


func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			match mb.button_index:
				MOUSE_BUTTON_WHEEL_UP:
					_camera.fov = clampf(_camera.fov * (1.0 - ZOOM_FACTOR), MIN_FOV, MAX_FOV)
				MOUSE_BUTTON_WHEEL_DOWN:
					_camera.fov = clampf(_camera.fov * (1.0 + ZOOM_FACTOR), MIN_FOV, MAX_FOV)

	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		switch_requested.emit()

	if event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and ke.physical_keycode == KEY_TAB:
			get_viewport().set_input_as_handled()
			switch_requested.emit()


# -----------------------------------------------------------------------
# Position sync
# -----------------------------------------------------------------------

func _sync_position() -> void:
	if _entity_id < 0:
		return
	var pos := EntityRegistry.get_entity_pos(_entity_id)
	if pos != Vector3.ZERO:
		global_position = pos + Vector3(0.0, EYE_HEIGHT, 0.0)


# -----------------------------------------------------------------------
# EntityRegistry callbacks
# -----------------------------------------------------------------------

func _on_selection_changed(id: int, is_selected: bool) -> void:
	if is_selected:
		_entity_id = id
		if _active:
			_sync_position()


func _on_entity_moved(id: int, new_pos: Vector3) -> void:
	if id == _entity_id and _active:
		global_position = new_pos + Vector3(0.0, EYE_HEIGHT, 0.0)
