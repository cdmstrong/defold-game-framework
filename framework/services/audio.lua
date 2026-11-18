-- Audio service: music/sfx groups with independent volume, mute and the
-- browser "play after first interaction" unlock.
--
-- The service talks to an injected `sound` backend so the module stays pure Lua
-- (testable) while the demo wires it to Defold's `sound` module. Backend must
-- expose the calls the service uses; anything missing is a no-op.
--
-- play_music(id)          -> true | nil, error
-- play_sfx(id)            -> handle | nil, error
-- set_volume(group, value) -> true | nil, error
-- set_muted(muted)         -> true
-- unlock()                 -> mark first-interaction done (browser audio)

local M = {}

function M.create(backend, options)
    options = options or {}
    local self = {
        backend = backend or {},
        volume = { music = options.music_volume or 1.0, sfx = options.sfx_volume or 1.0 },
        muted = options.muted or false,
        unlocked = false,
        music_id = nil,
        pending_music = nil, -- music requested before unlock (HTML5 autoplay policy)
    }

    local function effective(group)
        return self.muted and 0 or self.volume[group]
    end

    function self:unlock()
        self.unlocked = true
        if self.pending_music then
            local id = self.pending_music
            self.pending_music = nil
            self:play_music(id)
        end
        return true
    end

    function self:play_music(id, opts)
        if not self.unlocked then
            -- Browser autoplay policy: retain the intent, play after unlock.
            self.pending_music = id
            return true
        end
        if self.music_id then
            if self.backend.stop then self.backend.stop(self.music_id) end
        end
        if self.backend.play then
            local handle = self.backend.play(id, { gain = effective("music"), looping = opts and opts.looping })
            self.music_id = handle
            return handle, nil
        end
        return true, nil
    end

    function self:stop_music()
        if self.music_id and self.backend.stop then
            self.backend.stop(self.music_id)
        end
        self.music_id = nil
        self.pending_music = nil
        return true
    end

    function self:play_sfx(id, opts)
        if not self.unlocked then return nil, { code = "not_unlocked", message = "await first interaction" } end
        if self.backend.play then
            return self.backend.play(id, { gain = effective("sfx"), looping = false }), nil
        end
        return true, nil
    end

    function self:set_volume(group, value)
        value = math.max(0, math.min(1, value))
        if group ~= "music" and group ~= "sfx" then
            return nil, { code = "unknown_group", message = tostring(group) }
        end
        self.volume[group] = value
        -- Reflect into the live backend if it supports per-group gain.
        if group == "music" and self.music_id and self.backend.set_gain then
            self.backend.set_gain(self.music_id, effective("music"))
        end
        return true
    end

    function self:get_volume(group)
        return self.volume[group]
    end

    function self:set_muted(muted)
        self.muted = not not muted
        if self.music_id and self.backend.set_gain then
            self.backend.set_gain(self.music_id, effective("music"))
        end
        return true
    end

    function self:is_muted()
        return self.muted
    end

    return self
end

return M
