-- parser/tagger.lua
--
-- Stage 2 of the parser pipeline.
-- Takes a token list from the tokeniser and produces a partial CommandIntent.
--
-- A CommandIntent is a table with these fields (see CLAUDE.md for full spec):
--   verb       string           canonical verb ("examine", "take", etc.)
--   dobjWords  {string}         words describing the direct object
--   prep       string|nil       preposition ("in", "on", "with", etc.)
--   iobjWords  {string}|nil     words describing the indirect object
--   dobjRef    nil              filled in later by the resolver
--   iobjRef    nil              filled in later by the resolver
--
-- The tagger uses the lexicon tables only. It never touches the world model.
--
-- Algorithm:
--   1. Look up the first token in the verb synonym map -> canonical verb
--   2. Scan remaining tokens for a known preposition
--   3. Split remaining tokens into dobj span (before prep) and iobj span (after)
--   4. Strip stopwords from each span
--
-- TODO (Milestone 1b): check two-token combinations first so that multi-word
-- synonyms like "look at" and "pick up" are recognised before single tokens.

local Verbs        = require("engine.lua.lexicon.verbs")
local Prepositions = require("engine.lua.lexicon.prepositions")
local Stopwords    = require("engine.lua.lexicon.stopwords")

local Tagger = {}

-- Removes stopwords from a list of tokens.
-- e.g. { "the", "old", "iron", "key" } -> { "old", "iron", "key" }
local function stripStopwords(span)
    local result = {}
    for _, word in ipairs(span) do
        if not Stopwords[word] then
            result[#result + 1] = word
        end
    end
    return result
end

function Tagger.tag(tokens)
    -- Empty input produces nothing.
    if #tokens == 0 then
        return nil
    end

    -- Step 1: look up the first token in the synonym map.
    -- synonymMap["get"] = "take", synonymMap["x"] = "examine", etc.
    -- Returns nil if the word isn't a known verb.
    local verb = Verbs.synonymMap[tokens[1]]
    if not verb then
        return nil  -- unrecognised verb; caller handles this
    end

    -- Step 2: collect all tokens after the verb.
    local rest = {}
    for i = 2, #tokens do
        rest[#rest + 1] = tokens[i]
    end

    -- Step 3: scan for the first known preposition.
    -- e.g. in "put the lamp on the table", prepIndex = 3 (the "on")
    local prepIndex = nil
    local prep      = nil
    for i, token in ipairs(rest) do
        if Prepositions[token] then
            prepIndex = i
            prep      = token
            break
        end
    end

    -- Step 4: split into dobj span and iobj span around the preposition.
    -- If no preposition found, everything goes into the dobj span.
    local dobjSpan = {}
    local iobjSpan = nil

    if prepIndex then
        for i = 1, prepIndex - 1 do
            dobjSpan[#dobjSpan + 1] = rest[i]
        end
        iobjSpan = {}
        for i = prepIndex + 1, #rest do
            iobjSpan[#iobjSpan + 1] = rest[i]
        end
    else
        dobjSpan = rest
    end

    -- Step 5: strip stopwords from each span.
    -- dobjWords and iobjWords are what the resolver uses to match objects.
    -- Exception: if the verb has rawDobj = true, preserve the dobj span verbatim
    -- (the typed phrase is free text and must not have words removed).
    local verbEntry = Verbs[verb]
    local dobjWords = (verbEntry and verbEntry.rawDobj) and dobjSpan or stripStopwords(dobjSpan)
    local iobjWords = iobjSpan and stripStopwords(iobjSpan) or nil

    return {
        verb      = verb,
        dobjWords = dobjWords,
        prep      = prep,
        iobjWords = iobjWords,
        dobjRef   = nil,    -- filled in by resolver
        iobjRef   = nil,    -- filled in by resolver
    }
end

return Tagger
