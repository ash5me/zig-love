const std = @import("std");
const builtin = @import("builtin");
const types = @import("engine_types.zig");
const math = @import("engine_math.zig");
const runtime = @import("engine_runtime.zig");
const snapshot = @import("engine_snapshot.zig");

pub const InputState = types.InputState;
pub const EngineEvent = types.EngineEvent;
pub const Telemetry = types.Telemetry;
pub const RaycastHit = types.RaycastHit;
pub const CameraState = types.CameraState;
const EngineContext = types.EngineContext;
const SnapshotHeader = types.SnapshotHeader;
const INVALID_INDEX = types.INVALID_INDEX;
const EVENT_QUEUE_CAPACITY = types.EVENT_QUEUE_CAPACITY;
const FRAME_ARENA_CAPACITY = types.FRAME_ARENA_CAPACITY;
const SNAPSHOT_MAGIC = types.SNAPSHOT_MAGIC;
const SNAPSHOT_VERSION = types.SNAPSHOT_VERSION;
const BODY_STATIC = types.BODY_STATIC;
const BODY_DYNAMIC = types.BODY_DYNAMIC;
const SHAPE_CIRCLE = types.SHAPE_CIRCLE;
const SHAPE_CAPSULE = types.SHAPE_CAPSULE;
const EVENT_PLAY_SOUND = types.EVENT_PLAY_SOUND;
const EVENT_PLAYER_DIED = types.EVENT_PLAYER_DIED;
const EVENT_PATH_READY = types.EVENT_PATH_READY;
const PATH_IDLE = types.PATH_IDLE;
const PATH_WORKING = types.PATH_WORKING;
const PATH_FOUND = types.PATH_FOUND;
const PATH_FAILED = types.PATH_FAILED;
const WindowsTimer = types.WindowsTimer;
const PosixTimer = types.PosixTimer;

var timer_frequency: u64 = 0;

fn timestampNs() u64 {
    if (builtin.os.tag == .windows) {
        var frequency: i64 = 0;
        var counter: i64 = 0;
        if (timer_frequency == 0) {
            _ = WindowsTimer.QueryPerformanceFrequency(&frequency);
            timer_frequency = @intCast(frequency);
        }
        _ = WindowsTimer.QueryPerformanceCounter(&counter);
        return @intCast(@divTrunc(@as(i128, counter) * 1_000_000_000, @as(i128, timer_frequency)));
    }
    if (builtin.os.tag == .linux or builtin.os.tag == .macos) {
        var time: PosixTimer.Timespec = undefined;
        const clock_id: i32 = if (builtin.os.tag == .linux) 1 else 6;
        _ = PosixTimer.clock_gettime(clock_id, &time);
        return @intCast(@as(i128, time.sec) * 1_000_000_000 + @as(i128, time.nsec));
    }
    return 0;
}

