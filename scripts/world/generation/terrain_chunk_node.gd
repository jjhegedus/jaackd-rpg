class_name TerrainChunkNode
extends Node3D

# Scene node that owns one ChunkData and its rendered mesh.
# Attach this script to a Node3D that has a MeshInstance3D child named "Mesh"
# and a StaticBody3D > CollisionShape3D child named "Body/Shape" for physics.
#
# Fog of war is applied directly to the terrain shader via a per-chunk R8 texture
# (fog_texture uniform). One byte per cell encodes visibility:
#   0   → currently visible (terrain at full brightness)
#   140 → explored but not currently visible (terrain darkened ~55%)
#   255 → never explored (terrain rendered black)
#
# This avoids a separate overlay mesh, so fog never interferes with objects
# placed on the terrain surface (buildings, vegetation, entities).
# Note: fog does NOT automatically apply to those objects — they will need
# their own fog handling when added.

signal mesh_built(chunk: ChunkData)

@onready var mesh_instance: MeshInstance3D   = $Mesh
@onready var collision_body: StaticBody3D    = $Body
@onready var collision_shape: CollisionShape3D = $Body/Shape

var chunk_data: ChunkData
var _material: ShaderMaterial
var _fog_texture: ImageTexture


func load_chunk(data: ChunkData) -> void:
	chunk_data = data
	_rebuild_mesh()


func rebuild() -> void:
	if chunk_data:
		_rebuild_mesh()


func on_chunk_modified() -> void:
	_rebuild_mesh()


# Update fog of war from explored / visible cell masks.
# Both are PackedByteArrays of size cells_x * cells_y (row-major).
func update_fog(explored: PackedByteArray, visible: PackedByteArray) -> void:
	if chunk_data == null or _material == null:
		return

	var w    := chunk_data.cells_x
	var h    := chunk_data.cells_y
	var size := w * h

	var data := PackedByteArray()
	data.resize(size)
	for idx in size:
		var is_vis := idx < visible.size()  and visible[idx]  != 0
		var is_exp := idx < explored.size() and explored[idx] != 0
		if is_vis:
			data[idx] = 0
		elif is_exp:
			data[idx] = 140   # round(0.55 * 255)
		else:
			data[idx] = 255

	var img := Image.create_from_data(w, h, false, Image.FORMAT_R8, data)
	if _fog_texture == null:
		_fog_texture = ImageTexture.create_from_image(img)
	else:
		_fog_texture.update(img)
	_material.set_shader_parameter("fog_texture", _fog_texture)


# --- Internal ---

func _rebuild_mesh() -> void:
	if chunk_data == null:
		return

	var array_mesh := TerrainChunkMesh.build(chunk_data)
	mesh_instance.mesh = array_mesh

	if _material == null:
		_material = _make_terrain_material()
	mesh_instance.set_surface_override_material(0, _material)

	var shape := array_mesh.create_trimesh_shape()
	collision_shape.shape = shape

	var w_m := chunk_data.cells_x * chunk_data.cell_size_m
	var h_m := chunk_data.cells_y * chunk_data.cell_size_m
	position = Vector3(
		chunk_data.chunk_x * w_m,
		0.0,
		chunk_data.chunk_y * h_m
	)

	mesh_built.emit(chunk_data)


func _make_terrain_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode cull_disabled;

// R8 texture: 0.0 = visible, ~0.55 = explored/hidden, 1.0 = unexplored black.
// hint_default_black means fog_strength = 0 (no fog) until the texture is set.
uniform sampler2D fog_texture : source_color, hint_default_black, filter_linear;

void fragment() {
	float fog_strength = texture(fog_texture, UV).r;
	ALBEDO    = mix(COLOR.rgb, vec3(0.0), fog_strength);
	ROUGHNESS = 0.9;
	METALLIC  = 0.0;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	return mat
