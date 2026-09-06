---@diagnostic disable: undefined-global
local json = nil

local AssetManager = {}
AssetManager.__index = AssetManager

local function normalize_path(path)
    return (path:gsub("\\", "/"):gsub("^/", ""))
end

local function asset_key(kind, path)
    return kind .. ":" .. normalize_path(path)
end

local function modification_token(path)
    local info = love.filesystem.getInfo(path)
    if not info then return nil end
    return string.format("%s:%s:%s", tostring(info.modtime or 0), tostring(info.size or 0), tostring(info.type or ""))
end

function AssetManager.new()
    return setmetatable({
        cache = {},
        errors = {},
    }, AssetManager)
end

function AssetManager:_load(kind, path, loader)
    path = normalize_path(path)
    local key = asset_key(kind, path)
    local entry = self.cache[key]
    local token = modification_token(path)
    if entry and entry.token == token then return entry.value end
    if not token then
        self.errors[key] = "Asset not found: " .. path
        return nil
    end

    local ok, value = pcall(loader, path)
    if not ok then
        self.errors[key] = tostring(value)
        return nil
    end
    self.errors[key] = nil
    self.cache[key] = { kind = kind, path = path, token = token, value = value }
    return value
end

function AssetManager:load_image(path)
    return self:_load("image", path, love.graphics.newImage)
end

function AssetManager:load_sound(path, source_type)
    source_type = source_type or "static"
    return self:_load("sound:" .. source_type, path, function(asset_path)
        return love.audio.newSource(asset_path, source_type)
    end)
end

function AssetManager:load_text(path)
    return self:_load("text", path, function(asset_path)
        return love.filesystem.read(asset_path)
    end)
end

function AssetManager:load_lua(path)
    return self:_load("lua", path, function(asset_path)
        local chunk, error_message = love.filesystem.load(asset_path)
        assert(chunk, error_message)
        return chunk()
    end)
end

function AssetManager:load_json(path)
    if not json then
        json = require("modules.json")
    end
    local text = self:load_text(path)
    if not text then return nil end
    local ok, value = pcall(json.decode, text)
    if not ok then
        self.errors[asset_key("json", path)] = tostring(value)
        return nil
    end
    self.cache[asset_key("json", path)] = {
        kind = "json",
        path = normalize_path(path),
        token = modification_token(path),
        value = value,
    }
    return value
end

function AssetManager:reload(path)
    path = normalize_path(path)
    local reloaded = 0
    for key, entry in pairs(self.cache) do
        if entry.path == path then
            self.cache[key] = nil
            reloaded = reloaded + 1
        end
    end
    return reloaded
end

function AssetManager:reload_all()
    local reloaded = 0
    for key, entry in pairs(self.cache) do
        local token = modification_token(entry.path)
        if token ~= entry.token then
            self.cache[key] = nil
            reloaded = reloaded + 1
        end
    end
    return reloaded
end

function AssetManager:clear()
    for key, entry in pairs(self.cache) do
        if entry.value and type(entry.value.release) == "function" then
            pcall(entry.value.release, entry.value)
        end
        self.cache[key] = nil
    end
    self.errors = {}
end

function AssetManager:get_error(kind, path)
    return self.errors[asset_key(kind, path)]
end

return AssetManager
