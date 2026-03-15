class_name GameWorld
extends Node3D

# Root scene for active gameplay.
# Sets up tactical cameras, registers player entities from the world manifest,
# and drives chunk loading / LOD via the tactical camera's ground position.
#
# Camera model:
#   TAB key toggles between TACTICAL_FULL and SPLIT modes (ViewLayout).
#   SPLIT mode keeps TacticalCamera on the main viewport (left 60%) and
#   overlays a SubViewport on the right 40% showing the selected entity's
#   first-person view via ViewLayout's internal FP camera.

@onready var hud: HUD                           = $HUD
@onready var environment_node: WorldEnvironment = $Environment
@onready var chunks_root: Node3D                = $ChunksRoot
@onready var characters_root: Node3D            = $CharactersRoot

const CHUNK_SCENE := "res://scenes/world/terrain_chunk.tscn"

var _lod_manager: LODManager
var _tactical_cam  # TacticalCamera
var _entity_cam    # EntityCamController
var _view_layout: ViewLayout
var _chunk_nodes: Dictionary = {}   # chunk save_key → TerrainChunkNode
var _selection_marker: MeshInstance3D

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
	_register_player_entities()
	_setup_selection_marker()

	EntityRegistry.selection_changed.connect(_on_entity_selection_changed)
	EntityRegistry.position_updated.connect(_on_selected_entity_moved)

	if OS.is_debug_build():
		DebugBridge.screen_ready("GameWorld", "", [])


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

	_entity_cam = load("res://scripts/characters/entity_cam_controller.gd").new()
	add_child(_entity_cam)
	_entity_cam.switch_requested.connect(_switch_to_tactical)

	_view_layout = ViewLayout.new()
	add_child(_view_layout)

	_tactical_cam.activate()
	hud.set_camera(_tactical_cam)


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
	_view_layout.set_mode(ViewLayout.Mode.SPLIT)


func _switch_to_tactical() -> void:
	_in_tactical_view = true
	_tactical_cam.set_input_enabled(true)
	_view_layout.set_mode(ViewLayout.Mode.TACTICAL_FULL)


# -----------------------------------------------------------------------
# Entity registration
# -----------------------------------------------------------------------

func _register_player_entities() -> void:
	var manifest := WorldManager._manifest
	if manifest == null:
		push_error("GameWorld: no manifest — cannot register entities")
		return

	EntityRegistry.clear()

	var chunk_size_m := float(manifest.chunk_cells_local) * manifest.cell_size_local_m
	var cell_size := manifest.cell_size_local_m
	var start_pos := Vector3(
		manifest.start_chunk_x * chunk_size_m,
		0.0,
		manifest.start_chunk_y * chunk_size_m
	)

	# Place entities on the terrain surface, not at y=0.
	var start_chunk := WorldManager.get_chunk(
		manifest.start_face, manifest.start_chunk_x, manifest.start_chunk_y,
		ChunkData.LOD.LOCAL)
	if start_chunk != null and not start_chunk.base_heightmap.is_empty():
		var lx := clampi(int(fmod(start_pos.x, chunk_size_m) / cell_size), 0, start_chunk.cells_x - 1)
		var lz := clampi(int(fmod(start_pos.z, chunk_size_m) / cell_size), 0, start_chunk.cells_y - 1)
		start_pos.y = start_chunk.get_height(lx, lz)

	var player_chars: Array = manifest.characters.filter(
		func(c: Character) -> bool: return c.player_selectable and c.alive)

	for i in player_chars.size():
		var c: Character = player_chars[i]
		# Spread entities slightly around the start position.
		var offset := Vector3(float(i % 4) * 4.0, 0.0, float(i / 4) * 4.0)
		EntityRegistry.register(c.character_id, start_pos + offset, &"player")

	# Auto-select first player character and add all to zoom group.
	if not player_chars.is_empty():
		EntityRegistry.set_selected((player_chars[0] as Character).character_id)
		for c in player_chars:
			EntityRegistry.add_to_zoom((c as Character).character_id)

	# Trigger initial chunk loading around start position.
	WorldManager.update_active_chunks(
		manifest.start_face, manifest.start_chunk_x, manifest.start_chunk_y)

	# Snap tactical camera to entities now that registry is populated.
	_tactical_cam.snap_to_entities()


# -----------------------------------------------------------------------
# LOD / chunk management
# -----------------------------------------------------------------------

