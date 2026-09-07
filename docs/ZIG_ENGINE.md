# Zig Engine Reference

This document describes the native engine implemented in `src_zig/`. It covers
the Zig runtime and its exported C ABI. Lua gameplay, rendering adapters, and
the LÖVE application layer are intentionally out of scope.

## Purpose and Architecture

The engine is a native dynamic library named `game_systems`. `src_zig/main.zig`
owns the exported ABI and the `EngineContext`; the other modules provide the
implementation behind that ABI:

| Module | Responsibility |
| --- | --- |
| `main.zig` | C ABI, allocation, context lifecycle, pools, queries, tests |
| `engine_types.zig` | Public structs, constants, storage layout, platform timers |
| `engine_math.zig` | Geometry tests, ray intersections, contacts, camera matrix |
| `engine_physics.zig` | 2D physics, impulses, static colliders, 2.5D ground collisions |
| `engine_runtime.zig` | Events, audio commands, spatial grid, animation, particles, frame tick |
| `engine_snapshot.zig` | Full state serialization and XOR delta snapshots |

The engine uses a registry from `zig-ecs` for entity identity and lifecycle,
while component data remains in parallel native arrays. An entity handle is
kept internally in the registry; the public ABI uses a stable slot index and
the user-provided `u64` entity ID.

## Build Artifacts and Targets

`build.zig` builds the following:

- `game_systems`: the native dynamic library for the requested target.
- `zig build test`: the native unit-test binary, using the same root module.
- `zig build cross-windows`, `cross-linux`, and `cross-macos`: ABI/build checks.

The default build uses Debug optimization. `-Dproduction=true` selects
`ReleaseSafe`; safety checks remain enabled. The allocator is a Zig
`DebugAllocator`, and `engine_allocator_deinit` reports whether allocations
were fully released.

## Context Lifecycle

Create a context with:

```text
engine_create(capacity, grid_width, grid_height, cell_size) -> EngineContext*
```

All four dimensions must be valid and `cell_size` must be positive. Creation
allocates the entity arrays, spatial grid, pathfinding buffers, frame arena,
tilemap storage, and ECS registry. The initial defaults are:

- Gravity: `98.0`.
- Camera: identity transform, scale `1`, viewport `800 x 600`.
- New entities: dynamic circle bodies, radius `4`, collision disabled.
- Event and audio queues: `256` entries each.
- Frame arena: `64 KiB`.

Destroy with `engine_destroy`. This deinitializes the ECS registry and frees
all context-owned allocations. Call `engine_allocator_deinit` during shutdown
to detect allocator leaks.

The lifecycle and diagnostics exports are:

```text
engine_create, engine_destroy, engine_allocator_deinit
engine_entity_capacity, engine_reserve_entities, engine_alive_count
engine_entity_alive, engine_telemetry, engine_set_gravity, engine_get_gravity
```

Entity storage grows automatically when `engine_spawn` has no free slot. The
capacity doubles, or grows by one when doubling would not increase it. Explicit
growth is available through `engine_reserve_entities`. A failed allocation
returns `INVALID_INDEX` (`0xffffffff`) or `false` as appropriate.

## Entity and Component State

`engine_spawn` creates a registry entity and initializes its slot with an ID,
position, velocity, and sprite ID. `engine_find_entity` searches by the user
ID. `engine_destroy_entity` refuses to destroy an invalid entity or one with
active anchors. Anchors are reference counts intended to prevent destruction
while another system holds a logical reference:

```text
engine_spawn, engine_destroy_entity, engine_find_entity
engine_anchor_entity, engine_release_entity, engine_entity_anchor_count
```

The position model has two related forms:

- 2D: `x` and visual `y` position/velocity.
- 2.5D: `x` and ground-plane `z` for movement/depth, plus independent vertical
  `y` position/velocity affected by gravity.

The following functions expose direct array views. The arrays are slot-indexed
and must be treated as invalid for dead entity slots:

```text
engine_set_position, engine_set_velocity
engine_set_25d_position, engine_set_25d_velocity
engine_positions_x, engine_positions_y, engine_positions_z
engine_velocities_x, engine_velocities_y, engine_velocities_z
engine_shadow_positions_x, engine_shadow_positions_y
engine_depth_order, engine_sprite_ids
```

For ground-enabled entities, the shadow is `(x, z)` and `depth_order` is
`round(z * 1000)`. This gives render code a projected ground position while
keeping vertical `y` separate.

## Physics and Collision

### Bodies and shapes

Body types are:

| Constant | Value | Meaning |
| --- | ---: | --- |
| `BODY_STATIC` | 0 | Never integrated or moved by resolution |
| `BODY_KINEMATIC` | 1 | Integrated from its velocity, not impulse-driven |
| `BODY_DYNAMIC` | 2 | Integrated, receives gravity and collision impulses |

Supported shapes are circles, capsules, AABBs, oriented boxes, and convex
polygons. Polygons accept three to eight local-space vertices and a rotation.
Use:

```text
engine_set_body       # circle or capsule
engine_set_aabb       # axis-aligned box
engine_set_obb        # rotated box
engine_set_polygon    # convex polygon, up to 8 vertices
```

