#include "viewshed_native.h"
#include <godot_cpp/core/class_db.hpp>
#include <cmath>
#include <algorithm>

namespace godot {

void ViewshedNative::_bind_methods() {
    ClassDB::bind_static_method("ViewshedNative",
        D_METHOD("compute",
            "heightmap", "width", "height",
            "obs_x", "obs_y",
            "obs_height_offset", "max_range_cells", "cell_size_m"),
        &ViewshedNative::compute);
}


PackedByteArray ViewshedNative::compute(
        const PackedFloat32Array &heightmap,
        int width, int height,
        int obs_x, int obs_y,
        float obs_height_offset,
        int max_range_cells,
        float cell_size_m) {

    PackedByteArray result;
    result.resize(width * height);
    memset(result.ptrw(), 0, width * height);

    float obs_terrain_h = sample(heightmap, width, height, obs_x, obs_y);
    float obs_h         = obs_terrain_h + obs_height_offset;

    // Observer's own cell is always visible.
    result.set(obs_y * width + obs_x, 1);

    int max_r2 = max_range_cells * max_range_cells;
    int y_min  = std::max(0,          obs_y - max_range_cells);
    int y_max  = std::min(height - 1, obs_y + max_range_cells);
    int x_min  = std::max(0,          obs_x - max_range_cells);
    int x_max  = std::min(width  - 1, obs_x + max_range_cells);

    // Cells within this squared radius are always visible (avoids R3 staircase).
    const int GUARANTEED_VISIBLE_R2 = 9; // 3-cell radius

    for (int ty = y_min; ty <= y_max; ++ty) {
        for (int tx = x_min; tx <= x_max; ++tx) {
            if (tx == obs_x && ty == obs_y) continue;

            int dx = tx - obs_x;
            int dy = ty - obs_y;
            int r2 = dx * dx + dy * dy;
            if (r2 > max_r2) continue;

            if (r2 <= GUARANTEED_VISIBLE_R2 ||
                has_los(heightmap, width, height,
                        obs_x, obs_y, obs_h,
                        tx, ty, cell_size_m)) {
                result.set(ty * width + tx, 1);
            }
        }
    }

    return result;
}


bool ViewshedNative::has_los(
        const PackedFloat32Array &heightmap,
        int width, int height,
        int ox, int oy, float obs_h,
        int tx, int ty,
        float cell_size_m) {

    int dx    = tx - ox;
    int dy    = ty - oy;
    int steps = std::max(std::abs(dx), std::abs(dy));
    if (steps == 0) return true;

    float fdx = (float)dx;
    float fdy = (float)dy;
    float dist_to_target = std::sqrt(fdx * fdx + fdy * fdy) * cell_size_m;
    float target_h       = sample(heightmap, width, height, tx, ty);
    float target_slope   = (target_h - obs_h) / dist_to_target;

    float max_slope = -1e30f;

    for (int i = 1; i < steps; ++i) {
        float t   = (float)i / (float)steps;
        float fcx = ox + fdx * t;
        float fcy = oy + fdy * t;
        float cell_h = sample_bilinear(heightmap, width, height, fcx, fcy);
        float cdx    = fcx - (float)ox;
        float cdy    = fcy - (float)oy;
        float dist   = std::sqrt(cdx * cdx + cdy * cdy) * cell_size_m;
        if (dist > 0.0f) {
            float slope = (cell_h - obs_h) / dist;
            if (slope > max_slope) max_slope = slope;
        }
    }

    return target_slope >= max_slope;
}


float ViewshedNative::sample(
        const PackedFloat32Array &heightmap,
        int width, int height,
        int x, int y) {

    if (x < 0 || x >= width || y < 0 || y >= height) return 0.0f;
    return heightmap[y * width + x];
}


float ViewshedNative::sample_bilinear(
        const PackedFloat32Array &heightmap,
        int width, int height,
        float x, float y) {

    int x0 = std::clamp((int)x,     0, width  - 1);
    int y0 = std::clamp((int)y,     0, height - 1);
    int x1 = std::min(x0 + 1, width  - 1);
    int y1 = std::min(y0 + 1, height - 1);
    float fx = x - (float)x0;
    float fy = y - (float)y0;
    float h00 = heightmap[y0 * width + x0];
    float h10 = heightmap[y0 * width + x1];
    float h01 = heightmap[y1 * width + x0];
    float h11 = heightmap[y1 * width + x1];
    return h00 * (1.0f - fx) * (1.0f - fy)
         + h10 * fx           * (1.0f - fy)
         + h01 * (1.0f - fx) * fy
         + h11 * fx           * fy;
}

} // namespace godot
