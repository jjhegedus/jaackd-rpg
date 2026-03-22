class_name CommandPanel
extends CanvasLayer

# Commanding interface — replaces PartyPanel.
#
# Visible during PLANNING and REVIEW; hidden during RESOLUTION.
# Shows all player-owned groups with pending command per row.
# Click a row to select that group (sets the anchor entity as the active entity).
# Execute button ends planning for the local peer.
# Continue button (shown during REVIEW) returns to planning.

var _panel: PanelContainer
var _group_list: VBoxContainer
var _restructure_box: VBoxContainer
var _phase_label: Label
var _execute_btn: Button
var _selected_group_id: int = -1
var _editing_group_id: int = -1


func _ready() -> void:
	layer = 20
	_build_ui()
	TurnManager.phase_changed.connect(_on_phase_changed)
	TurnManager.command_submitted.connect(_on_command_submitted)
	TurnManager.peer_ready_changed.connect(_on_peer_ready_changed)
	EntityRegistry.group_loaded.connect(_on_group_loaded)
	EntityRegistry.groups_cleared.connect(_on_groups_cleared)
	EntityRegistry.group_restructured.connect(_on_group_restructured)
	call_deferred("_rebuild_group_rows")


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	if not _panel.visible:
		return
	var mb := event as InputEventMouseButton
	if mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN,
							MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
		if _panel.get_global_rect().has_point(mb.position):
			get_viewport().set_input_as_handled()


# -----------------------------------------------------------------------
# UI construction
# -----------------------------------------------------------------------

func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.visible = true
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)

	var vp := get_viewport().get_visible_rect().size
	_panel.position = Vector2(vp.x - 300.0, 130.0)
	_panel.size     = Vector2(294.0, vp.y - 140.0)

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

	var content_theme := Theme.new()
	content_theme.set_color("font_color", "Label", Color(0.88, 0.88, 0.88))
	content_theme.set_font_size("font_size", "Label", 13)
	_panel.theme = content_theme

	var outer := VBoxContainer.new()
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_theme_constant_override("separation", 6)
	_panel.add_child(outer)

	# Title + phase row
	var header := HBoxContainer.new()
	outer.add_child(header)

	var title := Label.new()
	title.text = "Commands"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(1.0, 1.0, 0.70))
	header.add_child(title)

	_phase_label = Label.new()
	_phase_label.text = "PLANNING"
	_phase_label.add_theme_font_size_override("font_size", 11)
	_phase_label.add_theme_color_override("font_color", Color(0.50, 1.00, 0.50))
	header.add_child(_phase_label)

	var sep := HSeparator.new()
	sep.add_theme_color_override("color", Color(0.4, 0.4, 0.6))
	outer.add_child(sep)

	# Scrollable group list
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)

	_group_list = VBoxContainer.new()
	_group_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_group_list.add_theme_constant_override("separation", 3)
	scroll.add_child(_group_list)

	var sep2 := HSeparator.new()
	sep2.add_theme_color_override("color", Color(0.4, 0.4, 0.6))
	outer.add_child(sep2)

	_restructure_box = VBoxContainer.new()
	_restructure_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_restructure_box.add_theme_constant_override("separation", 2)
	_restructure_box.visible = false
	outer.add_child(_restructure_box)

	var sep3 := HSeparator.new()
	sep3.add_theme_color_override("color", Color(0.4, 0.4, 0.6))
	outer.add_child(sep3)

	_execute_btn = Button.new()
	_execute_btn.text = "Execute"
	_execute_btn.custom_minimum_size = Vector2(0, 36)
	_execute_btn.pressed.connect(_on_execute_pressed)
	outer.add_child(_execute_btn)


# -----------------------------------------------------------------------
# Group rows
# -----------------------------------------------------------------------

func _rebuild_group_rows() -> void:
	for child in _group_list.get_children():
		child.queue_free()

	var manifest := WorldManager._manifest
	if manifest == null:
		return

	var local_peer := NetworkManager.local_peer_id
	var groups := EntityRegistry.get_groups_by_owner(local_peer)

	# Multi-entity groups first; within same size, stable order by group_id.
	groups.sort_custom(func(a, b):
		if a.member_ids.size() != b.member_ids.size():
			return a.member_ids.size() > b.member_ids.size()
		return a.group_id < b.group_id)

	# Auto-select first group if none selected.
	if _selected_group_id < 0 and not groups.is_empty():
		var first := groups[0] as EntityGroup
		_selected_group_id = first.group_id
		if first.anchor_entity >= 0:
			EntityRegistry.set_selected(first.anchor_entity)

	for g in groups:
		_add_group_row(g as EntityGroup)

	_rebuild_restructure()
	_notify_screen_ready()


