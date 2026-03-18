class_name EntityVisuals
extends Node3D

# Manages capsule mesh visuals and screen-space labels for all registered
# entities.
#
# Colour coding:
#   Yellow  — currently selected (any faction)
#   Blue    — player party (unselected)
#   Purple  — neutral / townspeople
#   Red     — enemy
#
# Fog-of-war: non-party entities are hidden when their terrain cell is not
# visible in the current viewshed.  Party members are always visible.
#
# Click-to-select: left-click within HIT_RADIUS_PX of a party capsule
# selects that entity (making TAB switch to their first-person view).

const CAPSULE_HEIGHT   := 1.8
const CAPSULE_RADIUS   := 0.3
const CAPSULE_Y_OFFSET := 0.9
const LABEL_Y_OFFSET   := CAPSULE_HEIGHT + 0.6
const LABEL_SCREEN_OFFSET := Vector2(12.0, -28.0)
const HIT_RADIUS_PX    := 28.0   # screen-space click tolerance

const COLOR_SELECTED    := Color(1.00, 0.85, 0.00)   # yellow
const COLOR_PARTY       := Color(0.20, 0.50, 1.00)   # blue
const COLOR_TOWNSPEOPLE := Color(0.65, 0.15, 0.80)   # purple
const COLOR_ENEMY       := Color(0.90, 0.15, 0.15)   # red

var _camera: Camera3D
var _fog_manager = null           # FogOfWarManager — set by GameWorld after setup
var _capsules: Dictionary = {}    # int → MeshInstance3D
var _label_layer: CanvasLayer
var _labels: Dictionary = {}      # int → Label
var _screen_pos: Dictionary = {}  # int → Vector2 (last projected capsule centre)


func _ready() -> void:
	_label_layer = CanvasLayer.new()
	_label_layer.layer = 5
	add_child(_label_layer)

	EntityRegistry.entity_registered.connect(_on_entity_registered)
	EntityRegistry.entity_unregistered.connect(_on_entity_unregistered)
	EntityRegistry.position_updated.connect(_on_entity_moved)
	EntityRegistry.selection_changed.connect(_on_selection_changed)
	EntityRegistry.faction_changed.connect(_on_faction_changed)

	for id in EntityRegistry.get_all_ids():
		_add_entity(id)


func set_camera(cam: Camera3D) -> void:
	_camera = cam


func set_fog_manager(fm) -> void:
	_fog_manager = fm


func set_labels_visible(vis: bool) -> void:
	_label_layer.visible = vis


# -----------------------------------------------------------------------
# Frame loop — project world positions to screen; handle fog hide/show
# -----------------------------------------------------------------------

func _process(_delta: float) -> void:
	if _camera == null:
		return
	var vp_rect := get_viewport().get_visible_rect()
	_screen_pos.clear()

	for id in _capsules:
		var world_pos := EntityRegistry.get_entity_pos(id)
		var rec := EntityRegistry.get_entity(id)
		var is_party := rec != null and rec.faction == &"player_party"

		# Fog-of-war: hide non-party entities whose cell is not visible.
		var in_fog := false
		if not is_party and _fog_manager != null:
			in_fog = not _fog_manager.is_world_pos_visible(world_pos)

		(_capsules[id] as MeshInstance3D).visible = not in_fog

		if not _label_layer.visible or in_fog:
			if _labels.has(id):
				(_labels[id] as Label).visible = false
			continue

		var world_top := world_pos + Vector3(0.0, LABEL_Y_OFFSET, 0.0)
		if _camera.is_position_behind(world_top):
			if _labels.has(id):
				(_labels[id] as Label).visible = false
			continue
		var screen := _camera.unproject_position(world_top)
		if not vp_rect.has_point(screen):
			if _labels.has(id):
				(_labels[id] as Label).visible = false
			continue
		if _labels.has(id):
			var label := _labels[id] as Label
			label.visible = true
			label.position = screen + LABEL_SCREEN_OFFSET

		# Store capsule centre in screen space for click detection.
		var cap_screen := _camera.unproject_position(
			world_pos + Vector3(0.0, CAPSULE_Y_OFFSET, 0.0))
		_screen_pos[id] = cap_screen


