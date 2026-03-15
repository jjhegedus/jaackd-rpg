class_name ViewshedSystem
extends RefCounted

# LOD-agnostic viewshed computation.
# Works at any resolution — pass in the appropriate heightmap and cell_size_m.
#
# Returns a PackedByteArray (length = width * height).
# Value 1 = visible from observer, 0 = not visible.
#
# Algorithm: radial elevation-angle sweep.
# For each target cell, march a Bresenham line from observer to target.
# Track the maximum elevation angle (slope) seen along the ray.
# Target is visible only if its slope from observer >= that maximum.
# This is the R2/R3 family of raster viewshed algorithms.


# Compute full viewshed from a single observer.
#
# obs_x, obs_y     — observer cell coordinates on the heightmap
# obs_height_offset — eye height above terrain surface (e.g. 1.7 for a person)
# max_range_cells  — maximum visibility radius in cells
# cell_size_m      — real-world size of one cell in metres (varies per LOD)
static func compute(
		heightmap: PackedFloat32Array,
		width: int, height: int,
		obs_x: int, obs_y: int,
		obs_height_offset: float,
		max_range_cells: int,
		cell_size_m: float = 4.0) -> PackedByteArray:

	var result := PackedByteArray()
	result.resize(width * height)
	result.fill(0)

	var obs_terrain_h := _sample(heightmap, width, height, obs_x, obs_y)
	var obs_h := obs_terrain_h + obs_height_offset

	# Observer's own cell is always visible.
	result[obs_y * width + obs_x] = 1

	var max_r2 := max_range_cells * max_range_cells
	var y_min := maxi(0, obs_y - max_range_cells)
	var y_max := mini(height - 1, obs_y + max_range_cells)
	var x_min := maxi(0, obs_x - max_range_cells)
	var x_max := mini(width - 1, obs_x + max_range_cells)

	for ty in range(y_min, y_max + 1):
		for tx in range(x_min, x_max + 1):
			if tx == obs_x and ty == obs_y:
				continue
			var dx := tx - obs_x
			var dy := ty - obs_y
			if dx * dx + dy * dy > max_r2:
				continue
			if _has_los(heightmap, width, height,
					obs_x, obs_y, obs_h, tx, ty, cell_size_m):
				result[ty * width + tx] = 1

	return result


# Merge multiple viewsheds (union) — used to combine all a player's characters.
static func merge(viewsheds: Array) -> PackedByteArray:
	if viewsheds.is_empty():
		return PackedByteArray()
	var result: PackedByteArray = viewsheds[0].duplicate()
	for i in range(1, viewsheds.size()):
		var other: PackedByteArray = viewsheds[i]
		var size := mini(result.size(), other.size())
		for j in size:
			if other[j]:
				result[j] = 1
	return result


# Cheap cone approximation for AI — no Bresenham, just elevation test
# against observer + range. Used before committing to a full LOS check.
static func cone_check(
		heightmap: PackedFloat32Array,
		width: int, height: int,
		obs_x: int, obs_y: int,
		obs_height_offset: float,
		target_x: int, target_y: int,
		cell_size_m: float = 4.0) -> bool:

	var obs_h := _sample(heightmap, width, height, obs_x, obs_y) + obs_height_offset
	var target_h := _sample(heightmap, width, height, target_x, target_y)
	var dx := float(target_x - obs_x)
	var dy := float(target_y - obs_y)
	var dist := sqrt(dx * dx + dy * dy) * cell_size_m
	if dist < 0.001:
		return true
	# Sample midpoint height — if midpoint terrain is above the LOS line, blocked.
	var mid_x := roundi(obs_x + dx * 0.5)
	var mid_y := roundi(obs_y + dy * 0.5)
	mid_x = clampi(mid_x, 0, width - 1)
	mid_y = clampi(mid_y, 0, height - 1)
	var mid_h := _sample(heightmap, width, height, mid_x, mid_y)
	var los_mid_h := obs_h + (target_h - obs_h) * 0.5
	return mid_h <= los_mid_h


# Returns the set of cells visible from observer as Array[Vector2i].
# Convenience wrapper around compute() for sparse use cases.
static func visible_cells(
		heightmap: PackedFloat32Array,
		width: int, height: int,
		obs_x: int, obs_y: int,
		obs_height_offset: float,
		max_range_cells: int,
		cell_size_m: float = 4.0) -> Array[Vector2i]:

	var mask := compute(heightmap, width, height,
		obs_x, obs_y, obs_height_offset, max_range_cells, cell_size_m)
	var cells: Array[Vector2i] = []
	for y in height:
		for x in width:
			if mask[y * width + x]:
				cells.append(Vector2i(x, y))
	return cells


# --- Internal ---

static func _has_los(
		heightmap: PackedFloat32Array,
		width: int, height: int,
		ox: int, oy: int, obs_h: float,
		tx: int, ty: int,
		cell_size_m: float) -> bool:

	var dx := tx - ox
	var dy := ty - oy
	var steps := maxi(absi(dx), absi(dy))
	if steps == 0:
		return true

	var fdx := float(dx)
	var fdy := float(dy)
	var dist_to_target := sqrt(fdx * fdx + fdy * fdy) * cell_size_m
	var target_h := _sample(heightmap, width, height, tx, ty)
	var target_slope := (target_h - obs_h) / dist_to_target

	var max_slope := -1e30

	for i in range(1, steps):
		var t := float(i) / float(steps)
		var cx := clampi(roundi(ox + fdx * t), 0, width - 1)
		var cy := clampi(roundi(oy + fdy * t), 0, height - 1)
		var cell_h := _sample(heightmap, width, height, cx, cy)
		var cdx := float(cx - ox)
		var cdy := float(cy - oy)
		var dist := sqrt(cdx * cdx + cdy * cdy) * cell_size_m
		if dist > 0.0:
			var slope := (cell_h - obs_h) / dist
			if slope > max_slope:
				max_slope = slope

	return target_slope >= max_slope


static func _sample(
		heightmap: PackedFloat32Array,
		width: int, height: int,
		x: int, y: int) -> float:
	if x < 0 or x >= width or y < 0 or y >= height:
		return 0.0
	return heightmap[y * width + x]
