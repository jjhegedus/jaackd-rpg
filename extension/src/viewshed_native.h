#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>

namespace godot {

class ViewshedNative : public RefCounted {
    GDCLASS(ViewshedNative, RefCounted)

protected:
    static void _bind_methods();

public:
    // Full viewshed — mirrors ViewshedSystem.compute() in GDScript.
    // Returns PackedByteArray: 1 = visible, 0 = not visible.
    static PackedByteArray compute(
        const PackedFloat32Array &heightmap,
        int width, int height,
        int obs_x, int obs_y,
        float obs_height_offset,
        int max_range_cells,
        float cell_size_m);

private:
    static bool has_los(
        const PackedFloat32Array &heightmap,
        int width, int height,
        int ox, int oy, float obs_h,
        int tx, int ty,
        float cell_size_m);

    // Integer-cell lookup (used for observer and target heights).
    static float sample(
        const PackedFloat32Array &heightmap,
        int width, int height,
        int x, int y);

    // Bilinear interpolation — used for intermediate ray samples to avoid
    // staircase blocking on steep slopes.
    static float sample_bilinear(
        const PackedFloat32Array &heightmap,
        int width, int height,
        float x, float y);
};

} // namespace godot
