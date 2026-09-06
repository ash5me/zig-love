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
- `engine_update(context, dt)` updates active entities and rebuilds the grid.

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
