---@diagnostic disable: undefined-global
local ffi = require("ffi")
local bit = require("bit")

package.path = "modules/?.lua;game/?.lua;" .. package.path

ffi.cdef(dofile("ffi_bindings.lua"))

local zig = ffi.load("zig-out/bin/game_systems.dll")
local ENTITY_CAPACITY = 1000
local GRID_WIDTH, GRID_HEIGHT, CELL_SIZE = 64, 64, 32.0
local INVALID_INDEX = 0xffffffff
local INPUT_PLAY_SOUND, INPUT_PLAYER_DIED = 1, 2
local EVENT_PLAY_SOUND, EVENT_PLAYER_DIED, EVENT_PATH_READY = 1, 2, 3
local PATH_WORKING, PATH_FOUND = 1, 2
local BODY_STATIC, BODY_KINEMATIC, BODY_DYNAMIC = 0, 1, 2
local SHAPE_CIRCLE, SHAPE_CAPSULE = 1, 2
local engine_context, positions_x, positions_y, positions_z, velocities_x, velocities_y, velocities_z, shadow_positions_x, shadow_positions_y, depth_order, sprite_ids, query_results, input_state, event, combat_event
local render_order, camera_matrix, camera_transform, camera_state
local first_entity_id
local first_physics_index, static_position_x, physics_checked = INVALID_INDEX, 0, false
local logic
local runtime
local debug_ui
local assets
local debug_ui_visible = false
local debug_sequence = 1000000

local FNV_OFFSET = 2166136261
local FNV_PRIME = 16777619

local function fnv1a32(value)
    local hash = FNV_OFFSET
    for index = 1, #value do
        hash = bit.bxor(hash, string.byte(value, index))
        hash = hash * FNV_PRIME
        hash = hash % 4294967296
    end
    return ffi.new("uint64_t", hash)
end

