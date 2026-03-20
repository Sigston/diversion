-- lexicon/stopwords.lua
--
-- Words stripped from noun phrases by the tagger.
-- These are articles and determiners that carry no meaning for object
-- matching — we don't want "the" or "a" treated as adjectives.
--
-- Example: "take the old iron key"
--   after stopword removal: { "old", "iron", "key" }
--   last token = noun ("key"), preceding tokens = adjectives ("old", "iron")

local Stopwords = {
    ["the"]   = true,
    ["a"]     = true,
    ["an"]    = true,
    ["some"]  = true,
    ["my"]    = true,
    ["your"]  = true,
    ["this"]  = true,
    ["that"]  = true,
}

return Stopwords
