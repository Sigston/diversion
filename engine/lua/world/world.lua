-- world/world.lua
--
-- The world model. Owns all rooms and objects, answers scope queries,
-- and handles player movement.
--
-- In Milestone 1a this is a hardcoded stub: one room, a few objects,
-- no JSON loading. The full version (Milestone 3) loads from JSON and
-- supports multiple rooms, time periods, and containers.
--
-- Other modules never access rooms or objects directly. They always go
-- through World's functions. This keeps the world internals replaceable.

local World = {}

-- ---------------------------------------------------------------------------
-- Objects
-- Each object has:
--   name        string       the primary name used in output ("iron key")
--   aliases     {string}     other names the player might use ("key")
--   adjectives  {string}     words that narrow object matching ("iron", "old")
--   description string       returned by the default examine handler
--   location    string       "inventory", a room key, or nil (not yet in world)
--   portable    bool         can the player pick this up?
--   handlers    table        verb-specific overrides (empty = use defaults)
-- ---------------------------------------------------------------------------
local objects = {

    iron_key = {
        name        = "iron key",
        aliases     = { "key" },
        adjectives  = { "iron", "old", "small" },
        description = "A small iron key. The bow is cast in the shape of a hare.",
        location    = "player_quarters",
        portable    = true,
        handlers    = {},
    },

    oil_lamp = {
        name        = "oil lamp",
        aliases     = { "lamp" },
        adjectives  = { "oil", "brass", "old" },
        description = "A brass oil lamp. The reservoir is about half full.",
        location    = "player_quarters",
        portable    = true,
        handlers    = {},
    },

    copper_key = {
        name        = "copper key",
        aliases     = { "key" },
        adjectives  = { "copper", "small" },
        description = "A small copper key. Simpler in design than you'd expect.",
        location    = "player_quarters",
        portable    = true,
        handlers    = {},
    },

    writing_desk = {
        name        = "writing desk",
        aliases     = { "desk" },
        adjectives  = { "writing", "large", "wooden" },
        description = "A large wooden desk. Its surface is bare except for a " ..
                      "faint ring left by some long-gone cup.",
        location    = "player_quarters",
        portable    = false,
        handlers    = {},
    },

    chest = {
        name        = "small chest",
        aliases     = { "chest" },
        adjectives  = { "small", "wooden" },
        description = "A small wooden chest secured with an iron lock.",
        location    = "player_quarters",
        portable    = false,
        locked      = true,
        lockKey     = "iron_key",
        handlers    = {},
    },
}

-- ---------------------------------------------------------------------------
-- Rooms
-- Each room has:
--   name         string           displayed on entry
--   description  function(ctx)    returns the room description string.
--                                 Takes a context table (visited, flags, etc.)
--                                 Must be a function — never a plain string.
--   exits        table            direction -> room key (or function, Milestone 3)
--   objects      {string}         keys into the objects table above
--   handlers     table            room-level verb intercepts (empty for now)
--   visited      bool             tracked to give short desc on repeat visits
-- ---------------------------------------------------------------------------
local rooms = {

    player_quarters = {
        name = "Your Quarters",
        description = function(self, ctx)
            if not self.visited then
                return "Your quarters are exactly as you left them — which is to " ..
                       "say, arranged with the particular chaos of someone who " ..
                       "knows where everything is. The writing desk dominates one " ..
                       "wall. An oil lamp sits where you last set it down. " ..
                       "Somewhere nearby, an iron key catches the light."
            end
            return "Your quarters. The writing desk, the lamp, the key."
        end,
        exits    = { north = "entrance_passage" },
        objects  = { "iron_key", "copper_key", "oil_lamp", "writing_desk", "chest" },
        handlers = {},
        visited  = false,
    },

    entrance_passage = {
        name = "Entrance Passage",
        description = function(self, ctx)
            if not self.visited then
                return "A narrow stone passage leads away from your quarters. " ..
                       "Bare walls, bare floor. The way back is to the south."
            end
            return "The entrance passage. Bare stone."
        end,
        exits    = { south = "player_quarters" },
        objects  = {},
        handlers = {},
        visited  = false,
    },
}

-- The player's current room key.
local currentRoomKey = "player_quarters"

-- ---------------------------------------------------------------------------
-- World API
-- ---------------------------------------------------------------------------

-- Returns the current room table.
function World.currentRoom()
    return rooms[currentRoomKey]
end

-- Returns the current room key string.
function World.currentRoomKey()
    return currentRoomKey
end

-- Returns a context table passed to room description functions.
-- Contains things the room needs but doesn't own: lit state, period, flags.
-- The room itself is passed separately as 'self', so it can check its own
-- properties (like visited) directly without going through ctx.
-- In Milestone 1a this is empty. Populated in later milestones.
function World.currentContext()
    return {}
end

-- Returns all objects currently in scope.
-- Scope = objects in the current room + objects in player inventory.
-- (Container recursion added in Milestone 3.)
function World.inScope()
    local scope = {}
    local room  = rooms[currentRoomKey]

    for _, key in ipairs(room.objects) do
        local obj = objects[key]
        if obj and obj.location == currentRoomKey then
            scope[#scope + 1] = obj
        end
    end

    for _, obj in pairs(objects) do
        if obj.location == "inventory" then
            scope[#scope + 1] = obj
        end
    end

    return scope
end

-- Returns the room description string, then marks the room as visited.
function World.describeCurrentRoom()
    local room = rooms[currentRoomKey]
    local desc = room.description(room, World.currentContext())
    room.visited = true
    return room.name .. "\n" .. desc
end

-- Returns a string listing everything in the player's inventory.
function World.describeInventory()
    local carried = {}
    for _, obj in pairs(objects) do
        if obj.location == "inventory" then
            carried[#carried + 1] = obj.name
        end
    end
    if #carried == 0 then
        return "You are carrying nothing."
    end
    return "You are carrying: " .. table.concat(carried, ", ") .. "."
end

-- Resets all mutable world state to its initial values.
-- Called at the start of each test run so tests are always independent.
function World.reset()
    for _, room in pairs(rooms) do
        room.visited = false
    end
    objects.iron_key.location     = "player_quarters"
    objects.copper_key.location   = "player_quarters"
    objects.oil_lamp.location     = "player_quarters"
    objects.writing_desk.location = "player_quarters"
    objects.chest.location        = "player_quarters"
    objects.chest.locked          = true
    currentRoomKey = "player_quarters"
end

-- Moves the player to a new room.
-- Called by the go handler. Does not print anything.
function World.moveTo(roomKey)
    currentRoomKey = roomKey
end

-- Moves an object to a new location.
-- location can be "inventory", a room key, or nil.
-- Used by the take and drop handlers (Milestone 1b).
function World.moveObject(obj, location)
    obj.location = location
end

-- Returns an object by key. Used by handlers that need to reference
-- a specific object directly rather than going through scope.
function World.getObject(key)
    return objects[key]
end

return World