func _add_group_row(group: EntityGroup) -> void:
	var is_selected := group.group_id == _selected_group_id

	var row := PanelContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.set_meta("group_id", group.group_id)
	row.gui_input.connect(_on_row_gui_input.bind(group.group_id))

	var row_style := StyleBoxFlat.new()
	row_style.bg_color    = Color(0.18, 0.22, 0.32) if is_selected else Color(0.10, 0.10, 0.16)
	row_style.border_color = Color(0.50, 0.60, 0.90) if is_selected else Color(0.20, 0.20, 0.35)
	row_style.set_border_width_all(1)
	row_style.corner_radius_top_left     = 3
	row_style.corner_radius_top_right    = 3
	row_style.corner_radius_bottom_left  = 3
	row_style.corner_radius_bottom_right = 3
	row_style.content_margin_left   = 8
	row_style.content_margin_right  = 8
	row_style.content_margin_top    = 5
	row_style.content_margin_bottom = 5
	row.add_theme_stylebox_override("panel", row_style)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)

	# Name row: label (or LineEdit when editing) + rename button
	var name_row := HBoxContainer.new()
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(name_row)

	if _editing_group_id == group.group_id:
		var edit := LineEdit.new()
		edit.text = _group_edit_name(group)
		edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		edit.add_theme_font_size_override("font_size", 13)
		edit.mouse_filter = Control.MOUSE_FILTER_STOP
		name_row.add_child(edit)
		# Grab focus after the node enters the tree.
		edit.call_deferred("grab_focus")
		edit.text_submitted.connect(_commit_rename.bind(group.group_id))
		edit.focus_exited.connect(_commit_rename_from_focus.bind(edit, group.group_id))
	else:
		var name_lbl := Label.new()
		name_lbl.text = _group_display_name(group)
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.add_theme_font_size_override("font_size", 13)
		name_lbl.add_theme_color_override("font_color",
			Color(1.0, 1.0, 1.0) if is_selected else Color(0.85, 0.85, 0.85))
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_row.add_child(name_lbl)

		var rename_btn := Button.new()
		rename_btn.text = "✎"
		rename_btn.flat = true
		rename_btn.custom_minimum_size = Vector2(24, 0)
		rename_btn.mouse_filter = Control.MOUSE_FILTER_STOP
		rename_btn.pressed.connect(_start_rename.bind(group.group_id))
		name_row.add_child(rename_btn)

	var cmd = TurnManager.get_pending_command(group.group_id)
	var cmd_lbl := Label.new()
	cmd_lbl.text = _command_summary(cmd)
	cmd_lbl.add_theme_font_size_override("font_size", 11)
	cmd_lbl.add_theme_color_override("font_color",
		Color(0.50, 0.90, 0.50) if cmd != null else Color(0.45, 0.45, 0.50))
	cmd_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(cmd_lbl)

	_group_list.add_child(row)


func _rebuild_restructure() -> void:
	for child in _restructure_box.get_children():
		child.queue_free()

	if TurnManager.phase != TurnManager.Phase.PLANNING:
		_restructure_box.visible = false
		return

	var selected := EntityRegistry.get_group(_selected_group_id)
	if selected == null:
		_restructure_box.visible = false
		return

	var local_peer := NetworkManager.local_peer_id
	var all_groups := EntityRegistry.get_groups_by_owner(local_peer)
	all_groups.sort_custom(func(a, b):
		if a.member_ids.size() != b.member_ids.size():
			return a.member_ids.size() > b.member_ids.size()
		return a.group_id < b.group_id)
	var other_groups: Array[EntityGroup] = []
	for g in all_groups:
		if (g as EntityGroup).group_id != _selected_group_id:
			other_groups.append(g as EntityGroup)

	var has_split  := selected.member_ids.size() >= 2
	var has_absorb := not other_groups.is_empty()

	if not has_split and not has_absorb:
		_restructure_box.visible = false
		return

	_restructure_box.visible = true

	var header := Label.new()
	header.text = "─ Restructure ─"
	header.add_theme_font_size_override("font_size", 11)
	header.add_theme_color_override("font_color", Color(0.55, 0.55, 0.70))
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_restructure_box.add_child(header)

	if has_split:
		for i in selected.member_ids.size():
			var mid := selected.member_ids[i]
			var ch  := _find_character(mid)
			var name := ch.display_name if ch != null else "Entity %d" % mid
			var row := HBoxContainer.new()
			row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.set_meta("split_idx", i)
			var lbl := Label.new()
			lbl.text = name
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			lbl.add_theme_font_size_override("font_size", 11)
			lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
			lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(lbl)
			var btn := Button.new()
			btn.text = "Split ↑"
			btn.flat = true
			btn.custom_minimum_size = Vector2(58, 0)
			btn.add_theme_font_size_override("font_size", 11)
			btn.mouse_filter = Control.MOUSE_FILTER_STOP
			btn.pressed.connect(_on_split_member.bind(selected.group_id, mid))
			row.add_child(btn)
			_restructure_box.add_child(row)

	if has_absorb:
		var absorb_lbl := Label.new()
		absorb_lbl.text = "Absorb:"
		absorb_lbl.add_theme_font_size_override("font_size", 11)
		absorb_lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.70))
		absorb_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_restructure_box.add_child(absorb_lbl)
		for i in other_groups.size():
			var og := other_groups[i]
			var row := HBoxContainer.new()
			row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.set_meta("absorb_idx", i)
			var lbl := Label.new()
			lbl.text = _group_display_name(og)
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			lbl.add_theme_font_size_override("font_size", 11)
			lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
			lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(lbl)
			var btn := Button.new()
			btn.text = "← Absorb"
			btn.flat = true
			btn.custom_minimum_size = Vector2(68, 0)
			btn.add_theme_font_size_override("font_size", 11)
			btn.mouse_filter = Control.MOUSE_FILTER_STOP
			btn.pressed.connect(_on_absorb_group.bind(og.group_id))
			row.add_child(btn)
			_restructure_box.add_child(row)


