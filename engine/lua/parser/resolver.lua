-- parser/resolver.lua
--
-- Stage 3 of the parser pipeline.
-- Turns the noun-phrase word lists in a CommandIntent into actual object
-- references, by matching them against in-scope objects.
--
-- Milestone 1a: simple resolver — takes the first matching object.
-- Milestone 1b: full resolver — verify() scoring and disambiguation.
--
-- For each noun phrase (dobjWords, iobjWords):
--   1. Get all in-scope objects from World.inScope()
--   2. Filter to those whose name or aliases contain the noun (last word)
--   3. Further filter by adjectives if any were given
--   4. If 0 matches -> FAIL_NOT_FOUND
--   5. If 1+ matches -> take the first one (M1a; M1b will score these)
--
-- Resolution order for two-object verbs is read from the verb lexicon
-- (resolveFirst = "dobj" or "iobj"). Default is "iobj".
--
-- Verbs with resolveObj = false skip resolution entirely — their dobjWords
-- contain non-object data (e.g. a direction) or are empty.

local World = require("engine.lua.world.world")
local Verbs = require("engine.lua.lexicon.verbs")

local Resolver = {}

-- Return values used to signal resolution outcomes to the caller.
Resolver.FAIL_NOT_FOUND = "FAIL_NOT_FOUND"
Resolver.FAIL_AMBIGUOUS = "FAIL_AMBIGUOUS"   -- used in Milestone 1b

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
        -- Check noun against name
        local nounMatch = obj.name:find(noun, 1, true)

        -- Check noun against aliases if name didn't match
        if not nounMatch and obj.aliases then
            for _, alias in ipairs(obj.aliases) do
                if alias:find(noun, 1, true) then
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

    return matches
end

-- ---------------------------------------------------------------------------
-- resolveNounPhrase(wordList)
--
-- Resolves a single noun phrase to an object reference.
-- Returns the object, or Resolver.FAIL_NOT_FOUND.
-- ---------------------------------------------------------------------------
local function resolveNounPhrase(wordList)
    if not wordList or #wordList == 0 then
        return nil  -- no noun phrase given; not an error
    end

    local candidates = World.inScope()
    local matches    = matchObject(wordList, candidates)

    if #matches == 0 then
        return Resolver.FAIL_NOT_FOUND
    end

    -- Milestone 1a: just take the first match.
    -- Milestone 1b: score with verify() and handle ties.
    return matches[1]
end

-- ---------------------------------------------------------------------------
-- resolve(intent)
--
-- Fills in dobjRef and iobjRef on the intent table.
-- Returns the intent on success, or a fail constant on failure.
-- ---------------------------------------------------------------------------
function Resolver.resolve(intent)
    local verbEntry = Verbs[intent.verb]

    -- If this verb doesn't resolve objects, pass the intent straight through.
    if not verbEntry or not verbEntry.resolveObj then
        return intent
    end

    -- Determine resolution order from the lexicon.
    local resolveFirst = verbEntry.resolveFirst or "iobj"

    local function resolvePhrase(wordList)
        local result = resolveNounPhrase(wordList)
        if result == Resolver.FAIL_NOT_FOUND then
            return nil, Resolver.FAIL_NOT_FOUND
        end
        return result, nil
    end

    if resolveFirst == "iobj" then
        -- Resolve indirect object first, then direct object.
        local iobjRef, err = resolvePhrase(intent.iobjWords)
        if err then return err end
        local dobjRef, err2 = resolvePhrase(intent.dobjWords)
        if err2 then return err2 end
        intent.iobjRef = iobjRef
        intent.dobjRef = dobjRef
    else
        -- Resolve direct object first, then indirect object.
        local dobjRef, err = resolvePhrase(intent.dobjWords)
        if err then return err end
        local iobjRef, err2 = resolvePhrase(intent.iobjWords)
        if err2 then return err2 end
        intent.dobjRef = dobjRef
        intent.iobjRef = iobjRef
    end

    return intent
end

return Resolver
