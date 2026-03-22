class_name HUD
extends CanvasLayer

# In-game HUD overlay.
# Displays position debug info, biome, health, and (eventually) fog-of-war.
#
# Driven by EntityRegistry — shows info for the yellow-selected entity.
# No longer depends on PlayerController.

signal fog_updated

const BIOME_NAMES := [
	"Ocean",           # 0
	"Grassland",       # 1
	"Swamp",           # 2
	"Temperate Forest",# 3
	"Mountain",        # 4
	"Alpine / Snow",   # 5
	"Desert",          # 6
]

@onready var fog_overlay: ColorRect   = $FogOverlay
@onready var coords_label: Label      = $Margin/VBox/CoordsLabel
@onready var biome_label: Label       = $Margin/VBox/BiomeLabel
@onready var health_bar: ProgressBar  = $Margin/VBox/HealthBar
@onready var entity_label: Label      = $Margin/VBox/EntityLabel
@onready var terrain_label: Label     = $Margin/VBox/TerrainLabel
@onready var cam_pos_label: Label     = $Margin/VBox/CamPosLabel
@onready var cam_height_label: Label  = $Margin/VBox/CamHeightLabel
@onready var cam_orient_label: Label  = $Margin/VBox/CamOrientLabel
@onready var status_label: Label      = $StatusBar/StatusLabel

# Current viewshed mask for the local player's character.
var _viewshed_mask: PackedByteArray
var _mask_width: int = 0
var _mask_height: int = 0

var _tactical_cam = null     # TacticalCamera reference set by GameWorld
var _active_camera: Camera3D = null  # whichever Camera3D is currently rendering


func set_camera(cam) -> void:
	_tactical_cam = cam
	_active_camera = cam.get_camera()


func set_active_view_camera(cam: Camera3D) -> void:
	_active_camera = cam


func _ready() -> void:
	EntityRegistry.selection_changed.connect(_on_selection_changed)
	EntityRegistry.position_updated.connect(_on_entity_moved)
	fog_overlay.visible = false


func update_viewshed(mask: PackedByteArray, w: int, h: int) -> void:
	_viewshed_mask = mask
	_mask_width = w
	_mask_height = h
	fog_updated.emit()
	# TODO: Upload mask as ImageTexture to a fog-of-war shader on fog_overlay.
	fog_overlay.visible = false


func _process(_delta: float) -> void:
	# Status bar
	if WorldManager._is_generating:
		status_label.text = "Loading terrain…"
	elif TurnManager.phase == TurnManager.Phase.RESOLUTION:
		status_label.text = "Resolving…"
	else:
		status_label.text = "Planning  [right-click to march]"

	var sel_id := EntityRegistry.get_selected_id()
	if sel_id < 0:
		entity_label.text = "Entity: —"
	else:
		var char_name := _get_character_name(sel_id)
		entity_label.text = "Entity: %s" % char_name

	# Camera debug info
	if _active_camera != null:
		var cam_pos: Vector3 = _active_camera.global_position
		var look_dir: Vector3 = -_active_camera.global_transform.basis.z
		cam_orient_label.text = "Cam look: %.2f, %.2f, %.2f" % [look_dir.x, look_dir.y, look_dir.z]
		cam_pos_label.text = "Cam pos: %.0f, %.0f, %.0f" % [cam_pos.x, cam_pos.y, cam_pos.z]
		if _tactical_cam != null and _tactical_cam.get_camera() == _active_camera:
			var base_y: float = _tactical_cam._target_base_y
			var overhead: float = _tactical_cam._target_height
			cam_height_label.text = "Cam height: %.0fm above terrain (base %.0f)" % [overhead, base_y]
		else:
			cam_height_label.text = "Cam height: %.1fm (eye level)" % EntityCamController.EYE_HEIGHT
	else:
		cam_pos_label.text = "Cam pos: —"
		cam_height_label.text = "Cam height: —"
		cam_orient_label.text = "Cam look: —"

	if sel_id < 0:
		return

	var pos := EntityRegistry.get_entity_pos(sel_id)
	coords_label.text = "%.0f, %.0f, %.0f" % [pos.x, pos.y, pos.z]

	# Terrain height at entity position
	var manifest := WorldManager._manifest
	if manifest != null:
		var chunk_size_m := float(manifest.chunk_cells_local) * manifest.cell_size_local_m
		var cell_size := manifest.cell_size_local_m
		var cx := int(pos.x / chunk_size_m)
		var cz := int(pos.z / chunk_size_m)
		var chunk := WorldManager.get_chunk(0, cx, cz, ChunkData.LOD.LOCAL)
		if chunk != null and not chunk.base_heightmap.is_empty():
			var lx := clampi(int(fmod(pos.x, chunk_size_m) / cell_size), 0, chunk.cells_x - 1)
			var lz := clampi(int(fmod(pos.z, chunk_size_m) / cell_size), 0, chunk.cells_y - 1)
			terrain_label.text = "Terrain: %.0fm" % chunk.get_height(lx, lz)
		else:
			terrain_label.text = "Terrain: no chunk"

	# Health bar from character stats (if the manifest character is accessible).
	if manifest == null:
		return
	for c in manifest.characters:
		var ch := c as Character
		if ch.character_id == sel_id and ch.stats != null and ch.stats.max_health > 0:
			health_bar.value = float(ch.stats.current_health) / float(ch.stats.max_health) * 100.0
			break


