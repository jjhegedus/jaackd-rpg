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
const REGIONAL_MAX_RANGE  := 150
const LOCAL_MAX_RANGE     := 200

# Cell sizes in metres
const PLANETARY_CELL_M := 10000.0
const REGIONAL_CELL_M  := 100.0
const LOCAL_CELL_M     := 4.0


func update(
		face: int,
		obs_chunk_x: int, obs_chunk_y: int,
		obs_cell_x: int, obs_cell_y: int,
		world_manager: Node) -> void:

	if not world_manager.has_method("get_chunk"):
		return

	var jobs: Array = []

	# --- Step 1: Planetary viewshed → queue visible Regional chunks ---
	var planetary: ChunkData = world_manager.get_chunk(
		face, obs_chunk_x, obs_chunk_y, ChunkData.LOD.PLANETARY)

	if planetary and not planetary.base_heightmap.is_empty():
		var vis_mask := ViewshedSystem.compute(
			planetary.base_heightmap,
			planetary.cells_x, planetary.cells_y,
			obs_cell_x, obs_cell_y,
			PLANETARY_OBS_OFFSET,
			PLANETARY_MAX_RANGE,
			PLANETARY_CELL_M
		)
		_enqueue_visible_chunks(
			vis_mask, planetary.cells_x, planetary.cells_y,
			face, obs_chunk_x, obs_chunk_y,
			ChunkData.LOD.REGIONAL,
			world_manager, jobs
		)

	# --- Step 2: Regional viewshed → queue visible Local chunks ---
	# Run for each already-loaded regional chunk in the vicinity.
	var regional: ChunkData = world_manager.get_chunk(
		face, obs_chunk_x, obs_chunk_y, ChunkData.LOD.REGIONAL)

	if regional and not regional.base_heightmap.is_empty():
		var vis_mask := ViewshedSystem.compute(
			regional.base_heightmap,
			regional.cells_x, regional.cells_y,
			obs_cell_x, obs_cell_y,
			REGIONAL_OBS_OFFSET,
			REGIONAL_MAX_RANGE,
			REGIONAL_CELL_M
		)
		_enqueue_visible_chunks(
			vis_mask, regional.cells_x, regional.cells_y,
			face, obs_chunk_x, obs_chunk_y,
			ChunkData.LOD.LOCAL,
			world_manager, jobs
		)

	if not jobs.is_empty():
		chunk_priority_updated.emit(jobs)


# Scan a visibility mask and queue any chunks that are visible but not yet loaded.
func _enqueue_visible_chunks(
		vis_mask: PackedByteArray,
		mask_w: int, mask_h: int,
		face: int, base_cx: int, base_cy: int,
		target_lod: ChunkData.LOD,
		world_manager: Node,
		jobs: Array) -> void:

	for y in mask_h:
		for x in mask_w:
			if vis_mask[y * mask_w + x] == 0:
				continue
			# Convert mask cell offset to chunk coordinates.
			# Each cell in the coarser LOD corresponds to one chunk in the finer LOD.
			var tcx := base_cx + (x - mask_w / 2)
			var tcy := base_cy + (y - mask_h / 2)
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