function love.load()
    love.window.setMode(960, 600, {
        fullscreen = false,
        resizable = true,
        borderless = false,
        centered = true,
        minwidth = 720,
        minheight = 500,
    })
    print("Sum from Zig:", zig.add_numbers(15, 27))
    engine_context = zig.engine_create(ENTITY_CAPACITY, GRID_WIDTH, GRID_HEIGHT, CELL_SIZE)
    assert(engine_context ~= nil, "Zig could not allocate EngineContext")
    positions_x = zig.engine_positions_x(engine_context)
    positions_y = zig.engine_positions_y(engine_context)
    positions_z = zig.engine_positions_z(engine_context)
    velocities_x = zig.engine_velocities_x(engine_context)
    velocities_y = zig.engine_velocities_y(engine_context)
    velocities_z = zig.engine_velocities_z(engine_context)
    shadow_positions_x = zig.engine_shadow_positions_x(engine_context)
    shadow_positions_y = zig.engine_shadow_positions_y(engine_context)
    depth_order = zig.engine_depth_order(engine_context)
    sprite_ids = zig.engine_sprite_ids(engine_context)
    render_order = zig.engine_render_order(engine_context)
    camera_matrix = zig.engine_camera_matrix(engine_context)
    camera_transform = love.math.newTransform()
    camera_state = ffi.new("CameraState")
    camera_state.viewport_width, camera_state.viewport_height = love.graphics.getDimensions()
    camera_state.scale = 1
    camera_state.parallax_x, camera_state.parallax_y = 1, 1
    zig.engine_camera_set(engine_context, camera_state)
    query_results = ffi.new("uint32_t[?]", ENTITY_CAPACITY)
    input_state = ffi.new("InputState")
    event = ffi.new("EngineEvent")
    combat_event = ffi.new("CombatHitEvent")

    for index = 0, ENTITY_CAPACITY - 1 do
        local id = fnv1a32("entity:" .. index)
        local entity_index = zig.engine_spawn(engine_context, id, 10.0 + index % 20, 10.0, 10.0, 98.0, fnv1a32("sprite:dot"))
        assert(entity_index ~= INVALID_INDEX, "Entity pool exhausted during startup")
        assert(zig.engine_set_render_z(engine_context, entity_index, index % 3), "Render layer assignment failed")
        if index < 10 then
            assert(zig.engine_animation_set(engine_context, entity_index, 1000 + index * 4, 4, 0.12, true), "Animation setup failed")
        end
        if index == 0 then first_entity_id = id end
    end

    local first_index = zig.engine_find_entity(engine_context, first_entity_id)
    assert(first_index ~= INVALID_INDEX, "Zig entity lookup failed")
    assert(zig.engine_anchor_entity(engine_context, first_index), "Entity anchor failed")
    assert(not zig.engine_destroy_entity(engine_context, first_index), "Anchored entity was destroyed")
    assert(zig.engine_entity_anchor_count(engine_context, first_index) == 1, "Entity anchor count mismatch")
    assert(zig.engine_release_entity(engine_context, first_index), "Entity release failed")
    assert(zig.engine_destroy_entity(engine_context, first_index), "Entity destroy failed")
    local reused_index = zig.engine_spawn(engine_context, first_entity_id, 10.0, 10.0, 10.0, 98.0, sprite_ids[0])
    assert(reused_index == first_index, "Free-list did not reuse the released slot")
    first_physics_index = reused_index
    static_position_x = positions_x[first_physics_index]
    assert(zig.engine_set_body(engine_context, first_physics_index, BODY_STATIC, SHAPE_CAPSULE, 2.0, 4.0), "Static capsule setup failed")
    local second_index = zig.engine_find_entity(engine_context, fnv1a32("entity:1"))
    assert(zig.engine_set_body(engine_context, second_index, BODY_KINEMATIC, SHAPE_CIRCLE, 4.0, 0), "Kinematic circle setup failed")
    local third_index = zig.engine_find_entity(engine_context, fnv1a32("entity:2"))
    assert(zig.engine_set_body(engine_context, third_index, BODY_DYNAMIC, SHAPE_CIRCLE, 4.0, 0), "Dynamic circle setup failed")
    assert(zig.engine_test_collision(engine_context, first_physics_index, second_index), "Circle/capsule collision failed")
    local ray_hit = ffi.new("RaycastHit")
    zig.engine_rebuild_spatial(engine_context)
    assert(zig.engine_raycast(engine_context, 0, 14, 30, 14, ray_hit), "Raycast missed static capsule")
    assert(ray_hit.entity_index == first_physics_index and ray_hit.distance > 0 and ray_hit.distance < 30, "Raycast hit result was invalid")

    local snapshot_size = tonumber(zig.engine_snapshot_size(engine_context))
    local snapshot = ffi.new("uint8_t[?]", snapshot_size)
    assert(tonumber(zig.engine_snapshot_write(engine_context, snapshot, snapshot_size)) == snapshot_size, "Snapshot write failed")
    local saved_x = positions_x[reused_index]
    positions_x[reused_index] = saved_x + 500.0
    assert(zig.engine_snapshot_read(engine_context, snapshot, snapshot_size), "Snapshot read failed")
    assert(positions_x[reused_index] == saved_x, "Snapshot did not restore entity position")

    zig.engine_frame_begin(engine_context)
    assert(zig.engine_frame_alloc(engine_context, 128) ~= nil, "Frame arena allocation failed")
    assert(tonumber(zig.engine_frame_arena_used(engine_context)) == 128, "Frame arena usage mismatch")

    zig.engine_rebuild_spatial(engine_context)
    local nearby_count = zig.engine_query_cell(engine_context, 0, 0, query_results, ENTITY_CAPACITY)
    assert(nearby_count > 0, "Spatial grid query returned no entities")
    assert(zig.engine_pathfind_begin(engine_context, 0, 0, 20, 15), "Pathfinding request rejected")
    local AssetManager = require("modules.assets")
    local Particles = require("modules.particles")
    local Lighting = require("modules.lighting")
    local SpriteBatch = require("modules.sprite_batch")
    local Events = require("modules.events")
    local Input = require("modules.input")
    local Audio = require("modules.audio")
    assets = AssetManager.new()
    runtime = {
        context = engine_context,
        zig = zig,
        assets = assets,
        event = event,
        positions_x = positions_x,
        positions_y = positions_y,
        positions_z = positions_z,
        velocities_x = velocities_x,
        velocities_y = velocities_y,
        velocities_z = velocities_z,
        shadow_positions_x = shadow_positions_x,
        shadow_positions_y = shadow_positions_y,
        depth_order = depth_order,
        render_order = render_order,
        camera_matrix = camera_matrix,
        camera_transform = camera_transform,
        camera_state = camera_state,
        telemetry = zig.engine_telemetry(engine_context),
        paused = false,
        draw_us = 0,
        status_text = "",
        path_status = 0,
        path_working = PATH_WORKING,
        event_play_sound = EVENT_PLAY_SOUND,
        event_player_died = EVENT_PLAYER_DIED,
        event_path_ready = EVENT_PATH_READY,
        ffi = ffi,
        combat_event = combat_event,
        hit_stop_remaining = 0,
    }
    runtime.particles = Particles.new(runtime)
    runtime.lighting = Lighting.new(runtime)
    runtime.sprite_batch = SpriteBatch.new(zig.engine_entity_capacity(engine_context))
    runtime.events = Events.new(runtime)
    runtime.input = Input.new()
    runtime.audio = Audio.new(runtime)
    local Combat = require("modules.combat")
    local PlayerFSM = require("modules.player_fsm")
    local EnemyAI = require("modules.enemy_ai")
    local CameraManager = require("modules.camera_manager")
    runtime.combat = Combat.new(runtime)
    runtime.enemy_slots = EnemyAI.Slots(2)
    runtime.camera_manager = CameraManager.new(runtime)
    runtime.new_player_fsm = function(owner, callbacks)
        return PlayerFSM.new({ combat = runtime.combat, owner = owner, input = runtime.input, callbacks = callbacks })
    end
    runtime.new_enemy_ai = function(owner, player, options)
        options = options or {}
        options.runtime = runtime
        options.combat = runtime.combat
        options.owner = owner
        options.player = player
        options.slots = options.slots or runtime.enemy_slots
        return EnemyAI.new(options)
    end
    runtime.events:on(EVENT_PLAY_SOUND, function()
        runtime.status_text = "Play sound event"
    end)
    runtime.events:on(EVENT_PLAYER_DIED, function()
        runtime.status_text = "Player died event"
    end)
    runtime.events:on(EVENT_PATH_READY, function()
        runtime.status_text = "Path ready: " .. tostring(zig.engine_pathfind_length(engine_context)) .. " nodes"
    end)
    runtime.spawn_entities = function(count)
        for _ = 1, math.max(0, math.min(count, 100)) do
            local id = ffi.new("uint64_t", debug_sequence)
            debug_sequence = debug_sequence + 1
            local index = zig.engine_spawn(engine_context, id, 10, 10, 0, 0, id)
            if index ~= INVALID_INDEX then
                zig.engine_set_render_z(engine_context, index, 1)
                zig.engine_set_body(engine_context, index, BODY_DYNAMIC, SHAPE_CIRCLE, 4, 0)
            end
        end
    end
    logic = dofile("game_logic.lua")
    debug_ui = require("modules.ui")
