class_name GameWorld
extends Node3D

# Root scene for active gameplay.
# Sets up cameras, registers player entities from the world manifest,
# and drives chunk loading / LOD via the tactical camera's ground position.
#
# Camera model:
#   TAB toggles between Tactical view (2D cartographic map) and Entity view
#   (EntityCamController at eye level of the selected entity).
#   TacticalCamera remains active in both modes to keep LOD chunk loading working.
#   ViewLayout shows a mode indicator label in the top-right corner.
#   EntityVisuals manages capsule meshes and screen-space labels for all entities.

@onready var hud: HUD                           = $HUD
@onready var environment_node: WorldEnvironment = $Environment
@onready var chunks_root: Node3D                = $ChunksRoot
@onready var characters_root: Node3D            = $CharactersRoot

const CHUNK_SCENE    := "res://scenes/world/terrain_chunk.tscn"
const TOWN_RADIUS_M  := 80.0    # townspeople scatter radius around start position
const ENEMY_ID_BASE  := 10000   # generated enemy IDs start here (above manifest range)

var _lod_manager: LODManager
var _tactical_cam  # TacticalCamera — kept active for LOD even in map view
var _entity_cam    # EntityCamController
var _tactical_map_view: TacticalMapView
var _view_layout: ViewLayout
var _entity_visuals: EntityVisuals
var _fog_manager: FogOfWarManager
var _chunk_nodes: Dictionary = {}            # "%d_%d_%d" → TerrainChunkNode
var _regional_nodes: Dictionary = {}         # "r_%d_%d_%d" → MeshInstance3D
var _regional_shader: Shader                 # shared across all regional chunks
var _regional_materials: Dictionary = {}     # "r_%d_%d_%d" → ShaderMaterial (per-chunk instance)
var _regional_fog_textures: Dictionary = {}  # "r_%d_%d_%d" → ImageTexture

var _next_enemy_id: int = 0
var _town_ring:  MeshInstance3D = null
var _town_label: Label3D        = null

# true = showing tactical overhead; false = showing entity first-person
var _in_tactical_view: bool = true


# -----------------------------------------------------------------------
# Lifecycle
# -----------------------------------------------------------------------

func _ready() -> void:
	_lod_manager = LODManager.new()
	_lod_manager.chunk_priority_updated.connect(_on_priority_updated)

	WorldManager.chunk_loaded.connect(_on_chunk_loaded)
	WorldManager.chunk_unloaded.connect(_on_chunk_unloaded)
	TurnManager.command_completed.connect(_on_command_completed)

	_setup_cameras()
	_setup_entity_visuals()
	_setup_fog()
	_setup_atmosphere()
	_register_player_entities()
	_setup_town_marker()
	_spawn_enemies()
	_setup_command_panel()

	EntityRegistry.position_updated.connect(_on_entity_position_updated)
	EntityRegistry.position_updated.connect(_tactical_map_view.on_entity_moved)
	_populate_group_known_chunks()

	# Open in tactical (map) view.
	_switch_to_tactical()

	if OS.is_debug_build():
		DebugBridge.screen_ready("GameWorld", "", [])


func _exit_tree() -> void:
	if _fog_manager != null:
		_fog_manager.save_explored()
	var manifest := WorldManager._manifest
	if manifest != null:
		manifest.save(manifest.get_save_path())


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and ke.physical_keycode == KEY_TAB:
			_toggle_view()

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			if _in_tactical_view and TurnManager.phase == TurnManager.Phase.PLANNING:
				_issue_march_to_cursor(mb.position)


# -----------------------------------------------------------------------
# Camera setup
# -----------------------------------------------------------------------

func _setup_cameras() -> void:
	_tactical_cam = load("res://scripts/world/navigation/tactical_camera.gd").new()
	add_child(_tactical_cam)
	_tactical_cam.ground_chunk_changed.connect(_on_ground_chunk_changed)
	_tactical_cam.activate()  # always active for LOD chunk driving

	_entity_cam = load("res://scripts/characters/entity_cam_controller.gd").new()
	add_child(_entity_cam)
	_entity_cam.switch_requested.connect(_switch_to_tactical)

	_tactical_map_view = TacticalMapView.new()
	add_child(_tactical_map_view)

	_view_layout = ViewLayout.new()
	add_child(_view_layout)

	hud.set_camera(_tactical_cam)


