---@diagnostic disable: undefined-global
local ffi = require("ffi")
local bit = require("bit")

ffi.cdef(dofile("ffi_bindings.lua"))

local zig = ffi.load("zig-out/bin/game_systems.dll")
local ENTITY_CAPACITY = 1000
local GRID_WIDTH, GRID_HEIGHT, CELL_SIZE = 64, 64, 32.0
local INVALID_INDEX = 0xffffffff
local INPUT_PLAY_SOUND, INPUT_PLAYER_DIED = 1, 2
local EVENT_PLAY_SOUND, EVENT_PLAYER_DIED, EVENT_PATH_READY = 1, 2, 3
local PATH_WORKING, PATH_FOUND = 1, 2
local engine_context, positions_x, positions_y, sprite_ids, query_results, input_state, event
local first_entity_id
local logic
local runtime

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
    print("Sum from Zig:", zig.add_numbers(15, 27))
    engine_context = zig.engine_create(ENTITY_CAPACITY, GRID_WIDTH, GRID_HEIGHT, CELL_SIZE)
    assert(engine_context ~= nil, "Zig could not allocate EngineContext")
    positions_x = zig.engine_positions_x(engine_context)
    positions_y = zig.engine_positions_y(engine_context)
    sprite_ids = zig.engine_sprite_ids(engine_context)
    query_results = ffi.new("uint32_t[?]", ENTITY_CAPACITY)
    input_state = ffi.new("InputState")
    event = ffi.new("EngineEvent")

    for index = 0, ENTITY_CAPACITY - 1 do
        local id = fnv1a32("entity:" .. index)
        local entity_index = zig.engine_spawn(engine_context, id, 10.0 + index % 20, 10.0, 10.0, 98.0, fnv1a32("sprite:dot"))
        assert(entity_index ~= INVALID_INDEX, "Entity pool exhausted during startup")
        if index == 0 then first_entity_id = id end
    end

    local first_index = zig.engine_find_entity(engine_context, first_entity_id)
    assert(first_index ~= INVALID_INDEX, "Zig entity lookup failed")
    assert(zig.engine_destroy_entity(engine_context, first_index), "Entity destroy failed")
    local reused_index = zig.engine_spawn(engine_context, first_entity_id, 10.0, 10.0, 10.0, 98.0, sprite_ids[0])
    assert(reused_index == first_index, "Free-list did not reuse the released slot")

    zig.engine_rebuild_spatial(engine_context)
    local nearby_count = zig.engine_query_cell(engine_context, 0, 0, query_results, ENTITY_CAPACITY)
    assert(nearby_count > 0, "Spatial grid query returned no entities")
    assert(zig.engine_pathfind_begin(engine_context, 0, 0, 20, 15), "Pathfinding request rejected")
    runtime = {
        context = engine_context,
        zig = zig,
        event = event,
        positions_x = positions_x,
        positions_y = positions_y,
        status_text = "",
        path_status = 0,
        path_working = PATH_WORKING,
        event_play_sound = EVENT_PLAY_SOUND,
        event_player_died = EVENT_PLAYER_DIED,
        event_path_ready = EVENT_PATH_READY,
    }
    logic = dofile("game_logic.lua")
end

function love.update(dt)
    local buttons = 0
    if love.mouse.isDown(1) then buttons = buttons + INPUT_PLAY_SOUND end
    if love.keyboard.isDown("x") then buttons = buttons + INPUT_PLAYER_DIED end
    if love.keyboard.isDown("w") then buttons = buttons + 4 end
    if love.keyboard.isDown("a") then buttons = buttons + 8 end
    if love.keyboard.isDown("s") then buttons = buttons + 16 end
    if love.keyboard.isDown("d") then buttons = buttons + 32 end
    input_state.buttons = buttons
    input_state.mouse_x, input_state.mouse_y = love.mouse.getPosition()
    zig.engine_set_input(engine_context, input_state)
    zig.engine_update(engine_context, dt)
    logic.update(runtime, dt)
end

function love.draw()
    logic.draw(runtime)
end

local function reload_logic()
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
    if key == "f5" then reload_logic() end
end

function love.quit()
    if engine_context ~= nil then
        zig.engine_destroy(engine_context)
        engine_context = nil
        positions_x = nil
        positions_y = nil
        sprite_ids = nil
        query_results = nil
        input_state = nil
        event = nil
        runtime = nil
        logic = nil
    end
end