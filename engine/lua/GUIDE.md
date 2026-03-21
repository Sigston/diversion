# Lua Engine — Developer Guide

Plain-English reference for the Lua/LÖVE2D version of the engine.
For overall project architecture see `docs/architecture.md`.

---

## What this is

The local development version of the Diversion IF engine. It runs on your
machine using LÖVE2D as the runtime. The same game logic that runs here also
runs in the TypeScript/browser version — they share the same JSON game data
files.

The Lua engine is the primary development environment: no build step, instant
feedback, and headless testing without needing a browser.

---

## Directory structure

```
engine/lua/
├── terminal.lua            LÖVE2D terminal UI: scrolling buffer, input line,
│                           command history, colour output, mouse/keyboard scroll.
│                           Meta-commands: test (inline test runner), quit.
├── loader.lua              Reads game/data/rooms.json + objects.json, builds world
│                           tables, calls World.load(). Works headless and in LÖVE2D.
├── lexicon/
│   ├── verbs.lua           Verb table: synonyms, resolveObj, resolveFirst.
│   │                       Also builds synonymMap (word -> canonical verb).
│   ├── prepositions.lua    Set of known prepositions (in, on, with, etc.)
│   └── stopwords.lua       Set of words stripped before object matching (the, a, etc.)
├── parser/
│   ├── tokeniser.lua       Stage 1: raw string -> token list
│   ├── tagger.lua          Stage 2: token list -> partial CommandIntent
│   ├── resolver.lua        Stage 3: fills dobjRef and iobjRef on the intent
│   ├── dispatcher.lua      Stage 4: runs verify/check/action cycle
│   └── init.lua            Entry point: Parser.process(rawInput) chains all stages
├── world/
│   ├── world.lua           World model: rooms, objects, scope, inventory
│   ├── defaults.lua        Default verb handlers (examine, look, inventory, take,
│   │                       drop, go/directions, put, unlock, lock, wait, help, quit)
│   ├── state.lua           Global state flags — stub, built in Milestone 3
│   └── terminal.lua        (empty — terminal is at engine/lua/terminal.lua)
└── loader.lua              JSON loader — stub, built in Milestone 3
```

Also at the project root:

```
main.lua                    LÖVE2D entry point — wires terminal to love callbacks
lib/json.lua                rxi JSON parser (MIT). Used by loader.lua.
test/parser_test.lua        Headless test suite (49 tests, all passing)
game/data/rooms.json        Room definitions: names, descriptions, exits, object lists
game/data/objects.json      Object definitions: names, aliases, adjectives, properties
```

---

## The parser pipeline

Player input travels through four stages in sequence:

```
rawInput
   │
   ▼
Tokeniser.tokenise()     lowercase, strip punctuation, split on whitespace
   │
   ▼  tokens: { "take", "the", "iron", "key" }
   │
   ▼
Tagger.tag()             look up verb, find preposition, split and strip stopwords
   │
   ▼  partial CommandIntent: { verb="take", dobjWords={"iron","key"}, ... }
   │
   ▼
Resolver.resolve()       match noun phrases to in-scope objects
   │
   ▼  complete CommandIntent: { ..., dobjRef=<iron_key object>, ... }
   │
   ▼
Dispatcher.dispatch()    find handler, run verify -> check -> action
   │
   ▼  output string returned to terminal
```

Each stage knows nothing about the others. The only thing they share is the
CommandIntent table, which is defined in `CLAUDE.md`.

---

## The three-phase execution cycle

Every verb handler goes through three phases. All three phases are always run
in order — they must never be collapsed into one.

**`verify(obj, intent)`** — must not modify state. Is this action logically
possible? Used during disambiguation scoring. Blocking result types:
`{ illogical = "msg" }`, `{ illogicalAlready = "msg" }`, `{ illogicalNow = "msg" }`.
Non-blocking: `{ logical = true }`, `{ dangerous = true }`, `{ nonObvious = true }`.
See `Resolver.verifyRank()` for the numeric ranks used for scoring.

**`check(obj, intent)`** — must not change world state; may set tracking flags
on the object (e.g. `self.attemptedOpen = true`). Called after objects are fully
resolved. Return a string to block, or `nil` to allow.

**`action(obj, intent)`** — the only phase that may modify game state.
Returns the output string.

---

## How to run the tests

No LÖVE2D required. From the project root:

```bash
lua test/parser_test.lua
```

Runs 49 tests covering: empty input, unrecognised verbs, look, inventory,
examine, take (including already-held and non-portable), drop, go (movement,
blocked exits), bare direction words and abbreviations, put (two-object),
unlock/lock (two-object, key matching, wrong key, no key, non-lockable),
disambiguation (clarification question, clarification response, auto-resolve
with prefix), and verifyRank unit tests. Exits with code 1 if any test fails
— useful for scripting.

All tests must pass before starting any new work in a session.

---

## How to run in LÖVE2D

Open the project root in VS Code and press **F5**, or from the terminal:

```bash
love .
```

Opens a full terminal UI. The starting room is described on load. Type commands
normally. Special terminal commands (not game verbs):

