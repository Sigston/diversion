-- parser/tokeniser.lua
--
-- Stage 1 of the parser pipeline.
-- Takes a raw input string and returns a list of lowercase tokens.
--
-- Steps:
--   1. Lowercase the whole string
--   2. Strip punctuation (keep only letters, digits, spaces)
--   3. Split on whitespace
--
-- The tokeniser does not consult the lexicon. It knows nothing about
-- verbs, objects, or game state. It just cleans up the raw string.
--
-- Examples:
--   "Take the Iron Key!"  -> { "take", "the", "iron", "key" }
--   "PUT lamp ON table"   -> { "put", "lamp", "on", "table" }
--   "  look  "            -> { "look" }

local Tokeniser = {}

function Tokeniser.tokenise(input)
    -- Step 1: lowercase
    local s = input:lower()

    -- Step 2: strip punctuation.
    -- The pattern [^%a%d%s] means "any character that is NOT
    -- a letter (%a), digit (%d), or whitespace (%s)".
    -- We replace all such characters with nothing.
    s = s:gsub("[^%a%d%s]", "")

    -- Step 3: split on whitespace into a token list.
    -- The pattern %S+ means "one or more non-whitespace characters".
    -- gmatch returns an iterator; we collect the results into a table.
    local tokens = {}
    for token in s:gmatch("%S+") do
        tokens[#tokens + 1] = token
    end

    return tokens
end

return Tokeniser
