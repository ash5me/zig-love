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

fn applyImpulse(context: *EngineContext, first: usize, second: ?usize, normal_x: f32, normal_y: f32, restitution: f32, friction: f32) void {
    const first_inverse_mass: f32 = if (context.body_type[first] == BODY_DYNAMIC) 1 else 0;
    const second_inverse_mass: f32 = if (second) |index| if (context.body_type[index] == BODY_DYNAMIC) 1 else 0 else 0;
    const total_inverse_mass = first_inverse_mass + second_inverse_mass;
    if (total_inverse_mass == 0) return;
    const second_velocity_x = if (second) |index| context.velocities_x[index] else 0;
    const second_velocity_y = if (second) |index| context.velocities_y[index] else 0;
    const relative_x = second_velocity_x - context.velocities_x[first];
    const relative_y = second_velocity_y - context.velocities_y[first];
    const normal_velocity = relative_x * normal_x + relative_y * normal_y;
    if (normal_velocity < 0) {
        const impulse = -(1 + restitution) * normal_velocity / total_inverse_mass;
        const impulse_x = impulse * normal_x;
        const impulse_y = impulse * normal_y;
        context.velocities_x[first] -= impulse_x * first_inverse_mass;
        context.velocities_y[first] -= impulse_y * first_inverse_mass;
        if (second) |index| {
            context.velocities_x[index] += impulse_x * second_inverse_mass;
            context.velocities_y[index] += impulse_y * second_inverse_mass;
        }
        const tangent_x = relative_x - normal_velocity * normal_x;
        const tangent_y = relative_y - normal_velocity * normal_y;
        const tangent_length = @sqrt(tangent_x * tangent_x + tangent_y * tangent_y);
        if (tangent_length > 0) {
            const tangent_velocity = (relative_x * tangent_x + relative_y * tangent_y) / tangent_length;
            const friction_impulse = -tangent_velocity * friction / total_inverse_mass;
            const friction_x = friction_impulse * tangent_x / tangent_length;
            const friction_y = friction_impulse * tangent_y / tangent_length;
            context.velocities_x[first] -= friction_x * first_inverse_mass;
            context.velocities_y[first] -= friction_y * first_inverse_mass;
            if (second) |index| {
                context.velocities_x[index] += friction_x * second_inverse_mass;
                context.velocities_y[index] += friction_y * second_inverse_mass;
            }
        }
    }
}

fn resolveEntityContact(context: *EngineContext, first: usize, second: usize, contact: math.Contact) void {
    const first_dynamic = context.body_type[first] == types.BODY_DYNAMIC;
    const second_dynamic = context.body_type[second] == types.BODY_DYNAMIC;
    if (!first_dynamic and !second_dynamic) return;
    const correction = @max(contact.penetration - 0.001, 0) * 0.8;
    if (first_dynamic and second_dynamic) {
        context.positions_x[first] -= contact.normal_x * correction * 0.5;
        context.positions_y[first] -= contact.normal_y * correction * 0.5;
        context.positions_x[second] += contact.normal_x * correction * 0.5;
        context.positions_y[second] += contact.normal_y * correction * 0.5;
        applyImpulse(context, first, second, contact.normal_x, contact.normal_y, 0.1, 0.6);
        if (contact.normal_y > 0.5) context.grounded[first] = true;
        if (contact.normal_y < -0.5) context.grounded[second] = true;
    } else if (first_dynamic) {
        context.positions_x[first] -= contact.normal_x * correction;
        context.positions_y[first] -= contact.normal_y * correction;
        applyImpulse(context, first, null, contact.normal_x, contact.normal_y, 0.05, 0.8);
        if (contact.normal_y > 0.5) context.grounded[first] = true;
    } else {
        context.positions_x[second] += contact.normal_x * correction;
        context.positions_y[second] += contact.normal_y * correction;
        applyImpulse(context, second, null, -contact.normal_x, -contact.normal_y, 0.05, 0.8);
        if (contact.normal_y < -0.5) context.grounded[second] = true;
    }
}

fn resolveStaticCollider(context: *EngineContext, index: usize, collider: usize) void {
    if (!context.collision_enabled[index] or context.body_type[index] != types.BODY_DYNAMIC) return;
    var contact = math.aabbContact(context, index, context.static_collider_x[collider], context.static_collider_y[collider], context.static_collider_half_width[collider], context.static_collider_half_height[collider]) orelse return;
    if (@abs(contact.normal_y) > @abs(contact.normal_x) and context.velocities_y[index] != 0) {
        contact.normal_y = if (context.velocities_y[index] > 0) 1 else -1;
    } else if (context.velocities_x[index] != 0) {
        contact.normal_x = if (context.velocities_x[index] > 0) 1 else -1;
    }
    const correction = @max(contact.penetration - 0.001, 0) * 0.85;
    context.positions_x[index] -= contact.normal_x * correction;
    context.positions_y[index] -= contact.normal_y * correction;
    applyImpulse(context, index, null, contact.normal_x, contact.normal_y, 0.05, 0.8);
    if (contact.normal_y > 0.5) context.grounded[index] = true;
}

fn solveCollisions(context: *EngineContext) void {
    for (0..4) |_| {
        for (0..context.capacity) |index| {
            if (!context.alive[index] or !context.collision_enabled[index] or context.body_type[index] != BODY_DYNAMIC) continue;
            for (0..types.MAX_STATIC_COLLIDERS) |collider| {
                if (context.static_collider_alive[collider]) resolveStaticCollider(context, index, collider);
            }
        }
        for (0..context.capacity) |first| {
            if (!context.alive[first] or !context.collision_enabled[first]) continue;
            for (first + 1..context.capacity) |second| {
                if (!context.alive[second] or !context.collision_enabled[second]) continue;
                if (math.shapeContact(context, first, second)) |contact| resolveEntityContact(context, first, second, contact);
            }
        }
    }
}

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

    @memset(context.grounded, false);
    var substeps: usize = 1;
    for (0..context.capacity) |index| {
        if (!context.alive[index] or !context.collision_enabled[index] or context.body_type[index] != types.BODY_DYNAMIC) continue;
        const displacement = @sqrt(context.velocities_x[index] * context.velocities_x[index] + context.velocities_y[index] * context.velocities_y[index]) * dt;
        const extent = @max(@min(context.shape_half_width[index], context.shape_half_height[index]), 1);
        substeps = @max(substeps, @min(@as(usize, 32), @as(usize, @intFromFloat(@ceil(displacement / extent)))));
    }
    const step_dt = dt / @as(f32, @floatFromInt(substeps));
    for (0..substeps) |_| {
        for (0..context.capacity) |index| {
            if (!context.alive[index] or context.body_type[index] == BODY_STATIC) continue;
            if (context.body_type[index] == types.BODY_DYNAMIC) context.velocities_y[index] += context.gravity * step_dt;
            context.positions_x[index] += context.velocities_x[index] * step_dt;
            context.positions_y[index] += context.velocities_y[index] * step_dt;
        }
        solveCollisions(context);
    }

    updateAnimations(context, dt);
    sortRenderOrder(context);
    rebuildSpatialGrid(context);
}