- `test` — runs the 49-test suite inline, with colour-coded PASS/FAIL output,
  then resets the world and re-describes the starting room so play continues.
- `quit` / `q` — exits LÖVE2D.

**Scrolling:**
- Mouse wheel — scroll up to see older output, down to return to latest.
- PageUp / PageDown — scroll by one page at a time.
- Home — jump to the top of the buffer.
- End — jump back to the bottom.
- Submitting any command always snaps back to the bottom.

---

## The module system

Lua doesn't have built-in modules. The pattern used throughout this project is:

```lua
local MyModule = {}

function MyModule.doSomething()
    -- ...
end

return MyModule
```

And to use it:

```lua
local MyModule = require("engine.lua.path.to.module")
```

`require` uses dots as path separators, which map to `/` on disk.
`package.path = "./?.lua;" .. package.path` at the top of entry-point files
tells Lua to look from the project root, so `engine.lua.parser.init` resolves
to `./engine/lua/parser/init.lua`.

---

## Lexicon tables

**`verbs.lua`** — defines all known verbs. Each entry has:
- `synonyms` — all words that map to this verb ("get", "grab" -> "take")
- `resolveObj` — false for verbs like `look` and `inventory` that don't
  refer to in-scope objects at all
- `resolveFirst` — which object to resolve first for two-object verbs
  ("iobj" or "dobj"; default is "iobj")

At load time, `verbs.lua` builds `Verbs.synonymMap` — a flat table mapping
every synonym to its canonical verb name. The tagger and resolver both use
this instead of the full verb table.

**`prepositions.lua`** and **`stopwords.lua`** are both set-style tables:
`{ ["in"]=true, ["on"]=true, ... }`. Membership testing is `O(1)`:
`if Prepositions[token] then ...`

---

## World model

`world.lua` owns all rooms and objects. Other modules never access the `rooms`
or `objects` tables directly — they always go through the World API:

| Function | What it does |
|---|---|
| `World.currentRoom()` | Returns the current room table |
| `World.currentRoomKey()` | Returns the current room key string |
| `World.currentContext()` | Returns the context table passed to description functions |
| `World.inScope()` | Returns all objects visible to the player right now |
| `World.describeCurrentRoom()` | Returns room title + description, marks room visited |
| `World.describeInventory()` | Returns a string listing carried items |
| `World.moveTo(roomKey)` | Moves the player to a different room (used by go handler) |
| `World.moveObject(obj, location)` | Moves an object (take, drop, containers) |
| `World.getObject(key)` | Returns an object by its key string |
| `World.reset()` | Resets all mutable state — called at the start of every test run |

Scope is computed fresh on every call to `World.inScope()` — it is never
cached between turns.

---

## Room descriptions

Room descriptions are always functions, never plain strings:

```lua
description = function(self, ctx)
    if not self.visited then
        return "First visit description..."
    end
    return "Short repeat description."
end
```

`self` is the room table itself — use it to read the room's own properties
(like `self.visited`). `ctx` is an external context table (lit state, time
period, flags) — used when the description depends on things the room doesn't
own. In Milestone 1a `ctx` is always an empty table.

`World.describeCurrentRoom()` calls `description(room, World.currentContext())`
and then sets `room.visited = true`.

---

## Handler lookup order

When a command is dispatched, `dispatcher.lua` looks for a handler in this
order:

1. Object-specific handler — `obj.handlers[verb]`
2. Room-level handler — `room.handlers[verb]`
3. Default handler — `Defaults[verb]` (in `world/defaults.lua`)
4. Nothing found — returns `"You can't do that."`

---

## Current state — Milestone 2 complete, M3 data layer complete

LÖVE2D interactive terminal running. Full parser pipeline behind it.

**Terminal features:**
- Scrolling output buffer (200 lines max), word-wrapped to window width
- Command history (50 commands, arrow-key navigation)
- Colour-coded output matching the TypeScript terminal (roomTitle, response,
  error, system, narrator, input)
- Room-title heuristic: first line of a go/look response coloured in roomTitle
- Scrollbar showing position in buffer; mouse wheel + PageUp/PageDown/Home/End
- Auto-scroll to bottom on every command submit
- `test` meta-command: runs 49-test suite inline with colour coding, then resets
- `quit` / `q`: exits via love.event

**Default handlers:** examine, look, inventory, take, drop, go, put, unlock,
lock, wait, help, quit (25 canonical verbs total)

**World data:** loaded from `game/data/rooms.json` and `game/data/objects.json`
at startup via `Loader.load()`. The world stub is no longer hardcoded.
Two rooms, five objects (copper_key and chest are test stubs).

Next: handler registry, narrator response layer, then game content.

---

## Naming conventions

- All identifiers: `snake_case`
- Rooms keyed by string: `"player_quarters"`, `"entrance_passage"`
- Objects keyed by string: `"iron_key"`, `"oil_lamp"`
- Canonical verbs: lowercase single word (`"take"`, `"examine"`)
- State flags: `"lamp_lit"`, `"bridge_open"`
