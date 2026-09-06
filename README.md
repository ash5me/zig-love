# Zig Love2D Engine Sandbox

A small LÖVE + Zig project that exposes a native game engine through LuaJIT FFI. The runtime uses Zig for engine state, simulation, collision, spatial queries, animation, and telemetry while LÖVE handles rendering, windowing, and input.

This project intentionally does not include ImGui or an editor overlay. The game is driven by a lightweight debug UI module instead of a developer editor.

## Requirements

- Zig 0.16.0 or compatible
- LÖVE 11.5 or compatible
- A Windows/Linux/macOS build environment matching the target you want to compile for

## Build

From the project root:

```powershell
zig build
```

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
- Entity pool with spawn, destroy, and reuse logic
- Position, velocity, render order, and sprite state management
- Physics state: static, kinematic, and dynamic bodies
- Dynamic-vs-dynamic collision response with impulses, restitution, and friction
- Circle, capsule, AABB, OBB, and convex polygon collision primitives
- Adaptive substep continuous collision detection for fast-moving bodies
- Native static AABB colliders and grounded contact reporting
- Collision tests and raycast queries over a spatial grid
- Pathfinding requests with incremental stepping
- Snapshot serialization and restore support
- Camera transform management
- Animation state and frame selection in native code
- Debug runtime panel in LÖVE for pause, gravity, spawn controls, and engine timing

## Project Layout

```text
build.zig                Zig build configuration
src_zig/
  engine_math.zig        Math helpers and utility routines
  engine_runtime.zig     Runtime simulation and update logic
  engine_snapshot.zig    Snapshot encode/decode logic
  engine_types.zig      Native structs and constants
  main.zig              Exported engine API
main.lua                 LÖVE entry point and FFI bridge setup
game_logic.lua           Reloadable gameplay logic
modules/
  ui.lua                 Debug panel / runtime controls
ffi_bindings.lua         LuaJIT FFI declarations
tools/
  generate_bindings.ps1  Regenerate the FFI bindings
  package.ps1            Package the game for distribution
zig-out/bin/             Built native libraries and output artifacts
```

## Core Engine API

The engine exports the following native API through LuaJIT FFI.

### Lifecycle and diagnostics

- `engine_create(...)`
- `engine_destroy(...)`
- `engine_entity_capacity(...)`
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
- `engine_positions_x(...)`
- `engine_positions_y(...)`
- `engine_velocities_x(...)`
- `engine_velocities_y(...)`
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

### Input and events

- `engine_set_input(...)`
- `engine_next_event(...)`
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

## Bindings Regeneration

If the exported Zig API changes, regenerate the LuaJIT FFI declarations:

```powershell
.\tools\generate_bindings.ps1
```

## Notes

- The engine state is intentionally native and is managed through Zig.
- LÖVE remains the rendering and windowing layer.
- ImGui/editor tooling has been removed from this project and is not part of the current runtime.
