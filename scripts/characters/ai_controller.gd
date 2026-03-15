class_name AIController
extends Node

# AI state machine for unassigned characters (no human player/WM controlling them).
#
# Driven entirely by the intervisibility system — the AI only reacts to things
# its character can actually see. No cheating.
#
# States:
#   IDLE    — standing still or performing a routine activity
#   PATROL  — moving along a route (home ↔ workplace or random waypoints)
#   PURSUE  — moving toward a detected target
#   FLEE    — moving away from a threat (low health)
#   ATTACK  — in range, performing attack action
#
# Transitions are triggered by viewshed results, not global state.
# The AI uses ViewshedSystem.cone_check() first (cheap), then full LOS if cone passes.

signal state_changed(new_state: State)
signal target_spotted(target_character_id: int)
signal target_lost

enum State { IDLE, PATROL, PURSUE, FLEE, ATTACK }

# How often (seconds) the AI re-evaluates its viewshed.
const THINK_INTERVAL := 0.5
# Distance (cells) at which PURSUE switches to ATTACK.
const ATTACK_RANGE_CELLS := 2
# Health fraction below which the AI flees.
const FLEE_HEALTH_FRACTION := 0.25
# How long (seconds) to stay in PURSUE after losing sight.
const PURSUE_LINGER := 8.0

@export var character: Character

var state: State = State.IDLE
var target_id: int = -1              # character_id of current target
var last_seen_pos: Vector2i          # last known cell position of target
var _think_timer: float = 0.0
var _pursue_linger_timer: float = 0.0
var _patrol_waypoints: Array[Vector2i] = []
var _patrol_index: int = 0

# Injected by the entity that owns this controller.
var _world_manager: Node
var _session_manager: SessionManager
var _face: int = 0
var _chunk_x: int = 0
var _chunk_y: int = 0
var _cell_x: int = 0
var _cell_y: int = 0


func setup(
		p_character: Character,
		p_world_manager: Node,
		p_session_manager: SessionManager,
		face: int, chunk_x: int, chunk_y: int,
		cell_x: int, cell_y: int) -> void:
	character = p_character
	_world_manager = p_world_manager
	_session_manager = p_session_manager
	_face = face
	_chunk_x = chunk_x
	_chunk_y = chunk_y
	_cell_x = cell_x
	_cell_y = cell_y
	_build_patrol_route()


func _process(delta: float) -> void:
	if character == null or not character.alive:
		return

	_think_timer -= delta
	if _think_timer <= 0.0:
		_think_timer = THINK_INTERVAL
		_think()

	_update_linger(delta)


# --- State machine ---

func _think() -> void:
	match state:
		State.IDLE:
			_think_idle()
		State.PATROL:
			_think_patrol()
		State.PURSUE:
			_think_pursue()
		State.FLEE:
			_think_flee()
		State.ATTACK:
			_think_attack()


func _think_idle() -> void:
	if _scan_for_threats():
		return
	# Idle characters eventually start patrolling.
	if _patrol_waypoints.size() > 0:
		_transition(State.PATROL)


func _think_patrol() -> void:
	_scan_for_threats()
	# Movement toward next waypoint handled externally (CharacterEntity).


func _think_pursue() -> void:
	var target := _find_target_character()
	if target == null:
		_pursue_linger_timer = PURSUE_LINGER
		_transition(State.PATROL)
		return

	if _is_in_attack_range(target):
		_transition(State.ATTACK)
		return

	if _health_fraction() < FLEE_HEALTH_FRACTION:
		_transition(State.FLEE)
		return

	# Check if still visible via cone first, then full LOS.
	if not _can_see_target(target):
		# Lost sight — linger before giving up.
		_pursue_linger_timer -= THINK_INTERVAL
		if _pursue_linger_timer <= 0.0:
			target_id = -1
			target_lost.emit()
			_transition(State.PATROL)
	else:
		_pursue_linger_timer = PURSUE_LINGER
		last_seen_pos = Vector2i(target.world_pos.x, target.world_pos.z)
		_session_manager.mark_encountered(target.character_id,
			character.controller_id if character.controller_id >= 0 else 1)


func _think_flee() -> void:
	if _health_fraction() >= FLEE_HEALTH_FRACTION:
		_transition(State.PATROL)
		return
	# Movement away from threat handled by CharacterEntity using last_seen_pos.