func _setup_entity_visuals() -> void:
	_entity_visuals = EntityVisuals.new()
	add_child(_entity_visuals)
	_entity_visuals.set_camera(_tactical_cam.get_camera())


func _setup_atmosphere() -> void:
	if environment_node == null or environment_node.environment == null:
		return
	var env := environment_node.environment
	var fog_color := Color(0.6, 0.65, 0.75)   # cool blue-grey haze

	env.fog_enabled            = true
	env.fog_light_color        = fog_color
	env.fog_light_energy       = 1.0
	env.fog_density            = 0.00025
	env.fog_aerial_perspective = 0.0

	# Ensure a ProceduralSkyMaterial exists and set all colours explicitly so
	# the scene file's defaults (which may be yellow) are always overridden.
	if env.sky == null:
		env.sky = Sky.new()
	if not (env.sky.sky_material is ProceduralSkyMaterial):
		env.sky.sky_material = ProceduralSkyMaterial.new()
	var sky := env.sky.sky_material as ProceduralSkyMaterial
	sky.sky_top_color        = Color(0.10, 0.28, 0.70)   # deep blue overhead
	sky.sky_horizon_color    = Color(0.45, 0.58, 0.80)   # lighter blue at horizon
	sky.ground_horizon_color = fog_color                  # matches fog for seamless fade
	sky.ground_bottom_color  = Color(0.18, 0.16, 0.14)   # dark underside


func _setup_fog() -> void:
	_fog_manager = FogOfWarManager.new()
	add_child(_fog_manager)
	_fog_manager.chunk_fog_updated.connect(_on_chunk_fog_updated)
	_fog_manager.regional_chunk_fog_updated.connect(_on_regional_chunk_fog_updated)
	var manifest := WorldManager._manifest
	if manifest != null:
		_fog_manager.set_world_name(manifest.world_name)
		_fog_manager.load_explored()
	# Give EntityVisuals a reference so it can query per-entity visibility.
	_entity_visuals.set_fog_manager(_fog_manager)
	# Give the 2D map its fog source.
	_tactical_map_view.set_fog_manager(_fog_manager)


func _setup_command_panel() -> void:
	var panel := CommandPanel.new()
	add_child(panel)


func _toggle_view() -> void:
	if _in_tactical_view:
		_switch_to_entity()
	else:
		_switch_to_tactical()


func _switch_to_entity() -> void:
	if EntityRegistry.get_selected_id() < 0:
		return  # nothing selected — can't show entity view
	_in_tactical_view = false
	_tactical_cam.set_input_enabled(false)
	_entity_cam.activate()
	_entity_visuals.set_labels_visible(false)
	_tactical_map_view.hide()
	_view_layout.set_mode(ViewLayout.Mode.ENTITY)
	hud.set_active_view_camera(_entity_cam.get_camera())


func _switch_to_tactical() -> void:
	_in_tactical_view = true
	_entity_cam.deactivate()
	_tactical_cam.set_input_enabled(true)
	_entity_visuals.set_labels_visible(true)
	var sel_id := EntityRegistry.get_selected_id()
	if sel_id >= 0:
		_tactical_map_view.focus_on_entity(EntityRegistry.get_entity_pos(sel_id))
	_tactical_map_view.show_map()
	_view_layout.set_mode(ViewLayout.Mode.TACTICAL_FULL)
	hud.set_active_view_camera(_tactical_cam.get_camera())


# -----------------------------------------------------------------------
# Entity registration
# -----------------------------------------------------------------------

