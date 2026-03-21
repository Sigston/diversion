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
-- ---------------------------------------------------------------------------
function Loader.load()
    local roomsSrc   = readFile("game/data/rooms.json")
    local objectsSrc = readFile("game/data/objects.json")

    local roomsJson   = json.decode(roomsSrc)
    local objectsJson = json.decode(objectsSrc)

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
        -- Optional properties — only present when set in JSON
        if data.fixed   ~= nil then obj.fixed   = data.fixed   end
        if data.locked  ~= nil then obj.locked  = data.locked  end
        if data.lockKey ~= nil then obj.lockKey = data.lockKey end
        objects[key] = obj
    end

    World.load(rooms, objects, roomsJson.startRoom)
end

return Loader
