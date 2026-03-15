extends SceneTree

# Headless verification: builds a real chunk and inspects the ArrayMesh for
# vertex colors and the correct material.
# Run with:
#   godot --headless --path . --script debug/check_terrain_colors.gd

func _init() -> void:
	var exit_code := 0

	# --- Build a chunk via the real generator ---
	var manifest := WorldManifest.new()
	manifest.world_seed = 2147483647
	manifest.cell_size_local_m = 4.0
	manifest.chunk_cells_local = 16   # small for speed
	manifest.cell_size_regional_m = 100.0
	manifest.chunk_cells_regional = 16
	manifest.cell_size_planetary_m = 10000.0
	manifest.chunk_cells_planetary = 8

	var gen := TerrainGenerator.new()
	gen.setup(manifest)

	# Sample many chunks to see the full height/colour range
	print("=== Height survey across chunks 0..15 ===")
	var min_h := INF
	var max_h := -INF
	for cy in 16:
		for cx in 16:
			var c := gen.generate_chunk(0, cx, cy, ChunkData.LOD.LOCAL)
			for h in c.base_heightmap:
				if h < min_h: min_h = h
				if h > max_h: max_h = h
	print("  height range: %.0fm to %.0fm" % [min_h, max_h])

	var chunk := gen.generate_chunk(0, 8, 8, ChunkData.LOD.LOCAL)

	print("=== Chunk heights (first 5) ===")
	for i in mini(5, chunk.base_heightmap.size()):
		print("  h[%d] = %.1f m" % [i, chunk.base_heightmap[i]])

	# --- Build the mesh ---
	var mesh := TerrainChunkMesh.build(chunk)

	# --- Check surface count ---
	if mesh.get_surface_count() == 0:
		print("FAIL: ArrayMesh has 0 surfaces")
		quit(1)
		return
	print("OK: surface count = %d" % mesh.get_surface_count())

	# --- Check material ---
	var mat := mesh.surface_get_material(0)
	if mat == null:
		print("FAIL: surface 0 has no material")
		exit_code = 1
	elif not mat is StandardMaterial3D:
		print("FAIL: material is %s, expected StandardMaterial3D" % mat.get_class())
		exit_code = 1
	else:
		var sm := mat as StandardMaterial3D
		if sm.vertex_color_use_as_albedo:
			print("OK: StandardMaterial3D with vertex_color_use_as_albedo = true")
		else:
			print("FAIL: vertex_color_use_as_albedo is false")
			exit_code = 1

	# --- Check vertex colours ---
	var arrays := mesh.surface_get_arrays(0)
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	if colors.is_empty():
		print("FAIL: no vertex colour array in mesh")
		exit_code = 1
	else:
		print("OK: %d vertex colours present" % colors.size())
		# Sample a few and check they're not all identical grey.
		var sample_count := mini(10, colors.size())
		var unique: Dictionary = {}
		for i in sample_count:
			var c := colors[i]
			var key := "%.2f,%.2f,%.2f" % [c.r, c.g, c.b]
			unique[key] = c
			print("  color[%d] = (%.2f, %.2f, %.2f)" % [i, c.r, c.g, c.b])
		if unique.size() <= 1:
			print("WARN: all sampled vertex colours are identical — possible flat terrain")
		else:
			print("OK: %d distinct colours in sample" % unique.size())

	if exit_code == 0:
		print("\nPASS")
	else:
		print("\nFAIL")
	quit(exit_code)