export fn engine_create(capacity: usize, grid_width: usize, grid_height: usize, cell_size: f32) ?*EngineContext {
    if (capacity == 0 or grid_width == 0 or grid_height == 0 or cell_size <= 0) return null;
    const allocator = std.heap.page_allocator;
    const ids = allocator.alloc(u64, capacity) catch return null;
    errdefer allocator.free(ids);
    const positions_x = allocator.alloc(f32, capacity) catch return null;
    errdefer allocator.free(positions_x);
    const positions_y = allocator.alloc(f32, capacity) catch return null;
    errdefer allocator.free(positions_y);
    const velocities_x = allocator.alloc(f32, capacity) catch return null;
    errdefer allocator.free(velocities_x);
    const velocities_y = allocator.alloc(f32, capacity) catch return null;
    errdefer allocator.free(velocities_y);
    const sprite_ids = allocator.alloc(u64, capacity) catch return null;
    errdefer allocator.free(sprite_ids);
    const alive = allocator.alloc(bool, capacity) catch return null;
    errdefer allocator.free(alive);
    const next_free = allocator.alloc(u32, capacity) catch return null;
    errdefer allocator.free(next_free);
    const grid_heads = allocator.alloc(u32, grid_width * grid_height) catch return null;
    errdefer allocator.free(grid_heads);
    const next_in_cell = allocator.alloc(u32, capacity) catch return null;
    errdefer allocator.free(next_in_cell);
    const path_visited = allocator.alloc(bool, grid_width * grid_height) catch return null;
    errdefer allocator.free(path_visited);
    const path_parent = allocator.alloc(u32, grid_width * grid_height) catch return null;
    errdefer allocator.free(path_parent);
    const path_queue = allocator.alloc(u32, grid_width * grid_height) catch return null;
    errdefer allocator.free(path_queue);
    const anchor_counts = allocator.alloc(u32, capacity) catch return null;
    errdefer allocator.free(anchor_counts);
    const frame_arena = allocator.alloc(u8, FRAME_ARENA_CAPACITY) catch return null;
    errdefer allocator.free(frame_arena);
    const render_order = allocator.alloc(u32, capacity) catch return null;
    errdefer allocator.free(render_order);
    const render_z = allocator.alloc(i32, capacity) catch return null;
    errdefer allocator.free(render_z);
    const animation_first_frame = allocator.alloc(u64, capacity) catch return null;
    errdefer allocator.free(animation_first_frame);
    const animation_frame_ids = allocator.alloc(u64, capacity) catch return null;
    errdefer allocator.free(animation_frame_ids);
    const animation_frame = allocator.alloc(u32, capacity) catch return null;
    errdefer allocator.free(animation_frame);
    const animation_frame_count = allocator.alloc(u32, capacity) catch return null;
    errdefer allocator.free(animation_frame_count);
    const animation_elapsed = allocator.alloc(f32, capacity) catch return null;
    errdefer allocator.free(animation_elapsed);
    const animation_frame_duration = allocator.alloc(f32, capacity) catch return null;
    errdefer allocator.free(animation_frame_duration);
    const animation_loop = allocator.alloc(bool, capacity) catch return null;
    errdefer allocator.free(animation_loop);
    const body_type = allocator.alloc(u8, capacity) catch return null;
    errdefer allocator.free(body_type);
    const shape_type = allocator.alloc(u8, capacity) catch return null;
    errdefer allocator.free(shape_type);
    const shape_radius = allocator.alloc(f32, capacity) catch return null;
    errdefer allocator.free(shape_radius);
    const capsule_half_length = allocator.alloc(f32, capacity) catch return null;
    errdefer allocator.free(capsule_half_length);
    const context = allocator.create(EngineContext) catch return null;

    @memset(ids, 0);
    @memset(positions_x, 0);
    @memset(positions_y, 0);
    @memset(velocities_x, 0);
    @memset(velocities_y, 0);
    @memset(sprite_ids, 0);
    @memset(alive, false);
    @memset(grid_heads, INVALID_INDEX);
    @memset(next_in_cell, INVALID_INDEX);
    @memset(path_visited, false);
    @memset(path_parent, INVALID_INDEX);
    @memset(path_queue, INVALID_INDEX);
    @memset(anchor_counts, 0);
    @memset(frame_arena, 0);
    @memset(render_order, INVALID_INDEX);
    @memset(render_z, 0);
    @memset(animation_first_frame, 0);
    @memset(animation_frame_ids, 0);
    @memset(animation_frame, 0);
    @memset(animation_frame_count, 0);
    @memset(animation_elapsed, 0);
    @memset(animation_frame_duration, 0);
    @memset(animation_loop, false);
    @memset(body_type, BODY_DYNAMIC);
    @memset(shape_type, SHAPE_CIRCLE);
    @memset(shape_radius, 4);
    @memset(capsule_half_length, 0);
    for (0..capacity) |index| {
        next_free[index] = if (index + 1 < capacity) @intCast(index + 1) else INVALID_INDEX;
    }

    context.* = .{
        .capacity = capacity,
        .alive_count = 0,
        .grid_width = grid_width,
        .grid_height = grid_height,
        .cell_size = cell_size,
        .ids = ids,
        .positions_x = positions_x,
        .positions_y = positions_y,
        .velocities_x = velocities_x,
        .velocities_y = velocities_y,
        .sprite_ids = sprite_ids,
        .alive = alive,
        .next_free = next_free,
        .free_head = 0,
        .grid_heads = grid_heads,
        .next_in_cell = next_in_cell,
        .input = .{ .buttons = 0, .mouse_x = 0, .mouse_y = 0 },
        .previous_buttons = 0,
        .events = undefined,
        .event_read = 0,
        .event_write = 0,
        .event_count = 0,
        .path_visited = path_visited,
        .path_parent = path_parent,
        .path_queue = path_queue,
        .path_start = INVALID_INDEX,
        .path_goal = INVALID_INDEX,
        .path_queue_head = 0,
        .path_queue_tail = 0,
        .path_state = PATH_IDLE,
        .anchor_counts = anchor_counts,
        .frame_arena = frame_arena,
        .frame_arena_offset = 0,
        .camera = .{ .x = 0, .y = 0, .scale = 1, .rotation = 0, .parallax_x = 1, .parallax_y = 1, .viewport_width = 800, .viewport_height = 600 },
        .camera_matrix = .{ 1, 0, 0, 0, 1, 0, 0, 0, 1 },
        .render_order = render_order,
        .render_z = render_z,
        .animation_first_frame = animation_first_frame,
        .animation_frame_ids = animation_frame_ids,
        .animation_frame = animation_frame,
        .animation_frame_count = animation_frame_count,
        .animation_elapsed = animation_elapsed,
        .animation_frame_duration = animation_frame_duration,
        .animation_loop = animation_loop,
        .body_type = body_type,
        .shape_type = shape_type,
        .shape_radius = shape_radius,
        .capsule_half_length = capsule_half_length,
        .gravity = 98.0,
        .telemetry = .{ .physics_us = 0, .spatial_sort_us = 0, .ffi_serialization_us = 0, .frame_us = 0 },
    };
    return context;
}

