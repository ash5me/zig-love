const std = @import("std");
const types = @import("engine_types.zig");
const ecs = @import("ecs");
const EngineContext = types.EngineContext;

pub const DELTA_MAGIC: u32 = types.SNAPSHOT_MAGIC ^ 0xFFFFFFFF;
pub const DeltaHeader = extern struct {
    magic: u32,
    version: u32,
    payload_size: u64,
};
const SnapshotHeader = types.SnapshotHeader;

pub fn snapshotPayloadSize(context: *const EngineContext) usize {
    return @sizeOf(SnapshotHeader) +
        @sizeOf(u64) * context.capacity * 2 +
        @sizeOf(f32) * context.capacity * 4 +
        @sizeOf(u32) * context.capacity +
        @sizeOf(types.EngineEvent) * types.EVENT_QUEUE_CAPACITY +
        @sizeOf(bool) * context.grid_width * context.grid_height +
        @sizeOf(u32) * context.grid_width * context.grid_height * 2 +
        @sizeOf(types.CameraState) + @sizeOf(f32) * 9 +
        @sizeOf(i32) * context.capacity + @sizeOf(u64) * context.capacity * 2 +
        @sizeOf(u32) * context.capacity * 2 + @sizeOf(f32) * context.capacity * 2 +
        @sizeOf(bool) * context.capacity + @sizeOf(u8) * context.capacity * 2 +
        @sizeOf(f32) * context.capacity * 5 + @sizeOf(u8) * context.capacity +
        @sizeOf(f32) * context.capacity * types.MAX_POLYGON_VERTICES * 2 +
        @sizeOf(bool) * context.capacity * 2 + @sizeOf(bool) * types.MAX_STATIC_COLLIDERS +
        @sizeOf(f32) * types.MAX_STATIC_COLLIDERS * 4 +
        @sizeOf(bool) * context.capacity +
        @sizeOf(u32) * types.MAX_TILEMAP_TILES +
        @sizeOf(bool) * types.MAX_PARTICLES + @sizeOf(f32) * types.MAX_PARTICLES * 11 +
        @sizeOf(bool) * types.MAX_LIGHTS + @sizeOf(f32) * types.MAX_LIGHTS * 7;
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

pub fn snapshotDeltaSize(context: *const EngineContext) usize {
    return @sizeOf(DeltaHeader) + snapshotPayloadSize(context) * 6;
}

fn writeU32(output: []u8, offset: *usize, value: u32) bool {
    return writeBytes(output, offset, std.mem.asBytes(&value));
}

fn readU32(input: []const u8, offset: *usize, value: *u32) bool {
    var bytes: [@sizeOf(u32)]u8 = undefined;
    if (!readBytes(input, offset, &bytes)) return false;
    @memcpy(std.mem.asBytes(value), &bytes);
    return true;
}

pub fn snapshotWriteDelta(context: *EngineContext, base: [*]const u8, base_size: usize, output: [*]u8, output_capacity: usize) usize {
    const payload_size = snapshotPayloadSize(context);
    if (base_size < payload_size or output_capacity < @sizeOf(DeltaHeader)) return 0;
    const allocator = std.heap.page_allocator;
    const current = allocator.alloc(u8, payload_size) catch return 0;
    defer allocator.free(current);
    if (snapshotWrite(context, current.ptr, payload_size) != payload_size) return 0;
    const bytes = output[0..output_capacity];
    var offset: usize = 0;
    const header = DeltaHeader{ .magic = DELTA_MAGIC, .version = types.SNAPSHOT_VERSION, .payload_size = payload_size };
    if (!writeBytes(bytes, &offset, std.mem.asBytes(&header))) return 0;
    var index: usize = 0;
    const base_bytes = base[0..base_size];
    while (index < payload_size) {
        var run_end = index;
        const is_zero = current[index] == base_bytes[index];
        while (run_end < payload_size and (current[run_end] == base_bytes[run_end]) == is_zero) : (run_end += 1) {}
        const length: u32 = @intCast(run_end - index);
        if (is_zero) {
            if (!writeBytes(bytes, &offset, &[_]u8{0})) return 0;
            if (!writeU32(bytes, &offset, length)) return 0;
        } else {
            if (!writeBytes(bytes, &offset, &[_]u8{1})) return 0;
            if (!writeU32(bytes, &offset, length)) return 0;
            for (index..run_end) |changed| {
                const value = current[changed] ^ base_bytes[changed];
                if (!writeBytes(bytes, &offset, &[_]u8{value})) return 0;
            }
        }
        index = run_end;
    }
    return offset;
}

pub fn snapshotApplyDelta(context: *EngineContext, input: [*]const u8, input_size: usize) bool {
    if (input_size < @sizeOf(DeltaHeader)) return false;
    const bytes = input[0..input_size];
    var offset: usize = 0;
    var header: DeltaHeader = undefined;
    if (!readBytes(bytes, &offset, std.mem.asBytes(&header))) return false;
    const payload_size = snapshotPayloadSize(context);
    if (header.magic != DELTA_MAGIC or header.version != types.SNAPSHOT_VERSION or header.payload_size != payload_size) return false;
    const allocator = std.heap.page_allocator;
    const current = allocator.alloc(u8, payload_size) catch return false;
    defer allocator.free(current);
    if (snapshotWrite(context, current.ptr, payload_size) != payload_size) return false;
    var index: usize = 0;
    while (index < payload_size) {
        if (offset >= bytes.len) return false;
        const kind = bytes[offset];
        offset += 1;
        var length: u32 = 0;
        if (!readU32(bytes, &offset, &length) or length == 0 or index + length > payload_size) return false;
        if (kind == 0) {
            index += length;
        } else if (kind == 1) {
            if (bytes.len -| offset < length) return false;
            for (0..length) |changed| {
                current[index + changed] ^= bytes[offset + changed];
            }
            offset += length;
            index += length;
        } else return false;
    }
    return snapshotRead(context, current.ptr, payload_size);
}

pub fn snapshotWrite(context: *EngineContext, output: [*]u8, output_capacity: usize) usize {
    const required = snapshotPayloadSize(context);
    if (output_capacity < required) return 0;
    const bytes = output[0..output_capacity];
    const allocator = std.heap.page_allocator;
    const alive = allocator.alloc(bool, context.capacity) catch return 0;
    defer allocator.free(alive);
    for (0..context.capacity) |index| alive[index] = types.isAlive(context, index);
    var offset: usize = 0;
    const header = SnapshotHeader{
        .magic = types.SNAPSHOT_MAGIC,
        .version = types.SNAPSHOT_VERSION,
        .capacity = context.capacity,
        .grid_width = context.grid_width,
        .grid_height = context.grid_height,
        .cell_size = context.cell_size,
        .alive_count = context.alive_count,
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
        .dropped_events = context.dropped_events,
        .tilemap_width = context.tilemap_width,
        .tilemap_height = context.tilemap_height,
        .tilemap_tile_width = context.tilemap_tile_width,
        .tilemap_tile_height = context.tilemap_tile_height,
        .particle_count = context.particle_count,
        .light_count = context.light_count,
    };
    if (!writeBytes(bytes, &offset, std.mem.asBytes(&header))) return 0;
    if (!writeBytes(bytes, &offset, std.mem.sliceAsBytes(context.ids))) return 0;
    if (!writeBytes(bytes, &offset, std.mem.sliceAsBytes(context.sprite_ids))) return 0;
    if (!writeBytes(bytes, &offset, std.mem.sliceAsBytes(context.positions_x))) return 0;
    if (!writeBytes(bytes, &offset, std.mem.sliceAsBytes(context.positions_y))) return 0;
    if (!writeBytes(bytes, &offset, std.mem.sliceAsBytes(context.velocities_x))) return 0;
    if (!writeBytes(bytes, &offset, std.mem.sliceAsBytes(context.velocities_y))) return 0;
    if (!writeBytes(bytes, &offset, std.mem.sliceAsBytes(context.anchor_counts))) return 0;
    if (!writeBytes(bytes, &offset, std.mem.sliceAsBytes(alive))) return 0;
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
    if (!writeBytes(bytes, &offset, std.mem.sliceAsBytes(context.shape_half_width))) return 0;
    if (!writeBytes(bytes, &offset, std.mem.sliceAsBytes(context.shape_half_height))) return 0;
    if (!writeBytes(bytes, &offset, std.mem.sliceAsBytes(context.shape_rotation))) return 0;
    if (!writeBytes(bytes, &offset, std.mem.sliceAsBytes(context.polygon_counts))) return 0;
    if (!writeBytes(bytes, &offset, std.mem.sliceAsBytes(context.polygon_vertices))) return 0;
    if (!writeBytes(bytes, &offset, std.mem.sliceAsBytes(context.grounded))) return 0;
    if (!writeBytes(bytes, &offset, std.mem.sliceAsBytes(context.collision_enabled))) return 0;
    if (!writeBytes(bytes, &offset, std.mem.sliceAsBytes(context.static_collider_alive[0..]))) return 0;
    if (!writeBytes(bytes, &offset, std.mem.sliceAsBytes(context.static_collider_x[0..]))) return 0;
    if (!writeBytes(bytes, &offset, std.mem.sliceAsBytes(context.static_collider_y[0..]))) return 0;
    if (!writeBytes(bytes, &offset, std.mem.sliceAsBytes(context.static_collider_half_width[0..]))) return 0;
    if (!writeBytes(bytes, &offset, std.mem.sliceAsBytes(context.static_collider_half_height[0..]))) return 0;
    if (!writeBytes(bytes, &offset, std.mem.sliceAsBytes(context.tilemap_tiles))) return 0;
    if (!writeBytes(bytes, &offset, std.mem.sliceAsBytes(context.particle_alive[0..]))) return 0;
    if (!writeBytes(bytes, &offset, std.mem.sliceAsBytes(context.particle_x[0..]))) return 0;
    if (!writeBytes(bytes, &offset, std.mem.sliceAsBytes(context.particle_y[0..]))) return 0;
    if (!writeBytes(bytes, &offset, std.mem.sliceAsBytes(context.particle_velocity_x[0..]))) return 0;
    if (!writeBytes(bytes, &offset, std.mem.sliceAsBytes(context.particle_velocity_y[0..]))) return 0;
    if (!writeBytes(bytes, &offset, std.mem.sliceAsBytes(context.particle_lifetime[0..]))) return 0;
    if (!writeBytes(bytes, &offset, std.mem.sliceAsBytes(context.particle_max_lifetime[0..]))) return 0;
    if (!writeBytes(bytes, &offset, std.mem.sliceAsBytes(context.particle_size[0..]))) return 0;
    if (!writeBytes(bytes, &offset, std.mem.sliceAsBytes(context.particle_red[0..]))) return 0;
    if (!writeBytes(bytes, &offset, std.mem.sliceAsBytes(context.particle_green[0..]))) return 0;
    if (!writeBytes(bytes, &offset, std.mem.sliceAsBytes(context.particle_blue[0..]))) return 0;
    if (!writeBytes(bytes, &offset, std.mem.sliceAsBytes(context.particle_alpha[0..]))) return 0;
    if (!writeBytes(bytes, &offset, std.mem.sliceAsBytes(context.light_alive[0..]))) return 0;
    if (!writeBytes(bytes, &offset, std.mem.sliceAsBytes(context.light_x[0..]))) return 0;
    if (!writeBytes(bytes, &offset, std.mem.sliceAsBytes(context.light_y[0..]))) return 0;
    if (!writeBytes(bytes, &offset, std.mem.sliceAsBytes(context.light_radius[0..]))) return 0;
    if (!writeBytes(bytes, &offset, std.mem.sliceAsBytes(context.light_red[0..]))) return 0;
    if (!writeBytes(bytes, &offset, std.mem.sliceAsBytes(context.light_green[0..]))) return 0;
    if (!writeBytes(bytes, &offset, std.mem.sliceAsBytes(context.light_blue[0..]))) return 0;
    if (!writeBytes(bytes, &offset, std.mem.sliceAsBytes(context.light_intensity[0..]))) return 0;
    return offset;
}

pub fn snapshotRead(context: *EngineContext, input: [*]const u8, input_size: usize) bool {
    if (input_size < @sizeOf(SnapshotHeader)) return false;
    const bytes = input[0..input_size];
    var offset: usize = 0;
    var header: SnapshotHeader = undefined;
    if (!readBytes(bytes, &offset, std.mem.asBytes(&header))) return false;
    if (header.magic != types.SNAPSHOT_MAGIC or header.version != types.SNAPSHOT_VERSION or
        header.capacity != context.capacity or header.grid_width != context.grid_width or
        header.grid_height != context.grid_height or input_size < snapshotPayloadSize(context)) return false;

    context.alive_count = @intCast(header.alive_count);
    context.cell_size = header.cell_size;
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
    context.dropped_events = header.dropped_events;
    context.tilemap_width = @intCast(header.tilemap_width);
    context.tilemap_height = @intCast(header.tilemap_height);
    context.tilemap_tile_width = header.tilemap_tile_width;
    context.tilemap_tile_height = header.tilemap_tile_height;
    context.particle_count = @intCast(header.particle_count);
    context.light_count = @intCast(header.light_count);

    const allocator = std.heap.page_allocator;
    const alive = allocator.alloc(bool, context.capacity) catch return false;
    defer allocator.free(alive);

    if (!readBytes(bytes, &offset, std.mem.sliceAsBytes(context.ids))) return false;
    if (!readBytes(bytes, &offset, std.mem.sliceAsBytes(context.sprite_ids))) return false;
    if (!readBytes(bytes, &offset, std.mem.sliceAsBytes(context.positions_x))) return false;
    if (!readBytes(bytes, &offset, std.mem.sliceAsBytes(context.positions_y))) return false;
    if (!readBytes(bytes, &offset, std.mem.sliceAsBytes(context.velocities_x))) return false;
    if (!readBytes(bytes, &offset, std.mem.sliceAsBytes(context.velocities_y))) return false;
    if (!readBytes(bytes, &offset, std.mem.sliceAsBytes(context.anchor_counts))) return false;
    if (!readBytes(bytes, &offset, std.mem.sliceAsBytes(alive))) return false;
    context.registry.deinit();
    context.registry = ecs.Registry.init(allocator);
    @memset(context.entities, null);
    for (alive, 0..) |is_alive, index| {
        if (is_alive) context.entities[index] = context.registry.create();
    }
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
    if (!readBytes(bytes, &offset, std.mem.sliceAsBytes(context.shape_half_width))) return false;
    if (!readBytes(bytes, &offset, std.mem.sliceAsBytes(context.shape_half_height))) return false;
    if (!readBytes(bytes, &offset, std.mem.sliceAsBytes(context.shape_rotation))) return false;
    if (!readBytes(bytes, &offset, std.mem.sliceAsBytes(context.polygon_counts))) return false;
    if (!readBytes(bytes, &offset, std.mem.sliceAsBytes(context.polygon_vertices))) return false;
    if (!readBytes(bytes, &offset, std.mem.sliceAsBytes(context.grounded))) return false;
    if (!readBytes(bytes, &offset, std.mem.sliceAsBytes(context.collision_enabled))) return false;
    if (!readBytes(bytes, &offset, std.mem.sliceAsBytes(context.static_collider_alive[0..]))) return false;
    if (!readBytes(bytes, &offset, std.mem.sliceAsBytes(context.static_collider_x[0..]))) return false;
    if (!readBytes(bytes, &offset, std.mem.sliceAsBytes(context.static_collider_y[0..]))) return false;
    if (!readBytes(bytes, &offset, std.mem.sliceAsBytes(context.static_collider_half_width[0..]))) return false;
    if (!readBytes(bytes, &offset, std.mem.sliceAsBytes(context.static_collider_half_height[0..]))) return false;
    if (!readBytes(bytes, &offset, std.mem.sliceAsBytes(context.tilemap_tiles))) return false;
    if (!readBytes(bytes, &offset, std.mem.sliceAsBytes(context.particle_alive[0..]))) return false;
    if (!readBytes(bytes, &offset, std.mem.sliceAsBytes(context.particle_x[0..]))) return false;
    if (!readBytes(bytes, &offset, std.mem.sliceAsBytes(context.particle_y[0..]))) return false;
    if (!readBytes(bytes, &offset, std.mem.sliceAsBytes(context.particle_velocity_x[0..]))) return false;
    if (!readBytes(bytes, &offset, std.mem.sliceAsBytes(context.particle_velocity_y[0..]))) return false;
    if (!readBytes(bytes, &offset, std.mem.sliceAsBytes(context.particle_lifetime[0..]))) return false;
    if (!readBytes(bytes, &offset, std.mem.sliceAsBytes(context.particle_max_lifetime[0..]))) return false;
    if (!readBytes(bytes, &offset, std.mem.sliceAsBytes(context.particle_size[0..]))) return false;
    if (!readBytes(bytes, &offset, std.mem.sliceAsBytes(context.particle_red[0..]))) return false;
    if (!readBytes(bytes, &offset, std.mem.sliceAsBytes(context.particle_green[0..]))) return false;
    if (!readBytes(bytes, &offset, std.mem.sliceAsBytes(context.particle_blue[0..]))) return false;
    if (!readBytes(bytes, &offset, std.mem.sliceAsBytes(context.particle_alpha[0..]))) return false;
    if (!readBytes(bytes, &offset, std.mem.sliceAsBytes(context.light_alive[0..]))) return false;
    if (!readBytes(bytes, &offset, std.mem.sliceAsBytes(context.light_x[0..]))) return false;
    if (!readBytes(bytes, &offset, std.mem.sliceAsBytes(context.light_y[0..]))) return false;
    if (!readBytes(bytes, &offset, std.mem.sliceAsBytes(context.light_radius[0..]))) return false;
    if (!readBytes(bytes, &offset, std.mem.sliceAsBytes(context.light_red[0..]))) return false;
    if (!readBytes(bytes, &offset, std.mem.sliceAsBytes(context.light_green[0..]))) return false;
    if (!readBytes(bytes, &offset, std.mem.sliceAsBytes(context.light_blue[0..]))) return false;
    if (!readBytes(bytes, &offset, std.mem.sliceAsBytes(context.light_intensity[0..]))) return false;
    return true;
}
