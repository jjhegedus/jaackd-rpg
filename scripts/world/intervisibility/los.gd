class_name LineOfSight
extends RefCounted

# Binary LOS check between two specific points on a heightmap.
# Used by encounter triggers, combat, and AI detection.
# Faster than a full viewshed when only a single pair is needed.
#
# For bulk checks (e.g. "can any of these enemies see the player?")
# use ViewshedSystem.compute() once and query the result mask instead.


# Returns true if target is visible from observer.
#
# obs_height_offset   — eye height above terrain (observer, e.g. 1.7m)
# target_height_offset — height above terrain at target point (e.g. 1.0m for crouched)
static func check(
		heightmap: PackedFloat32Array,
		width: int, height: int,
		obs_x: int, obs_y: int,
		obs_height_offset: float,
		target_x: int, target_y: int,
		target_height_offset: float = 0.0,
		cell_size_m: float = 4.0) -> bool:

	var obs_terrain_h := _sample(heightmap, width, height, obs_x, obs_y)
	var obs_h := obs_terrain_h + obs_height_offset

	var target_terrain_h := _sample(heightmap, width, height, target_x, target_y)
	var target_h := target_terrain_h + target_height_offset

	var dx := target_x - obs_x
	var dy := target_y - obs_y
	var steps := maxi(absi(dx), absi(dy))
	if steps == 0:
		return true

	var fdx := float(dx)
	var fdy := float(dy)
	var dist_to_target := sqrt(fdx * fdx + fdy * fdy) * cell_size_m
	if dist_to_target < 0.001:
		return true

	# Walk Bresenham line. For each intermediate cell, check if terrain
	# breaks the straight line from obs_h to target_h.
	for i in range(1, steps):
		var t := float(i) / float(steps)
		var cx := clampi(roundi(obs_x + fdx * t), 0, width - 1)
		var cy := clampi(roundi(obs_y + fdy * t), 0, height - 1)
		var cell_h := _sample(heightmap, width, height, cx, cy)
		# Height of the LOS line at this point
		var los_h := obs_h + (target_h - obs_h) * t
		if cell_h > los_h:
			return false

	return true


# Returns the first blocking cell along the ray, or Vector2i(-1, -1) if clear.
# Useful for determining what/where blocked the view.
static func first_blocker(
		heightmap: PackedFloat32Array,
		width: int, height: int,
		obs_x: int, obs_y: int,
		obs_height_offset: float,
		target_x: int, target_y: int,
		target_height_offset: float = 0.0) -> Vector2i:

	var obs_h := _sample(heightmap, width, height, obs_x, obs_y) + obs_height_offset
	var target_h := _sample(heightmap, width, height, target_x, target_y) + target_height_offset

	var dx := target_x - obs_x
	var dy := target_y - obs_y
	var steps := maxi(absi(dx), absi(dy))
	if steps == 0:
		return Vector2i(-1, -1)

	var fdx := float(dx)
	var fdy := float(dy)

	for i in range(1, steps):
		var t := float(i) / float(steps)
		var cx := clampi(roundi(obs_x + fdx * t), 0, width - 1)
		var cy := clampi(roundi(obs_y + fdy * t), 0, height - 1)
		var cell_h := _sample(heightmap, width, height, cx, cy)
		var los_h := obs_h + (target_h - obs_h) * t
		if cell_h > los_h:
			return Vector2i(cx, cy)

	return Vector2i(-1, -1)


static func _sample(
		heightmap: PackedFloat32Array,
		width: int, height: int,
		x: int, y: int) -> float:
	if x < 0 or x >= width or y < 0 or y >= height:
		return 0.0
	return heightmap[y * width + x]
