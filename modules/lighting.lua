---@diagnostic disable: undefined-global
local Lighting = {}
Lighting.__index = Lighting

function Lighting.new(state)
    local zig = state.zig
    return setmetatable({
        state = state,
        zig = zig,
        x = zig.engine_light_positions_x(state.context),
        y = zig.engine_light_positions_y(state.context),
        radius = zig.engine_light_radii(state.context),
        red = zig.engine_light_red(state.context),
        green = zig.engine_light_green(state.context),
        blue = zig.engine_light_blue(state.context),
        intensity = zig.engine_light_intensity(state.context),
        alive = zig.engine_light_alive(state.context),
        occluders = {},
    }, Lighting)
end

function Lighting:add_occluder(x, y, width, height)
    self.occluders[#self.occluders + 1] = { x = x, y = y, width = width, height = height }
end

function Lighting:draw_shadows()
    for index = 0, 127 do
        if self.alive[index] then
            local light_x, light_y = self.x[index], self.y[index]
            for _, box in ipairs(self.occluders) do
                local corners = {
                    { box.x, box.y }, { box.x + box.width, box.y },
                    { box.x + box.width, box.y + box.height }, { box.x, box.y + box.height },
                }
                local far = {}
                for corner = 1, 4 do
                    local dx, dy = corners[corner][1] - light_x, corners[corner][2] - light_y
                    local length = math.max(0.001, math.sqrt(dx * dx + dy * dy))
                    far[corner] = { corners[corner][1] + dx / length * self.radius[index], corners[corner][2] + dy / length * self.radius[index] }
                end
                love.graphics.setColor(0, 0, 0, 0.32)
                love.graphics.polygon("fill", corners[1][1], corners[1][2], corners[2][1], corners[2][2], far[2][1], far[2][2], far[1][1], far[1][2])
                love.graphics.polygon("fill", corners[3][1], corners[3][2], corners[4][1], corners[4][2], far[4][1], far[4][2], far[3][1], far[3][2])
            end
        end
    end
end

function Lighting:draw()
    love.graphics.setBlendMode("add")
    for index = 0, 127 do
        if self.alive[index] then
            local radius = self.radius[index]
            love.graphics.setColor(self.red[index], self.green[index], self.blue[index], self.intensity[index] * 0.18)
            love.graphics.circle("fill", self.x[index], self.y[index], radius)
            love.graphics.setColor(self.red[index], self.green[index], self.blue[index], self.intensity[index] * 0.28)
            love.graphics.circle("fill", self.x[index], self.y[index], radius * 0.55)
        end
    end
    love.graphics.setBlendMode("alpha")
    love.graphics.setColor(1, 1, 1, 1)
end

return Lighting
