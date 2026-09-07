# Zig Love2D Engine Sandbox

A small LÖVE + Zig project that exposes a native game engine through LuaJIT FFI. The runtime uses Zig for engine state, simulation, collision, spatial queries, animation, and telemetry while LÖVE handles rendering, windowing, and input.

This project intentionally does not include ImGui or an editor overlay. The game is driven by a lightweight debug UI module instead of a developer editor.

## Requirements

- Zig 0.16.0 or compatible
- LÖVE 11.5 or compatible
- A Windows/Linux/macOS build environment matching the target you want to compile for

The engine uses [zig-ecs](https://github.com/prime31/zig-ecs), a Zig ECS library
inspired by EnTT, for entity lifecycle and registry management.

## Build

From the project root:

```powershell
zig build
```

Dependencies are pinned in `build.zig.zon`. On a clean checkout, fetch them with:

```powershell
zig build --fetch
```

Run the native engine tests with:

```powershell
zig build test
```

## Native Debugging

Install the CodeLLDB VS Code extension and set the `LOVE_EXE` environment variable to your LÖVE executable, for example:

```powershell
$env:LOVE_EXE = "C:\Program Files\LOVE\love.exe"
```

Start the `Debug Game` configuration. It builds the native library with `Debug` symbols, launches LÖVE with this workspace, and lets CodeLLDB stop in Zig code, including `__zig_panic`.

The native target is a dynamic library loaded by LÖVE, so it cannot be launched directly as `my_game`. To debug a standalone Zig executable or test binary with the matching compiler toolchain, use:

```powershell
zig lldb .\zig-out\bin\my_game.exe
zig gdb .\zig-out\bin\my_game.exe
```

Replace `my_game.exe` with the executable produced by the command you are debugging. Build performance variants with `-Dproduction=true` for `ReleaseSafe`; keep `Debug` for normal native debugging.

The native library is output to:

```text
zig-out/bin/game_systems.dll
```

## Run

Start the game from the project root:

```powershell
love .
```

With console output enabled:

```powershell
love --console .
```

At startup the project prints a basic Zig sanity check:

```text
Sum from Zig: 42
```

## Current Features

- Native engine context created in Zig and exposed to Lua through FFI
- ECS-managed entities with spawn, destroy, validity, and reuse logic
- Automatically growing entity storage with graceful spawn fallback and capacity telemetry
- Position, velocity, render order, and sprite state management
- Reusable LÖVE SpriteBatch path for ordered entity rendering
- Physics state: static, kinematic, and dynamic bodies
- Optional 2.5D ground-plane bodies with `x/z` AABB collision and independent vertical `y` gravity
- Lua-visible ground-shadow coordinates and automatic `z` depth ordering
- Frame-accurate 2.5D hitbox and hurtbox combat
- Structured combat hit events with damage, knockback, and hit-stop durations
- Lua player FSM with three-hit light combos, Jump Attack, Hitstun, and Knockdown
- Close-range grab locks with knee strikes and directional enemy throws
- Recovery-window combo buffering with duplicate-hit prevention per attack
- Dynamic-vs-dynamic collision response with impulses, restitution, and friction
- Circle, capsule, AABB, OBB, and convex polygon collision primitives
- Adaptive substep continuous collision detection for fast-moving bodies
- Native static AABB colliders and grounded contact reporting
- Collision tests and raycast queries over a spatial grid
- Pathfinding requests with incremental stepping
- Full snapshot serialization and ECS restore support, plus XOR delta snapshots for rollback
- Bidirectional event commands with Lua handler registration and overflow accounting
- Native spatial audio commands with distance attenuation and stereo panning
- Rebindable keyboard, mouse, gamepad, and analog input actions
- Camera transform management
- Animation state and frame selection in native code
- Centralized asset manager with cached Lua, text, JSON, image, and sound loading
- VFS-style normalized asset paths with modification-time cache invalidation
- F5 hot reload support for gameplay and level data assets
- Debug runtime panel in LÖVE for pause, gravity, spawn controls, and engine timing

## Project Layout

```text
build.zig                Zig build configuration
build.zig.zon            Pinned Zig package dependencies
src_zig/
  engine_math.zig        Math helpers and utility routines
  engine_runtime.zig     Runtime simulation and update logic
  engine_snapshot.zig    Snapshot encode/decode logic
  engine_types.zig      Native structs and constants
  main.zig              Exported engine API
main.lua                 LÖVE entry point and FFI bridge setup
game_logic.lua           Reloadable gameplay logic
modules/
  assets.lua            Cached asset/VFS facade
  events.lua             Bidirectional native event facade
  audio.lua              Spatial audio command consumer
  input.lua              Rebindable action mapping
  json.lua              Dependency-free JSON decoder
  ui.lua                 Debug panel / runtime controls
game/
  platformer/
    levels.lua           Asset-backed platformer level data
    platformer.lua       Platformer gameplay logic
  streets_of_rage/
    combat.lua           Declarative hitbox/hurtbox combat registry
    camera_manager.lua   Forward-only camera and arena trigger manager
    enemy_ai.lua         Enemy approach, flank, attack, and projectile states
    grab_system.lua      Close-range player/enemy grab coordinator
    player_fsm.lua       Player combat state machine and combo buffering
ffi_bindings.lua         LuaJIT FFI declarations
tools/
  generate_bindings.ps1  Regenerate the FFI bindings
  package.ps1            Package the game for distribution
zig-out/bin/             Built native libraries and output artifacts
```

## ECS Architecture

Gameplay architecture is separated by game mode. The existing platformer lives
in `game/platformer/`, while the Streets of Rage-style systems live under
`game/streets_of_rage/`. Shared engine adapters remain in `modules/`.

Entity creation, validity, and destruction are owned by the pinned
[`prime31/zig-ecs`](https://github.com/prime31/zig-ecs) registry. The existing
SoA component arrays remain the native physics and LuaJIT FFI projection, so the
public API does not need a second entity representation or a C++ bridge.

The ECS registry owns entity handles and lifecycle state. Physics data such as
positions, velocities, shapes, and collision state remains in native arrays for
cache-friendly simulation and direct Lua access.

## Asset Pipeline

`modules/assets.lua` is the single entry point for runtime assets. It normalizes
paths and caches loaded values by asset type and path. It supports:

- `load_lua(path)` for level and configuration data
- `load_text(path)` and `load_json(path)` for data files
- `load_image(path)` for textures
- `load_sound(path, source_type)` for audio sources
- `reload(path)`, `reload_all()`, and `clear()` for development and shutdown

Platformer levels are loaded from `game/platformer/levels.lua` through this manager rather
than being embedded in the gameplay module. Press `F5` to invalidate changed
assets and reload gameplay and level data.

## Core Engine API

The engine exports the following native API through LuaJIT FFI.

### Lifecycle and diagnostics

- `engine_create(...)`
- `engine_destroy(...)`
- `engine_entity_capacity(...)`
- `engine_reserve_entities(...)`
- `engine_alive_count(...)`
- `engine_telemetry(...)`
- `engine_update(...)`

### Entity state

- `engine_spawn(...)`
- `engine_destroy_entity(...)`
- `engine_find_entity(...)`
- `engine_anchor_entity(...)`
- `engine_release_entity(...)`
- `engine_entity_anchor_count(...)`
- `engine_set_position(...)`
- `engine_set_velocity(...)`
- `engine_set_25d_position(...)` with `x`, ground-plane `z`, and vertical `y`
- `engine_set_25d_velocity(...)`
- `engine_positions_x(...)`
- `engine_positions_y(...)`
- `engine_positions_z(...)`
- `engine_velocities_x(...)`
- `engine_velocities_y(...)`
- `engine_velocities_z(...)`
- `engine_shadow_positions_x(...)`
- `engine_shadow_positions_y(...)`
- `engine_depth_order(...)`
- `engine_sprite_ids(...)`
- `engine_set_gravity(...)`
- `engine_get_gravity(...)`

### Physics and collision

- `engine_set_body(...)` for circles and capsules
- `engine_set_aabb(...)`
- `engine_set_obb(...)`
- `engine_set_polygon(...)` for convex polygons
- `engine_add_static_aabb(...)`
- `engine_clear_static_colliders(...)`
- `engine_is_grounded(...)`
- `engine_test_collision(...)`
- `engine_raycast(...)`
- `engine_set_ground_aabb(...)`

### Combat

Combat volumes are transient and should be registered every frame. Hitboxes and
hurtboxes use offset AABBs with `x`, visual `y`, and ground-plane `z` coordinates.
The native resolver emits structured events when volumes overlap.

- `engine_combat_clear(...)`
- `engine_combat_register_hitbox(...)`
- `engine_combat_register_hurtbox(...)`
- `engine_combat_resolve(...)`
- `engine_next_combat_hit(...)`

`modules/combat.lua` stores attack data as nested Lua tables. Each attack can
define multiple active frame windows, offset boxes, damage, knockback, and
hit-stop values. `modules/player_fsm.lua` consumes this registry and exposes the
player controller through `runtime.new_player_fsm(owner, callbacks)`.

Example:

```lua
local player = runtime.new_player_fsm(player_entity, {
  on_state_changed = function(state)
    print("Player state:", state)
  end,
  on_hit = function(hit)
    print("Damage:", hit.damage, "Victim:", hit.victim)
  end,
})
```

The FSM buffers the light attack button only during each attack's recovery
window. A valid input advances `Attack1` to `Attack2` and then `Attack3`; a
missed window returns the player to `Idle`. Incoming hits transition to
`Hitstun` or `Knockdown`, with temporary invulnerability during knockdown
recovery. `Jump Attack` is available from `Idle` through the jump action.

### Spatial and rendering state

- `engine_rebuild_spatial(...)`
- `engine_query_cell(...)`
- `engine_set_render_z(...)`
- `engine_sort_render_order(...)`
- `engine_render_order(...)`
- `engine_render_count(...)`
- `engine_camera_set(...)`
- `engine_camera_matrix(...)`

### Animation

- `engine_animation_set(...)`
- `engine_current_sprite_frame_id(...)`

### Tilemaps, particles, and lights

The native runtime provides fixed-capacity render data pools. `modules/tilemap.lua`
loads orthogonal Tiled JSON maps, uploads tile IDs through the tilemap API, and
renders an optional tileset image. `modules/particles.lua` and
`modules/lighting.lua` render native particle and point-light pools without
allocating per-frame entity objects in Lua.

- `engine_tilemap_create(...)`, `engine_tilemap_set_tile(...)`, `engine_tilemap_tiles(...)`
- `engine_particle_spawn(...)`, `engine_particle_count(...)`, `engine_particle_*`
- `engine_light_create(...)`, `engine_light_destroy(...)`, `engine_light_count(...)`, `engine_light_*`

### Input and events

- `engine_set_input(...)`
- `engine_set_audio_listener(...)`
- `engine_emit_spatial_sound(...)`
- `engine_next_audio_command(...)`
- `engine_clear_audio_commands(...)`
- `engine_audio_dropped_count(...)`
- `engine_next_event(...)`
- `engine_emit_event(...)`
- `engine_clear_events(...)`
- `engine_dropped_event_count(...)`

`modules/events.lua` provides `on`, `emit`, `poll`, and `clear` methods. Event
overflow is counted in telemetry instead of being silently discarded.

`modules/input.lua` maps named actions to multiple keyboard keys, mouse buttons,
gamepad buttons, and analog axes. The resulting action mask remains compatible
with the native `InputState` ABI.

- `engine_pending_event_count(...)`

### Frame memory

- `engine_frame_begin(...)`
- `engine_frame_alloc(...)`
- `engine_frame_arena_used(...)`
- `engine_frame_arena_capacity(...)`

### Snapshots

- `engine_snapshot_size(...)`
- `engine_snapshot_write(...)`
- `engine_snapshot_read(...)`
- `engine_snapshot_delta_size(...)`
- `engine_snapshot_write_delta(...)`
- `engine_snapshot_apply_delta(...)`

Snapshots include entity membership, simulation state, event state, tilemap
data, particles, and lights. Delta snapshots encode XOR changes against a full
base snapshot using zero-run compression.

### Pathfinding

- `engine_pathfind_begin(...)`
- `engine_pathfind_step(...)`
- `engine_pathfind_state(...)`
- `engine_pathfind_length(...)`

### Sanity check

- `add_numbers(...)`

## Debug Controls

Press `F2` to toggle the debug panel.

The debug panel allows:

- pause/resume the engine update loop
- adjust gravity with a slider
- spawn a number of new entities
- inspect the native timing values for physics, spatial sorting, FFI serialization, and draw work

## Cross-Compilation

The project includes ABI verification builds for multiple targets:

```powershell
zig build cross-windows
zig build cross-linux
zig build cross-macos
```

Use:

```powershell
zig build -Dcross-release=false
```

for faster verification builds during development.

## Production Build

```powershell
zig build -Dproduction=true
```

Development builds use `Debug` safety checks by default. Production and cross-target builds use `ReleaseSafe`, preserving runtime safety checks while enabling optimization. The native engine uses Zig's `GeneralPurposeAllocator`; `love.quit()` deinitializes it and reports leaked allocations.

## Bindings Regeneration

If the exported Zig API changes, regenerate the LuaJIT FFI declarations:

```powershell
.\tools\generate_bindings.ps1
```

## Notes

- The engine state is intentionally native and is managed through Zig.
- LÖVE remains the rendering and windowing layer.
- ImGui/editor tooling has been removed from this project and is not part of the current runtime.
