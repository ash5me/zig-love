---@diagnostic disable: undefined-global, undefined-field
local SpriteBatch = {}
SpriteBatch.__index = SpriteBatch

local function create_dot_image()
    local image_data = love.image.newImageData(16, 16)
    for y = 0, 15 do
        for x = 0, 15 do
            local dx, dy = x - 7.5, y - 7.5
            local distance = math.sqrt(dx * dx + dy * dy)
            local alpha = math.max(0, math.min(1, 7.5 - distance))
            image_data:setPixel(x, y, 1, 1, 1, alpha)
        end
    end
    local image = love.graphics.newImage(image_data)
    image:setFilter("nearest", "nearest")
    return image
end

function SpriteBatch.new(capacity)
    capacity = tonumber(capacity)
    assert(capacity and capacity > 0, "SpriteBatch capacity must be a positive number")
    local image = create_dot_image()
    local batch = love.graphics.newSpriteBatch(image, capacity, "stream")
    return setmetatable({
        image = image,
        batch = batch,
        capacity = capacity,
    }, SpriteBatch)
end

function SpriteBatch:draw_entities(state)
    local render_count = tonumber(state.zig.engine_render_count(state.context)) or 0
    self.batch:clear()
    for order_index = 0, render_count - 1 do
        local entity_index = tonumber(state.render_order[order_index])
        if entity_index ~= nil then
            local x = tonumber(state.positions_x[entity_index]) or 0
            local y = tonumber(state.positions_y[entity_index]) or 0
            self.batch:add(x - 8, y - 8)
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(self.batch)
end

function SpriteBatch:release()
    if self.batch then self.batch:release() end
    if self.image then self.image:release() end
    self.batch = nil
    self.image = nil
end

return SpriteBatch
