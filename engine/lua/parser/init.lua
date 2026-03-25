-- parser/init.lua
--
-- Entry point for the parser pipeline.
-- Chains the four stages together and owns the disambiguation state machine.
--
-- States:
--   NORMAL        default; processes new commands
--   AWAIT_CLARIFY waiting for the player to pick from a list of candidates
--
-- Public interface:
--   Parser.process(rawInput) -> string
--   Parser.reset()           -> resets FSM state (call between test runs)

local Tokeniser  = require("engine.lua.parser.tokeniser")
local Tagger     = require("engine.lua.parser.tagger")
local Resolver   = require("engine.lua.parser.resolver")
local Dispatcher = require("engine.lua.parser.dispatcher")
local Stopwords  = require("engine.lua.lexicon.stopwords")

local Parser = {}

-- FSM state
local state   = "NORMAL"
local pending = nil   -- { intent, candidates, which } stored during AWAIT_CLARIFY

-- ---------------------------------------------------------------------------
-- buildClarificationQuestion(candidates)
--
-- Formats a "which do you mean" question from a list of candidate objects.
-- ---------------------------------------------------------------------------
local function buildClarificationQuestion(candidates)
    if #candidates == 2 then
        return "Which do you mean, the " .. candidates[1].name ..
               " or the " .. candidates[2].name .. "?"
    end
    local parts = {}
    for i, c in ipairs(candidates) do
        if i < #candidates then
            parts[#parts + 1] = "the " .. c.name
        else
            parts[#parts + 1] = "or the " .. c.name
        end
    end
    return "Which do you mean, " .. table.concat(parts, ", ") .. "?"
end

-- ---------------------------------------------------------------------------
-- handleClarification(rawInput)
--
-- Called when state == AWAIT_CLARIFY. Tries to match the player's input
-- against the stored candidate list. On success, completes the stored intent
-- and dispatches. On failure, re-asks the question.
-- ---------------------------------------------------------------------------
local function handleClarification(rawInput)
    -- Strip stopwords from the clarification input so "the copper key"
    -- and "copper key" both reduce to ["copper", "key"].
    local tokens = Tokeniser.tokenise(rawInput)
    local words  = {}
    for _, token in ipairs(tokens) do
        if not Stopwords[token] then
            words[#words + 1] = token
        end
    end

    -- Use the same adjective+noun matching as the resolver, restricted to
    -- the stored candidate list so we don't re-query scope.
    local matches = Resolver.filterCandidates(words, pending.candidates)
    local matched = nil
    if #matches == 1 then
        matched = matches[1]
    end

    if not matched then
        return "I didn't understand that. " ..
               buildClarificationQuestion(pending.candidates)
    end

    -- Complete the stored intent and dispatch.
    local resolvedIntent = pending.intent
    resolvedIntent[pending.which .. "Ref"] = matched  -- sets dobjRef or iobjRef
    state   = "NORMAL"
    pending = nil
    return Dispatcher.dispatch(resolvedIntent)
end

-- ---------------------------------------------------------------------------
-- Parser.process(rawInput)
-- ---------------------------------------------------------------------------
function Parser.process(rawInput)
    -- AWAIT_CLARIFY: interpret input as a selection from the candidate list.
    if state == "AWAIT_CLARIFY" then
        return handleClarification(rawInput)
    end

    -- Stage 1: tokenise
    local tokens = Tokeniser.tokenise(rawInput)
    if #tokens == 0 then
        return ""
    end

    -- Stage 2: tag
    local intent = Tagger.tag(tokens)
    if not intent then
        return "You don't need to use the word \"" .. tokens[1] .. "\"."
    end

    -- Stage 3: resolve
    local result, extra = Resolver.resolve(intent)

    if result == Resolver.FAIL_NOT_FOUND then
        local words = (extra and extra.words) or intent.dobjWords or {}
        local phrase = #words > 0 and table.concat(words, " ") or "that"
        return "You don't see any " .. phrase .. " here."
    end

    if result == Resolver.FAIL_AMBIGUOUS then
        state   = "AWAIT_CLARIFY"
        pending = extra
        return buildClarificationQuestion(extra.candidates)
    end

    -- Stage 4: dispatch
    local output = Dispatcher.dispatch(result)

    -- Prepend auto-resolve announcements if any noun phrase was auto-resolved
    -- from multiple candidates (the player needs to know which object was chosen).
    local prefix = ""
    if extra.dobj then prefix = prefix .. "(the " .. extra.dobj.name .. ") " end
    if extra.iobj then prefix = prefix .. "(the " .. extra.iobj.name .. ") " end

    return prefix .. output
end

-- Resets disambiguation state. Call between test runs.
function Parser.reset()
    state   = "NORMAL"
    pending = nil
end

return Parser
