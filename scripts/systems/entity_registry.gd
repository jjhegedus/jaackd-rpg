extends Node

# Registry of all active entities in the current game session.
# Autoloaded as EntityRegistry.
#
# Tracks world positions, faction, and UI selection state for every
# entity currently in play. The source of truth for:
#   - TravelSimulation  → detection sweep target lists
#   - TacticalCamera    → player/zoom bounding box for framing
#   - ViewLayout        → which entity's first-person to show
#   - TurnManager       → entity positions when issuing commands

# -----------------------------------------------------------------------
# Signals
# -----------------------------------------------------------------------

signal entity_registered(character_id: int)
signal entity_unregistered(character_id: int)
signal position_updated(character_id: int, world_pos: Vector3)
signal selection_changed(character_id: int, is_selected: bool)
signal zoom_group_changed(character_id: int, in_zoom: bool)
signal faction_changed(character_id: int, faction: StringName)
signal group_loaded(group_id: int)
signal groups_cleared
signal group_restructured(group_id: int)

# -----------------------------------------------------------------------
# Inner type
# -----------------------------------------------------------------------

class EntityRecord:
	var character_id: int = -1
	var world_pos: Vector3 = Vector3.ZERO
	var faction: StringName = &""   # &"player", &"enemy", &"neutral"
	var is_selected: bool = false   # yellow — drives first-person viewport
	var in_zoom: bool = false       # blue — included in zoomed overhead

# -----------------------------------------------------------------------
# State
# -----------------------------------------------------------------------

var _entities: Dictionary = {}        # int (character_id) → EntityRecord
var _selected_id: int = -1             # at most one entity is yellow at a time

var _groups: Dictionary = {}           # int (group_id) → EntityGroup
var _entity_to_group: Dictionary = {}  # int (character_id) → int (group_id)

# -----------------------------------------------------------------------
# Registration
# -----------------------------------------------------------------------

func register(character_id: int, world_pos: Vector3, faction: StringName) -> void:
	if _entities.has(character_id):
		return
	var rec := EntityRecord.new()
	rec.character_id = character_id
	rec.world_pos = world_pos
	rec.faction = faction
	_entities[character_id] = rec
	entity_registered.emit(character_id)


func set_faction(character_id: int, new_faction: StringName) -> void:
	var rec := _entities.get(character_id) as EntityRecord
	if rec == null or rec.faction == new_faction:
		return
	rec.faction = new_faction
	faction_changed.emit(character_id, new_faction)


func unregister(character_id: int) -> void:
	if not _entities.has(character_id):
		return
	if _selected_id == character_id:
		_selected_id = -1
	_entities.erase(character_id)
	entity_unregistered.emit(character_id)


func update_position(character_id: int, new_pos: Vector3) -> void:
	var rec := _entities.get(character_id) as EntityRecord
	if rec == null:
		return
	rec.world_pos = new_pos
	position_updated.emit(character_id, new_pos)


# -----------------------------------------------------------------------
# Selection — yellow (single; drives first-person viewport)
# -----------------------------------------------------------------------

func set_selected(character_id: int) -> void:
	if _selected_id == character_id:
		return
	if _selected_id >= 0 and _entities.has(_selected_id):
		(_entities[_selected_id] as EntityRecord).is_selected = false
		selection_changed.emit(_selected_id, false)
	_selected_id = character_id
	if character_id >= 0 and _entities.has(character_id):
		(_entities[character_id] as EntityRecord).is_selected = true
		selection_changed.emit(character_id, true)


func clear_selection() -> void:
	set_selected(-1)


func get_selected_id() -> int:
	return _selected_id


func get_selected_pos() -> Vector3:
	if _selected_id < 0:
		return Vector3.ZERO
	var rec := _entities.get(_selected_id) as EntityRecord
	return rec.world_pos if rec != null else Vector3.ZERO


# -----------------------------------------------------------------------
# Zoom group — blue (multiple; defines zoomed overhead bounding box)
# -----------------------------------------------------------------------

func add_to_zoom(character_id: int) -> void:
	var rec := _entities.get(character_id) as EntityRecord
	if rec == null or rec.in_zoom:
		return
	rec.in_zoom = true
	zoom_group_changed.emit(character_id, true)


func remove_from_zoom(character_id: int) -> void:
	var rec := _entities.get(character_id) as EntityRecord
	if rec == null or not rec.in_zoom:
		return
	rec.in_zoom = false
	zoom_group_changed.emit(character_id, false)


