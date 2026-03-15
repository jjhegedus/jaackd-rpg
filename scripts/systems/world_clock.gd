extends Node

# Simulation world clock. Tracks time in seconds since the start of the world.
# Autoloaded as WorldClock.
#
# All simulation systems (TravelSimulation, DetectionSystem light level,
# "travel until dusk" conditions) query this.

signal day_changed(day: int)
signal hour_crossed(hour: int)            # fires each time a whole hour passes
signal time_of_day_changed(is_day: bool)  # fires at dawn and dusk

const SECONDS_PER_HOUR  := 3600.0
const HOURS_PER_DAY     := 24.0
const DAWN_HOUR         := 6.0    # first light
const DUSK_HOUR         := 20.0   # last light

# Start at 8:00 on day 1.
var _elapsed_seconds: float = 8.0 * SECONDS_PER_HOUR


# -----------------------------------------------------------------------
# Advance
# -----------------------------------------------------------------------

func advance(seconds: float) -> void:
	var prev_day    := get_day()
	var prev_hour_i := int(get_hour())
	var prev_is_day := is_daytime()

	_elapsed_seconds += seconds

	var new_day    := get_day()
	var new_hour_i := int(get_hour())
	var new_is_day := is_daytime()

	if new_day != prev_day:
		day_changed.emit(new_day)

	if new_hour_i != prev_hour_i:
		hour_crossed.emit(new_hour_i)

	if new_is_day != prev_is_day:
		time_of_day_changed.emit(new_is_day)


# -----------------------------------------------------------------------
# Queries
# -----------------------------------------------------------------------

# Fractional hour within the day (0.0 .. 24.0).
func get_hour() -> float:
	return fmod(_elapsed_seconds / SECONDS_PER_HOUR, HOURS_PER_DAY)


# Whole day number (0-based).
func get_day() -> int:
	return int(_elapsed_seconds / (SECONDS_PER_HOUR * HOURS_PER_DAY))


func is_daytime() -> bool:
	var h := get_hour()
	return h >= DAWN_HOUR and h < DUSK_HOUR


# Hours remaining until the given target hour today.
# If target has already passed today, returns hours until that time tomorrow.
func hours_until(target_hour: float) -> float:
	var current := get_hour()
	if target_hour > current:
		return target_hour - current
	return (HOURS_PER_DAY - current) + target_hour


# Light level for detection calculations: 0.0 (full dark) .. 1.0 (full day).
# Peaks around noon, drops to a minimum at night.
func get_light_level() -> float:
	var h := get_hour()
	if not is_daytime():
		return 0.05  # near-dark; moonlight / starlight minimum
	# Smooth ramp: dawn/dusk = 0.3, noon (13:00) = 1.0
	var noon := (DAWN_HOUR + DUSK_HOUR) * 0.5
	var half_span := (DUSK_HOUR - DAWN_HOUR) * 0.5
	var dist_from_noon := absf(h - noon)
	return clampf(1.0 - (dist_from_noon / half_span) * 0.7, 0.3, 1.0)


func get_time_string() -> String:
	var h := int(get_hour())
	var m := int(fmod(get_hour(), 1.0) * 60.0)
	return "Day %d  %02d:%02d" % [get_day() + 1, h, m]


# -----------------------------------------------------------------------
# Save / restore (for world persistence)
# -----------------------------------------------------------------------

func get_elapsed_seconds() -> float:
	return _elapsed_seconds


func set_elapsed_seconds(s: float) -> void:
	_elapsed_seconds = maxf(0.0, s)