func _on_ground_chunk_changed(face: int, chunk_x: int, chunk_y: int) -> void:
	WorldManager.update_active_chunks(face, chunk_x, chunk_y)
	_lod_manager.update(face, chunk_x, chunk_y, 0, 0, WorldManager)


func _on_priority_updated(jobs: Array) -> void:
	for job in jobs:
		if not WorldManager.is_chunk_loaded(job.face, job.cx, job.cy, job.lod):
			WorldManager._generate_queue.append(job)
	WorldManager._process_queue()


func _on_chunk_loaded(chunk: ChunkData) -> void:
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
	# Entities register at y=0 before chunks load; this corrects their elevation
	# once the heightmap is available, which also repositions the selection marker.
	_snap_entities_in_chunk(chunk)


func _snap_entities_in_chunk(chunk: ChunkData) -> void:
	var manifest := WorldManager._manifest
	if manifest == null:
		return
	var chunk_size_m := float(manifest.chunk_cells_local) * manifest.cell_size_local_m
	var cell_size    := manifest.cell_size_local_m
	for id in EntityRegistry.get_player_ids():
		var pos := EntityRegistry.get_entity_pos(id)
		var cx := int(pos.x / chunk_size_m)
		var cz := int(pos.z / chunk_size_m)
		if cx != chunk.chunk_x or cz != chunk.chunk_y:
			continue
		var lx := clampi(int(fmod(pos.x, chunk_size_m) / cell_size), 0, chunk.cells_x - 1)
		var lz := clampi(int(fmod(pos.z, chunk_size_m) / cell_size), 0, chunk.cells_y - 1)
		pos.y = chunk.get_height(lx, lz)
		EntityRegistry.update_position(id, pos)


func _on_chunk_unloaded(chunk_key: String) -> void:
	if _chunk_nodes.has(chunk_key):
		_chunk_nodes[chunk_key].queue_free()
		_chunk_nodes.erase(chunk_key)


# -----------------------------------------------------------------------
# Selection marker
# -----------------------------------------------------------------------

func _setup_selection_marker() -> void:
	var ring := CylinderMesh.new()
	ring.top_radius    = 5.0
	ring.bottom_radius = 5.0
	ring.height        = 0.4
	ring.radial_segments = 24

	var mat := StandardMaterial3D.new()
	mat.albedo_color           = Color(1.0, 0.9, 0.0, 0.85)
	mat.emission_enabled       = true
	mat.emission               = Color(1.0, 0.85, 0.0)
	mat.emission_energy_multiplier = 2.0
	mat.transparency           = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test          = true   # always renders on top of terrain

	_selection_marker = MeshInstance3D.new()
	_selection_marker.mesh = ring
	_selection_marker.set_surface_override_material(0, mat)
	_selection_marker.visible = false
	add_child(_selection_marker)

	# Position at currently selected entity if one exists.
	var sel_id := EntityRegistry.get_selected_id()
	if sel_id >= 0:
		_selection_marker.global_position = EntityRegistry.get_entity_pos(sel_id) \
			+ Vector3(0.0, 0.3, 0.0)
		_selection_marker.visible = true


func _on_entity_selection_changed(id: int, is_selected: bool) -> void:
	if is_selected:
		var pos := EntityRegistry.get_entity_pos(id)
		_selection_marker.global_position = pos + Vector3(0.0, 0.3, 0.0)
		_selection_marker.visible = true
	elif id == EntityRegistry.get_selected_id():
		_selection_marker.visible = false


func _on_selected_entity_moved(id: int, pos: Vector3) -> void:
	if id == EntityRegistry.get_selected_id():
		_selection_marker.global_position = pos + Vector3(0.0, 0.3, 0.0)


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

	var lead_pos  := EntityRegistry.get_entity_pos(lead_id)
	var flat_diff := Vector2(dest.x - lead_pos.x, dest.z - lead_pos.z)
	if flat_diff.length() < 1.0:
		return

	var cmd := TravelCommand.new()
	cmd.termination = TravelCommand.Termination.DISTANCE
	cmd.distance_m  = flat_diff.length()
	cmd.direction   = flat_diff.normalized()
	cmd.pace        = TravelCommand.Pace.NORMAL

	TurnManager.issue_command(
		cmd,
		EntityRegistry.get_player_positions(),
		EntityRegistry.get_player_ids())


func _on_command_completed(_cmd: Variant) -> void:
	# Skip manual REVIEW for now — return immediately to PLANNING
	# so the player can issue another command.
	TurnManager.end_review()
