class_name ContourLineGenerator
extends RefCounted

# Generates elevation contour line segments from a heightmap using the
# marching squares algorithm.
#
# Output: Dictionary{ float threshold → PackedVector2Array }
# Each PackedVector2Array contains consecutive pairs of points (segment start,
# segment end) in local pixel coordinates (0..cells_x, 0..cells_y).

# Default elevation thresholds in metres.
const DEFAULT_THRESHOLDS: Array = [0.0, 100.0, 300.0, 700.0, 1500.0, 2500.0]


static func generate(chunk: ChunkData, thresholds: Array = DEFAULT_THRESHOLDS) -> Dictionary:
	var result := {}
	var w    := chunk.cells_x
	var h    := chunk.cells_y
	var hmap := chunk.base_heightmap

	if hmap.is_empty() or w < 2 or h < 2:
		return result

	for threshold in thresholds:
		result[threshold] = _march(hmap, w, h, float(threshold))

	return result


static func _march(hmap: PackedFloat32Array, w: int, h: int, threshold: float) -> PackedVector2Array:
	var segments := PackedVector2Array()

	for row in range(h - 1):
		for col in range(w - 1):
			var tl := hmap[row * w + col]
			var tr := hmap[row * w + col + 1]
			var bl := hmap[(row + 1) * w + col]
			var br := hmap[(row + 1) * w + col + 1]

			# 4-bit case index: bit3=TL bit2=TR bit1=BL bit0=BR (1 = above threshold)
			var case_idx := 0
			if tl >= threshold: case_idx |= 8
			if tr >= threshold: case_idx |= 4
			if bl >= threshold: case_idx |= 2
			if br >= threshold: case_idx |= 1

			if case_idx == 0 or case_idx == 15:
				continue

			# Crossing positions on each edge (pixel space, within this cell)
			var p_top    := Vector2(col + _t(tl, tr, threshold), float(row))
			var p_right  := Vector2(float(col + 1),              row + _t(tr, br, threshold))
			var p_bottom := Vector2(col + _t(bl, br, threshold), float(row + 1))
			var p_left   := Vector2(float(col),                  row + _t(tl, bl, threshold))

			# Standard marching squares lookup — one or two segments per cell.
			# Cases 6 and 9 are saddle points; disambiguation favours the
			# "same-side" pairing (adequate for topographic display).
			match case_idx:
				1:  segments.append_array([p_bottom, p_right])
				2:  segments.append_array([p_left,   p_bottom])
				3:  segments.append_array([p_left,   p_right])
				4:  segments.append_array([p_top,    p_right])
				5:  segments.append_array([p_top,    p_bottom])
				6:  segments.append_array([p_top, p_right, p_left, p_bottom])
				7:  segments.append_array([p_top,    p_left])
				8:  segments.append_array([p_left,   p_top])
				9:  segments.append_array([p_left, p_top, p_bottom, p_right])
				10: segments.append_array([p_top,    p_bottom])
				11: segments.append_array([p_top,    p_right])
				12: segments.append_array([p_left,   p_right])
				13: segments.append_array([p_left,   p_bottom])
				14: segments.append_array([p_bottom, p_right])

	return segments


# Returns the interpolation parameter where the value crosses threshold
# between corner values a and b.  Returns 0.5 for degenerate edges.
static func _t(a: float, b: float, threshold: float) -> float:
	if absf(b - a) < 0.0001:
		return 0.5
	return clampf((threshold - a) / (b - a), 0.0, 1.0)
