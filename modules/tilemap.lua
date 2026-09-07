---@diagnostic disable: undefined-global, undefined-field
local Tilemap = {}
Tilemap.__index = Tilemap

function Tilemap.load(state, path, tileset_path)
    local data = assert(state.assets:load_json(path), "Tilemap JSON could not be loaded: " .. path)
    assert(data.orientation == nil or data.orientation == "orthogonal", "Only orthogonal Tiled maps are supported")
    assert(data.width and data.height and data.tilewidth and data.tileheight, "Tilemap dimensions are missing")
    local map = setmetatable({
        state = state,
        width = data.width,
        height = data.height,
        tile_width = data.tilewidth,
        tile_height = data.tileheight,
        layers = {},
        image = tileset_path and state.assets:load_image(tileset_path) or nil,
        columns = 0,
        tileset_tile_width = data.tilewidth,
        tileset_tile_height = data.tileheight,
    }, Tilemap)
    assert(state.zig.engine_tilemap_create(state.context, map.width, map.height, map.tile_width, map.tile_height), "Native tilemap capacity exceeded")
    for _, layer in ipairs(data.layers or {}) do
        if layer.type == "tilelayer" and layer.data then
            local tiles = {}
            for index, gid in ipairs(layer.data) do
                tiles[index] = gid or 0
                local x = (index - 1) % map.width
                local y = math.floor((index - 1) / map.width)
                assert(state.zig.engine_tilemap_set_tile(state.context, x, y, gid or 0), "Native tilemap upload failed")
            end
            map.layers[#map.layers + 1] = { tiles = tiles, opacity = layer.opacity or 1, offset_x = layer.offsetx or 0, offset_y = layer.offsety or 0 }
        end
    end
    if map.image then
        map.columns = math.floor(map.image:getWidth() / map.tileset_tile_width)
    end
    return map
end

function Tilemap:draw()
    for _, layer in ipairs(self.layers) do
        love.graphics.setColor(1, 1, 1, layer.opacity)
        for index, gid in ipairs(layer.tiles) do
            if gid > 0 then
                local x = (index - 1) % self.width
                local y = math.floor((index - 1) / self.width)
                local draw_x = x * self.tile_width + layer.offset_x
                local draw_y = y * self.tile_height + layer.offset_y
                if self.image and self.columns > 0 then
                    local tile = gid - 1
                    local quad = love.graphics.newQuad((tile % self.columns) * self.tileset_tile_width, math.floor(tile / self.columns) * self.tileset_tile_height, self.tileset_tile_width, self.tileset_tile_height, self.image)
                    love.graphics.draw(self.image, quad, draw_x, draw_y)
                else
                    love.graphics.rectangle("fill", draw_x, draw_y, self.tile_width, self.tile_height)
                end
            end
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

return Tilemap
