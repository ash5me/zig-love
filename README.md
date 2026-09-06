# Zig Love2D Integration

A small example of calling Zig code from a Love2D game through LuaJIT FFI.

## Requirements

- Zig 0.16.0 or compatible
- Love2D 11.5 or compatible
- A Love2D build with LuaJIT FFI support

## Build

From the project root:

```powershell
zig build
```

The shared library is generated at:

```text
zig-out/bin/game_systems.dll
```

## Run

Start the Love2D project from the project root:

```powershell
love .
```

For visible console output, use:

```powershell
love --console .
```

The startup test calls Zig's `add_numbers` function and prints:

```text
Sum from Zig: 42
```

## Project Layout

```text
build.zig          Zig build configuration
src_zig/main.zig   Exported Zig functions
main.lua           Love2D game and LuaJIT FFI declarations
game_logic.lua     Reloadable gameplay logic
ffi_bindings.lua   Generated LuaJIT FFI declarations
tools/             Binding generator and Windows packaging scripts
zig-out/bin/       Generated shared library and debug files
```

## Phase 1 Bridge

`engine_create` allocates an opaque `EngineContext` on Zig's native page
allocator. Call `engine_destroy` from `love.quit`; no array view is valid after
that call.

Lua computes stable 32-bit FNV-1a IDs and passes them through the `u64` ID lanes.
Zig APIs accept those IDs instead of receiving Lua strings.

## Phase 2 Engine Core

Entity data uses a Structure-of-Arrays layout: positions, velocities, sprite IDs,
IDs, and lifecycle flags occupy separate contiguous arrays. Lua receives direct
views of the position and sprite arrays for zero-copy rendering.

`engine_spawn` and `engine_destroy_entity` manage fixed-capacity slots with an
internal free-list. Destroyed slots are immediately reusable without allocating
or moving other entities. `engine_update` rebuilds a fixed-size spatial hash grid;
`engine_query_cell` returns the pooled entity indices in one grid cell.

## Phase 4 Systems

Lua fills one `InputState` cdata struct per frame with keyboard/mouse button bits
and cursor coordinates, then sends that snapshot through `engine_set_input`.
Zig detects button edges and writes gameplay changes to a fixed 256-entry event
ring. Lua drains it with `engine_next_event` and can route sound or scene logic
without polling gameplay state.

The reusable grid also backs a breadth-first pathfinder. `engine_pathfind_begin`
starts a request and `engine_pathfind_step` processes only the requested node
budget per frame, preventing a large search from blocking the render loop.

## Advanced Memory Systems

`engine_snapshot_size`, `engine_snapshot_write`, and `engine_snapshot_read`
serialize and restore the pool arrays, lifecycle free-list, anchors, input,
events, and pathfinding state. Snapshots include a magic number, version, and
layout dimensions so incompatible buffers are rejected before mutation.

Lua-held entity references use `engine_anchor_entity` and
`engine_release_entity`. An anchored live slot cannot be destroyed or returned
to the free-list until every matching release has occurred.

`engine_frame_alloc` provides short-lived byte storage from a fixed native arena.
`engine_frame_begin` resets it, and `engine_update` calls that reset
automatically at the start of every frame. Exhaustion returns a null pointer;
there is no fallback allocation during gameplay.

## Gameplay and Rendering Pipeline

`CameraState` is maintained in Zig with position, scale, rotation, viewport, and
parallax values. `engine_camera_matrix` exposes the calculated 3x3 transform;
the Lua renderer embeds it into LÖVE's transform before drawing.

Render layers use a separate `render_z` array and `render_order` index buffer.
`engine_sort_render_order` and the frame update sort indices by Z without moving
the position, velocity, or sprite SoA arrays.

Animation state is also native. `engine_animation_set` configures the first frame,
frame count, duration, and loop mode; `engine_update` advances it and
`engine_current_sprite_frame_id` returns the active frame ID for Lua-side asset
selection.

## Physics and Geometry

Entities can be configured as `BODY_STATIC`, `BODY_KINEMATIC`, or
`BODY_DYNAMIC`. Static bodies do not move, kinematic bodies follow their velocity
without gravity, and dynamic bodies receive gravity and velocity integration.
`engine_set_body` also selects circle or vertical capsule narrow-phase geometry.

`engine_test_collision` performs circle/capsule distance tests. `engine_raycast`
walks the spatial grid along a segment and tests the candidate shapes, returning
the nearest entity ID, entity index, impact coordinates, and distance through a
`RaycastHit` result.

## Exported Functions

- `add_numbers(a, b)` returns the sum of two integers.
- `engine_create(capacity, grid_width, grid_height, cell_size)` allocates the SoA and grid.
- `engine_spawn(...)` takes a free pool slot and returns its index.
- `engine_destroy_entity(context, index)` returns a slot to the free-list.
- `engine_find_entity(context, id)` looks up an entity index by ID.
- `engine_query_cell(context, cell_x, cell_y, output, capacity)` queries a grid bucket.
- `engine_set_input(context, input)` submits the current input snapshot.
- `engine_next_event(context, output)` drains one queued gameplay event.
- `engine_pathfind_begin(context, start_x, start_y, goal_x, goal_y)` starts a search.
- `engine_pathfind_step(context, node_budget)` advances the search incrementally.
- `engine_snapshot_write(context, buffer, capacity)` serializes engine state.
- `engine_snapshot_read(context, buffer, size)` validates and restores a snapshot.
- `engine_anchor_entity(context, index)` protects a Lua-held entity slot.
- `engine_release_entity(context, index)` releases one Lua anchor.
- `engine_frame_alloc(context, size)` allocates temporary frame memory.
- `engine_camera_set(context, camera)` updates the world-to-screen camera.
- `engine_camera_matrix(context)` returns the calculated transform matrix.
- `engine_sort_render_order(context)` sorts the render index buffer by Z.
- `engine_animation_set(context, index, first_frame, count, duration, loop)` configures an animation.
- `engine_current_sprite_frame_id(context, index)` reads the native animation frame.
- `engine_set_body(context, index, body_type, shape_type, radius, half_length)` configures physics behavior.
- `engine_test_collision(context, first, second)` performs circle/capsule collision testing.
- `engine_raycast(context, ax, ay, bx, by, output)` performs a grid-accelerated LOS query.
- `engine_update(context, dt)` updates active entities and rebuilds the grid.

## Diagnostics and Cross-Compilation

The optional in-game debug panel reports native physics, spatial-sort, FFI
serialization, and Lua draw times in microseconds. Native timings use Windows
QueryPerformanceCounter on the production Windows target.

Cross-target ABI checks compile the shared library without requiring the host OS
to match the target:

```powershell
zig build cross-windows
zig build cross-linux
zig build cross-macos
```

Use `-Dcross-release=false` for faster debug-oriented cross checks. The normal
`zig build -Dproduction=true` path still produces the host platform artifact.

## Phase 5 Shipping

Press `F5` while running to reload `game_logic.lua`. The Lua module is replaced
only after it loads and validates; the Zig context, pooled entities, positions,
pathfinding state, and event queue remain intact.

Regenerate the FFI declarations after changing exported Zig types or functions:

```powershell
.\tools\generate_bindings.ps1
```

Build the native library with production optimization:

```powershell
zig build -Dproduction=true
```

To create a Windows fused executable, provide a full `love.exe` path. The
script creates `dist/game.love` and appends it to `dist/game.exe`:

```powershell
.\tools\package.ps1 -LoveExe "C:\\Program Files\\LOVE\\love.exe"
```