func _register_player_entities() -> void:
	var manifest := WorldManager._manifest
	if manifest == null:
		push_error("GameWorld: no manifest — cannot register entities")
		return

	EntityRegistry.clear()
	EntityRegistry.load_groups(manifest.groups)

	# In offline/single-player mode there is no lobby to claim groups, so
	# auto-claim all player_selectable groups for the local peer.
	if NetworkManager.is_offline():
		var local_peer := NetworkManager.local_peer_id
		for c in manifest.characters:
			var ch := c as Character
			if not ch.player_selectable or not ch.alive:
				continue
			var group := EntityRegistry.get_group_for_entity(ch.character_id)
			if group != null and group.owner_peer_id < 0:
				group.owner_peer_id = local_peer

	var chunk_size_m := float(manifest.chunk_cells_local) * manifest.cell_size_local_m
	var cell_size    := manifest.cell_size_local_m
	var town_center  := Vector3(
		manifest.start_chunk_x * chunk_size_m + chunk_size_m * 0.5,
		0.0,
		manifest.start_chunk_y * chunk_size_m + chunk_size_m * 0.5
	)

	# Snap town centre to terrain if the start chunk is already loaded.
	var start_chunk := WorldManager.get_chunk(
		manifest.start_face, manifest.start_chunk_x, manifest.start_chunk_y,
		ChunkData.LOD.LOCAL)
	if start_chunk != null and not start_chunk.base_heightmap.is_empty():
		var lx := clampi(int(fmod(town_center.x, chunk_size_m) / cell_size), 0, start_chunk.cells_x - 1)
		var lz := clampi(int(fmod(town_center.z, chunk_size_m) / cell_size), 0, start_chunk.cells_y - 1)
		town_center.y = start_chunk.get_height(lx, lz)

	# --- Party (player-controlled, blue, TAB-switchable) ---
	var party_chars: Array = manifest.characters.filter(
		func(c: Character) -> bool: return c.player_selectable and c.alive)

	for i in party_chars.size():
		var c: Character = party_chars[i]
		var offset := Vector3(float(i % 4) * 4.0, 0.0, float(i / 4) * 4.0)
		EntityRegistry.register(c.character_id, town_center + offset, &"player_party")

	if not party_chars.is_empty():
		EntityRegistry.set_selected((party_chars[0] as Character).character_id)
		for c in party_chars:
			EntityRegistry.add_to_zoom((c as Character).character_id)

	# --- Townspeople (neutral, purple) — distributed inside town radius ---
	var rng := RandomNumberGenerator.new()
	var townspeople: Array = manifest.characters.filter(
		func(c: Character) -> bool: return not c.player_selectable and c.alive)

	for c in townspeople:
		var ch := c as Character
		rng.seed = manifest.world_seed ^ (ch.character_id * 2654435761)
		var angle  := rng.randf() * TAU
		var radius := rng.randf_range(8.0, TOWN_RADIUS_M)
		var pos := Vector3(
			town_center.x + cos(angle) * radius,
			town_center.y,
			town_center.z + sin(angle) * radius
		)
		EntityRegistry.register(ch.character_id, pos, &"townspeople")

	WorldManager.update_active_chunks(
		manifest.start_face, manifest.start_chunk_x, manifest.start_chunk_y)

	_tactical_cam.snap_to_entities()


func _spawn_enemies() -> void:
	var manifest := WorldManager._manifest
	if manifest == null:
		return
	var chunk_size_m := float(manifest.chunk_cells_local) * manifest.cell_size_local_m

	# One enemy per outer chunk of the 7×7 grid (skip centre 3×3 = town area).
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			if abs(dx) <= 1 and abs(dy) <= 1:
				continue  # town area
			var cx := manifest.start_chunk_x + dx
			var cz := manifest.start_chunk_y + dy
			# Place at chunk centre; Y=0 until the chunk loads and snaps it.
			var pos := Vector3(
				float(cx) * chunk_size_m + chunk_size_m * 0.5,
				0.0,
				float(cz) * chunk_size_m + chunk_size_m * 0.5
			)
			var eid := ENEMY_ID_BASE + _next_enemy_id
			_next_enemy_id += 1
			EntityRegistry.register(eid, pos, &"enemy")


