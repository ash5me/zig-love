const std = @import("std");
const builtin = @import("builtin");

const INVALID_INDEX: u32 = std.math.maxInt(u32);
const EVENT_QUEUE_CAPACITY: usize = 256;
const FRAME_ARENA_CAPACITY: usize = 64 * 1024;
const SNAPSHOT_MAGIC: u32 = 0x5A47454E;
const SNAPSHOT_VERSION: u32 = 1;

pub const InputState = extern struct {
    buttons: u32,
    mouse_x: f32,
    mouse_y: f32,
};

pub const EngineEvent = extern struct {
    id: u32,
    value: u32,
};

pub const Telemetry = extern struct {
    physics_us: u64,
    spatial_sort_us: u64,
    ffi_serialization_us: u64,
    frame_us: u64,
};

pub const RaycastHit = extern struct {
    entity_index: u32,
    entity_id: u64,
    x: f32,
    y: f32,
    distance: f32,
};

pub const BODY_STATIC: u8 = 0;
pub const BODY_KINEMATIC: u8 = 1;
pub const BODY_DYNAMIC: u8 = 2;
pub const SHAPE_CIRCLE: u8 = 1;
pub const SHAPE_CAPSULE: u8 = 2;

pub const EVENT_PLAY_SOUND: u32 = 1;
pub const EVENT_PLAYER_DIED: u32 = 2;
pub const EVENT_PATH_READY: u32 = 3;

const PATH_IDLE: u32 = 0;
const PATH_WORKING: u32 = 1;
const PATH_FOUND: u32 = 2;
const PATH_FAILED: u32 = 3;

pub const CameraState = extern struct {
    x: f32,
    y: f32,
    scale: f32,
    rotation: f32,
    parallax_x: f32,
    parallax_y: f32,
    viewport_width: f32,
    viewport_height: f32,
};

const SnapshotHeader = extern struct {
    magic: u32,
    version: u32,
    capacity: u64,
    grid_width: u64,
    grid_height: u64,
    cell_size: f32,
    alive_count: u64,
    free_head: u32,
    previous_buttons: u32,
    event_read: u64,
    event_write: u64,
    event_count: u64,
    path_start: u32,
    path_goal: u32,
    path_queue_head: u64,
    path_queue_tail: u64,
    path_state: u32,
    input: InputState,
    gravity: f32,
};

const EngineContext = struct {
    capacity: usize,
    alive_count: usize,
    grid_width: usize,
    grid_height: usize,
    cell_size: f32,
    ids: []u64,
    positions_x: []f32,
    positions_y: []f32,
    velocities_x: []f32,
    velocities_y: []f32,
    sprite_ids: []u64,
    alive: []bool,
    next_free: []u32,
    free_head: u32,
    grid_heads: []u32,
    next_in_cell: []u32,
    input: InputState,
    previous_buttons: u32,
    events: [EVENT_QUEUE_CAPACITY]EngineEvent,
    event_read: usize,
    event_write: usize,
    event_count: usize,
    path_visited: []bool,
    path_parent: []u32,
    path_queue: []u32,
    path_start: u32,
    path_goal: u32,
    path_queue_head: usize,
    path_queue_tail: usize,
    path_state: u32,
    anchor_counts: []u32,
    frame_arena: []u8,
    frame_arena_offset: usize,
    camera: CameraState,
    camera_matrix: [9]f32,
    render_order: []u32,
    render_z: []i32,
    animation_first_frame: []u64,
    animation_frame_ids: []u64,
    animation_frame: []u32,
    animation_frame_count: []u32,
    animation_elapsed: []f32,
    animation_frame_duration: []f32,
    animation_loop: []bool,
    body_type: []u8,
    shape_type: []u8,
    shape_radius: []f32,
    capsule_half_length: []f32,
    gravity: f32,
    telemetry: Telemetry,
};

const WindowsTimer = if (builtin.os.tag == .windows) struct {
    extern "kernel32" fn QueryPerformanceCounter(counter: *i64) callconv(.winapi) i32;
    extern "kernel32" fn QueryPerformanceFrequency(frequency: *i64) callconv(.winapi) i32;
} else struct {};

