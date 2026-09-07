---@diagnostic disable: undefined-global
local logic = {}

function logic.update(state)
    if state.path_status == 0 or state.path_status == state.path_working then
        state.path_status = state.zig.engine_pathfind_step(state.context, 32)
    end

    if state.events then
        state.events:poll()
    else
        while state.zig.engine_next_event(state.context, state.event) do
            if state.event.id == state.event_play_sound then
                state.status_text = "Play sound event"
            elseif state.event.id == state.event_player_died then
                state.status_text = "Player died event"
            elseif state.event.id == state.event_path_ready then
                state.status_text = "Path ready: " .. tostring(state.zig.engine_pathfind_length(state.context)) .. " nodes"
            end
        end
    end
end

function logic.draw(state)
    local draw_start = love.timer.getTime()
    local width, height = love.graphics.getDimensions()
    love.graphics.clear(0.08, 0.12, 0.20, 1)
    love.graphics.setColor(0.18, 0.45, 0.82, 1)
    love.graphics.rectangle("fill", 0, 0, width, height)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("Engine booting...", 20, 18)

    if state and state.camera_matrix then
        local matrix = state.camera_matrix
        local ok = pcall(function()
            state.camera_transform:setMatrix(
                matrix[0], matrix[1],
                matrix[3], matrix[4],
                matrix[2], matrix[5]
            )
        end)
        if ok then
            love.graphics.push("all")
            love.graphics.applyTransform(state.camera_transform)
            if state.sprite_batch then
                state.sprite_batch:draw_entities(state)
            end
            love.graphics.pop()
        end
    end

    state.draw_us = math.floor((love.timer.getTime() - draw_start) * 1000000)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("Zig SoA + pooled ECS + spatial grid", 10, 40)
    love.graphics.print(state.status_text, 10, 58)
end

return logic