export fn engine_destroy(context: ?*EngineContext) void {
    const value = context orelse return;
    const allocator = std.heap.page_allocator;
    allocator.free(value.ids);
    allocator.free(value.positions_x);
    allocator.free(value.positions_y);
    allocator.free(value.velocities_x);
    allocator.free(value.velocities_y);
    allocator.free(value.sprite_ids);
    allocator.free(value.alive);
    allocator.free(value.next_free);
    allocator.free(value.grid_heads);
    allocator.free(value.next_in_cell);
    allocator.free(value.path_visited);
    allocator.free(value.path_parent);
    allocator.free(value.path_queue);
    allocator.free(value.anchor_counts);
    allocator.free(value.frame_arena);
    allocator.free(value.render_order);
    allocator.free(value.render_z);
    allocator.free(value.animation_first_frame);
    allocator.free(value.animation_frame_ids);
    allocator.free(value.animation_frame);
    allocator.free(value.animation_frame_count);
    allocator.free(value.animation_elapsed);
    allocator.free(value.animation_frame_duration);
    allocator.free(value.animation_loop);
    allocator.free(value.body_type);
    allocator.free(value.shape_type);
    allocator.free(value.shape_radius);
    allocator.free(value.capsule_half_length);
    allocator.destroy(value);
}

