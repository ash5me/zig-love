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
    love.graphics.print("Zig SoA + pooled ECS + spatial grid", 10, 10)
    love.graphics.print(state.status_text, 10, 28)
    for index = 0, 9 do
        love.graphics.circle("fill", state.positions_x[index], state.positions_y[index], 4)
    end
end

return logic
