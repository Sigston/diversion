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
-- assignFirstIds — replaces every [FIRST] tag in a string with [FIRST:N]
-- using a module-level counter. Called on all text fields during loading so
-- authors write plain [FIRST] and IDs are assigned automatically.
-- Returns non-string values unchanged.
-- ---------------------------------------------------------------------------
local firstIdCounter = 0
local function assignFirstIds(text)
    if type(text) ~= "string" then return text end
    return (text:gsub("%[FIRST%]", function()
        local id = firstIdCounter
        firstIdCounter = firstIdCounter + 1
        return "[FIRST:" .. id .. "]"
    end))
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
        traversalMsg = assignFirstIds(raw.traversalMsg),
        blockedMsg   = assignFirstIds(raw.blockedMsg),
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
-- ---------------------------------------------------------------------------
-- makeCondition — compiles a JSON condition object to a boolean closure.
-- Condition types match the connector condition schema:
--   { type = "flagCheck",   flag, value }
--   { type = "objectState", object, property, value }
-- ---------------------------------------------------------------------------
local function makeCondition(cond)
    if cond.type == "flagCheck" then
        local flag = cond.flag
        local val  = cond.value
        return function() return State.get(flag) == val end
    elseif cond.type == "objectState" then
        local objKey = cond.object
        local prop   = cond.property
        local val    = cond.value
        return function()
            local o = World.getObject(objKey)
            return o ~= nil and o[prop] == val
        end
    end
    return function() return true end  -- unknown type; always pass
end