export fn engine_entity_capacity(context: *const EngineContext) usize {
    return context.capacity;
}
export fn engine_alive_count(context: *const EngineContext) usize {
    return context.alive_count;
}
export fn engine_telemetry(context: *EngineContext) *Telemetry {
    return &context.telemetry;
}
export fn engine_set_gravity(context: *EngineContext, gravity: f32) void {
    context.gravity = gravity;
}
export fn engine_get_gravity(context: *const EngineContext) f32 {
    return context.gravity;
}
export fn engine_positions_x(context: *EngineContext) [*]f32 {
    return context.positions_x.ptr;
}
export fn engine_positions_y(context: *EngineContext) [*]f32 {
    return context.positions_y.ptr;
}
export fn engine_velocities_x(context: *EngineContext) [*]f32 {
    return context.velocities_x.ptr;
}
export fn engine_velocities_y(context: *EngineContext) [*]f32 {
    return context.velocities_y.ptr;
}
export fn engine_sprite_ids(context: *EngineContext) [*]u64 {
    return context.sprite_ids.ptr;
}

export fn engine_set_position(context: *EngineContext, index: u32, x: f32, y: f32) bool {
    if (index >= context.capacity or !context.alive[index]) return false;
    context.positions_x[index] = x;
    context.positions_y[index] = y;
    return true;
}

export fn engine_set_velocity(context: *EngineContext, index: u32, x: f32, y: f32) bool {
    if (index >= context.capacity or !context.alive[index]) return false;
    context.velocities_x[index] = x;
    context.velocities_y[index] = y;
    return true;
}

export fn engine_spawn(context: *EngineContext, id: u64, x: f32, y: f32, velocity_x: f32, velocity_y: f32, sprite_id: u64) u32 {
    if (context.free_head == INVALID_INDEX) return INVALID_INDEX;
    const index = context.free_head;
    context.free_head = context.next_free[index];
    context.next_free[index] = INVALID_INDEX;
    context.ids[index] = id;
    context.positions_x[index] = x;
    context.positions_y[index] = y;
    context.velocities_x[index] = velocity_x;
    context.velocities_y[index] = velocity_y;
    context.sprite_ids[index] = sprite_id;
    context.animation_first_frame[index] = sprite_id;
    context.animation_frame_ids[index] = sprite_id;
    context.animation_frame[index] = 0;
    context.animation_frame_count[index] = 0;
    context.animation_elapsed[index] = 0;
    context.animation_frame_duration[index] = 0;
    context.animation_loop[index] = false;
    context.render_z[index] = 0;
    context.body_type[index] = BODY_DYNAMIC;
    context.shape_type[index] = SHAPE_CIRCLE;
    context.shape_radius[index] = 4;
    context.capsule_half_length[index] = 0;
    context.alive[index] = true;
    context.anchor_counts[index] = 0;
    context.alive_count += 1;
    return index;
}

export fn engine_destroy_entity(context: *EngineContext, index: u32) bool {
    if (index >= context.capacity or !context.alive[index] or context.anchor_counts[index] != 0) return false;
    context.alive[index] = false;
    context.ids[index] = 0;
    context.anchor_counts[index] = 0;
    context.next_free[index] = context.free_head;
    context.free_head = index;
    context.alive_count -= 1;
    return true;
}

export fn engine_anchor_entity(context: *EngineContext, index: u32) bool {
    if (index >= context.capacity or !context.alive[index]) return false;
    if (context.anchor_counts[index] == std.math.maxInt(u32)) return false;
    context.anchor_counts[index] += 1;
    return true;
}

export fn engine_release_entity(context: *EngineContext, index: u32) bool {
    if (index >= context.capacity or context.anchor_counts[index] == 0) return false;
    context.anchor_counts[index] -= 1;
    return true;
}

export fn engine_entity_anchor_count(context: *const EngineContext, index: u32) u32 {
    if (index >= context.capacity) return 0;
    return context.anchor_counts[index];
}

export fn engine_camera_set(context: *EngineContext, camera: *const CameraState) void {
    context.camera = camera.*;
    if (context.camera.scale <= 0) context.camera.scale = 1;
    math.updateCameraMatrix(context);
}

