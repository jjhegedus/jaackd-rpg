class_name FogOfWarManager
extends Node

# Manages per-chunk fog of war state for both LOCAL and REGIONAL LODs.
#
# Explored mask  — cells ever seen by any player entity. Saved to disk.
# Visible mask   — cells visible in the most recent viewshed. Runtime only.
#
# Viewshed computation runs on a background Thread. Each run computes both
# the local viewshed (4 m/cell, 3×3 composite) and the regional viewshed
# (100 m/cell, 3×3 composite) in one pass so we only need one thread.

signal chunk_fog_updated(chunk_key: String)
signal regional_chunk_fog_updated(chunk_key: String)

const VISIBILITY_RANGE_M := 400.0  # world metres — identical range for both LODs
const EYE_HEIGHT         := 1.7
const MOVE_THRESHOLD_CELLS      := 1
const COMPOSITE_CHUNK_RADIUS    := 1     # 1 → 3×3 grid

# --- Local fog ---
var _explored: Dictionary = {}   # chunk_key → PackedByteArray (0/1 per cell)
var _visible:  Dictionary = {}   # chunk_key → PackedByteArray (runtime only)

# --- Regional fog ---
var _regional_explored: Dictionary = {}
var _regional_visible:  Dictionary = {}

var _last_cell: Dictionary = {}  # entity_id → Vector2i (local cell)

var _thread: Thread
var _mutex:  Mutex
var _pending: Dictionary = {}

var _world_name: String = ""


func _init() -> void:
	_thread = Thread.new()
	_mutex  = Mutex.new()


# -----------------------------------------------------------------------
# Frame loop
# -----------------------------------------------------------------------

func _process(_delta: float) -> void:
	if not _thread.is_started():
		return
	if _thread.is_alive():
		return
	_thread.wait_to_finish()
	_mutex.lock()
	var result := _pending.duplicate()
	_pending.clear()
	_mutex.unlock()
	if result.is_empty():
		return
	var t0 := Time.get_ticks_usec()
	_apply_result(result)
	var t_apply_local_us := Time.get_ticks_usec() - t0

	t0 = Time.get_ticks_usec()
	_apply_regional_result(result)
	var t_apply_regional_us := Time.get_ticks_usec() - t0

	print("[FOG] build_local=%dms  build_regional=%dms  viewshed_local=%dms  viewshed_regional=%dms  apply_local=%dms  apply_regional=%dms" % [
		result.get("t_build_local_us",    0) / 1000,
		result.get("t_build_regional_us", 0) / 1000,
		result.get("t_viewshed_local_us", 0) / 1000,
		result.get("t_viewshed_regional_us", 0) / 1000,
		t_apply_local_us / 1000,
		t_apply_regional_us / 1000,
	])


# -----------------------------------------------------------------------
# Public API
# -----------------------------------------------------------------------

func set_world_name(name: String) -> void:
	_world_name = name


func load_explored() -> void:
	if _world_name.is_empty():
		return
	var path := _save_path_local()
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f:
			var data = f.get_var()
			if data is Dictionary:
				_explored = data

	var rpath := _save_path_regional()
	if FileAccess.file_exists(rpath):
		var f := FileAccess.open(rpath, FileAccess.READ)
		if f:
			var data = f.get_var()
			if data is Dictionary:
				_regional_explored = data


func save_explored() -> void:
	if _world_name.is_empty():
		return
	_write_var(_save_path_local(), _explored)
	_write_var(_save_path_regional(), _regional_explored)


func try_update(entity_id: int, pos: Vector3, chunk: ChunkData) -> void:
	var lx := _local_cell_x(pos, chunk)
	var lz := _local_cell_z(pos, chunk)
	var cell := Vector2i(lx, lz)

	if _last_cell.has(entity_id):
		var last: Vector2i = _last_cell[entity_id]
		if absi(cell.x - last.x) + absi(cell.y - last.y) < MOVE_THRESHOLD_CELLS:
			return

	_last_cell[entity_id] = cell
	_launch(lx, lz, chunk)


