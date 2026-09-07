---@diagnostic disable: undefined-global
local EnemyAI = {}
EnemyAI.__index = EnemyAI

local STATE_APPROACH = "Approach"
local STATE_FLANK = "Flank"
local STATE_ATTACK = "Attack"
local STATE_GRABBED = "Grabbed"
local STATE_PROJECTILE = "Projectile"
local STATE_HITSTUN = "Hitstun"
local STATE_KNOCKDOWN = "Knockdown"
local Slots = {}
Slots.__index = Slots

local function move_toward(value, target, amount)
    if math.abs(target - value) <= amount then return target end
    return value + (target > value and amount or -amount)
end

local function sign(value)
    return value < 0 and -1 or 1
end

local function approach(value, target, amount)
    if value < target then return math.min(value + amount, target) end
    return math.max(value - amount, target)
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
        grabbed_by = nil,
        projectile_vx = 0,
        projectile_vz = 0,
        velocity_x = 0,
        velocity_z = 0,
        acceleration = options.acceleration or 700,
        friction = options.friction or 900,
    }, EnemyAI)
    self.combat:on_hit(function(hit) self:on_hit(hit) end)
    return self
end

function EnemyAI:change_state(next_state)
    if self.state == next_state then return end
    if self.state == STATE_ATTACK then self.slots:release(self.owner) end
    self.state = next_state
    self.state_time = 0
    if next_state == STATE_ATTACK or next_state == STATE_GRABBED or next_state == STATE_PROJECTILE then
        self.velocity_x, self.velocity_z = 0, 0
    end
    if self.callbacks.on_state_changed then self.callbacks.on_state_changed(next_state, self.owner) end
end

function EnemyAI:is_neutral()
    return self.state == STATE_APPROACH or self.state == STATE_FLANK
end

function EnemyAI:set_grabbed(player)
    self.slots:release(self.owner)
    self.combat.attacks[self.owner] = nil
    self.grabbed_by = player
    self:change_state(STATE_GRABBED)
end

function EnemyAI:release_grab()
    self.grabbed_by = nil
    self:change_state(STATE_APPROACH)
end

function EnemyAI:stop_motion()
    self.runtime.zig.engine_set_25d_velocity(self.runtime.context, self.owner, 0, 0, 0)
end

function EnemyAI:on_hit(hit)
    if hit.victim ~= self.owner or self.state == STATE_KNOCKDOWN then return end
    self.slots:release(self.owner)
    self.combat.attacks[self.owner] = nil
    self.state_time = 0
    self.state = math.abs(hit.knockback.y or 0) >= 50 and STATE_KNOCKDOWN or STATE_HITSTUN
    if self.callbacks.on_state_changed then self.callbacks.on_state_changed(self.state, self.owner) end
end

function EnemyAI:launch_projectile(vx, vz)
    self.grabbed_by = nil
    self.projectile_vx, self.projectile_vz = vx, vz
    self:change_state(STATE_PROJECTILE)
    self.combat:begin_attack(self.owner, self.combat.attack_data.throw_projectile)
    self.combat:set_facing(self.owner, vx < 0 and -1 or 1)
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
    local target_x, target_z = dx * self.speed, dz * self.speed
    self.velocity_x = dx == 0 and approach(self.velocity_x, 0, self.friction * dt) or approach(self.velocity_x, target_x, self.acceleration * dt)
    self.velocity_z = dz == 0 and approach(self.velocity_z, 0, self.friction * dt) or approach(self.velocity_z, target_z, self.acceleration * dt)
    runtime.zig.engine_set_25d_position(runtime.context, self.owner, x + self.velocity_x * dt, z + self.velocity_z * dt, runtime.positions_y[self.owner])
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
    if self.state == STATE_GRABBED then
        self.velocity_x, self.velocity_z = 0, 0
        local player = self.grabbed_by
        if player then
            local runtime = self.runtime
            runtime.zig.engine_set_25d_position(runtime.context, self.owner, runtime.positions_x[player.owner] + player.facing * 28, runtime.positions_z[player.owner], runtime.positions_y[self.owner])
        end
        self:register_hurtbox()
        return
    end
    if self.state == STATE_PROJECTILE then
        local runtime = self.runtime
        local x, z = self:position()
        runtime.zig.engine_set_25d_position(runtime.context, self.owner, x + self.projectile_vx * dt, z + self.projectile_vz * dt, runtime.positions_y[self.owner])
        if self.combat:is_attacking(self.owner) then self:register_attack() else self:change_state(STATE_APPROACH) end
        self:register_hurtbox()
        return
    end
    if self.state == STATE_HITSTUN then
        self.state_time = self.state_time + dt
        if self.state_time >= 0.28 then
            self:stop_motion()
            self:change_state(STATE_APPROACH)
        end
        self:register_hurtbox()
        return
    end
    if self.state == STATE_KNOCKDOWN then
        self.state_time = self.state_time + dt
        if self.state_time >= 1.1 then
            self:stop_motion()
            self:change_state(STATE_APPROACH)
        end
        self:register_hurtbox()
        return
    end
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