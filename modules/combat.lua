---@diagnostic disable: undefined-global
local Combat = {}
Combat.__index = Combat

-- Attack data is intentionally declarative: each move can contain multiple active windows.
Combat.attacks = {
    light = {
        frame_duration = 1 / 12,
        total_frames = 8,
        hit_stop = 0.08,
        windows = {
            { start_frame = 3, end_frame = 4, hitboxes = {
                { x = 34, y = 34, z = 0, width = 54, height = 34, depth = 28, damage = 1, knockback = { x = 95, y = 0, z = 18 } },
            } },
        },
    },
}

local function active_window(attack, frame)
    for _, window in ipairs(attack.windows or {}) do
        if frame >= window.start_frame and frame <= window.end_frame then return window end
    end
    return nil
end

function Combat.new(runtime)
    return setmetatable({
        runtime = runtime,
        attacks = {},
        hurtboxes = {},
        callbacks = {},
        frame = 0,
    }, Combat)
end

function Combat:on_hit(callback)
    assert(type(callback) == "function", "combat hit callback must be a function")
    self.callbacks[#self.callbacks + 1] = callback
end

function Combat:begin_frame(dt)
    local runtime = self.runtime
    runtime.zig.engine_combat_clear(runtime.context)
    self.hurtboxes = {}
    self.frame = self.frame + 1
    for owner, attack_state in pairs(self.attacks) do
        attack_state.elapsed = attack_state.elapsed + dt
        attack_state.frame = math.floor(attack_state.elapsed / attack_state.attack.frame_duration) + 1
        if attack_state.frame > attack_state.attack.total_frames then self.attacks[owner] = nil end
    end
end

function Combat:begin_attack(owner, attack)
    assert(type(owner) == "number", "combat owner must be an entity index")
    assert(type(attack) == "table" and attack.frame_duration and attack.total_frames, "invalid attack data")
    self.attacks[owner] = { attack = attack, elapsed = 0, frame = 1 }
end

function Combat:register_hurtbox(owner, box)
    assert(box and box.width and box.height and box.depth, "hurtbox requires width, height, and depth")
    local runtime = self.runtime
    local x = runtime.positions_x[owner] + (box.x or 0)
    local y = runtime.positions_y[owner] + (box.y or 0)
    local z = runtime.positions_z[owner] + (box.z or 0)
    runtime.zig.engine_combat_register_hurtbox(runtime.context, owner, x, y, z, box.width, box.height, box.depth)
    self.hurtboxes[#self.hurtboxes + 1] = { owner = owner, box = box }
end

function Combat:register_attack_hitboxes(owner)
    local state = self.attacks[owner]
    if not state then return end
    local window = active_window(state.attack, state.frame)
    if not window then return end
    local runtime = self.runtime
    for _, box in ipairs(window.hitboxes or {}) do
        local x = runtime.positions_x[owner] + (box.x or 0) * (state.facing or 1)
        local y = runtime.positions_y[owner] + (box.y or 0)
        local z = runtime.positions_z[owner] + (box.z or 0)
        local knockback = box.knockback or {}
        runtime.zig.engine_combat_register_hitbox(runtime.context, owner, x, y, z, box.width, box.height, box.depth, box.damage or 0, (knockback.x or 0) * (state.facing or 1), knockback.y or 0, knockback.z or 0, box.hit_stop or state.attack.hit_stop or 0)
    end
end

function Combat:set_facing(owner, facing)
    if self.attacks[owner] then self.attacks[owner].facing = facing < 0 and -1 or 1 end
end

function Combat:resolve()
    local runtime = self.runtime
    runtime.zig.engine_combat_resolve(runtime.context)
    local event = runtime.combat_event
    while runtime.zig.engine_next_combat_hit(runtime.context, event) do
        local hit = {
            attacker = tonumber(event.attacker), victim = tonumber(event.victim), damage = tonumber(event.damage),
            knockback = { x = tonumber(event.knockback_x), y = tonumber(event.knockback_y), z = tonumber(event.knockback_z) },
            hit_stop = tonumber(event.hit_stop),
        }
        runtime.hit_stop_remaining = math.max(runtime.hit_stop_remaining or 0, hit.hit_stop)
        for _, callback in ipairs(self.callbacks) do callback(hit) end
    end
end

return Combat