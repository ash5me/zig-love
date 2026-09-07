---@diagnostic disable: undefined-global
local CameraManager = {}
CameraManager.__index = CameraManager

function CameraManager.new(runtime, options)
    options = options or {}
    local camera = runtime.camera_state
    local self = setmetatable({
        runtime = runtime,
        x = tonumber(camera.x) or 0,
        left_wall = options.left_wall or 0,
        follow_offset = options.follow_offset or 180,
        smooth_speed = options.smooth_speed or 7,
        player = options.player,
        triggers = {},
        active_trigger = nil,
        wave = {},
        camera_locked = false,
        prompt = nil,
        previous_player_x = nil,
        on_prompt = options.on_prompt,
    }, CameraManager)
    return self
end

function CameraManager:set_player(entity)
    self.player = entity
    self.previous_player_x = nil
end

function CameraManager:add_trigger(trigger)
    assert(trigger and trigger.x and trigger.width and type(trigger.spawn) == "function", "arena trigger requires x, width, and spawn")
    trigger.triggered = false
    self.triggers[#self.triggers + 1] = trigger
    return trigger
end

function CameraManager:is_alive(entity)
    return self.runtime.zig.engine_entity_alive(self.runtime.context, entity)
end

function CameraManager:start_wave(trigger)
    self.active_trigger = trigger
    self.camera_locked = true
    self.prompt = nil
    self.wave = trigger.spawn(self, trigger) or {}
    trigger.triggered = true
    self.runtime.status_text = trigger.message or "Defeat the wave"
end

function CameraManager:check_trigger(player_x)
    local previous_x = self.previous_player_x or player_x
    for _, trigger in ipairs(self.triggers) do
        if not trigger.triggered and previous_x < trigger.x and player_x >= trigger.x then
            self:start_wave(trigger)
            break
        end
    end
end

function CameraManager:wave_cleared()
    if not self.active_trigger then return false end
    for _, entity in ipairs(self.wave) do
        if self:is_alive(entity) then return false end
    end
    return true
end

function CameraManager:finish_wave()
    self.camera_locked = false
    self.prompt = "GO!"
    self.runtime.status_text = self.prompt
    if self.on_prompt then self.on_prompt(self.prompt, self.active_trigger) end
    if self.active_trigger and self.active_trigger.on_cleared then
        self.active_trigger.on_cleared(self.active_trigger)
    end
    self.active_trigger = nil
    self.wave = {}
end

function CameraManager:update(dt)
    if not self.player then return end
    local runtime = self.runtime
    local player_x = tonumber(runtime.positions_x[self.player])
    if not player_x then return end
    self:check_trigger(player_x)
    if self.active_trigger and self:wave_cleared() then self:finish_wave() end

    local target_x = math.max(self.left_wall, player_x + self.follow_offset)
    if self.camera_locked then
        target_x = self.x
    elseif target_x > self.x then
        local blend = 1 - math.exp(-self.smooth_speed * dt)
        self.x = self.x + (target_x - self.x) * blend
    end
    self.x = math.max(self.left_wall, self.x)
    runtime.camera_state.x = self.x
    runtime.zig.engine_camera_set(runtime.context, runtime.camera_state)
    self.previous_player_x = player_x
end

function CameraManager:is_locked()
    return self.camera_locked
end

function CameraManager:get_prompt()
    return self.prompt
end

return CameraManager