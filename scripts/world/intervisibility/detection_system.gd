class_name DetectionSystem
extends RefCounted

# Asymmetric detection built on top of symmetric LOS/viewshed geometry.
#
# LOS (terrain) is symmetric — if terrain allows a ray from A to B, it allows B to A.
# Detection adds one-way modifiers:
#   observer perception  (0..1) — how well they spot things
#   target concealment   (0..1) — how hard they are to see (cover, shadow, posture)
#   light level          (0..1) — darkness boosts target concealment
#
# Detection levels:
#   NONE     — no awareness
#   PARTIAL  — "feeling watched" — triggers interlude, not full encounter
#   DETECTED — full detection — can trigger encounter

enum DetectionLevel { NONE, PARTIAL, DETECTED }

# Eye heights in metres above terrain surface.
const EYE_HEIGHT_STANDING := 1.7
const EYE_HEIGHT_CROUCHED := 0.8
const EYE_HEIGHT_PRONE    := 0.3

# Base concealment by biome index (matches TerrainChunkMesh height bands / biome palette).
# 0 = fully exposed, 1 = perfectly hidden.
const BIOME_CONCEALMENT: Array[float] = [
	0.0,   # 0 deep water  — not applicable but defined for index safety
	0.05,  # 1 shallow water
	0.05,  # 2 sand / beach
	0.15,  # 3 lowland grass
	0.35,  # 4 highland meadow
	0.15,  # 5 bare rock
	0.10,  # 6 snow / ice (very exposed)
	0.60,  # 7 dense forest (if biome table extends here)
]

# Distance at which detection is 100% (no falloff).
const FULL_DETECT_RANGE_M := 50.0
# Distance at which detection probability reaches 0.
const MAX_DETECT_RANGE_M  := 600.0


# -----------------------------------------------------------------------
# Primary API
# -----------------------------------------------------------------------

# Binary LOS + weighted detection check between one observer and one target.
#
# obs_perception    (0..1)  0 = oblivious, 1 = eagle-eyed
# target_concealment (0..1) 0 = fully exposed, 1 = perfectly hidden
# light_level       (0..1)  1 = full daylight, 0 = full dark
static func check_detection(
		heightmap: PackedFloat32Array,
		width: int, height: int,
		obs_x: int, obs_y: int,
		obs_perception: float,
		target_x: int, target_y: int,
		target_concealment: float,
		obs_height_offset: float = EYE_HEIGHT_STANDING,
		target_height_offset: float = EYE_HEIGHT_STANDING,
		light_level: float = 1.0,
		cell_size_m: float = 4.0) -> DetectionLevel:

	# Terrain LOS first — symmetric, cheap to reject.
	if not LineOfSight.check(heightmap, width, height,
			obs_x, obs_y, obs_height_offset,
			target_x, target_y, target_height_offset,
			cell_size_m):
		return DetectionLevel.NONE

	# Distance-based base detection probability.
	var dx := float(target_x - obs_x)
	var dy := float(target_y - obs_y)
	var dist_m := sqrt(dx * dx + dy * dy) * cell_size_m
	var base_detect := _distance_factor(dist_m)
	if base_detect <= 0.0:
		return DetectionLevel.NONE

	# Darkness boosts the target's effective concealment.
	var effective_concealment := clampf(
		target_concealment + (1.0 - light_level) * 0.4, 0.0, 1.0)

	# Score: base × perception boost × (1 - concealment).
	# Perception ranges from 0.5× (perception=0) to 1.0× (perception=1).
	var score := base_detect * (0.5 + obs_perception * 0.5) * (1.0 - effective_concealment)

	if score >= 0.55:
		return DetectionLevel.DETECTED
	elif score >= 0.20:
		return DetectionLevel.PARTIAL
	return DetectionLevel.NONE


# Sweep: check detection from one observer against a list of targets.
# Targets is Array of Dictionary: {"x", "y", "concealment", "height_offset"}.
# Returns Array[DetectionLevel] parallel to targets.
#
# Optimises by pre-computing the observer viewshed once and skipping
# any target not in it before doing the full distance/concealment math.
static func sweep(
		heightmap: PackedFloat32Array,
		width: int, height: int,
		obs_x: int, obs_y: int,
		obs_perception: float,
		targets: Array,
		obs_height_offset: float = EYE_HEIGHT_STANDING,
		light_level: float = 1.0,
		cell_size_m: float = 4.0) -> Array:

	var max_range_cells := int(MAX_DETECT_RANGE_M / cell_size_m)
	var vs := ViewshedSystem.compute(heightmap, width, height,
		obs_x, obs_y, obs_height_offset, max_range_cells, cell_size_m)

	var result: Array = []
	result.resize(targets.size())

	for i in targets.size():
		var t: Dictionary = targets[i]
		var tx: int = t.get("x", 0)
		var ty: int = t.get("y", 0)

		if tx < 0 or tx >= width or ty < 0 or ty >= height:
			result[i] = DetectionLevel.NONE
			continue

		# Fast-reject via viewshed mask before full detection calculation.
		if vs[ty * width + tx] == 0:
			result[i] = DetectionLevel.NONE
			continue

		result[i] = check_detection(
			heightmap, width, height,
			obs_x, obs_y, obs_perception,
			tx, ty,
			float(t.get("concealment", 0.0)),
			obs_height_offset,
			float(t.get("height_offset", EYE_HEIGHT_STANDING)),
			light_level,
			cell_size_m)

	return result


# -----------------------------------------------------------------------
# Concealment helpers — build the target_concealment float from context
# -----------------------------------------------------------------------

# Base concealment from biome index (terrain cover).
static func concealment_from_biome(biome_index: int) -> float:
	if biome_index < 0 or biome_index >= BIOME_CONCEALMENT.size():
		return 0.0
	return BIOME_CONCEALMENT[biome_index]


# Full entity concealment: biome cover + pace modifier + posture.
# stealth_bonus: entity-specific modifier from BehaviorProfile or equipment (0..0.5)
# pace_modifier:  from TravelCommand.get_pace_concealment_modifier()
# is_prone:       true if entity is lying down
static func entity_concealment(
		biome_index: int,
		stealth_bonus: float = 0.0,
		pace_modifier: float = 0.0,
		is_prone: bool = false) -> float:

	var base := concealment_from_biome(biome_index)
	var posture_bonus := 0.3 if is_prone else 0.0
	return clampf(base + stealth_bonus + pace_modifier + posture_bonus, 0.0, 1.0)


# -----------------------------------------------------------------------
# Internal
# -----------------------------------------------------------------------

static func _distance_factor(dist_m: float) -> float:
	if dist_m <= FULL_DETECT_RANGE_M:
		return 1.0
	if dist_m >= MAX_DETECT_RANGE_M:
		return 0.0
	return 1.0 - (dist_m - FULL_DETECT_RANGE_M) / (MAX_DETECT_RANGE_M - FULL_DETECT_RANGE_M)