# Replace the entire zoom group with the given id list.
func set_zoom_group(ids: Array[int]) -> void:
	for id in _entities:
		var rec := _entities[id] as EntityRecord
		if rec.in_zoom and not ids.has(id):
			rec.in_zoom = false
			zoom_group_changed.emit(id, false)
	for id in ids:
		add_to_zoom(id)


func get_zoom_group() -> Array[int]:
	var result: Array[int] = []
	for id in _entities:
		if (_entities[id] as EntityRecord).in_zoom:
			result.append(id)
	return result


# -----------------------------------------------------------------------
# Bounding boxes — used by TacticalCamera for framing
# -----------------------------------------------------------------------

# AABB of the zoom-group entities (blue). Empty AABB if group is empty.
func get_zoom_bounds() -> AABB:
	var positions: Array[Vector3] = []
	for id in _entities:
		var rec := _entities[id] as EntityRecord
		if rec.in_zoom:
			positions.append(rec.world_pos)
	return _positions_to_aabb(positions)


# AABB of all player-controlled entities. Used for global overhead framing.
func get_player_bounds() -> AABB:
	var positions: Array[Vector3] = []
	for id in _entities:
		var rec := _entities[id] as EntityRecord
		if rec.faction == &"player_party":
			positions.append(rec.world_pos)
	return _positions_to_aabb(positions)


# -----------------------------------------------------------------------
# Queries
# -----------------------------------------------------------------------

func get_entity(character_id: int) -> EntityRecord:
	return _entities.get(character_id) as EntityRecord


func get_entity_pos(character_id: int) -> Vector3:
	var rec := _entities.get(character_id) as EntityRecord
	return rec.world_pos if rec != null else Vector3.ZERO


func get_all_ids() -> Array[int]:
	var result: Array[int] = []
	for id in _entities:
		result.append(id)
	return result


func get_ids_by_faction(faction: StringName) -> Array[int]:
	var result: Array[int] = []
	for id in _entities:
		if (_entities[id] as EntityRecord).faction == faction:
			result.append(id)
	return result


func get_player_ids() -> Array[int]:
	return get_ids_by_faction(&"player_party")


func get_enemy_ids() -> Array[int]:
	return get_ids_by_faction(&"enemy")


# Entities within range_m of world_pos (ignoring Y), optionally by faction.
func get_nearby(world_pos: Vector3, range_m: float,
		faction: StringName = &"") -> Array[int]:
	var result: Array[int] = []
	var range_sq := range_m * range_m
	for id in _entities:
		var rec := _entities[id] as EntityRecord
		if faction != &"" and rec.faction != faction:
			continue
		var diff := rec.world_pos - world_pos
		diff.y = 0.0
		if diff.length_squared() <= range_sq:
			result.append(id)
	return result


# Build a target list for DetectionSystem.sweep() from enemy entities near pos.
# chunk_size_m and cell_size_m are needed to convert world → chunk-local cell coords.
func build_detection_targets(
		near_pos: Vector3,
		range_m: float,
		chunk_size_m: float,
		cell_size_m: float,
		default_concealment: float = 0.0) -> Array:

	var ids := get_nearby(near_pos, range_m, &"enemy")
	var targets: Array = []
	for id in ids:
		var rec := _entities[id] as EntityRecord
		var local_x := fmod(rec.world_pos.x, chunk_size_m)
		var local_z := fmod(rec.world_pos.z, chunk_size_m)
		if local_x < 0.0:
			local_x += chunk_size_m
		if local_z < 0.0:
			local_z += chunk_size_m
		targets.append({
			"id":            id,
			"x":             int(local_x / cell_size_m),
			"y":             int(local_z / cell_size_m),
			"concealment":   default_concealment,
			"height_offset": 1.7,  # DetectionSystem.EYE_HEIGHT_STANDING
		})
	return targets


func get_player_positions() -> Array[Vector3]:
	var result: Array[Vector3] = []
	for id in _entities:
		var rec := _entities[id] as EntityRecord
		if rec.faction == &"player_party":
			result.append(rec.world_pos)
	return result


# -----------------------------------------------------------------------
# Groups
# -----------------------------------------------------------------------

# Load all groups from the manifest at session start.
func load_groups(manifest_groups: Array[EntityGroup]) -> void:
	_groups.clear()
	_entity_to_group.clear()
	for g in manifest_groups:
		var eg := g as EntityGroup
		_groups[eg.group_id] = eg
		for mid in eg.member_ids:
			_entity_to_group[mid] = eg.group_id
		group_loaded.emit(eg.group_id)


