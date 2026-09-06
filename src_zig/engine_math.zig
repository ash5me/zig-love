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

fn rayPolygonHit(vertices: []const Vec2, ax: f32, ay: f32, dx: f32, dy: f32) ?f32 {
    var lower: f32 = 0;
    var upper: f32 = 1;
    for (vertices, 0..) |point, vertex| {
        const next = vertices[(vertex + 1) % vertices.len];
        const edge_x = next.x - point.x;
        const edge_y = next.y - point.y;
        const start_side = edge_x * (ay - point.y) - edge_y * (ax - point.x);
        const direction_side = edge_x * dy - edge_y * dx;
        if (direction_side == 0) {
            if (start_side < 0) return null;
            continue;
        }
        const crossing = -start_side / direction_side;
        if (direction_side > 0) lower = @max(lower, crossing) else upper = @min(upper, crossing);
        if (lower > upper) return null;
    }
    if (upper < 0 or lower > 1) return null;
    return @max(lower, 0);
}

pub fn rayShapeHit(context: *const EngineContext, index: usize, ax: f32, ay: f32, dx: f32, dy: f32) ?f32 {
    const x = context.positions_x[index];
    const y = context.positions_y[index];
    const radius = context.shape_radius[index];
    if (context.shape_type[index] == types.SHAPE_CIRCLE) return rayCircleHit(ax, ay, dx, dy, x, y, radius);
    if (context.shape_type[index] == types.SHAPE_AABB or context.shape_type[index] == types.SHAPE_OBB or context.shape_type[index] == types.SHAPE_POLYGON) {
        var vertices: [types.MAX_POLYGON_VERTICES]Vec2 = undefined;
        const count = shapeVertices(context, index, &vertices);
        return rayPolygonHit(vertices[0..count], ax, ay, dx, dy);
    }

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

pub const Contact = struct {
    normal_x: f32,
    normal_y: f32,
    penetration: f32,
};

const Vec2 = struct { x: f32, y: f32 };

fn shapeVertices(context: *const EngineContext, index: usize, vertices: *[types.MAX_POLYGON_VERTICES]Vec2) usize {
    const x = context.positions_x[index];
    const y = context.positions_y[index];
    const shape = context.shape_type[index];
    if (shape == types.SHAPE_CAPSULE) {
        const radius = context.shape_radius[index];
        const half_length = context.capsule_half_length[index];
        vertices[0] = .{ .x = x - radius, .y = y - half_length };
        vertices[1] = .{ .x = x, .y = y - half_length - radius };
        vertices[2] = .{ .x = x + radius, .y = y - half_length };
        vertices[3] = .{ .x = x + radius, .y = y + half_length };
        vertices[4] = .{ .x = x, .y = y + half_length + radius };
        vertices[5] = .{ .x = x - radius, .y = y + half_length };
        return 6;
    }
    if (shape == types.SHAPE_AABB) {
        const half_width = context.shape_half_width[index];
        const half_height = context.shape_half_height[index];
        vertices[0] = .{ .x = x - half_width, .y = y - half_height };
        vertices[1] = .{ .x = x + half_width, .y = y - half_height };
        vertices[2] = .{ .x = x + half_width, .y = y + half_height };
        vertices[3] = .{ .x = x - half_width, .y = y + half_height };
        return 4;
    }
    if (shape == types.SHAPE_OBB) {
        const half_width = context.shape_half_width[index];
        const half_height = context.shape_half_height[index];
        const cosine = @cos(context.shape_rotation[index]);
        const sine = @sin(context.shape_rotation[index]);
        const local = [_]Vec2{
            .{ .x = -half_width, .y = -half_height }, .{ .x = half_width, .y = -half_height },
            .{ .x = half_width, .y = half_height },   .{ .x = -half_width, .y = half_height },
        };
        for (local, 0..) |point, vertex| {
            vertices[vertex] = .{ .x = x + point.x * cosine - point.y * sine, .y = y + point.x * sine + point.y * cosine };
        }
        return 4;
    }
    if (shape == types.SHAPE_POLYGON) {
        const cosine = @cos(context.shape_rotation[index]);
        const sine = @sin(context.shape_rotation[index]);
        const base = index * types.MAX_POLYGON_VERTICES * 2;
        const count = context.polygon_counts[index];
        for (0..count) |vertex| {
            const local_x = context.polygon_vertices[base + vertex * 2];
            const local_y = context.polygon_vertices[base + vertex * 2 + 1];
            vertices[vertex] = .{ .x = x + local_x * cosine - local_y * sine, .y = y + local_x * sine + local_y * cosine };
        }
        return count;
    }
    return 0;
}

fn polygonContact(first: []const Vec2, second: []const Vec2, center_x: f32, center_y: f32) ?Contact {
    var best_depth = std.math.inf(f32);
    var best_x: f32 = 0;
    var best_y: f32 = 0;
    const polygons = [_][]const Vec2{ first, second };
    for (polygons) |polygon| {
        for (polygon, 0..) |point, vertex| {
            const next = polygon[(vertex + 1) % polygon.len];
            var axis_x = -(next.y - point.y);
            var axis_y = next.x - point.x;
            const axis_length = @sqrt(axis_x * axis_x + axis_y * axis_y);
            if (axis_length == 0) continue;
            axis_x /= axis_length;
            axis_y /= axis_length;
            var first_min = std.math.inf(f32);
            var first_max = -std.math.inf(f32);
            var second_min = std.math.inf(f32);
            var second_max = -std.math.inf(f32);
            for (first) |sample| {
                const projection = sample.x * axis_x + sample.y * axis_y;
                first_min = @min(first_min, projection);
                first_max = @max(first_max, projection);
            }
            for (second) |sample| {
                const projection = sample.x * axis_x + sample.y * axis_y;
                second_min = @min(second_min, projection);
                second_max = @max(second_max, projection);
            }
            const overlap = @min(first_max, second_max) - @max(first_min, second_min);
            if (overlap <= 0) return null;
            if (overlap < best_depth) {
                best_depth = overlap;
                best_x = axis_x;
                best_y = axis_y;
            }
        }
    }
    if (best_x * (center_x) + best_y * (center_y) < 0) {
        best_x = -best_x;
        best_y = -best_y;
    }
    return .{ .normal_x = best_x, .normal_y = best_y, .penetration = best_depth };
}

fn circlePolygonContact(circle_x: f32, circle_y: f32, radius: f32, polygon: []const Vec2, first_circle: bool) ?Contact {
    if (polygon.len == 0) return null;
    var closest = polygon[0];
    var closest_distance = std.math.inf(f32);
    for (polygon, 0..) |point, vertex| {
        const next = polygon[(vertex + 1) % polygon.len];
        const edge_x = next.x - point.x;
        const edge_y = next.y - point.y;
        const edge_length_squared = edge_x * edge_x + edge_y * edge_y;
        if (edge_length_squared == 0) continue;
        const along_edge = clamp(((circle_x - point.x) * edge_x + (circle_y - point.y) * edge_y) / edge_length_squared, 0, 1);
        const candidate = Vec2{ .x = point.x + edge_x * along_edge, .y = point.y + edge_y * along_edge };
        const dx = candidate.x - circle_x;
        const dy = candidate.y - circle_y;
        const distance = dx * dx + dy * dy;
        if (distance < closest_distance) {
            closest_distance = distance;
            closest = candidate;
        }
    }
    const dx = circle_x - closest.x;
    const dy = circle_y - closest.y;
    const distance = @sqrt(dx * dx + dy * dy);
    const circle_radius = radius;
    if (distance >= circle_radius) return null;
    var normal_x = if (distance == 0) @as(f32, 1) else dx / distance;
    var normal_y = if (distance == 0) @as(f32, 0) else dy / distance;
    if (first_circle) {
        normal_x = -normal_x;
        normal_y = -normal_y;
    }
    return .{ .normal_x = normal_x, .normal_y = normal_y, .penetration = circle_radius - distance };
}

pub fn shapeContact(context: *const EngineContext, first: usize, second: usize) ?Contact {
    const first_circle = context.shape_type[first] == types.SHAPE_CIRCLE;
    const second_circle = context.shape_type[second] == types.SHAPE_CIRCLE;
    const first_x = context.positions_x[first];
    const first_y = context.positions_y[first];
    const second_x = context.positions_x[second];
    const second_y = context.positions_y[second];
    if (first_circle and second_circle) {
        const dx = second_x - first_x;
        const dy = second_y - first_y;
        const distance = @sqrt(dx * dx + dy * dy);
        const radius_sum = context.shape_radius[first] + context.shape_radius[second];
        if (distance >= radius_sum) return null;
        if (distance == 0) return .{ .normal_x = 1, .normal_y = 0, .penetration = radius_sum };
        return .{ .normal_x = dx / distance, .normal_y = dy / distance, .penetration = radius_sum - distance };
    }
    if (!first_circle and !second_circle) {
        var first_vertices: [types.MAX_POLYGON_VERTICES]Vec2 = undefined;
        var second_vertices: [types.MAX_POLYGON_VERTICES]Vec2 = undefined;
        const first_count = shapeVertices(context, first, &first_vertices);
        const second_count = shapeVertices(context, second, &second_vertices);
        return polygonContact(first_vertices[0..first_count], second_vertices[0..second_count], second_x - first_x, second_y - first_y);
    }
    const circle = if (first_circle) first else second;
    const polygon = if (first_circle) second else first;
    var polygon_vertices: [types.MAX_POLYGON_VERTICES]Vec2 = undefined;
    const polygon_count = shapeVertices(context, polygon, &polygon_vertices);
    return circlePolygonContact(context.positions_x[circle], context.positions_y[circle], context.shape_radius[circle], polygon_vertices[0..polygon_count], first_circle);
}

pub fn aabbContact(context: *const EngineContext, index: usize, x: f32, y: f32, half_width: f32, half_height: f32) ?Contact {
    var static_vertices = [_]Vec2{
        .{ .x = x - half_width, .y = y - half_height },
        .{ .x = x + half_width, .y = y - half_height },
        .{ .x = x + half_width, .y = y + half_height },
        .{ .x = x - half_width, .y = y + half_height },
    };
    if (context.shape_type[index] == types.SHAPE_CIRCLE) {
        return circlePolygonContact(context.positions_x[index], context.positions_y[index], context.shape_radius[index], static_vertices[0..], true);
    }
    var entity_vertices: [types.MAX_POLYGON_VERTICES]Vec2 = undefined;
    const entity_count = shapeVertices(context, index, &entity_vertices);
    return polygonContact(entity_vertices[0..entity_count], static_vertices[0..], x - context.positions_x[index], y - context.positions_y[index]);
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
