class_name TravelCommand
extends Resource

# A player-issued strategic movement or rest order.
#
# The command defines where to go (or to rest), for how long / until what
# condition, at what pace and formation. TravelSimulation executes it.
#
# Commands are interruptible — an encounter or interlude fires mid-execution
# and the remaining time is preserved in time_remaining_hours.

# -----------------------------------------------------------------------
# Enums
# -----------------------------------------------------------------------

enum Type { TRAVEL, REST }

enum Termination {
	DURATION,     # for N hours
	TIME_OF_DAY,  # until a specific clock hour (e.g. 20.0 = dusk)
	DESTINATION,  # until a specific chunk is reached
	DISTANCE,     # until N metres travelled from start
}

# Pace affects movement speed and concealment (cautious = slower but quieter).
enum Pace { CAUTIOUS, NORMAL, FAST }

# Formation affects collective viewshed spread vs mutual support.
enum Formation { TIGHT, STANDARD, SPREAD }

# -----------------------------------------------------------------------
# Command parameters (set by the player)
# -----------------------------------------------------------------------

@export var type: Type = Type.TRAVEL

@export var termination: Termination = Termination.DURATION
@export var duration_hours: float = 8.0            # DURATION
@export var target_hour: float = 20.0              # TIME_OF_DAY (20 = dusk)
@export var destination_chunk: Vector2i = Vector2i.ZERO  # DESTINATION
@export var distance_m: float = 0.0               # DISTANCE

# Travel direction in world XZ, normalised. Ignored for DESTINATION termination.
@export var direction: Vector2 = Vector2(0.0, 1.0)

@export var pace: Pace = Pace.NORMAL
@export var formation: Formation = Formation.STANDARD

# -----------------------------------------------------------------------
# Execution state (written by TravelSimulation)
# -----------------------------------------------------------------------

var time_remaining_hours: float = 0.0   # updated as the command executes
var distance_remaining_m: float = 0.0  # for DISTANCE termination

# -----------------------------------------------------------------------
# Constants per pace
# -----------------------------------------------------------------------

# Base human travel speed at normal pace: ~5 km/h on flat terrain.
const BASE_SPEED_M_PER_HOUR := 5000.0

const _PACE_SPEED := {
	Pace.CAUTIOUS: 0.5,
	Pace.NORMAL:   1.0,
	Pace.FAST:     1.7,
}

# Concealment modifier from pace: positive = better hidden, negative = more exposed.
const _PACE_CONCEALMENT := {
	Pace.CAUTIOUS:  0.15,   # moving quietly
	Pace.NORMAL:    0.0,
	Pace.FAST:     -0.25,   # noisy, hard to miss
}

# Detection (perception) modifier from formation: spread formation gives wider
# collective viewshed; tight formation has overlapping blind spots.
const _FORMATION_DETECTION := {
	Formation.TIGHT:    -0.1,
	Formation.STANDARD:  0.0,
	Formation.SPREAD:    0.2,
}

# -----------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------

func get_speed_m_per_hour() -> float:
	return BASE_SPEED_M_PER_HOUR * _PACE_SPEED.get(pace, 1.0)


func get_pace_concealment_modifier() -> float:
	return _PACE_CONCEALMENT.get(pace, 0.0)


func get_formation_detection_modifier() -> float:
	return _FORMATION_DETECTION.get(formation, 0.0)


func is_rest() -> bool:
	return type == Type.REST


# Compute the initial time budget for this command given the current clock state.
func compute_initial_duration() -> float:
	match termination:
		Termination.DURATION:
			return duration_hours
		Termination.TIME_OF_DAY:
			return WorldClock.hours_until(target_hour)
		Termination.DISTANCE:
			var speed := get_speed_m_per_hour()
			return distance_m / maxf(speed, 1.0)
		Termination.DESTINATION:
			# Duration is unknown; use a generous day cap.
			return 24.0
	return duration_hours


# Human-readable summary for UI / debug.
func describe() -> String:
	var type_str := "Rest" if is_rest() else "Travel"
	var pace_str: String = ["cautious", "normal", "fast"][pace]
	match termination:
		Termination.DURATION:
			return "%s %s for %.1fh" % [type_str, pace_str, duration_hours]
		Termination.TIME_OF_DAY:
			return "%s %s until %02d:00" % [type_str, pace_str, int(target_hour)]
		Termination.DESTINATION:
			return "%s %s to chunk (%d,%d)" % [type_str, pace_str,
				destination_chunk.x, destination_chunk.y]
		Termination.DISTANCE:
			return "%s %s for %.0fm" % [type_str, pace_str, distance_m]
	return type_str
