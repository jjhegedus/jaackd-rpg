class_name PlayerController
extends CharacterBody3D

# First-person / third-person player controller.
# Handles movement, camera, and triggers viewshed updates when the player
# moves into a new chunk or cell.
#
# Attach to a CharacterBody3D with:
#   CameraArm (SpringArm3D) → Camera3D
#   CollisionShape3D (capsule)

signal chunk_changed(face: int, chunk_x: int, chunk_y: int)
signal cell_changed(face: int, chunk_x: int, chunk_y: int, cell_x: int, cell_y: int)

const MOVE_SPEED      := 6.0    # m/s walking
const RUN_MULTIPLIER  := 2.0
const JUMP_VELOCITY   := 5.0
const MOUSE_SENS      := 0.002  # rad/pixel
const GRAVITY         := 9.8

const LOCAL_CELL_M    := 4.0    # metres per local LOD cell (matches LODManager)
const CHUNK_CELLS     := 64     # cells per chunk side (must match ChunkData default)

@onready var camera_arm: SpringArm3D = $CameraArm
@onready var camera: Camera3D        = $CameraArm/Camera3D

var character: Character   # the Character resource this player is driving
var _face: int = 0
var _chunk_x: int = 0
var _chunk_y: int = 0
var _cell_x: int = 0
var _cell_y: int = 0
var _camera_pitch: float = 0.0


func _ready() -> void:
	add_to_group("player")
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENS)
		_camera_pitch = clampf(
			_camera_pitch - event.relative.y * MOUSE_SENS,
			deg_to_rad(-80.0), deg_to_rad(80.0)
		)
		camera_arm.rotation.x = _camera_pitch

	if event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(
			Input.MOUSE_MODE_VISIBLE
			if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
			else Input.MOUSE_MODE_CAPTURED
		)


func _physics_process(delta: float) -> void:
	# Gravity
	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	# Jump
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Horizontal movement
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	var speed := MOVE_SPEED * (RUN_MULTIPLIER if Input.is_action_pressed("run") else 1.0)

	if direction != Vector3.ZERO:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed)
		velocity.z = move_toward(velocity.z, 0.0, speed)

	move_and_slide()

	# Update character world_pos for AI / viewshed / session systems.
	if character:
		character.world_pos = global_position

	_update_chunk_cell()


func _update_chunk_cell() -> void:
	var world_x := int(global_position.x)
	var world_z := int(global_position.z)

	var new_cell_x := int(world_x / LOCAL_CELL_M)
	var new_cell_y := int(world_z / LOCAL_CELL_M)
	var new_chunk_x := new_cell_x / CHUNK_CELLS
	var new_chunk_y := new_cell_y / CHUNK_CELLS
	var local_cell_x := new_cell_x % CHUNK_CELLS
	var local_cell_y := new_cell_y % CHUNK_CELLS

	if new_chunk_x != _chunk_x or new_chunk_y != _chunk_y:
		_chunk_x = new_chunk_x
		_chunk_y = new_chunk_y
		WorldManager.update_active_chunks(_face, _chunk_x, _chunk_y)
		chunk_changed.emit(_face, _chunk_x, _chunk_y)

	if local_cell_x != _cell_x or local_cell_y != _cell_y:
		_cell_x = local_cell_x
		_cell_y = local_cell_y
		cell_changed.emit(_face, _chunk_x, _chunk_y, _cell_x, _cell_y)
