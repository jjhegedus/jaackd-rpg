class_name TacticalMapView
extends CanvasLayer

# 2D cartographic tactical map overlay.
#
# Replaces the 3D overhead TacticalCamera for the tactical view.
# One map pixel = one regional terrain cell (100 m × 100 m).
#
# Fog states per cell:
#   Visible      → full terrain colour
#   Remembered   → desaturated terrain colour
#   Unknown      → black
#
# Controls:
#   Scroll wheel → zoom
#   Left-drag    → pan
#   (opens centred on the active entity)

const CELLS_PER_CHUNK   := 64    # regional chunk dimension (square)
const ZOOM_MIN          := 0.25
const ZOOM_MAX          := 32.0
const ENTITY_DOT_R      := 4.0   # screen pixels, unscaled
const ACTIVE_ENTITY_R   := 6.0

# Contour colours and widths indexed by DEFAULT_THRESHOLDS order.
const CONTOUR_COLORS: Array = [
	Color(0.30, 0.50, 0.85, 0.90),  # sea level
	Color(0.55, 0.55, 0.55, 0.50),  # 100 m
	Color(0.55, 0.55, 0.55, 0.50),  # 300 m
	Color(0.50, 0.45, 0.38, 0.65),  # 700 m
	Color(0.48, 0.42, 0.36, 0.75),  # 1500 m
	Color(0.85, 0.88, 0.92, 0.85),  # 2500 m
]

var _fog_manager: FogOfWarManager = null

# Child nodes
var _bg:          ColorRect
var _map_control: Control

# Chunk data caches
var _chunk_textures: Dictionary = {}  # "face_cx_cy" → ImageTexture
var _chunk_contours: Dictionary = {}  # "face_cx_cy" → Dictionary{threshold→PackedVector2Array}

# Pan / zoom state
var _map_offset:  Vector2 = Vector2.ZERO  # top-left corner in map-pixel space
var _zoom:        float   = 4.0           # screen pixels per map pixel
var _drag_active: bool    = false
var _drag_last:   Vector2


# -----------------------------------------------------------------------
# Lifecycle
# -----------------------------------------------------------------------

func _ready() -> void:
	layer = 5
	add_to_group("tactical_map")
	_setup_ui()
	hide()
	WorldManager.chunk_loaded.connect(_on_chunk_loaded)


func _setup_ui() -> void:
	_bg = ColorRect.new()
	_bg.color = Color(0.05, 0.05, 0.08)
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_bg)

	_map_control = Control.new()
	_map_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_map_control.mouse_filter = Control.MOUSE_FILTER_STOP
	_map_control.draw.connect(_on_map_draw)
	_map_control.gui_input.connect(_on_map_gui_input)
	add_child(_map_control)


# -----------------------------------------------------------------------
# Public API
# -----------------------------------------------------------------------

func set_fog_manager(fm: FogOfWarManager) -> void:
	_fog_manager = fm
	fm.regional_chunk_fog_updated.connect(_on_regional_fog_updated)


func show_map() -> void:
	show()
	_refresh_all_chunks()
	_map_control.queue_redraw()


func focus_on_entity(world_pos: Vector3) -> void:
	var map_pos  := _world_to_map(world_pos)
	var vp_size  := get_viewport().get_visible_rect().size
	_map_offset  = map_pos - vp_size * 0.5 / _zoom
	_map_control.queue_redraw()


# Called by GameWorld when any entity moves; triggers a redraw of the dot layer.
func on_entity_moved(_id: int, _pos: Vector3) -> void:
	_map_control.queue_redraw()


# -----------------------------------------------------------------------
# Chunk rendering
# -----------------------------------------------------------------------

func _refresh_all_chunks() -> void:
	if _fog_manager == null:
		return
	for coord in _fog_manager.get_explored_regional_chunks():
		_render_chunk("0_%d_%d" % [coord.x, coord.y])


func _render_chunk(chunk_key: String) -> void:
	var parts := chunk_key.split("_")
	if parts.size() != 3:
		return
	var cx    := int(parts[1])
	var cy    := int(parts[2])
	var chunk: ChunkData = WorldManager.get_chunk(0, cx, cy, ChunkData.LOD.REGIONAL)
	if chunk == null or chunk.base_heightmap.is_empty():
		return

	var explored := PackedByteArray()
	var visible  := PackedByteArray()
	if _fog_manager != null:
		explored = _fog_manager.get_regional_explored(chunk_key)
		visible  = _fog_manager.get_regional_visible(chunk_key)

	var img := MapRenderer.render_chunk(chunk, explored, visible)
	if _chunk_textures.has(chunk_key):
		(_chunk_textures[chunk_key] as ImageTexture).update(img)
	else:
		_chunk_textures[chunk_key] = ImageTexture.create_from_image(img)

	# Contour lines are height-only — compute once, not on every fog update.
	if not _chunk_contours.has(chunk_key):
		_chunk_contours[chunk_key] = ContourLineGenerator.generate(chunk)

	_map_control.queue_redraw()


# -----------------------------------------------------------------------
# Drawing  (called from _map_control.draw signal)
# -----------------------------------------------------------------------

func _on_map_draw() -> void:
	_draw_tiles()
	_draw_contours()
	_draw_entity_dots()


