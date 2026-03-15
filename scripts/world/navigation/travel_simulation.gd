class_name TravelSimulation
extends RefCounted

# Executes a TravelCommand for a set of entities.
#
# Ticks in chunk-crossing intervals. At each tick:
#   1. Advance entity positions along command direction.
#   2. Advance WorldClock.
#   3. Run detection sweeps (player viewsheds vs enemy positions, and vice-versa).
#   4. Fire encounter_triggered or interlude_triggered if thresholds are crossed.
#   5. Check termination condition.
#
# Encounter trigger:
#   - Action-based: a party with visibility takes a hostile action.  (resolved externally)
#   - Mutual detection: both sides have DETECTED level on each other → encounter_triggered.
#
# Interlude trigger:
#   - One-sided PARTIAL detection: the player entities sense something but can't confirm.
#   - Emits interlude_triggered; caller (TurnManager) pauses for player decision.

signal encounter_triggered(position: Vector3, detected_entity_ids: Array[int])
signal interlude_triggered(position: Vector3, threat_direction: Vector2)
signal command_completed(hours_elapsed: float)
signal progress_updated(fraction: float, position: Vector3)

# Simulation tick size in hours. Each tick advances the clock and moves entities
# by (speed × tick) metres. Smaller = more detection resolution, more CPU.
const TICK_HOURS := 0.25   # 15-minute ticks

# At normal pace (~5km/h), 15 min = 1250m per tick. At 4m/cell local LOD,
# that's ~312 cells — roughly 4-5 chunks. Fine enough for encounter detection.

var _manifest: WorldManifest
var _command: TravelCommand
var _entity_positions: Array[Vector3]
var _entity_ids: Array[int]

var _hours_elapsed: float = 0.0
var _distance_travelled_m: float = 0.0
var _is_running: bool = false
var _total_duration_hours: float = 0.0

# Detection state tracked between ticks to distinguish new vs sustained detections.
# Keys: entity_id (int), values: DetectionSystem.DetectionLevel
var _last_player_detection_of_enemy: Dictionary = {}
var _last_enemy_detection_of_player: Dictionary = {}


# -----------------------------------------------------------------------
# Initialise and run
# -----------------------------------------------------------------------

func initialize(
		manifest: WorldManifest,
		command: TravelCommand,
		entity_positions: Array[Vector3],
		entity_ids: Array[int]) -> void:

	_manifest = manifest
	_command = command
	_entity_positions = entity_positions.duplicate()
	_entity_ids = entity_ids.duplicate()
	_hours_elapsed = 0.0
	_distance_travelled_m = 0.0
	_is_running = true

	_total_duration_hours = command.compute_initial_duration()
	command.time_remaining_hours = _total_duration_hours

	if command.termination == TravelCommand.Termination.DISTANCE:
		command.distance_remaining_m = command.distance_m


# Advance simulation by one tick.
# Called from TurnManager._process() during the RESOLUTION phase.
func step() -> void:
	if not _is_running:
		return

	var dt := minf(TICK_HOURS, _command.time_remaining_hours)
	if dt <= 0.0:
		_complete()
		return

	# Move entities.
	var chunk_size_m := float(_manifest.chunk_cells_local) * _manifest.cell_size_local_m
	var cell_size    := _manifest.cell_size_local_m
	if not _command.is_rest():
		var dist_m := _command.get_speed_m_per_hour() * dt
		var move := Vector3(_command.direction.x, 0.0, _command.direction.y) * dist_m
		for i in _entity_positions.size():
			_entity_positions[i] += move
			# Snap Y to terrain surface.
			var snap_chunk := _get_chunk_at(_entity_positions[i], chunk_size_m)
			if snap_chunk != null:
				var lx := _world_to_local_cell(_entity_positions[i].x, chunk_size_m, cell_size, snap_chunk.cells_x)
				var lz := _world_to_local_cell(_entity_positions[i].z, chunk_size_m, cell_size, snap_chunk.cells_y)
				_entity_positions[i].y = snap_chunk.get_height(lx, lz)
			EntityRegistry.update_position(_entity_ids[i], _entity_positions[i])
		_distance_travelled_m += dist_m
		if _command.termination == TravelCommand.Termination.DISTANCE:
			_command.distance_remaining_m -= dist_m

	# Advance simulation clock.
	WorldClock.advance(dt * 3600.0)
	_hours_elapsed += dt
	_command.time_remaining_hours -= dt

	# Detection sweep at this tick position.
	_run_detection_sweep()

	# Emit progress for UI.
	var fraction := _hours_elapsed / maxf(_total_duration_hours, 0.001)
	var lead_pos := _entity_positions[0] if not _entity_positions.is_empty() else Vector3.ZERO
	progress_updated.emit(clampf(fraction, 0.0, 1.0), lead_pos)

	# Check termination.
	if _check_termination():
		_complete()