# -----------------------------------------------------------------------
# Click-to-select: left-click selects the nearest visible party member
# -----------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not (mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT):
		return

	var best_id   := -1
	var best_dist := HIT_RADIUS_PX
	for id in _screen_pos:
		var rec := EntityRegistry.get_entity(id)
		if rec == null or rec.faction != &"player_party":
			continue
		var dist := mb.position.distance_to(_screen_pos[id] as Vector2)
		if dist < best_dist:
			best_dist = dist
			best_id   = id

	if best_id >= 0:
		EntityRegistry.set_selected(best_id)
		get_viewport().set_input_as_handled()


# -----------------------------------------------------------------------
# Entity add / remove
# -----------------------------------------------------------------------

func _add_entity(id: int) -> void:
	_add_capsule(id)
	_add_label(id)


func _remove_entity(id: int) -> void:
	if _capsules.has(id):
		(_capsules[id] as MeshInstance3D).queue_free()
		_capsules.erase(id)
	if _labels.has(id):
		(_labels[id] as Label).queue_free()
		_labels.erase(id)


func _add_capsule(id: int) -> void:
	var capsule := CapsuleMesh.new()
	capsule.height = CAPSULE_HEIGHT
	capsule.radius = CAPSULE_RADIUS

	var mat := StandardMaterial3D.new()
	var rec := EntityRegistry.get_entity(id)
	mat.albedo_color = COLOR_SELECTED if (rec != null and rec.is_selected) else _faction_color(id)

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = capsule
	mesh_inst.set_surface_override_material(0, mat)

	var pos := EntityRegistry.get_entity_pos(id)
	mesh_inst.position = pos + Vector3(0.0, CAPSULE_Y_OFFSET, 0.0)

	add_child(mesh_inst)
	_capsules[id] = mesh_inst


func _add_label(id: int) -> void:
	var label := Label.new()
	label.text = _build_label_text(id)

	var settings := LabelSettings.new()
	settings.font_color = Color(1.0, 1.0, 1.0)
	settings.font_size  = 13
	settings.shadow_color  = Color(0.0, 0.0, 0.0, 0.85)
	settings.shadow_offset = Vector2(1.0, 1.0)
	settings.shadow_size   = 1
	label.label_settings = settings

	_label_layer.add_child(label)
	_labels[id] = label


# -----------------------------------------------------------------------
# Label text
# -----------------------------------------------------------------------

func _build_label_text(id: int) -> String:
	var rec      := EntityRegistry.get_entity(id)
	var is_party := rec != null and rec.faction == &"player_party"

	var manifest := WorldManager._manifest
	if manifest != null:
		for c in manifest.characters:
			var ch := c as Character
			if ch.character_id != id:
				continue
			if is_party:
				var type_str := "Human" if ch.is_human() else ch.creature_type.type_name
				return "%s  %s\n%s" % [ch.display_name, type_str, ch.get_display_role()]
			else:
				# Only reveal race — name and role unknown until met.
				return "Human" if ch.is_human() else ch.creature_type.type_name

	# Generated entity not in manifest (e.g. spawned enemies).
	return "Human"


# -----------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------

func _faction_color(id: int) -> Color:
	var rec := EntityRegistry.get_entity(id)
	if rec == null:
		return COLOR_TOWNSPEOPLE
	match rec.faction:
		&"player_party": return COLOR_PARTY
		&"enemy":        return COLOR_ENEMY
		_:               return COLOR_TOWNSPEOPLE


# -----------------------------------------------------------------------
# EntityRegistry callbacks
# -----------------------------------------------------------------------

func _on_entity_registered(id: int) -> void:
	_add_entity(id)


func _on_entity_unregistered(id: int) -> void:
	_remove_entity(id)


func _on_entity_moved(id: int, pos: Vector3) -> void:
	if _capsules.has(id):
		(_capsules[id] as MeshInstance3D).position = pos + Vector3(0.0, CAPSULE_Y_OFFSET, 0.0)


func _on_selection_changed(id: int, is_selected: bool) -> void:
	if not _capsules.has(id):
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = COLOR_SELECTED if is_selected else _faction_color(id)
	(_capsules[id] as MeshInstance3D).set_surface_override_material(0, mat)


func _on_faction_changed(id: int, _faction: StringName) -> void:
	# Rebuild label (party ↔ non-party shows different text).
	if _labels.has(id):
		(_labels[id] as Label).text = _build_label_text(id)
	# Update capsule colour unless the entity is currently selected.
	if not _capsules.has(id):
		return
	var rec := EntityRegistry.get_entity(id)
	if rec != null and rec.is_selected:
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _faction_color(id)
	(_capsules[id] as MeshInstance3D).set_surface_override_material(0, mat)
