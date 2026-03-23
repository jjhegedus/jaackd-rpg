class_name MapRenderer
extends RefCounted

# Renders a single regional ChunkData into an RGB8 Image.
# One pixel = one terrain cell.  Fog states applied per cell:
#   Visible    → full terrain colour
#   Remembered → desaturated terrain colour
#   Unknown    → black

# Altitude stops and colours matching terrain_chunk_mesh.gd
const STOPS: Array = [-200.0, 0.0, 4.0, 40.0, 1100.0, 2200.0, 3500.0]
const COLORS: Array = [
	Color(0.04, 0.12, 0.55),  # deep ocean
	Color(0.10, 0.45, 0.85),  # shallow water
	Color(0.90, 0.82, 0.45),  # sand / coast
	Color(0.18, 0.72, 0.12),  # lowland grass
	Color(0.22, 0.58, 0.10),  # highland meadow
	Color(0.55, 0.38, 0.20),  # bare rock
	Color(0.95, 0.97, 1.00),  # snow / ice
]

# How much to desaturate Remembered cells (0 = no change, 1 = full greyscale).
const DESATURATE_AMOUNT := 0.85


static func render_chunk(
		chunk: ChunkData,
		explored: PackedByteArray,
		visible: PackedByteArray) -> Image:
	var w   := chunk.cells_x
	var h   := chunk.cells_y
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)

	for y in h:
		for x in w:
			var idx    := y * w + x
			var height := chunk.base_heightmap[idx] if idx < chunk.base_heightmap.size() else 0.0
			var base   := _height_color(height)

			var is_vis := idx < visible.size()  and visible[idx]  != 0
			var is_exp := idx < explored.size() and explored[idx] != 0

			var color: Color
			if is_vis:
				color = base
			elif is_exp:
				color = _desaturate(base, DESATURATE_AMOUNT)
			else:
				color = Color.BLACK

			img.set_pixel(x, y, color)

	return img


static func _height_color(height_m: float) -> Color:
	if height_m <= STOPS[0]:
		return COLORS[0]
	for i in range(STOPS.size() - 1):
		if height_m <= STOPS[i + 1]:
			var t := (height_m - float(STOPS[i])) / (float(STOPS[i + 1]) - float(STOPS[i]))
			return (COLORS[i] as Color).lerp(COLORS[i + 1], t)
	return COLORS[COLORS.size() - 1]


# Lerp toward greyscale by luminance.
static func _desaturate(color: Color, amount: float) -> Color:
	var lum := color.r * 0.299 + color.g * 0.587 + color.b * 0.114
	return color.lerp(Color(lum, lum, lum), amount)