func _on_split_member(group_id: int, member_id: int) -> void:
	EntityRegistry.split_member(group_id, member_id)


func _on_absorb_group(absorb_id: int) -> void:
	EntityRegistry.merge_groups(absorb_id, _selected_group_id)


func _group_display_name(group: EntityGroup) -> String:
	if group.is_solo() and group.display_name == "":
		var ch := _find_character(group.member_ids[0])
		return ch.display_name if ch != null else "Entity %d" % group.member_ids[0]
	var base := group.display_name if group.display_name != "" else "Group %d" % group.group_id
	if group.is_solo():
		return base
	return "%s  (%d)" % [base, group.member_ids.size()]


# The editable text shown in the LineEdit — always the raw group name, never
# the character name fallback, so renaming a solo group sets display_name.
func _group_edit_name(group: EntityGroup) -> String:
	if group.display_name != "":
		return group.display_name
	if group.is_solo():
		var ch := _find_character(group.member_ids[0])
		return ch.display_name if ch != null else ""
	return ""


func _start_rename(group_id: int) -> void:
	_editing_group_id = group_id
	_selected_group_id = group_id
	_rebuild_group_rows()


func _commit_rename(new_name: String, group_id: int) -> void:
	if _editing_group_id != group_id:
		return  # already committed (e.g. Enter fired before focus_exited)
	var group := EntityRegistry.get_group(group_id)
	if group != null:
		group.display_name = new_name.strip_edges()
		var manifest := WorldManager._manifest
		if manifest != null:
			manifest.save(manifest.get_save_path())
	_editing_group_id = -1
	call_deferred("_rebuild_group_rows")


func _commit_rename_from_focus(edit: LineEdit, group_id: int) -> void:
	_commit_rename(edit.text, group_id)


func _command_summary(cmd) -> String:
	if cmd == null:
		return "Idle"
	var tc := cmd as TravelCommand
	if tc == null:
		return "Command queued"
	match tc.termination:
		TravelCommand.Termination.DESTINATION:
			return "→ %s" % str(tc.destination_chunk)
		TravelCommand.Termination.DISTANCE:
			var dist_km := tc.distance_m / 1000.0
			return "March  %.1f km" % dist_km
	return "Command queued"


func _find_character(char_id: int) -> Character:
	var manifest := WorldManager._manifest
	if manifest == null:
		return null
	for c in manifest.characters:
		var ch := c as Character
		if ch.character_id == char_id:
			return ch
	return null


# -----------------------------------------------------------------------
# Row selection
# -----------------------------------------------------------------------

func _on_row_gui_input(event: InputEvent, group_id: int) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		_select_group(group_id)
		get_viewport().set_input_as_handled()


func _select_group(group_id: int) -> void:
	_selected_group_id = group_id
	var group := EntityRegistry.get_group(group_id)
	if group != null and group.anchor_entity >= 0:
		EntityRegistry.set_selected(group.anchor_entity)
	_rebuild_group_rows()


func get_selected_group_id() -> int:
	return _selected_group_id