const PosixTimer = if (builtin.os.tag == .linux or builtin.os.tag == .macos) struct {
    const Timespec = extern struct { sec: i64, nsec: i64 };
    extern "c" fn clock_gettime(clock_id: i32, time: *Timespec) callconv(.c) i32;
} else struct {};

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

fn snapshotPayloadSize(context: *const EngineContext) usize {
    return @sizeOf(SnapshotHeader) +
        @sizeOf(u64) * context.capacity * 2 +
        @sizeOf(f32) * context.capacity * 4 +
        @sizeOf(bool) * context.capacity +
        @sizeOf(u32) * context.capacity * 2 +
        @sizeOf(EngineEvent) * EVENT_QUEUE_CAPACITY +
        @sizeOf(bool) * context.grid_width * context.grid_height +
        @sizeOf(u32) * context.grid_width * context.grid_height * 2 +
        @sizeOf(CameraState) + @sizeOf(f32) * 9 +
        @sizeOf(i32) * context.capacity + @sizeOf(u64) * context.capacity * 2 +
        @sizeOf(u32) * context.capacity * 2 + @sizeOf(f32) * context.capacity * 2 +
        @sizeOf(bool) * context.capacity + @sizeOf(u8) * context.capacity * 2 +
        @sizeOf(f32) * context.capacity * 2;
}

fn writeBytes(output: []u8, offset: *usize, source: []const u8) bool {
    if (source.len > output.len -| offset.*) return false;
    @memcpy(output[offset.*..][0..source.len], source);
    offset.* += source.len;
    return true;
}

fn readBytes(input: []const u8, offset: *usize, destination: []u8) bool {
    if (destination.len > input.len -| offset.*) return false;
    @memcpy(destination, input[offset.*..][0..destination.len]);
    offset.* += destination.len;
    return true;
}

fn pushEvent(context: *EngineContext, id: u32, value: u32) void {
    if (context.event_count == EVENT_QUEUE_CAPACITY) return;
    context.events[context.event_write] = .{ .id = id, .value = value };
    context.event_write = (context.event_write + 1) % EVENT_QUEUE_CAPACITY;
    context.event_count += 1;
}

fn cellIndex(context: *const EngineContext, x: f32, y: f32) ?usize {
    if (x < 0 or y < 0) return null;
    const cell_x: usize = @intFromFloat(@floor(x / context.cell_size));
    const cell_y: usize = @intFromFloat(@floor(y / context.cell_size));
    if (cell_x >= context.grid_width or cell_y >= context.grid_height) return null;
    return cell_y * context.grid_width + cell_x;
}

fn clearGrid(context: *EngineContext) void {
    @memset(context.grid_heads, INVALID_INDEX);
    @memset(context.next_in_cell, INVALID_INDEX);
}

fn rebuildSpatialGrid(context: *EngineContext) void {
    clearGrid(context);
    for (0..context.capacity) |index| {
        if (!context.alive[index]) continue;
        const cell = cellIndex(context, context.positions_x[index], context.positions_y[index]) orelse continue;
        context.next_in_cell[index] = context.grid_heads[cell];
        context.grid_heads[cell] = @intCast(index);
    }
}