export fn engine_camera_matrix(context: *const EngineContext) [*]const f32 {
    return &context.camera_matrix;
}

export fn engine_set_render_z(context: *EngineContext, index: u32, z: i32) bool {
    if (index >= context.capacity or !context.alive[index]) return false;
    context.render_z[index] = z;
    return true;
}

export fn engine_sort_render_order(context: *EngineContext) void {
    runtime.sortRenderOrder(context);
}

export fn engine_render_order(context: *EngineContext) [*]const u32 {
    return context.render_order.ptr;
}

export fn engine_render_count(context: *const EngineContext) usize {
    var count: usize = 0;
    for (context.alive) |is_alive| {
        if (is_alive) count += 1;
    }
    return count;
}

export fn engine_animation_set(context: *EngineContext, index: u32, first_frame_id: u64, frame_count: u32, frame_duration: f32, loop: bool) bool {
    if (index >= context.capacity or !context.alive[index] or frame_count == 0 or frame_duration <= 0) return false;
    context.animation_first_frame[index] = first_frame_id;
    context.animation_frame_ids[index] = first_frame_id;
    context.animation_frame[index] = 0;
    context.animation_frame_count[index] = frame_count;
    context.animation_elapsed[index] = 0;
    context.animation_frame_duration[index] = frame_duration;
    context.animation_loop[index] = loop;
    context.sprite_ids[index] = first_frame_id;
    return true;
}

export fn engine_current_sprite_frame_id(context: *const EngineContext, index: u32) u64 {
    if (index >= context.capacity or !context.alive[index]) return 0;
    return context.animation_frame_ids[index];
}

export fn engine_set_body(context: *EngineContext, index: u32, body_type: u8, shape_type: u8, radius: f32, half_length: f32) bool {
    if (index >= context.capacity or !context.alive[index] or body_type > BODY_DYNAMIC or (shape_type != SHAPE_CIRCLE and shape_type != SHAPE_CAPSULE) or radius <= 0 or half_length < 0) return false;
    context.body_type[index] = body_type;
    context.shape_type[index] = shape_type;
    context.shape_radius[index] = radius;
    context.capsule_half_length[index] = if (shape_type == SHAPE_CAPSULE) half_length else 0;
    return true;
}

export fn engine_test_collision(context: *const EngineContext, first: u32, second: u32) bool {
    if (first >= context.capacity or second >= context.capacity or !context.alive[first] or !context.alive[second] or first == second) return false;
    const radius_sum = context.shape_radius[first] + context.shape_radius[second];
    return math.shapeDistanceSquared(context, first, second) <= radius_sum * radius_sum;
}

