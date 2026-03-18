class_name ViewLayout
extends CanvasLayer

# Displays a small mode indicator in the top-right corner so the player
# always knows which view is active.
#
# GameWorld calls set_mode() when the player presses Tab.

enum Mode { TACTICAL_FULL, ENTITY }

var _mode: Mode = Mode.TACTICAL_FULL
var _indicator: Label


func _ready() -> void:
	layer = 10
	_build_indicator()
	_apply_mode()


func set_mode(mode: Mode) -> void:
	if mode == _mode:
		return
	_mode = mode
	_apply_mode()


func get_mode() -> Mode:
	return _mode


# -----------------------------------------------------------------------
# Indicator label
# -----------------------------------------------------------------------

func _build_indicator() -> void:
	_indicator = Label.new()
	_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	var settings := LabelSettings.new()
	settings.font_color = Color(0.9, 0.9, 0.9, 0.75)
	settings.font_size = 12
	settings.shadow_color = Color(0.0, 0.0, 0.0, 0.6)
	settings.shadow_offset = Vector2(1.0, 1.0)
	_indicator.label_settings = settings

	add_child(_indicator)
	_reposition_indicator()


func _apply_mode() -> void:
	match _mode:
		Mode.TACTICAL_FULL:
			_indicator.text = "TACTICAL VIEW"
		Mode.ENTITY:
			_indicator.text = "ENTITY VIEW"


func _reposition_indicator() -> void:
	var vp_w := get_viewport().get_visible_rect().size.x
	_indicator.position = Vector2(vp_w - 160.0, 8.0)
	_indicator.custom_minimum_size = Vector2(150.0, 0.0)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_SIZE_CHANGED:
		_reposition_indicator()
