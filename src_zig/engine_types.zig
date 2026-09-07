const std = @import("std");
const builtin = @import("builtin");
const ecs = @import("ecs");

pub const INVALID_INDEX: u32 = std.math.maxInt(u32);
pub const EVENT_QUEUE_CAPACITY: usize = 256;
pub const FRAME_ARENA_CAPACITY: usize = 64 * 1024;
pub const MAX_POLYGON_VERTICES: usize = 8;
pub const MAX_STATIC_COLLIDERS: usize = 256;
pub const MAX_TILEMAP_TILES: usize = 262144;
pub const MAX_PARTICLES: usize = 4096;
pub const MAX_LIGHTS: usize = 128;
pub const SNAPSHOT_MAGIC: u32 = 0x5A47454E;
pub const SNAPSHOT_VERSION: u32 = 4;

pub const InputState = extern struct {
    buttons: u32,
    mouse_x: f32,
    mouse_y: f32,
};

pub const EngineEvent = extern struct {
    id: u32,
    value: u32,
};

pub const AudioCommand = extern struct {
    sound_id: u64,
    source_x: f32,
    source_y: f32,
    volume: f32,
    pan: f32,
};

pub const Telemetry = extern struct {
    physics_us: u64,
    spatial_sort_us: u64,
    ffi_serialization_us: u64,
    frame_us: u64,
    entity_capacity: u64,
    dropped_events: u64,
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
pub const SHAPE_AABB: u8 = 3;
pub const SHAPE_OBB: u8 = 4;
pub const SHAPE_POLYGON: u8 = 5;

pub const EVENT_PLAY_SOUND: u32 = 1;
pub const EVENT_PLAYER_DIED: u32 = 2;
pub const EVENT_PATH_READY: u32 = 3;

pub const PATH_IDLE: u32 = 0;
pub const PATH_WORKING: u32 = 1;
pub const PATH_FOUND: u32 = 2;
pub const PATH_FAILED: u32 = 3;

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

pub const SnapshotHeader = extern struct {
    magic: u32,
    version: u32,
    capacity: u64,
    grid_width: u64,
    grid_height: u64,
    cell_size: f32,
    alive_count: u64,
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
    dropped_events: u64,
    tilemap_width: u64,
    tilemap_height: u64,
    tilemap_tile_width: f32,
    tilemap_tile_height: f32,
    particle_count: u64,
    light_count: u64,
};

pub const EngineContext = struct {
    registry: ecs.Registry,
    capacity: usize,
    alive_count: usize,
    grid_width: usize,
    grid_height: usize,
    cell_size: f32,
    ids: []u64,
    positions_x: []f32,
    positions_y: []f32,
    positions_z: []f32,
    velocities_x: []f32,
    velocities_y: []f32,
    velocities_z: []f32,
    shadow_x: []f32,
    shadow_y: []f32,
    depth_order: []i32,
    sprite_ids: []u64,
    entities: []?ecs.Entity,
    grid_heads: []u32,
    next_in_cell: []u32,
    input: InputState,
    previous_buttons: u32,
    events: [EVENT_QUEUE_CAPACITY]EngineEvent,
    event_read: usize,
    event_write: usize,
    event_count: usize,
    dropped_events: u64,
    audio_commands: [EVENT_QUEUE_CAPACITY]AudioCommand,
    audio_read: usize,
    audio_write: usize,
    audio_count: usize,
    audio_listener_x: f32,
    audio_listener_y: f32,
    audio_dropped: u64,
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
    shape_half_width: []f32,
    shape_half_height: []f32,
    shape_rotation: []f32,
    polygon_counts: []u8,
    polygon_vertices: []f32,
    grounded: []bool,
    collision_enabled: []bool,
    ground_collision_enabled: []bool,
    ground_half_width: []f32,
    ground_half_depth: []f32,
    static_collider_alive: [MAX_STATIC_COLLIDERS]bool,
    static_collider_x: [MAX_STATIC_COLLIDERS]f32,
    static_collider_y: [MAX_STATIC_COLLIDERS]f32,
    static_collider_half_width: [MAX_STATIC_COLLIDERS]f32,
    static_collider_half_height: [MAX_STATIC_COLLIDERS]f32,
    tilemap_width: usize,
    tilemap_height: usize,
    tilemap_tile_width: f32,
    tilemap_tile_height: f32,
    tilemap_tiles: []u32,
    particle_alive: [MAX_PARTICLES]bool,
    particle_x: [MAX_PARTICLES]f32,
    particle_y: [MAX_PARTICLES]f32,
    particle_velocity_x: [MAX_PARTICLES]f32,
    particle_velocity_y: [MAX_PARTICLES]f32,
    particle_lifetime: [MAX_PARTICLES]f32,
    particle_max_lifetime: [MAX_PARTICLES]f32,
    particle_size: [MAX_PARTICLES]f32,
    particle_red: [MAX_PARTICLES]f32,
    particle_green: [MAX_PARTICLES]f32,
    particle_blue: [MAX_PARTICLES]f32,
    particle_alpha: [MAX_PARTICLES]f32,
    particle_count: usize,
    light_alive: [MAX_LIGHTS]bool,
    light_x: [MAX_LIGHTS]f32,
    light_y: [MAX_LIGHTS]f32,
    light_radius: [MAX_LIGHTS]f32,
    light_red: [MAX_LIGHTS]f32,
    light_green: [MAX_LIGHTS]f32,
    light_blue: [MAX_LIGHTS]f32,
    light_intensity: [MAX_LIGHTS]f32,
    light_count: usize,
    gravity: f32,
    telemetry: Telemetry,
};

pub fn isAlive(context: *const EngineContext, index: usize) bool {
    if (index >= context.capacity) return false;
    const entity = context.entities[index] orelse return false;
    return @constCast(&context.registry).valid(entity);
}

pub const WindowsTimer = if (builtin.os.tag == .windows) struct {
    pub extern "kernel32" fn QueryPerformanceCounter(counter: *i64) callconv(.winapi) i32;
    pub extern "kernel32" fn QueryPerformanceFrequency(frequency: *i64) callconv(.winapi) i32;
} else struct {};

pub const PosixTimer = if (builtin.os.tag == .linux or builtin.os.tag == .macos) struct {
    pub const Timespec = extern struct { sec: i64, nsec: i64 };
    pub extern "c" fn clock_gettime(clock_id: i32, time: *Timespec) callconv(.c) i32;
} else struct {};

pub var timer_frequency: u64 = 0;
