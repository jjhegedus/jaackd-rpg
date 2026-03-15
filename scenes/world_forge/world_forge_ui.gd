class_name WorldForgeUI
extends Control

# Panels
@onready var setup_panel: VBoxContainer = $SetupPanel
@onready var forge_panel: VBoxContainer = $ForgePanel
@onready var people_panel: VBoxContainer = $PeoplePanel
@onready var creatures_panel: VBoxContainer = $CreaturesPanel

# Setup panel controls
@onready var world_name_input: LineEdit = $SetupPanel/WorldNameInput
@onready var town_name_input: LineEdit = $SetupPanel/TownNameInput
@onready var seed_input: SpinBox = $SetupPanel/SeedInput
@onready var randomize_seed_btn: Button = $SetupPanel/RandomizeSeedBtn
@onready var forge_btn: Button = $SetupPanel/ForgeBtn
@onready var disk_label: Label = $SetupPanel/DiskLabel

# Forge progress panel
@onready var progress_bar: ProgressBar = $ForgePanel/ProgressBar
@onready var status_label: Label = $ForgePanel/StatusLabel

# People panel controls
@onready var people_list: ItemList = $PeoplePanel/PeopleList
@onready var name_input: LineEdit = $PeoplePanel/Scroll/CharacterEditor/NameInput
@onready var age_input: SpinBox = $PeoplePanel/Scroll/CharacterEditor/AgeInput
@onready var role_option: OptionButton = $PeoplePanel/Scroll/CharacterEditor/RoleOption
@onready var selectable_check: CheckBox = $PeoplePanel/Scroll/CharacterEditor/SelectableCheck
@onready var backstory_seed_label: TextEdit = $PeoplePanel/Scroll/CharacterEditor/BackstorySeedLabel
@onready var backstory_override_input: TextEdit = $PeoplePanel/Scroll/CharacterEditor/BackstoryOverrideInput
@onready var backstory_notes_input: TextEdit = $PeoplePanel/Scroll/CharacterEditor/BackstoryNotesInput
@onready var add_person_btn: Button = $PeoplePanel/AddPersonBtn

# Creature types panel
@onready var creature_list: ItemList = $CreaturesPanel/CreatureList
@onready var creature_name_input: LineEdit = $CreaturesPanel/CreatureEditor/NameInput
@onready var creature_humanoid_check: CheckBox = $CreaturesPanel/CreatureEditor/HumanoidCheck
@onready var creature_viewshed_input: SpinBox = $CreaturesPanel/CreatureEditor/ViewshedInput
@onready var creature_desc_input: TextEdit = $CreaturesPanel/CreatureEditor/DescInput
@onready var add_creature_btn: Button = $CreaturesPanel/AddCreatureBtn

const ALL_ROLES: Array[String] = [
	"innkeeper", "inn_server", "cook",
	"priest", "acolyte",
	"blacksmith", "apprentice",
	"merchant", "shop_assistant",
	"herbalist",
	"stable_master", "stable_hand",
	"farmer", "carpenter", "town_guard", "elder",
	"child", "other",
]

var _forge: WorldForge
var _backstory_gen: BackstoryGenerator
var _characters: Array[Character] = []
var _creature_types: Array[CreatureType] = []
var _selected_char_idx: int = -1
var _selected_creature_idx: int = -1
var _forge_world_name: String = ""


func _ready() -> void:
	_forge = WorldForge.new()
	add_child(_forge)
	_backstory_gen = BackstoryGenerator.new()
	_forge.progress_updated.connect(_on_progress_updated)
	_forge.forge_completed.connect(_on_forge_completed)
	_forge.forge_failed.connect(_on_forge_failed)

	randomize_seed_btn.pressed.connect(_randomize_seed)
	forge_btn.pressed.connect(_start_forge)
	add_person_btn.pressed.connect(_add_person)
	add_creature_btn.pressed.connect(_add_creature)
	people_list.item_selected.connect(_on_person_selected)
	creature_list.item_selected.connect(_on_creature_selected)

	# Wire People panel buttons
	$PeoplePanel/Scroll/CharacterEditor/ApplyBtn.pressed.connect(_apply_char_edits)
	$PeoplePanel/Scroll/CharacterEditor/GenBackstoryBtn.pressed.connect(_generate_backstory)
	$PeoplePanel/NavBar/PeopleToSetupBtn.pressed.connect(func(): _save_edits(); _go_main_menu())
	$PeoplePanel/NavBar/PeopleToCreaturesBtn.pressed.connect(func(): _show_panel(creatures_panel))

	# Wire Creatures panel buttons
	$CreaturesPanel/NavBar/CreaturesToSetupBtn.pressed.connect(func(): _save_edits(); _go_main_menu())
	$CreaturesPanel/NavBar/CreaturesToPeopleBtn.pressed.connect(func(): _show_panel(people_panel))

	# Populate role dropdown
	role_option.clear()
	for r in ALL_ROLES:
		role_option.add_item(r.replace("_", " ").capitalize())

	# Wire Setup panel navigation
	$SetupPanel/BackBtn.pressed.connect(_go_main_menu)

	# Wire Forge panel navigation
	$ForgePanel/BackBtn.pressed.connect(_go_main_menu)

	_update_disk_label()

	# Edit mode: skip setup, load existing world directly into People panel.
	if WorldManager.edit_world_name != "":
		_enter_edit_mode(WorldManager.edit_world_name)
		WorldManager.edit_world_name = ""
	else:
		_show_panel(setup_panel)


