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
-- Milestone 1b: take, drop, go.

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

-- ---------------------------------------------------------------------------
-- take
-- Picks up an object and moves it to inventory.
-- verify: blocks on fixed objects and already-held items.
-- check:  blocks on non-portable objects (heavy, etc.) the player couldn't
--         know are immovable until they try.
-- action: moves object to inventory.
-- ---------------------------------------------------------------------------
Defaults["take"] = {
    verify = function(obj, _intent)
        if not obj then
            return { illogical = "You don't see that here." }
        end
        if obj.fixed then
            return { illogical = "That's fixed in place." }
        end
        if obj.location == "inventory" then
            return { illogicalAlready = "You're already carrying that." }
        end
        return { logical = true }
    end,

    check = function(obj, _intent)
        if obj.portable == false then
            return "You can't pick that up."
        end
    end,

    action = function(obj, _intent)
        World.moveObject(obj, "inventory")
        return "Taken."
    end,
}

-- ---------------------------------------------------------------------------
-- drop
-- Drops a held object into the current room.
-- verify: blocks if the player isn't holding the object.
-- action: moves object to the current room.
-- ---------------------------------------------------------------------------
Defaults["drop"] = {
    verify = function(obj, _intent)
        if not obj then
            return { illogical = "You aren't carrying that." }
        end
        if obj.location ~= "inventory" then
            return { illogical = "You aren't carrying that." }
        end
        return { logical = true }
    end,

    action = function(obj, _intent)
        World.moveObject(obj, World.currentRoomKey())
        return "Dropped."
    end,
}

-- ---------------------------------------------------------------------------
-- go / directions
--
-- Moves the player in a direction. Registered under "go" and all eight
-- direction verbs so bare "north" works identically to "go north".
--
-- Direction source:
--   "go north" -> verb="go", dobjWords={"north"} -> dobjWords[1]
--   "north"    -> verb="north", dobjWords={}     -> intent.verb
-- ---------------------------------------------------------------------------
local goHandler = {
    action = function(_obj, intent)
        local direction = intent.dobjWords[1]
        if not direction and intent.verb ~= "go" then
            direction = intent.verb
        end
        if not direction then
            return "Go where?"
        end
        local room = World.currentRoom()
        local exit = room.exits[direction]
        if not exit then
            return "You can't go that way."
        end
        local destKey
        if type(exit) == "function" then
            destKey = exit()
        else
            destKey = exit
        end
        if not destKey then
            return "You can't go that way."
        end
        World.moveTo(destKey)
        return World.describeCurrentRoom()
    end,
}

-- ---------------------------------------------------------------------------
-- unlock
-- verify: object must be lockable and currently locked.
-- check:  correct key must be supplied.
-- action: set locked = false.
-- ---------------------------------------------------------------------------
Defaults["unlock"] = {
    verify = function(obj, _intent)
        if not obj then
            return { illogical = "You don't see that here." }
        end
        if obj.locked == nil then
            return { illogical = "That doesn't have a lock." }
        end
        if not obj.locked then
            return { illogicalAlready = "It's not locked." }
        end
        return { logical = true }
    end,

    check = function(obj, intent)
        if not intent.iobjRef then
            return "You'll need a key for that."
        end
        if World.getObject(obj.lockKey) ~= intent.iobjRef then
            return "That key doesn't fit."
        end
    end,

    action = function(obj, _intent)
        obj.locked = false
        return "Unlocked."
    end,
}

-- ---------------------------------------------------------------------------
-- lock
-- verify: object must be lockable and currently unlocked.
-- check:  correct key must be supplied.
-- action: set locked = true.
-- ---------------------------------------------------------------------------
Defaults["lock"] = {
    verify = function(obj, _intent)
        if not obj then
            return { illogical = "You don't see that here." }
        end
        if obj.locked == nil then
            return { illogical = "That doesn't have a lock." }
        end
        if obj.locked then
            return { illogicalAlready = "It's already locked." }
        end
        return { logical = true }
    end,

    check = function(obj, intent)
        if not intent.iobjRef then
            return "You'll need a key for that."
        end
        if World.getObject(obj.lockKey) ~= intent.iobjRef then
            return "That key doesn't fit."
        end
    end,

    action = function(obj, _intent)
        obj.locked = true
        return "Locked."
    end,
}

-- ---------------------------------------------------------------------------
-- put
-- Moves a held object to the current room, near the indirect object.
-- Full container placement (object inside object) deferred to Milestone 3.
-- verify: dobj must be in inventory.
-- action: move dobj to current room; report using the preposition given.
-- ---------------------------------------------------------------------------
Defaults["put"] = {
    verify = function(obj, _intent)
        if not obj then
            return { illogical = "You don't see that here." }
        end
        if obj.location ~= "inventory" then
            return { illogical = "You aren't holding that." }
        end
        return { logical = true }
    end,

    action = function(obj, intent)
        if not intent.iobjRef then
            return "Put the " .. obj.name .. " where?"
        end
        local prep = intent.prep or "in"
        World.moveObject(obj, World.currentRoomKey())
        return "You put the " .. obj.name .. " " .. prep .. " the " ..
               intent.iobjRef.name .. "."
    end,
}

Defaults["go"] = goHandler
for _, dir in ipairs({ "north","south","east","west","up","down","in","out" }) do
    Defaults[dir] = goHandler
end

-- ---------------------------------------------------------------------------
-- wait — a turn passes with no other effect.
-- ---------------------------------------------------------------------------
Defaults["wait"] = {
    action = function(_obj, _intent)
        return "Time passes."
    end,
}

-- ---------------------------------------------------------------------------
-- help — lists available commands.
-- ---------------------------------------------------------------------------
Defaults["help"] = {
    action = function(_obj, _intent)
        return "Commands: look, examine [thing], take [thing], drop [thing],\n" ..
               "inventory, go [direction], north, south, east, west,\n" ..
               "put [thing] in/on [thing], unlock/lock [thing] with [key],\n" ..
               "wait, quit."
    end,
}

-- ---------------------------------------------------------------------------
-- quit — handled at the terminal level in LÖVE2D (love.event.quit).
-- This handler exists as a fallback for headless / test contexts.
-- ---------------------------------------------------------------------------
Defaults["quit"] = {
    action = function(_obj, _intent)
        return "Goodbye."
    end,
}

return Defaults
