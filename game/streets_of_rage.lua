---@diagnostic disable: undefined-global
local StreetsOfRage = {}

local WIDTH, HEIGHT = 960, 600
local FLOOR_Y = 440
local PLAYER = 0
local ENEMIES = { 1, 2, 3 }
local PLAYER_ACCELERATION = 1250
local PLAYER_MAX_SPEED = 190
local PLAYER_FRICTION = 1550
local SOUND_ROOT = "assets/Streets-of-Rage-1-Sound-Effects/"
local SOUND = {
    attack = 1,
    impact = 2,
    grab = 3,
    throw = 4,
    player_hurt = 5,
    enemy_hurt = 6,
    player_knockdown = 7,
    enemy_attack = 8,
    player_voice = 47,
    enemy_voice = 48,
}

local function screen_x(state, world_x)
    return world_x - state.camera_manager.x + WIDTH * 0.5
end

local function load_frames(state, folder, prefix, count)
    local frames = {}
    for index = 1, count do
        local frame = state.assets:load_image(folder .. "/" .. prefix .. tostring(index) .. ".png")
        if frame then frames[#frames + 1] = frame end
    end
    return frames
end

local function draw_actor(actor, frames, x, z, facing, elapsed, color)
    local image = #frames > 0 and frames[math.floor(elapsed * 10) % #frames + 1] or nil
    local screen_y = FLOOR_Y - z * 0.45
    love.graphics.setColor(0.04, 0.03, 0.04, 0.28)
    love.graphics.ellipse("fill", x, screen_y + 4, 34, 9)
    if image then
        local scale = 0.9
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(image, x, screen_y, 0, scale * facing, scale, image:getWidth() / 2, image:getHeight())
    else
        love.graphics.setColor(color[1], color[2], color[3], 1)
        love.graphics.circle("fill", x, screen_y - 62, 16)
        love.graphics.rectangle("fill", x - 20, screen_y - 50, 40, 48, 6, 6)
    end
end

local function draw_prop(prop, x, z, camera_x)
    if not prop.image then return end
    local scale = prop.scale or 1
    local screen_y = FLOOR_Y - z * 0.45
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(prop.image, x - camera_x + WIDTH * 0.5, screen_y, 0, scale, scale, prop.image:getWidth() * 0.5, prop.image:getHeight())
end

local function draw_layer(image, camera_x, alpha)
    if not image then return end
    local scale = math.max(WIDTH / image:getWidth(), HEIGHT / image:getHeight())
    local width = image:getWidth() * scale
    local offset = -((camera_x * 0.22) % width)
    love.graphics.setColor(1, 1, 1, alpha or 1)
    for x = offset - width, WIDTH + width, width do
        love.graphics.draw(image, x, 0, 0, scale, scale)
    end
end

local function register_sounds(state)
    for index = 1, 46 do
        local source = state.assets:load_sound(SOUND_ROOT .. "SE " .. tostring(index) .. ".wav")
        if source then state.audio:register(index, source) end
    end
    for index = 1, 10 do
        local sound_id = 46 + index
        local source = state.assets:load_sound(SOUND_ROOT .. "Voice" .. tostring(index) .. ".wav")
        if source then state.audio:register(sound_id, source) end
    end
end

local function emit_sound(state, sound_id, entity, volume)
    if not state.audio or not state.positions_x[entity] then return end
    state.audio:emit(sound_id, state.positions_x[entity], state.positions_y[entity], 720, volume or 1)
end

local function approach(value, target, amount)
    if value < target then return math.min(value + amount, target) end
    return math.max(value - amount, target)
end

local function separate_actors(state, game)
    local actors = { PLAYER }
    for _, enemy in ipairs(game.enemies) do actors[#actors + 1] = enemy.owner end
    for first_index = 1, #actors do
        for second_index = first_index + 1, #actors do
            local first, second = actors[first_index], actors[second_index]
            local dx = state.positions_x[second] - state.positions_x[first]
            local dz = state.positions_z[second] - state.positions_z[first]
            local overlap_x = 30 - math.abs(dx)
            local overlap_z = 20 - math.abs(dz)
            if overlap_x > 0 and overlap_z > 0 then
                if overlap_x < overlap_z then
                    local direction = dx >= 0 and 1 or -1
                    local correction = overlap_x * 0.5
                    state.zig.engine_set_25d_position(state.context, first, state.positions_x[first] - direction * correction, state.positions_z[first], state.positions_y[first])
                    state.zig.engine_set_25d_position(state.context, second, state.positions_x[second] + direction * correction, state.positions_z[second], state.positions_y[second])
                else
                    local direction = dz >= 0 and 1 or -1
                    local correction = overlap_z * 0.5
                    state.zig.engine_set_25d_position(state.context, first, state.positions_x[first], state.positions_z[first] - direction * correction, state.positions_y[first])
                    state.zig.engine_set_25d_position(state.context, second, state.positions_x[second], state.positions_z[second] + direction * correction, state.positions_y[second])
                end
            end
        end
    end
end

function StreetsOfRage.update(state, dt)
    local game = state.streets_of_rage
    if not game then
        game = {
            initialized = false,
            elapsed = 0,
            player = PLAYER,
            enemies = {},
            player_vx = 0,
            player_vz = 0,
            player_moving = false,
        }
        state.streets_of_rage = game
    end
    game.elapsed = game.elapsed + dt

    if not game.initialized then
        game.frames = {
            player = load_frames(state, "assets/Sprites/Brawler-Girl/Idle", "idle", 4),
            player_walk = load_frames(state, "assets/Sprites/Brawler-Girl/Walk", "walk", 10),
            enemy = load_frames(state, "assets/Sprites/Enemy-Punk/Idle", "idle", 4),
            enemy_walk = load_frames(state, "assets/Sprites/Enemy-Punk/Walk", "walk", 4),
        }
        register_sounds(state)
        state.combat:on_hit(function(hit)
            emit_sound(state, SOUND.impact, hit.attacker, 0.9)
            emit_sound(state, hit.victim == PLAYER and SOUND.player_hurt or SOUND.enemy_hurt, hit.victim, 0.85)
        end)
        game.stage_back = state.assets:load_image("assets/Stage Layers/back.png")
        game.stage_fore = state.assets:load_image("assets/Stage Layers/fore.png")
        game.props = {
            { image = state.assets:load_image("assets/Stage Layers/props/car.png"), x = 170, z = -30, scale = 0.9 },
            { image = state.assets:load_image("assets/Stage Layers/props/barrel.png"), x = 360, z = 18, scale = 0.75 },
            { image = state.assets:load_image("assets/Stage Layers/props/hydrant.png"), x = 760, z = -18, scale = 0.7 },
            { image = state.assets:load_image("assets/Stage Layers/props/banner-hor/banner-hor1.png"), x = 560, z = 48, scale = 0.8 },
        }
        for _, index in ipairs({ PLAYER, 1, 2, 3 }) do
            state.zig.engine_set_25d_position(state.context, index, index == PLAYER and 180 or 480 + index * 80, index == PLAYER and 0 or (index % 2 == 0 and 38 or -38), 0)
            state.zig.engine_set_ground_aabb(state.context, index, 1, 18, 12)
        end
        state.player_fsm = state.new_player_fsm(PLAYER, {
            on_state_changed = function(next_state)
                state.status_text = next_state == "Grabbed" and "Enemy grabbed" or ""
                if next_state == "Attack1" or next_state == "Attack2" or next_state == "Attack3" then
                    emit_sound(state, SOUND.attack, PLAYER, 0.8)
                elseif next_state == "Knee Strike" then
                    emit_sound(state, SOUND.attack, PLAYER, 0.95)
                elseif next_state == "Knockdown" then
                    emit_sound(state, SOUND.player_knockdown, PLAYER, 1)
                elseif next_state == "Grabbed" then
                    emit_sound(state, SOUND.grab, PLAYER, 0.9)
                end
            end,
        })
        state.camera_manager:set_player(PLAYER)
        for _, index in ipairs(ENEMIES) do
            local enemy = state.new_enemy_ai(index, PLAYER, {
                attack_distance = 76,
                callbacks = {
                    on_state_changed = function(next_state, owner)
                        if next_state == "Attack" then emit_sound(state, SOUND.enemy_attack, owner, 0.8) end
                        if next_state == "Projectile" then emit_sound(state, SOUND.throw, owner, 1) end
                    end,
                },
            })
            game.enemies[#game.enemies + 1] = enemy
        end
        state.camera_manager:add_trigger({
            x = 600,
            width = 40,
            message = "Defeat the street punks",
            spawn = function()
                return ENEMIES
            end,
        })
        game.initialized = true
    end

    local player_x = state.positions_x[PLAYER]
    local player_z = state.positions_z[PLAYER]
    local horizontal, depth = 0, 0
    if state.input:is_down("move_left") then horizontal = horizontal - 1 end
    if state.input:is_down("move_right") then horizontal = horizontal + 1 end
    if state.input:is_down("move_up") then depth = depth - 1 end
    if state.input:is_down("move_down") then depth = depth + 1 end
    if state.player_fsm:get_state() == "Idle" or state.player_fsm:get_state() == "Grabbed" then
        if horizontal ~= 0 then state.player_fsm:set_facing(horizontal) end
        local target_vx = horizontal * PLAYER_MAX_SPEED
        local target_vz = depth * PLAYER_MAX_SPEED * 0.62
        local acceleration = PLAYER_ACCELERATION * dt
        local friction = PLAYER_FRICTION * dt
        game.player_vx = horizontal == 0 and approach(game.player_vx, 0, friction) or approach(game.player_vx, target_vx, acceleration)
        game.player_vz = depth == 0 and approach(game.player_vz, 0, friction) or approach(game.player_vz, target_vz, acceleration)
        game.player_moving = math.abs(game.player_vx) > 2 or math.abs(game.player_vz) > 2
        state.zig.engine_set_25d_position(state.context, PLAYER, math.max(48, math.min(900, player_x + game.player_vx * dt)), math.max(-80, math.min(80, player_z + game.player_vz * dt)), state.positions_y[PLAYER])
    else
        game.player_vx, game.player_vz, game.player_moving = 0, 0, false
    end

    state.player_fsm:update(dt)
    for _, enemy in ipairs(game.enemies) do enemy:update(dt) end
    separate_actors(state, game)
end

function StreetsOfRage.draw(state)
    local game = state.streets_of_rage
    local camera_x = state.camera_manager.x
    love.graphics.clear(0.06, 0.07, 0.11, 1)
    draw_layer(game.stage_back, camera_x, 1)
    if not game.stage_back then
        love.graphics.setColor(0.10, 0.12, 0.18, 1)
        love.graphics.rectangle("fill", 0, 230, WIDTH, 220)
        love.graphics.setColor(0.18, 0.16, 0.17, 1)
        love.graphics.rectangle("fill", 0, 450, WIDTH, 150)
        love.graphics.setColor(0.40, 0.34, 0.28, 1)
        love.graphics.rectangle("fill", 0, FLOOR_Y + 36, WIDTH, 4)
        for x = 0, WIDTH, 90 do
            love.graphics.rectangle("fill", x, 300 + (x % 3) * 18, 56, 74)
            love.graphics.setColor(0.72, 0.52, 0.24, 0.45)
            love.graphics.rectangle("fill", x + 12, 316 + (x % 3) * 18, 10, 18)
        end
    end
    for _, prop in ipairs(game.props or {}) do draw_prop(prop, prop.x, prop.z, camera_x) end

    local player_x, player_z = state.positions_x[PLAYER], state.positions_z[PLAYER]
    local player_frames = game.player_moving and game.frames.player_walk or game.frames.player
    draw_actor(PLAYER, player_frames, screen_x(state, player_x), player_z, state.player_fsm.facing, game.elapsed, { 0.86, 0.18, 0.27 })
    for _, enemy in ipairs(game.enemies) do
        local index = enemy.owner
        local enemy_state = enemy:get_state()
        local enemy_frames = (enemy_state == "Approach" or enemy_state == "Flank") and game.frames.enemy_walk or game.frames.enemy
        draw_actor(enemy, enemy_frames, screen_x(state, state.positions_x[index]), state.positions_z[index], enemy.facing, game.elapsed, { 0.66, 0.18, 0.14 })
    end
    draw_layer(game.stage_fore, camera_x, 0.8)

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("NIGHT SHIFT", 24, 20)
    love.graphics.print("A/D: move   W/S: depth   J/Z: attack   Space: jump attack   Close range: grab   K/Q: throw", 24, 44)
    love.graphics.print("State: " .. state.player_fsm:get_state(), 24, 70)
    if state.camera_manager:get_prompt() then
        love.graphics.setColor(1, 0.78, 0.22, 1)
        love.graphics.printf(state.camera_manager:get_prompt(), 0, 112, WIDTH, "center")
    end
end

return StreetsOfRage