func _setup_town_marker() -> void:
	var manifest := WorldManager._manifest
	if manifest == null:
		return
	var chunk_size_m := float(manifest.chunk_cells_local) * manifest.cell_size_local_m
	var cx := float(manifest.start_chunk_x) * chunk_size_m + chunk_size_m * 0.5
	var cz := float(manifest.start_chunk_y) * chunk_size_m + chunk_size_m * 0.5

	# Ground ring — flat triangle ring mesh, orange outline only.
	_town_ring = MeshInstance3D.new()
	_town_ring.mesh = _make_ring_mesh(TOWN_RADIUS_M, 1.5, 64)
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(1.0, 0.50, 0.05)   # orange
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.cull_mode    = BaseMaterial3D.CULL_DISABLED
	_town_ring.set_surface_override_material(0, ring_mat)
	_town_ring.position = Vector3(cx, 0.0, cz)   # Y snapped in _on_chunk_loaded
	chunks_root.add_child(_town_ring)

	# Floating billboard label.
	var town_name: String = manifest.starting_town_name
	if town_name.is_empty():
		town_name = "Settlement"
	_town_label = Label3D.new()
	_town_label.text      = town_name
	_town_label.font_size = 48
	_town_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_town_label.modulate  = Color(1.0, 1.0, 1.0)
	_town_label.position  = Vector3(cx, 50.0, cz)  # Y snapped in _on_chunk_loaded
	chunks_root.add_child(_town_label)


# -----------------------------------------------------------------------
# LOD / chunk management
# -----------------------------------------------------------------------

func _on_ground_chunk_changed(face: int, chunk_x: int, chunk_y: int) -> void:
	WorldManager.update_active_chunks(face, chunk_x, chunk_y)
	# Pass the selected entity's cell position within the chunk so the LODManager
	# can compute the regional viewshed from the correct observer location.
	var cell_x := 0
	var cell_z := 0
	var manifest := WorldManager._manifest
	if manifest != null:
		var chunk_m := float(manifest.chunk_cells_local) * manifest.cell_size_local_m
		var pos     := EntityRegistry.get_selected_pos()
		cell_x = clampi(int(fmod(pos.x, chunk_m) / manifest.cell_size_local_m), 0, manifest.chunk_cells_local - 1)
		cell_z = clampi(int(fmod(pos.z, chunk_m) / manifest.cell_size_local_m), 0, manifest.chunk_cells_local - 1)
	_lod_manager.update(face, chunk_x, chunk_y, cell_x, cell_z, WorldManager)


func _on_priority_updated(jobs: Array) -> void:
	for job in jobs:
		if not WorldManager.is_chunk_loaded(job.face, job.cx, job.cy, job.lod):
			WorldManager._generate_queue.append(job)
	WorldManager._process_queue()


func _on_chunk_loaded(chunk: ChunkData) -> void:
	if chunk.lod == ChunkData.LOD.REGIONAL:
		_on_regional_chunk_loaded(chunk)
		return
	if chunk.lod != ChunkData.LOD.LOCAL:
		return

	var key := "%d_%d_%d" % [chunk.face, chunk.chunk_x, chunk.chunk_y]
	if _chunk_nodes.has(key):
		(_chunk_nodes[key] as TerrainChunkNode).load_chunk(chunk)
	else:
		var chunk_scene: PackedScene = load(CHUNK_SCENE)
		var node: TerrainChunkNode = chunk_scene.instantiate()
		chunks_root.add_child(node)
		node.load_chunk(chunk)
		_chunk_nodes[key] = node

	# Snap any player entities sitting in this chunk to the terrain surface.
	_snap_entities_in_chunk(chunk)

	# Apply any existing fog data for this chunk (e.g. on re-load).
	_update_chunk_fog(key)

	# Trigger initial viewshed for player entities that start in this chunk.
	_trigger_fog_for_entities_in_chunk(chunk)


func _snap_entities_in_chunk(chunk: ChunkData) -> void:
	var manifest := WorldManager._manifest
	if manifest == null:
		return
	var chunk_size_m := float(manifest.chunk_cells_local) * manifest.cell_size_local_m
	var cell_size    := manifest.cell_size_local_m
	# Snap every registered entity whose XZ lands in this chunk.
	for id in EntityRegistry.get_all_ids():
		var pos := EntityRegistry.get_entity_pos(id)
		var cx := int(pos.x / chunk_size_m)
		var cz := int(pos.z / chunk_size_m)
		if cx != chunk.chunk_x or cz != chunk.chunk_y:
			continue
		var lx := clampi(int(fmod(pos.x, chunk_size_m) / cell_size), 0, chunk.cells_x - 1)
		var lz := clampi(int(fmod(pos.z, chunk_size_m) / cell_size), 0, chunk.cells_y - 1)
		pos.y = chunk.get_height(lx, lz)
		EntityRegistry.update_position(id, pos)
	# Snap the town ring and label when the start chunk loads.
	_snap_town_marker(chunk)