func interrupt() -> void:
	_is_running = false


func is_running() -> bool:
	return _is_running


func get_entity_positions() -> Array[Vector3]:
	return _entity_positions


# -----------------------------------------------------------------------
# Detection sweep
# -----------------------------------------------------------------------

func _run_detection_sweep() -> void:
	if _entity_positions.is_empty() or _manifest == null:
		return

	var chunk_size_m := float(_manifest.chunk_cells_local) * _manifest.cell_size_local_m
	var cell_size    := _manifest.cell_size_local_m
	var light        := WorldClock.get_light_level()
	var pace_conceal := _command.get_pace_concealment_modifier()
	var form_detect  := _command.get_formation_detection_modifier()

	# --- Player-entity viewshed sweep ---
	# For each controlled entity, compute viewshed and record which cells are
	# visible. Later, when EntityRegistry provides enemy positions, those cells
	# will be checked for detection.

	var player_viewsheds: Array[PackedByteArray] = []

	for pos in _entity_positions:
		var chunk := _get_chunk_at(pos, chunk_size_m)
		if chunk == null:
			continue

		var hmap  := chunk.get_final_heightmap()
		var w     := chunk.cells_x
		var h     := chunk.cells_y
		var lx    := _world_to_local_cell(pos.x, chunk_size_m, cell_size, w)
		var lz    := _world_to_local_cell(pos.z, chunk_size_m, cell_size, h)

		# Player entity perception boost from formation.
		var perception := clampf(0.6 + form_detect, 0.0, 1.0)

		var max_range := int(DetectionSystem.MAX_DETECT_RANGE_M / cell_size)
		var vs := ViewshedSystem.compute(hmap, w, h, lx, lz,
			DetectionSystem.EYE_HEIGHT_STANDING, max_range, cell_size)
		player_viewsheds.append(vs)

	# Merge into a collective player viewshed.
	var collective_vs := ViewshedSystem.merge(player_viewsheds)

	if _entity_positions.is_empty():
		return

	var lead_pos := _entity_positions[0]

	# Build enemy target list from EntityRegistry.
	var enemy_targets := EntityRegistry.build_detection_targets(
		lead_pos,
		DetectionSystem.MAX_DETECT_RANGE_M,
		chunk_size_m,
		cell_size)

	if enemy_targets.is_empty():
		return

	# Get the chunk under the lead entity for player-side detection.
	var lead_chunk := _get_chunk_at(lead_pos, chunk_size_m)
	if lead_chunk == null:
		return

	var hmap  := lead_chunk.get_final_heightmap()
	var w     := lead_chunk.cells_x
	var h     := lead_chunk.cells_y
	var lead_lx := _world_to_local_cell(lead_pos.x, chunk_size_m, cell_size, w)
	var lead_lz := _world_to_local_cell(lead_pos.z, chunk_size_m, cell_size, h)

	# Player perception boosted by formation modifier.
	var perception := clampf(0.6 + _command.get_formation_detection_modifier(), 0.0, 1.0)

	# Player concealment affected by pace.
	var player_biome_idx := lead_chunk.biome_map[lead_lz * w + lead_lx] if not lead_chunk.biome_map.is_empty() else 0
	var player_conceal := DetectionSystem.entity_concealment(
		player_biome_idx, 0.0, _command.get_pace_concealment_modifier())

	# Sweep: can player see each enemy?
	var player_sees: Array = DetectionSystem.sweep(
		hmap, w, h, lead_lx, lead_lz, perception,
		enemy_targets, DetectionSystem.EYE_HEIGHT_STANDING, light, cell_size)

	# For each enemy, also check if the enemy can see the player.
	for i in enemy_targets.size():
		var t: Dictionary = enemy_targets[i]
		var enemy_id: int  = t.get("id", -1)
		var enemy_lx: int  = t.get("x", 0)
		var enemy_lz: int  = t.get("y", 0)

		# Enemy detection of player (default perception 0.5 until stats are wired).
		var enemy_sees_player: DetectionSystem.DetectionLevel = DetectionSystem.check_detection(
			hmap, w, h,
			enemy_lx, enemy_lz, 0.5,
			lead_lx, lead_lz, player_conceal,
			DetectionSystem.EYE_HEIGHT_STANDING,
			DetectionSystem.EYE_HEIGHT_STANDING,
			light, cell_size)

		var player_sees_enemy: DetectionSystem.DetectionLevel = player_sees[i]

		# Mutual detection → encounter trigger.
		if (player_sees_enemy == DetectionSystem.DetectionLevel.DETECTED
				and enemy_sees_player == DetectionSystem.DetectionLevel.DETECTED):
			encounter_triggered.emit(lead_pos, [enemy_id])
			interrupt()
			return

		# Enemy sees player but player does not see enemy → interlude.
		if (enemy_sees_player >= DetectionSystem.DetectionLevel.PARTIAL
				and player_sees_enemy == DetectionSystem.DetectionLevel.NONE):
			var enemy_world_pos := EntityRegistry.get_entity_pos(enemy_id)
			var threat_dir := Vector2(
				enemy_world_pos.x - lead_pos.x,
				enemy_world_pos.z - lead_pos.z).normalized()
			interlude_triggered.emit(lead_pos, threat_dir)
			interrupt()
			return


