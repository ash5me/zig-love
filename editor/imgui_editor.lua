local ffi = require("ffi")

local editor = {
    selected_entity = -1,
    pause_value = ffi.new("bool[1]", false),
    gravity_value = ffi.new("float[1]", 98),
    position_x = ffi.new("float[1]"),
    position_y = ffi.new("float[1]"),
    velocity_x = ffi.new("float[1]"),
    velocity_y = ffi.new("float[1]"),
}

function editor:init(imgui)
    self.imgui = imgui
    if imgui and imgui.love and imgui.love.Init then
        if not self._init_done then
            imgui.love.Init({ use_imgui_docking = true, use_imgui_viewport = false })
            self._init_done = true
        end
    end
end

function editor:update(state, dt)
    self.imgui.love.Update(dt)
    self.imgui.NewFrame()
    self.gravity_value[0] = state.zig.engine_get_gravity(state.context)
end

function editor:draw(state)
    local ig = self.imgui
    ig.MainDockSpace()

    if ig.Begin("Engine Editor") then
        ig.Text("Live engine state")
        ig.Separator()
        if ig.Checkbox("Pause simulation", self.pause_value) then
            state.paused = self.pause_value[0]
        end
        if ig.SliderFloat("Gravity", self.gravity_value, -300, 600) then
            state.zig.engine_set_gravity(state.context, self.gravity_value[0])
        end
        if ig.Button("Spawn 10 entities") then
            state.spawn_entities(10)
        end
        ig.Text("Physics: %dus", tonumber(state.telemetry.physics_us))
        ig.Text("Spatial: %dus", tonumber(state.telemetry.spatial_sort_us))
        ig.Text("Draw: %dus", state.draw_us)
    end
    ig.End()

    if ig.Begin("Entity Hierarchy") then
        local count = tonumber(state.zig.engine_render_count(state.context)) or 0
        local visible_count = math.min(count, 128)
        for order_index = 0, visible_count - 1 do
            local index = tonumber(state.render_order[order_index])
            if ig.Selectable(string.format("Entity %d##entity_%d", index, index), self.selected_entity == index) then
                self.selected_entity = index
            end
        end
    end
    ig.End()

    if ig.Begin("Inspector") then
        if self.selected_entity >= 0 then
            local index = self.selected_entity
            self.position_x[0] = state.positions_x[index]
            self.position_y[0] = state.positions_y[index]
            self.velocity_x[0] = state.velocities_x[index]
            self.velocity_y[0] = state.velocities_y[index]
            if ig.SliderFloat("Position X", self.position_x, -2000, 2000) or ig.SliderFloat("Position Y", self.position_y, -2000, 2000) then
                state.zig.engine_set_position(state.context, index, self.position_x[0], self.position_y[0])
            end
            if ig.SliderFloat("Velocity X", self.velocity_x, -500, 500) or ig.SliderFloat("Velocity Y", self.velocity_y, -500, 500) then
                state.zig.engine_set_velocity(state.context, index, self.velocity_x[0], self.velocity_y[0])
            end
            ig.Text("Sprite frame: %d", tonumber(state.zig.engine_current_sprite_frame_id(state.context, index)))
        else
            ig.Text("Select an entity")
        end
    end
    ig.End()

    ig.Render()
    ig.love.RenderDrawLists()
end

function editor:shutdown()
    if self and self.imgui and self.imgui.love and self.imgui.love.Shutdown then
        return self.imgui.love.Shutdown()
    end
    return nil
end

return editor
