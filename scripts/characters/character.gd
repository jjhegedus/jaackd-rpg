class_name Character
extends Resource

# --- Controller ---
enum Controller { UNASSIGNED, PLAYER, WM, AI }

# --- Identity ---
@export var character_id: int = -1
@export var display_name: String = ""
@export var age: int = 0

# --- Appearance & Stats ---
@export var appearance: AppearanceData
@export var stats: CharacterStats

# null = human; set for creatures/animals
@export var creature_type: CreatureType

@export var behavior_profile: BehaviorProfile

# --- Family & Social ---
@export var family_id: int = -1  # -1 = no family unit
@export var family_role: StringName = &""  # "parent", "child", "spouse", "grandparent"

# key: character_id (int), value: relationship StringName
# e.g. {3: &"spouse", 7: &"child", 12: &"employer"}
@export var relationships: Dictionary = {}

# --- Role in world ---
@export var faction: StringName = &""
@export var town_role: StringName = &""       # "innkeeper", "blacksmith", "farmer", etc.
@export var home_building: StringName = &""
@export var workplace_building: StringName = &""

# --- World position ---
@export var world_chunk_face: int = 0
@export var world_chunk_x: int = 0
@export var world_chunk_y: int = 0
@export var local_pos: Vector3 = Vector3.ZERO

# --- Group membership ---
# The EntityGroup this entity belongs to. -1 = not yet assigned.
# Every entity is always in exactly one group; solo entities are in a
# solo group (size == 1). Set by WorldManifest.ensure_solo_groups().
@export var group_id: int = -1

# --- Control ---
@export var controller: Controller = Controller.UNASSIGNED
@export var controller_id: int = -1  # network peer ID; -1 if AI/unassigned

# --- Session ---
@export var alive: bool = true
# peer IDs that have encountered this character in play
@export var known_by: Array[int] = []
# default false; must be explicitly set true for adventurers / player-owned entities
@export var player_selectable: bool = false

# --- Backstory ---
# Seed-generated text. Shown if backstory_override is empty.
@export_multiline var backstory_seed: String = ""
# WM full replacement. If non-empty, shown instead of backstory_seed.
@export_multiline var backstory_override: String = ""
# WM additions always appended to whichever backstory is shown.
@export_multiline var backstory_notes: String = ""


func _init() -> void:
	appearance = AppearanceData.new()
	stats = CharacterStats.new()
	behavior_profile = BehaviorProfile.new()


func get_backstory() -> String:
	var base := backstory_override if backstory_override != "" else backstory_seed
	if backstory_notes != "":
		return base + "\n\n" + backstory_notes
	return base


func is_human() -> bool:
	return creature_type == null


func get_display_role() -> String:
	if town_role != &"":
		return str(town_role).capitalize()
	if creature_type != null:
		return creature_type.type_name
	return "Traveler"
