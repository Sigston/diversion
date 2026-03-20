-- parser/dispatcher.lua
--
-- Receives a fully resolved CommandIntent and runs the three-phase cycle:
--   verify() -> check() -> action()
--
-- Lookup order for handlers:
--   1. Object-specific handler  (obj.handlers[verb])
--   2. Room-level handler       (room.handlers[verb])
--   3. Default handler          (Defaults[verb])
--   4. Nothing found            -> "You can't do that."
--
-- The three phases must never be collapsed (see CLAUDE.md absolute rules).
-- verify() is read-only. check() is read-only. action() may modify state.

local World    = require("engine.lua.world.world")
local Defaults = require("engine.lua.world.defaults")

local Dispatcher = {}

-- ---------------------------------------------------------------------------
-- runCycle(handler, obj, intent)
--
-- Runs verify -> check -> action on a handler table.
-- Any phase is optional — if a handler omits verify() or check(), we skip it.
--
-- verify() returns a result table. If result.illogical is set, we stop
-- and return that message. Otherwise we continue.
--
-- check() returns a string to block, or nil to allow.
--
-- action() returns the output string.
-- ---------------------------------------------------------------------------
function Dispatcher.runCycle(handler, obj, intent)
    -- Phase 1: verify
    -- Read-only. May be called multiple times (during disambiguation).
    -- If it returns illogical, the action is blocked.
    if handler.verify then
        local result = handler.verify(obj, intent)
        if result and result.illogical then
            return result.illogical
        end
    end

    -- Phase 2: check
    -- Read-only. Called after objects are fully resolved.
    -- Returns a string to block, or nil to allow.
    if handler.check then
        local block = handler.check(obj, intent)
        if block then
            return block
        end
    end

    -- Phase 3: action
    -- The only phase that may modify game state.
    -- Returns the output string.
    if handler.action then
        return handler.action(obj, intent)
    end

    return "Nothing happens."
end

-- ---------------------------------------------------------------------------
-- dispatch(intent)
--
-- Finds the right handler for the verb in the given intent, then runs
-- the three-phase cycle.
-- ---------------------------------------------------------------------------
function Dispatcher.dispatch(intent)
    local verb = intent.verb
    local obj  = intent.dobjRef     -- nil for verbs like look, inventory
    local room = World.currentRoom()

    -- 1. Object-specific handler
    if obj and obj.handlers and obj.handlers[verb] then
        return Dispatcher.runCycle(obj.handlers[verb], obj, intent)
    end

    -- 2. Room-level handler
    if room.handlers and room.handlers[verb] then
        return Dispatcher.runCycle(room.handlers[verb], room, intent)
    end

    -- 3. Default handler
    if Defaults[verb] then
        return Dispatcher.runCycle(Defaults[verb], obj, intent)
    end

    -- 4. Nothing found
    return "You can't do that."
end

return Dispatcher
