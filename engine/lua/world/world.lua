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

    initialState = {}
    for key, obj in pairs(objects) do
        initialState[key] = {
            location = obj.location,
            locked   = obj.locked,
            moved    = obj.moved,
        }
    end
    for key in pairs(rooms) do
        initialState[key] = { visited = false }
    end
end

-- ---------------------------------------------------------------------------
-- World API — basic queries
-- ---------------------------------------------------------------------------

function World.currentRoom()
    return rooms[currentRoomKey]
end

function World.currentRoomKey()
    return currentRoomKey
end

-- Returns a context table for object description functions.
-- Room descriptions get a richer context built inside describeCurrentRoom().
function World.currentContext()
    return {}
end

-- Returns all objects currently in scope.
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

function World.reset()
    for key, snap in pairs(initialState) do
        if rooms[key] then
            rooms[key].visited = false
        elseif objects[key] then
            objects[key].location = snap.location
            if snap.locked ~= nil then
                objects[key].locked = snap.locked
            end
            objects[key].moved = snap.moved
        end
    end
    currentRoomKey = startRoomKey
end

function World.moveTo(roomKey)
    currentRoomKey = roomKey
end

function World.moveObject(obj, location)
    -- Track that this object has been moved by the player (affects initSpecialDesc).
    if location == "inventory" and obj.location ~= "inventory" then
        obj.moved = true
    end
    obj.location = location
end

function World.getObject(key)
    return objects[key]
end

-- ---------------------------------------------------------------------------
-- Room description compositor
-- ---------------------------------------------------------------------------

-- Returns true if the room has ambient light.
-- Default: lit (isLit == nil or isLit == true).
-- Override in JSON: "isLit": false for dark rooms.
local function isIlluminated(room)
    return room.isLit ~= false
end

-- Clears the mentioned flag on every object in the room before each LOOK.
local function unmentionAll(room)
    for _, key in ipairs(room.objects) do
        local obj = objects[key]
        if obj then obj.mentioned = false end
    end
end

-- Returns true if obj has an active specialDesc or initSpecialDesc paragraph.
local function hasActiveSpecialDesc(obj)
    if obj.initSpecialDesc and not obj.moved then return true end
    if obj.specialDesc then return true end
    return false
end

-- Renders an object's specialDesc paragraph and marks it as mentioned.
local function showSpecialDesc(obj)
    local text
    if obj.initSpecialDesc and not obj.moved then
        text = obj.initSpecialDesc
    else
        text = obj.specialDesc
    end
    if not text then return nil end
    if type(text) == "function" then text = text(obj) end
    obj.mentioned = true
    return text
end

-- Builds the "You can also see: X, Y, and Z." sentence for unlisted misc items.
local function buildMiscSentence(items)
    local names = {}
    for _, obj in ipairs(items) do
        names[#names + 1] = obj.name
        obj.mentioned = true
    end
    if #names == 1 then
        return "You can also see: " .. names[1] .. "."
    elseif #names == 2 then
        return "You can also see: " .. names[1] .. " and " .. names[2] .. "."
    end
    local last = table.remove(names)
    return "You can also see: " .. table.concat(names, ", ") .. ", and " .. last .. "."
end

-- Runs the four-stage listing and returns the assembled string, or nil.
local function listContents(room, ctx)
    local firstSpecial  = {}
    local miscItems     = {}
    local secondSpecial = {}

    for _, key in ipairs(room.objects) do
        local obj = objects[key]
        if obj and not ctx.excluded[key] and not obj.mentioned
                and obj.location == currentRoomKey then
            if hasActiveSpecialDesc(obj) then
                if obj.specialDescBeforeContents ~= false then
                    firstSpecial[#firstSpecial + 1] = obj
                else
                    secondSpecial[#secondSpecial + 1] = obj
                end
            elseif obj.listed ~= false then
                miscItems[#miscItems + 1] = obj
            end
        end
    end

    local function byOrder(a, b)
        return (a.specialDescOrder or 100) < (b.specialDescOrder or 100)
    end
    table.sort(firstSpecial,  byOrder)
    table.sort(secondSpecial, byOrder)

    local result = {}

    for _, obj in ipairs(firstSpecial) do
        local text = showSpecialDesc(obj)
        if text then result[#result + 1] = text end
    end

    if #miscItems > 0 then
        result[#result + 1] = buildMiscSentence(miscItems)
    end

    for _, obj in ipairs(secondSpecial) do
        local text = showSpecialDesc(obj)
        if text then result[#result + 1] = text end
    end

    if #result == 0 then return nil end
    return table.concat(result, "\n\n")
end

-- Builds the "Exits: north, south." sentence for traversable exits.
local function listExits(room)
    local available = {}
    for dir, exit in pairs(room.exits) do
        local dest
        if type(exit) == "function" then
            dest = exit()
        else
            dest = exit
        end
        if dest then
            available[#available + 1] = dir
        end
    end
    if #available == 0 then return nil end
    table.sort(available)
    return "Exits: " .. table.concat(available, ", ") .. "."
end

-- The master compositor. Assembles the complete room description:
-- title, body, four-stage object listing, exit list.
function World.describeCurrentRoom()
    local room = rooms[currentRoomKey]

    -- Step 1: Reset mentioned flags on all room objects.
    unmentionAll(room)

    local parts = {}

    -- Step 2: Room title (dark name when unlit).
    if isIlluminated(room) then
        parts[#parts + 1] = room.name
    else
        parts[#parts + 1] = room.darkName or "In the dark"
    end

    -- Step 3: Dark branch — suppress everything except darkDesc.
    if not isIlluminated(room) then
        local darkDesc = room.darkDesc or "It is pitch black; you can't see a thing."
        if type(darkDesc) == "function" then darkDesc = darkDesc(room) end
        parts[#parts + 1] = darkDesc
        room.visited = true
        return table.concat(parts, "\n")
    end

    -- Step 4: Build room context (firstVisit flag + exclude helper).
    local excluded = {}
    local ctx = {
        firstVisit = not room.visited,
        excluded   = excluded,
        exclude    = function(key) excluded[key] = true end,
    }

    -- Step 5: Room description body.
    -- Title and body join with a single newline; subsequent blocks use double.
    local desc = room.description(room, ctx)
    local out = parts[1] .. "\n" .. desc

    -- Steps 6–7: Object listing and exit listing (unless suppressed).
    if not room.suppressListing then
        local listing = listContents(room, ctx)
        if listing then out = out .. "\n\n" .. listing end

        local exits = listExits(room)
        if exits then out = out .. "\n\n" .. exits end
    end

    -- Step 8: Mark room as visited.
    room.visited = true

    return out
end

return World
