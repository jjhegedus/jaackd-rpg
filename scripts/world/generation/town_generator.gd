class_name TownGenerator
extends RefCounted

const TARGET_POPULATION_MIN := 50
const TARGET_POPULATION_MAX := 60
const MAX_FAMILIES := 6
const CHILD_MAX_PER_FAMILY := 4

# Business definitions: role → {building, min_age, max_age, count}
const BUSINESSES := {
	"inn_and_tavern": {
		"roles": [
			{role = "innkeeper",    min_age = 35, max_age = 60, count = 1},
			{role = "inn_server",   min_age = 17, max_age = 30, count = 2},
			{role = "cook",         min_age = 25, max_age = 55, count = 1},
		]
	},
	"church": {
		"roles": [
			{role = "priest",       min_age = 40, max_age = 70, count = 1},
			{role = "acolyte",      min_age = 15, max_age = 25, count = 2},
		]
	},
	"blacksmith": {
		"roles": [
			{role = "blacksmith",   min_age = 30, max_age = 60, count = 1},
			{role = "apprentice",   min_age = 13, max_age = 20, count = 1},
		]
	},
	"general_store": {
		"roles": [
			{role = "merchant",     min_age = 30, max_age = 60, count = 1},
			{role = "shop_assistant", min_age = 16, max_age = 35, count = 1},
		]
	},
	"herbalist": {
		"roles": [
			{role = "herbalist",    min_age = 35, max_age = 65, count = 1},
			{role = "apprentice",   min_age = 15, max_age = 30, count = 1},
		]
	},
	"stable": {
		"roles": [
			{role = "stable_master", min_age = 25, max_age = 55, count = 1},
			{role = "stable_hand",   min_age = 14, max_age = 25, count = 2},
		]
	},
}

const INDEPENDENT_ROLES := [
	{role = "farmer",        min_age = 20, max_age = 65},
	{role = "carpenter",     min_age = 25, max_age = 60},
	{role = "town_guard",    min_age = 20, max_age = 45},
	{role = "elder",         min_age = 60, max_age = 80},
]

var _rng: RandomNumberGenerator
var _backstory_gen: BackstoryGenerator
var _next_id: int = 0


func generate(seed: int, town_name: String) -> Array[Character]:
	_rng = RandomNumberGenerator.new()
	_rng.seed = seed
	_backstory_gen = BackstoryGenerator.new()
	_next_id = 0

	var characters: Array[Character] = []

	# Step 1: families
	var family_count := _rng.randi_range(4, MAX_FAMILIES)
	var family_id := 0
	for _f in family_count:
		var family := _generate_family(family_id, town_name)
		characters.append_array(family)
		family_id += 1

	# Step 2: business roles (fill from unassigned adults)
	var unassigned := characters.filter(func(c): return c.town_role == &"")
	_assign_business_roles(characters, unassigned)

	# Step 3: fill remaining business slots with new characters
	_fill_missing_business_roles(characters, town_name)

	# Step 4: independents to reach target population
	var target := _rng.randi_range(TARGET_POPULATION_MIN, TARGET_POPULATION_MAX)
	while characters.size() < target:
		var role_def: Dictionary = INDEPENDENT_ROLES[_rng.randi() % INDEPENDENT_ROLES.size()]
		var c := _new_character(
			town_name,
			_rng.randi_range(role_def.min_age, role_def.max_age),
			role_def.role
		)
		characters.append(c)

	return characters


# --- Family generation ---

func _generate_family(family_id: int, town_name: String) -> Array[Character]:
	var members: Array[Character] = []

	# Parents
	var parent_a_age := _rng.randi_range(25, 55)
	var parent_b_age := clampi(parent_a_age + _rng.randi_range(-10, 10), 20, 65)

	var parent_a := _new_character(town_name, parent_a_age, "farmer")
	var parent_b := _new_character(town_name, parent_b_age, "farmer")
	parent_a.family_id = family_id
	parent_b.family_id = family_id
	parent_a.family_role = &"parent"
	parent_b.family_role = &"parent"
	parent_a.relationships[parent_b.character_id] = &"spouse"
	parent_b.relationships[parent_a.character_id] = &"spouse"

	# 10% chance one parent is deceased (widowed household — still generate the character
	# as alive in game; "widowed" is just a backstory note)
	var is_widowed := _rng.randf() < 0.10

	members.append(parent_a)
	if not is_widowed:
		members.append(parent_b)

	# Children — age constrained to at most (younger parent age - 15)
	var youngest_parent_age := mini(parent_a_age, parent_b_age)
	var max_child_age := youngest_parent_age - 15
	if max_child_age >= 1:
		var child_count := _rng.randi_range(1, CHILD_MAX_PER_FAMILY)
		for _c in child_count:
			var child_age := _rng.randi_range(0, max_child_age)
			var child := _new_character(town_name, child_age, "child" if child_age < 13 else "")
			child.family_id = family_id
			child.family_role = &"child"
			child.relationships[parent_a.character_id] = &"parent"
			child.relationships[parent_b.character_id] = &"parent"
			parent_a.relationships[child.character_id] = &"child"
			parent_b.relationships[child.character_id] = &"child"
			members.append(child)

	# 15% chance: elderly grandparent lives with this family
	if _rng.randf() < 0.15:
		var elder_age := _rng.randi_range(62, 80)
		var grandparent := _new_character(town_name, elder_age, "elder")
		grandparent.family_id = family_id
		grandparent.family_role = &"grandparent"
		members.append(grandparent)

	return members


