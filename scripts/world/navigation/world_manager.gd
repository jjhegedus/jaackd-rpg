extends Node

signal chunk_loaded(chunk: ChunkData)
signal chunk_unloaded(chunk_key: String)

const LOAD_RADIUS_LOCAL := 3      # chunks in each direction at local LOD
const LOAD_RADIUS_REGIONAL := 5   # chunks at regional LOD

var _manifest: WorldManifest
var _generator: TerrainGenerator

# Set before changing to the World Forge scene to open a world for editing.
var edit_world_name: String = ""

# key: chunk save_key string → ChunkData
var _loaded_local: Dictionary = {}
var _loaded_regional: Dictionary = {}
var _loaded_planetary: Dictionary = {}

# Background generation queue
var _generate_queue: Array[Dictionary] = []  # {face, cx, cy, lod}
var _is_generating: bool = false
var _generate_thread: Thread


func _ready() -> void:
	_generate_thread = Thread.new()


func _exit_tree() -> void:
	if _generate_thread.is_started():
		_generate_thread.wait_to_finish()


# Call once a world has been loaded/created.
func initialize(manifest: WorldManifest) -> void:
	_manifest = manifest
	_generator = TerrainGenerator.new()
	_generator.setup(manifest)


# Called each time the player moves to a new chunk position.
func update_active_chunks(
		face: int, chunk_x: int, chunk_y: int) -> void:
	_enqueue_radius(face, chunk_x, chunk_y, LOAD_RADIUS_LOCAL, ChunkData.LOD.LOCAL)
	_enqueue_radius(face, chunk_x, chunk_y, LOAD_RADIUS_REGIONAL, ChunkData.LOD.REGIONAL)
	_process_queue()


func get_chunk(face: int, chunk_x: int, chunk_y: int,
		lod: ChunkData.LOD) -> ChunkData:
	var key := _key(face, chunk_x, chunk_y)
	var cache := _cache_for_lod(lod)
	if cache.has(key):
		return cache[key]
	# Don't block the main thread while the background thread is generating.
	# Callers should handle null and retry when chunk_loaded fires.
	if _is_generating:
		return null
	# Synchronous fallback only when idle (e.g. direct tool calls or tests)
	return _load_or_generate(face, chunk_x, chunk_y, lod)


func is_chunk_loaded(face: int, chunk_x: int, chunk_y: int,
		lod: ChunkData.LOD) -> bool:
	return _cache_for_lod(lod).has(_key(face, chunk_x, chunk_y))


# --- Internal ---

func _enqueue_radius(face: int, cx: int, cy: int,
		radius: int, lod: ChunkData.LOD) -> void:
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var nx := cx + dx
			var ny := cy + dy
			if nx < 0 or ny < 0:
				continue
			var key := _key(face, nx, ny)
			var cache := _cache_for_lod(lod)
			if not cache.has(key):
				_generate_queue.append({face = face, cx = nx, cy = ny, lod = lod})


func _process_queue() -> void:
	if _is_generating or _generate_queue.is_empty():
		return
	if _generate_thread.is_started():
		_generate_thread.wait_to_finish()
	_is_generating = true
	_generate_thread.start(_background_generate.bind(_generate_queue.duplicate()))
	_generate_queue.clear()


func _background_generate(queue: Array) -> void:
	for job in queue:
		var chunk := _load_or_generate(job.face, job.cx, job.cy, job.lod)
		# Marshal result back to main thread
		call_deferred("_on_chunk_ready", chunk)
	call_deferred("_on_queue_done")


func _on_chunk_ready(chunk: ChunkData) -> void:
	var key := _key(chunk.face, chunk.chunk_x, chunk.chunk_y)
	_cache_for_lod(chunk.lod)[key] = chunk
	chunk_loaded.emit(chunk)


func _on_queue_done() -> void:
	_is_generating = false
	if not _generate_queue.is_empty():
		_process_queue()


func _load_or_generate(face: int, cx: int, cy: int,
		lod: ChunkData.LOD) -> ChunkData:
	var path := _chunk_path(face, cx, cy, lod)
	if ResourceLoader.exists(path):
		var chunk := ResourceLoader.load(path) as ChunkData
		if chunk:
			return chunk
	# Not on disk — generate deterministically
	var chunk := _generator.generate_chunk(face, cx, cy, lod)
	_save_chunk(chunk)
	return chunk


func _save_chunk(chunk: ChunkData) -> void:
	if not DiskManager.can_write(_estimate_chunk_bytes(chunk)):
		push_warning("WorldManager: disk space too low to save chunk.")
		return
	var path := _chunk_path(chunk.face, chunk.chunk_x, chunk.chunk_y, chunk.lod)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	ResourceSaver.save(chunk, path)
	chunk.dirty = false


func _estimate_chunk_bytes(chunk: ChunkData) -> int:
	# 4 bytes per float, 2 float arrays + 2 byte arrays per cell
	return chunk.cells_x * chunk.cells_y * (4 * 4 + 2)


func _chunk_path(face: int, cx: int, cy: int, lod: ChunkData.LOD) -> String:
	var lod_name: String = str(ChunkData.LOD.keys()[lod]).to_lower()
	return DiskManager.chunks_dir(_manifest.world_name) \
		+ "%s/f%d_%d_%d.res" % [lod_name, face, cx, cy]


func _cache_for_lod(lod: ChunkData.LOD) -> Dictionary:
	match lod:
		ChunkData.LOD.PLANETARY: return _loaded_planetary
		ChunkData.LOD.REGIONAL: return _loaded_regional
		_: return _loaded_local


func _key(face: int, cx: int, cy: int) -> String:
	return "f%d_%d_%d" % [face, cx, cy]
