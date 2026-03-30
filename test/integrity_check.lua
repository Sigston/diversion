-- test/integrity_check.lua
--
-- Validates game data JSON files for structural and logical correctness.
--
-- Usage:
--   Standalone:  lua test/integrity_check.lua [data-path]
--                (data-path defaults to "game/data/diversion")
--   As module:   local Check = require("test.integrity_check")
--                local errors, warnings = Check.run("game/data/diversion", printFn)
--
-- printFn receives plain strings. The caller applies colour if desired.
-- Returns (errorCount, warningCount).

local json = require("lib.json")

local IntegrityCheck = {}

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------
local VALID_DIRECTIONS = {
    north=true, south=true, east=true, west=true,
    up=true, down=true, ["in"]=true, out=true,
}

local REVERSE_DIRECTION = {
    north="south", south="north",
    east="west",  west="east",
    up="down",    down="up",
    ["in"]="out", out="in",
}

-- ---------------------------------------------------------------------------
-- readFile — tries love.filesystem then io.open (mirrors loader.lua).
-- ---------------------------------------------------------------------------
local function readFile(path)
    if love and love.filesystem then
        local content = love.filesystem.read(path)
        if content then return content, nil end
    end
    local f, e = io.open(path, "r")
    if not f then return nil, e end
    local content = f:read("*a")
    f:close()
    return content, nil
end