-- ---------------------------------------------------------------------------
-- makeDescription — converts a room description from JSON to a function.
--
-- JSON format:
--   plain string             → always returns that string
--   { firstVisit, revisit }  → first-visit text once, short text thereafter
--   array of blocks          → first block whose when[] conditions all pass wins;
--                              a block with no when is an unconditional fallback
--
-- The returned function matches the room description contract:
--   function(self, ctx) → string
-- where self is the room table (carries .visited) and ctx is the world context.
-- ---------------------------------------------------------------------------
local function makeDescription(desc)
    if type(desc) == "string" then
        local text = assignFirstIds(desc)
        return function(self, _ctx) return text end
    end
    -- Array of conditional blocks: first matching when[] wins; no when = fallback.
    if desc[1] ~= nil then
        local blocks = {}
        for _, block in ipairs(desc) do
            local conditions = {}
            for _, cond in ipairs(block.when or {}) do
                conditions[#conditions + 1] = makeCondition(cond)
            end
            blocks[#blocks + 1] = {
                conditions = conditions,
                firstVisit = assignFirstIds(block.firstVisit or ""),
                revisit    = assignFirstIds(block.revisit    or ""),
            }
        end
        return function(self, _ctx)
            for _, block in ipairs(blocks) do
                local ok = true
                for _, cond in ipairs(block.conditions) do
                    if not cond() then ok = false; break end
                end
                if ok then
                    return self.visited and block.revisit or block.firstVisit
                end
            end
            return ""
        end
    end
    local first   = assignFirstIds(desc.firstVisit or "")
    local revisit = assignFirstIds(desc.revisit    or "")
    return function(self, _ctx)
        if not self.visited then return first end
        return revisit
    end
end

-- ---------------------------------------------------------------------------
-- makeObjectDescription — converts an object description from JSON.
-- Plain string → kept as string (assignFirstIds applied).
-- Array of blocks → function(self, ctx) → string; first matching when[] wins.
-- Each block uses "text" (no firstVisit/revisit — objects don't track visits).
-- ---------------------------------------------------------------------------
local function makeObjectDescription(desc)
    if type(desc) ~= "table" or desc[1] == nil then
        return assignFirstIds(desc or "")
    end
    local blocks = {}
    for _, block in ipairs(desc) do
        local conditions = {}
        for _, cond in ipairs(block.when or {}) do
            conditions[#conditions + 1] = makeCondition(cond)
        end
        blocks[#blocks + 1] = {
            conditions = conditions,
            text       = assignFirstIds(block.text or ""),
        }
    end
    return function(_self, _ctx)
        for _, block in ipairs(blocks) do
            local ok = true
            for _, cond in ipairs(block.conditions) do
                if not cond() then ok = false; break end
            end
            if ok then return block.text end
        end
        return ""
    end
end

-- ---------------------------------------------------------------------------
-- makeEffect — compiles a JSON effect object to a void closure.
-- Effect types:
--   { type = "setFlag",       flag, value }
--   { type = "setObjectProp", object, property, value }
-- ---------------------------------------------------------------------------
local function makeEffect(eff)
    if eff.type == "setFlag" then
        local flag = eff.flag
        local val  = eff.value
        return function() State.set(flag, val) end
    elseif eff.type == "setObjectProp" then
        local objKey = eff.object
        local prop   = eff.property
        local val    = eff.value
        return function()
            local o = World.getObject(objKey)
            if o then o[prop] = val end
        end
    end
    return function() end  -- unknown type; no-op
end

-- ---------------------------------------------------------------------------
-- terminalTypeHandler — built-in handler assigned to objects with typeResponses.
--
-- Iterates the object's compiled typeResponses in order. For each rule whose
-- phrases include the typed input and whose conditions all pass, applies effects
-- and returns the rule's text. Falls through to typeDefault if nothing matches.
-- ---------------------------------------------------------------------------
local terminalTypeHandler = {
    verify = function(_obj, intent)
        if not intent.dobjWords or #intent.dobjWords == 0 then
            return { illogicalNow = "Type what?" }
        end
        return { logical = true }
    end,

    action = function(obj, intent)
        local phrase = table.concat(intent.dobjWords, " ")
        for _, rule in ipairs(obj.typeResponses) do
            if rule.phrases[phrase] then
                local ok = true
                for _, cond in ipairs(rule.conditions) do
                    if not cond() then ok = false; break end
                end
                if ok then
                    for _, eff in ipairs(rule.effects) do eff() end
                    if rule.redescribe then
                        local room = World.currentRoom()
                        room.visited = false
                        return rule.text .. "\n\n" .. World.describeCurrentRoom()
                    end
                    return rule.text
                end
            end
        end
        return obj.typeDefault or "The cursor blinks. Nothing happens."
    end,
}

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
        if data.isLit ~= nil then
            if type(data.isLit) == "table" then
                rooms[key].isLit = makeCondition(data.isLit)
            else
                rooms[key].isLit = data.isLit
            end
        end
        if data.darkName       ~= nil then rooms[key].darkName       = data.darkName       end
        if data.darkDesc       ~= nil then rooms[key].darkDesc       = assignFirstIds(data.darkDesc) end
        if data.suppressListing ~= nil then
            if type(data.suppressListing) == "table" then
                rooms[key].suppressListing = makeCondition(data.suppressListing)
            else
                rooms[key].suppressListing = data.suppressListing
            end
        end
        if data.afterTurn ~= nil then
            local compiled = {}
            for _, rule in ipairs(data.afterTurn) do
                local conditions = {}
                for _, cond in ipairs(rule.when or {}) do
                    conditions[#conditions + 1] = makeCondition(cond)
                end
                compiled[#compiled + 1] = {
                    conditions = conditions,
                    text       = assignFirstIds(rule.text),
                }
            end
            rooms[key].afterTurn = compiled
        end
    end

    -- Build objects table
    local objects = {}
    for key, data in pairs(objectsJson) do
        local obj = {
            name        = data.name,
            aliases     = data.aliases    or {},
            adjectives  = data.adjectives or {},
            description = makeObjectDescription(data.description),
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
        if data.openable               ~= nil then obj.openable               = data.openable                       end
        if data.specialDesc            ~= nil then obj.specialDesc            = makeObjectDescription(data.specialDesc) end
        if data.initSpecialDesc        ~= nil then obj.initSpecialDesc        = assignFirstIds(data.initSpecialDesc) end
        if data.specialDescBeforeContents ~= nil then obj.specialDescBeforeContents = data.specialDescBeforeContents end
        if data.specialDescOrder       ~= nil then obj.specialDescOrder       = data.specialDescOrder       end
        if data.stateDesc ~= nil then
            if type(data.stateDesc) == "table" then
                local openMsg   = assignFirstIds(data.stateDesc.open)
                local closedMsg = assignFirstIds(data.stateDesc.closed)
                obj.stateDesc = function(self)
                    return self.isOpen and openMsg or closedMsg
                end
            else
                obj.stateDesc = assignFirstIds(data.stateDesc)
            end
        end
        if data.visibleInDark          ~= nil then obj.visibleInDark          = data.visibleInDark                  end
        if data.readDesc               ~= nil then obj.readDesc               = assignFirstIds(data.readDesc)        end
        if data.scenery                ~= nil then obj.scenery                = data.scenery                         end
        if data.notImportantMsg        ~= nil then obj.notImportantMsg        = assignFirstIds(data.notImportantMsg) end
        if data.otherSide              ~= nil then obj.otherSide              = data.otherSide              end
        -- Compile typeResponses into runtime form and assign built-in handler.
        if data.typeResponses then
            local compiled = {}
            for _, rule in ipairs(data.typeResponses) do
                local phrases = {}
                for _, p in ipairs(rule.phrases) do phrases[p] = true end
                local conditions = {}
                for _, cond in ipairs(rule.when or {}) do
                    conditions[#conditions + 1] = makeCondition(cond)
                end
                local effects = {}
                for _, eff in ipairs(rule.effects or {}) do
                    effects[#effects + 1] = makeEffect(eff)
                end
                compiled[#compiled + 1] = {
                    phrases    = phrases,
                    conditions = conditions,
                    effects    = effects,
                    text       = assignFirstIds(rule.text),
                    redescribe = rule.redescribe or false,
                }
            end
            obj.typeResponses    = compiled
            obj.typeDefault      = assignFirstIds(data.typeDefault)
            obj.handlers["type"] = terminalTypeHandler
        end
        objects[key] = obj
    end

    World.load(rooms, objects, roomsJson.startRoom)

    -- Apply initial flag values from events.json.
    for flag, value in pairs(eventsJson.flags or {}) do
        State.set(flag, value)
    end

    -- Load help content from events.json (process directives in help texts).
    local help = eventsJson.help or {}
    if help.default then help.default = assignFirstIds(help.default) end
    if help.topics then
        for k, v in pairs(help.topics) do
            help.topics[k] = assignFirstIds(v)
        end
    end
    World.loadHelp(help)

    return assignFirstIds(eventsJson.intro or "")
end

return Loader
