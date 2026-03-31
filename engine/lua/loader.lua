-- engine/lua/loader.lua
--
-- Reads game/data/rooms.json and game/data/objects.json, instantiates the
-- world model, and calls World.load() to make everything live.
--
-- Works both inside LÖVE2D (love.filesystem) and in headless Lua (io.open).
-- Called once at startup before any parser or world operations.

local json     = require("lib.json")
local World    = require("engine.lua.world.world")
local State    = require("engine.lua.world.state")
local Settings = require("engine.lua.world.settings")

local Loader = {}

-- ---------------------------------------------------------------------------
-- readFile — reads a text file, trying love.filesystem first then io.open.
-- ---------------------------------------------------------------------------
local function readFile(path)
    if love and love.filesystem then
        local content = love.filesystem.read(path)
        if content then return content end
    end
    local f, err = io.open(path, "r")
    if not f then error("Loader: cannot read '" .. path .. "': " .. (err or "?")) end
    local content = f:read("*a")
    f:close()
    return content
end

-- ---------------------------------------------------------------------------
-- makeConnector — normalises a raw JSON exit value to a connector table.
--
-- JSON forms:
--   plain string  "room_key"
--     → { dest = "room_key" }  (always traversable)
--
--   object  { dest, condition?, traversalMsg?, blockedMsg? }
--     → connector table; condition "flagCheck" builds a canPass closure.
-- ---------------------------------------------------------------------------
local function makeConnector(raw)
    if type(raw) == "string" then
        return { dest = raw }
    end
    local conn = {
        dest         = raw.dest,
        traversalMsg = raw.traversalMsg,
        blockedMsg   = raw.blockedMsg,
        door         = raw.door,
    }
    if raw.condition then
        if raw.condition.type == "flagCheck" then
            local flag = raw.condition.flag
            local val  = raw.condition.value
            conn.canPass = function() return State.get(flag) == val end
        elseif raw.condition.type == "objectState" then
            local objKey = raw.condition.object
            local prop   = raw.condition.property
            local val    = raw.condition.value
            conn.canPass = function()
                local obj = World.getObject(objKey)
                return obj ~= nil and obj[prop] == val
            end
        end
    end
    return conn
end

-- ---------------------------------------------------------------------------
-- makeDescription — converts a room description from JSON to a function.
--
-- JSON format:
--   plain string         → always returns that string
--   { firstVisit, revisit } → first-visit text once, short text thereafter
--
-- The returned function matches the room description contract:
--   function(self, ctx) → string
-- where self is the room table (carries .visited) and ctx is the world context.
-- ---------------------------------------------------------------------------
local function makeDescription(desc)
    if type(desc) == "string" then
        return function(_self, _ctx) return desc end
    end
    local first   = desc.firstVisit
    local revisit = desc.revisit
    return function(self, _ctx)
        if not self.visited then return first end
        return revisit
    end
end

-- ---------------------------------------------------------------------------
-- Loader.load — public entry point. Call once before World.reset().
-- dataPath: directory containing rooms.json, objects.json, events.json.
--   If omitted, reads game/config.json to determine which game folder to load.
--   Pass "game/data/test" explicitly to load the parser test fixtures.
-- Returns the intro string from events.json (empty string if none).
-- ---------------------------------------------------------------------------

-- The resolved data path from the most recent Loader.load() call.
-- Useful for other callers (e.g. the integrity checker) that need the same path.
Loader.currentPath = nil

function Loader.load(dataPath)
    if not dataPath then
        local ok, src = pcall(readFile, "game/config.json")
        if ok then
            local cfg = json.decode(src)
            dataPath = "game/data/" .. (cfg.game or "diversion")
        else
            dataPath = "game/data/diversion"
        end
    end
    Loader.currentPath = dataPath
    local roomsSrc   = readFile(dataPath .. "/rooms.json")
    local objectsSrc = readFile(dataPath .. "/objects.json")
    local eventsSrc  = readFile(dataPath .. "/events.json")

    local roomsJson   = json.decode(roomsSrc)
    local objectsJson = json.decode(objectsSrc)
    local eventsJson  = json.decode(eventsSrc)

    -- settings.json is optional; missing file leaves all settings at defaults.
    local ok, settingsSrc = pcall(readFile, dataPath .. "/settings.json")
    Settings.load(ok and json.decode(settingsSrc) or {})

    -- Build rooms table
    local rooms = {}
    for key, data in pairs(roomsJson.rooms) do
        local exits = {}
        for dir, raw in pairs(data.exits or {}) do
            exits[dir] = makeConnector(raw)
        end
        rooms[key] = {
            name        = data.name,
            description = makeDescription(data.description),
            exits       = exits,
            objects     = {},
            handlers    = {},
            visited     = false,
        }
        -- Optional room properties
        if data.isLit          ~= nil then rooms[key].isLit          = data.isLit          end
        if data.darkName       ~= nil then rooms[key].darkName       = data.darkName       end
        if data.darkDesc       ~= nil then rooms[key].darkDesc       = data.darkDesc       end
        if data.suppressListing ~= nil then rooms[key].suppressListing = data.suppressListing end
    end

    -- Build objects table
    local objects = {}
    for key, data in pairs(objectsJson) do
        local obj = {
            name        = data.name,
            aliases     = data.aliases    or {},
            adjectives  = data.adjectives or {},
            description = data.description or "",
            location    = data.location,   -- may be nil (JSON null)
            portable    = data.portable,
            handlers    = {},
        }
        -- Optional object properties
        if data.fixed                  ~= nil then obj.fixed                  = data.fixed                  end
        if data.isLockable             ~= nil then obj.isLockable             = data.isLockable             end
        if data.locked                 ~= nil then obj.locked                 = data.locked                 end
        if data.lockKey                ~= nil then obj.lockKey                = data.lockKey                end
        if data.isOpen                 ~= nil then obj.isOpen                 = data.isOpen                 end
        if data.contType               ~= nil then obj.contType               = data.contType               end
        if data.remapIn                ~= nil then obj.remapIn                = data.remapIn                end
        if data.remapOn                ~= nil then obj.remapOn                = data.remapOn                end
        if data.listed                 ~= nil then obj.listed                 = data.listed                 end
        if data.specialDesc            ~= nil then obj.specialDesc            = data.specialDesc            end
        if data.initSpecialDesc        ~= nil then obj.initSpecialDesc        = data.initSpecialDesc        end
        if data.specialDescBeforeContents ~= nil then obj.specialDescBeforeContents = data.specialDescBeforeContents end
        if data.specialDescOrder       ~= nil then obj.specialDescOrder       = data.specialDescOrder       end
        if data.stateDesc ~= nil then
            if type(data.stateDesc) == "table" then
                local openMsg   = data.stateDesc.open
                local closedMsg = data.stateDesc.closed
                obj.stateDesc = function(self)
                    return self.isOpen and openMsg or closedMsg
                end
            else
                obj.stateDesc = data.stateDesc
            end
        end
        if data.visibleInDark          ~= nil then obj.visibleInDark          = data.visibleInDark          end
        if data.readDesc               ~= nil then obj.readDesc               = data.readDesc               end
        if data.scenery                ~= nil then obj.scenery                = data.scenery                end
        if data.notImportantMsg        ~= nil then obj.notImportantMsg        = data.notImportantMsg        end
        if data.otherSide              ~= nil then obj.otherSide              = data.otherSide              end
        objects[key] = obj
    end

    World.load(rooms, objects, roomsJson.startRoom)
    return eventsJson.intro or ""
end

return Loader
