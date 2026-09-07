---@diagnostic disable: undefined-global
local EnemyAI = {}
EnemyAI.__index = EnemyAI

local STATE_APPROACH = "Approach"
local STATE_FLANK = "Flank"
local STATE_ATTACK = "Attack"
local Slots = {}
Slots.__index = Slots

local function move_toward(value, target, amount)
    if math.abs(target - value) <= amount then return target end
    return value + (target > value and amount or -amount)
end

local function sign(value)
    return value < 0 and -1 or 1
end

function EnemyAI.Slots(max_attackers)
    return setmetatable({
        max_attackers = max_attackers or 2,
        active = {},
    }, Slots)
end

function Slots:count()
    local count = 0
    for _ in pairs(self.active) do count = count + 1 end
    return count
end

function Slots:claim(owner)
    if self.active[owner] then return true end
    if self:count() >= self.max_attackers then return false end
    self.active[owner] = true
    return true
end

function Slots:release(owner)
    self.active[owner] = nil
end

function Slots:is_active(owner)
    return self.active[owner] == true
end

function EnemyAI.new(options)
    assert(options and options.runtime and options.combat and options.owner and options.player, "enemy AI requires runtime, combat, owner, and player")
    local self = setmetatable({
        runtime = options.runtime,
        combat = options.combat,
        owner = options.owner,
        player = options.player,
        slots = options.slots or EnemyAI.Slots(2),
        state = STATE_APPROACH,
        state_time = 0,
        facing = 1,
        speed = options.speed or 82,
        attack_distance = options.attack_distance or 72,
        depth_tolerance = options.depth_tolerance or 10,
        flank_offset = options.flank_offset or 42,
        hurtbox = options.hurtbox or { x = 0, y = 36, z = 0, width = 30, height = 72, depth = 24 },
        attack_data = options.attack_data or options.combat.attack_data.light_1,
        callbacks = options.callbacks or {},
    }, EnemyAI)
    return self
end

function EnemyAI:change_state(next_state)
    if self.state == next_state then return end
    if self.state == STATE_ATTACK then self.slots:release(self.owner) end
    self.state = next_state
    self.state_time = 0
    if self.callbacks.on_state_changed then self.callbacks.on_state_changed(next_state, self.owner) end
end

function EnemyAI:target_position()
    return self.runtime.positions_x[self.player], self.runtime.positions_z[self.player]
end

function EnemyAI:position()
    return self.runtime.positions_x[self.owner], self.runtime.positions_z[self.owner]
end

function EnemyAI:move(dx, dz, dt)
    local runtime = self.runtime
    local x, z = self:position()
    if math.abs(dx) > 0.01 then self.facing = sign(dx) end
    runtime.zig.engine_set_25d_position(runtime.context, self.owner, x + dx * self.speed * dt, z + dz * self.speed * dt, runtime.positions_y[self.owner])
end

function EnemyAI:register_hurtbox()
    self.combat:register_hurtbox(self.owner, self.hurtbox)
end

function EnemyAI:register_attack()
    self.combat:set_facing(self.owner, self.facing)
    self.combat:register_attack_hitboxes(self.owner)
end

function EnemyAI:try_attack()
    if not self.slots:claim(self.owner) then
        self:change_state(STATE_FLANK)
        return false
    end
    self.combat:begin_attack(self.owner, self.attack_data)
    self.combat:set_facing(self.owner, self.facing)
    self:change_state(STATE_ATTACK)
    self:register_attack()
    return true
end

function EnemyAI:update(dt)
    if self.runtime.hit_stop_remaining > 0 then
        self:register_hurtbox()
        return
    end
    self.state_time = self.state_time + dt
    local player_x, player_z = self:target_position()
    local enemy_x, enemy_z = self:position()
    local horizontal_distance = player_x - enemy_x
    local depth_distance = player_z - enemy_z
    local desired_z = player_z + (self.owner % 2 == 0 and self.flank_offset or -self.flank_offset)

    if self.state == STATE_APPROACH then
        if math.abs(depth_distance) > self.depth_tolerance then
            self:move(0, sign(depth_distance), dt)
        elseif math.abs(horizontal_distance) > self.attack_distance then
            self:move(sign(horizontal_distance), 0, dt)
        elseif not self:try_attack() then
            self:change_state(STATE_FLANK)
        end
    elseif self.state == STATE_FLANK then
        if math.abs(enemy_z - desired_z) > self.depth_tolerance then
            self:move(0, sign(desired_z - enemy_z), dt)
        elseif math.abs(horizontal_distance) > self.attack_distance then
            self:move(sign(horizontal_distance), 0, dt)
        elseif not self:try_attack() then
            -- Hold just outside the player's reach until an attack slot opens.
            local hold_x = player_x - sign(horizontal_distance == 0 and self.facing or horizontal_distance) * (self.attack_distance + 28)
            if math.abs(hold_x - enemy_x) > 4 then self:move(sign(hold_x - enemy_x), 0, dt) end
        end
    elseif self.state == STATE_ATTACK then
        if not self.combat:is_attacking(self.owner) then
            self.slots:release(self.owner)
            self:change_state(STATE_APPROACH)
        else
            self:register_attack()
        end
    end
    self:register_hurtbox()
end

function EnemyAI:get_state()
    return self.state
end

return EnemyAI