func force_update(entity_id: int, pos: Vector3, chunk: ChunkData) -> void:
	_last_cell.erase(entity_id)
	try_update(entity_id, pos, chunk)


func get_explored(chunk_key: String) -> PackedByteArray:
	return _explored.get(chunk_key, PackedByteArray())

func get_visible(chunk_key: String) -> PackedByteArray:
	return _visible.get(chunk_key, PackedByteArray())

func get_regional_explored(chunk_key: String) -> PackedByteArray:
	return _regional_explored.get(chunk_key, PackedByteArray())


# Returns the regional chunk coords (Vector2i) where at least one cell has
# been explored.  Used to populate EntityGroup.known_chunks at session load.
func get_explored_regional_chunks() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for key in _regional_explored.keys():
		var mask: PackedByteArray = _regional_explored[key]
		if mask.has(1):
			var parts := (key as String).split("_")
			if parts.size() == 3:
				result.append(Vector2i(int(parts[1]), int(parts[2])))
	return result

func get_regional_visible(chunk_key: String) -> PackedByteArray:
	return _regional_visible.get(chunk_key, PackedByteArray())


# Returns true if the given world position falls inside the most recent
# visible mask.  Party members should always show; everyone else hides when
# this returns false.
func is_world_pos_visible(world_pos: Vector3) -> bool:
	var manifest := WorldManager._manifest
	if manifest == null:
		return false
	var chunk_size_m := float(manifest.chunk_cells_local) * manifest.cell_size_local_m
	var cell_size    := manifest.cell_size_local_m
	var cx := int(world_pos.x / chunk_size_m)
	var cz := int(world_pos.z / chunk_size_m)
	var key := "0_%d_%d" % [cx, cz]
	var vis: PackedByteArray = _visible.get(key, PackedByteArray())
	if vis.is_empty():
		return false
	var lx := clampi(int(fmod(world_pos.x, chunk_size_m) / cell_size), 0, manifest.chunk_cells_local - 1)
	var lz := clampi(int(fmod(world_pos.z, chunk_size_m) / cell_size), 0, manifest.chunk_cells_local - 1)
	var idx := lz * manifest.chunk_cells_local + lx
	return idx < vis.size() and vis[idx] != 0


func clear() -> void:
	if _thread.is_started():
		_thread.wait_to_finish()
	_explored.clear()
	_visible.clear()
	_regional_explored.clear()
	_regional_visible.clear()
	_last_cell.clear()
	_mutex.lock()
	_pending.clear()
	_mutex.unlock()


# -----------------------------------------------------------------------
# Thread launch
# -----------------------------------------------------------------------

func _launch(lx: int, lz: int, chunk: ChunkData) -> void:
	if _thread.is_started() and _thread.is_alive():
		return
	if _thread.is_started():
		_thread.wait_to_finish()

	# Local composite (main thread — WorldManager access is safe here).
	var t0 := Time.get_ticks_usec()
	var composite := _build_composite(chunk, lx, lz)
	var t_build_local_us := Time.get_ticks_usec() - t0

	# World position of observer — used to locate the regional chunk.
	var world_x := float(chunk.chunk_x) * float(chunk.cells_x) * chunk.cell_size_m \
				 + float(lx) * chunk.cell_size_m
	var world_z := float(chunk.chunk_y) * float(chunk.cells_y) * chunk.cell_size_m \
				 + float(lz) * chunk.cell_size_m

	t0 = Time.get_ticks_usec()
	var reg_composite := _build_regional_composite(world_x, world_z)
	var t_build_regional_us := Time.get_ticks_usec() - t0

	var args := {
		"t_build_local_us":    t_build_local_us,
		"t_build_regional_us": t_build_regional_us,
		# Local
		"hmap":        composite.hmap,
		"width":       composite.width,
		"height":      composite.height,
		"obs_x":       composite.obs_x,
		"obs_y":       composite.obs_y,
		"cell_size_m": chunk.cell_size_m,
		"face":        chunk.face,
		"center_cx":   chunk.chunk_x,
		"center_cy":   chunk.chunk_y,
		"chunk_w":     chunk.cells_x,
		"chunk_h":     chunk.cells_y,
		# Regional
		"reg_hmap":        reg_composite.get("hmap", PackedFloat32Array()),
		"reg_width":       reg_composite.get("width", 0),
		"reg_height":      reg_composite.get("height", 0),
		"reg_obs_x":       reg_composite.get("obs_x", 0),
		"reg_obs_y":       reg_composite.get("obs_y", 0),
		"reg_cell_size_m": reg_composite.get("cell_size_m", 100.0),
		"reg_face":        chunk.face,
		"reg_center_cx":   reg_composite.get("center_cx", 0),
		"reg_center_cy":   reg_composite.get("center_cy", 0),
		"reg_chunk_w":     reg_composite.get("chunk_w", 0),
		"reg_chunk_h":     reg_composite.get("chunk_h", 0),
	}
	_thread.start(_run_viewshed.bind(args))


