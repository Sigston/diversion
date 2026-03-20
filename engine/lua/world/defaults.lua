-- world/defaults.lua
--
-- Default verb handlers. These are reached when no object-specific or
-- room-level handler intercepts the command first.
--
-- Each handler is a table with up to three functions:
--
--   verify(obj, intent)  -> result table, or nil (means "no objection")
--       Used for disambiguation ranking. Must never modify game state.
--       Return values:
--           { logical = true }              no objection (default if nil)
--           { logical = true, rank = 150 }  preferred candidate
--           { illogical = "message" }       hard block; excluded from candidates
--
--   check(obj, intent)   -> string, or nil
--       Enforces conditions the player couldn't know in advance.
--       Return nil to allow. Return a string to block with that message.
--
--   action(obj, intent)  -> string
--       Executes the effect. Returns the output string.
--       This is the only phase that may modify game state.
--
-- Milestone 1a: examine, look, inventory.
-- Milestone 1b adds: take, drop, go.

local World = require("engine.lua.world.world")

local Defaults = {}

-- ---------------------------------------------------------------------------
-- examine
-- Describes an object. The object must exist in scope (resolver ensures this)
-- and must have a description.
-- ---------------------------------------------------------------------------
Defaults["examine"] = {
    verify = function(obj, _intent)
        if not obj then
            return { illogical = "You don't see that here." }
        end
        return { logical = true }
    end,

    action = function(obj, _intent)
        -- description may be a plain string or a function.
        -- Rule 5 from CLAUDE.md: always call it as a function if it is one.
        if type(obj.description) == "function" then
            return obj.description(obj, World.currentContext())
        end
        return obj.description or "You see nothing special about it."
    end,
}

-- ---------------------------------------------------------------------------
-- look
-- Describes the current room. No object involved.
-- ---------------------------------------------------------------------------
Defaults["look"] = {
    action = function()
        return World.describeCurrentRoom()
    end,
}

-- ---------------------------------------------------------------------------
-- inventory
-- Lists what the player is carrying. No object involved.
-- ---------------------------------------------------------------------------
Defaults["inventory"] = {
    action = function()
        return World.describeInventory()
    end,
}

return Defaults
