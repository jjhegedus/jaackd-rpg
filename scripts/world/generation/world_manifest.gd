class_name WorldManifest
extends Resource

const CURRENT_VERSION := 1
const CURRENT_FORGE_VERSION := 2  # v2: ChunkData edge_right/edge_bottom/edge_corner for seamless chunk stitching

# --- Identity ---
@export var world_name: String = ""
@export var world_seed: int = 0
@export var version: int = CURRENT_VERSION
@export var forge_version: int = 0   # 0 = pre-versioning (outdated)
@export var created_at: int = 0   # Unix timestamp

# --- Planet ---
@export var planet_radius_km: float = 1000.0

# --- LOD config ---
# Cell sizes in meters for each LOD level
@export var cell_size_planetary_m: float = 10000.0  # 10 km
@export var cell_size_regional_m: float = 100.0
@export var cell_size_local_m: float = 4.0

# Cells per chunk side at each LOD
@export var chunk_cells_planetary: int = 32
@export var chunk_cells_regional: int = 64
@export var chunk_cells_local: int = 64

# --- Starting point ---
# Cube-sphere face + cell address of the starting town
@export var start_face: int = 0
@export var start_chunk_x: int = 0
@export var start_chunk_y: int = 0
@export var start_local_pos: Vector3 = Vector3.ZERO

# How far from start was pre-baked at world forge time (in chunks, regional LOD)
@export var prebaked_regional_radius: int = 0
@export var prebaked_local_radius: int = 0

# --- Town ---
@export var starting_town_name: String = ""
@export var characters: Array[Character] = []

# --- Validity ---
# A world is only "ready to play" once World Forge has completed generation
@export var is_valid: bool = false


func save(path: String) -> Error:
	return ResourceSaver.save(self, path)


static func load_from(path: String) -> WorldManifest:
	if not ResourceLoader.exists(path):
		return null
	return ResourceLoader.load(path) as WorldManifest


func get_save_path() -> String:
	return DiskManager.manifest_path(world_name)
