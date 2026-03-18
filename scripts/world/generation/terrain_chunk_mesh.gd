class_name TerrainChunkMesh
extends RefCounted

# Converts a ChunkData heightmap into an ArrayMesh for rendering.
#
# Uses an indexed vertex buffer so every grid-point corner is shared by all
# adjacent triangles. This lets generate_normals() average normals across
# cell boundaries → smooth shading, no visible grid lines.
#
# Vertex colours encode a smooth height-based gradient (sea-level-relative).

# Altitude stops for colour gradient (metres above sea level = 0)
const _STOPS: Array = [-200.0, 0.0, 4.0, 40.0, 1100.0, 2200.0, 3500.0]
const _COLORS: Array = [
	Color(0.04, 0.12, 0.55),  # deep ocean
	Color(0.10, 0.45, 0.85),  # shallow water
	Color(0.90, 0.82, 0.45),  # sand / coast
	Color(0.18, 0.72, 0.12),  # lowland grass
	Color(0.22, 0.58, 0.10),  # highland meadow (stays green to ~1100 m)
	Color(0.55, 0.38, 0.20),  # bare rock
	Color(0.95, 0.97, 1.00),  # snow / ice
]


static func build(chunk: ChunkData) -> ArrayMesh:
	var hmap := chunk.get_final_heightmap()
	var w    := chunk.cells_x
	var h    := chunk.cells_y
	var cs   := chunk.cell_size_m

	if hmap.is_empty() or w < 2 or h < 2:
		return ArrayMesh.new()

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# --- (w+1)×(h+1) vertices so the mesh spans the full chunk boundary ---
	# Interior uses the heightmap; edges use the boundary samples stored in the
	# chunk (which are the same values the adjacent chunk samples at its origin),
	# ensuring seamless height stitching across chunk borders.
	var has_edges := not chunk.edge_right.is_empty()
	for row in h + 1:
		for col in w + 1:
			var ht: float
			if row < h and col < w:
				ht = hmap[row * w + col]
			elif col == w and row < h:
				ht = chunk.edge_right[row] if has_edges else hmap[row * w + (w - 1)]
			elif row == h and col < w:
				ht = chunk.edge_bottom[col] if has_edges else hmap[(h - 1) * w + col]
			else:
				ht = chunk.edge_corner if has_edges else hmap[(h - 1) * w + (w - 1)]
			st.set_color(_height_color(ht))
			st.set_uv(Vector2(float(col) / w, float(row) / h))
			st.add_vertex(Vector3(col * cs, ht, row * cs))

	# --- w×h quads using (w+1)-wide vertex stride ---
	for row in range(h):
		for col in range(w):
			var i00 := row * (w + 1) + col
			var i10 := row * (w + 1) + col + 1
			var i01 := (row + 1) * (w + 1) + col
			var i11 := (row + 1) * (w + 1) + col + 1

			if (row + col) % 2 == 0:
				st.add_index(i00); st.add_index(i10); st.add_index(i01)
				st.add_index(i10); st.add_index(i11); st.add_index(i01)
			else:
				st.add_index(i00); st.add_index(i10); st.add_index(i11)
				st.add_index(i00); st.add_index(i11); st.add_index(i01)

	st.generate_normals()
	return st.commit()


# Smooth colour gradient — linearly interpolates between altitude stops.
static func _height_color(height_m: float) -> Color:
	if height_m <= _STOPS[0]:
		return _COLORS[0]
	for i in range(_STOPS.size() - 1):
		if height_m <= _STOPS[i + 1]:
			var t: float = (height_m - float(_STOPS[i])) / (float(_STOPS[i + 1]) - float(_STOPS[i]))
			return (_COLORS[i] as Color).lerp(_COLORS[i + 1] as Color, t)
	return _COLORS[_COLORS.size() - 1]
