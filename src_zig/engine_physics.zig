const types = @import("engine_types.zig");
const math = @import("engine_math.zig");
const EngineContext = types.EngineContext;

fn applyImpulse(context: *EngineContext, first: usize, second: ?usize, normal_x: f32, normal_y: f32, restitution: f32, friction: f32) void {
    const first_inverse_mass: f32 = if (context.body_type[first] == types.BODY_DYNAMIC) 1 else 0;
    const second_inverse_mass: f32 = if (second) |index| if (context.body_type[index] == types.BODY_DYNAMIC) 1 else 0 else 0;
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
            if (!types.isAlive(context, index) or !context.collision_enabled[index] or context.body_type[index] != types.BODY_DYNAMIC) continue;
            for (0..types.MAX_STATIC_COLLIDERS) |collider| {
                if (context.static_collider_alive[collider]) resolveStaticCollider(context, index, collider);
            }
        }
        for (0..context.capacity) |first| {
            if (!types.isAlive(context, first) or !context.collision_enabled[first]) continue;
            for (first + 1..context.capacity) |second| {
                if (!types.isAlive(context, second) or !context.collision_enabled[second]) continue;
                if (math.shapeContact(context, first, second)) |contact| resolveEntityContact(context, first, second, contact);
            }
        }
    }
}

fn solveGroundCollisions(context: *EngineContext) void {
    for (0..4) |_| {
        for (0..context.capacity) |first| {
            if (!types.isAlive(context, first) or !context.ground_collision_enabled[first] or context.body_type[first] != types.BODY_DYNAMIC) continue;
            for (first + 1..context.capacity) |second| {
                if (!types.isAlive(context, second) or !context.ground_collision_enabled[second]) continue;
                const dx = context.positions_x[first] - context.positions_x[second];
                const dz = context.positions_z[first] - context.positions_z[second];
                const overlap_x = context.ground_half_width[first] + context.ground_half_width[second] - @abs(dx);
                const overlap_z = context.ground_half_depth[first] + context.ground_half_depth[second] - @abs(dz);
                if (overlap_x <= 0 or overlap_z <= 0) continue;
                const first_dynamic = context.body_type[first] == types.BODY_DYNAMIC;
                const second_dynamic = context.body_type[second] == types.BODY_DYNAMIC;
                if (overlap_x < overlap_z) {
                    const direction: f32 = if (dx >= 0) 1 else -1;
                    const first_share: f32 = if (second_dynamic) 0.5 else 1;
                    const second_share: f32 = if (first_dynamic) 0.5 else 1;
                    if (first_dynamic) context.positions_x[first] += direction * overlap_x * first_share;
                    if (second_dynamic) context.positions_x[second] -= direction * overlap_x * second_share;
                    if (first_dynamic) context.velocities_x[first] = 0;
                    if (second_dynamic) context.velocities_x[second] = 0;
                } else {
                    const direction: f32 = if (dz >= 0) 1 else -1;
                    const first_share: f32 = if (second_dynamic) 0.5 else 1;
                    const second_share: f32 = if (first_dynamic) 0.5 else 1;
                    if (first_dynamic) context.positions_z[first] += direction * overlap_z * first_share;
                    if (second_dynamic) context.positions_z[second] -= direction * overlap_z * second_share;
                    if (first_dynamic) context.velocities_z[first] = 0;
                    if (second_dynamic) context.velocities_z[second] = 0;
                }
            }
        }
    }
}

pub fn step(context: *EngineContext, dt: f32) void {
    @memset(context.grounded, false);
    var substeps: usize = 1;
    for (0..context.capacity) |index| {
        if (!types.isAlive(context, index) or !context.collision_enabled[index] or context.body_type[index] != types.BODY_DYNAMIC) continue;
        const displacement = @sqrt(context.velocities_x[index] * context.velocities_x[index] + context.velocities_y[index] * context.velocities_y[index]) * dt;
        const extent = @max(@min(context.shape_half_width[index], context.shape_half_height[index]), 1);
        substeps = @max(substeps, @min(@as(usize, 32), @as(usize, @intFromFloat(@ceil(displacement / extent)))));
    }
    const step_dt = dt / @as(f32, @floatFromInt(substeps));
    for (0..substeps) |_| {
        for (0..context.capacity) |index| {
            if (!types.isAlive(context, index) or context.body_type[index] == types.BODY_STATIC) continue;
            if (context.body_type[index] == types.BODY_DYNAMIC) context.velocities_y[index] += context.gravity * step_dt;
            context.positions_x[index] += context.velocities_x[index] * step_dt;
            context.positions_y[index] += context.velocities_y[index] * step_dt;
            if (context.ground_collision_enabled[index]) context.positions_z[index] += context.velocities_z[index] * step_dt;
        }
        solveCollisions(context);
        solveGroundCollisions(context);
    }
}