fn updateCameraMatrix(context: *EngineContext) void {
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

fn sortRenderOrder(context: *EngineContext) void {
    var count: usize = 0;
    for (0..context.capacity) |index| {
        if (!context.alive[index]) continue;
        context.render_order[count] = @intCast(index);
        count += 1;
    }
    var index: usize = 1;
    while (index < count) : (index += 1) {
        const value = context.render_order[index];
        var position = index;
        while (position > 0 and context.render_z[context.render_order[position - 1]] > context.render_z[value]) : (position -= 1) {
            context.render_order[position] = context.render_order[position - 1];
        }
        context.render_order[position] = value;
    }
}

fn updateAnimations(context: *EngineContext, dt: f32) void {
    for (0..context.capacity) |index| {
        if (!context.alive[index] or context.animation_frame_count[index] == 0) continue;
        context.animation_elapsed[index] += dt;
        while (context.animation_elapsed[index] >= context.animation_frame_duration[index]) {
            context.animation_elapsed[index] -= context.animation_frame_duration[index];
            const next_frame = context.animation_frame[index] + 1;
            if (next_frame >= context.animation_frame_count[index]) {
                if (!context.animation_loop[index]) {
                    context.animation_frame[index] = context.animation_frame_count[index] - 1;
                    context.animation_elapsed[index] = 0;
                    break;
                }
                context.animation_frame[index] = 0;
            } else {
                context.animation_frame[index] = next_frame;
            }
        }
        context.animation_frame_ids[index] = context.animation_first_frame[index] + context.animation_frame[index];
        context.sprite_ids[index] = context.animation_frame_ids[index];
    }
}

fn clamp(value: f32, minimum: f32, maximum: f32) f32 {
    return @max(minimum, @min(value, maximum));
}

fn rayCircleHit(ax: f32, ay: f32, dx: f32, dy: f32, cx: f32, cy: f32, radius: f32) ?f32 {
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

fn rayShapeHit(context: *const EngineContext, index: usize, ax: f32, ay: f32, dx: f32, dy: f32) ?f32 {
    const x = context.positions_x[index];
    const y = context.positions_y[index];
    const radius = context.shape_radius[index];
    if (context.shape_type[index] != SHAPE_CAPSULE) return rayCircleHit(ax, ay, dx, dy, x, y, radius);

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

fn shapeDistanceSquared(context: *const EngineContext, first: usize, second: usize) f32 {
    const first_x = context.positions_x[first];
    const first_y = context.positions_y[first];
    const second_x = context.positions_x[second];
    const second_y = context.positions_y[second];
    const first_capsule = context.shape_type[first] == SHAPE_CAPSULE;
    const second_capsule = context.shape_type[second] == SHAPE_CAPSULE;
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
    updateCameraMatrix(context);
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
    sortRenderOrder(context);
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
    return shapeDistanceSquared(context, first, second) <= radius_sum * radius_sum;
}

export fn engine_raycast(context: *const EngineContext, ax: f32, ay: f32, bx: f32, by: f32, output: *RaycastHit) bool {
    const dx = bx - ax;
    const dy = by - ay;
    const length = @sqrt(dx * dx + dy * dy);
    if (length == 0) return false;
    const start_cell = cellIndex(context, ax, ay) orelse return false;
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
            if (rayShapeHit(context, entity, ax, ay, dx, dy)) |candidate| {
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
    rebuildSpatialGrid(context);
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
    return snapshotPayloadSize(context);
}

export fn engine_snapshot_write(context: *EngineContext, output: [*]u8, output_capacity: usize) usize {
    const serialization_start = timestampNs();
    const required = snapshotPayloadSize(context);
    if (output_capacity < required) return 0;
    const bytes = output[0..output_capacity];
    var offset: usize = 0;
    const header = SnapshotHeader{
        .magic = SNAPSHOT_MAGIC,
        .version = SNAPSHOT_VERSION,
        .capacity = context.capacity,
        .grid_width = context.grid_width,
        .grid_height = context.grid_height,
        .cell_size = context.cell_size,
        .alive_count = context.alive_count,
        .free_head = context.free_head,
        .previous_buttons = context.previous_buttons,
        .event_read = context.event_read,
        .event_write = context.event_write,
        .event_count = context.event_count,
        .path_start = context.path_start,
        .path_goal = context.path_goal,
        .path_queue_head = context.path_queue_head,
        .path_queue_tail = context.path_queue_tail,
        .path_state = context.path_state,
        .input = context.input,
        .gravity = context.gravity,
    };
    if (!writeBytes(bytes, &offset, std.mem.asBytes(&header))) return 0;
    if (!writeBytes(bytes, &offset, std.mem.sliceAsBytes(context.ids))) return 0;
    if (!writeBytes(bytes, &offset, std.mem.sliceAsBytes(context.sprite_ids))) return 0;
    if (!writeBytes(bytes, &offset, std.mem.sliceAsBytes(context.positions_x))) return 0;
    if (!writeBytes(bytes, &offset, std.mem.sliceAsBytes(context.positions_y))) return 0;
    if (!writeBytes(bytes, &offset, std.mem.sliceAsBytes(context.velocities_x))) return 0;
    if (!writeBytes(bytes, &offset, std.mem.sliceAsBytes(context.velocities_y))) return 0;
    if (!writeBytes(bytes, &offset, std.mem.sliceAsBytes(context.alive))) return 0;
    if (!writeBytes(bytes, &offset, std.mem.sliceAsBytes(context.anchor_counts))) return 0;
    if (!writeBytes(bytes, &offset, std.mem.sliceAsBytes(context.next_free))) return 0;
    if (!writeBytes(bytes, &offset, std.mem.sliceAsBytes(context.events[0..]))) return 0;
    if (!writeBytes(bytes, &offset, std.mem.sliceAsBytes(context.path_visited))) return 0;
    if (!writeBytes(bytes, &offset, std.mem.sliceAsBytes(context.path_parent))) return 0;
    if (!writeBytes(bytes, &offset, std.mem.sliceAsBytes(context.path_queue))) return 0;
    if (!writeBytes(bytes, &offset, std.mem.asBytes(&context.camera))) return 0;
    if (!writeBytes(bytes, &offset, std.mem.sliceAsBytes(context.camera_matrix[0..]))) return 0;
    if (!writeBytes(bytes, &offset, std.mem.sliceAsBytes(context.render_z))) return 0;
    if (!writeBytes(bytes, &offset, std.mem.sliceAsBytes(context.animation_first_frame))) return 0;
    if (!writeBytes(bytes, &offset, std.mem.sliceAsBytes(context.animation_frame_ids))) return 0;
    if (!writeBytes(bytes, &offset, std.mem.sliceAsBytes(context.animation_frame))) return 0;
    if (!writeBytes(bytes, &offset, std.mem.sliceAsBytes(context.animation_frame_count))) return 0;
    if (!writeBytes(bytes, &offset, std.mem.sliceAsBytes(context.animation_elapsed))) return 0;
    if (!writeBytes(bytes, &offset, std.mem.sliceAsBytes(context.animation_frame_duration))) return 0;
    if (!writeBytes(bytes, &offset, std.mem.sliceAsBytes(context.animation_loop))) return 0;
    if (!writeBytes(bytes, &offset, std.mem.sliceAsBytes(context.body_type))) return 0;
    if (!writeBytes(bytes, &offset, std.mem.sliceAsBytes(context.shape_type))) return 0;
    if (!writeBytes(bytes, &offset, std.mem.sliceAsBytes(context.shape_radius))) return 0;
    if (!writeBytes(bytes, &offset, std.mem.sliceAsBytes(context.capsule_half_length))) return 0;
    context.telemetry.ffi_serialization_us = (timestampNs() - serialization_start) / 1000;
    return offset;
}

export fn engine_snapshot_read(context: *EngineContext, input: [*]const u8, input_size: usize) bool {
    if (input_size < @sizeOf(SnapshotHeader)) return false;
    const bytes = input[0..input_size];
    var offset: usize = 0;
    var header: SnapshotHeader = undefined;
    if (!readBytes(bytes, &offset, std.mem.asBytes(&header))) return false;
    if (header.magic != SNAPSHOT_MAGIC or header.version != SNAPSHOT_VERSION or
        header.capacity != context.capacity or header.grid_width != context.grid_width or
        header.grid_height != context.grid_height or input_size < snapshotPayloadSize(context)) return false;
    context.alive_count = @intCast(header.alive_count);
    context.cell_size = header.cell_size;
    context.free_head = header.free_head;
    context.previous_buttons = header.previous_buttons;
    context.event_read = @intCast(header.event_read);
    context.event_write = @intCast(header.event_write);
    context.event_count = @intCast(header.event_count);
    context.path_start = header.path_start;
    context.path_goal = header.path_goal;
    context.path_queue_head = @intCast(header.path_queue_head);
    context.path_queue_tail = @intCast(header.path_queue_tail);
    context.path_state = header.path_state;
    context.input = header.input;
    context.gravity = header.gravity;
    if (!readBytes(bytes, &offset, std.mem.sliceAsBytes(context.ids))) return false;
    if (!readBytes(bytes, &offset, std.mem.sliceAsBytes(context.sprite_ids))) return false;
    if (!readBytes(bytes, &offset, std.mem.sliceAsBytes(context.positions_x))) return false;
    if (!readBytes(bytes, &offset, std.mem.sliceAsBytes(context.positions_y))) return false;
    if (!readBytes(bytes, &offset, std.mem.sliceAsBytes(context.velocities_x))) return false;
    if (!readBytes(bytes, &offset, std.mem.sliceAsBytes(context.velocities_y))) return false;
    if (!readBytes(bytes, &offset, std.mem.sliceAsBytes(context.alive))) return false;
    if (!readBytes(bytes, &offset, std.mem.sliceAsBytes(context.anchor_counts))) return false;
    if (!readBytes(bytes, &offset, std.mem.sliceAsBytes(context.next_free))) return false;
    if (!readBytes(bytes, &offset, std.mem.sliceAsBytes(context.events[0..]))) return false;
    if (!readBytes(bytes, &offset, std.mem.sliceAsBytes(context.path_visited))) return false;
    if (!readBytes(bytes, &offset, std.mem.sliceAsBytes(context.path_parent))) return false;
    if (!readBytes(bytes, &offset, std.mem.sliceAsBytes(context.path_queue))) return false;
    if (!readBytes(bytes, &offset, std.mem.asBytes(&context.camera))) return false;
    if (!readBytes(bytes, &offset, std.mem.sliceAsBytes(context.camera_matrix[0..]))) return false;
    if (!readBytes(bytes, &offset, std.mem.sliceAsBytes(context.render_z))) return false;
    if (!readBytes(bytes, &offset, std.mem.sliceAsBytes(context.animation_first_frame))) return false;
    if (!readBytes(bytes, &offset, std.mem.sliceAsBytes(context.animation_frame_ids))) return false;
    if (!readBytes(bytes, &offset, std.mem.sliceAsBytes(context.animation_frame))) return false;
    if (!readBytes(bytes, &offset, std.mem.sliceAsBytes(context.animation_frame_count))) return false;
    if (!readBytes(bytes, &offset, std.mem.sliceAsBytes(context.animation_elapsed))) return false;
    if (!readBytes(bytes, &offset, std.mem.sliceAsBytes(context.animation_frame_duration))) return false;
    if (!readBytes(bytes, &offset, std.mem.sliceAsBytes(context.animation_loop))) return false;
    if (!readBytes(bytes, &offset, std.mem.sliceAsBytes(context.body_type))) return false;
    if (!readBytes(bytes, &offset, std.mem.sliceAsBytes(context.shape_type))) return false;
    if (!readBytes(bytes, &offset, std.mem.sliceAsBytes(context.shape_radius))) return false;
    if (!readBytes(bytes, &offset, std.mem.sliceAsBytes(context.capsule_half_length))) return false;
    updateCameraMatrix(context);
    sortRenderOrder(context);
    rebuildSpatialGrid(context);
    return true;
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
            pushEvent(context, EVENT_PATH_READY, current);
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
    updateCameraMatrix(context);
    const pressed = context.input.buttons & ~context.previous_buttons;
    if ((pressed & 1) != 0) pushEvent(context, EVENT_PLAY_SOUND, 0);
    if ((pressed & 2) != 0) pushEvent(context, EVENT_PLAYER_DIED, 0);
    context.previous_buttons = context.input.buttons;
    const physics_start = timestampNs();
    for (0..context.capacity) |index| {
        if (!context.alive[index] or context.body_type[index] == BODY_STATIC) continue;
        if (context.body_type[index] == BODY_DYNAMIC) context.velocities_y[index] += context.gravity * dt;
        context.positions_x[index] += context.velocities_x[index] * dt;
        context.positions_y[index] += context.velocities_y[index] * dt;
    }
    updateAnimations(context, dt);
    context.telemetry.physics_us = (timestampNs() - physics_start) / 1000;
    const spatial_start = timestampNs();
    sortRenderOrder(context);
    rebuildSpatialGrid(context);
    context.telemetry.spatial_sort_us = (timestampNs() - spatial_start) / 1000;
    context.telemetry.frame_us = (timestampNs() - frame_start) / 1000;
}

export fn add_numbers(a: c_int, b: c_int) c_int {
    return a + b;
}