-- ---------------------------------------------------------------------------
-- IntegrityCheck.run
-- ---------------------------------------------------------------------------
function IntegrityCheck.run(dataPath, printFn)
    dataPath = dataPath or "game/data/diversion"
    printFn  = printFn  or print

    local errorCount   = 0
    local warningCount = 0

    local function err(msg)
        printFn("ERROR: " .. msg)
        errorCount = errorCount + 1
    end

    local function warn(msg)
        printFn("WARNING: " .. msg)
        warningCount = warningCount + 1
    end

    -- ----------------------------------------------------------------
    -- Load and parse
    -- ----------------------------------------------------------------
    local roomsSrc,   roomsReadErr   = readFile(dataPath .. "/rooms.json")
    local objectsSrc, objectsReadErr = readFile(dataPath .. "/objects.json")

    if not roomsSrc then
        err("Cannot read rooms.json: " .. (roomsReadErr or "?"))
        return errorCount, warningCount
    end
    if not objectsSrc then
        err("Cannot read objects.json: " .. (objectsReadErr or "?"))
        return errorCount, warningCount
    end

    local ok, roomsData = pcall(json.decode, roomsSrc)
    if not ok then
        err("rooms.json invalid JSON: " .. tostring(roomsData))
        return errorCount, warningCount
    end
    local ok2, objectsData = pcall(json.decode, objectsSrc)
    if not ok2 then
        err("objects.json invalid JSON: " .. tostring(objectsData))
        return errorCount, warningCount
    end

    local rooms     = roomsData.rooms or {}
    local objects   = objectsData     or {}
    local startRoom = roomsData.startRoom

    -- ----------------------------------------------------------------
    -- Helper: walk an object's location chain to find its room.
    -- Returns room key, "inventory", or nil.
    -- Second return is an error string on failure.
    -- ----------------------------------------------------------------
    local function resolveRoom(objKey, visited)
        visited = visited or {}
        if visited[objKey] then return nil, "circular" end
        visited[objKey] = true
        local obj = objects[objKey]
        if not obj then return nil, "object not found: " .. objKey end
        local loc = obj.location
        if loc == nil          then return nil end
        if loc == "inventory"  then return "inventory" end
        if rooms[loc]          then return loc end
        if objects[loc]        then return resolveRoom(loc, visited) end
        return nil, "invalid location '" .. tostring(loc) .. "'"
    end

    -- ----------------------------------------------------------------
    -- Helper: get the dest from a raw exit value.
    -- ----------------------------------------------------------------
    local function exitDest(raw)
        if type(raw) == "string" then return raw end
        if type(raw) == "table"  then return raw.dest end
    end

    -- ----------------------------------------------------------------
    -- 1. startRoom
    -- ----------------------------------------------------------------
    if not startRoom then
        err("rooms.json: missing 'startRoom'")
    elseif not rooms[startRoom] then
        err("rooms.json: startRoom '" .. startRoom .. "' does not exist")
    end

    -- ----------------------------------------------------------------
    -- 2. Room schema and exit checks
    -- ----------------------------------------------------------------
    for key, room in pairs(rooms) do
        local r = "Room '" .. key .. "': "

        -- name
        if type(room.name) ~= "string" or room.name == "" then
            err(r .. "missing or empty 'name'")
        end

        -- description
        if room.description == nil then
            err(r .. "missing 'description'")
        elseif type(room.description) == "table" then
            if type(room.description.firstVisit) ~= "string" then
                err(r .. "description.firstVisit must be a string")
            end
            if type(room.description.revisit) ~= "string" then
                err(r .. "description.revisit must be a string")
            end
        elseif type(room.description) ~= "string" then
            err(r .. "'description' must be a string or {firstVisit, revisit} object")
        end

        -- darkness
        if room.isLit == false and not room.darkDesc then
            warn(r .. "isLit is false but 'darkDesc' is absent (generic fallback will be used)")
        end

        -- exits
        if type(room.exits) ~= "table" then
            err(r .. "missing or invalid 'exits'")
        else
            if next(room.exits) == nil then
                warn(r .. "has no exits (dead end)")
            end

            for dir, raw in pairs(room.exits) do
                local e = r .. "exit '" .. dir .. "': "

                if not VALID_DIRECTIONS[dir] then
                    err(e .. "unknown direction")
                end

                local dest, door, condition, blockedMsg
                local validShape = true

                if type(raw) == "string" then
                    dest = raw
                elseif type(raw) == "table" then
                    dest       = raw.dest
                    door       = raw.door
                    condition  = raw.condition
                    blockedMsg = raw.blockedMsg
                else
                    err(e .. "must be a room key string or a connector object")
                    validShape = false
                end

                if validShape then
                    -- dest
                    if type(dest) ~= "string" or dest == "" then
                        err(e .. "missing or empty 'dest'")
                    elseif not rooms[dest] then
                        err(e .. "dest '" .. dest .. "' is not a known room")
                    end

                    -- door
                    if door ~= nil then
                        if not objects[door] then
                            err(e .. "door '" .. door .. "' is not a known object")
                        else
                            if objects[door].isOpen == nil then
                                err(e .. "door object '" .. door .. "' has no 'isOpen' property")
                            end
                            local doorRoom = resolveRoom(door)
                            if doorRoom ~= key then
                                warn(e .. "door '" .. door ..
                                     "' is not located in this room (found in '" ..
                                     tostring(doorRoom) .. "')")
                            end
                            local otherSideKey = objects[door].otherSide
                            if otherSideKey and type(dest) == "string" and rooms[dest] then
                                local otherRoom = resolveRoom(otherSideKey)
                                if otherRoom ~= dest then
                                    warn(e .. "door.otherSide '" .. otherSideKey ..
                                         "' is not located in dest room '" .. dest ..
                                         "' (found in '" .. tostring(otherRoom) .. "')")
                                end
                            end
                        end
                    end

                    -- condition
                    if condition ~= nil then
                        if not blockedMsg then
                            warn(e .. "has a condition but no 'blockedMsg' (player gets generic message)")
                        end
                        if condition.type == "flagCheck" then
                            if not condition.flag then
                                err(e .. "flagCheck condition missing 'flag'")
                            end
                            if condition.value == nil then
                                err(e .. "flagCheck condition missing 'value'")
                            end
                        elseif condition.type == "objectState" then
                            if not condition.object then
                                err(e .. "objectState condition missing 'object'")
                            elseif not objects[condition.object] then
                                err(e .. "objectState condition.object '" ..
                                    condition.object .. "' is not a known object")
                            else
                                local prop = condition.property
                                if not prop then
                                    err(e .. "objectState condition missing 'property'")
                                elseif objects[condition.object][prop] == nil then
                                    warn(e .. "objectState condition property '" .. prop ..
                                         "' is not defined on object '" ..
                                         condition.object .. "'")
                                end
                            end
                            if condition.value == nil then
                                err(e .. "objectState condition missing 'value'")
                            end
                        else
                            warn(e .. "unknown condition type '" ..
                                 tostring(condition.type) .. "'")
                        end
                    end
                end
            end
        end

    end

    -- ----------------------------------------------------------------
    -- 3. Object schema checks
    -- ----------------------------------------------------------------
    for key, obj in pairs(objects) do
        local o = "Object '" .. key .. "': "

        if type(obj.name) ~= "string" or obj.name == "" then
            err(o .. "missing or empty 'name'")
        end
        if type(obj.description) ~= "string" then
            err(o .. "missing or non-string 'description'")
        end

        -- location
        local loc = obj.location
        if loc ~= nil and loc ~= "inventory" then
            if not rooms[loc] and not objects[loc] then
                err(o .. "location '" .. tostring(loc) ..
                    "' is not a known room or object key")
            end
        end

        -- otherSide symmetry
        if obj.otherSide ~= nil then
            if not objects[obj.otherSide] then
                err(o .. "otherSide '" .. obj.otherSide .. "' is not a known object")
            elseif objects[obj.otherSide].otherSide ~= key then
                err(o .. "otherSide '" .. obj.otherSide ..
                    "' does not point back to '" .. key .. "'")
            end
        end

        -- lockKey / isLockable
        if obj.lockKey ~= nil and not objects[obj.lockKey] then
            err(o .. "lockKey '" .. obj.lockKey .. "' is not a known object")
        end
        if obj.isLockable and obj.lockKey == nil then
            warn(o .. "isLockable is true but no 'lockKey' is defined")
        end
        if obj.isLockable and obj.locked == nil then
            warn(o .. "isLockable is true but 'locked' state is not defined")
        end
        if obj.locked ~= nil and not obj.isLockable then
            warn(o .. "has 'locked' but 'isLockable' is not true")
        end

        -- contType
        if obj.contType ~= nil and obj.contType ~= "in" and obj.contType ~= "on" then
            err(o .. "contType must be 'in' or 'on', got '" .. tostring(obj.contType) .. "'")
        end

        -- remapIn / remapOn targets
        if obj.remapIn ~= nil then
            if not objects[obj.remapIn] then
                err(o .. "remapIn '" .. obj.remapIn .. "' is not a known object")
            elseif objects[obj.remapIn].contType ~= "in" then
                err(o .. "remapIn target '" .. obj.remapIn .. "' does not have contType 'in'")
            end
        end
        if obj.remapOn ~= nil then
            if not objects[obj.remapOn] then
                err(o .. "remapOn '" .. obj.remapOn .. "' is not a known object")
            elseif objects[obj.remapOn].contType ~= "on" then
                err(o .. "remapOn target '" .. obj.remapOn .. "' does not have contType 'on'")
            end
        end

        -- stateDesc {open, closed} requires isOpen
        if type(obj.stateDesc) == "table" then
            if obj.stateDesc.open == nil or obj.stateDesc.closed == nil then
                err(o .. "stateDesc object must have both 'open' and 'closed' keys")
            end
            if obj.isOpen == nil then
                err(o .. "stateDesc {open/closed} requires 'isOpen' to be defined on this object")
            end
        end

        -- isOpen without contType or otherSide
        if obj.isOpen ~= nil and obj.contType == nil and obj.otherSide == nil then
            warn(o .. "has 'isOpen' but neither 'contType' nor 'otherSide' — is this intentional?")
        end

        -- initSpecialDesc without specialDesc
        if obj.initSpecialDesc ~= nil and obj.specialDesc == nil then
            warn(o .. "has 'initSpecialDesc' but no 'specialDesc'")
        end

        -- circular container chain
        local _, circErr = resolveRoom(key)
        if circErr == "circular" then
            err(o .. "circular location chain detected")
        end
    end

    -- ----------------------------------------------------------------
    -- 4. Duplicate names / aliases within the same room
    --    Built from object location properties (not a room objects array).
    -- ----------------------------------------------------------------
    local roomObjMap = {}
    for objKey, obj in pairs(objects) do
        local loc = obj.location
        if loc and rooms[loc] then
            if not roomObjMap[loc] then roomObjMap[loc] = {} end
            roomObjMap[loc][#roomObjMap[loc]+1] = objKey
        end
    end

    for roomKey, objList in pairs(roomObjMap) do
        local seen = {}
        for _, objKey in ipairs(objList) do
            local obj = objects[objKey]
            if obj then
                local terms = {}
                if type(obj.name) == "string" then
                    terms[#terms+1] = obj.name:lower()
                end
                if type(obj.aliases) == "table" then
                    for _, a in ipairs(obj.aliases) do
                        terms[#terms+1] = a:lower()
                    end
                end
                for _, term in ipairs(terms) do
                    if seen[term] and seen[term] ~= objKey then
                        warn("Room '" .. roomKey .. "': objects '" .. seen[term] ..
                             "' and '" .. objKey ..
                             "' share the name/alias '" .. term .. "'")
                    else
                        seen[term] = objKey
                    end
                end
            end
        end
    end

    -- ----------------------------------------------------------------
    -- 5. Graph connectivity: every room reachable from startRoom
    --    (ignoring conditions — checks that exits exist, not that they
    --    are unblocked at game start)
    -- ----------------------------------------------------------------
    if startRoom and rooms[startRoom] then
        local visited_rooms = { [startRoom] = true }
        local queue = { startRoom }
        while #queue > 0 do
            local current = table.remove(queue, 1)
            local room = rooms[current]
            if room and type(room.exits) == "table" then
                for _, raw in pairs(room.exits) do
                    local dest = exitDest(raw)
                    if dest and rooms[dest] and not visited_rooms[dest] then
                        visited_rooms[dest] = true
                        queue[#queue+1] = dest
                    end
                end
            end
        end
        for roomKey in pairs(rooms) do
            if not visited_rooms[roomKey] then
                warn("Room '" .. roomKey ..
                     "' is unreachable from startRoom '" .. startRoom .. "'")
            end
        end
    end

    -- ----------------------------------------------------------------
    -- 6. Reciprocal exits
    -- ----------------------------------------------------------------
    for roomKey, room in pairs(rooms) do
        if type(room.exits) == "table" then
            for dir, raw in pairs(room.exits) do
                local dest = exitDest(raw)
                local rev  = REVERSE_DIRECTION[dir]
                if dest and rooms[dest] and rev then
                    local destExits = rooms[dest].exits
                    if type(destExits) == "table" then
                        local reverseRaw = destExits[rev]
                        if not reverseRaw then
                            warn("Room '" .. roomKey .. "' exits " .. dir ..
                                 " to '" .. dest .. "', but '" .. dest ..
                                 "' has no '" .. rev .. "' exit back")
                        else
                            local backDest = exitDest(reverseRaw)
                            if backDest ~= roomKey then
                                warn("Room '" .. roomKey .. "' exits " .. dir ..
                                     " to '" .. dest .. "', but '" .. dest ..
                                     "'s '" .. rev .. "' exit goes to '" ..
                                     tostring(backDest) .. "' instead")
                            end
                        end
                    end
                end
            end
        end
    end

    -- ----------------------------------------------------------------
    -- Summary
    -- ----------------------------------------------------------------
    printFn("")
    if errorCount == 0 and warningCount == 0 then
        printFn("All checks passed.")
    else
        printFn(errorCount   .. " error"   .. (errorCount   ~= 1 and "s" or "") ..
                ", " ..
                warningCount .. " warning" .. (warningCount ~= 1 and "s" or ""))
    end

    return errorCount, warningCount
end

return IntegrityCheck
