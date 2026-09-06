---@diagnostic disable: undefined-global
local ui = {
    previous_mouse_down = false,
    dragging_slider = false,
    gravity = 98.0,
    paused = false,
    spawn_text = "10",
    text_active = false,
    text_selected = false,
    hover = nil,
}

local function inside(x, y, rect)
    return x >= rect.x and x <= rect.x + rect.w and y >= rect.y and y <= rect.y + rect.h
end

function ui:layout()
    local width, height = love.graphics.getDimensions()
    local panel_width = math.min(300, math.max(196, width - 24))
    local panel_height = 238
    local panel = {
        x = math.max(12, width - panel_width - 12),
        y = 12,
        w = panel_width,
        h = math.min(panel_height, math.max(190, height - 24)),
    }
    local content_x = panel.x + 14
    local content_width = panel.w - 28
    return panel, {
        pause = { x = content_x, y = panel.y + 44, w = content_width, h = 26 },
        slider = { x = content_x, y = panel.y + 92, w = content_width, h = 18 },
        spawn = { x = content_x, y = panel.y + 134, w = content_width * 0.42, h = 28 },
        count = { x = content_x + content_width * 0.46, y = panel.y + 134, w = content_width * 0.54, h = 28 },
    }, height < 280
end

function ui:set_gravity_from_mouse(state, mouse_x, slider)
    local normalized = math.max(0, math.min(1, (mouse_x - slider.x) / slider.w))
    self.gravity = -300 + normalized * 900
    state.zig.engine_set_gravity(state.context, self.gravity)
end

function ui:update(state)
    local panel, controls = self:layout()
    local mouse_x, mouse_y = love.mouse.getPosition()
    local mouse_down = love.mouse.isDown(1)
    local clicked = mouse_down and not self.previous_mouse_down
    self.hover = nil
    for name, rect in pairs(controls) do
        if inside(mouse_x, mouse_y, rect) then self.hover = name end
    end

    if clicked then
        if inside(mouse_x, mouse_y, controls.pause) then
            self.paused = not self.paused
        elseif inside(mouse_x, mouse_y, controls.slider) then
            self.dragging_slider = true
            self:set_gravity_from_mouse(state, mouse_x, controls.slider)
        elseif inside(mouse_x, mouse_y, controls.spawn) then
            state.spawn_entities(tonumber(self.spawn_text) or 0)
        elseif inside(mouse_x, mouse_y, controls.count) then
            self.text_active = true
            self.text_selected = true
        else
            self.text_active = false
            self.text_selected = false
        end
    end

    if self.dragging_slider and mouse_down then
        self:set_gravity_from_mouse(state, mouse_x, controls.slider)
    elseif not mouse_down then
        self.dragging_slider = false
    end

    self.previous_mouse_down = mouse_down
    state.paused = self.paused
    state.debug_gravity = self.gravity
end

function ui:textinput(text)
    if not self.text_active or not text:match("^[0-9]+$") then return end
    if self.text_selected then
        self.spawn_text = ""
        self.text_selected = false
    end
    if #self.spawn_text + #text <= 5 then self.spawn_text = self.spawn_text .. text end
end

function ui:keypressed(key)
    if key == "escape" then
        self.text_active = false
        self.text_selected = false
    elseif self.text_active and key == "backspace" then
        if self.text_selected then
            self.spawn_text = ""
            self.text_selected = false
        else
            self.spawn_text = self.spawn_text:sub(1, -2)
        end
    elseif self.text_active and key == "return" then
        self.text_active = false
        self.text_selected = false
    end
end

function ui:draw_button(rect, label, active)
    local hovered = self.hover ~= nil and ((label == "Pause" or label == "Resume") and self.hover == "pause" or label == "Spawn" and self.hover == "spawn")
    if active then
        love.graphics.setColor(0.18, 0.48, 0.78, 1)
    elseif hovered then
        love.graphics.setColor(0.14, 0.25, 0.38, 1)
    else
        love.graphics.setColor(0.09, 0.13, 0.20, 1)
    end
    love.graphics.rectangle("fill", rect.x, rect.y, rect.w, rect.h, 5, 5)
    love.graphics.setColor(0.32, 0.46, 0.62, 1)
    love.graphics.rectangle("line", rect.x, rect.y, rect.w, rect.h, 5, 5)
    love.graphics.setColor(0.92, 0.96, 1, 1)
    love.graphics.printf(label, rect.x, rect.y + 6, rect.w, "center")
