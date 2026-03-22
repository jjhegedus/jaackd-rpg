class_name LODManager
extends RefCounted

# Drives chunk generation priority using intervisibility.
#
# At each LOD level the viewshed of the player (or any observer) determines
# which chunks at the next finer LOD level need to exist. This means:
#   Planetary viewshed  → which Regional chunks to load/generate
#   Regional viewshed   → which Local chunks to load/generate
#
# This is what makes distant landmarks (mountains, towns in valleys) exist
# visually before the player reaches them — they're within the planetary
# viewshed, so their regional data is generated as soon as the player can see them.

signal chunk_priority_updated(jobs: Array)  # Array of {face, cx, cy, lod}

# Viewshed parameters per LOD
const PLANETARY_OBS_OFFSET := 2.0   # metres above terrain for planetary survey
const REGIONAL_OBS_OFFSET  := 1.8   # typical standing height
const LOCAL_OBS_OFFSET     := 1.7

# Max viewshed range in cells at each LOD.
# Planetary at 10km/cell: 50 cells = 500 km view (planet-spanning ridge visibility)
# Regional at 100m/cell:  150 cells = 15 km
# Local at 4m/cell:       200 cells = 800 m
const PLANETARY_MAX_RANGE := 50
const REGIONAL_MAX_RANGE  := 25
const LOCAL_MAX_RANGE     := 200

# Cell sizes in metres
const PLANETARY_CELL_M := 10000.0
const REGIONAL_CELL_M  := 100.0
const LOCAL_CELL_M     := 4.0


func update(
		face: int,
		obs_chunk_x: int, obs_chunk_y: int,   # LOCAL chunk coords
		obs_cell_x: int, obs_cell_y: int,      # LOCAL cell within chunk
		world_manager: Node) -> void:

	if not world_manager.has_method("get_chunk"):
		return
	var manifest := world_manager._manifest as WorldManifest
	if manifest == null:
		return

	var local_cell_m     : float = manifest.cell_size_local_m
	var local_chunk_m    : float = float(manifest.chunk_cells_local) * local_cell_m
	var regional_cell_m  : float = manifest.cell_size_regional_m
	var regional_chunk_m : float = float(manifest.chunk_cells_regional) * regional_cell_m

	# Player world position from local chunk + cell coords.
	var world_x := obs_chunk_x * local_chunk_m + obs_cell_x * local_cell_m
	var world_z := obs_chunk_y * local_chunk_m + obs_cell_y * local_cell_m

	var jobs: Array = []

	# --- Step 1: Planetary viewshed → queue visible Regional chunks ---
	# (Planetary LOD not yet implemented — skip.)

	# --- Step 2: Regional viewshed → queue visible Local chunks ---
	# Find the regional chunk that contains the player.
	var reg_cx := floori(world_x / regional_chunk_m)
	var reg_cy := floori(world_z / regional_chunk_m)

	# Player's observer cell within that regional chunk.
	var reg_obs_x := clampi(
		floori((world_x - reg_cx * regional_chunk_m) / regional_cell_m),
		0, manifest.chunk_cells_regional - 1)
	var reg_obs_z := clampi(
		floori((world_z - reg_cy * regional_chunk_m) / regional_cell_m),
		0, manifest.chunk_cells_regional - 1)

	var regional: ChunkData = world_manager.get_chunk(
		face, reg_cx, reg_cy, ChunkData.LOD.REGIONAL)

	if regional and not regional.base_heightmap.is_empty():
		var vis_mask := ViewshedSystem.compute(
			regional.base_heightmap,
			regional.cells_x, regional.cells_y,
			reg_obs_x, reg_obs_z,
			REGIONAL_OBS_OFFSET,
			REGIONAL_MAX_RANGE,
			REGIONAL_CELL_M
		)
		_enqueue_visible_chunks(
			vis_mask, regional.cells_x, regional.cells_y,
			face,
			reg_cx, reg_cy,
			regional_cell_m,
			local_chunk_m,
			ChunkData.LOD.LOCAL,
			world_manager, jobs
		)

	if not jobs.is_empty():
		chunk_priority_updated.emit(jobs)


# Scan a visibility mask and queue chunks that are visible but not yet loaded.
# Converts source-grid cell coordinates to target-chunk coordinates via world space,
# so different LOD cell sizes and chunk sizes are handled correctly.
func _enqueue_visible_chunks(
		vis_mask: PackedByteArray,
		mask_w: int, mask_h: int,
		face: int,
		source_cx: int, source_cy: int,
		source_cell_size_m: float,
		target_chunk_size_m: float,
		target_lod: ChunkData.LOD,
		world_manager: Node,
		jobs: Array) -> void:

	# World-space origin of the source chunk.
	var source_chunk_w_m := float(mask_w) * source_cell_size_m
	var source_chunk_h_m := float(mask_h) * source_cell_size_m
	var origin_x := source_cx * source_chunk_w_m
	var origin_z := source_cy * source_chunk_h_m

	var seen: Dictionary = {}
	for y in mask_h:
		for x in mask_w:
			if vis_mask[y * mask_w + x] == 0:
				continue
			# Centre of this source cell in world space.
			var wx := origin_x + (x + 0.5) * source_cell_size_m
			var wz := origin_z + (y + 0.5) * source_cell_size_m
			# Which target chunk contains this world position?
			var tcx := floori(wx / target_chunk_size_m)
			var tcy := floori(wz / target_chunk_size_m)
			var key := "%d_%d" % [tcx, tcy]
			if seen.has(key):
				continue
			seen[key] = true
			if not world_manager.is_chunk_loaded(face, tcx, tcy, target_lod):
				jobs.append({face = face, cx = tcx, cy = tcy, lod = target_lod})


# Compute the local-LOD viewshed for a character (used for fog of war + encounters).
# Returns a PackedByteArray mask for the character's current local chunk.
func compute_local_viewshed(
		face: int, chunk_x: int, chunk_y: int,
		cell_x: int, cell_y: int,
		world_manager: Node,
		obs_height_offset: float = LOCAL_OBS_OFFSET) -> PackedByteArray:

	var local_chunk: ChunkData = world_manager.get_chunk(
		face, chunk_x, chunk_y, ChunkData.LOD.LOCAL)

	if local_chunk == null or local_chunk.base_heightmap.is_empty():
		return PackedByteArray()

	return ViewshedSystem.compute(
		local_chunk.get_final_heightmap(),
		local_chunk.cells_x, local_chunk.cells_y,
		cell_x, cell_y,
		obs_height_offset,
		LOCAL_MAX_RANGE,
		LOCAL_CELL_M
	)
