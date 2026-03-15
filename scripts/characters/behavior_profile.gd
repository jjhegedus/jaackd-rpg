class_name BehaviorProfile
extends Resource

enum Disposition { AGGRESSIVE, TERRITORIAL, CAUTIOUS, NEUTRAL, FRIENDLY, COWARDLY }
enum CombatStyle { MELEE, RANGED, FLEE, SUPPORT, AMBUSH }
enum SocialTendency { SOLITARY, PAIR, SMALL_GROUP, LARGE_GROUP, HERD }

@export var disposition: Disposition = Disposition.NEUTRAL
@export var combat_style: CombatStyle = CombatStyle.MELEE
@export var social_tendency: SocialTendency = SocialTendency.SOLITARY

# 0.0–1.0: likelihood of fleeing when health drops below flee_threshold
@export var flee_threshold: float = 0.25
@export var flee_probability: float = 0.5

# How far this creature will pursue a target before giving up (in meters)
@export var pursuit_range: float = 50.0

# Personality traits (for humanoids; ignored for simple creatures)
@export var personality_traits: Array[StringName] = []


static func for_humanoid(rng: RandomNumberGenerator) -> BehaviorProfile:
	var p := BehaviorProfile.new()
	p.disposition = Disposition.NEUTRAL
	p.combat_style = CombatStyle.MELEE
	p.social_tendency = SocialTendency.SMALL_GROUP
	p.flee_threshold = rng.randf_range(0.1, 0.4)
	p.flee_probability = rng.randf_range(0.3, 0.8)
	p.pursuit_range = rng.randf_range(30.0, 100.0)
	var all_traits: Array[StringName] = [
		&"brave", &"cautious", &"greedy", &"generous", &"curious",
		&"suspicious", &"loyal", &"mercenary", &"pious", &"cynical",
		&"cheerful", &"melancholy", &"hot-tempered", &"patient", &"ambitious"
	]
	# Pick 2 traits
	all_traits.shuffle()
	p.personality_traits = [all_traits[0], all_traits[1]]
	return p
