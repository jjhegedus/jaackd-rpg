class_name CreatureType
extends Resource

@export var type_name: String = ""
@export var is_humanoid: bool = false
@export var description: String = ""

@export var base_stats: CharacterStats
@export var behavior_profile: BehaviorProfile

# Viewshed range in meters
@export var viewshed_range: float = 80.0

# Loot table resource path; empty = no loot
@export var loot_table_path: String = ""


func _init() -> void:
	base_stats = CharacterStats.new()
	behavior_profile = BehaviorProfile.new()


func create_instance_stats(rng: RandomNumberGenerator) -> CharacterStats:
	# Returns a slightly varied copy of base_stats for a spawned instance
	var s := CharacterStats.new()
	s.strength = base_stats.strength + rng.randi_range(-2, 2)
	s.dexterity = base_stats.dexterity + rng.randi_range(-2, 2)
	s.constitution = base_stats.constitution + rng.randi_range(-2, 2)
	s.intelligence = base_stats.intelligence + rng.randi_range(-2, 2)
	s.wisdom = base_stats.wisdom + rng.randi_range(-2, 2)
	s.charisma = base_stats.charisma + rng.randi_range(-2, 2)
	s.max_health = s.constitution + rng.randi_range(1, 8)
	s.current_health = s.max_health
	s.movement_speed = base_stats.movement_speed
	return s