func _think_attack() -> void:
	var target := _find_target_character()
	if target == null or not target.alive:
		target_id = -1
		target_lost.emit()
		_transition(State.PATROL)
		return
	if not _is_in_attack_range(target):
		_transition(State.PURSUE)
		return
	if _health_fraction() < FLEE_HEALTH_FRACTION:
		_transition(State.FLEE)


# --- Detection ---

func _scan_for_threats() -> bool:
	if _world_manager == null:
		return false

	var chunk: ChunkData = _world_manager.get_chunk(
		_face, _chunk_x, _chunk_y, ChunkData.LOD.LOCAL)
	if chunk == null:
		return false

	var heightmap := chunk.get_final_heightmap()
	var w := chunk.cells_x
	var h := chunk.cells_y

	# Check all player-controlled characters for proximity + LOS.
	for c in _get_player_characters():
		var tcx: int = int(c.world_pos.x) / int(LODManager.LOCAL_CELL_M)
		var tcy: int = int(c.world_pos.z) / int(LODManager.LOCAL_CELL_M)

		# Cheap cone check first.
		if not ViewshedSystem.cone_check(heightmap, w, h,
				_cell_x, _cell_y, 1.7, tcx, tcy):
			continue

		# Full LOS.
		if LineOfSight.check(heightmap, w, h,
				_cell_x, _cell_y, 1.7, tcx, tcy, 1.0):
			target_id = c.character_id
			last_seen_pos = Vector2i(tcx, tcy)
			target_spotted.emit(target_id)
			_transition(State.PURSUE)
			return true

	return false


func _can_see_target(target: Character) -> bool:
	if _world_manager == null:
		return false
	var chunk: ChunkData = _world_manager.get_chunk(
		_face, _chunk_x, _chunk_y, ChunkData.LOD.LOCAL)
	if chunk == null:
		return false
	var tcx := int(target.world_pos.x) / int(LODManager.LOCAL_CELL_M)
	var tcy := int(target.world_pos.z) / int(LODManager.LOCAL_CELL_M)
	return LineOfSight.check(
		chunk.get_final_heightmap(), chunk.cells_x, chunk.cells_y,
		_cell_x, _cell_y, 1.7, tcx, tcy, 1.0)


func _is_in_attack_range(target: Character) -> bool:
	var tcx := int(target.world_pos.x) / int(LODManager.LOCAL_CELL_M)
	var tcy := int(target.world_pos.z) / int(LODManager.LOCAL_CELL_M)
	var dx := tcx - _cell_x
	var dy := tcy - _cell_y
	return dx * dx + dy * dy <= ATTACK_RANGE_CELLS * ATTACK_RANGE_CELLS


# --- Helpers ---

func _transition(new_state: State) -> void:
	if state == new_state:
		return
	state = new_state
	state_changed.emit(new_state)


func _update_linger(delta: float) -> void:
	if state == State.PURSUE and target_id < 0:
		_pursue_linger_timer -= delta


func _health_fraction() -> float:
	if character == null or character.stats == null:
		return 1.0
	if character.stats.max_health <= 0:
		return 1.0
	return float(character.stats.health) / float(character.stats.max_health)


func _find_target_character() -> Character:
	if target_id < 0 or _session_manager == null:
		return null
	return _session_manager._find_character(target_id)


func _get_player_characters() -> Array[Character]:
	if _session_manager == null:
		return []
	var result: Array[Character] = []
	for peer_id in _session_manager.assignments:
		if peer_id == -1:
			continue
		for cid in _session_manager.assignments[peer_id]:
			var c := _session_manager._find_character(cid)
			if c and c.alive and c.controller == Character.Controller.PLAYER:
				result.append(c)
	return result


func _build_patrol_route() -> void:
	# Simple two-point patrol: home ↔ workplace.
	# CharacterEntity will translate building names to cell coordinates later.
	_patrol_waypoints.clear()
	_patrol_index = 0

	# Placeholder waypoints at current position — extended when buildings are placed.
	_patrol_waypoints.append(Vector2i(_cell_x, _cell_y))


func get_patrol_target() -> Vector2i:
	if _patrol_waypoints.is_empty():
		return Vector2i(_cell_x, _cell_y)
	return _patrol_waypoints[_patrol_index % _patrol_waypoints.size()]


func advance_patrol() -> void:
	if _patrol_waypoints.size() > 0:
		_patrol_index = (_patrol_index + 1) % _patrol_waypoints.size()