# --- Business role assignment ---

func _assign_business_roles(all_chars: Array[Character],
		candidates: Array) -> void:
	for building in BUSINESSES:
		for role_def in BUSINESSES[building].roles:
			for _i in role_def.count:
				var match_idx := _find_candidate(
					candidates, role_def.min_age, role_def.max_age
				)
				if match_idx >= 0:
					var c: Character = candidates[match_idx]
					c.town_role = StringName(role_def.role)
					c.workplace_building = StringName(building)
					candidates.remove_at(match_idx)


func _find_candidate(candidates: Array, min_age: int, max_age: int) -> int:
	for i in candidates.size():
		var c: Character = candidates[i]
		if c.age >= min_age and c.age <= max_age and c.town_role == &"":
			return i
	return -1


func _fill_missing_business_roles(all_chars: Array[Character],
		town_name: String) -> void:
	for building in BUSINESSES:
		for role_def in BUSINESSES[building].roles:
			# Count how many of this role exist for this building
			var existing := all_chars.filter(func(c):
				return c.town_role == StringName(role_def.role) \
					and c.workplace_building == StringName(building)
			)
			var deficit: int = role_def.count - existing.size()
			for _i in deficit:
				var age := _rng.randi_range(role_def.min_age, role_def.max_age)
				var c := _new_character(town_name, age, role_def.role)
				c.workplace_building = StringName(building)
				all_chars.append(c)


# --- Character factory ---

func _new_character(town_name: String, age: int, role: String) -> Character:
	var c := Character.new()
	c.character_id = _next_id
	_next_id += 1
	c.age = age
	c.town_role = StringName(role)

	c.display_name = _generate_name()
	c.appearance.randomize_from_rng(_rng)
	c.stats.randomize_from_rng(_rng)
	c.behavior_profile = BehaviorProfile.for_humanoid(_rng)

	c.backstory_seed = _backstory_gen.generate(c, town_name, _rng)
	c.player_selectable = false   # townspeople are NPCs, not player-commanded

	return c


func get_next_id() -> int:
	return _next_id


# Creates a player-selectable adventurer character (not a townsperson).
func create_adventurer(id: int, role: String, rng: RandomNumberGenerator) -> Character:
	var c := Character.new()
	c.character_id = id
	c.display_name = _generate_name()
	c.town_role = StringName(role)
	c.age = rng.randi_range(20, 35)
	c.player_selectable = true
	c.alive = true
	c.stats.randomize_from_rng(rng)
	c.appearance.randomize_from_rng(rng)
	return c


func _generate_name() -> String:
	const FIRST_NAMES := [
		"Aldric", "Mira", "Tor", "Kess", "Davan", "Oryn", "Sera", "Bram",
		"Lysa", "Conn", "Veld", "Asha", "Nile", "Rue", "Garn", "Hella",
		"Idris", "Wren", "Cael", "Fenn", "Petra", "Rook", "Dahl", "Ives",
		"Maren", "Sable", "Tomas", "Una", "Vesper", "Wulf", "Yara", "Zev",
		"Ander", "Brix", "Cora", "Drex", "Elsa", "Fiona", "Gale", "Holt",
		"Ivy", "Jorn", "Kira", "Lore", "Mace", "Nora", "Oswin", "Pell",
		"Quinn", "Rand", "Soli", "Tave", "Urso", "Vane", "Ward", "Xara"
	]
	const SURNAMES := [
		"Aldren", "Cross", "Vale", "Marsh", "Holt", "Stone", "Wren",
		"Fell", "Graves", "Bright", "Thorn", "Black", "Grey", "Ash",
		"Drake", "Ford", "Glen", "Hart", "Isle", "Knowe", "Lane",
		"Moor", "Nash", "Oakes", "Penn", "Reed", "Shaw", "Teal",
		"Underwood", "Vane", "Wood", "York"
	]
	var first: String = FIRST_NAMES[_rng.randi() % FIRST_NAMES.size()]
	var last: String = SURNAMES[_rng.randi() % SURNAMES.size()]
	return first + " " + last