func _update_disk_label() -> void:
	var free_gb := DiskManager.get_free_bytes() / (1024.0 * 1024.0 * 1024.0)
	var fraction := DiskManager.get_free_fraction() * 100.0
	disk_label.text = "Free disk: %.1f GB (%.0f%%)" % [free_gb, fraction]
	disk_label.modulate = Color.RED if fraction < 30.0 else Color.WHITE


func _randomize_seed() -> void:
	seed_input.value = randi()


func _start_forge() -> void:
	var world_name := world_name_input.text.strip_edges()
	if world_name == "":
		_show_error("World name cannot be empty.")
		return

	if not DiskManager.can_write(500 * 1024 * 1024):  # 500 MB estimate
		_show_error("Not enough free disk space to create a new world.")
		return

	_forge_world_name = world_name
	_show_panel(forge_panel)
	progress_bar.value = 0.0
	status_label.text = "Starting…"

	_forge.start_forge(
		world_name,
		town_name_input.text.strip_edges(),
		int(seed_input.value),
		0, 8, 8  # default start: face 0, chunk (8,8) near planet centre
	)


func _on_progress_updated(fraction: float, status: String) -> void:
	progress_bar.value = fraction * 100.0
	status_label.text = status
	if OS.is_debug_build():
		DebugBridge.log_progress(fraction, status)


func _on_forge_completed(manifest: WorldManifest) -> void:
	_characters.assign(manifest.characters)
	_refresh_people_list()
	status_label.text = "World '%s' created! %d townsfolk generated." \
		% [manifest.world_name, _characters.size()]
	# Show people panel so WM can review and edit
	_show_panel(people_panel)


func _on_forge_failed(reason: String) -> void:
	status_label.text = "FAILED: " + reason
	_show_error(reason)
	if OS.is_debug_build():
		DebugBridge.log_error(reason)


# --- People panel ---

func _refresh_people_list() -> void:
	people_list.clear()
	for c in _characters:
		var lock_icon := " [locked]" if not c.player_selectable else ""
		people_list.add_item(
			"%s  |  Age %d  |  %s%s" % [c.display_name, c.age, c.get_display_role(), lock_icon]
		)


func _on_person_selected(idx: int) -> void:
	_selected_char_idx = idx
	var c: Character = _characters[idx]
	name_input.text = c.display_name
	age_input.value = c.age
	selectable_check.button_pressed = c.player_selectable
	backstory_seed_label.text = c.backstory_seed
	backstory_override_input.text = c.backstory_override
	backstory_notes_input.text = c.backstory_notes
	# Populate role option (simplified — full list populated in scene)
	_set_role_option(c.town_role)


func _set_role_option(role: StringName) -> void:
	for i in role_option.item_count:
		if ALL_ROLES[i] == str(role):
			role_option.select(i)
			return


func _apply_char_edits() -> void:
	if _selected_char_idx < 0:
		return
	var c: Character = _characters[_selected_char_idx]
	c.display_name = name_input.text.strip_edges()
	c.age = int(age_input.value)
	c.player_selectable = selectable_check.button_pressed
	c.backstory_override = backstory_override_input.text
	c.backstory_notes = backstory_notes_input.text
	var role_idx: int = role_option.selected
	if role_idx >= 0 and role_idx < ALL_ROLES.size():
		c.town_role = StringName(ALL_ROLES[role_idx])
	_refresh_people_list()


func _generate_backstory() -> void:
	if _selected_char_idx < 0:
		return
	var c: Character = _characters[_selected_char_idx]
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var town_name: String = _forge.current_manifest.starting_town_name \
		if _forge.current_manifest else _forge_world_name
	var generated: String = _backstory_gen.generate(c, town_name, rng)
	backstory_seed_label.text = generated
	c.backstory_seed = generated


