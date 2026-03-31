-- engine/lua/world/text_processor.lua
--
-- Processes inline text directives in any string before display.
--
-- Directives:
--   [FIRST:N]...[FIRST END]        — shows content only the first time this
--                                    block is encountered in a session; omitted
--                                    on subsequent displays. IDs are assigned
--                                    by the loader at load time so authors
--                                    write plain [FIRST] with no ID.
--   [ONE OF]...[OR]...[ONE OF END] — picks one option at random each time.
--
-- Call TextProcessor.process(text) in the parser's process() function so that
-- all output — room descriptions, object descriptions, handler responses — is
-- processed before reaching the terminal. This also makes directives testable
-- through the normal Parser.process() path.

local State = require("engine.lua.world.state")

local TextProcessor = {}

-- ---------------------------------------------------------------------------
-- processFirst — resolves [FIRST:N]...[FIRST END] blocks.
-- Uses string.find with plain=true for the closing tag so that multiline
-- content is handled correctly (Lua's '.' does not match newlines).
-- ---------------------------------------------------------------------------
local function processFirst(text)
    local result = {}
    local pos = 1
    while true do
        local s, e, id = text:find("%[FIRST:(%d+)%]", pos)
        if not s then
            result[#result + 1] = text:sub(pos)
            break
        end
        result[#result + 1] = text:sub(pos, s - 1)
        local cs, ce = text:find("[FIRST END]", e + 1, true)
        if not cs then
            -- Malformed: no closing tag — include everything from here.
            result[#result + 1] = text:sub(s)
            break
        end
        local content = text:sub(e + 1, cs - 1)
        local key = "_first_" .. id
        if not State.get(key) then
            State.set(key, true)
            result[#result + 1] = content
        end
        pos = ce + 1
    end
    return table.concat(result)
end

-- ---------------------------------------------------------------------------
-- processOneOf — resolves [ONE OF]...[OR]...[ONE OF END] blocks.
-- All string.find calls use plain=true so bracket characters are literal.
-- ---------------------------------------------------------------------------
local function processOneOf(text)
    local result = {}
    local pos = 1
    while true do
        local s, e = text:find("[ONE OF]", pos, true)
        if not s then
            result[#result + 1] = text:sub(pos)
            break
        end
        result[#result + 1] = text:sub(pos, s - 1)
        local cs, ce = text:find("[ONE OF END]", e + 1, true)
        if not cs then
            -- Malformed: no closing tag — include everything from here.
            result[#result + 1] = text:sub(s)
            break
        end
        local inner = text:sub(e + 1, cs - 1)
        -- Split inner content on [OR] separators.
        local options = {}
        local opos = 1
        while true do
            local os, oe = inner:find("[OR]", opos, true)
            if not os then
                options[#options + 1] = inner:sub(opos)
                break
            end
            options[#options + 1] = inner:sub(opos, os - 1)
            opos = oe + 1
        end
        result[#result + 1] = options[math.random(#options)] or ""
        pos = ce + 1
    end
    return table.concat(result)
end

-- ---------------------------------------------------------------------------
-- TextProcessor.process — apply all directives in order.
-- [FIRST] resolved before [ONE OF] so a [ONE OF] inside a [FIRST] block
-- is only evaluated when the block is shown.
-- ---------------------------------------------------------------------------
function TextProcessor.process(text)
    text = processFirst(text)
    text = processOneOf(text)
    return text
end

return TextProcessor