func _snap_town_marker(chunk: ChunkData) -> void:
	if _town_ring == null and _town_label == null:
		return
	var manifest := WorldManager._manifest
	if manifest == null:
		return
	if chunk.chunk_x != manifest.start_chunk_x or chunk.chunk_y != manifest.start_chunk_y:
		return
	var chunk_size_m := float(manifest.chunk_cells_local) * manifest.cell_size_local_m
	var cell_size    := manifest.cell_size_local_m
	var cx_world     := float(manifest.start_chunk_x) * chunk_size_m + chunk_size_m * 0.5
	var cz_world     := float(manifest.start_chunk_y) * chunk_size_m + chunk_size_m * 0.5
	var lx := clampi(int(chunk_size_m * 0.5 / cell_size), 0, chunk.cells_x - 1)
	var lz := clampi(int(chunk_size_m * 0.5 / cell_size), 0, chunk.cells_y - 1)
	var terrain_y := chunk.get_height(lx, lz)
	if _town_ring  != null:
		_town_ring.position  = Vector3(cx_world, terrain_y + 0.3, cz_world)
	if _town_label != null:
		_town_label.position = Vector3(cx_world, terrain_y + 20.0, cz_world)


func _trigger_fog_for_all_entities() -> void:
	var manifest := WorldManager._manifest
	if manifest == null:
		return
	var chunk_size_m := float(manifest.chunk_cells_local) * manifest.cell_size_local_m
	for id in EntityRegistry.get_player_ids():
		var pos := EntityRegistry.get_entity_pos(id)
		var cx := int(pos.x / chunk_size_m)
		var cz := int(pos.z / chunk_size_m)
		var chunk := WorldManager.get_chunk(0, cx, cz, ChunkData.LOD.LOCAL)
		if chunk != null:
			_fog_manager.force_update(id, pos, chunk)


func _trigger_fog_for_entities_in_chunk(chunk: ChunkData) -> void:
	var manifest := WorldManager._manifest
	if manifest == null:
		return
	var chunk_size_m := float(manifest.chunk_cells_local) * manifest.cell_size_local_m
	for id in EntityRegistry.get_player_ids():
		var pos := EntityRegistry.get_entity_pos(id)
		var cx := int(pos.x / chunk_size_m)
		var cz := int(pos.z / chunk_size_m)
		if cx == chunk.chunk_x and cz == chunk.chunk_y:
			_fog_manager.force_update(id, pos, chunk)


func _on_chunk_unloaded(chunk_key: String) -> void:
	if _chunk_nodes.has(chunk_key):
		_chunk_nodes[chunk_key].queue_free()
		_chunk_nodes.erase(chunk_key)
	var rkey := "r_" + chunk_key
	if _regional_nodes.has(rkey):
		_regional_nodes[rkey].queue_free()
		_regional_nodes.erase(rkey)
		_regional_materials.erase(rkey)
		_regional_fog_textures.erase(rkey)


func _on_regional_chunk_loaded(chunk: ChunkData) -> void:
	var key := "r_%d_%d_%d" % [chunk.face, chunk.chunk_x, chunk.chunk_y]
	var node: MeshInstance3D
	if _regional_nodes.has(key):
		node = _regional_nodes[key]
	else:
		node = MeshInstance3D.new()
		chunks_root.add_child(node)
		_regional_nodes[key] = node

	var mesh := TerrainChunkMesh.build(chunk)
	node.mesh = mesh

	if _regional_shader == null:
		_regional_shader = _make_regional_shader()

	var mat := ShaderMaterial.new()
	mat.shader = _regional_shader
	_regional_materials[key] = mat
	node.set_surface_override_material(0, mat)

	var w_m := chunk.cells_x * chunk.cell_size_m
	var h_m := chunk.cells_y * chunk.cell_size_m
	# Offset 1 m below world-origin so local terrain (exact height) always wins
	# the depth test where both LODs overlap. At 100 m/cell resolution, 1 m is
	# imperceptible on the regional backdrop.
	node.position = Vector3(chunk.chunk_x * w_m, -1.0, chunk.chunk_y * h_m)

	# Apply any already-computed fog for this chunk (e.g. on re-load after save).
	var fog_key := "%d_%d_%d" % [chunk.face, chunk.chunk_x, chunk.chunk_y]
	_update_regional_chunk_fog(fog_key)

	# The first viewshed pass may have been skipped because this regional chunk
	# wasn't loaded yet. Re-trigger for all entities so the regional viewshed
	# runs now that we have real heightmap data.
	_trigger_fog_for_all_entities()


