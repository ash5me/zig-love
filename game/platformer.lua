---@diagnostic disable: undefined-global
local platformer = {}

local levels = {
    {
        name = "Greenway",
        sky = { 0.10, 0.25, 0.34 },
        start = { 48, 420 },
        goal = { 860, 120 },
        platforms = {
            { 0, 470, 960, 50 }, { 120, 380, 150, 20 },
            { 340, 310, 150, 20 }, { 570, 240, 150, 20 }, { 790, 170, 130, 20 },
        },
    },
    {
        name = "Copper Steps",
        sky = { 0.30, 0.18, 0.12 },
        start = { 42, 420 },
        goal = { 870, 100 },
        platforms = {
            { 0, 470, 960, 50 }, { 90, 400, 120, 20 }, { 270, 330, 120, 20 },
            { 450, 260, 120, 20 }, { 630, 190, 120, 20 }, { 810, 130, 110, 20 },
        },
    },
    {
        name = "Moonlit Ruins",
        sky = { 0.08, 0.10, 0.24 },
        start = { 42, 420 },
        goal = { 870, 110 },
        platforms = {
            { 0, 470, 960, 50 }, { 70, 390, 110, 20 }, { 250, 440, 100, 20 },
            { 390, 330, 110, 20 }, { 560, 400, 100, 20 }, { 700, 250, 110, 20 },
            { 840, 160, 100, 20 },
        },
    },
}

local player = { index = 0, x = 0, y = 0, width = 24, height = 32, vx = 0, vy = 0, grounded = false }
local jump_speed = -540
local landing_tolerance = 8

local function level(state)
    return levels[state.level_index]
end

local function reset(state)
    local current = level(state)
    player.x, player.y = current.start[1], current.start[2]
    player.vx, player.vy, player.grounded = 0, 0, false
    state.zig.engine_set_body(state.context, player.index, 2, 1, 12, 0)
    state.zig.engine_set_position(state.context, player.index, player.x, player.y)
    state.zig.engine_set_velocity(state.context, player.index, 0, 0)
    state.status_text = "Reach the gold beacon"
end

local function horizontal_overlap(left, right, platform)
    return right > platform[1] and left < platform[1] + platform[3]
end

function platformer.update(state, dt)
    if not state.platformer_ready then
        state.level_index = 1
        state.platformer_ready = true
        reset(state)
    end

    if love.keyboard.isDown("r") then reset(state) end
    local current = level(state)
    local direction = 0
    if love.keyboard.isDown("left") or love.keyboard.isDown("a") then direction = direction - 1 end
    if love.keyboard.isDown("right") or love.keyboard.isDown("d") then direction = direction + 1 end
    player.vx = direction * 190
    if (love.keyboard.isDown("space") or love.keyboard.isDown("up") or love.keyboard.isDown("w")) and player.grounded then
        player.vy, player.grounded = jump_speed, false
    end

    local previous_bottom = player.y + player.height
    player.vy = math.min(player.vy + 980 * dt, 620)
    player.x = math.max(0, math.min(936, player.x + player.vx * dt))
    player.y = player.y + player.vy * dt
    player.grounded = false
    local left, right = player.x, player.x + player.width
    local bottom = player.y + player.height
    for _, platform in ipairs(current.platforms) do
        local crossed_top = previous_bottom <= platform[2] + landing_tolerance and bottom >= platform[2]
        if player.vy >= 0 and crossed_top and horizontal_overlap(left, right, platform) then
            player.y, player.vy, player.grounded = platform[2] - player.height, 0, true
            bottom = player.y + player.height
        end
    end
    if player.y > 560 then reset(state) end

    local goal = current.goal
    if player.x + player.width > goal[1] - 18 and player.x < goal[1] + 18 and player.y < goal[2] + 34 and bottom > goal[2] - 34 then
        if state.level_index < #levels then
            state.level_index = state.level_index + 1
            reset(state)
            state.status_text = "Level " .. tostring(state.level_index) .. ": " .. level(state).name
        else
            state.status_text = "All three levels complete! Press R to replay"
        end
    end
    state.zig.engine_set_position(state.context, player.index, player.x, player.y)
    state.zig.engine_set_velocity(state.context, player.index, player.vx, player.vy)
end

function platformer.draw(state)
    local started = love.timer.getTime()
    local current = level(state)
    love.graphics.clear(current.sky[1], current.sky[2], current.sky[3], 1)
    love.graphics.setColor(1, 1, 1, 0.08)
    for x = 40, 960, 120 do love.graphics.circle("fill", x, 90 + (x % 4) * 18, 2) end

    for index, platform in ipairs(current.platforms) do
        local color = index == 1 and { 0.18, 0.24, 0.28 } or { 0.25, 0.47, 0.38 }
        love.graphics.setColor(color[1], color[2], color[3], 1)
        love.graphics.rectangle("fill", platform[1], platform[2], platform[3], platform[4], 4, 4)
        love.graphics.setColor(0.55, 0.78, 0.58, 1)
        love.graphics.rectangle("fill", platform[1], platform[2], platform[3], 4, 2, 2)
    end

    local goal = current.goal
    love.graphics.setColor(0.95, 0.72, 0.18, 1)
    love.graphics.rectangle("fill", goal[1] - 4, goal[2] - 30, 8, 60)
    love.graphics.circle("fill", goal[1], goal[2] - 32, 13)
    love.graphics.setColor(0.95, 0.35, 0.28, 1)
    love.graphics.rectangle("fill", player.x, player.y, player.width, player.height, 5, 5)
    love.graphics.setColor(1, 0.84, 0.55, 1)
    love.graphics.rectangle("fill", player.x + 5, player.y + 6, 5, 5, 2, 2)
    love.graphics.rectangle("fill", player.x + 15, player.y + 6, 5, 5, 2, 2)

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("LEVEL " .. tostring(state.level_index) .. " / 3  " .. current.name, 20, 18)
    love.graphics.print("A/D or arrows: move    Space/W/Up: jump    R: restart", 20, 40)
    love.graphics.print(state.status_text or "", 20, 62)
    state.draw_us = math.floor((love.timer.getTime() - started) * 1000000)
end

return platformer
