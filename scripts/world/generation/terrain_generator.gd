class_name TerrainGenerator
extends RefCounted

signal chunk_generated(chunk: ChunkData)
signal progress_updated(fraction: float, status: String)

var _manifest: WorldManifest
var _sampler: NoiseSampler
var _coord: CoordConverter


func setup(manifest: WorldManifest) -> void:
	_manifest = manifest
	_sampler = NoiseSampler.new()
	_sampler.setup(manifest.world_seed)
	_coord = CoordConverter.new(
		manifest.planet_radius_km,
		manifest.cell_size_local_m,
		manifest.chunk_cells_local
	)


# Generate a single chunk at the given LOD and address.
# This is deterministic — same inputs always produce the same output.
func generate_chunk(face: int, chunk_x: int, chunk_y: int, lod: ChunkData.LOD) -> ChunkData:
	var chunk := ChunkData.new()
	chunk.face = face
	chunk.chunk_x = chunk_x
	chunk.chunk_y = chunk_y
	chunk.lod = lod
	chunk.world_seed = _manifest.world_seed

	var cell_size: float
	var chunk_cells: int
	match lod:
		ChunkData.LOD.PLANETARY:
			cell_size = _manifest.cell_size_planetary_m
			chunk_cells = _manifest.chunk_cells_planetary
		ChunkData.LOD.REGIONAL:
			cell_size = _manifest.cell_size_regional_m
			chunk_cells = _manifest.chunk_cells_regional
		ChunkData.LOD.LOCAL:
			cell_size = _manifest.cell_size_local_m
			chunk_cells = _manifest.chunk_cells_local

	chunk.initialize(chunk_cells, chunk_cells, cell_size)

	# World-space origin of this chunk (top-left cell corner)
	var chunk_world_size := chunk_cells * cell_size
	# Simple flat projection: face origin in meters
	var face_origin_x := chunk_x * chunk_world_size
	var face_origin_z := chunk_y * chunk_world_size

	for cy in chunk_cells:
		for cx in chunk_cells:
			var wx := face_origin_x + cx * cell_size
			var wz := face_origin_z + cy * cell_size
			chunk.base_heightmap[cy * chunk_cells + cx] = _sampler.get_height(wx, wz)
			chunk.biome_map[cy * chunk_cells + cx] = _classify_biome(wx, wz)

	# Boundary samples — one extra column to the right and one extra row below.
	# These match the adjacent chunk's first row/column exactly (deterministic noise),
	# so chunk meshes stitch together without seams.
	var wx_right := face_origin_x + chunk_cells * cell_size
	var wz_bottom := face_origin_z + chunk_cells * cell_size
	for cy in chunk_cells:
		chunk.edge_right[cy] = _sampler.get_height(wx_right, face_origin_z + cy * cell_size)
	for cx in chunk_cells:
		chunk.edge_bottom[cx] = _sampler.get_height(face_origin_x + cx * cell_size, wz_bottom)
	chunk.edge_corner = _sampler.get_height(wx_right, wz_bottom)

	chunk.generated = true
	chunk_generated.emit(chunk)
	return chunk


# Generate the full planetary LOD (all 6 faces).
# Emits progress_updated periodically. Intended to run on a background thread.
func generate_planetary_lod() -> Array[ChunkData]:
	var results: Array[ChunkData] = []
	# Compute chunk count from planetary cell size — NOT the local-LOD coord converter.
	# 1000km radius → circumference ~6,283km → ~157 cells at 10km/cell → ~4 chunks/side.
	var circumference := 2.0 * PI * _manifest.planet_radius_km * 1000.0
	var face_cells_planetary := int(ceil(circumference / (4.0 * _manifest.cell_size_planetary_m)))
	var chunks_per_face_side := maxi(1, face_cells_planetary / _manifest.chunk_cells_planetary)
	var done := 0
	var face_total := 6 * chunks_per_face_side * chunks_per_face_side

	for face in 6:
		for cy in chunks_per_face_side:
			for cx in chunks_per_face_side:
				results.append(generate_chunk(face, cx, cy, ChunkData.LOD.PLANETARY))
				done += 1
				if done % 10 == 0:
					progress_updated.emit(
						float(done) / float(face_total),
						"Generating planetary terrain… %d%%" % int(100.0 * done / face_total)
					)

	progress_updated.emit(1.0, "Planetary terrain complete.")
	return results


# Classify a biome index from world position.
# Returns a byte index into the biome table.
func _classify_biome(wx: float, wz: float) -> int:
	var elevation := _sampler.get_height(wx, wz)  # sea-relative: 0 = sea level
	var moisture := _sampler.get_moisture(wx, wz)
	# Reconstruct [0..1] normalised range for threshold comparisons.
	var elev_norm := (elevation + _sampler.get_sea_level_m()) / _sampler.max_height_m

	if elevation < 0.0:
		return 0  # Ocean

	if elev_norm > 0.80:
		return 5  # Alpine / Snow

	if elev_norm > 0.60:
		return 4  # Mountain

	if moisture > 0.65:
		if elev_norm > 0.35:
			return 3  # Temperate Forest
		else:
			return 2  # Swamp / Wetland

	if moisture < 0.30:
		return 6  # Desert / Arid

	return 1  # Grassland / Plains
