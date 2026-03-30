-- engine/lua/world/settings.lua
--
-- Engine-level settings loaded from settings.json at startup.
-- Unlike State, settings are configuration rather than game state —
-- they are not saved/restored and survive World.reset().
--
-- API:
--   Settings.load(table)   called by the loader with the parsed JSON
--   Settings.get(key)      returns the setting value, or the default if unset
--   Settings.reset()       restores defaults (called between test runs)

local Settings = {}

-- Defaults applied when a key is absent from settings.json.
local defaults = {
    doorsCloseOnExit = true,
}

local data = {}

function Settings.load(raw)
    data = raw or {}
end

function Settings.get(key)
    if data[key] ~= nil then return data[key] end
    return defaults[key]
end

function Settings.reset()
    data = {}
end

return Settings
