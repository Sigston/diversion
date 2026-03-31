-- parser/resolver.lua
--
-- Stage 3 of the parser pipeline.
-- Turns the noun-phrase word lists in a CommandIntent into actual object
-- references, by matching them against in-scope objects.
--
-- For each noun phrase (dobjWords, iobjWords):
--   1. Get all in-scope objects from World.inScope()
--   2. Filter to those whose name or aliases contain the noun (last word)
--   3. Further filter by adjectives if any were given
--   4. If 0 candidates  -> FAIL_NOT_FOUND
--   5. If 1 candidate   -> assign directly
--   6. If N candidates  -> score with verify(), rank, auto-resolve or FAIL_AMBIGUOUS
--
-- Resolution order for two-object verbs is read from the verb lexicon
-- (resolveFirst = "dobj" or "iobj"). Default is "iobj".
--
-- Verbs with resolveObj = false skip resolution entirely — their dobjWords
-- contain non-object data (e.g. a direction) or are empty.

local World    = require("engine.lua.world.world")
local Verbs    = require("engine.lua.lexicon.verbs")
local Defaults = require("engine.lua.world.defaults")

local Resolver = {}

-- Return values used to signal resolution outcomes to init.lua.
Resolver.FAIL_NOT_FOUND = "FAIL_NOT_FOUND"
Resolver.FAIL_AMBIGUOUS = "FAIL_AMBIGUOUS"

-- ---------------------------------------------------------------------------
-- verifyRank(result)
--
-- Maps a verify() result table to a numeric rank for disambiguation scoring.
-- Higher rank = more preferred candidate.
-- ---------------------------------------------------------------------------
function Resolver.verifyRank(result)
    if not result              then return 100 end
    if result.logical          then return result.rank or 100 end
    if result.dangerous        then return 90  end
    if result.illogicalAlready then return 40  end
    if result.illogicalNow     then return 40  end
    if result.illogical        then return 30  end
    if result.nonObvious       then return 30  end
    return 100
end

