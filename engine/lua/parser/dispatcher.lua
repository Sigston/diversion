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
-- verify() must not modify state. check() must not change world state; may set
-- tracking flags on the object. action() may modify state.

local World    = require("engine.lua.world.world")
local Defaults = require("engine.lua.world.defaults")
local Verbs    = require("engine.lua.lexicon.verbs")

local Dispatcher = {}

-- ---------------------------------------------------------------------------
-- runCycle(handler, obj, intent)
--
-- Runs verify -> check -> action on a handler table.
-- Any phase is optional — if a handler omits verify() or check(), we skip it.
--
-- verify() returns a result table. Blocking result types are:
--   illogical, illogicalAlready, illogicalNow — each carries a message string.
-- Non-blocking types: logical, dangerous, nonObvious.
--
-- check() returns a string to block, or nil to allow.
--
-- action() returns the output string.
-- ---------------------------------------------------------------------------
function Dispatcher.runCycle(handler, obj, intent)
    -- Phase 1: verify
    -- Must not modify state. May be called multiple times (during disambiguation).
    -- Blocks on illogical, illogicalAlready, or illogicalNow.
    if handler.verify then
        local result = handler.verify(obj, intent)
        if result then
            local msg = result.illogical or result.illogicalAlready or result.illogicalNow
            if msg then return msg end
        end
    end

    -- Phase 2: check
    -- Must not change world state. May set tracking flags on the object.
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

    -- Scenery interception: non-examine/read verbs bounce off scenery objects.
    if obj and obj.scenery and verb ~= "examine" and verb ~= "read" then
        return obj.notImportantMsg or "That's not something you need to worry about."
    end

    -- 1. Object-specific handler
    if obj and obj.handlers and obj.handlers[verb] then
        return Dispatcher.runCycle(obj.handlers[verb], obj, intent)
    end

    -- 1b. scopeDispatch: verb has no resolved dobjRef but wants an ambient
    -- receiver. Scan scope for the first object that has a handler for this verb.
    -- Used by TYPE, where the terminal is found implicitly rather than named.
    local verbEntry = Verbs[verb]
    if not obj and verbEntry and verbEntry.scopeDispatch then
        for _, candidate in ipairs(World.inScope()) do
            if candidate.handlers and candidate.handlers[verb] then
                return Dispatcher.runCycle(candidate.handlers[verb], candidate, intent)
            end
        end
        -- No handler-bearing object found; fall through to room/default.
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