func _build_composite(chunk: ChunkData, lx: int, lz: int) -> Dictionary:
	var cw := chunk.cells_x
	var ch := chunk.cells_y
	var r  := COMPOSITE_CHUNK_RADIUS
	var comp_w := cw * (2 * r + 1)
	var comp_h := ch * (2 * r + 1)

	var hmap := PackedFloat32Array()
	hmap.resize(comp_w * comp_h)
	hmap.fill(0.0)

	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var ncx := chunk.chunk_x + dx
			var ncy := chunk.chunk_y + dy
			var neighbor: ChunkData = WorldManager.get_chunk(
				chunk.face, ncx, ncy, ChunkData.LOD.LOCAL)
			if neighbor == null:
				continue
			var src := neighbor.get_final_heightmap()
			if src.size() < cw * ch:
				continue
			var off_x := (dx + r) * cw
			var off_y := (dy + r) * ch
			for row in ch:
				var src_base := row * cw
				var dst_base := (off_y + row) * comp_w + off_x
				for col in cw:
					hmap[dst_base + col] = src[src_base + col]

	return {
		"hmap":   hmap,
		"width":  comp_w,
		"height": comp_h,
		"obs_x":  r * cw + lx,
		"obs_y":  r * ch + lz,
	}


func _build_regional_composite(world_x: float, world_z: float) -> Dictionary:
	var manifest := WorldManager._manifest
	if manifest == null:
		return {}

	var cell_size   := manifest.cell_size_regional_m
	var cells_w     := manifest.chunk_cells_regional
	var cells_h     := manifest.chunk_cells_regional
	var chunk_size  := cell_size * float(cells_w)

	var center_cx := floori(world_x / chunk_size)
	var center_cy := floori(world_z / chunk_size)

	var obs_lx := clampi(floori((world_x - float(center_cx) * chunk_size) / cell_size), 0, cells_w - 1)
	var obs_lz := clampi(floori((world_z - float(center_cy) * chunk_size) / cell_size), 0, cells_h - 1)

	var r      := COMPOSITE_CHUNK_RADIUS
	var comp_w := cells_w * (2 * r + 1)
	var comp_h := cells_h * (2 * r + 1)

	var hmap := PackedFloat32Array()
	hmap.resize(comp_w * comp_h)
	# Fill with a very high sentinel so missing chunks block LOS instead of
	# acting as flat sea-level terrain (which would mark the full 8 km radius
	# as visible/explored before real data is available).
	hmap.fill(9999.0)

	var center_found := false
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var ncx := center_cx + dx
			var ncy := center_cy + dy
			var neighbor: ChunkData = WorldManager.get_chunk(
				0, ncx, ncy, ChunkData.LOD.REGIONAL)
			if neighbor == null:
				continue
			if dx == 0 and dy == 0:
				center_found = true
			var src := neighbor.get_final_heightmap()
			if src.size() < cells_w * cells_h:
				continue
			var off_x := (dx + r) * cells_w
			var off_y := (dy + r) * cells_h
			for row in cells_h:
				var src_base := row * cells_w
				var dst_base := (off_y + row) * comp_w + off_x
				for col in cells_w:
					hmap[dst_base + col] = src[src_base + col]

	# Don't run the regional viewshed if the player's own chunk isn't loaded —
	# the observer height would be wrong (9999 m) and produce garbage results.
	if not center_found:
		return {}

	return {
		"hmap":        hmap,
		"width":       comp_w,
		"height":      comp_h,
		"obs_x":       r * cells_w + obs_lx,
		"obs_y":       r * cells_h + obs_lz,
		"cell_size_m": cell_size,
		"center_cx":   center_cx,
		"center_cy":   center_cy,
		"chunk_w":     cells_w,
		"chunk_h":     cells_h,
	}


