-- engine/lua/loader.lua
--
-- Reads game/data/rooms.json and game/data/objects.json, instantiates the
-- world model, and calls World.load() to make everything live.
--
-- Works both inside LÖVE2D (love.filesystem) and in headless Lua (io.open).
-- Called once at startup before any parser or world operations.

local json  = require("lib.json")
local World = require("engine.lua.world.world")

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
-- Returns the intro string from events.json (empty string if none).
-- ---------------------------------------------------------------------------
function Loader.load()
    local roomsSrc   = readFile("game/data/rooms.json")
    local objectsSrc = readFile("game/data/objects.json")
    local eventsSrc  = readFile("game/data/events.json")

    local roomsJson   = json.decode(roomsSrc)
    local objectsJson = json.decode(objectsSrc)
    local eventsJson  = json.decode(eventsSrc)

    -- Build rooms table
    local rooms = {}
    for key, data in pairs(roomsJson.rooms) do
        rooms[key] = {
            name        = data.name,
            description = makeDescription(data.description),
            exits       = data.exits    or {},
            objects     = data.objects  or {},
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
        if data.locked                 ~= nil then obj.locked                 = data.locked                 end
        if data.lockKey                ~= nil then obj.lockKey                = data.lockKey                end
        if data.listed                 ~= nil then obj.listed                 = data.listed                 end
        if data.specialDesc            ~= nil then obj.specialDesc            = data.specialDesc            end
        if data.initSpecialDesc        ~= nil then obj.initSpecialDesc        = data.initSpecialDesc        end
        if data.specialDescBeforeContents ~= nil then obj.specialDescBeforeContents = data.specialDescBeforeContents end
        if data.specialDescOrder       ~= nil then obj.specialDescOrder       = data.specialDescOrder       end
        if data.stateDesc              ~= nil then obj.stateDesc              = data.stateDesc              end
        objects[key] = obj
    end

    World.load(rooms, objects, roomsJson.startRoom)
    return eventsJson.intro or ""
end

return Loader