The circle/capsule, AABB, and polygon setters enable 2D collision for the
entity. The OBB setter stores the rotated shape but leaves the existing
collision-enabled flag unchanged, so callers should enable collision through
their entity setup path before relying on an OBB. `engine_set_ground_aabb`
independently enables an axis-aligned footprint on the `x/z` ground plane.
`engine_add_static_aabb` adds up to `256` native static colliders, and
`engine_clear_static_colliders` removes them all.

### Simulation behavior

`engine_update(context, dt)` delegates physics to `engine_physics.step`.
Dynamic bodies receive `gravity * dt` on vertical velocity and all movable
bodies integrate position. Fast dynamic bodies use adaptive continuous
substeps, capped at `32`, based on displacement versus shape extent.

Collision solving performs four iterations for each substep. It handles:

- Dynamic-vs-static and dynamic-vs-dynamic shape contacts.
- Positional correction with a small penetration slop.
- Normal impulses with restitution.
- Tangential friction impulses.
- Static AABB contacts and grounded reporting.
- Ground-plane AABB overlap and velocity cancellation on the least-overlap
  axis.

The math layer uses circle intersection, capsule approximations, the
Separating Axis Test for polygon contacts, and rotated polygon vertices for
OBBs and custom polygons. Queries are available through:

```text
engine_is_grounded, engine_test_collision, engine_raycast
```

`engine_raycast` traverses the spatial grid with a 2D grid-stepping algorithm,
tests shapes in visited cells, and returns the nearest hit as `RaycastHit`:
entity slot, entity ID, hit position, and distance.

## Spatial Grid and Rendering State

The context owns a linked-list spatial hash/grid. Each entity is inserted into
the cell containing its position; entities outside the grid are skipped.

```text
engine_rebuild_spatial
engine_query_cell(cell_x, cell_y, output, output_capacity)
```

Cell queries return at most `output_capacity` entries. The returned count is
also capped to that capacity.

Render state is stored natively so the consumer can iterate ordered slot
indices without allocating entity objects:

```text
engine_set_render_z, engine_sort_render_order
engine_render_order, engine_render_count
```

Ground-enabled entities sort by computed depth; other entities sort by their
explicit render-Z value. Sorting is an insertion sort over the live slots.

Camera state contains position, scale, rotation, parallax, and viewport size.
`engine_camera_set` clamps non-positive scale to `1` and updates a 3x3 affine
matrix returned by `engine_camera_matrix`.

## Animation

Animation state is per entity. `engine_animation_set` defines a contiguous
range of sprite IDs, frame duration, and looping behavior:

```text
engine_animation_set
engine_current_sprite_frame_id
```

During the update, elapsed time advances through as many frames as needed. A
non-looping animation stays on its final frame; looping animations wrap to the
first frame. The active frame is also written to the entity's `sprite_ids`
array.

## Combat Volumes

Combat volumes are transient fixed-capacity data and should be cleared and
registered for each simulation frame:

```text
engine_combat_clear
engine_combat_register_hitbox
engine_combat_register_hurtbox
engine_combat_resolve
engine_next_combat_hit
```

There can be at most `512` hitboxes and `512` hurtboxes. Volumes are centered
3D AABBs using `x`, visual `y`, and ground `z`. A hitbox never hits its own
owner. Overlap produces a `CombatHitEvent` containing attacker, victim, damage,
three-axis knockback, and hit-stop duration. The combat event queue holds up to
`256` results; excess results are skipped.

## Tilemaps, Particles, and Lights

These are native fixed-capacity render pools:

### Tilemaps

`engine_tilemap_create` configures one orthogonal tilemap and clears its tile
IDs. The maximum storage is `262144` tiles. Use:

```text
engine_tilemap_create, engine_tilemap_set_tile
engine_tilemap_width, engine_tilemap_height
engine_tilemap_tile_width, engine_tilemap_tile_height
engine_tilemap_tiles
```

### Particles

The pool contains `4096` particles. Spawned particles store position,
velocity, lifetime, size, RGB color, and alpha. Each update integrates position,
reduces lifetime, removes expired particles, and sets alpha to the remaining
lifetime ratio.

```text
engine_particle_spawn, engine_particle_kill, engine_particle_count
engine_particle_positions_x, engine_particle_positions_y
engine_particle_sizes, engine_particle_red, engine_particle_green
engine_particle_blue, engine_particle_alpha, engine_particle_alive
```

### Lights

The pool contains `128` point lights. Each light stores position, radius, RGB
color, and intensity:

```text
engine_light_create, engine_light_destroy, engine_light_count
engine_light_positions_x, engine_light_positions_y, engine_light_radii
engine_light_red, engine_light_green, engine_light_blue
engine_light_intensity, engine_light_alive
```

Invalid parameters or a full pool return `INVALID_INDEX` or `false`.

## Events, Input, and Spatial Audio

`InputState` contains a 32-bit button mask and mouse coordinates. Input is
copied into the context with `engine_set_input`. On each update, the engine
computes newly pressed buttons as `buttons & ~previous_buttons`:

