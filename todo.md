# Zig Engine Improvement Roadmap

This backlog covers the native engine in `src_zig/`. Lua gameplay and LÖVE
rendering integration are outside its scope. Items are ordered by risk and
leverage rather than by implementation size.

## P0: Correctness and Determinism

- [ ] Fix OBB setup so `engine_set_obb` explicitly enables collision, matching
  the other shape setters. Add a regression test for OBB-vs-OBB and OBB-vs-AABB
  simulation contacts.
- [ ] Make entity-storage growth transactional. `resizeEntityStorage` currently
  reallocates many arrays in sequence; an allocation failure after an earlier
  successful realloc can leave the context with mismatched array lengths.
  Stage allocations or use a recoverable growth strategy, then add an injected
  allocation-failure test.
- [ ] Define and enforce a fixed-step simulation policy. Add an accumulator or
  a documented caller contract, clamp unreasonable `dt` values, and test that
  equivalent elapsed time produces equivalent results across frame rates.
- [ ] Make simulation ordering deterministic. Use stable entity iteration and
  stable collision/contact ordering, and document whether floating-point
  results are guaranteed only per platform or across platforms.
- [ ] Finish snapshot validation. Validate every serialized count, queue index,
  enum, polygon count, tilemap dimension, and payload offset before mutating
  the context. Add malformed, truncated, wrong-version, and wrong-capacity
  tests.
- [ ] Define snapshot semantics for transient queues. Decide whether events,
  audio commands, and combat results are restored for rollback or discarded at
  the restore boundary, then test the chosen behavior.
- [ ] Add a path reconstruction API. `engine_pathfind_length` reports only a
  count even though parent links are stored; expose a caller-provided output
  buffer for the grid coordinates or cell indices.
- [ ] Add traversability to pathfinding. Support blocked cells or a callback/
  mask so BFS does not search through every grid cell indiscriminately.
- [ ] Resolve combat duplicate hits. Track attacker/victim or hitbox/hurtbox
  pairs during one resolve pass so one attack cannot damage the same target
  repeatedly unless that behavior is explicitly requested.

## P1: Physics and Runtime Quality

- [ ] Add explicit friction and restitution configuration per body or material.
  Replace the current hard-coded impulse coefficients with documented defaults
  and setters.
- [ ] Improve capsule collision accuracy. The current polygon approximation is
  useful for contacts, but raycasts and mixed-shape contacts should use exact
  capsule geometry where practical; add boundary-focused tests.
- [ ] Add collision filtering. Provide layer/mask or category/mask fields so
  entities can selectively collide without disabling collision globally.
- [ ] Add trigger/sensor bodies. Report overlap enter, stay, and exit events
  without applying impulses.
- [ ] Replace the all-pairs dynamic collision loop with a broad phase based on
  the spatial grid or per-entity swept bounds. Preserve deterministic pair
  ordering and benchmark against the current implementation.
- [ ] Use swept bounds for fast bodies and static colliders. Adaptive substeps
  reduce tunneling risk, but a broad-phase query should also include the full
  motion interval rather than only the current cell.
- [ ] Separate 2D vertical physics from 2.5D ground depth more explicitly.
  Document units and coordinate conventions in the ABI, and add tests for
  moving platforms, kinematic bodies, and simultaneous `y` and `z` movement.
- [ ] Complete grounded/contact reporting. Expose the contact normal or a
  contact count, and reset/report grounded state consistently for all ground
  collision cases.
- [ ] Add a real telemetry pipeline. Populate `physics_us`,
  `spatial_sort_us`, and `ffi_serialization_us` around their actual work, and
  define whether timings are per-frame, rolling, or last-frame values.
- [ ] Add explicit overflow telemetry for audio and combat queues. Keep event,
  audio, and combat drop counts separate and expose them through `Telemetry`.

## P1: ABI and Memory Safety

- [ ] Generate and ship a C-compatible header from the exported Zig ABI. Keep
  struct layouts, constants, sentinel values, and function signatures checked
  by a compile-time or CI ABI test.
- [ ] Add pointer lifetime rules to the API or remove raw array-pointer
  exposure. Any `spawn` or `reserve` can invalidate array pointers after a
  resize; provide accessor refresh functions or a stable view contract.
