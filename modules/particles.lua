---@diagnostic disable: undefined-global
local Particles = {}
Particles.__index = Particles

function Particles.new(state)
    local zig = state.zig
    return setmetatable({
        state = state,
        zig = zig,
        x = zig.engine_particle_positions_x(state.context),
        y = zig.engine_particle_positions_y(state.context),
        size = zig.engine_particle_sizes(state.context),
        red = zig.engine_particle_red(state.context),
        green = zig.engine_particle_green(state.context),
        blue = zig.engine_particle_blue(state.context),
        alpha = zig.engine_particle_alpha(state.context),
        alive = zig.engine_particle_alive(state.context),
    }, Particles)
end

function Particles:emit(x, y, velocity_x, velocity_y, lifetime, size, color)
    color = color or { 1, 1, 1 }
    return self.zig.engine_particle_spawn(self.state.context, x, y, velocity_x, velocity_y, lifetime, size, color[1], color[2], color[3])
end

function Particles:draw()
    for index = 0, 4095 do
        if self.alive[index] then
            love.graphics.setColor(self.red[index], self.green[index], self.blue[index], self.alpha[index])
            love.graphics.circle("fill", self.x[index], self.y[index], self.size[index])
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

return Particles