# -----------------------------------------------------------------------
# Thread function
# -----------------------------------------------------------------------

func _run_viewshed(args: Dictionary) -> void:
	# Derive per-LOD cell ranges from the shared world-space range.
	var local_range_cells  := int(VISIBILITY_RANGE_M / args.cell_size_m)
	var region_range_cells := int(VISIBILITY_RANGE_M / args.reg_cell_size_m)

	# Local viewshed
	var t0 := Time.get_ticks_usec()
	var visible: PackedByteArray = ViewshedSystem.compute(
		args.hmap, args.width, args.height,
		args.obs_x, args.obs_y,
		EYE_HEIGHT, local_range_cells, args.cell_size_m)
	var t_viewshed_local_us := Time.get_ticks_usec() - t0

	# Regional viewshed (skipped if composite was empty — no regional chunks loaded)
	var reg_visible := PackedByteArray()
	var t_viewshed_regional_us := 0
	if args.reg_width > 0 and not (args.reg_hmap as PackedFloat32Array).is_empty():
		t0 = Time.get_ticks_usec()
		reg_visible = ViewshedSystem.compute(
			args.reg_hmap, args.reg_width, args.reg_height,
			args.reg_obs_x, args.reg_obs_y,
			EYE_HEIGHT, region_range_cells, args.reg_cell_size_m)
		t_viewshed_regional_us = Time.get_ticks_usec() - t0

	_mutex.lock()
	_pending = {
		"visible":    visible,
		"comp_width": args.width,
		"face":       args.face,
		"center_cx":  args.center_cx,
		"center_cy":  args.center_cy,
		"chunk_w":    args.chunk_w,
		"chunk_h":    args.chunk_h,

		"reg_visible":    reg_visible,
		"reg_comp_width": args.reg_width,
		"reg_face":       args.reg_face,
		"reg_center_cx":  args.reg_center_cx,
		"reg_center_cy":  args.reg_center_cy,
		"reg_chunk_w":    args.reg_chunk_w,
		"reg_chunk_h":    args.reg_chunk_h,

		"t_build_local_us":       args.get("t_build_local_us", 0),
		"t_build_regional_us":    args.get("t_build_regional_us", 0),
		"t_viewshed_local_us":    t_viewshed_local_us,
		"t_viewshed_regional_us": t_viewshed_regional_us,
	}
	_mutex.unlock()


# -----------------------------------------------------------------------
# Apply results (main thread)
# -----------------------------------------------------------------------