-- ---------------------------------------------------------------------------
-- matchObject(wordList, candidates)
--
-- Given a list of words (adjectives + noun) and a list of candidate objects,
-- returns the subset of candidates that match.
--
-- Matching rules:
--   - The last word in wordList is treated as the noun.
--     A candidate matches if noun appears in its name or aliases.
--   - Preceding words are adjectives.
--     A candidate must also match all adjectives against its adjectives list.
--     (If a candidate has no adjectives field, adjectives are ignored.)
-- ---------------------------------------------------------------------------
local function matchObject(wordList, candidates)
    if #wordList == 0 then
        return {}
    end

    local noun       = wordList[#wordList]
    local adjectives = {}
    for i = 1, #wordList - 1 do
        adjectives[#adjectives + 1] = wordList[i]
    end

    local matches = {}
    for _, obj in ipairs(candidates) do
        -- Check noun against the last word of the display name (exact match).
        -- "oil lamp" → last word "lamp"; prevents "desk" matching "desk surface".
        local lastWord = obj.name:match("(%S+)$") or obj.name
        local nounMatch = (lastWord == noun)

        -- Check noun against aliases (exact match) if name didn't match.
        if not nounMatch and obj.aliases then
            for _, alias in ipairs(obj.aliases) do
                if alias == noun then
                    nounMatch = true
                    break
                end
            end
        end

        if nounMatch then
            -- Check adjectives (all must match)
            local adjMatch = true
            if #adjectives > 0 and obj.adjectives then
                for _, adj in ipairs(adjectives) do
                    local found = false
                    for _, objAdj in ipairs(obj.adjectives) do
                        if objAdj == adj then
                            found = true
                            break
                        end
                    end
                    if not found then
                        adjMatch = false
                        break
                    end
                end
            end

            if adjMatch then
                matches[#matches + 1] = obj
            end
        end
    end

    if #matches > 0 then return matches end

    -- Adjective-only fallback: if noun matching found nothing, treat all words
    -- as adjectives. Allows "iron" to select the iron key when disambiguating.
    local adjOnly = {}
    for _, obj in ipairs(candidates) do
        if obj.adjectives then
            local allMatch = true
            for _, word in ipairs(wordList) do
                local found = false
                for _, objAdj in ipairs(obj.adjectives) do
                    if objAdj == word then found = true; break end
                end
                if not found then allMatch = false; break end
            end
            if allMatch then adjOnly[#adjOnly + 1] = obj end
        end
    end
    return adjOnly
end

-- ---------------------------------------------------------------------------
-- getVerifyResult(obj, verb, intent)
--
-- Calls verify() on the most specific handler available for this object/verb.
-- Lookup order: object-specific handler, then default handler.
-- Returns nil if no verify() phase exists (= no objection, rank 100).
-- ---------------------------------------------------------------------------
local function getVerifyResult(obj, verb, intent)
    -- Scenery objects are illogical targets for anything except examine and read.
    if obj.scenery and verb ~= "examine" and verb ~= "read" then
        return { illogical = obj.notImportantMsg or "That's not something you need to worry about." }
    end
    local handler = (obj.handlers and obj.handlers[verb]) or Defaults[verb]
    if handler and handler.verify then
        return handler.verify(obj, intent)
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- resolveNounPhrase(wordList, verb, intent)
--
-- Resolves a single noun phrase to an object reference.
--
-- Returns (success path):
--   obj, false   -- exactly one candidate matched; no announcement needed
--   obj, true    -- auto-resolved from multiple candidates; prepend "(the name)"
--
-- Returns (failure path):
--   FAIL_NOT_FOUND, wordList   -- nothing matched
--   FAIL_AMBIGUOUS, candidates -- multiple candidates tied; ask for clarification
-- ---------------------------------------------------------------------------
local function resolveNounPhrase(wordList, verb, intent)
    if not wordList or #wordList == 0 then
        return nil, nil  -- no noun phrase given; not an error
    end

    local candidates = World.inScope()
    local matches    = matchObject(wordList, candidates)

    if #matches == 0 then
        return Resolver.FAIL_NOT_FOUND, wordList
    end

    if #matches == 1 then
        return matches[1], false  -- single match; no auto-resolve announcement
    end

    -- Multiple candidates: score each with verify() and rank them.
    local scored = {}
    for _, obj in ipairs(matches) do
        local result = getVerifyResult(obj, verb, intent)
        scored[#scored + 1] = { obj = obj, rank = Resolver.verifyRank(result) }
    end

    local best = 0
    for _, s in ipairs(scored) do
        if s.rank > best then best = s.rank end
    end

    local top = {}
    for _, s in ipairs(scored) do
        if s.rank == best then
            top[#top + 1] = s.obj
        end
    end

    if #top == 1 then
        return top[1], true  -- unique highest rank: auto-resolve
    end

    return Resolver.FAIL_AMBIGUOUS, top  -- tied: ask for clarification
end

-- ---------------------------------------------------------------------------
-- resolve(intent)
--
-- Fills in dobjRef and iobjRef on the intent table.
--
-- Returns two values: result, extra
--
--   On success:
--     result = intent (fully or partially resolved)
--     extra  = { dobj = obj|nil, iobj = obj|nil }
--              non-nil fields indicate auto-resolved objects (need announcement)
--
--   On FAIL_NOT_FOUND:
--     result = Resolver.FAIL_NOT_FOUND
--     extra  = { words = wordList }
--
--   On FAIL_AMBIGUOUS:
--     result = Resolver.FAIL_AMBIGUOUS
--     extra  = { candidates, which, intent }
--              'intent' has any previously resolved refs already set
-- ---------------------------------------------------------------------------
function Resolver.resolve(intent)
    local verbEntry = Verbs[intent.verb]

    -- If this verb doesn't resolve objects, pass the intent straight through.
    if not verbEntry or not verbEntry.resolveObj then
        return intent, {}
    end

    local resolveFirst = verbEntry.resolveFirst or "iobj"
    local autoInfo     = {}  -- populated when auto-resolving from multiple candidates

    -- Resolve one noun phrase; update autoInfo; return error info on failure.
    local function resolvePhrase(wordList, which)
        local obj, extra = resolveNounPhrase(wordList, intent.verb, intent)
        if obj == Resolver.FAIL_NOT_FOUND then
            return nil, Resolver.FAIL_NOT_FOUND, { words = extra }
        end
        if obj == Resolver.FAIL_AMBIGUOUS then
            -- extra is the tied candidate list
            return nil, Resolver.FAIL_AMBIGUOUS,
                   { candidates = extra, which = which, intent = intent }
        end
        if extra == true then
            autoInfo[which] = obj  -- flag for auto-resolve announcement
        end
        return obj, nil, nil
    end

    if resolveFirst == "iobj" then
        local iobjRef, err, data = resolvePhrase(intent.iobjWords, "iobj")
        if err then return err, data end
        intent.iobjRef = iobjRef  -- set before resolving dobj so it's in intent if dobj fails
        local dobjRef, err2, data2 = resolvePhrase(intent.dobjWords, "dobj")
        if err2 then return err2, data2 end
        intent.dobjRef = dobjRef
    else
        local dobjRef, err, data = resolvePhrase(intent.dobjWords, "dobj")
        if err then return err, data end
        intent.dobjRef = dobjRef  -- set before resolving iobj so it's in intent if iobj fails
        local iobjRef, err2, data2 = resolvePhrase(intent.iobjWords, "iobj")
        if err2 then return err2, data2 end
        intent.iobjRef = iobjRef
    end

    return intent, autoInfo
end

-- Exposed for use in handleClarification: filters a candidate list using the
-- same adjective+noun matching as the full resolver.
function Resolver.filterCandidates(wordList, candidates)
    return matchObject(wordList, candidates)
end

return Resolver
