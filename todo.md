1. Robust Physics & Collision Resolution
No Dynamic-vs-Dynamic Collision Response: While your engine_math.zig contains distance/overlap math (shapeDistanceSquared) and raycasts, the runtime doesn't resolve collisions between dynamic bodies (no impulse/penetration resolution, restitution, or friction math).

Missing Shape Primitives: You currently support Circles and Capsules, but lack Axis-Aligned Bounding Boxes (AABB), Oriented Bounding Boxes (OBB), and Convex Polygons.

No Continuous Collision Detection (CCD): Fast-moving dynamic entities will pass straight through thin platforms ("tunneling") because positional integration relies on simple Euler steps without sweeping.

Primitive Platformer Logic: In platformer.lua, platform landing is manually calculated in Lua with hardcoded array iterations instead of relying on the Zig physics solver.

2. Rendering & Batching Pipeline
No Sprite Batching or Instancing: Render loops in logic.lua call individual love.graphics.circle calls per entity. Drawing thousands of entities this way introduces massive CPU-to-GPU call overhead in Lua.

Missing Tilemap Engine: There is no native support for loading, parsing, or rendering tilemaps (e.g., Tiled .tmx / JSON format).

No Particle or Lighting Systems: No built-in particle emitter system in Zig for high-count FX, nor 2D light/shadow projection primitives.

3. Engine Architecture & Memory Management
Basic Fixed-Size Memory Limits: Context memory capacities are pre-allocated at startup without dynamic pool resizing, ring-buffer cleanup, or graceful fallback mechanisms when capacity fills up.

Incomplete Snapshot Serialization: In engine_snapshot.zig, writing functions exist, but full state restoration (snapshotRead) and delta-compression for rollback networking are incomplete.

Unidirectional Event Pipeline: Events flow from Zig to Lua via the ring buffer, but Lua lacks a structured, bi-directional event interface to pass custom triggers back into Zig cleanly.

4. Audio, Input & Asset Pipelines
No Native Spatial Audio Engine: Audio events in Zig (EVENT_PLAY_SOUND) rely entirely on Lua catching the event ID and manually calling love.audio, with no spatial attenuation (distance-based volume/panning) calculated on the Zig side.

No Rebindable Input Mapping: Input is handled via raw bitmasks (context.input.buttons), with no action-mapping system (e.g., mapping "Jump" to both Space and a Controller A button).

No Asset Manager / VFS: No centralized pipeline for caching, loading, or hot-reloading textures, sound files, or level data.