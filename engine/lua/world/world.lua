-- world/world.lua
--
-- The world model. Owns all rooms and objects, answers scope queries,
-- and handles player movement.
--
-- Populated at startup by Loader.load() / World.load(). Never hardcodes game
-- content — all data comes from JSON via the loader.
--
-- Other modules never access rooms or objects directly. They always go
-- through World's functions. This keeps the world internals replaceable.

local World = {}

-- ---------------------------------------------------------------------------
-- Module-level state — populated by World.load()
-- ---------------------------------------------------------------------------
local rooms          = {}
local objects        = {}
local currentRoomKey = ""
local startRoomKey   = ""

-- Snapshot of mutable object/room state taken at load time, used by reset().
-- initialState[key] = { location, locked }   for objects
-- initialState[key] = { visited = false }    for rooms
local initialState = {}

-- ---------------------------------------------------------------------------
-- World.load — called once by the loader after parsing JSON.
-- Stores the tables and computes the reset snapshot.
-- ---------------------------------------------------------------------------
function World.load(roomsTable, objectsTable, startRoom)
    rooms          = roomsTable
    objects        = objectsTable
    startRoomKey   = startRoom
    currentRoomKey = startRoom

    -- Snapshot mutable state for reset()
    initialState = {}
    for key, obj in pairs(objects) do
        initialState[key] = {
            location = obj.location,
            locked   = obj.locked,   -- nil for non-lockable objects
        }
    end
    for key in pairs(rooms) do
        initialState[key] = { visited = false }
    end
end

-- ---------------------------------------------------------------------------
-- World API
-- ---------------------------------------------------------------------------

function World.currentRoom()
    return rooms[currentRoomKey]
end

function World.currentRoomKey()
    return currentRoomKey
end

-- Returns the context table passed to room description functions.
-- Contains things the room needs but doesn't own: lit state, period, flags.
-- Extended in later milestones.
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

function World.describeCurrentRoom()
    local room = rooms[currentRoomKey]
    local desc = room.description(room, World.currentContext())
    room.visited = true
    return room.name .. "\n" .. desc
end

function World.describeInventory()
    local carried = {}
    for _, obj in pairs(objects) do
        if obj.location == "inventory" then
            carried[#carried + 1] = obj.name
        end
    end
    if #carried == 0 then return "You are carrying nothing." end
    return "You are carrying: " .. table.concat(carried, ", ") .. "."
end

-- Resets all mutable world state to the values captured at load time.
-- Called at the start of each test run so tests are always independent.
function World.reset()
    for key, snap in pairs(initialState) do
        if rooms[key] then
            rooms[key].visited = false
        elseif objects[key] then
            objects[key].location = snap.location
            if snap.locked ~= nil then
                objects[key].locked = snap.locked
            end
        end
    end
    currentRoomKey = startRoomKey
end

function World.moveTo(roomKey)
    currentRoomKey = roomKey
end

function World.moveObject(obj, location)
    obj.location = location
end

function World.getObject(key)
    return objects[key]
end

return World
