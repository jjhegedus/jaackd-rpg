class_name PartyPanel
extends CanvasLayer

# Party management overlay — press P to open / close.
# Shows all player_selectable characters; toggle between party and town.


var _panel: PanelContainer
var _container: VBoxContainer
var _title_label: Label


func _ready() -> void:
	layer = 20
	_build_ui()
	EntityRegistry.faction_changed.connect(_on_faction_changed)


# -----------------------------------------------------------------------
# Input — P toggles; swallow ALL mouse events when open (prevents terrain
# zoom from firing when the mouse wheel hits the scroll list end)
# -----------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and not ke.echo and ke.physical_keycode == KEY_P:
			_panel.visible = not _panel.visible
			if _panel.visible:
				_rebuild_rows()
			get_viewport().set_input_as_handled()
		return

	# While the panel is open, swallow wheel events so they don't zoom terrain.
	if _panel.visible and event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN,
								MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
			get_viewport().set_input_as_handled()


# -----------------------------------------------------------------------
# UI construction
# -----------------------------------------------------------------------

func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.visible = false
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP   # block clicks from reaching 3D
	add_child(_panel)

	# Anchor-based positioning is unreliable for Controls parented to a CanvasLayer
	# (the left/top anchors reset to 0 on scene-tree entry).  Use viewport size directly.
	var vp := get_viewport().get_visible_rect().size
	_panel.position = Vector2(vp.x - 300.0, 130.0)
	_panel.size     = Vector2(294.0, vp.y - 140.0)

	# Apply style and theme after the panel is in the scene tree.
	var style := StyleBoxFlat.new()
	style.bg_color                   = Color(0.06, 0.06, 0.10, 0.96)
	style.border_color               = Color(0.35, 0.35, 0.50, 1.0)
	style.set_border_width_all(1)
	style.corner_radius_top_left     = 6
	style.corner_radius_top_right    = 6
	style.corner_radius_bottom_left  = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left   = 12
	style.content_margin_right  = 12
	style.content_margin_top    = 10
	style.content_margin_bottom = 10
	_panel.add_theme_stylebox_override("panel", style)

	# Explicit theme so descendant Labels have a reliable base colour / size.
	var content_theme := Theme.new()
	content_theme.set_color("font_color", "Label", Color(0.88, 0.88, 0.88))
	content_theme.set_font_size("font_size", "Label", 13)
	_panel.theme = content_theme

	# Log the resolved panel rect one frame after build (layout is deferred).
	call_deferred("_log_panel_rect")

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical          = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal        = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode       = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)

	var outer := VBoxContainer.new()
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_theme_constant_override("separation", 4)
	scroll.add_child(outer)

	# Title
	_title_label = Label.new()
	_title_label.text = "Party  (P to close)"
	outer.add_child(_title_label)
	_title_label.add_theme_font_size_override("font_size", 15)
	_title_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.70))

	var sep := HSeparator.new()
	sep.add_theme_color_override("color", Color(0.4, 0.4, 0.6))
	outer.add_child(sep)

	_container = VBoxContainer.new()
	_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_container.add_theme_constant_override("separation", 2)
	outer.add_child(_container)


func _log_panel_rect() -> void:
	Log.write("PartyPanel built — pos=%s  size=%s  anchor_left=%.2f  offset_left=%.0f" % [
		str(_panel.position), str(_panel.size),
		_panel.anchor_left, _panel.offset_left])


func _rebuild_rows() -> void:
	for child in _container.get_children():
		child.queue_free()

	var manifest := WorldManager._manifest
	Log.write("PartyPanel _rebuild_rows — manifest=%s  panel_pos=%s  panel_size=%s" % [
		str(manifest != null), str(_panel.global_position), str(_panel.size)])
	if manifest == null:
		return

	var count := 0
	for c in manifest.characters:
		var ch := c as Character
		if not ch.player_selectable or not ch.alive:
			continue
		_add_row(ch)
		count += 1
	Log.write("PartyPanel rows added=%d" % count)
	_notify_screen_ready()


func _notify_screen_ready() -> void:
	if not OS.is_debug_build():
		return
	var nodes: Array = [{"id": "title", "node": _title_label}]
	for i in _container.get_child_count():
		var row := _container.get_child(i)
		var kids := row.get_children()
		if kids.size() >= 2:
			nodes.append({"id": "row_%d_lbl" % i, "node": kids[0]})
			nodes.append({"id": "row_%d_btn" % i, "node": kids[1]})
	DebugBridge.screen_ready("GameWorld", "PartyPanel", nodes)


func _add_row(ch: Character) -> void:
	var rec      := EntityRegistry.get_entity(ch.character_id)
	var in_party := rec != null and rec.faction == &"player_party"

	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 6)
	row.set_meta("char_id", ch.character_id)

	var role := ch.get_display_role()
	var lbl  := Label.new()
	lbl.text = ("%s  %s" % [ch.display_name, role]) if role != "" else ch.display_name
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.size_flags_vertical   = Control.SIZE_SHRINK_CENTER

	var btn := Button.new()
	btn.text = "Party" if in_party else "Town"
	btn.custom_minimum_size = Vector2(58, 0)
	btn.pressed.connect(_toggle.bind(ch.character_id))

	row.add_child(lbl)
	row.add_child(btn)
	_container.add_child(row)

	# Set overrides after the nodes are in the scene tree so they take effect.
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color",
		Color(1.0, 1.0, 1.0) if in_party else Color(0.60, 0.60, 0.65))


# -----------------------------------------------------------------------
# Toggle
# -----------------------------------------------------------------------

func _toggle(character_id: int) -> void:
	var rec := EntityRegistry.get_entity(character_id)
	if rec == null:
		return

	var in_party    := rec.faction == &"player_party"
	var new_faction : StringName = &"townspeople" if in_party else &"player_party"
	EntityRegistry.set_faction(character_id, new_faction)

	if new_faction == &"player_party":
		EntityRegistry.add_to_zoom(character_id)
	else:
		EntityRegistry.remove_from_zoom(character_id)
		if EntityRegistry.get_selected_id() == character_id:
			var party := EntityRegistry.get_player_ids()
			EntityRegistry.set_selected(party[0] if not party.is_empty() else -1)

	_refresh_row(character_id, new_faction)


func _refresh_row(character_id: int, faction: StringName) -> void:
	for row in _container.get_children():
		if not row.has_meta("char_id") or int(row.get_meta("char_id")) != character_id:
			continue
		var in_party := faction == &"player_party"
		var kids     := row.get_children()
		if kids.size() >= 2:
			(kids[0] as Label).add_theme_color_override("font_color",
				Color(1.0, 1.0, 1.0) if in_party else Color(0.60, 0.60, 0.65))
			(kids[1] as Button).text = "Party" if in_party else "Town"
		break


func _on_faction_changed(character_id: int, faction: StringName) -> void:
	if _panel.visible:
		_refresh_row(character_id, faction)