func _add_person() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var entered_name := name_input.text.strip_edges()
	var c := Character.new()
	c.character_id = _characters.size()
	c.display_name = entered_name if entered_name != "" else "New Person"
	c.age = int(age_input.value)
	var role_idx: int = role_option.selected
	c.town_role = StringName(ALL_ROLES[role_idx]) if role_idx >= 0 else &"farmer"
	c.stats.randomize_from_rng(rng)
	c.appearance.randomize_from_rng(rng)
	c.behavior_profile = BehaviorProfile.for_humanoid(rng)
	_characters.append(c)
	_refresh_people_list()
	people_list.select(_characters.size() - 1)
	_on_person_selected(_characters.size() - 1)


# --- Creature types panel ---

func _refresh_creature_list() -> void:
	creature_list.clear()
	for ct in _creature_types:
		creature_list.add_item(
			"%s  |  %s  |  Viewshed %.0fm" % [
				ct.type_name,
				"Humanoid" if ct.is_humanoid else "Creature",
				ct.viewshed_range
			]
		)


func _on_creature_selected(idx: int) -> void:
	_selected_creature_idx = idx
	var ct: CreatureType = _creature_types[idx]
	creature_name_input.text = ct.type_name
	creature_humanoid_check.button_pressed = ct.is_humanoid
	creature_viewshed_input.value = ct.viewshed_range
	creature_desc_input.text = ct.description


func _add_creature() -> void:
	var ct := CreatureType.new()
	ct.type_name = "New Creature"
	ct.viewshed_range = 80.0
	_creature_types.append(ct)
	_refresh_creature_list()
	creature_list.select(_creature_types.size() - 1)
	_on_creature_selected(_creature_types.size() - 1)


# --- Edit mode ---

func _enter_edit_mode(world_name: String) -> void:
	var path := DiskManager.manifest_path(world_name)
	var manifest := WorldManifest.load_from(path)
	if manifest == null:
		_show_panel(setup_panel)
		return
	_forge.current_manifest = manifest
	_forge_world_name = world_name
	_characters.assign(manifest.characters)
	_refresh_people_list()
	_show_panel(people_panel)


func _save_edits() -> void:
	if _forge.current_manifest == null:
		return
	_forge.current_manifest.characters.assign(_characters)
	_forge.current_manifest.forge_version = WorldManifest.CURRENT_FORGE_VERSION
	var path := DiskManager.manifest_path(_forge.current_manifest.world_name)
	ResourceSaver.save(_forge.current_manifest, path)


# --- Helpers ---

func _go_main_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


func _show_panel(panel: Control) -> void:
	for p in [setup_panel, forge_panel, people_panel, creatures_panel]:
		if p != null:
			p.visible = (p == panel)
	if OS.is_debug_build():
		_debug_register_panel(panel)


func _debug_register_panel(panel: Control) -> void:
	var nodes: Array = []
	if panel == setup_panel:
		nodes = [
			{"id": "WorldNameInput",   "node": world_name_input},
			{"id": "TownNameInput",    "node": town_name_input},
			{"id": "SeedInput",        "node": seed_input},
			{"id": "RandomizeSeedBtn", "node": randomize_seed_btn},
			{"id": "ForgeBtn",         "node": forge_btn},
			{"id": "BackBtn",          "node": $SetupPanel/BackBtn},
		]
	elif panel == forge_panel:
		nodes = [
			{"id": "BackBtn", "node": $ForgePanel/BackBtn},
		]
	elif panel == people_panel:
		nodes = [
			{"id": "PeopleList",         "node": people_list},
			{"id": "NameInput",          "node": name_input},
			{"id": "AgeInput",           "node": age_input},
			{"id": "RoleOption",         "node": role_option},
			{"id": "AddPersonBtn",       "node": add_person_btn},
			{"id": "ApplyBtn",           "node": $PeoplePanel/Scroll/CharacterEditor/ApplyBtn},
			{"id": "GenBackstoryBtn",    "node": $PeoplePanel/Scroll/CharacterEditor/GenBackstoryBtn},
			{"id": "PeopleToSetupBtn",   "node": $PeoplePanel/NavBar/PeopleToSetupBtn},
			{"id": "PeopleToCreaturesBtn", "node": $PeoplePanel/NavBar/PeopleToCreaturesBtn},
		]
	elif panel == creatures_panel:
		nodes = [
			{"id": "CreatureList",       "node": creature_list},
			{"id": "CreatureNameInput",  "node": creature_name_input},
			{"id": "AddCreatureBtn",     "node": add_creature_btn},
			{"id": "CreaturesToSetupBtn",  "node": $CreaturesPanel/NavBar/CreaturesToSetupBtn},
			{"id": "CreaturesToPeopleBtn", "node": $CreaturesPanel/NavBar/CreaturesToPeopleBtn},
		]
	DebugBridge.screen_ready("WorldForge", panel.name, nodes)


func _show_error(msg: String) -> void:
	push_warning("WorldForge UI error: " + msg)
	if status_label:
		status_label.text = "Error: " + msg
