-- parser/init.lua
--
-- Entry point for the parser pipeline.
-- Chains the four stages together:
--   Tokeniser -> Tagger -> Resolver -> Dispatcher
--
-- Also owns the disambiguation state machine (added in Milestone 1b).
-- In Milestone 1a: NORMAL state only, no disambiguation.
--
-- Public interface:
--   Parser.process(rawInput) -> string
--       Takes raw player input, runs it through the pipeline,
--       returns the output string to be printed by the terminal.

local Tokeniser  = require("engine.lua.parser.tokeniser")
local Tagger     = require("engine.lua.parser.tagger")
local Resolver   = require("engine.lua.parser.resolver")
local Dispatcher = require("engine.lua.parser.dispatcher")

local Parser = {}

function Parser.process(rawInput)
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
    local result = Resolver.resolve(intent)
    if result == Resolver.FAIL_NOT_FOUND then
        -- Pull the noun from dobjWords to make a natural message.
        local noun = intent.dobjWords[#intent.dobjWords] or "that"
        return "You don't see any " .. noun .. " here."
    end

    -- Stage 4: dispatch
    return Dispatcher.dispatch(intent)
end

return Parser
