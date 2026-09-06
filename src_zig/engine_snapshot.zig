const std = @import("std");
const types = @import("engine_types.zig");
const EngineContext = types.EngineContext;
const SnapshotHeader = types.SnapshotHeader;

pub fn snapshotPayloadSize(context: *const EngineContext) usize {
    return @sizeOf(SnapshotHeader) +
        @sizeOf(u64) * context.capacity * 2 +
        @sizeOf(f32) * context.capacity * 4 +
        @sizeOf(bool) * context.capacity +
        @sizeOf(u32) * context.capacity * 2 +
        @sizeOf(types.EngineEvent) * types.EVENT_QUEUE_CAPACITY +
        @sizeOf(bool) * context.grid_width * context.grid_height +
        @sizeOf(u32) * context.grid_width * context.grid_height * 2 +
        @sizeOf(types.CameraState) + @sizeOf(f32) * 9 +
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

pub fn snapshotWrite(context: *EngineContext, output: [*]u8, output_capacity: usize) usize {
    const required = snapshotPayloadSize(context);
    if (output_capacity < required) return 0;
    const bytes = output[0..output_capacity];
    var offset: usize = 0;
    const header = SnapshotHeader{
        .magic = types.SNAPSHOT_MAGIC,
        .version = types.SNAPSHOT_VERSION,
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
    return true;
}
