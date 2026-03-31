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

local World    = require("engine.lua.world.world")
local Settings = require("engine.lua.world.settings")

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
        local desc
        if type(obj.description) == "function" then
            desc = obj.description(obj, World.currentContext())
        else
            desc = obj.description or "You see nothing special about it."
        end
        -- Append stateDesc if present (Examine only — not shown during LOOK).
        if obj.stateDesc then
            local state
            if type(obj.stateDesc) == "function" then
                state = obj.stateDesc(obj)
            else
                state = obj.stateDesc
            end
            if state and state ~= "" then
                desc = desc .. " " .. state
            end
        end
        -- Sub-container summary for composite objects (remapIn / remapOn).
        if obj.remapIn then
            local sub = World.getObject(obj.remapIn)
            if sub then
                if not sub.isOpen then
                    desc = desc .. "\n" .. "The " .. sub.name .. " is closed."
                else
                    local contents = World.contentsOf(sub._key)
                    if #contents > 0 then
                        local names = {}
                        for _, item in ipairs(contents) do names[#names + 1] = item.name end
                        desc = desc .. "\n" .. "The " .. sub.name .. " is open. It contains: " ..
                               table.concat(names, ", ") .. "."
                    else
                        desc = desc .. "\n" .. "The " .. sub.name .. " is open and empty."
                    end
                end
            end
        end
        if obj.remapOn then
            local sub = World.getObject(obj.remapOn)
            if sub then
                local contents = World.contentsOf(sub._key)
                if #contents > 0 then
                    local names = {}
                    for _, item in ipairs(contents) do names[#names + 1] = item.name end
                    desc = desc .. "\n" .. "On the " .. sub.name .. ": " ..
                           table.concat(names, ", ") .. "."
                else
                    desc = desc .. "\n" .. "The " .. sub.name .. " is empty."
                end
            end
        end
        -- Container state and contents for objects that are themselves containers (Examine only).
        if obj.contType then
            if obj.contType == "in" then
                if not obj.isOpen then
                    desc = desc .. " It is closed."
                else
                    desc = desc .. " It is open."
                    local contents = World.contentsOf(obj._key)
                    if #contents > 0 then
                        local names = {}
                        for _, item in ipairs(contents) do
                            names[#names + 1] = item.name
                        end
                        desc = desc .. "\n" .. "It contains: " ..
                               table.concat(names, ", ") .. "."
                    else
                        desc = desc .. "\n" .. "It is empty."
                    end
                end
            elseif obj.contType == "on" then
                local contents = World.contentsOf(obj._key)
                if #contents > 0 then
                    local names = {}
                    for _, item in ipairs(contents) do
                        names[#names + 1] = item.name
                    end
                    desc = desc .. "\n" .. "On it: " ..
                           table.concat(names, ", ") .. "."
                else
                    desc = desc .. "\n" .. "It is empty."
                end
            end
        end
        return desc
    end,
}

-- ---------------------------------------------------------------------------
-- read
-- Returns the readDesc of an object. Distinct from examine — examine describes
-- the object's appearance; read returns its textual content.
-- ---------------------------------------------------------------------------
Defaults["read"] = {
    verify = function(obj, _intent)
        if not obj then
            return { illogical = "You don't see that here." }
        end
        if not obj.readDesc then
            return { illogical = "There's nothing to read on that." }
        end
        return { logical = true }
    end,

    action = function(obj, _intent)
        if type(obj.readDesc) == "function" then
            return obj.readDesc(obj, World.currentContext())
        end
        return obj.readDesc
    end,
}

-- ---------------------------------------------------------------------------
-- type
-- Fallback when no terminal is in scope. The real work happens in the
-- terminal object's own handler (reached via scopeDispatch in the dispatcher).
-- ---------------------------------------------------------------------------
Defaults["type"] = {
    action = function(_obj, _intent)
        return "There's nothing here to type on."
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
        local conn = World.getConnector(room, direction)
        if not conn then
            return "You can't go that way."
        end
        if conn.canPass and not conn.canPass() then
            return conn.blockedMsg or "You can't go that way."
        end
        local parts = {}
        -- Auto-open door if present and currently closed.
        if conn.door then
            local door = World.getObject(conn.door)
            if door and door.isOpen == false then
                door.isOpen = true
                if door.otherSide then
                    local other = World.getObject(door.otherSide)
                    if other then other.isOpen = true end
                end
                parts[#parts + 1] = "You open the " .. door.name .. "."
            end
        end
        if conn.traversalMsg then parts[#parts + 1] = conn.traversalMsg end
        World.moveTo(conn.dest)
        parts[#parts + 1] = World.describeCurrentRoom()
        -- Auto-close door behind the player (if setting is enabled).
        if conn.door and Settings.get("doorsCloseOnExit") then
            local door = World.getObject(conn.door)
            if door then
                door.isOpen = false
                if door.otherSide then
                    local other = World.getObject(door.otherSide)
                    if other then other.isOpen = false end
                end
                parts[#parts + 1] = "The " .. door.name .. " closes behind you."
            end
        end
        return table.concat(parts, "\n\n")
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
        if not obj.isLockable then
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
        if obj.otherSide then
            local other = World.getObject(obj.otherSide)
            if other then other.locked = false end
        end
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
        if not obj.isLockable then
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
        if obj.otherSide then
            local other = World.getObject(obj.otherSide)
            if other then other.locked = true end
        end
        return "Locked."
    end,
}

-- ---------------------------------------------------------------------------
-- open
-- Opens an openable object.
-- verify: object must have isOpen defined; must not already be open; must not be locked.
-- action: sets isOpen = true.
-- ---------------------------------------------------------------------------
Defaults["open"] = {
    verify = function(obj, _intent)
        if not obj then
            return { illogical = "You don't see that here." }
        end
        -- Remap to the in-container sub-object if present (e.g. "open desk" → desk_drawer).
        local target = (obj.remapIn and World.getObject(obj.remapIn)) or obj
        if target.isOpen == nil then
            return { illogical = "That doesn't open." }
        end
        if target.isOpen then
            return { illogicalAlready = "It's already open." }
        end
        if target.locked then
            return { illogicalNow = "It's locked." }
        end
        return { logical = true }
    end,

    action = function(obj, _intent)
        local target = (obj.remapIn and World.getObject(obj.remapIn)) or obj
        target.isOpen = true
        return "Opened."
    end,
}

-- ---------------------------------------------------------------------------
-- close
-- Closes an openable object.
-- verify: object must have isOpen defined; must not already be closed.
-- action: sets isOpen = false.
-- ---------------------------------------------------------------------------
Defaults["close"] = {
    verify = function(obj, _intent)
        if not obj then
            return { illogical = "You don't see that here." }
        end
        -- Remap to the in-container sub-object if present (e.g. "close desk" → desk_drawer).
        local target = (obj.remapIn and World.getObject(obj.remapIn)) or obj
        if target.isOpen == nil then
            return { illogical = "That doesn't close." }
        end
        if not target.isOpen then
            return { illogicalAlready = "It's already closed." }
        end
        return { logical = true }
    end,

    action = function(obj, _intent)
        local target = (obj.remapIn and World.getObject(obj.remapIn)) or obj
        target.isOpen = false
        return "Closed."
    end,
}

-- ---------------------------------------------------------------------------
-- put
-- Moves a held object into or onto a container.
-- verify: dobj must be in inventory.
-- action: resolve container via remapIn/remapOn; validate; move dobj into it.
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
        local container = World.resolveContainer(intent.iobjRef, prep)
        -- Validate the container accepts this prep.
        if not container.contType or container.contType ~= prep then
            return "You can't put things " .. prep .. " the " .. container.name .. "."
        end
        -- In-containers must be open.
        if container.contType == "in" and not container.isOpen then
            return "The " .. container.name .. " isn't open."
        end
        World.moveObject(obj, container._key)
        return "You put the " .. obj.name .. " " .. prep .. " the " ..
               container.name .. "."
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
-- help — returns authored help text from events.json.
-- "help" alone returns the default help block.
-- "help <topic>" returns the topic text, or a "no help available" message.
-- ---------------------------------------------------------------------------
Defaults["help"] = {
    action = function(_obj, intent)
        local topic = intent.dobjWords and table.concat(intent.dobjWords, " ") or ""
        return World.getHelp(topic)
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
