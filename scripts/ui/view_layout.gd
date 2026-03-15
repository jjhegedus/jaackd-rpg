class_name ViewLayout
extends CanvasLayer

# Manages the split-screen layout for Turn Mode.
#
# Modes:
#   TACTICAL_FULL  — main viewport shows tactical overhead only (full screen)
#   SPLIT          — main viewport shows tactical overhead (left panel), plus
#                    a SubViewportContainer overlay covering the right 40% that
#                    renders the yellow-selected entity's first-person view.
#
# The FP SubViewport uses own_world_3d = false to share the main World3D,
# so it sees the same terrain and characters without duplicating anything.
# The tactical camera keeps the main viewport; ViewLayout's internal FP
# camera tracks the selected entity directly from EntityRegistry.
#
# Usage (from GameWorld):
#   _view_layout = ViewLayout.new()
#   add_child(_view_layout)
#   _view_layout.set_mode(ViewLayout.Mode.SPLIT)

enum Mode { TACTICAL_FULL, SPLIT }

const SPLIT_RATIO  := 0.6     # fraction of screen width given to tactical view
const BORDER_PX    := 2       # thin divider between panels
const EYE_HEIGHT_M := 1.7     # metres above entity ground position
const YAW_SPEED    := 90.0    # degrees per second
const PITCH_SPEED  := 45.0    # degrees per second
const MIN_PITCH    := -80.0
const MAX_PITCH    :=  80.0
const ZOOM_FACTOR  := 0.15    # fraction of FOV per scroll step
const MIN_FOV      := 20.0
const MAX_FOV      := 90.0

var _mode: Mode = Mode.TACTICAL_FULL
var _fp_yaw_deg: float   = 0.0
var _fp_pitch_deg: float = -10.0  # slight downward tilt by default

var _fp_container: SubViewportContainer
var _fp_viewport: SubViewport
var _fp_camera: Camera3D
var _divider: ColorRect


func _ready() -> void:
	layer = 10   # above HUD (default layer 0)
	_build_panels()
	_apply_mode()
	EntityRegistry.selection_changed.connect(_on_selection_changed)
	EntityRegistry.position_updated.connect(_on_entity_moved)


func set_mode(mode: Mode) -> void:
	if mode == _mode:
		return
	_mode = mode
	_apply_mode()


func get_mode() -> Mode:
	return _mode


# -----------------------------------------------------------------------
# Panel construction
# -----------------------------------------------------------------------

func _build_panels() -> void:
	# Thin vertical divider (hidden in TACTICAL_FULL mode).
	_divider = ColorRect.new()
	_divider.color = Color(0.0, 0.0, 0.0, 0.8)
	add_child(_divider)

	# FP SubViewportContainer — covers the right portion of the screen.
	_fp_container = SubViewportContainer.new()
	_fp_container.stretch = true
	add_child(_fp_container)

	_fp_viewport = SubViewport.new()
	_fp_viewport.own_world_3d = false     # share the main World3D
	_fp_viewport.transparent_bg = false
	_fp_container.add_child(_fp_viewport)

	_fp_camera = Camera3D.new()
	_fp_camera.name = "FPCamera"
	_fp_viewport.add_child(_fp_camera)

	_update_panel_sizes()


# -----------------------------------------------------------------------
# Mode application
# -----------------------------------------------------------------------

func _apply_mode() -> void:
	var split_active := _mode == Mode.SPLIT
	_fp_container.visible = split_active
	_divider.visible = split_active
	if split_active:
		_update_panel_sizes()
		_sync_fp_camera()


func _update_panel_sizes() -> void:
	var vp_size := get_viewport().get_visible_rect().size
	var fp_w := int(vp_size.x * (1.0 - SPLIT_RATIO))
	var fp_x := int(vp_size.x * SPLIT_RATIO)

	_fp_container.set_position(Vector2(fp_x, 0.0))
	_fp_container.set_size(Vector2(fp_w, vp_size.y))
	_fp_viewport.size = Vector2i(fp_w, int(vp_size.y))

	_divider.set_position(Vector2(fp_x - BORDER_PX, 0.0))
	_divider.set_size(Vector2(BORDER_PX, vp_size.y))


# -----------------------------------------------------------------------
# Input — WASD / arrows rotate FP camera when in SPLIT mode
# -----------------------------------------------------------------------

func _process(delta: float) -> void:
	if _mode != Mode.SPLIT:
		return
	_handle_fp_input(delta)


func _handle_fp_input(delta: float) -> void:
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		_fp_yaw_deg -= YAW_SPEED * delta
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		_fp_yaw_deg += YAW_SPEED * delta
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		_fp_pitch_deg = clampf(_fp_pitch_deg + PITCH_SPEED * delta, MIN_PITCH, MAX_PITCH)
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		_fp_pitch_deg = clampf(_fp_pitch_deg - PITCH_SPEED * delta, MIN_PITCH, MAX_PITCH)
	_fp_camera.rotation_degrees = Vector3(_fp_pitch_deg, _fp_yaw_deg, 0.0)


func _unhandled_input(event: InputEvent) -> void:
	if _mode != Mode.SPLIT:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			match mb.button_index:
				MOUSE_BUTTON_WHEEL_UP:
					_fp_camera.fov = clampf(_fp_camera.fov * (1.0 - ZOOM_FACTOR), MIN_FOV, MAX_FOV)
				MOUSE_BUTTON_WHEEL_DOWN:
					_fp_camera.fov = clampf(_fp_camera.fov * (1.0 + ZOOM_FACTOR), MIN_FOV, MAX_FOV)


# -----------------------------------------------------------------------
# FP camera — tracks yellow-selected entity from EntityRegistry
# -----------------------------------------------------------------------

func _sync_fp_camera() -> void:
	var sel_id := EntityRegistry.get_selected_id()
	if sel_id < 0:
		return
	var pos := EntityRegistry.get_entity_pos(sel_id)
	_fp_camera.global_position = pos + Vector3(0.0, EYE_HEIGHT_M, 0.0)
	_fp_camera.rotation_degrees = Vector3(_fp_pitch_deg, _fp_yaw_deg, 0.0)


func _on_selection_changed(_id: int, _is_selected: bool) -> void:
	if _mode == Mode.SPLIT:
		_sync_fp_camera()


func _on_entity_moved(id: int, _pos: Vector3) -> void:
	if _mode == Mode.SPLIT and id == EntityRegistry.get_selected_id():
		_sync_fp_camera()


# -----------------------------------------------------------------------
# Viewport resize
# -----------------------------------------------------------------------

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_SIZE_CHANGED and _mode == Mode.SPLIT:
		_update_panel_sizes()