# -----------------------------------------------------------------------
# EntityRegistry callbacks
# -----------------------------------------------------------------------

func _on_selection_changed(id: int, _is_selected: bool) -> void:
	_refresh_viewshed_for(id)


func _on_entity_moved(id: int, _pos: Vector3) -> void:
	if id == EntityRegistry.get_selected_id():
		_refresh_viewshed_for(id)


func _refresh_viewshed_for(entity_id: int) -> void:
	if entity_id < 0 or WorldManager._manifest == null:
		return

	var manifest := WorldManager._manifest
	var chunk_size_m := float(manifest.chunk_cells_local) * manifest.cell_size_local_m
	var cell_size    := manifest.cell_size_local_m
	var pos          := EntityRegistry.get_entity_pos(entity_id)
	var cx           := int(pos.x / chunk_size_m)
	var cz           := int(pos.z / chunk_size_m)
	var chunk        := WorldManager.get_chunk(0, cx, cz, ChunkData.LOD.LOCAL)

	if chunk == null or chunk.base_heightmap.is_empty():
		return

	var lx := clampi(int(fmod(pos.x, chunk_size_m) / cell_size), 0, chunk.cells_x - 1)
	var lz := clampi(int(fmod(pos.z, chunk_size_m) / cell_size), 0, chunk.cells_y - 1)

	var mask := ViewshedSystem.compute(
		chunk.get_final_heightmap(),
		chunk.cells_x, chunk.cells_y,
		lx, lz,
		1.7,  # DetectionSystem.EYE_HEIGHT_STANDING
		200,
		cell_size
	)
	update_viewshed(mask, chunk.cells_x, chunk.cells_y)

	var biome_idx := chunk.biome_map[lz * chunk.cells_x + lx] \
		if not chunk.biome_map.is_empty() else 0
	var biome_name: String = BIOME_NAMES[biome_idx] if biome_idx < BIOME_NAMES.size() else "Unknown"
	biome_label.text = "Biome: %s" % biome_name


func _get_character_name(character_id: int) -> String:
	var manifest := WorldManager._manifest
	if manifest == null:
		return "#%d" % character_id
	for c in manifest.characters:
		var ch := c as Character
		if ch.character_id == character_id:
			if ch.display_name != "":
				return ch.display_name
			var role := ch.get_display_role()
			return role if role != "" else "#%d" % character_id
	return "#%d" % character_id
