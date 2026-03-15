class_name TerrainChunkNode
extends Node3D

# Scene node that owns one ChunkData and its rendered mesh.
# Attach this script to a Node3D that has a MeshInstance3D child named "Mesh"
# and a StaticBody3D > CollisionShape3D child named "Body/Shape" for physics.
#
# WorldManager creates and destroys these nodes as chunks load/unload.

signal mesh_built(chunk: ChunkData)

@onready var mesh_instance: MeshInstance3D   = $Mesh
@onready var collision_body: StaticBody3D    = $Body
@onready var collision_shape: CollisionShape3D = $Body/Shape

var chunk_data: ChunkData


func load_chunk(data: ChunkData) -> void:
	chunk_data = data
	_rebuild_mesh()


func rebuild() -> void:
	if chunk_data:
		_rebuild_mesh()


# Called when terrain is edited (foundation flattening, sculpting).
func on_chunk_modified() -> void:
	_rebuild_mesh()


# --- Internal ---

func _rebuild_mesh() -> void:
	if chunk_data == null:
		return

	var array_mesh := TerrainChunkMesh.build(chunk_data)
	mesh_instance.mesh = array_mesh
	# Custom shader reads vertex COLOR directly — bypasses any StandardMaterial3D quirks.
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode cull_disabled;

void fragment() {
	ALBEDO    = COLOR.rgb;
	ROUGHNESS = 0.9;
	METALLIC  = 0.0;
	// Keep back-face normal pointing in the same direction as the front face
	// so tilted-camera views of distant terrain light correctly.
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mesh_instance.set_surface_override_material(0, mat)

	# Rebuild trimesh collision shape from the same mesh.
	var shape := array_mesh.create_trimesh_shape()
	collision_shape.shape = shape

	# Position this node at the chunk's world origin.
	# Chunk (cx, cy) on face f starts at (cx * chunk_width_m, 0, cy * chunk_height_m).
	var w_m := chunk_data.cells_x * chunk_data.cell_size_m
	var h_m := chunk_data.cells_y * chunk_data.cell_size_m
	position = Vector3(
		chunk_data.chunk_x * w_m,
		0.0,
		chunk_data.chunk_y * h_m
	)

	mesh_built.emit(chunk_data)
