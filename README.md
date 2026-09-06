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

The engine exports a native API used by Lua via FFI, including:

- `engine_create(...)`
- `engine_destroy(...)`
- `engine_spawn(...)`
- `engine_destroy_entity(...)`
- `engine_set_position(...)`
- `engine_set_velocity(...)`
- `engine_set_input(...)`
- `engine_update(...)`
- `engine_raycast(...)`
- `engine_query_cell(...)`
- `engine_pathfind_begin(...)`
- `engine_pathfind_step(...)`
- `engine_snapshot_write(...)`
- `engine_snapshot_read(...)`
- `engine_camera_set(...)`
- `engine_camera_matrix(...)`
- `engine_animation_set(...)`
- `engine_current_sprite_frame_id(...)`
- `engine_set_body(...)`
- `engine_test_collision(...)`

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
