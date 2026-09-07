---@diagnostic disable: undefined-global
local GrabSystem = {}
GrabSystem.__index = GrabSystem

function GrabSystem.new(runtime, combat, options)
    options = options or {}
    return setmetatable({
        runtime = runtime,
        combat = combat,
        enemies = {},
        range_x = options.range_x or 42,
        range_z = options.range_z or 24,
    }, GrabSystem)
end

function GrabSystem:add_enemy(enemy)
    self.enemies[#self.enemies + 1] = enemy
end

function GrabSystem:remove_enemy(enemy)
    for index, candidate in ipairs(self.enemies) do
        if candidate == enemy then
            table.remove(self.enemies, index)
            return
        end
    end
end

function GrabSystem:try_grab(player)
    if player.state ~= "Idle" then return false end
    local runtime = self.runtime
    local player_x = runtime.positions_x[player.owner]
    local player_z = runtime.positions_z[player.owner]
    for _, enemy in ipairs(self.enemies) do
        if enemy:is_neutral() then
            local close_x = math.abs(runtime.positions_x[enemy.owner] - player_x) <= self.range_x
            local close_z = math.abs(runtime.positions_z[enemy.owner] - player_z) <= self.range_z
            if close_x and close_z then
                player:begin_grab(enemy)
                return true
            end
        end
    end
    return false
end

return GrabSystem