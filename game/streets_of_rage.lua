---@diagnostic disable: undefined-global
local StreetsOfRage = {}

local WIDTH, HEIGHT = 960, 600
local FLOOR_Y = 440
local PLAYER = 0
local ENEMIES = { 1, 2, 3 }

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

function StreetsOfRage.update(state, dt)
    local game = state.streets_of_rage
    if not game then
        game = {
            initialized = false,
            elapsed = 0,
            player = PLAYER,
            enemies = {},
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
        for _, index in ipairs({ PLAYER, 1, 2, 3 }) do
            state.zig.engine_set_25d_position(state.context, index, index == PLAYER and 180 or 480 + index * 80, index == PLAYER and 0 or (index % 2 == 0 and 38 or -38), 0)
            state.zig.engine_set_ground_aabb(state.context, index, 2, 18, 12)
        end
        state.player_fsm = state.new_player_fsm(PLAYER, {
            on_state_changed = function(next_state)
                state.status_text = next_state == "Grabbed" and "Enemy grabbed" or ""
            end,
        })
        state.camera_manager:set_player(PLAYER)
        for _, index in ipairs(ENEMIES) do
            local enemy = state.new_enemy_ai(index, PLAYER, { attack_distance = 76 })
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
        state.zig.engine_set_25d_position(state.context, PLAYER, math.max(48, math.min(900, player_x + horizontal * 190 * dt)), math.max(-80, math.min(80, player_z + depth * 130 * dt)), state.positions_y[PLAYER])
    end

    state.player_fsm:update(dt)
    for _, enemy in ipairs(game.enemies) do enemy:update(dt) end
end

function StreetsOfRage.draw(state)
    local game = state.streets_of_rage
    love.graphics.clear(0.06, 0.07, 0.11, 1)
    love.graphics.setColor(0.10, 0.12, 0.18, 1)
    love.graphics.rectangle("fill", 0, 230, WIDTH, 220)
    love.graphics.setColor(0.18, 0.16, 0.17, 1)
    love.graphics.rectangle("fill", 0, 450, WIDTH, 150)
    love.graphics.setColor(0.40, 0.34, 0.28, 1)
    love.graphics.rectangle("fill", 0, FLOOR_Y + 36, WIDTH, 4)
    for x = 0, WIDTH, 90 do
        love.graphics.setColor(0.20, 0.22, 0.28, 1)
        love.graphics.rectangle("fill", x, 300 + (x % 3) * 18, 56, 74)
        love.graphics.setColor(0.72, 0.52, 0.24, 0.45)
        love.graphics.rectangle("fill", x + 12, 316 + (x % 3) * 18, 10, 18)
    end

    local player_x, player_z = state.positions_x[PLAYER], state.positions_z[PLAYER]
    local player_frames = state.player_fsm:get_state() == "Idle" and game.frames.player_walk or game.frames.player
    draw_actor(PLAYER, player_frames, player_x, player_z, state.player_fsm.facing, game.elapsed, { 0.86, 0.18, 0.27 })
    for _, enemy in ipairs(game.enemies) do
        local index = enemy.owner
        local enemy_frames = enemy:get_state() == "Approach" and game.frames.enemy_walk or game.frames.enemy
        draw_actor(enemy, enemy_frames, state.positions_x[index], state.positions_z[index], enemy.facing, game.elapsed, { 0.66, 0.18, 0.14 })
    end

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("NIGHT SHIFT", 24, 20)
    love.graphics.print("A/D: move   W/S: depth   J/Z: attack   Close range: grab   K/Q: throw", 24, 44)
    love.graphics.print("State: " .. state.player_fsm:get_state(), 24, 70)
    if state.camera_manager:get_prompt() then
        love.graphics.setColor(1, 0.78, 0.22, 1)
        love.graphics.printf(state.camera_manager:get_prompt(), 0, 112, WIDTH, "center")
    end
end

return StreetsOfRage
