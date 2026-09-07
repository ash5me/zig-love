---@diagnostic disable: undefined-global, undefined-field
local Audio = {}
Audio.__index = Audio

function Audio.new(state)
    return setmetatable({
        state = state,
        sounds = {},
        command = state.ffi.new("AudioCommand"),
    }, Audio)
end

function Audio:register(sound_id, source)
    assert(source, "Audio source is required")
    self.sounds[tostring(sound_id)] = source
end

function Audio:emit(sound_id, source_x, source_y, max_distance, volume)
    return self.state.zig.engine_emit_spatial_sound(
        self.state.context,
        sound_id,
        source_x,
        source_y,
        max_distance or 512,
        volume or 1
    )
end

function Audio:update_listener(x, y)
    self.state.zig.engine_set_audio_listener(self.state.context, x, y)
end

function Audio:poll()
    local zig = self.state.zig
    while zig.engine_next_audio_command(self.state.context, self.command) do
        local source = self.sounds[tostring(self.command.sound_id)]
        if source then
            local playback = source:clone()
            playback:setVolume(tonumber(self.command.volume))
            playback:setPan(tonumber(self.command.pan))
            playback:play()
        end
    end
end

function Audio:clear()
    self.state.zig.engine_clear_audio_commands(self.state.context)
end

return Audio