- Bit `1` emits `EVENT_PLAY_SOUND` and a sample spatial sound command.
- Bit `2` emits `EVENT_PLAYER_DIED`.

Custom events use a bounded FIFO of `EngineEvent { id, value }`:

```text
engine_set_input
engine_emit_event, engine_next_event, engine_clear_events
engine_pending_event_count, engine_dropped_event_count
```

Event overflow increments `dropped_events` instead of overwriting queued data.
Pathfinding also emits `EVENT_PATH_READY` when it reaches its goal.

Audio commands use a separate bounded FIFO of `AudioCommand`. Volume is
linearly attenuated to zero at `max_distance`, and pan is clamped to `[-1, 1]`
from the source's horizontal offset relative to the listener:

```text
engine_set_audio_listener
engine_emit_spatial_sound, engine_next_audio_command
engine_clear_audio_commands, engine_audio_dropped_count
```

## Pathfinding

Pathfinding is incremental breadth-first search over the same grid dimensions
as the spatial grid. It uses four-neighbor movement and does not inspect
colliders or tile IDs; callers decide which cells are traversable externally.

```text
engine_pathfind_begin(start_x, start_y, goal_x, goal_y)
engine_pathfind_step(node_budget)
engine_pathfind_state
engine_pathfind_length
```

States are `PATH_IDLE`, `PATH_WORKING`, `PATH_FOUND`, and `PATH_FAILED`.
`engine_pathfind_step` processes at most `node_budget` nodes, so callers can
spread a search over multiple frames. `engine_pathfind_length` returns the
number of grid nodes in a found path, or zero otherwise. The implementation
stores parent links but does not export the path's individual coordinates.

## Frame Arena and Telemetry

The frame arena is a 64 KiB bump allocator for temporary native data:

```text
engine_frame_begin
engine_frame_alloc
engine_frame_arena_used
engine_frame_arena_capacity
```

`engine_frame_begin` resets the offset; allocations are not individually freed
and return `null` when the remaining capacity is insufficient.

`Telemetry` reports microsecond timings for physics, spatial sorting, FFI
serialization, and the whole frame, plus current entity capacity and dropped
events. `engine_telemetry` refreshes capacity and dropped-event values before
returning the pointer.

## Snapshots and Rollback

Full snapshots serialize the versioned native state into a caller-provided
buffer. Query the required size first:

```text
engine_snapshot_size
engine_snapshot_write
engine_snapshot_read
```

The snapshot includes entity IDs and membership, transforms, velocities,
render and animation state, physics shapes, grounded/collision flags, static
colliders, event state, pathfinding state, camera state, tilemap data,
particles, and lights. It does not serialize raw ECS handles. On restore, the
registry is deinitialized and recreated, then one new registry entity is
created for every live serialized slot.

Snapshots carry magic `0x5A47454E` and version `4`. Reads reject mismatched
magic/version, capacity, or grid dimensions, and reject undersized buffers.

Delta snapshots compare a current full snapshot with a base byte buffer and
encode runs as either unchanged bytes or XOR bytes. The delta format has its
own magic (`SNAPSHOT_MAGIC ^ 0xffffffff`) and the same version. Use:

```text
engine_snapshot_delta_size
engine_snapshot_write_delta
engine_snapshot_apply_delta
```

Delta application reconstructs a full payload in memory and passes it through
the normal snapshot restore path.

## Update Order

`engine_update(context, dt)` performs the following operations in order:

1. Reset the frame arena.
2. Recalculate the camera matrix.
3. Convert input edges into built-in sound/death events.
4. Advance physics and collision resolution.
5. Advance animations.
6. Advance and expire particles.
7. Compute depth/shadow values and sort render order.
8. Rebuild the spatial grid.
9. Record total frame time in telemetry.

Combat registration/resolution, snapshot operations, pathfinding steps, and
native pool creation remain explicit API calls and are not implicit parts of
the update loop.

## ABI and Error Conventions

The exported functions use C-compatible integer and floating-point types plus
the exported structs (`InputState`, `EngineEvent`, `AudioCommand`,
`Telemetry`, `RaycastHit`, `CombatHitEvent`, and `CameraState`). Pointer-returning
array accessors expose internal storage directly; callers must respect the
current capacity and avoid retaining pointers across a capacity-growing spawn
or reserve operation.

Common failure conventions are:

- `false`: invalid entity/index/arguments, unavailable pool slot, or full queue.
- `0`: no result for count/ID-style queries, or an invalid animation frame ID.
- `INVALID_INDEX` (`u32` maximum): failed entity, particle, light, collider, or
  path index allocation.
- `null`: failed context creation or frame-arena allocation.
- Snapshot read/apply: `false` for malformed, incompatible, or truncated data.

## Native Tests

The tests at the end of `src_zig/main.zig` cover dynamic impulses, fast-body
static collision and grounded state, depth-aware combat, 2.5D collision and
render state, polygon collision/raycasting, transient pools, entity growth and
events, spatial audio, and full/delta snapshot restoration.

Run them with:

```powershell
zig build test
```

The small `add_numbers(a, b)` export is also retained as a native/FFI sanity
check; it returns the sum of two C `int` values.
