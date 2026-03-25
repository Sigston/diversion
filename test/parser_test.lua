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
local State    = require("engine.lua.world.state")

-- Load world data from JSON once before any tests run.
Loader.load()

-- run(printFn) — printFn defaults to Lua's built-in print.
-- Pass a custom function to redirect output (e.g. to the LÖVE2D terminal).
local function run(printFn)
    printFn = printFn or print
    World.reset()   -- ensure clean world state regardless of what ran before
    Parser.reset()  -- ensure clean FSM state (NORMAL, no pending clarification)
    State.reset()   -- ensure clean flag state
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
        "knows where everything is." ..
        "\n\nYou can also see: iron key, copper key, oil lamp, and small chest." ..
        "\n\nThere is a writing desk here. On the desk surface: quill pen." ..
        "\n\nExits: north.")

    check("second look gives short description",
        "look",
        "Your Quarters\n" ..
        "Your quarters." ..
        "\n\nYou can also see: iron key, copper key, oil lamp, and small chest." ..
        "\n\nThere is a writing desk here. On the desk surface: quill pen." ..
        "\n\nExits: north.")

    check("l is a synonym for look",
        "l",
        "Your Quarters\n" ..
        "Your quarters." ..
        "\n\nYou can also see: iron key, copper key, oil lamp, and small chest." ..
        "\n\nThere is a writing desk here. On the desk surface: quill pen." ..
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
        "A large wooden desk. A faint ring left by some long-gone cup marks the surface." ..
        "\nThe desk drawer is closed." ..
        "\nOn the desk surface: quill pen.")

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

    check("go east blocked (connector present but canPass false)",
        "go east",
        "The door is locked shut.")

    check("go south returns to player quarters",
        "go south",
        "Your Quarters\n" ..
        "Your quarters." ..
        "\n\nYou can also see: iron key, copper key, oil lamp, and small chest." ..
        "\n\nThere is a writing desk here. On the desk surface: quill pen." ..
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
        "Your quarters." ..
        "\n\nYou can also see: iron key, copper key, oil lamp, and small chest." ..
        "\n\nThere is a writing desk here. On the desk surface: quill pen." ..
        "\n\nExits: north.")

    check("bare 'n' abbreviation moves again",
        "n",
        "Entrance Passage\n" ..
        "The entrance passage. Bare stone." ..
        "\n\nExits: south.")

    check("bare direction with blocked connector",
        "east",
        "The door is locked shut.")

    check("bare 'south' returns home",
        "south",
        "Your Quarters\n" ..
        "Your quarters." ..
        "\n\nYou can also see: iron key, copper key, oil lamp, and small chest." ..
        "\n\nThere is a writing desk here. On the desk surface: quill pen." ..
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

    check("put key on desk (remaps to desk surface)",
        "put iron key on desk",
        "You put the iron key on the desk surface.")

    check("put key on desk again (not holding it)",
        "put iron key on desk",
        "You aren't holding that.")

    check("put with no destination",
        "put copper key",
        "Put the copper key where?")

    -- -----------------------------------------------------------------------
    header("unlock / lock")
    -- iron_key is on desk_surface (accessible); copper_key is in inventory.
    -- -----------------------------------------------------------------------

    check("unlock chest with ambiguous key disambiguates",
        "unlock chest with key",
        "Which do you mean, the iron key or the copper key?")

    check("clarifying wrong key gives correct rejection",
        "copper key",
        "That key doesn't fit.")

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

    -- Chest is locked; iron_key is on desk_surface (accessible), copper_key in inventory.
    -- Adjective-only disambiguation: "iron" should resolve to the iron key.
    check("unlock with key is ambiguous",
        "unlock chest with key",
        "Which do you mean, the iron key or the copper key?")

    check("adjective-only clarification selects iron key",
        "iron",
        "Unlocked.")

    check("lock chest to restore state",
        "lock chest with iron key",
        "Locked.")

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
    header("connectors")
    -- Player is in player_quarters (reset). Go north to entrance_passage first.
    -- -----------------------------------------------------------------------

    check("go north to entrance passage (setup for connector tests)",
        "north",
        "Entrance Passage\n" ..
        "The entrance passage. Bare stone." ..
        "\n\nExits: south.")

    check("blocked connector returns blockedMsg",
        "east",
        "The door is locked shut.")

    check("listExits hides blocked connector",
        "look",
        "Entrance Passage\n" ..
        "The entrance passage. Bare stone." ..
        "\n\nExits: south.")

    -- Unlock the passage via State flag (direct engine call, not a parser command).
    State.set("test_passage_open", true)

    check("unblocked connector traverses with traversalMsg",
        "east",
        "You push through the heavy door.\n\n" ..
        "Blocked Passage\n" ..
        "A short corridor. The way back is west." ..
        "\n\nExits: west.")

    check("listExits shows unblocked connector from destination",
        "look",
        "Blocked Passage\n" ..
        "A short corridor. The way back is west." ..
        "\n\nExits: west.")

    -- -----------------------------------------------------------------------
    header("open / close")
    -- Player is in blocked_passage after connector tests.
    -- Navigate back to player_quarters where the chest is.
    -- (test_passage_open is still true, so east exit shows in entrance_passage.)
    -- -----------------------------------------------------------------------

    check("west back to entrance passage",
        "west",
        "Entrance Passage\n" ..
        "The entrance passage. Bare stone." ..
        "\n\nExits: east, south.")

    check("south back to player quarters",
        "south",
        "Your Quarters\n" ..
        "Your quarters." ..
        "\n\nYou can also see: oil lamp and small chest." ..
        "\n\nThere is a writing desk here. On the desk surface: iron key, quill pen." ..
        "\n\nExits: north.")

    -- Chest is locked from earlier lock tests.
    check("open locked chest is blocked",
        "open chest",
        "It's locked.")

    check("unlock chest to allow opening",
        "unlock chest with iron key",
        "Unlocked.")

    check("open chest",
        "open chest",
        "Opened.")

    check("open chest again (already open)",
        "open chest",
        "It's already open.")

    check("close chest",
        "close chest",
        "Closed.")

    check("close chest again (already closed)",
        "close chest",
        "It's already closed.")

    check("open non-openable object",
        "open lamp",
        "That doesn't open.")

    -- -----------------------------------------------------------------------
    header("containment")
    -- Player is in player_quarters.
    -- iron_key: on desk_surface (put there during put tests)
    -- quill_pen: on desk_surface (initial location)
    -- velvet_pouch: in chest (chest is unlocked and closed from open/close tests)
    -- desk_drawer: closed
    -- -----------------------------------------------------------------------

    -- quill pen is in scope via desk_surface (contType "on")
    check("examine quill pen via desk surface",
        "examine quill pen",
        "A quill pen of dark feather. The nib is still sharp.")

    -- examine a surface shows its contents
    check("examine desk surface shows contents",
        "examine desk surface",
        "The writing surface of the desk.\nOn it: iron key, quill pen.")

    -- velvet pouch not in scope while chest is closed
    check("velvet pouch out of scope when chest closed",
        "examine velvet pouch",
        "You don't see any velvet pouch here.")

    -- examine closed in-container shows closed state
    check("examine desk drawer (closed)",
        "examine desk drawer",
        "A narrow drawer in the writing desk. It is closed.")

    -- take quill pen from surface
    check("take quill pen from desk surface",
        "take quill pen",
        "Taken.")

    -- put it back on desk: remaps to desk_surface
    check("put quill pen on desk (remaps to desk surface)",
        "put quill pen on desk",
        "You put the quill pen on the desk surface.")

    -- take it again, try to put in closed drawer
    check("take quill pen again",
        "take quill pen",
        "Taken.")

    check("put quill pen in desk (drawer closed)",
        "put quill pen in desk",
        "The desk drawer isn't open.")

    -- open drawer then put succeeds
    check("open desk drawer",
        "open desk drawer",
        "Opened.")

    check("put quill pen in desk (drawer open)",
        "put quill pen in desk",
        "You put the quill pen in the desk drawer.")

    -- examine open in-container lists contents
    check("examine desk drawer (open, with quill pen)",
        "examine desk drawer",
        "A narrow drawer in the writing desk. It is open.\nIt contains: quill pen.")

    -- open chest to bring velvet pouch into scope
    check("open chest (unlocked from earlier)",
        "open chest",
        "Opened.")

    check("velvet pouch in scope when chest open",
        "examine velvet pouch",
        "A small velvet pouch, tied with a drawstring.")

    -- examine open in-container shows its contents
    check("examine chest (open, with velvet pouch)",
        "examine chest",
        "A small wooden chest secured with an iron lock. It is open.\n" ..
        "It contains: velvet pouch.")

    -- put something in a non-container errors cleanly
    check("put key in lamp (lamp is not a container)",
        "put copper key in lamp",
        "You can't put things in the oil lamp.")

    -- -----------------------------------------------------------------------
    header("open / close desk via remap")
    -- Player is in player_quarters.
    -- desk_drawer is open (from "open desk drawer" earlier in containment tests).
    -- iron_key is on desk_surface.
    -- copper_key is in inventory.
    -- -----------------------------------------------------------------------

    -- close desk remaps to the drawer
    check("close desk (remaps to drawer)",
        "close desk",
        "Closed.")

    -- take iron key from the surface so we can put it in the drawer
    check("take iron key from desk surface",
        "take iron key",
        "Taken.")

    -- open desk remaps to the drawer
    check("open desk (remaps to drawer)",
        "open desk",
        "Opened.")

    -- put iron key in desk (drawer now open)
    check("put iron key in desk",
        "put iron key in desk",
        "You put the iron key in the desk drawer.")

    -- close desk again; iron key is now inside and out of scope
    check("close desk again",
        "close desk",
        "Closed.")

    check("iron key not in scope when drawer closed",
        "take iron key",
        "You don't see any iron key here.")

    -- open desk and take the key back out
    check("open desk to retrieve iron key",
        "open desk",
        "Opened.")

    check("take iron key from open drawer",
        "take iron key",
        "Taken.")

    -- confirm it is in inventory
    check("inventory shows iron key and copper key",
        "inventory",
        "You are carrying: copper key, iron key.")

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