func _draw_tiles() -> void:
	var vp := get_viewport().get_visible_rect()
	for key in _chunk_textures:
		var coords      := _key_coords(key)
		var tex         := _chunk_textures[key] as ImageTexture
		var tile_sz_map := float(CELLS_PER_CHUNK)
		var screen_pos  := _map_to_screen(Vector2(coords.x * tile_sz_map, coords.y * tile_sz_map))
		var screen_sz   := Vector2(tile_sz_map * _zoom, tile_sz_map * _zoom)
		# Cull tiles outside the viewport.
		if screen_pos.x + screen_sz.x < vp.position.x or screen_pos.x > vp.position.x + vp.size.x:
			continue
		if screen_pos.y + screen_sz.y < vp.position.y or screen_pos.y > vp.position.y + vp.size.y:
			continue
		_map_control.draw_texture_rect(tex, Rect2(screen_pos, screen_sz), false)


func _draw_contours() -> void:
	var thresholds := ContourLineGenerator.DEFAULT_THRESHOLDS
	for key in _chunk_contours:
		if not _chunk_textures.has(key):
			continue  # only draw where we have a rendered tile
		var coords    := _key_coords(key)
		var chunk_ox  := float(coords.x * CELLS_PER_CHUNK)
		var chunk_oy  := float(coords.y * CELLS_PER_CHUNK)
		var contours: Dictionary = _chunk_contours[key]

		for i in thresholds.size():
			var threshold := float(thresholds[i])
			if not contours.has(threshold):
				continue
			var segs: PackedVector2Array = contours[threshold]
			var color: Color = CONTOUR_COLORS[i] if i < CONTOUR_COLORS.size() else Color.GRAY
			var j := 0
			while j + 1 < segs.size():
				var a := _map_to_screen(Vector2(chunk_ox + segs[j].x,     chunk_oy + segs[j].y))
				var b := _map_to_screen(Vector2(chunk_ox + segs[j + 1].x, chunk_oy + segs[j + 1].y))
				_map_control.draw_line(a, b, color, 1.0)
				j += 2


func _draw_entity_dots() -> void:
	var selected_id := EntityRegistry.get_selected_id()
	var vp          := get_viewport().get_visible_rect()

	for id in EntityRegistry.get_player_ids():
		var pos        := EntityRegistry.get_entity_pos(id)
		var screen_pos := _map_to_screen(_world_to_map(pos))

		# Cull dots outside the viewport with a small margin.
		if screen_pos.x < vp.position.x - 20 or screen_pos.x > vp.position.x + vp.size.x + 20:
			continue
		if screen_pos.y < vp.position.y - 20 or screen_pos.y > vp.position.y + vp.size.y + 20:
			continue

		if id == selected_id:
			_map_control.draw_circle(screen_pos, ACTIVE_ENTITY_R, Color.YELLOW)
			_map_control.draw_arc(screen_pos, ACTIVE_ENTITY_R + 2.0, 0.0, TAU, 20, Color.WHITE, 1.5)
		else:
			_map_control.draw_circle(screen_pos, ENTITY_DOT_R, Color(0.3, 0.6, 1.0))


# -----------------------------------------------------------------------
# Input
# -----------------------------------------------------------------------

func _on_map_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			match mb.button_index:
				MOUSE_BUTTON_WHEEL_UP:
					_zoom_at(mb.position, minf(_zoom * 1.15, ZOOM_MAX))
					get_viewport().set_input_as_handled()
				MOUSE_BUTTON_WHEEL_DOWN:
					_zoom_at(mb.position, maxf(_zoom / 1.15, ZOOM_MIN))
					get_viewport().set_input_as_handled()
				MOUSE_BUTTON_LEFT:
					_drag_active = true
					_drag_last   = mb.position
		else:
			if mb.button_index == MOUSE_BUTTON_LEFT:
				_drag_active = false

	elif event is InputEventMouseMotion:
		if _drag_active:
			_map_offset -= (event as InputEventMouseMotion).relative / _zoom
			_map_control.queue_redraw()


# -----------------------------------------------------------------------
# Signal handlers
# -----------------------------------------------------------------------

func _on_chunk_loaded(chunk: ChunkData) -> void:
	if chunk.lod != ChunkData.LOD.REGIONAL:
		return
	_render_chunk("%d_%d_%d" % [chunk.face, chunk.chunk_x, chunk.chunk_y])


func _on_regional_fog_updated(chunk_key: String) -> void:
	_render_chunk(chunk_key)


# -----------------------------------------------------------------------
# Coordinate helpers
# -----------------------------------------------------------------------

func _world_to_map(world_pos: Vector3) -> Vector2:
	var manifest := WorldManager._manifest
	if manifest == null:
		return Vector2.ZERO
	return Vector2(world_pos.x / manifest.cell_size_regional_m,
				   world_pos.z / manifest.cell_size_regional_m)


func _map_to_screen(map_pos: Vector2) -> Vector2:
	return (map_pos - _map_offset) * _zoom


func _screen_to_map(screen_pos: Vector2) -> Vector2:
	return screen_pos / _zoom + _map_offset


func _zoom_at(screen_pos: Vector2, new_zoom: float) -> void:
	var map_pos  := _screen_to_map(screen_pos)
	_zoom        = new_zoom
	_map_offset  = map_pos - screen_pos / _zoom
	_map_control.queue_redraw()


func _key_coords(key: String) -> Vector2i:
	var parts := key.split("_")
	if parts.size() != 3:
		return Vector2i.ZERO
	return Vector2i(int(parts[1]), int(parts[2]))