# -----------------------------------------------------------------------
# Termination check
# -----------------------------------------------------------------------

func _check_termination() -> bool:
	match _command.termination:
		TravelCommand.Termination.DURATION, TravelCommand.Termination.TIME_OF_DAY:
			return _command.time_remaining_hours <= 0.0

		TravelCommand.Termination.DISTANCE:
			return _command.distance_remaining_m <= 0.0

		TravelCommand.Termination.DESTINATION:
			var chunk_size_m := float(_manifest.chunk_cells_local) * _manifest.cell_size_local_m
			var dest := _command.destination_chunk
			for pos in _entity_positions:
				var cx := int(pos.x / chunk_size_m)
				var cz := int(pos.z / chunk_size_m)
				if Vector2i(cx, cz) == dest:
					return true
			return false

	return false


func _complete() -> void:
	_is_running = false
	command_completed.emit(_hours_elapsed)


# -----------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------

func _get_chunk_at(world_pos: Vector3, chunk_size_m: float) -> ChunkData:
	var cx := int(world_pos.x / chunk_size_m)
	var cz := int(world_pos.z / chunk_size_m)
	return WorldManager.get_chunk(0, cx, cz, ChunkData.LOD.LOCAL)


func _world_to_local_cell(
		world_coord: float,
		chunk_size_m: float,
		cell_size: float,
		max_cells: int) -> int:
	var local := fmod(world_coord, chunk_size_m)
	# fmod can return negative values for negative world_coord.
	if local < 0.0:
		local += chunk_size_m
	return clampi(int(local / cell_size), 0, max_cells - 1)
