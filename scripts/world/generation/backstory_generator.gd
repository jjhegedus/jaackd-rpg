class_name BackstoryGenerator
extends RefCounted

const TEMPLATE_DIR := "res://data/backstory_templates/"

# Cache loaded templates
var _templates: Dictionary = {}  # role String → parsed JSON Dictionary


func generate(character: Character, town_name: String, rng: RandomNumberGenerator) -> String:
	var role := str(character.town_role)
	var tmpl := _get_template(role)
	if tmpl.is_empty():
		tmpl = _get_template("default")
	if tmpl.is_empty():
		return ""

	var templates: Array = tmpl.get("templates", [])
	if templates.is_empty():
		return ""

	var chosen: String = str(templates[rng.randi() % templates.size()])
	return _fill(chosen, character, town_name, tmpl, rng)


func _fill(template: String, c: Character,
		town_name: String, data: Dictionary, rng: RandomNumberGenerator) -> String:
	var pronoun := _pronoun(c)
	var pronoun_pos := _pronoun_possessive(c)
	var pronoun_obj := _pronoun_object(c)
	var pronoun_cap := pronoun.capitalize()
	var pronoun_pos_cap := pronoun_pos.capitalize()

	var years := _years_in_role(c, rng)

	# Pick personality line based on first trait
	var personality_line := ""
	if not c.behavior_profile.personality_traits.is_empty():
		var trait_key := str(c.behavior_profile.personality_traits[0])
		var lines: Dictionary = data.get("personality_lines", {})
		if lines.has(trait_key):
			personality_line = str(lines[trait_key])
		else:
			# fallback to any available line
			var keys: Array = lines.keys()
			if not keys.is_empty():
				personality_line = str(lines[keys[rng.randi() % keys.size()]])

	var hooks: Array = data.get("hooks", [])
	var hook: String = str(hooks[rng.randi() % hooks.size()]) if not hooks.is_empty() else ""

	var origin: String = ""
	var origins: Array = data.get("origins", [])
	if not origins.is_empty():
		origin = str(origins[rng.randi() % origins.size()])

	var predecessor: String = ""
	var predecessors: Array = data.get("predecessors", [])
	if not predecessors.is_empty():
		predecessor = str(predecessors[rng.randi() % predecessors.size()])

	var business := _business_name(c)

	var result := template
	result = result.replace("{name}", c.display_name)
	result = result.replace("{town}", town_name)
	result = result.replace("{business}", business)
	result = result.replace("{years}", str(years))
	result = result.replace("{pronoun}", pronoun)
	result = result.replace("{pronoun_pos}", pronoun_pos)
	result = result.replace("{pronoun_obj}", pronoun_obj)
	result = result.replace("{pronoun_cap}", pronoun_cap)
	result = result.replace("{pronoun_pos_cap}", pronoun_pos_cap)
	result = result.replace("{origin}", origin)
	result = result.replace("{predecessor}", predecessor)
	result = result.replace("{personality_line}", personality_line)
	result = result.replace("{hook}", hook)

	# Recurse: personality_line and hook may themselves contain tokens
	# (one extra pass is sufficient)
	result = result.replace("{name}", c.display_name)
	result = result.replace("{pronoun}", pronoun)
	result = result.replace("{pronoun_pos}", pronoun_pos)
	result = result.replace("{pronoun_obj}", pronoun_obj)
	result = result.replace("{pronoun_cap}", pronoun_cap)
	result = result.replace("{business}", business)
	result = result.replace("{town}", town_name)

	return result


func _get_template(role: String) -> Dictionary:
	if _templates.has(role):
		return _templates[role]
	var path := TEMPLATE_DIR + role.replace(" ", "_") + ".json"
	if ResourceLoader.exists(path):
		var file := FileAccess.open(path, FileAccess.READ)
		if file:
			var json := JSON.new()
			if json.parse(file.get_as_text()) == OK:
				_templates[role] = json.data
				return json.data
	_templates[role] = {}
	return {}


func _pronoun(c: Character) -> String:
	# Deterministic from character_id until a gender field is added.
	# "he" and "she" share the same verb forms the templates were written for.
	return "he" if c.character_id % 2 == 0 else "she"


func _pronoun_possessive(c: Character) -> String:
	return "his" if c.character_id % 2 == 0 else "her"


func _pronoun_object(c: Character) -> String:
	return "him" if c.character_id % 2 == 0 else "her"


func _years_in_role(c: Character, rng: RandomNumberGenerator) -> int:
	var working_age := maxi(c.age - 16, 1)
	return rng.randi_range(1, working_age)


func _business_name(c: Character) -> String:
	if c.workplace_building != &"":
		return str(c.workplace_building).replace("_", " ").capitalize()
	return "the shop"
