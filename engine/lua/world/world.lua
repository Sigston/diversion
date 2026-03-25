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
        obj._key = key    -- store own key for container operations
        initialState[key] = {
            location = obj.location,
            locked   = obj.locked,
            moved    = obj.moved,
            isOpen   = obj.isOpen,
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

-- Returns true if obj is physically reachable from the current room.
-- On-containers are always open. In-containers require isOpen = true.
local function isReachable(obj)
    local loc = obj.location
    if loc == currentRoomKey then return true end
    if loc == nil then return false end
    local container = objects[loc]
    if not container then return false end
    if not isReachable(container) then return false end
    if container.contType == "on" then return true end
    if container.contType == "in" and container.isOpen then return true end
    return false
end

-- Returns all objects currently in scope.
-- Includes room objects (reachable through open containers/surfaces) + inventory.
function World.inScope()
    local scope = {}
    local room  = rooms[currentRoomKey]

    for _, key in ipairs(room.objects) do
        local obj = objects[key]
        if obj and isReachable(obj) then
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

-- Returns objects directly inside a container, sorted by name.
function World.contentsOf(objKey)
    local result = {}
    for _, obj in pairs(objects) do
        if obj.location == objKey then
            result[#result + 1] = obj
        end
    end
    table.sort(result, function(a, b) return a.name < b.name end)
    return result
end

-- Follows remapIn/remapOn on obj to find the actual container for a PUT operation.
-- If obj has no remap for the given prep, returns obj itself.
function World.resolveContainer(obj, prep)
    if prep == "in" and obj.remapIn then
        return objects[obj.remapIn]
    end
    if prep == "on" and obj.remapOn then
        return objects[obj.remapOn]
    end
    return obj
end

function World.describeInventory()
    local carried = {}
    for _, obj in pairs(objects) do
        if obj.location == "inventory" then
            carried[#carried + 1] = obj.name
        end
    end
    if #carried == 0 then return "You are carrying nothing." end
    table.sort(carried)
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
            if snap.isOpen ~= nil then
                objects[key].isOpen = snap.isOpen
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

function World.getConnector(room, dir)
    return room.exits[dir]
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
            elseif obj.listed ~= false
                   and not obj.remapIn and not obj.remapOn
                   and not (obj.contType == "in" and obj.isOpen) then
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

    -- Stage 4A: Composite objects (remapIn / remapOn) get a dedicated paragraph.
    -- They are excluded from the misc sentence and described here instead.
    for _, key in ipairs(room.objects) do
        local obj = objects[key]
        if obj and not ctx.excluded[key] and not obj.mentioned
                and obj.location == currentRoomKey
                and (obj.remapIn or obj.remapOn) then
            local lines = { "There is a " .. obj.name .. " here." }
            if obj.remapOn then
                local sub = World.getObject(obj.remapOn)
                if sub then
                    local contents = World.contentsOf(sub._key)
                    local names = {}
                    for _, item in ipairs(contents) do
                        if not item.mentioned then
                            names[#names + 1] = item.name
                            item.mentioned = true
                        end
                    end
                    if #names > 0 then
                        lines[#lines + 1] = "On the " .. sub.name .. ": " ..
                                             table.concat(names, ", ") .. "."
                    end
                    sub.mentioned = true
                end
            end
            if obj.remapIn then
                local sub = World.getObject(obj.remapIn)
                if sub then
                    if sub.isOpen then
                        local contents = World.contentsOf(sub._key)
                        local names = {}
                        for _, item in ipairs(contents) do
                            if not item.mentioned then
                                names[#names + 1] = item.name
                                item.mentioned = true
                            end
                        end
                        if #names > 0 then
                            lines[#lines + 1] = "The " .. sub.name .. " is open. It contains: " ..
                                                 table.concat(names, ", ") .. "."
                        else
                            lines[#lines + 1] = "The " .. sub.name .. " is open and empty."
                        end
                    end
                    sub.mentioned = true
                end
            end
            obj.mentioned = true
            result[#result + 1] = table.concat(lines, " ")
        end
    end

    -- Stage 4B: Direct containers in the room (on-surfaces and open in-containers).
    for _, key in ipairs(room.objects) do
        local cont = objects[key]
        if cont and cont.contType and not ctx.excluded[key] and not cont.mentioned
                and cont.location == currentRoomKey then
            if cont.contType == "on" then
                local contents = World.contentsOf(key)
                local names = {}
                for _, item in ipairs(contents) do
                    if not item.mentioned then
                        names[#names + 1] = item.name
                        item.mentioned = true
                    end
                end
                if #names > 0 then
                    result[#result + 1] = "On the " .. cont.name .. ": " ..
                                           table.concat(names, ", ") .. "."
                end
                cont.mentioned = true
            elseif cont.contType == "in" and cont.isOpen then
                local contents = World.contentsOf(key)
                local names = {}
                for _, item in ipairs(contents) do
                    if not item.mentioned then
                        names[#names + 1] = item.name
                        item.mentioned = true
                    end
                end
                if #names > 0 then
                    result[#result + 1] = "The " .. cont.name .. " is open. It contains: " ..
                                           table.concat(names, ", ") .. "."
                else
                    result[#result + 1] = "The " .. cont.name .. " is open and empty."
                end
                cont.mentioned = true
            end
            -- Closed in-containers: skip (in misc list or invisible if listed:false).
        end
    end

    if #result == 0 then return nil end
    return table.concat(result, "\n\n")
end

-- Builds the "Exits: north, south." sentence for traversable exits.
-- Blocked connectors (canPass returns false) are hidden from the list.
local function listExits(room)
    local available = {}
    for dir, conn in pairs(room.exits) do
        local passable = not conn.canPass or conn.canPass()
        if passable then
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