export fn engine_raycast(context: *const EngineContext, ax: f32, ay: f32, bx: f32, by: f32, output: *RaycastHit) bool {
    const dx = bx - ax;
    const dy = by - ay;
    const length = @sqrt(dx * dx + dy * dy);
    if (length == 0) return false;
    const start_cell = math.cellIndex(context, ax, ay) orelse return false;
    var cell_x: i32 = @intCast(start_cell % context.grid_width);
    var cell_y: i32 = @intCast(start_cell / context.grid_width);
    const step_x: i32 = if (dx >= 0) 1 else -1;
    const step_y: i32 = if (dy >= 0) 1 else -1;
    const delta_x = if (dx == 0) std.math.inf(f32) else @abs(context.cell_size / dx);
    const delta_y = if (dy == 0) std.math.inf(f32) else @abs(context.cell_size / dy);
    const next_x = if (dx >= 0) (@as(f32, @floatFromInt(cell_x)) + 1) * context.cell_size else @as(f32, @floatFromInt(cell_x)) * context.cell_size;
    const next_y = if (dy >= 0) (@as(f32, @floatFromInt(cell_y)) + 1) * context.cell_size else @as(f32, @floatFromInt(cell_y)) * context.cell_size;
    var max_x = if (dx == 0) std.math.inf(f32) else (next_x - ax) / dx;
    var max_y = if (dy == 0) std.math.inf(f32) else (next_y - ay) / dy;
    var best_t: f32 = 1;
    var best_index: u32 = INVALID_INDEX;
    var iterations: usize = 0;
    while (cell_x >= 0 and cell_y >= 0 and cell_x < context.grid_width and cell_y < context.grid_height and iterations < context.grid_width + context.grid_height) : (iterations += 1) {
        var entity = context.grid_heads[@as(usize, @intCast(cell_y)) * context.grid_width + @as(usize, @intCast(cell_x))];
        while (entity != INVALID_INDEX) : (entity = context.next_in_cell[entity]) {
            if (math.rayShapeHit(context, entity, ax, ay, dx, dy)) |candidate| {
                if (candidate <= best_t) {
                    best_t = candidate;
                    best_index = entity;
                }
            }
        }
        if (max_x < max_y) {
            if (max_x > best_t) break;
            cell_x += step_x;
            max_x += delta_x;
        } else {
            if (max_y > best_t) break;
            cell_y += step_y;
            max_y += delta_y;
        }
    }
    if (best_index == INVALID_INDEX) return false;
    output.* = .{
        .entity_index = best_index,
        .entity_id = context.ids[best_index],
        .x = ax + dx * best_t,
        .y = ay + dy * best_t,
        .distance = length * best_t,
    };
    return true;
}

export fn engine_find_entity(context: *const EngineContext, id: u64) u32 {
    for (0..context.capacity) |index| {
        if (context.alive[index] and context.ids[index] == id) return @intCast(index);
    }
    return INVALID_INDEX;
}

export fn engine_rebuild_spatial(context: *EngineContext) void {
    runtime.rebuildSpatialGrid(context);
}

export fn engine_query_cell(context: *const EngineContext, cell_x: i32, cell_y: i32, output: [*]u32, output_capacity: usize) usize {
    if (cell_x < 0 or cell_y < 0) return 0;
    const x: usize = @intCast(cell_x);
    const y: usize = @intCast(cell_y);
    if (x >= context.grid_width or y >= context.grid_height) return 0;
    var count: usize = 0;
    var index = context.grid_heads[y * context.grid_width + x];
    while (index != INVALID_INDEX) : (index = context.next_in_cell[index]) {
        if (count < output_capacity) output[count] = index;
        count += 1;
    }
    return @min(count, output_capacity);
}

export fn engine_set_input(context: *EngineContext, input: *const InputState) void {
    context.input = input.*;
}

export fn engine_next_event(context: *EngineContext, output: *EngineEvent) bool {
    if (context.event_count == 0) return false;
    output.* = context.events[context.event_read];
    context.event_read = (context.event_read + 1) % EVENT_QUEUE_CAPACITY;
    context.event_count -= 1;
    return true;
}

export fn engine_pending_event_count(context: *const EngineContext) usize {
    return context.event_count;
}

export fn engine_frame_begin(context: *EngineContext) void {
    context.frame_arena_offset = 0;
}

export fn engine_frame_alloc(context: *EngineContext, size: usize) ?[*]u8 {
    if (size > context.frame_arena.len -| context.frame_arena_offset) return null;
    const start = context.frame_arena_offset;
    context.frame_arena_offset += size;
    return context.frame_arena.ptr + start;
}

export fn engine_frame_arena_used(context: *const EngineContext) usize {
    return context.frame_arena_offset;
}

export fn engine_frame_arena_capacity(context: *const EngineContext) usize {
    return context.frame_arena.len;
}

export fn engine_snapshot_size(context: *const EngineContext) usize {
    return snapshot.snapshotPayloadSize(context);
}

export fn engine_snapshot_write(context: *EngineContext, output: [*]u8, output_capacity: usize) usize {
    return snapshot.snapshotWrite(context, output, output_capacity);
}

