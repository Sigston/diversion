-- test/parser_test.lua
--
-- Headless test suite. No LÖVE2D required.
-- Run standalone with: lua test/parser_test.lua
-- Or required from main.lua for in-game debugging.

package.path = "./?.lua;" .. package.path

local Parser = require("engine.lua.parser.init")
local World  = require("engine.lua.world.world")

local function run()
    World.reset()   -- ensure clean state regardless of what ran before
    local passed = 0
    local failed = 0

    local function check(description, input, expected)
        local output = Parser.process(input)
        if output == expected then
            print("PASS: " .. description)
            passed = passed + 1
        else
            print("FAIL: " .. description)
            print("  input:    " .. input)
            print("  expected: " .. expected)
            print("  got:      " .. output)
            failed = failed + 1
        end
    end

    local function header(title)
        print("\n-- " .. title .. " --")
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
    -- -----------------------------------------------------------------------

    check("look gives room title",
        "look",
        "Your Quarters\n" ..
        "Your quarters are exactly as you left them — which is to " ..
        "say, arranged with the particular chaos of someone who " ..
        "knows where everything is. The writing desk dominates one " ..
        "wall. An oil lamp sits where you last set it down. " ..
        "Somewhere nearby, an iron key catches the light.")

    check("second look gives short description",
        "look",
        "Your Quarters\nYour quarters. The writing desk, the lamp, the key.")

    check("l is a synonym for look",
        "l",
        "Your Quarters\nYour quarters. The writing desk, the lamp, the key.")

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
    print("\n" .. passed .. " passed, " .. failed .. " failed.")
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
