extends Node

# Turn state machine. Autoloaded as TurnManager.
#
# Owns pending commands (one per group) and active simulations.
# Drives simulation ticks each _process() frame during RESOLUTION.
#
# Turn types:
#   TRAVEL   — entities moving; TravelSimulation ticking
#   REST     — entities resting; TravelSimulation ticking (same engine, no movement)
#   ENCOUNTER — tactical combat; not yet implemented (placeholder state)
#
# Phases:
#   PLANNING   — players are issuing commands to their groups; ready gate open
#   RESOLUTION — all simulations running simultaneously on one world clock
#   REVIEW     — all simulations complete; players can observe before re-planning
#
# Planning window:
#   Opens at session start and whenever any simulation completes or is interrupted.
#   All simulations are paused during PLANNING/REVIEW. Each peer has a ready flag;
#   when all peers confirm ready, execution begins.
#
#   Note: the design calls for in-progress simulations to continue while only
#   affected groups re-plan. That refinement is deferred — for now all simulations
#   pause together when any event fires.

# -----------------------------------------------------------------------
# Signals
# -----------------------------------------------------------------------

signal phase_changed(turn_type: int, phase: int)
signal encounter_triggered(position: Vector3, attacker_ids: Array[int])
signal interlude_triggered(position: Vector3, threat_direction: Vector2)
signal command_completed(command: Variant)
signal command_submitted(group_id: int)
signal peer_ready_changed(peer_id: int, is_ready: bool)
signal all_peers_ready

# -----------------------------------------------------------------------
# Enums
# -----------------------------------------------------------------------

enum TurnType { TRAVEL, REST, ENCOUNTER }
enum Phase    { PLANNING, RESOLUTION, REVIEW }

# -----------------------------------------------------------------------
# State
# -----------------------------------------------------------------------

var turn_type: TurnType = TurnType.TRAVEL
var phase: Phase = Phase.PLANNING

# Simulation ticks advance by this many sim-hours per real second during
# RESOLUTION. Tune to taste: 2.0 = a 24-hour day resolves in 12 real seconds.
const SIM_HOURS_PER_REAL_SECOND := 2.0

# Pending commands set by players during PLANNING (group_id → TravelCommand).
var _pending_commands: Dictionary = {}

# Active simulations running during RESOLUTION (group_id → TravelSimulation).
var _active_simulations: Dictionary = {}

# Fractional sim-hour accumulator shared across all simulations.
var _sim_accum_hours: float = 0.0

# Per-peer ready flags (peer_id → bool). All must be true before execution starts.
var _ready_peers: Dictionary = {}

# Peers that must confirm ready before execution. Updated from NetworkManager signals.
var _connected_peers: Array[int] = []


# -----------------------------------------------------------------------
# Lifecycle
# -----------------------------------------------------------------------

func _ready() -> void:
	NetworkManager.server_started.connect(_on_server_started)
	NetworkManager.peer_joined.connect(_on_peer_joined)
	NetworkManager.peer_left.connect(_on_peer_left)


func _process(delta: float) -> void:
	if phase != Phase.RESOLUTION:
		return

	_sim_accum_hours += delta * SIM_HOURS_PER_REAL_SECOND

	while _sim_accum_hours >= 0.25:
		_sim_accum_hours -= 0.25
		var any_running := false
		for gid in _active_simulations:
			var sim = _active_simulations[gid]
			if sim.is_running():
				sim.step()
				any_running = true
		if not any_running:
			break


# -----------------------------------------------------------------------
# Public API — command submission
# -----------------------------------------------------------------------

# Store a pending command for a group during PLANNING.
# Replaces any previous pending command for that group.
# Un-readies the owning peer so they must re-confirm after changing a command.
func submit_command(group_id: int, command) -> void:  # command: TravelCommand
	if phase != Phase.PLANNING:
		push_warning("TurnManager: cannot submit command outside PLANNING phase")
		return
	var group := EntityRegistry.get_group(group_id)
	if group == null:
		push_warning("TurnManager: no group with id %d" % group_id)
		return
	command.group_id = group_id
	_pending_commands[group_id] = command
	command_submitted.emit(group_id)
	# Changing a command un-readies the owning peer.
	var owner := group.owner_peer_id
	if owner >= 0 and _ready_peers.get(owner, false):
		_ready_peers[owner] = false
		peer_ready_changed.emit(owner, false)


func get_pending_command(group_id: int):  # -> TravelCommand or null
	return _pending_commands.get(group_id)


func clear_command(group_id: int) -> void:
	_pending_commands.erase(group_id)


# -----------------------------------------------------------------------
# Public API — ready gate
# -----------------------------------------------------------------------

# Mark a peer as ready (or un-ready). When all connected peers are ready,
# execution starts automatically.
func set_peer_ready(peer_id: int, is_ready: bool) -> void:
	if phase != Phase.PLANNING:
		return
	if _ready_peers.get(peer_id, false) == is_ready:
		return
	_ready_peers[peer_id] = is_ready
	peer_ready_changed.emit(peer_id, is_ready)
	if is_ready:
		_check_all_ready()