end

function ui:draw(state)
    local panel, controls, compact = self:layout()
    local physics_us = tonumber(state.telemetry.physics_us)
    local spatial_us = tonumber(state.telemetry.spatial_sort_us)
    local ffi_us = tonumber(state.telemetry.ffi_serialization_us)
    local frame_us = tonumber(state.telemetry.frame_us)

    love.graphics.setColor(0.035, 0.05, 0.08, 0.96)
    love.graphics.rectangle("fill", panel.x, panel.y, panel.w, panel.h, 8, 8)
    love.graphics.setColor(0.20, 0.34, 0.50, 1)
    love.graphics.rectangle("line", panel.x, panel.y, panel.w, panel.h, 8, 8)
    love.graphics.setColor(0.88, 0.94, 1, 1)
    love.graphics.print("ENGINE DEBUG", panel.x + 14, panel.y + 12)
    love.graphics.setColor(0.46, 0.58, 0.70, 1)
    love.graphics.print("Runtime controls", panel.x + 14, panel.y + 27)

    self:draw_button(controls.pause, self.paused and "Resume" or "Pause", self.paused)
    love.graphics.setColor(0.64, 0.72, 0.82, 1)
    love.graphics.print("Gravity", controls.slider.x, controls.slider.y - 17)
    love.graphics.setColor(0.08, 0.12, 0.18, 1)
    love.graphics.rectangle("fill", controls.slider.x, controls.slider.y, controls.slider.w, controls.slider.h, 4, 4)
    love.graphics.setColor(0.18, 0.48, 0.78, 1)
    local fill = (self.gravity + 300) / 900 * controls.slider.w
    love.graphics.rectangle("fill", controls.slider.x, controls.slider.y, fill, controls.slider.h, 4, 4)
    local knob_x = controls.slider.x + fill
    love.graphics.circle("fill", knob_x, controls.slider.y + controls.slider.h * 0.5, 7)
    love.graphics.setColor(0.90, 0.95, 1, 1)
    love.graphics.print(string.format("%+.1f", self.gravity), controls.slider.x + controls.slider.w - 45, controls.slider.y - 17)

    self:draw_button(controls.spawn, "Spawn", false)
    local count_active = self.text_active
    love.graphics.setColor(count_active and 0.12 or 0.08, count_active and 0.22 or 0.12, count_active and 0.34 or 0.18, 1)
    love.graphics.rectangle("fill", controls.count.x, controls.count.y, controls.count.w, controls.count.h, 5, 5)
    love.graphics.setColor(0.32, 0.46, 0.62, 1)
    love.graphics.rectangle("line", controls.count.x, controls.count.y, controls.count.w, controls.count.h, 5, 5)
    love.graphics.setColor(0.92, 0.96, 1, 1)
    love.graphics.print("Count: " .. self.spawn_text .. (count_active and "|" or ""), controls.count.x + 8, controls.count.y + 6)

    love.graphics.setColor(0.46, 0.58, 0.70, 1)
    if compact then
        love.graphics.print(string.format("%dus / %dus / %dus", physics_us, spatial_us, state.draw_us), panel.x + 14, panel.y + panel.h - 20)
    else
        love.graphics.print(string.format("Physics  %6dus   Spatial %6dus", physics_us, spatial_us), panel.x + 14, panel.y + 174)
        love.graphics.print(string.format("FFI %6dus   Draw %6dus   Frame %6dus", ffi_us, state.draw_us, frame_us), panel.x + 14, panel.y + 191)
    end
    love.graphics.setColor(1, 1, 1, 1)
end

return ui