func _make_regional_shader() -> Shader:
	var shader := Shader.new()
	shader.code = """shader_type spatial;

// R8 texture: 0.0 = visible, ~0.55 = explored/hidden, 1.0 = unexplored black.
// hint_default_white: terrain visible until viewshed is computed (no black flicker).
// filter_nearest + repeat_disable: sharp per-cell fog, UV=1.0 clamps to last texel.
uniform sampler2D fog_texture : source_color, hint_default_white, filter_nearest, repeat_disable;

void fragment() {
	float fog_strength = texture(fog_texture, UV).r;
	ALBEDO    = mix(COLOR.rgb, vec3(0.0), fog_strength);
	ROUGHNESS = 0.9;
	METALLIC  = 0.0;
}"""
	return shader


# -----------------------------------------------------------------------
# Fog of war
# -----------------------------------------------------------------------

func _on_entity_position_updated(id: int, pos: Vector3) -> void:
	if not EntityRegistry.get_player_ids().has(id):
		return
	var manifest := WorldManager._manifest
	if manifest == null:
		return
	var chunk_size_m := float(manifest.chunk_cells_local) * manifest.cell_size_local_m
	var cx := int(pos.x / chunk_size_m)
	var cz := int(pos.z / chunk_size_m)
	var chunk := WorldManager.get_chunk(0, cx, cz, ChunkData.LOD.LOCAL)
	if chunk == null:
		return
	_fog_manager.try_update(id, pos, chunk)


# Migration: populate known_chunks from fog for any group that has none yet
# (saves that predate this feature, or freshly forged worlds).
func _populate_group_known_chunks() -> void:
	if _fog_manager == null:
		return
	var local_peer := NetworkManager.local_peer_id
	for group in EntityRegistry.get_groups_by_owner(local_peer):
		var eg := group as EntityGroup
		if eg.known_chunks.is_empty():
			eg.known_chunks = _fog_manager.get_explored_regional_chunks()


func _on_chunk_fog_updated(chunk_key: String) -> void:
	_update_chunk_fog(chunk_key)


func _on_regional_chunk_fog_updated(chunk_key: String) -> void:
	_update_regional_chunk_fog(chunk_key)
	# Keep group known_chunks in sync as new areas are explored.
	var parts := chunk_key.split("_")
	if parts.size() != 3:
		return
	var coord := Vector2i(int(parts[1]), int(parts[2]))
	var local_peer := NetworkManager.local_peer_id
	for group in EntityRegistry.get_groups_by_owner(local_peer):
		var eg := group as EntityGroup
		if not eg.known_chunks.has(coord):
			eg.known_chunks.append(coord)


func _update_regional_chunk_fog(chunk_key: String) -> void:
	var rkey := "r_" + chunk_key
	if not _regional_materials.has(rkey):
		return
	var manifest := WorldManager._manifest
	if manifest == null:
		return
	var w    := manifest.chunk_cells_regional
	var h    := manifest.chunk_cells_regional
	var size := w * h

	var explored := _fog_manager.get_regional_explored(chunk_key)
	var visible  := _fog_manager.get_regional_visible(chunk_key)

	var data := PackedByteArray()
	data.resize(size)
	for idx in size:
		var is_vis := idx < visible.size()  and visible[idx]  != 0
		var is_exp := idx < explored.size() and explored[idx] != 0
		if is_vis:
			data[idx] = 0
		elif is_exp:
			data[idx] = 140
		else:
			data[idx] = 255

	var t0 := Time.get_ticks_usec()
	var img := Image.create_from_data(w, h, false, Image.FORMAT_R8, data)
	var mat: ShaderMaterial = _regional_materials[rkey]
	if _regional_fog_textures.has(rkey):
		var tex: ImageTexture = _regional_fog_textures[rkey]
		tex.update(img)
		mat.set_shader_parameter("fog_texture", tex)
	else:
		var tex := ImageTexture.create_from_image(img)
		_regional_fog_textures[rkey] = tex
		mat.set_shader_parameter("fog_texture", tex)
	var elapsed := Time.get_ticks_usec() - t0
	if elapsed > 1000:
		print("[FOG] regional texture upload chunk=%s  %dms" % [chunk_key, elapsed / 1000])