func _apply_result(result: Dictionary) -> void:
	var comp_visible: PackedByteArray = result.visible
	var comp_w: int                   = result.comp_width
	var face: int                     = result.face
	var cx: int                       = result.center_cx
	var cy: int                       = result.center_cy
	var cw: int                       = result.chunk_w
	var ch: int                       = result.chunk_h
	var r  := COMPOSITE_CHUNK_RADIUS

	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var ncx := cx + dx
			var ncy := cy + dy
			var key := "%d_%d_%d" % [face, ncx, ncy]
			var off_x := (dx + r) * cw
			var off_y := (dy + r) * ch
			var size  := cw * ch

			var vis := PackedByteArray()
			vis.resize(size)
			for row in ch:
				for col in cw:
					var comp_idx := (off_y + row) * comp_w + (off_x + col)
					vis[row * cw + col] = comp_visible[comp_idx] if comp_idx < comp_visible.size() else 0

			var old_vis := _visible.get(key, PackedByteArray()) as PackedByteArray
			var vis_changed := (old_vis.size() != vis.size())
			if not vis_changed:
				for i in size:
					if old_vis[i] != vis[i]:
						vis_changed = true
						break

			var exp_changed := false
			if not _explored.has(key):
				var exp := PackedByteArray()
				exp.resize(size)
				exp.fill(0)
				_explored[key] = exp
			var explored: PackedByteArray = _explored[key]
			for i in size:
				if vis[i] and explored[i] == 0:
					explored[i] = 1
					exp_changed = true

			if not vis_changed and not exp_changed:
				continue

			if exp_changed:
				_explored[key] = explored
			_visible[key] = vis
			chunk_fog_updated.emit(key)


func _apply_regional_result(result: Dictionary) -> void:
	var reg_visible: PackedByteArray = result.get("reg_visible", PackedByteArray())
	if reg_visible.is_empty():
		return

	var comp_w: int = result.reg_comp_width
	if comp_w == 0:
		return

	var face: int = result.reg_face
	var cx: int   = result.reg_center_cx
	var cy: int   = result.reg_center_cy
	var cw: int   = result.reg_chunk_w
	var ch: int   = result.reg_chunk_h
	var r  := COMPOSITE_CHUNK_RADIUS

	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var ncx := cx + dx
			var ncy := cy + dy
			var key := "%d_%d_%d" % [face, ncx, ncy]
			var off_x := (dx + r) * cw
			var off_y := (dy + r) * ch
			var size  := cw * ch

			var vis := PackedByteArray()
			vis.resize(size)
			for row in ch:
				for col in cw:
					var comp_idx := (off_y + row) * comp_w + (off_x + col)
					vis[row * cw + col] = reg_visible[comp_idx] if comp_idx < reg_visible.size() else 0

			var old_vis := _regional_visible.get(key, PackedByteArray()) as PackedByteArray
			var vis_changed := (old_vis.size() != vis.size())
			if not vis_changed:
				for i in size:
					if old_vis[i] != vis[i]:
						vis_changed = true
						break

			var exp_changed := false
			if not _regional_explored.has(key):
				var exp := PackedByteArray()
				exp.resize(size)
				exp.fill(0)
				_regional_explored[key] = exp
			var explored: PackedByteArray = _regional_explored[key]
			for i in size:
				if vis[i] and explored[i] == 0:
					explored[i] = 1
					exp_changed = true

			if not vis_changed and not exp_changed:
				continue

			if exp_changed:
				_regional_explored[key] = explored
			_regional_visible[key] = vis
			regional_chunk_fog_updated.emit(key)


# -----------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------

func _local_cell_x(pos: Vector3, chunk: ChunkData) -> int:
	var chunk_size_m := float(chunk.cells_x) * chunk.cell_size_m
	return clampi(int(fmod(pos.x, chunk_size_m) / chunk.cell_size_m), 0, chunk.cells_x - 1)


func _local_cell_z(pos: Vector3, chunk: ChunkData) -> int:
	var chunk_size_m := float(chunk.cells_y) * chunk.cell_size_m
	return clampi(int(fmod(pos.z, chunk_size_m) / chunk.cell_size_m), 0, chunk.cells_y - 1)


func _save_path_local() -> String:
	return DiskManager.world_dir(_world_name) + "fog_explored.dat"


func _save_path_regional() -> String:
	return DiskManager.world_dir(_world_name) + "fog_regional_explored.dat"


func _write_var(path: String, data: Dictionary) -> void:
	if path.is_empty():
		return
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("FogOfWarManager: cannot write to " + path)
		return
	f.store_var(data)
