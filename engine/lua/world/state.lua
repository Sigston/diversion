-- world/state.lua
-- Global state flags.
-- State.set(key, value), State.get(key), State.reset()

local State = {}
local flags = {}

function State.set(key, value) flags[key] = value end
function State.get(key)        return flags[key]   end
function State.reset()         flags = {}          end

return State
