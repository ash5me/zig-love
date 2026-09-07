---@diagnostic disable: undefined-global
local PlayerFSM = {}
PlayerFSM.__index = PlayerFSM

local STATE_IDLE = "Idle"
local STATE_ATTACK_1 = "Attack1"
local STATE_ATTACK_2 = "Attack2"
local STATE_ATTACK_3 = "Attack3"
local STATE_HITSTUN = "Hitstun"
local STATE_KNOCKDOWN = "Knockdown"
local STATE_JUMP_ATTACK = "Jump Attack"
local STATE_GRABBED = "Grabbed"
local STATE_KNEE = "Knee Strike"

local attack_states = {
    [STATE_ATTACK_1] = { attack = "light_1", next = STATE_ATTACK_2, total = 10, recovery_start = 7 },
    [STATE_ATTACK_2] = { attack = "light_2", next = STATE_ATTACK_3, total = 11, recovery_start = 8 },
    [STATE_ATTACK_3] = { attack = "light_3", next = nil, total = 14, recovery_start = 10 },
    [STATE_JUMP_ATTACK] = { attack = "jump_attack", next = nil, total = 12, recovery_start = 9 },
}

function PlayerFSM.new(options)
    assert(options and options.combat and options.owner, "player FSM requires combat and owner")
    local self = setmetatable({
        combat = options.combat,
        owner = options.owner,
        input = options.input,
        state = STATE_IDLE,
        state_time = 0,
        state_frame = 0,
        facing = 1,
        buffered_attack = false,
        invulnerable = false,
        jump_attack = false,
        previous_attack = false,
        previous_jump = false,
        callbacks = options.callbacks or {},
        hurtbox = options.hurtbox or { x = 0, y = 36, z = 0, width = 30, height = 72, depth = 24 },
        grab_system = options.grab_system,
        grabbed_enemy = nil,
    }, PlayerFSM)
    self.combat:on_hit(function(hit) self:on_hit(hit) end)
    return self
end

function PlayerFSM:change_state(next_state)
    self.state = next_state
    self.state_time = 0
    self.state_frame = 0
    self.buffered_attack = false
    self.invulnerable = false
    if next_state == STATE_IDLE then self.combat.attacks[self.owner] = nil end
    local callback = self.callbacks.on_state_changed
    if callback then callback(next_state) end
end

function PlayerFSM:begin_grab(enemy)
    self.grabbed_enemy = enemy
    enemy:set_grabbed(self)
    self:change_state(STATE_GRABBED)
    if self.callbacks.on_grab then self.callbacks.on_grab(enemy.owner) end
end

function PlayerFSM:direction()
    local horizontal = 0
    local depth = 0
    if self.input and self.input:is_down("move_left") then horizontal = horizontal - 1 end
    if self.input and self.input:is_down("move_right") then horizontal = horizontal + 1 end
    if self.input and self.input:is_down("move_up") then depth = depth - 1 end
    if self.input and self.input:is_down("move_down") then depth = depth + 1 end
    if horizontal ~= 0 then self.facing = horizontal end
    return horizontal, depth
end

function PlayerFSM:release_grab()
    if self.grabbed_enemy then self.grabbed_enemy:release_grab() end
    self.grabbed_enemy = nil
end

function PlayerFSM:start_knee()
    self:change_state(STATE_KNEE)
    self.combat:begin_attack(self.owner, self.combat.attack_data.knee_attack)
    self.combat:set_facing(self.owner, self.facing)
end

function PlayerFSM:throw_grabbed(horizontal, depth)
    local enemy = self.grabbed_enemy
    if not enemy then return end
    self:release_grab()
    local direction_x = horizontal ~= 0 and horizontal or self.facing
    local direction_z = depth ~= 0 and depth or 0
    enemy:launch_projectile(direction_x * 300, direction_z * 160)
    self:change_state(STATE_IDLE)
end

function PlayerFSM:pressed(action, previous)
    local down = self.input and self.input:is_down(action) or false
    return down and not previous, down
end

function PlayerFSM:start_attack(state)
    local definition = attack_states[state]
    self:change_state(state)
    self.combat:begin_attack(self.owner, self.combat.attack_data[definition.attack])
    self.combat:set_facing(self.owner, self.facing)
end

function PlayerFSM:update(dt)
    if self.combat.runtime.hit_stop_remaining > 0 then return end
    self.state_time = self.state_time + dt
    self.state_frame = math.floor(self.state_time / (1 / 12)) + 1

    local attack_pressed, attack_down = self:pressed("attack", self.previous_attack)
    local jump_pressed, jump_down = self:pressed("jump_attack", self.previous_jump)
    self.previous_attack, self.previous_jump = attack_down, jump_down

    if self.state == STATE_IDLE then
        if self.grab_system and self.grab_system:try_grab(self) then
            self.previous_attack = attack_down
            self.previous_jump = jump_down
            self.combat:register_hurtbox(self.owner, self.hurtbox)
            return
        end
        if attack_pressed then
            self:start_attack(STATE_ATTACK_1)
        elseif jump_pressed then
            self:start_attack(STATE_JUMP_ATTACK)
        end
    elseif self.state == STATE_GRABBED then
        if attack_pressed then
            local horizontal, depth = self:direction()
            if horizontal ~= 0 or depth ~= 0 then self:throw_grabbed(horizontal, depth) else self:start_knee() end
        end
    elseif self.state == STATE_KNEE then
        if not self.combat:is_attacking(self.owner) then
            self:change_state(STATE_GRABBED)
        end
    elseif attack_states[self.state] then
        local definition = attack_states[self.state]
        local attack_frame = self.combat:attack_frame(self.owner)
        if attack_pressed and attack_frame >= definition.recovery_start and attack_frame <= definition.total then
            self.buffered_attack = true
        end
        if attack_frame > definition.total then
            if self.buffered_attack and definition.next then
                self:start_attack(definition.next)
            else
                self:change_state(STATE_IDLE)
            end
        end
    elseif self.state == STATE_HITSTUN then
        if self.state_time >= 0.28 then self:change_state(STATE_IDLE) end
    elseif self.state == STATE_KNOCKDOWN then
        if self.state_time >= 0.8 then
            self.invulnerable = true
        end
        if self.state_time >= 1.1 then self:change_state(STATE_IDLE) end
    end

    if attack_states[self.state] then
        self.combat:set_facing(self.owner, self.facing)
        self.combat:register_attack_hitboxes(self.owner)
    end
    self.combat:register_hurtbox(self.owner, self.hurtbox)
end

function PlayerFSM:on_hit(hit)
    if hit.victim ~= self.owner or self.invulnerable then return end
    local callback = self.callbacks.on_hit
    if callback then callback(hit) end
    if hit.knockback and math.abs(hit.knockback.y or 0) >= 50 then
        self:change_state(STATE_KNOCKDOWN)
    else
        self:change_state(STATE_HITSTUN)
    end
end

function PlayerFSM:set_facing(facing)
    if facing ~= 0 then self.facing = facing < 0 and -1 or 1 end
end

function PlayerFSM:is_invulnerable()
    return self.invulnerable
end

function PlayerFSM:get_state()
    return self.state
end

return PlayerFSM