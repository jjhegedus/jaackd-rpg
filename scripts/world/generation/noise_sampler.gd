class_name NoiseSampler
extends RefCounted

# Layered FastNoiseLite sampler.
# get_height() returns metres relative to sea level: 0 = sea surface, negative = below.

const DEFAULT_MAX_HEIGHT_M := 4000.0  # meters above sea level at max noise
const SEA_LEVEL_FRACTION := 0.35      # fraction of max height treated as sea level

var _base_noise: FastNoiseLite
var _detail_noise: FastNoiseLite
var _moisture_noise: FastNoiseLite
var max_height_m: float = DEFAULT_MAX_HEIGHT_M


func setup(seed: int) -> void:
	# Continental shape — large features
	_base_noise = FastNoiseLite.new()
	_base_noise.seed = seed
	_base_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_base_noise.frequency = 0.00002
	_base_noise.fractal_octaves = 6
	_base_noise.fractal_lacunarity = 2.0
	_base_noise.fractal_gain = 0.5

	# Ridge/detail layer
	_detail_noise = FastNoiseLite.new()
	_detail_noise.seed = seed + 1
	_detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_detail_noise.frequency = 0.0002
	_detail_noise.fractal_octaves = 4
	_detail_noise.fractal_lacunarity = 2.2
	_detail_noise.fractal_gain = 0.45
	_detail_noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED

	# Moisture map (independent seed offset)
	_moisture_noise = FastNoiseLite.new()
	_moisture_noise.seed = seed + 9973
	_moisture_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_moisture_noise.frequency = 0.00003
	_moisture_noise.fractal_octaves = 4


# Returns elevation in metres relative to sea level.
# 0 = sea surface, negative = below sea, positive = above sea.
# world_x, world_z in meters from planet centre projection.
func get_height(world_x: float, world_z: float) -> float:
	var base: float = _base_noise.get_noise_2d(world_x, world_z)       # [-1, 1]
	var detail: float = _detail_noise.get_noise_2d(world_x, world_z)   # [-1, 1]

	# Combine: base drives continent/ocean split, detail adds ridges
	var combined: float = base * 0.7 + detail * 0.3
	# Remap [-1,1] → [0,1]
	combined = (combined + 1.0) * 0.5
	# Apply a slight continent bias (push values toward ocean or land)
	combined = pow(combined, 0.85)
	# Subtract sea level so 0 = sea surface in world space.
	return combined * max_height_m - get_sea_level_m()


# Returns moisture in [0, 1].
func get_moisture(world_x: float, world_z: float) -> float:
	var m: float = _moisture_noise.get_noise_2d(world_x, world_z)
	return (m + 1.0) * 0.5


# The absolute height offset that maps noise output to sea level = 0.
# Use this for normalisation; do NOT compare raw heights against this.
func get_sea_level_m() -> float:
	return max_height_m * SEA_LEVEL_FRACTION