# -----------------------------------------------------------------------
# Execute / Continue button
# -----------------------------------------------------------------------

func _on_execute_pressed() -> void:
	if TurnManager.phase == TurnManager.Phase.REVIEW:
		TurnManager.end_review()
	else:
		TurnManager.set_peer_ready(NetworkManager.local_peer_id, true)


# -----------------------------------------------------------------------
# Signal handlers
# -----------------------------------------------------------------------

func _on_phase_changed(_turn_type: int, phase: int) -> void:
	match phase:
		TurnManager.Phase.PLANNING:
			_panel.visible = true
			_phase_label.text = "PLANNING"
			_phase_label.add_theme_color_override("font_color", Color(0.50, 1.00, 0.50))
			_execute_btn.text = "Execute"
			_execute_btn.disabled = false
			_rebuild_group_rows()
		TurnManager.Phase.RESOLUTION:
			_panel.visible = false
		TurnManager.Phase.REVIEW:
			_panel.visible = true
			_phase_label.text = "REVIEW"
			_phase_label.add_theme_color_override("font_color", Color(1.00, 0.80, 0.30))
			_execute_btn.text = "Continue"
			_execute_btn.disabled = false
			_rebuild_group_rows()


func _on_command_submitted(group_id: int) -> void:
	# Refresh just the affected row's command summary.
	for row in _group_list.get_children():
		if not row.has_meta("group_id"):
			continue
		if int(row.get_meta("group_id")) != group_id:
			continue
		var group := EntityRegistry.get_group(group_id)
		if group == null:
			return
		var col := row.get_child(0) as VBoxContainer
		if col == null or col.get_child_count() < 2:
			return
		var cmd = TurnManager.get_pending_command(group_id)
		var cmd_lbl := col.get_child(1) as Label
		if cmd_lbl == null:
			return
		cmd_lbl.text = _command_summary(cmd)
		cmd_lbl.add_theme_color_override("font_color",
			Color(0.50, 0.90, 0.50) if cmd != null else Color(0.45, 0.45, 0.50))
		return


func _on_peer_ready_changed(peer_id: int, is_ready: bool) -> void:
	if peer_id != NetworkManager.local_peer_id:
		return
	_execute_btn.disabled = is_ready
	if is_ready:
		_execute_btn.text = "Waiting..."


func _on_group_loaded(_group_id: int) -> void:
	call_deferred("_rebuild_group_rows")


func _on_groups_cleared() -> void:
	_selected_group_id = -1
	call_deferred("_rebuild_group_rows")


func _on_group_restructured(_group_id: int) -> void:
	# If the selected group was absorbed, it no longer exists.
	if EntityRegistry.get_group(_selected_group_id) == null:
		_selected_group_id = -1
	call_deferred("_rebuild_group_rows")


# -----------------------------------------------------------------------
# Debug
# -----------------------------------------------------------------------

func _notify_screen_ready() -> void:
	if not OS.is_debug_build():
		return
	var nodes: Array = [{"id": "phase_label", "node": _phase_label},
						{"id": "execute_btn", "node": _execute_btn}]
	var row_idx := 0
	for i in _group_list.get_child_count():
		var row := _group_list.get_child(i)
		if row.is_queued_for_deletion():
			continue
		nodes.append({"id": "group_row_%d" % row_idx, "node": row})
		# Expose rename button or active LineEdit inside the row.
		var col := row.get_child(0) if row.get_child_count() > 0 else null
		if col == null:
			row_idx += 1
			continue
		var name_row := col.get_child(0) if col.get_child_count() > 0 else null
		if name_row == null:
			row_idx += 1
			continue
		for child in name_row.get_children():
			if child is LineEdit:
				nodes.append({"id": "rename_edit_%d" % row_idx, "node": child})
			elif child is Button:
				nodes.append({"id": "rename_btn_%d" % row_idx, "node": child})
		row_idx += 1
	# Expose restructure buttons.
	for child in _restructure_box.get_children():
		if child.is_queued_for_deletion() or not (child is HBoxContainer):
			continue
		if child.has_meta("split_idx"):
			var idx := int(child.get_meta("split_idx"))
			for btn in child.get_children():
				if btn is Button:
					nodes.append({"id": "split_%d" % idx, "node": btn})
		elif child.has_meta("absorb_idx"):
			var idx := int(child.get_meta("absorb_idx"))
			for btn in child.get_children():
				if btn is Button:
					nodes.append({"id": "absorb_%d" % idx, "node": btn})
	DebugBridge.screen_ready("GameWorld", "CommandPanel", nodes, {"group_count": row_idx})
