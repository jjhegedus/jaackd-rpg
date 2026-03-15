class_name CoordConverter
extends RefCounted

# Cube-sphere: 6 faces indexed 0-5
# Face layout (cube net):
#   Face 0: +Y (top)
#   Face 1: -Y (bottom)
#   Face 2: +X (right)
#   Face 3: -X (left)
#   Face 4: +Z (front)
#   Face 5: -Z (back)

# Each face is a square grid of (face_cells x face_cells) cells.
# face_cells = ceil(planet_circumference / cell_size)

const FACE_COUNT := 6

var planet_radius_m: float
var cell_size_m: float
var face_cells: int          # cells per face side
var chunk_cells: int         # cells per chunk side


func _init(p_radius_km: float, p_cell_size_m: float, p_chunk_cells: int) -> void:
	planet_radius_m = p_radius_km * 1000.0
	cell_size_m = p_cell_size_m
	chunk_cells = p_chunk_cells
	var circumference := 2.0 * PI * planet_radius_m
	face_cells = int(ceil(circumference / (4.0 * cell_size_m)))


# --- Global cell address ---
class GlobalCell:
	var face: int
	var cx: int   # cell x within face
	var cy: int   # cell y within face

	func _init(f: int, x: int, y: int) -> void:
		face = f; cx = x; cy = y

	func to_chunk(chunk_cells_per_side: int) -> GlobalChunk:
		return GlobalChunk.new(face, cx / chunk_cells_per_side, cy / chunk_cells_per_side)


# --- Global chunk address ---
class GlobalChunk:
	var face: int
	var cx: int   # chunk x within face
	var cy: int   # chunk y within face

	func _init(f: int, x: int, y: int) -> void:
		face = f; cx = x; cy = y

	func save_key() -> String:
		return "f%d_%d_%d" % [face, cx, cy]

	func equals(other: GlobalChunk) -> bool:
		return face == other.face and cx == other.cx and cy == other.cy


# Convert a GlobalChunk + local 2D cell offset to a 3D sphere-surface position.
# local_x, local_z: cell indices within the chunk (0..chunk_cells-1)
# Returns a Vector3 on the sphere surface (flat-local approximation near chunk center).
func chunk_local_to_world_pos(chunk: GlobalChunk, local_x: int, local_z: int) -> Vector3:
	# For now: flat local approximation.
	# Origin of the chunk maps to a sphere surface point; local offsets are flat.
	var origin := chunk_center_world(chunk)
	return origin + Vector3(local_x * cell_size_m, 0.0, local_z * cell_size_m)


# Returns the approximate world-space center of a chunk (flat local, Y=0 is sea level).
func chunk_center_world(chunk: GlobalChunk) -> Vector3:
	# Normalize face coords to [-1, 1]
	var u := (chunk.cx * chunk_cells + chunk_cells * 0.5) / face_cells * 2.0 - 1.0
	var v := (chunk.cy * chunk_cells + chunk_cells * 0.5) / face_cells * 2.0 - 1.0
	var cube_pt := _face_uv_to_cube(chunk.face, u, v)
	var sphere_pt := cube_pt.normalized() * planet_radius_m
	return sphere_pt


# World position (on flat-local terrain) → nearest GlobalChunk at this LOD.
# Assumes the world is rendered in a local flat patch centered near start_world_pos.
func world_pos_to_chunk(world_pos: Vector3, origin_chunk: GlobalChunk) -> GlobalChunk:
	# Offset from origin chunk center
	var origin_center := chunk_center_world(origin_chunk)
	var delta := world_pos - origin_center
	var chunk_size_m := chunk_cells * cell_size_m
	var dx := int(floor(delta.x / chunk_size_m))
	var dz := int(floor(delta.z / chunk_size_m))
	# Wrap within face (simple; edge wrapping handled later)
	var chunks_per_face := face_cells / chunk_cells
	var new_cx := clampi(origin_chunk.cx + dx, 0, chunks_per_face - 1)
	var new_cy := clampi(origin_chunk.cy + dz, 0, chunks_per_face - 1)
	return GlobalChunk.new(origin_chunk.face, new_cx, new_cy)


func _face_uv_to_cube(face: int, u: float, v: float) -> Vector3:
	match face:
		0: return Vector3(u, 1.0, v)   # +Y top
		1: return Vector3(u, -1.0, v)  # -Y bottom
		2: return Vector3(1.0, v, u)   # +X right
		3: return Vector3(-1.0, v, u)  # -X left
		4: return Vector3(u, v, 1.0)   # +Z front
		5: return Vector3(u, v, -1.0)  # -Z back
	return Vector3.ZERO
