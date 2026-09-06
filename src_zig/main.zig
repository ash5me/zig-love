const std = @import("std");

const INVALID_INDEX: u32 = std.math.maxInt(u32);
const EVENT_QUEUE_CAPACITY: usize = 256;

pub const InputState = extern struct {
    buttons: u32,
    mouse_x: f32,
    mouse_y: f32,
};

pub const EngineEvent = extern struct {
    id: u32,
    value: u32,
};

pub const EVENT_PLAY_SOUND: u32 = 1;
pub const EVENT_PLAYER_DIED: u32 = 2;
pub const EVENT_PATH_READY: u32 = 3;

const PATH_IDLE: u32 = 0;
const PATH_WORKING: u32 = 1;
const PATH_FOUND: u32 = 2;
const PATH_FAILED: u32 = 3;

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
};

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
    allocator.destroy(value);
}

export fn engine_entity_capacity(context: *const EngineContext) usize {
    return context.capacity;
}
export fn engine_alive_count(context: *const EngineContext) usize {
    return context.alive_count;
}
export fn engine_positions_x(context: *EngineContext) [*]f32 {
    return context.positions_x.ptr;
}
export fn engine_positions_y(context: *EngineContext) [*]f32 {
    return context.positions_y.ptr;
}
export fn engine_sprite_ids(context: *EngineContext) [*]u64 {
    return context.sprite_ids.ptr;
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
    context.alive[index] = true;
    context.alive_count += 1;
    return index;
}

export fn engine_destroy_entity(context: *EngineContext, index: u32) bool {
    if (index >= context.capacity or !context.alive[index]) return false;
    context.alive[index] = false;
    context.ids[index] = 0;
    context.next_free[index] = context.free_head;
    context.free_head = index;
    context.alive_count -= 1;
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
    const pressed = context.input.buttons & ~context.previous_buttons;
    if ((pressed & 1) != 0) pushEvent(context, EVENT_PLAY_SOUND, 0);
    if ((pressed & 2) != 0) pushEvent(context, EVENT_PLAYER_DIED, 0);
    context.previous_buttons = context.input.buttons;
    for (0..context.capacity) |index| {
        if (!context.alive[index]) continue;
        context.positions_x[index] += context.velocities_x[index] * dt;
        context.positions_y[index] += context.velocities_y[index] * dt;
    }
    rebuildSpatialGrid(context);
}

export fn add_numbers(a: c_int, b: c_int) c_int {
    return a + b;
}
