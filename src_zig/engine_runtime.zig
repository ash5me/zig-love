const std = @import("std");
const types = @import("engine_types.zig");
const math = @import("engine_math.zig");
const physics = @import("engine_physics.zig");
const EngineContext = types.EngineContext;
const INVALID_INDEX = types.INVALID_INDEX;
const EVENT_PLAY_SOUND = types.EVENT_PLAY_SOUND;
const EVENT_PLAYER_DIED = types.EVENT_PLAYER_DIED;
const EVENT_PATH_READY = types.EVENT_PATH_READY;
pub fn pushEvent(context: *EngineContext, id: u32, value: u32) void {
    if (context.event_count == types.EVENT_QUEUE_CAPACITY) {
        context.dropped_events += 1;
        return;
    }
    context.events[context.event_write] = .{ .id = id, .value = value };
    context.event_write = (context.event_write + 1) % types.EVENT_QUEUE_CAPACITY;
    context.event_count += 1;
}

pub fn pushSpatialSound(context: *EngineContext, sound_id: u64, source_x: f32, source_y: f32, max_distance: f32, base_volume: f32) void {
    if (max_distance <= 0 or base_volume <= 0 or context.audio_count == types.EVENT_QUEUE_CAPACITY) {
        if (context.audio_count == types.EVENT_QUEUE_CAPACITY) context.audio_dropped += 1;
        return;
    }
    const dx = source_x - context.audio_listener_x;
    const dy = source_y - context.audio_listener_y;
    const distance = @sqrt(dx * dx + dy * dy);
    const normalized_distance = @min(distance / max_distance, 1);
    context.audio_commands[context.audio_write] = .{
        .sound_id = sound_id,
        .source_x = source_x,
        .source_y = source_y,
        .volume = base_volume * (1 - normalized_distance),
        .pan = @max(-1, @min(1, dx / max_distance)),
    };
    context.audio_write = (context.audio_write + 1) % types.EVENT_QUEUE_CAPACITY;
    context.audio_count += 1;
}

pub fn clearGrid(context: *EngineContext) void {
    @memset(context.grid_heads, INVALID_INDEX);
    @memset(context.next_in_cell, INVALID_INDEX);
}

pub fn rebuildSpatialGrid(context: *EngineContext) void {
    clearGrid(context);
    for (0..context.capacity) |index| {
        if (!types.isAlive(context, index)) continue;
        const cell = math.cellIndex(context, context.positions_x[index], context.positions_y[index]) orelse continue;
        context.next_in_cell[index] = context.grid_heads[cell];
        context.grid_heads[cell] = @intCast(index);
    }
}

pub fn sortRenderOrder(context: *EngineContext) void {
    var count: usize = 0;
    for (0..context.capacity) |index| {
        if (!types.isAlive(context, index)) continue;
        context.depth_order[index] = @intFromFloat(@round(context.positions_z[index] * 1000));
        context.shadow_x[index] = context.positions_x[index];
        context.shadow_y[index] = context.positions_z[index];
        context.render_order[count] = @intCast(index);
        count += 1;
    }
    var index: usize = 1;
    while (index < count) : (index += 1) {
        const value = context.render_order[index];
        var position = index;
        while (position > 0 and renderKey(context, context.render_order[position - 1]) > renderKey(context, value)) : (position -= 1) {
            context.render_order[position] = context.render_order[position - 1];
        }
        context.render_order[position] = value;
    }
}

fn renderKey(context: *const EngineContext, index: u32) i32 {
    return if (context.ground_collision_enabled[index]) context.depth_order[index] else context.render_z[index];
}

pub fn updateAnimations(context: *EngineContext, dt: f32) void {
    for (0..context.capacity) |index| {
        if (!types.isAlive(context, index) or context.animation_frame_count[index] == 0) continue;
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

pub fn updateParticles(context: *EngineContext, dt: f32) void {
    for (0..types.MAX_PARTICLES) |index| {
        if (!context.particle_alive[index]) continue;
        context.particle_lifetime[index] -= dt;
        if (context.particle_lifetime[index] <= 0) {
            context.particle_alive[index] = false;
            context.particle_count -= 1;
            continue;
        }
        context.particle_x[index] += context.particle_velocity_x[index] * dt;
        context.particle_y[index] += context.particle_velocity_y[index] * dt;
        context.particle_alpha[index] = @max(0, context.particle_lifetime[index] / context.particle_max_lifetime[index]);
    }
}

pub fn engineTick(context: *EngineContext, dt: f32) void {
    const pressed = context.input.buttons & ~context.previous_buttons;
    if ((pressed & 1) != 0) {
        pushEvent(context, EVENT_PLAY_SOUND, 0);
        pushSpatialSound(context, 1, context.audio_listener_x, context.audio_listener_y, 512, 1);
    }
    if ((pressed & 2) != 0) pushEvent(context, EVENT_PLAYER_DIED, 0);
    context.previous_buttons = context.input.buttons;

    physics.step(context, dt);

    updateAnimations(context, dt);
    updateParticles(context, dt);
    sortRenderOrder(context);
    rebuildSpatialGrid(context);
}
