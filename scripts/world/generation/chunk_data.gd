class_name ChunkData
extends Resource

enum LOD { PLANETARY, REGIONAL, LOCAL }

# --- Addressing ---
@export var lod: LOD = LOD.LOCAL
@export var face: int = 0       # cube-sphere face 0–5
@export var chunk_x: int = 0
@export var chunk_y: int = 0
@export var world_seed: int = 0

# --- Dimensions ---
# Cell counts per axis (set at generation time based on LOD)
@export var cells_x: int = 64
@export var cells_y: int = 64
@export var cell_size_m: float = 4.0   # meters per cell edge

# --- Terrain data ---
# Flat row-major arrays: index = y * cells_x + x
@export var base_heightmap: PackedFloat32Array = PackedFloat32Array()
@export var sediment_map: PackedFloat32Array = PackedFloat32Array()

# One-cell-wide boundary samples for seamless chunk stitching.
# edge_right[row]  = height at (cells_x, row)   — right border column (cells_y values)
# edge_bottom[col] = height at (col, cells_y)    — bottom border row   (cells_x values)
# edge_corner      = height at (cells_x, cells_y)
@export var edge_right: PackedFloat32Array = PackedFloat32Array()
@export var edge_bottom: PackedFloat32Array = PackedFloat32Array()
@export var edge_corner: float = 0.0

# Per-cell biome index (index into biome table)
@export var biome_map: PackedByteArray = PackedByteArray()

# --- Player modifications ---
# Bit flags per cell: bit 0 = modified, bit 1 = foundation/hardened
@export var modification_mask: PackedByteArray = PackedByteArray()
# Non-zero only where modification_mask bit 0 is set
@export var modified_heightmap: PackedFloat32Array = PackedFloat32Array()

# --- State ---
@export var generated: bool = false
@export var dirty: bool = false  # true = needs to be written to disk


func _init() -> void:
	pass


func initialize(p_cells_x: int, p_cells_y: int, p_cell_size_m: float) -> void:
	cells_x = p_cells_x
	cells_y = p_cells_y
	cell_size_m = p_cell_size_m
	var count := cells_x * cells_y
	base_heightmap.resize(count)
	base_heightmap.fill(0.0)
	sediment_map.resize(count)
	sediment_map.fill(0.0)
	biome_map.resize(count)
	biome_map.fill(0)
	modification_mask.resize(count)
	modification_mask.fill(0)
	modified_heightmap.resize(count)
	modified_heightmap.fill(0.0)
	edge_right.resize(cells_y)
	edge_right.fill(0.0)
	edge_bottom.resize(cells_x)
	edge_bottom.fill(0.0)
	edge_corner = 0.0


func get_height(x: int, y: int) -> float:
	var idx := y * cells_x + x
	if modification_mask[idx] & 1:
		return modified_heightmap[idx]
	return base_heightmap[idx]


func set_modified_height(x: int, y: int, height: float) -> void:
	var idx := y * cells_x + x
	modified_heightmap[idx] = height
	modification_mask[idx] |= 1
	dirty = true


func set_foundation(x: int, y: int, height: float) -> void:
	var idx := y * cells_x + x
	modified_heightmap[idx] = height
	modification_mask[idx] |= 3  # both modified + foundation bits
	dirty = true


func is_foundation(x: int, y: int) -> bool:
	return (modification_mask[y * cells_x + x] & 2) != 0


func revert(x: int, y: int) -> void:
	var idx := y * cells_x + x
	modification_mask[idx] = 0
	modified_heightmap[idx] = 0.0
	dirty = true


func get_final_heightmap() -> PackedFloat32Array:
	# Returns base heightmap merged with any player modifications.
	if modification_mask.is_empty():
		return base_heightmap
	var result := base_heightmap.duplicate()
	for i in result.size():
		if modification_mask[i] & 1:
			result[i] = modified_heightmap[i]
	return result


func get_world_size() -> Vector2:
	return Vector2(cells_x * cell_size_m, cells_y * cell_size_m)
