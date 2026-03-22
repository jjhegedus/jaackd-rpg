class_name WorldForge
extends Node

signal forge_started
signal progress_updated(fraction: float, status: String)
signal forge_completed(manifest: WorldManifest)
signal forge_failed(reason: String)

enum ForgeState { IDLE, RUNNING, COMPLETE, FAILED }

var state: ForgeState = ForgeState.IDLE
var current_manifest: WorldManifest

var _generator: TerrainGenerator
var _town_gen: TownGenerator
var _forge_thread: Thread


func _ready() -> void:
	_forge_thread = Thread.new()


func _exit_tree() -> void:
	if _forge_thread.is_started():
		_forge_thread.wait_to_finish()


# --- Public API ---

func can_forge(world_name: String, estimated_bytes: int) -> bool:
	if world_name.strip_edges() == "":
		return false
	if DiskManager.manifest_path(world_name) != "" \
			and ResourceLoader.exists(DiskManager.manifest_path(world_name)):
		return false  # world already exists
	return DiskManager.can_write(estimated_bytes)


func start_forge(
		world_name: String,
		town_name: String,
		seed: int,
		start_face: int,
		start_chunk_x: int,
		start_chunk_y: int) -> void:

	if state == ForgeState.RUNNING:
		push_warning("WorldForge: already running.")
		return

	var manifest := _build_manifest(
		world_name, town_name, seed, start_face, start_chunk_x, start_chunk_y
	)

	var err := DiskManager.ensure_world_dir(world_name)
	if err != OK:
		forge_failed.emit("Could not create world directory: %s" % error_string(err))
		return

	current_manifest = manifest
	state = ForgeState.RUNNING
	forge_started.emit()

	_forge_thread.start(_forge_thread_func.bind(manifest))


func _forge_thread_func(manifest: WorldManifest) -> void:
	_generator = TerrainGenerator.new()
	_generator.setup(manifest)
	_generator.progress_updated.connect(_on_gen_progress)

	# --- Phase 1: Planetary LOD ---
	call_deferred("_emit_progress", 0.0, "Generating planetary terrain…")
	var planetary_chunks := _generator.generate_planetary_lod()

	call_deferred("_emit_progress", 0.5, "Saving planetary terrain…")
	_save_chunks(planetary_chunks, manifest)

	# --- Phase 2: Town + starting area ---
	call_deferred("_emit_progress", 0.55, "Generating starting town…")
	_town_gen = TownGenerator.new()
	var characters := _town_gen.generate(manifest.world_seed, manifest.starting_town_name)

	# Add a starting adventurer party (player_selectable = true).
	var adv_rng := RandomNumberGenerator.new()
	adv_rng.seed = manifest.world_seed ^ 0x5A3F1C2D
	var adv_roles := ["warrior", "ranger", "rogue", "cleric", "mage"]
	var next_adv_id: int = _town_gen.get_next_id()
	for role in adv_roles:
		characters.append(_town_gen.create_adventurer(next_adv_id, role, adv_rng))
		next_adv_id += 1

	manifest.characters.assign(characters)
	manifest.ensure_solo_groups()

	# --- Phase 3: Pre-bake regional chunks from starting point ---
	call_deferred("_emit_progress", 0.65, "Pre-baking regional terrain…")
	var regional_chunks := _prebake_regional(manifest)
	_save_chunks(regional_chunks, manifest)
	manifest.prebaked_regional_radius = 3

	# --- Phase 4: Pre-bake local chunks from starting point ---
	call_deferred("_emit_progress", 0.85, "Pre-baking local terrain…")
	var local_chunks := _prebake_local(manifest)
	_save_chunks(local_chunks, manifest)
	manifest.prebaked_local_radius = 3

	# --- Finalize ---
	manifest.is_valid = true
	call_deferred("_finalize", manifest)


func _prebake_regional(manifest: WorldManifest) -> Array[ChunkData]:
	var chunks: Array[ChunkData] = []
	var radius := 3
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			chunks.append(_generator.generate_chunk(
				manifest.start_face,
				manifest.start_chunk_x + dx,
				manifest.start_chunk_y + dy,
				ChunkData.LOD.REGIONAL
			))
	return chunks


func _prebake_local(manifest: WorldManifest) -> Array[ChunkData]:
	var chunks: Array[ChunkData] = []
	var radius := 3
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			chunks.append(_generator.generate_chunk(
				manifest.start_face,
				manifest.start_chunk_x + dx,
				manifest.start_chunk_y + dy,
				ChunkData.LOD.LOCAL
			))
	return chunks


func _save_chunks(chunks: Array[ChunkData], manifest: WorldManifest) -> void:
	for chunk in chunks:
		var lod_name: String = str(ChunkData.LOD.keys()[chunk.lod]).to_lower()
		var path := DiskManager.chunks_dir(manifest.world_name) \
			+ "%s/f%d_%d_%d.res" % [lod_name, chunk.face, chunk.chunk_x, chunk.chunk_y]
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		ResourceSaver.save(chunk, path)


func _finalize(manifest: WorldManifest) -> void:
	var path := DiskManager.manifest_path(manifest.world_name)
	ResourceSaver.save(manifest, path)
	state = ForgeState.COMPLETE
	_forge_thread.wait_to_finish()
	forge_completed.emit(manifest)


func _on_gen_progress(fraction: float, status: String) -> void:
	call_deferred("_emit_progress", fraction * 0.5, status)


func _emit_progress(fraction: float, status: String) -> void:
	progress_updated.emit(fraction, status)


func _build_manifest(world_name: String, town_name: String, seed: int,
		start_face: int, start_chunk_x: int, start_chunk_y: int) -> WorldManifest:
	var m := WorldManifest.new()
	m.world_name = world_name
	m.world_seed = seed if seed != 0 else randi()
	m.starting_town_name = town_name if town_name != "" else _random_town_name(m.world_seed)
	m.created_at = int(Time.get_unix_time_from_system())
	m.forge_version = WorldManifest.CURRENT_FORGE_VERSION
	m.start_face = start_face
	m.start_chunk_x = start_chunk_x
	m.start_chunk_y = start_chunk_y
	return m


func _random_town_name(seed: int) -> String:
	const PREFIXES := ["Thorn", "Ash", "Iron", "Stone", "Crow", "Bright", "Dark", "Fell",
					   "Glen", "High", "Low", "Old", "New", "Long", "Short", "Black", "Red"]
	const SUFFIXES := ["wall", "ford", "haven", "gate", "wick", "moor", "hollow",
					   "cross", "bridge", "mill", "field", "wood", "vale", "ton"]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + 42
	return PREFIXES[rng.randi() % PREFIXES.size()] + SUFFIXES[rng.randi() % SUFFIXES.size()]