- [ ] Use opaque entity handles with generation checks in addition to slot
  indices. This prevents stale references from accidentally addressing a new
  entity that reused the same slot.
- [ ] Add checked arithmetic for all capacity and byte-size calculations,
  especially snapshot sizes, grid dimensions, polygon storage, and tilemap
  dimensions.
- [ ] Replace magic numeric event/button IDs with exported enums or named
  constants in the generated binding surface.
- [ ] Add an explicit context status/error API. Return a stable error code or
  last-error value for invalid arguments, full pools, malformed snapshots, and
  allocation failures instead of requiring callers to infer the cause from
  `false` or `INVALID_INDEX`.

## P1: Test and Verification Coverage

- [ ] Add tests for every exported subsystem: entity destruction/anchors,
  reserve growth, camera matrices, animation looping, frame arena exhaustion,
  tilemap bounds, light/particle pool exhaustion, event/audio queue overflow,
  spatial queries, and pathfinding states.
- [ ] Add property or fuzz tests for shape contacts, raycasts, polygon input,
  and snapshot read/apply. No malformed input should panic or partially mutate
  the context.
- [ ] Add rollback determinism tests that snapshot, advance, restore, and
  replay the same input sequence while comparing all serialized state.
- [ ] Run native tests and ABI builds for Windows, Linux, and macOS in CI.
  Include Debug and ReleaseSafe builds and treat compiler warnings/errors as
  failures.
- [ ] Add performance benchmarks for update time, entity growth, collision
  broad phase, snapshot size/write time, and spatial queries at representative
  entity counts.

## P2: Rendering and Content Capabilities

- [ ] Add tilemap collision extraction or a collision layer import path so
  authored level geometry can populate static colliders automatically.
- [ ] Add tilemap chunking or dirty-region updates for maps near the
  `MAX_TILEMAP_TILES` limit instead of treating the entire map as one pool.
- [ ] Add animation metadata beyond contiguous frame IDs: per-frame duration,
  event markers, reverse playback, and explicit animation completion events.
- [ ] Add particle emission controls and pooling helpers: bursts, spawn rate,
  acceleration, color/size curves, and deterministic seeds.
- [ ] Add light falloff and shadow/culling metadata while keeping the native
  light pool fixed-capacity and directly iterable.
- [ ] Add render commands or batching metadata for sprites, particles, and
  lights so the LÖVE bridge can minimize state changes without rebuilding
  temporary Lua objects.

## P2: Diagnostics and Editor Support

- [ ] Add a native debug command surface for pause, single-step, gravity,
  entity inspection, collision visualization, spatial-cell visualization, and
  queue/pool statistics. Keep it separate from the simulation ABI.
- [ ] Add frame capture and replay files containing input, engine configuration,
  and snapshots. Make captures loadable in a headless test runner.
- [ ] Add a native profiler timeline or scoped timers around update phases and
  expose the data without allocating per frame.
- [ ] Build an editor only after the ABI and capture/replay tools are stable:
  entity selection, transform gizmos, live component inspection, grid snapping,
  and runtime spawning should consume the public debug API rather than access
  `EngineContext` fields directly.

## P3: Larger Engine Features

- [ ] Add a scheduler or explicit system pipeline so physics, combat, AI,
  animation, and presentation can declare ordering instead of relying on one
  fixed `engine_update` sequence.
- [ ] Add separate worlds or scenes with controlled transfer of entities,
  static colliders, tilemaps, and render pools.
- [ ] Add worker-thread-friendly job boundaries for pathfinding, broad-phase
  building, and snapshot compression, while keeping the public context API
  single-threaded until ownership rules are defined.
- [ ] Add optional compression for full snapshots and deltas, with versioned
  feature flags so rollback buffers can trade memory for CPU explicitly.
- [ ] Define a versioned save-game format separate from rollback snapshots;
  save data should not depend on exact array capacity or internal ECS layout.

## Suggested First Slice

1. Fix OBB collision enabling and add its regression test.
2. Make storage growth failure-safe.
3. Add snapshot fuzz/validation tests.
4. Add fixed-step/determinism coverage.
5. Measure the collision loop before replacing it with a broad phase.
