class_name CharacterStats
extends Resource

@export var strength: int = 10
@export var dexterity: int = 10
@export var constitution: int = 10
@export var intelligence: int = 10
@export var wisdom: int = 10
@export var charisma: int = 10

@export var max_health: int = 10
@export var current_health: int = 10
@export var movement_speed: float = 5.0

const BASE_STAT := 10
const STAT_MIN := 3
const STAT_MAX := 18


func randomize_from_rng(rng: RandomNumberGenerator) -> void:
	strength = _roll_stat(rng)
	dexterity = _roll_stat(rng)
	constitution = _roll_stat(rng)
	intelligence = _roll_stat(rng)
	wisdom = _roll_stat(rng)
	charisma = _roll_stat(rng)
	max_health = constitution + rng.randi_range(1, 8)
	current_health = max_health


func _roll_stat(rng: RandomNumberGenerator) -> int:
	# Roll 4d6 drop lowest
	var rolls: Array[int] = []
	for i in 4:
		rolls.append(rng.randi_range(1, 6))
	rolls.sort()
	return rolls[1] + rolls[2] + rolls[3]
