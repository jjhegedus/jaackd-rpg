extends Node

# Turn state machine. Autoloaded as TurnManager.
#
# Owns the active TravelCommand and TravelSimulation. Drives simulation ticks
# each _process() frame during the RESOLUTION phase.
#
# Turn types:
#   TRAVEL   — entities moving; TravelSimulation ticking
#   REST     — entities resting; TravelSimulation ticking (same engine, no movement)
#   ENCOUNTER — tactical combat; not yet implemented (placeholder state)
#
# Phases:
#   PLANNING   — player is issuing orders (simulation idle)
#   RESOLUTION — simulation running; player watches
#   REVIEW     — simulation complete; player can replay / change camera before
#                confirming they are ready to return to PLANNING

# -----------------------------------------------------------------------
# Signals
# -----------------------------------------------------------------------

signal phase_changed(turn_type: int, phase: int)
signal encounter_triggered(position: Vector3, attacker_ids: Array[int])
signal interlude_triggered(position: Vector3, threat_direction: Vector2)
signal command_completed(command: Variant)

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

var _active_command = null  # TravelCommand
var _simulation = null      # TravelSimulation
var _sim_accum_hours: float = 0.0  # fractional tick accumulator


# -----------------------------------------------------------------------
# Lifecycle
# -----------------------------------------------------------------------

func _ready() -> void:
	pass


func _process(delta: float) -> void:
	if phase != Phase.RESOLUTION:
		return
	if _simulation == null or not _simulation.is_running():
		return

	# Accumulate real time → sim time, then step in TICK_HOURS increments.
	_sim_accum_hours += delta * SIM_HOURS_PER_REAL_SECOND

	while _sim_accum_hours >= 0.25 and _simulation.is_running():  # 0.25 = TravelSimulation.TICK_HOURS
		_sim_accum_hours -= 0.25
		_simulation.step()


# -----------------------------------------------------------------------
# Public API — called by UI / game logic
# -----------------------------------------------------------------------

# Issue a travel or rest command. Entities are identified by id; their
# current world positions are passed so TravelSimulation can track them.
func issue_command(
		command,  # TravelCommand
		entity_positions: Array[Vector3],
		entity_ids: Array[int]) -> void:

	if phase != Phase.PLANNING:
		push_warning("TurnManager: cannot issue command while not in PLANNING phase")
		return

	_active_command = command
	_sim_accum_hours = 0.0

	_simulation = load("res://scripts/world/navigation/travel_simulation.gd").new()
	_simulation.encounter_triggered.connect(_on_encounter_triggered)
	_simulation.interlude_triggered.connect(_on_interlude_triggered)
	_simulation.command_completed.connect(_on_command_completed)
	_simulation.initialize(WorldManager._manifest, command, entity_positions, entity_ids)

	turn_type = TurnType.REST if command.is_rest() else TurnType.TRAVEL
	_set_phase(Phase.RESOLUTION)


# Interrupt the running simulation (e.g. player presses "Stop").
func interrupt_command() -> void:
	if _simulation != null:
		_simulation.interrupt()
	_set_phase(Phase.REVIEW)


# Player has finished reviewing the last turn and is ready for new orders.
func end_review() -> void:
	if phase != Phase.REVIEW:
		return
	_active_command = null
	_simulation = null
	_set_phase(Phase.PLANNING)


# Query current entity positions from the running (or most recent) simulation.
func get_entity_positions() -> Array[Vector3]:
	if _simulation == null:
		return []
	return _simulation.get_entity_positions()


func get_active_command():  # -> TravelCommand
	return _active_command


# -----------------------------------------------------------------------
# Simulation callbacks
# -----------------------------------------------------------------------

func _on_encounter_triggered(position: Vector3, entity_ids: Array[int]) -> void:
	# Simulation has already interrupted itself.
	turn_type = TurnType.ENCOUNTER
	_set_phase(Phase.PLANNING)
	encounter_triggered.emit(position, entity_ids)


func _on_interlude_triggered(position: Vector3, threat_dir: Vector2) -> void:
	# Simulation has already interrupted itself.
	_set_phase(Phase.PLANNING)
	interlude_triggered.emit(position, threat_dir)


func _on_command_completed(hours_elapsed: float) -> void:
	_set_phase(Phase.REVIEW)
	command_completed.emit(_active_command)


# -----------------------------------------------------------------------
# Internal
# -----------------------------------------------------------------------

func _set_phase(new_phase: Phase) -> void:
	if phase == new_phase:
		return
	phase = new_phase
	phase_changed.emit(turn_type, phase)