func _update_chunk_fog(chunk_key: String) -> void:
	if not _chunk_nodes.has(chunk_key):
		return
	var explored := _fog_manager.get_explored(chunk_key)
	var visible  := _fog_manager.get_visible(chunk_key)
	# Skip upload if there is no data — the shader's hint_default_white renders
	# unexplored chunks as fully visible, so there is nothing to paint.
	if explored.is_empty() and visible.is_empty():
		return
	var t0 := Time.get_ticks_usec()
	(_chunk_nodes[chunk_key] as TerrainChunkNode).update_fog(explored, visible)
	var elapsed := Time.get_ticks_usec() - t0
	if elapsed > 1000:
		print("[FOG] local texture upload chunk=%s  %dms" % [chunk_key, elapsed / 1000])


# -----------------------------------------------------------------------
# Movement commands
# -----------------------------------------------------------------------

func _issue_march_to_cursor(screen_pos: Vector2) -> void:
	var cam: Camera3D = _tactical_cam.get_camera()
	var ray_origin: Vector3 = cam.project_ray_origin(screen_pos)
	var ray_dir: Vector3    = cam.project_ray_normal(screen_pos)

	var space  := get_world_3d().direct_space_state
	var query  := PhysicsRayQueryParameters3D.create(
		ray_origin, ray_origin + ray_dir * 10000.0)
	var result := space.intersect_ray(query)
	if result.is_empty():
		return

	var dest: Vector3 = result.position
	var lead_id := EntityRegistry.get_selected_id()
	if lead_id < 0:
		return

	var group := EntityRegistry.get_group_for_entity(lead_id)
	if group == null:
		return

	var lead_pos  := EntityRegistry.get_entity_pos(lead_id)
	var flat_diff := Vector2(dest.x - lead_pos.x, dest.z - lead_pos.z)
	if flat_diff.length() < 1.0:
		return

	var cmd := TravelCommand.new()
	cmd.termination = TravelCommand.Termination.DISTANCE
	cmd.distance_m  = flat_diff.length()
	cmd.direction   = flat_diff.normalized()
	cmd.pace        = TravelCommand.Pace.NORMAL

	TurnManager.submit_command(group.group_id, cmd)


func _on_command_completed(_cmd: Variant) -> void:
	pass  # CommandPanel handles REVIEW → PLANNING via its Continue button.


# -----------------------------------------------------------------------
# Mesh helpers
# -----------------------------------------------------------------------

# Flat ring lying in the XZ plane, centred at origin.
# radius    — distance from centre to ring midline
# thickness — ring width in metres
# segments  — number of quad strips around the circumference
static func _make_ring_mesh(radius: float, thickness: float, segments: int) -> ArrayMesh:
	var inner_r := radius - thickness * 0.5
	var outer_r := radius + thickness * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for i in segments:
		var a0 := float(i)       / float(segments) * TAU
		var a1 := float(i + 1)   / float(segments) * TAU
		var i0 := Vector3(cos(a0) * inner_r, 0.0, sin(a0) * inner_r)
		var o0 := Vector3(cos(a0) * outer_r, 0.0, sin(a0) * outer_r)
		var i1 := Vector3(cos(a1) * inner_r, 0.0, sin(a1) * inner_r)
		var o1 := Vector3(cos(a1) * outer_r, 0.0, sin(a1) * outer_r)
		st.add_vertex(i0); st.add_vertex(o0); st.add_vertex(i1)
		st.add_vertex(o0); st.add_vertex(o1); st.add_vertex(i1)
	return st.commit()