end

function love.update(dt)
    input_state.buttons = runtime.input:buttons()
    input_state.mouse_x, input_state.mouse_y = love.mouse.getPosition()
    zig.engine_set_input(engine_context, input_state)
    runtime.audio:update_listener(camera_state.x, camera_state.y)
    runtime.audio:poll()
    if debug_ui_visible then
        debug_ui:update(runtime)
    end
    if not runtime.paused then
        if runtime.hit_stop_remaining > 0 then
            runtime.hit_stop_remaining = math.max(0, runtime.hit_stop_remaining - dt)
            return
        end
        runtime.hit_stop_remaining = math.max(0, runtime.hit_stop_remaining - dt)
        runtime.combat:begin_frame(dt)
        zig.engine_update(engine_context, dt)
        assert(tonumber(zig.engine_frame_arena_used(engine_context)) == 0, "Frame arena did not reset")
        if not physics_checked then
            assert(positions_x[first_physics_index] == static_position_x, "Static body moved during update")
            physics_checked = true
        end
        logic.update(runtime, dt)
        runtime.combat:resolve()
        runtime.camera_manager:update(dt)
    end
end

function love.draw()
    love.graphics.clear(0.08, 0.12, 0.20, 1)
    local ok, err = pcall(function()
        if logic and runtime then
            logic.draw(runtime)
            if runtime.particles then runtime.particles:draw() end
            if runtime.lighting then
                runtime.lighting:draw_shadows()
                runtime.lighting:draw()
            end
        end
    end)
    if not ok then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print("Draw error: " .. tostring(err), 20, 20)
    end
    if debug_ui_visible then
        local ui_ok, ui_err = pcall(function()
            if debug_ui then debug_ui:draw(runtime) end
        end)
        if not ui_ok then
            love.graphics.setColor(1, 0.3, 0.3, 1)
            love.graphics.print("UI draw error: " .. tostring(ui_err), 20, 40)
        end
    end
end

local function reload_logic()
    assets:reload_all()
    runtime.assets_reload_requested = true
    local ok, candidate = pcall(dofile, "game_logic.lua")
    if not ok then
        print("Lua logic reload failed: " .. tostring(candidate))
        return
    end
    if type(candidate) ~= "table" or type(candidate.update) ~= "function" or type(candidate.draw) ~= "function" then
        print("Lua logic reload rejected: expected update and draw functions")
        return
    end
    logic = candidate
    runtime.status_text = "Lua logic reloaded"
    print("Lua logic reloaded; Zig state preserved")
end

function love.keypressed(key)
    if key == "f2" then
        debug_ui_visible = not debug_ui_visible
        return
    end
    if debug_ui_visible and key == "f5" then
        reload_logic()
        debug_ui:keypressed(key)
    elseif debug_ui_visible then
        debug_ui:keypressed(key)
    end
end

function love.textinput(text)
    if debug_ui_visible then
        debug_ui:textinput(text)
    end
end

function love.quit()
    if runtime ~= nil and runtime.sprite_batch ~= nil then
        runtime.sprite_batch:release()
    end
    if engine_context ~= nil then
        zig.engine_destroy(engine_context)
        engine_context = nil
        positions_x = nil
        positions_y = nil
        velocities_x = nil
        velocities_y = nil
        sprite_ids = nil
        query_results = nil
        input_state = nil
        event = nil
        runtime = nil
        logic = nil
        if assets ~= nil then assets:clear() end
        assets = nil
    end
end