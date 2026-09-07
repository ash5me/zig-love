---@diagnostic disable: undefined-global
local Input = {}
Input.__index = Input

function Input.new()
    return setmetatable({
        bindings = {
            play_sound = { bit = 1, keys = { "mouse1" } },
            player_died = { bit = 2, keys = { "x" } },
            jump = { bit = 4, keys = { "space", "w", "up" }, gamepad = "a" },
            jump_attack = { bit = 1024, keys = { "space" }, gamepad = "a" },
            move_left = { bit = 8, keys = { "a", "left" }, axis = -1 },
            move_right = { bit = 32, keys = { "d", "right" }, axis = 1 },
            move_down = { bit = 16, keys = { "s", "down" } },
            move_up = { bit = 64, keys = { "w", "up" } },
            attack = { bit = 128, keys = { "j", "z", "mouse1" }, gamepad = "x" },
            pick_up = { bit = 256, keys = { "e" }, gamepad = "y" },
            throw = { bit = 512, keys = { "k", "q" }, gamepad = "rightshoulder" },
        },
    }, Input)
end

function Input:bind(action, binding)
    assert(self.bindings[action], "Unknown input action: " .. tostring(action))
    self.bindings[action] = binding
end

local function key_down(key)
    if key == "mouse1" then return love.mouse.isDown(1) end
    return love.keyboard.isDown(key)
end

local function gamepad_down(binding)
    if not binding then return false end
    for _, joystick in ipairs(love.joystick.getJoysticks()) do
        if joystick:isGamepad() and joystick:isGamepadDown(binding) then return true end
    end
    return false
end

function Input:is_down(action)
    local binding = self.bindings[action]
    if not binding then return false end
    for _, key in ipairs(binding.keys or {}) do
        if key_down(key) then return true end
    end
    if gamepad_down(binding.gamepad) then return true end
    if binding.axis then
        for _, joystick in ipairs(love.joystick.getJoysticks()) do
            if joystick:isGamepad() then
                local axis = joystick:getGamepadAxis("leftx")
                if (binding.axis < 0 and axis < -0.35) or (binding.axis > 0 and axis > 0.35) then return true end
            end
        end
    end
    return false
end

function Input:buttons()
    local buttons = 0
    for _, binding in pairs(self.bindings) do
        if self:is_down_for_binding(binding) then buttons = buttons + binding.bit end
    end
    return buttons
end

function Input:is_down_for_binding(binding)
    for _, key in ipairs(binding.keys or {}) do
        if key_down(key) then return true end
    end
    if gamepad_down(binding.gamepad) then return true end
    if binding.axis then
        for _, joystick in ipairs(love.joystick.getJoysticks()) do
            if joystick:isGamepad() then
                local axis = joystick:getGamepadAxis("leftx")
                if (binding.axis < 0 and axis < -0.35) or (binding.axis > 0 and axis > 0.35) then return true end
            end
        end
    end
    return false
end

return Input
