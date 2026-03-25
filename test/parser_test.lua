-- test/parser_test.lua
--
-- Headless test suite. No LÖVE2D required.
-- Run standalone with: lua test/parser_test.lua
-- Or required from main.lua for in-game debugging.

package.path = "./?.lua;" .. package.path

local Parser   = require("engine.lua.parser.init")
local World    = require("engine.lua.world.world")
local Resolver = require("engine.lua.parser.resolver")
local Loader   = require("engine.lua.loader")

-- Load world data from JSON once before any tests run.
Loader.load()

-- run(printFn) — printFn defaults to Lua's built-in print.
-- Pass a custom function to redirect output (e.g. to the LÖVE2D terminal).
local function run(printFn)
    printFn = printFn or print
    World.reset()   -- ensure clean world state regardless of what ran before
    Parser.reset()  -- ensure clean FSM state (NORMAL, no pending clarification)
    local passed = 0
    local failed = 0

    local function check(description, input, expected)
        local output = Parser.process(input)
        if output == expected then
            printFn("PASS: " .. description)
            passed = passed + 1
        else
            printFn("FAIL: " .. description)
            printFn("  input:    " .. input)
            printFn("  expected: " .. expected)
            printFn("  got:      " .. output)
            failed = failed + 1
        end
    end

    local function header(title)
        printFn("\n-- " .. title .. " --")
    end

    -- -----------------------------------------------------------------------
    header("Empty and unrecognised input")
    -- -----------------------------------------------------------------------

    check("empty input returns empty string",
        "",
        "")

    check("unrecognised verb",
        "jump",
        'You don\'t need to use the word "jump".')

    -- -----------------------------------------------------------------------
    header("look")
    -- player_quarters has one exit: north. Objects all have listed=false.
    -- -----------------------------------------------------------------------

    check("look gives room title and description",
        "look",
        "Your Quarters\n" ..
        "Your quarters are exactly as you left them — which is to " ..
        "say, arranged with the particular chaos of someone who " ..
        "knows where everything is. The writing desk dominates one " ..
        "wall. An oil lamp sits where you last set it down. " ..
        "Somewhere nearby, an iron key catches the light." ..
        "\n\nExits: north.")

    check("second look gives short description",
        "look",
        "Your Quarters\n" ..
        "Your quarters. The writing desk, the lamp, the key." ..
        "\n\nExits: north.")

    check("l is a synonym for look",
        "l",
        "Your Quarters\n" ..
        "Your quarters. The writing desk, the lamp, the key." ..
        "\n\nExits: north.")

    -- -----------------------------------------------------------------------
    header("inventory")
    -- -----------------------------------------------------------------------

    check("inventory when carrying nothing",
        "inventory",
        "You are carrying nothing.")

    check("i is a synonym for inventory",
        "i",
        "You are carrying nothing.")

    -- -----------------------------------------------------------------------
    header("examine")
    -- -----------------------------------------------------------------------

    check("examine the lamp",
        "examine lamp",
        "A brass oil lamp. The reservoir is about half full.")

    check("x is a synonym for examine",
        "x lamp",
        "A brass oil lamp. The reservoir is about half full.")

    check("examine with adjective",
        "examine iron key",
        "A small iron key. The bow is cast in the shape of a hare.")

    check("examine the desk",
        "examine desk",
        "A large wooden desk. Its surface is bare except for a " ..
        "faint ring left by some long-gone cup.")

    check("examine something not here",
        "examine dragon",
        "You don't see any dragon here.")

    -- -----------------------------------------------------------------------
    header("take")
    -- -----------------------------------------------------------------------

    check("take the lamp",
        "take lamp",
        "Taken.")

    check("take lamp again (already carrying it)",
        "take lamp",
        "You're already carrying that.")

    check("take the desk (not portable)",
        "take desk",
        "You can't pick that up.")

    check("inventory shows carried item",
        "inventory",
        "You are carrying: oil lamp.")

    -- -----------------------------------------------------------------------
    header("drop")
    -- -----------------------------------------------------------------------

    check("drop the lamp (carrying it)",
        "drop lamp",
        "Dropped.")

    check("drop the lamp again (not carrying it)",
        "drop lamp",
        "You aren't carrying that.")

    check("drop iron key (never picked up)",
        "drop iron key",
        "You aren't carrying that.")

    -- -----------------------------------------------------------------------
    header("go")
    -- -----------------------------------------------------------------------

    check("go north moves to entrance passage",
        "go north",
        "Entrance Passage\n" ..
        "A narrow stone passage leads away from your quarters. " ..
        "Bare walls, bare floor. The way back is to the south." ..
        "\n\nExits: south.")

    check("second look in new room gives short desc",
        "look",
        "Entrance Passage\n" ..
        "The entrance passage. Bare stone." ..
        "\n\nExits: south.")

    check("go east blocked (no exit in entrance passage)",
        "go east",
        "You can't go that way.")

    check("go south returns to player quarters",
        "go south",
        "Your Quarters\n" ..
        "Your quarters. The writing desk, the lamp, the key." ..
        "\n\nExits: north.")

    -- -----------------------------------------------------------------------
    header("bare directions")
    -- Player is currently in player_quarters (both rooms already visited).
    -- -----------------------------------------------------------------------

    check("bare 'north' moves room",
        "north",
        "Entrance Passage\n" ..
        "The entrance passage. Bare stone." ..
        "\n\nExits: south.")

    check("bare 's' abbreviation moves back",
        "s",
        "Your Quarters\n" ..
        "Your quarters. The writing desk, the lamp, the key." ..
        "\n\nExits: north.")

    check("bare 'n' abbreviation moves again",
        "n",
        "Entrance Passage\n" ..
        "The entrance passage. Bare stone." ..
        "\n\nExits: south.")

    check("bare direction with no exit",
        "east",
        "You can't go that way.")

    check("bare 'south' returns home",
        "south",
        "Your Quarters\n" ..
        "Your quarters. The writing desk, the lamp, the key." ..
        "\n\nExits: north.")

    -- -----------------------------------------------------------------------
    header("disambiguation")
    -- -----------------------------------------------------------------------
    -- Both keys are in the room. "take key" is ambiguous: iron_key and
    -- copper_key both score logical (rank 100), so they tie -> FAIL_AMBIGUOUS.

    check("take key is ambiguous",
        "take key",
        "Which do you mean, the iron key or the copper key?")

    check("clarification resolves and dispatches",
        "copper key",
        "Taken.")

    -- copper_key is now in inventory (illogicalAlready, rank 40).
    -- iron_key is still in room (logical, rank 100).
    -- "take key" auto-resolves to iron_key, prepends "(the iron key)".
    check("take key auto-resolves after one is taken",
        "take key",
        "(the iron key) Taken.")

    -- -----------------------------------------------------------------------
    header("put")
    -- copper_key and iron_key are in inventory; oil_lamp is in the room.
    -- -----------------------------------------------------------------------

    check("put key on desk",
        "put iron key on desk",
        "You put the iron key on the writing desk.")

    check("put key on desk again (not holding it)",
        "put iron key on desk",
        "You aren't holding that.")

    check("put with no destination",
        "put copper key",
        "Put the copper key where?")

    -- -----------------------------------------------------------------------
    header("unlock / lock")
    -- -----------------------------------------------------------------------

    check("unlock chest with no key",
        "unlock chest",
        "You'll need a key for that.")

    check("unlock chest with wrong key",
        "unlock chest with copper key",
        "That key doesn't fit.")

    check("unlock chest with correct key",
        "unlock chest with iron key",
        "Unlocked.")

    check("unlock already-unlocked chest",
        "unlock chest with iron key",
        "It's not locked.")

    check("lock chest with correct key",
        "lock chest with iron key",
        "Locked.")

    check("lock already-locked chest",
        "lock chest with iron key",
        "It's already locked.")

    check("unlock non-lockable object",
        "unlock desk",
        "That doesn't have a lock.")

    -- -----------------------------------------------------------------------
    header("verifyRank")
    -- -----------------------------------------------------------------------

    -- verifyRank is tested directly (unit test for the scoring helper).
    local function checkRank(description, result, expected)
        local got = Resolver.verifyRank(result)
        if got == expected then
            printFn("PASS: " .. description)
            passed = passed + 1
        else
            printFn("FAIL: " .. description)
            printFn("  expected rank: " .. expected)
            printFn("  got rank:      " .. got)
            failed = failed + 1
        end
    end

    checkRank("nil result -> 100",              nil,                      100)
    checkRank("logical -> 100",                 { logical = true },       100)
    checkRank("logical with rank -> custom",    { logical = true, rank = 150 }, 150)
    checkRank("dangerous -> 90",                { dangerous = true },     90)
    checkRank("illogicalAlready -> 40",         { illogicalAlready = "" }, 40)
    checkRank("illogicalNow -> 40",             { illogicalNow = "" },    40)
    checkRank("illogical -> 30",                { illogical = "" },       30)
    checkRank("nonObvious -> 30",               { nonObvious = true },    30)

    -- -----------------------------------------------------------------------
    printFn("\n" .. passed .. " passed, " .. failed .. " failed.")
    return passed, failed
end

-- ---------------------------------------------------------------------------
-- Auto-run when executed directly: lua test/parser_test.lua
-- arg[0] is the script path when run directly; it's the love executable
-- path (e.g. /usr/bin/love) when run inside LÖVE2D, so we check for
-- "parser_test" in the name to distinguish the two cases.
if arg and arg[0] and arg[0]:find("parser_test", 1, true) then
    local _, failed = run()
    if failed > 0 then
        os.exit(1)
    end
end

return run
