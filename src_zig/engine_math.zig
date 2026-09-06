const std = @import("std");
const types = @import("engine_types.zig");
const EngineContext = types.EngineContext;

pub fn clamp(value: f32, minimum: f32, maximum: f32) f32 {
    return @max(minimum, @min(value, maximum));
}

pub fn cellIndex(context: *const EngineContext, x: f32, y: f32) ?usize {
    if (x < 0 or y < 0) return null;
    const cell_x: usize = @intFromFloat(@floor(x / context.cell_size));
    const cell_y: usize = @intFromFloat(@floor(y / context.cell_size));
    if (cell_x >= context.grid_width or cell_y >= context.grid_height) return null;
    return cell_y * context.grid_width + cell_x;
}

pub fn rayCircleHit(ax: f32, ay: f32, dx: f32, dy: f32, cx: f32, cy: f32, radius: f32) ?f32 {
    const a = dx * dx + dy * dy;
    if (a == 0) return null;
    const offset_x = ax - cx;
    const offset_y = ay - cy;
    const c = offset_x * offset_x + offset_y * offset_y - radius * radius;
    if (c <= 0) return 0;
    const b = 2 * (offset_x * dx + offset_y * dy);
    const discriminant = b * b - 4 * a * c;
    if (discriminant < 0) return null;
    const root = @sqrt(discriminant);
    const first = (-b - root) / (2 * a);
    if (first >= 0 and first <= 1) return first;
    const second = (-b + root) / (2 * a);
    if (second >= 0 and second <= 1) return second;
    return null;
}

pub fn rayShapeHit(context: *const EngineContext, index: usize, ax: f32, ay: f32, dx: f32, dy: f32) ?f32 {
    const x = context.positions_x[index];
    const y = context.positions_y[index];
    const radius = context.shape_radius[index];
    if (context.shape_type[index] != types.SHAPE_CAPSULE) return rayCircleHit(ax, ay, dx, dy, x, y, radius);

    const half_length = context.capsule_half_length[index];
    var best: ?f32 = null;
    if (ax >= x - radius and ax <= x + radius and ay >= y - half_length and ay <= y + half_length) best = 0;
    if (dx != 0) {
        const left = (x - radius - ax) / dx;
        const right = (x + radius - ax) / dx;
        for ([_]f32{ left, right }) |candidate| {
            if (candidate >= 0 and candidate <= 1) {
                const hit_y = ay + dy * candidate;
                if (hit_y >= y - half_length and hit_y <= y + half_length) best = if (best) |value| @min(value, candidate) else candidate;
            }
        }
    }
    for ([_]f32{ y - half_length, y + half_length }) |cap_y| {
        if (rayCircleHit(ax, ay, dx, dy, x, cap_y, radius)) |candidate| {
            best = if (best) |value| @min(value, candidate) else candidate;
        }
    }
    return best;
}

pub fn shapeDistanceSquared(context: *const EngineContext, first: usize, second: usize) f32 {
    const first_x = context.positions_x[first];
    const first_y = context.positions_y[first];
    const second_x = context.positions_x[second];
    const second_y = context.positions_y[second];
    const first_capsule = context.shape_type[first] == types.SHAPE_CAPSULE;
    const second_capsule = context.shape_type[second] == types.SHAPE_CAPSULE;
    if (!first_capsule and !second_capsule) {
        const dx = first_x - second_x;
        const dy = first_y - second_y;
        return dx * dx + dy * dy;
    }
    if (first_capsule and second_capsule) {
        const first_min = first_y - context.capsule_half_length[first];
        const first_max = first_y + context.capsule_half_length[first];
        const second_min = second_y - context.capsule_half_length[second];
        const second_max = second_y + context.capsule_half_length[second];
        const vertical_gap = if (first_max < second_min) second_min - first_max else if (second_max < first_min) first_min - second_max else 0;
        const dx = first_x - second_x;
        return dx * dx + vertical_gap * vertical_gap;
    }
    const capsule = if (first_capsule) first else second;
    const circle = if (first_capsule) second else first;
    const closest_y = clamp(context.positions_y[circle], context.positions_y[capsule] - context.capsule_half_length[capsule], context.positions_y[capsule] + context.capsule_half_length[capsule]);
    const dx = context.positions_x[circle] - context.positions_x[capsule];
    const dy = context.positions_y[circle] - closest_y;
    return dx * dx + dy * dy;
}

pub fn updateCameraMatrix(context: *EngineContext) void {
    const cosine = @cos(context.camera.rotation) * context.camera.scale;
    const sine = @sin(context.camera.rotation) * context.camera.scale;
    const parallax_x = context.camera.x * context.camera.parallax_x;
    const parallax_y = context.camera.y * context.camera.parallax_y;
    context.camera_matrix = .{
        cosine, -sine,  context.camera.viewport_width * 0.5 - parallax_x * cosine + parallax_y * sine,
        sine,   cosine, context.camera.viewport_height * 0.5 - parallax_x * sine - parallax_y * cosine,
        0,      0,      1,
    };
}