export fn engine_snapshot_read(context: *EngineContext, input: [*]const u8, input_size: usize) bool {
    return snapshot.snapshotRead(context, input, input_size);
}

export fn engine_pathfind_begin(context: *EngineContext, start_x: i32, start_y: i32, goal_x: i32, goal_y: i32) bool {
    if (start_x < 0 or start_y < 0 or goal_x < 0 or goal_y < 0) return false;
    const start_x_u: usize = @intCast(start_x);
    const start_y_u: usize = @intCast(start_y);
    const goal_x_u: usize = @intCast(goal_x);
    const goal_y_u: usize = @intCast(goal_y);
    if (start_x_u >= context.grid_width or start_y_u >= context.grid_height or goal_x_u >= context.grid_width or goal_y_u >= context.grid_height) return false;

    @memset(context.path_visited, false);
    @memset(context.path_parent, INVALID_INDEX);
    context.path_start = @intCast(start_y_u * context.grid_width + start_x_u);
    context.path_goal = @intCast(goal_y_u * context.grid_width + goal_x_u);
    context.path_queue_head = 0;
    context.path_queue_tail = 1;
    context.path_queue[0] = context.path_start;
    context.path_visited[context.path_start] = true;
    context.path_state = PATH_WORKING;
    return true;
}

export fn engine_pathfind_step(context: *EngineContext, node_budget: usize) u32 {
    if (context.path_state != PATH_WORKING or node_budget == 0) return context.path_state;
    var processed: usize = 0;
    while (processed < node_budget and context.path_queue_head < context.path_queue_tail) : (processed += 1) {
        const current = context.path_queue[context.path_queue_head];
        context.path_queue_head += 1;
        if (current == context.path_goal) {
            context.path_state = PATH_FOUND;
            runtime.pushEvent(context, EVENT_PATH_READY, current);
            return context.path_state;
        }

        const current_x: i32 = @intCast(current % context.grid_width);
        const current_y: i32 = @intCast(current / context.grid_width);
        const offsets_x = [_]i32{ 1, -1, 0, 0 };
        const offsets_y = [_]i32{ 0, 0, 1, -1 };
        for (offsets_x, offsets_y) |offset_x, offset_y| {
            const neighbor_x = current_x + offset_x;
            const neighbor_y = current_y + offset_y;
            if (neighbor_x < 0 or neighbor_y < 0) continue;
            const neighbor_x_u: usize = @intCast(neighbor_x);
            const neighbor_y_u: usize = @intCast(neighbor_y);
            if (neighbor_x_u >= context.grid_width or neighbor_y_u >= context.grid_height) continue;
            const neighbor = neighbor_y_u * context.grid_width + neighbor_x_u;
            if (context.path_visited[neighbor]) continue;
            context.path_visited[neighbor] = true;
            context.path_parent[neighbor] = current;
            context.path_queue[context.path_queue_tail] = @intCast(neighbor);
            context.path_queue_tail += 1;
        }
    }
    if (context.path_queue_head >= context.path_queue_tail) context.path_state = PATH_FAILED;
    return context.path_state;
}

export fn engine_pathfind_state(context: *const EngineContext) u32 {
    return context.path_state;
}

export fn engine_pathfind_length(context: *const EngineContext) usize {
    if (context.path_state != PATH_FOUND) return 0;
    var length: usize = 1;
    var current = context.path_goal;
    while (current != context.path_start) {
        current = context.path_parent[current];
        if (current == INVALID_INDEX or length == context.grid_width * context.grid_height) return 0;
        length += 1;
    }
    return length;
}

export fn engine_update(context: *EngineContext, dt: f32) void {
    const frame_start = timestampNs();
    engine_frame_begin(context);
    math.updateCameraMatrix(context);
    runtime.engineTick(context, dt);
    context.telemetry.frame_us = (timestampNs() - frame_start) / 1000;
}

export fn add_numbers(a: c_int, b: c_int) c_int {
    return a + b;
}
