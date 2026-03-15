class_name EntityCamController
extends Node3D

# Ghost camera that sits at a selected entity's eye position.
# Used for the first-person viewport in turn mode and action mode.
#
# This is not a physics body — it has no collision.  It simply follows
# whatever entity is currently yellow-selected in EntityRegistry.
#
# Controls (when active):
#   Mouse movement — look around (pitch/yaw)
#   Tab or Escape  — return to tactical camera (handled externally via signal)
#
# The caller (GameWorld) listens to switch_requested and swaps cameras.

signal switch_requested   # player wants to return to tactical view

const EYE_HEIGHT  := 1.7    # metres above entity ground position
const MOUSE_SENS  := 0.002  # radians per pixel

var _camera: Camera3D
var _pitch: float = 0.0
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
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func deactivate() -> void:
	_active = false
	_camera.current = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func get_camera() -> Camera3D:
	return _camera


# -----------------------------------------------------------------------
# Frame loop
# -----------------------------------------------------------------------

func _process(_delta: float) -> void:
	if not _active:
		return
	_sync_position()


func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return

	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		rotate_y(-motion.relative.x * MOUSE_SENS)
		_pitch = clampf(
			_pitch - motion.relative.y * MOUSE_SENS,
			deg_to_rad(-80.0), deg_to_rad(80.0))
		_camera.rotation.x = _pitch

	if event.is_action_pressed("ui_cancel"):
		switch_requested.emit()

	if event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and ke.physical_keycode == KEY_TAB:
			switch_requested.emit()


# -----------------------------------------------------------------------
# Position sync
# -----------------------------------------------------------------------

func _sync_position() -> void:
	if _entity_id < 0:
		return
	var pos := EntityRegistry.get_entity_pos(_entity_id)
	# Only update if entity is at a real position (not zero / unregistered).
	if pos != Vector3.ZERO:
		global_position = pos + Vector3(0.0, EYE_HEIGHT, 0.0)


# -----------------------------------------------------------------------
# EntityRegistry callbacks
# -----------------------------------------------------------------------

func _on_selection_changed(id: int, is_selected: bool) -> void:
	if is_selected:
		_entity_id = id
		_sync_position()


func _on_entity_moved(id: int, new_pos: Vector3) -> void:
	if id == _entity_id and _active:
		global_position = new_pos + Vector3(0.0, EYE_HEIGHT, 0.0)
