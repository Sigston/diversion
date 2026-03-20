-- lexicon/prepositions.lua
--
-- The list of prepositions the tagger recognises.
-- When the tagger scans a token list, the first known preposition it finds
-- splits the input into two noun phrases:
--   everything before  -> direct object words   (dobjWords)
--   everything after   -> indirect object words  (iobjWords)
--
-- Example: "put the lamp on the table"
--   dobjWords  = { "lamp" }
--   prep       = "on"
--   iobjWords  = { "table" }

local Prepositions = {
    ["in"]      = true,
    ["into"]    = true,
    ["inside"]  = true,
    ["on"]      = true,
    ["onto"]    = true,
    ["with"]    = true,
    ["from"]    = true,
    ["through"] = true,
    ["under"]   = true,
    ["behind"]  = true,
    ["about"]   = true,
}

return Prepositions
