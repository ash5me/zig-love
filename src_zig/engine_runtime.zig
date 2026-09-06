const std = @import("std");
const types = @import("engine_types.zig");
const math = @import("engine_math.zig");
const EngineContext = types.EngineContext;
const INVALID_INDEX = types.INVALID_INDEX;
const EVENT_PLAY_SOUND = types.EVENT_PLAY_SOUND;
const EVENT_PLAYER_DIED = types.EVENT_PLAYER_DIED;
const EVENT_PATH_READY = types.EVENT_PATH_READY;
const BODY_DYNAMIC = types.BODY_DYNAMIC;
const BODY_STATIC = types.BODY_STATIC;

pub fn pushEvent(context: *EngineContext, id: u32, value: u32) void {
    if (context.event_count == types.EVENT_QUEUE_CAPACITY) return;
    context.events[context.event_write] = .{ .id = id, .value = value };
    context.event_write = (context.event_write + 1) % types.EVENT_QUEUE_CAPACITY;
    context.event_count += 1;
}

pub fn clearGrid(context: *EngineContext) void {
    @memset(context.grid_heads, INVALID_INDEX);
    @memset(context.next_in_cell, INVALID_INDEX);
}

pub fn rebuildSpatialGrid(context: *EngineContext) void {
    clearGrid(context);
    for (0..context.capacity) |index| {
        if (!context.alive[index]) continue;
        const cell = math.cellIndex(context, context.positions_x[index], context.positions_y[index]) orelse continue;
        context.next_in_cell[index] = context.grid_heads[cell];
        context.grid_heads[cell] = @intCast(index);
    }
}

pub fn sortRenderOrder(context: *EngineContext) void {
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

pub fn updateAnimations(context: *EngineContext, dt: f32) void {
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

pub fn engineTick(context: *EngineContext, dt: f32) void {
    const pressed = context.input.buttons & ~context.previous_buttons;
    if ((pressed & 1) != 0) pushEvent(context, EVENT_PLAY_SOUND, 0);
    if ((pressed & 2) != 0) pushEvent(context, EVENT_PLAYER_DIED, 0);
    context.previous_buttons = context.input.buttons;

    for (0..context.capacity) |index| {
        if (!context.alive[index] or context.body_type[index] == BODY_STATIC) continue;
        if (context.body_type[index] == types.BODY_DYNAMIC) context.velocities_y[index] += context.gravity * dt;
        context.positions_x[index] += context.velocities_x[index] * dt;
        context.positions_y[index] += context.velocities_y[index] * dt;
    }

    updateAnimations(context, dt);
    sortRenderOrder(context);
    rebuildSpatialGrid(context);
}