func get_group(group_id: int) -> EntityGroup:
	return _groups.get(group_id) as EntityGroup


# Returns the group that contains this entity, or null if not found.
func get_group_for_entity(character_id: int) -> EntityGroup:
	var gid: int = _entity_to_group.get(character_id, -1)
	if gid == -1:
		return null
	return _groups.get(gid) as EntityGroup


func get_all_groups() -> Array[EntityGroup]:
	var result: Array[EntityGroup] = []
	for g in _groups.values():
		result.append(g as EntityGroup)
	return result


# Returns all groups owned by the given peer (-1 = unclaimed groups).
func get_groups_by_owner(owner_peer_id: int) -> Array[EntityGroup]:
	var result: Array[EntityGroup] = []
	for g in _groups.values():
		var eg := g as EntityGroup
		if eg.owner_peer_id == owner_peer_id:
			result.append(eg)
	return result


func get_group_count() -> int:
	return _groups.size()


# -----------------------------------------------------------------------
# Group restructuring (PLANNING phase only)
# -----------------------------------------------------------------------

# Move all members of absorb_group into into_group, then remove absorb_group.
# Clears any pending command on the absorbed group.
func merge_groups(absorb_id: int, into_id: int) -> void:
	if absorb_id == into_id:
		return
	var absorb := _groups.get(absorb_id) as EntityGroup
	var into   := _groups.get(into_id)   as EntityGroup
	if absorb == null or into == null:
		return
	for mid in absorb.member_ids:
		into.member_ids.append(mid)
		_entity_to_group[mid] = into_id
	if into.anchor_entity < 0 and not absorb.member_ids.is_empty():
		into.anchor_entity = absorb.member_ids[0]
	# Union known_chunks — both sides retain all exploration knowledge.
	for coord in absorb.known_chunks:
		if not into.known_chunks.has(coord):
			into.known_chunks.append(coord)
	TurnManager.clear_command(absorb_id)
	_groups.erase(absorb_id)
	var manifest := WorldManager._manifest
	if manifest != null:
		for i in manifest.groups.size():
			if (manifest.groups[i] as EntityGroup).group_id == absorb_id:
				manifest.groups.remove_at(i)
				break
		manifest.save(manifest.get_save_path())
	group_restructured.emit(into_id)


# Split member_id out of its group into a new solo group owned by the same peer.
# Returns the new group_id, or -1 on failure.
func split_member(group_id: int, member_id: int) -> int:
	var group := _groups.get(group_id) as EntityGroup
	if group == null or not group.member_ids.has(member_id):
		return -1
	if group.member_ids.size() <= 1:
		return -1
	var manifest := WorldManager._manifest
	if manifest == null:
		return -1
	group.member_ids.erase(member_id)
	if group.anchor_entity == member_id:
		group.anchor_entity = group.member_ids[0]
	var new_group := EntityGroup.new()
	new_group.group_id      = manifest.next_group_id
	manifest.next_group_id += 1
	new_group.display_name  = ""
	new_group.owner_peer_id = group.owner_peer_id
	new_group.member_ids    = [member_id]
	new_group.anchor_entity = member_id
	new_group.known_chunks  = group.known_chunks.duplicate()
	_groups[new_group.group_id] = new_group
	_entity_to_group[member_id] = new_group.group_id
	manifest.groups.append(new_group)
	manifest.save(manifest.get_save_path())
	group_restructured.emit(new_group.group_id)
	return new_group.group_id


# -----------------------------------------------------------------------
# Session lifecycle
# -----------------------------------------------------------------------

# Call when loading a new world or returning to main menu.
func clear() -> void:
	_entities.clear()
	_selected_id = -1
	_groups.clear()
	_entity_to_group.clear()
	groups_cleared.emit()


# -----------------------------------------------------------------------
# Internal
# -----------------------------------------------------------------------

func _positions_to_aabb(positions: Array[Vector3]) -> AABB:
	if positions.is_empty():
		return AABB()
	var mn := positions[0]
	var mx := positions[0]
	for p in positions:
		mn = Vector3(minf(mn.x, p.x), minf(mn.y, p.y), minf(mn.z, p.z))
		mx = Vector3(maxf(mx.x, p.x), maxf(mx.y, p.y), maxf(mx.z, p.z))
	return AABB(mn, mx - mn)
