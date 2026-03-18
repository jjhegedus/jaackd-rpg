class_name PartyPanel
extends CanvasLayer

# Party management overlay — press P to open / close.
# Shows all player_selectable characters; toggle between party and town.

const COLOR_IN_PARTY := Color(0.20, 0.50, 1.00)   # blue
const COLOR_IN_TOWN  := Color(0.65, 0.15, 0.80)   # purple

var _panel: PanelContainer
var _container: VBoxContainer


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

	# Anchor panel to right edge of screen.
	_panel.set_anchor_and_offset(SIDE_LEFT,   1.0, -300.0)
	_panel.set_anchor_and_offset(SIDE_RIGHT,  1.0,   -6.0)
	_panel.set_anchor_and_offset(SIDE_TOP,    0.0,  130.0)
	_panel.set_anchor_and_offset(SIDE_BOTTOM, 1.0,  -10.0)
	add_child(_panel)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel.add_child(scroll)

	var outer := VBoxContainer.new()
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_theme_constant_override("separation", 4)
	scroll.add_child(outer)

	# Title
	var title := Label.new()
	title.text = "Party  (P to close)"
	var ts := LabelSettings.new()
	ts.font_size  = 15
	ts.font_color = Color(1.0, 1.0, 0.70)
	title.label_settings = ts
	outer.add_child(title)

	var sep := HSeparator.new()
	sep.add_theme_color_override("color", Color(0.4, 0.4, 0.6))
	outer.add_child(sep)

	_container = VBoxContainer.new()
	_container.add_theme_constant_override("separation", 2)
	outer.add_child(_container)


func _rebuild_rows() -> void:
	for child in _container.get_children():
		child.queue_free()

	var manifest := WorldManager._manifest
	if manifest == null:
		return

	for c in manifest.characters:
		var ch := c as Character
		if not ch.player_selectable or not ch.alive:
			continue
		_add_row(ch)


func _add_row(ch: Character) -> void:
	var rec      := EntityRegistry.get_entity(ch.character_id)
	var in_party := rec != null and rec.faction == &"player_party"

	var row := HBoxContainer.new()
	row.set_meta("char_id", ch.character_id)
	row.add_theme_constant_override("separation", 6)

	# Faction colour dot
	var dot := ColorRect.new()
	dot.custom_minimum_size = Vector2(10, 10)
	dot.color               = COLOR_IN_PARTY if in_party else COLOR_IN_TOWN
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(dot)

	# Name + role
	var role := ch.get_display_role()
	var lbl  := Label.new()
	lbl.text                   = ("%s  %s" % [ch.display_name, role]) if role != "" else ch.display_name
	lbl.size_flags_horizontal  = Control.SIZE_EXPAND_FILL
	lbl.clip_text              = true
	var ls := LabelSettings.new()
	ls.font_size  = 13
	ls.font_color = Color(1.0, 1.0, 1.0) if in_party else Color(0.60, 0.60, 0.65)
	ls.shadow_color  = Color(0.0, 0.0, 0.0, 0.9)
	ls.shadow_offset = Vector2(1.0, 1.0)
	ls.shadow_size   = 1
	lbl.label_settings = ls
	row.add_child(lbl)

	# Toggle button
	var btn := Button.new()
	btn.text                = "Party" if in_party else "Town"
	btn.custom_minimum_size = Vector2(52, 0)
	btn.pressed.connect(_toggle.bind(ch.character_id))
	row.add_child(btn)

	_container.add_child(row)


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
		if kids.size() >= 3:
			(kids[0] as ColorRect).color = COLOR_IN_PARTY if in_party else COLOR_IN_TOWN
			var ls := LabelSettings.new()
			ls.font_size     = 13
			ls.font_color    = Color(1.0, 1.0, 1.0) if in_party else Color(0.60, 0.60, 0.65)
			ls.shadow_color  = Color(0.0, 0.0, 0.0, 0.9)
			ls.shadow_offset = Vector2(1.0, 1.0)
			ls.shadow_size   = 1
			(kids[1] as Label).label_settings = ls
			(kids[2] as Button).text = "Party" if in_party else "Town"
		break


func _on_faction_changed(character_id: int, faction: StringName) -> void:
	if _panel.visible:
		_refresh_row(character_id, faction)
