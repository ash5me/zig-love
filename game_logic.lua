---@diagnostic disable: undefined-global
local logic = {}

function logic.update(state)
    if state.path_status == 0 or state.path_status == state.path_working then
        state.path_status = state.zig.engine_pathfind_step(state.context, 32)
    end

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

function logic.draw(state)
    local draw_start = love.timer.getTime()
    local matrix = state.camera_matrix
    state.camera_transform:setMatrix(
        matrix[0], matrix[3], 0, matrix[2],
        matrix[1], matrix[4], 0, matrix[5],
        0, 0, 1, 0,
        0, 0, 0, matrix[8]
    )
    love.graphics.push("all")
    love.graphics.applyTransform(state.camera_transform)
    for order_index = 0, 9 do
        local index = state.render_order[order_index]
        love.graphics.circle("fill", state.positions_x[index], state.positions_y[index], 4)
    end
    love.graphics.pop()
    state.draw_us = math.floor((love.timer.getTime() - draw_start) * 1000000)
    love.graphics.print("Zig SoA + pooled ECS + spatial grid", 10, 10)
    love.graphics.print(state.status_text, 10, 28)
end

return logic