func is_peer_ready(peer_id: int) -> bool:
	return _ready_peers.get(peer_id, false)


# -----------------------------------------------------------------------
# Public API — other
# -----------------------------------------------------------------------

# Interrupt all running simulations (e.g. player presses "Stop").
func interrupt_command() -> void:
	_interrupt_all_simulations()
	_set_phase(Phase.REVIEW)


# All peers have finished reviewing; return to PLANNING for the next window.
func end_review() -> void:
	if phase != Phase.REVIEW:
		return
	_active_simulations.clear()
	_ready_peers.clear()
	_set_phase(Phase.PLANNING)


# Query current entity positions from the active simulation for a group.
func get_entity_positions(group_id: int = -1) -> Array[Vector3]:
	if group_id >= 0:
		var sim = _active_simulations.get(group_id)
		if sim != null:
			return sim.get_entity_positions()
		return []
	# No group specified — return positions from all active simulations.
	var result: Array[Vector3] = []
	for gid in _active_simulations:
		result.append_array(_active_simulations[gid].get_entity_positions())
	return result


func get_pending_commands() -> Dictionary:
	return _pending_commands.duplicate()


# -----------------------------------------------------------------------
# NetworkManager callbacks — peer tracking
# -----------------------------------------------------------------------

func _on_server_started() -> void:
	_connected_peers = [NetworkManager.local_peer_id]
	_ready_peers.clear()


func _on_peer_joined(peer_id: int) -> void:
	if not _connected_peers.has(peer_id):
		_connected_peers.append(peer_id)
	_ready_peers[peer_id] = false
	peer_ready_changed.emit(peer_id, false)


func _on_peer_left(peer_id: int) -> void:
	_connected_peers.erase(peer_id)
	_ready_peers.erase(peer_id)
	# A peer leaving may unblock the ready gate.
	if phase == Phase.PLANNING:
		_check_all_ready()


# -----------------------------------------------------------------------
# Internal — ready gate
# -----------------------------------------------------------------------

func _check_all_ready() -> void:
	if _connected_peers.is_empty():
		return
	for pid in _connected_peers:
		if not _ready_peers.get(pid, false):
			return
	all_peers_ready.emit()
	_start_execution()


func _start_execution() -> void:
	if _pending_commands.is_empty():
		# All groups idle — nothing to execute. Stay in PLANNING.
		return

	_active_simulations.clear()
	_sim_accum_hours = 0.0

	var any_travel := false
	for group_id in _pending_commands:
		var command = _pending_commands[group_id]
		var group := EntityRegistry.get_group(group_id)
		if group == null:
			continue

		var entity_ids: Array[int] = []
		var entity_positions: Array[Vector3] = []
		for mid in group.member_ids:
			entity_ids.append(mid)
			entity_positions.append(EntityRegistry.get_entity_pos(mid))

		var sim = load("res://scripts/world/navigation/travel_simulation.gd").new()
		sim.encounter_triggered.connect(_on_encounter_triggered)
		sim.interlude_triggered.connect(_on_interlude_triggered)
		sim.command_completed.connect(_on_command_completed.bind(group_id))
		sim.initialize(WorldManager._manifest, command, entity_positions, entity_ids)
		_active_simulations[group_id] = sim

		if not command.is_rest():
			any_travel = true

	_pending_commands.clear()
	turn_type = TurnType.TRAVEL if any_travel else TurnType.REST
	_set_phase(Phase.RESOLUTION)


func _interrupt_all_simulations() -> void:
	for gid in _active_simulations:
		var sim = _active_simulations[gid]
		if sim.is_running():
			sim.interrupt()


# -----------------------------------------------------------------------
# Simulation callbacks
# -----------------------------------------------------------------------

func _on_encounter_triggered(position: Vector3, entity_ids: Array[int]) -> void:
	_interrupt_all_simulations()
	turn_type = TurnType.ENCOUNTER
	_ready_peers.clear()
	_set_phase(Phase.PLANNING)
	encounter_triggered.emit(position, entity_ids)


func _on_interlude_triggered(position: Vector3, threat_dir: Vector2) -> void:
	_interrupt_all_simulations()
	_ready_peers.clear()
	_set_phase(Phase.PLANNING)
	interlude_triggered.emit(position, threat_dir)


func _on_command_completed(_hours_elapsed: float, _group_id: int) -> void:
	# Check if all simulations have now finished.
	for gid in _active_simulations:
		if _active_simulations[gid].is_running():
			return
	# All done — move to REVIEW.
	_set_phase(Phase.REVIEW)
	command_completed.emit(null)


# -----------------------------------------------------------------------
# Internal
# -----------------------------------------------------------------------

func _set_phase(new_phase: Phase) -> void:
	if phase == new_phase:
		return
	phase = new_phase
	phase_changed.emit(turn_type, phase)
