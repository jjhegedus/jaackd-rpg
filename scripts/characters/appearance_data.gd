class_name AppearanceData
extends Resource

enum SkinTone { FAIR, LIGHT, MEDIUM, OLIVE, TAN, BROWN, DARK }
enum HairColor { BLACK, DARK_BROWN, BROWN, AUBURN, BLONDE, RED, GREY, WHITE }
enum HairLength { BALD, SHORT, MEDIUM, LONG }
enum EyeColor { BROWN, HAZEL, BLUE, GREEN, GREY, AMBER }
enum BuildType { SLIGHT, LEAN, AVERAGE, STOCKY, HEAVY }

@export var skin_tone: SkinTone = SkinTone.MEDIUM
@export var hair_color: HairColor = HairColor.BROWN
@export var hair_length: HairLength = HairLength.MEDIUM
@export var eye_color: EyeColor = EyeColor.BROWN
@export var build: BuildType = BuildType.AVERAGE
@export var height_cm: int = 170  # stored in cm
@export var distinguishing_features: String = ""


func randomize_from_rng(rng: RandomNumberGenerator) -> void:
	skin_tone = rng.randi_range(0, SkinTone.size() - 1) as SkinTone
	hair_color = rng.randi_range(0, HairColor.size() - 1) as HairColor
	hair_length = rng.randi_range(0, HairLength.size() - 1) as HairLength
	eye_color = rng.randi_range(0, EyeColor.size() - 1) as EyeColor
	build = rng.randi_range(0, BuildType.size() - 1) as BuildType
	height_cm = rng.randi_range(155, 195)


func get_description() -> String:
	var skin_name: String = str(SkinTone.keys()[skin_tone]).to_lower().replace("_", " ")
	var hair_name: String = str(HairColor.keys()[hair_color]).to_lower().replace("_", " ")
	var hair_len: String = str(HairLength.keys()[hair_length]).to_lower()
	var eye_name: String = str(EyeColor.keys()[eye_color]).to_lower()
	var build_name: String = str(BuildType.keys()[build]).to_lower()
	var height_ft := "%.0f'%.0f\"" % [height_cm / 30.48, fmod(height_cm / 2.54, 12.0)]
	return "%s, %s with %s %s hair and %s eyes, %s build" % [
		height_ft, skin_name, hair_len, hair_name, eye_name, build_name
	]
