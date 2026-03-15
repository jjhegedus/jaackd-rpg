class_name SessionManager
extends Node

# SessionManager — handles character assignment at session start.
#
# Flow:
#   1. Host loads a WorldManifest (which contains all Characters).
#   2. Players join and see the selectable characters near the starting point.
#   3. Players claim characters in join order.
#   4. If a human WM is present, they claim last and get all remaining characters.
#   5. If no WM, all unclaimed characters go to AIController.
#
# After assignment the session begins. During play:
#   - A player whose character dies may claim any character in their known_by list.
#   - New characters encountered during play are added to the claimable pool on death.

signal character_claimed(character_id: int, peer_id: int)
signal session_ready(assignments: Dictionary)  # peer_id → Array[int] (character_ids)

enum Phase { WAITING, SELECTING, ACTIVE }

var phase: Phase = Phase.WAITING
var manifest: WorldManifest
var assignments: Dictionary = {}    # peer_id (int) → Array[int] (character_ids)
var wm_peer_id: int = -1            # -1 = no human WM (AI handles all unclaimed)
var _pending_selection: Array = []  # peer IDs waiting to select, in order


func setup(p_manifest: WorldManifest, wm_id: int = -1) -> void:
	manifest = p_manifest
	wm_peer_id = wm_id
	assignments.clear()
	phase = Phase.WAITING


# Begin the selection phase. Call after all players have joined.
func start_selection(peer_ids_in_order: Array[int]) -> void:
	phase = Phase.SELECTING
	_pending_selection = peer_ids_in_order.duplicate()
	# Remove WM from normal selection order — they go last.
	if wm_peer_id >= 0 and _pending_selection.has(wm_peer_id):
		_pending_selection.erase(wm_peer_id)


# Returns the characters available for a given peer to select.
# Only includes selectable characters near the starting point and not yet claimed.
func available_for(peer_id: int) -> Array[Character]:
	var claimed_ids := _all_claimed_ids()
	var result: Array[Character] = []
	for c in manifest.characters:
		if not c.player_selectable:
			continue
		if claimed_ids.has(c.character_id):
			continue
		result.append(c)
	return result


# A player claims a character. Server-authoritative.
func claim_character(peer_id: int, character_id: int) -> bool:
	# Validate
	var c := _find_character(character_id)
	if c == null or not c.player_selectable:
		return false
	if _all_claimed_ids().has(character_id):
		return false

	if not assignments.has(peer_id):
		assignments[peer_id] = []
	assignments[peer_id].append(character_id)
	c.controller = Character.Controller.PLAYER
	c.controller_id = peer_id
	character_claimed.emit(character_id, peer_id)

	# Advance selection queue
	if _pending_selection.size() > 0 and _pending_selection[0] == peer_id:
		_pending_selection.pop_front()

	return true


# Called after all players have selected. Assigns remaining characters.
func finalize_assignments() -> void:
	var unclaimed := _unclaimed_characters()

	if wm_peer_id >= 0:
		# Human WM gets all remaining.
		if not assignments.has(wm_peer_id):
			assignments[wm_peer_id] = []
		for c in unclaimed:
			assignments[wm_peer_id].append(c.character_id)
			c.controller = Character.Controller.WM
			c.controller_id = wm_peer_id
	else:
		# No WM — all unclaimed go to AI.
		for c in unclaimed:
			c.controller = Character.Controller.AI
			c.controller_id = -1

	phase = Phase.ACTIVE
	session_ready.emit(assignments)


# After a character dies, the player may claim a character they've encountered.
func claim_on_death(dead_peer_id: int, new_character_id: int) -> bool:
	var c := _find_character(new_character_id)
	if c == null:
		return false
	# Must have been encountered by this peer's previous characters.
	if not c.known_by.has(dead_peer_id):
		return false
	if _all_claimed_ids().has(new_character_id):
		return false
	return claim_character(dead_peer_id, new_character_id)


# Mark a character as encountered by a peer (expands future death-claim pool).
func mark_encountered(character_id: int, peer_id: int) -> void:
	var c := _find_character(character_id)
	if c and not c.known_by.has(peer_id):
		c.known_by.append(peer_id)


# --- Helpers ---

func _all_claimed_ids() -> Array:
	var ids: Array = []
	for peer_id in assignments:
		ids.append_array(assignments[peer_id])
	return ids


func _unclaimed_characters() -> Array[Character]:
	var claimed := _all_claimed_ids()
	var result: Array[Character] = []
	for c in manifest.characters:
		if not claimed.has(c.character_id):
			result.append(c)
	return result


func _find_character(character_id: int) -> Character:
	for c in manifest.characters:
		if c.character_id == character_id:
			return c
	return null
