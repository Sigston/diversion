# CLAUDE.md — Diversion (working title)

This file is the persistent briefing for all Claude Code sessions on this project.
Read it in full at the start of every session. Update it at the end of every session
with decisions made that are not already recorded here.

---

## What this project is

A parser-driven interactive fiction engine, built twice — once in Lua/LÖVE2D for
local development, once in TypeScript for web deployment. Both runtimes load the
same JSON game data files. The engine is being built to run a specific game called
*Diversion* (working title). Engine decisions should always be made with that game's
requirements in mind. More information about the specific game can be found in 
`docs/diversion-brief.md`.

---

## Architecture

Full specification in `docs/architecture_v2.md` (canonical).
`docs/architecture.md` is preserved as v1 with a change log in Section 18.
`docs/tads3-adv3lite-reference.md` contains detailed research notes on the
TADS 3 / adv3Lite system that informed these decisions.
This section summarises the decisions most likely to affect Claude Code's work.

### Layer diagram

```
┌─────────────────────────────────────────┐
│      Runtime Presentation Layer         │  main.lua / index.ts
├─────────────────────────────────────────┤
│      Terminal / UI Shell                │  scrolling buffer, prompt, history
├─────────────────────────────────────────┤
│      Parser Pipeline                    │  tokeniser → tagger → resolver
│                                         │           → disambiguator → dispatcher
├─────────────────────────────────────────┤
│      Command Execution Cycle            │  verify() → check() → action()
├─────────────────────────────────────────┤
│      World Model                        │  rooms, objects, relations, scope
├─────────────────────────────────────────┤
│      Game Logic / Content               │  verb handlers, event hooks
├─────────────────────────────────────────┤
│      State Manager                      │  flags, save/load
└─────────────────────────────────────────┘
```

### File structure

```
/
├── CLAUDE.md
├── GUIDE.md               index only — points to engine guides
├── main.lua               LÖVE2D entry point (runs tests in M1a; full game in M2)
├── docs/
│   ├── diversion-brief.md
│   ├── architecture.md         v1 — preserved, with change log in Section 18
│   ├── architecture_v2.md      canonical — use this for implementation
│   └── tads3-adv3lite-reference.md  research notes; source for M1b decisions
├── engine/
│   ├── lua/
│   │   ├── GUIDE.md
│   │   ├── loader.lua     JSON loader stub (Milestone 3)
│   │   ├── terminal.lua   LÖVE2D terminal UI stub (Milestone 2)
│   │   ├── parser/
│   │   │   ├── init.lua
│   │   │   ├── tokeniser.lua
│   │   │   ├── tagger.lua
│   │   │   ├── resolver.lua
│   │   │   └── dispatcher.lua
│   │   ├── world/
│   │   │   ├── world.lua
│   │   │   ├── state.lua
│   │   │   └── defaults.lua
│   │   └── lexicon/
│   │       ├── verbs.lua
│   │       ├── prepositions.lua
│   │       └── stopwords.lua
│   └── typescript/
│       ├── GUIDE.md
│       ├── index.html
│       ├── vite.config.ts
│       ├── package.json
│       ├── tsconfig.json
│       └── src/
│           ├── main.ts
│           ├── style.css
│           ├── types.ts
│           ├── parser/
│           ├── world/
│           ├── lexicon/
│           └── test/
├── game/
│   └── data/              JSON game data (Milestone 3)
└── test/
    └── parser_test.lua
```

### Data format
All game content is JSON. The engine loads JSON at runtime. Neither runtime
reads Lua data files for game content — those were scaffolding only.
The same JSON files are loaded by both the Lua and TypeScript engines.

### The loader
Each runtime has a loader that:
1. Reads JSON game data files
2. Instantiates the world model
3. Connects named handler references to registered handler functions
4. Wires AI narrator overrides into the response system

The loader is the only place where the two runtimes differ substantively.
Everything above the loader is identical in logic, different only in syntax.

---

## Absolute rules

### 1. game/data/ must never contain executable code
JSON files are pure data. Logic lives in the engine's handler registry,
referenced by name from the data files. No eval, no embedded scripts.

### 2. verify() must never modify game state or read the other object's ref
verify() is called twice per command: once in the resolver (scoring all
candidates for disambiguation) and once in the dispatcher (final gate).
During the resolver pass, the other noun phrase may not yet be resolved —
intent.dobjRef or intent.iobjRef will be nil. verify() must base its result
only on properties of its own object and global state (State flags, World
queries). Never read intent.dobjRef or intent.iobjRef inside verify().

### 3. Handlers return strings; they never print or console.log
All output flows upward to the terminal layer. Game logic is testable
without any runtime (LÖVE2D or browser) running.

### 4. The three phases must not be collapsed
verify(), check(), and action() are distinct phases with distinct purposes:
- verify(): is this logical from the player's perspective? Used for
  disambiguation scoring. Must not modify state or read other-object refs.
- check(): can this proceed given conditions the player couldn't know?
  Called after objects are resolved. Must not change world state; may set
  tracking flags on the object (e.g. self.attemptedOpen = true).
- action(): execute the effect, return output string. Use World.moveObject()
  for all object moves — never write obj.location directly.

### 5. Room descriptions are functions, not strings
Descriptions take a context argument (at minimum: lit state, period state)
and return a string. The go handler and look handler must call description
as a function. Never read it as a plain string.

### 6. Exits may be functions
An exit value may be a string (room key) or a function that returns a
string or nil. The go handler must check type and call accordingly.
A nil return means the exit is present but not traversable — return the
door or obstacle's specific message, not a generic "you can't go that way".

### 7. AI narrator responses are authored, not generated
The engine must support a narrator response layer that overrides default
messages with authored lines. Data schema must include narratorResponses
at room, object, and verb levels. Default fallbacks exist but should
rarely be reached in the final game.

---

## Naming conventions

- All Lua identifiers: snake_case
- All TypeScript identifiers: camelCase (types/interfaces: PascalCase)
- Rooms keyed by string: "entrance_passage", "player_quarters"
- Objects keyed by string: "oil_lamp", "iron_key"
- Canonical verbs: lowercase single word ("take", "put", "examine")
- State flags: lowercase with underscores ("bridge_open", "lamp_lit")
- Handler registry keys: dot-namespaced ("handlers.door.unlock",
  "handlers.timemachine.enter")
- JSON files: snake_case filenames, camelCase property names

---

## CommandIntent — the contract type

Every component below the resolver operates on CommandIntent.
Nothing below the resolver ever sees a raw string.

```
{
  verb:       string        -- canonical verb
  dobjWords:  string[]      -- adjectives + noun of direct object
  dobjRef:    object|null   -- resolved object (set by resolver)
  prep:       string|null   -- preposition
  iobjWords:  string[]|null -- adjectives + noun of indirect object
  iobjRef:    object|null   -- resolved object (set by resolver)
  auxWords:   string[]|null -- reserved: third noun phrase
  auxRef:     object|null   -- reserved: third resolved object
}
```

The aux fields are reserved for three-object verbs. Do not implement them
in Milestone 1. Do not remove them from the struct definition.

---

## Indirect object resolution order

Default: resolve indirect object first.
Exceptions: unlock, unlockWith — resolve direct object first.
This is configurable per canonical verb in the lexicon. Do not hardcode.

---

## Two-object handler dispatch

For two-object verbs (PUT X IN Y), the dispatcher calls runCycle only on the
**dobj's handler**. The iobj's handler is consulted by the **resolver** during
disambiguation scoring (verify() is called on iobj candidates to rank them),
but once both objects are resolved, the iobj's handler is not further invoked
by the dispatcher.

The dobj's handler receives the full intent including intent.iobjRef and is
responsible for the complete action logic. This is a deliberate simplification
from adv3Lite's split dobjFor/iobjFor chains — sufficient for this game's scope.

If an iobj genuinely needs to interject at check time, the dobj's action can
manually delegate to intent.iobjRef.handlers[verb]. This is explicit delegation,
not automatic dispatch.

---

## resolveObj flag

Some verbs do not resolve to in-scope objects at all:
  - go: direction word is data for the handler, not an object reference
  - look: no noun phrase
  - inventory: no noun phrase

Each verb lexicon entry has a resolveObj field (default: true).
When false, the resolver skips object resolution entirely and passes
the partial intent straight to the dispatcher.

Do not special-case these verbs in the resolver. Always read resolveObj
from the verb's lexicon entry.

---

## verify() result types

verify() returns one of these result tables. The resolver uses the rank to
score candidates. Higher rank = more preferred. All blocking types (Blocks=yes)
also stop the action in the dispatcher's second-pass check.

| Result | Rank | Blocks? | Use case |
|---|---|---|---|
| `{ logical = true }` | 100 | No | Default; no objection |
| `{ logical = true, rank = n }` | n | No | Fine-tune; 150 = especially good fit |
| `{ dangerous = true }` | 90 | No | Allow explicit; block auto-select (airlock) |
| `{ illogicalAlready = "msg" }` | 40 | Yes | Already done ("already carrying that") |
| `{ illogicalNow = "msg" }` | 40 | Yes | Currently impossible ("lamp already lit") |
| `{ illogical = "msg" }` | 30 | Yes | Inherently wrong always ("can't take a wall") |
| `{ nonObvious = true }` | 30 | No | Allow explicit; block auto-select (puzzle) |

Use `fixed = true` on objects to produce `{ illogical = ... }` (rank 30) at verify.
Use `portable = false` to produce a check() failure (not a verify failure).
Use `illogicalAlready` (not `illogical`) when the action has already been done.

The resolver needs a `verifyRank(result)` helper that maps these to numbers.
The dispatcher's runCycle must block on illogical, illogicalAlready, AND
illogicalNow — extracting the message from whichever field is set.

---

## The disambiguation state machine

States: NORMAL, AWAIT_CLARIFY

On AUTO-RESOLVE (one candidate has uniquely highest verify rank, N>1 scored):
  - Prepend "(the [object.name])" to the output
  - Assign object to intent ref, remain in NORMAL, continue to dispatch
  - No announcement if only one candidate matched in the first place

On FAIL_AMBIGUOUS (top-ranked candidates are tied):
  - Store partial intent and candidate list
  - Transition to AWAIT_CLARIFY
  - Emit clarification question with candidate names

On next input while AWAIT_CLARIFY:
  - Interpret as selection from candidate list
  - Complete stored intent, transition to NORMAL, dispatch

On FAIL_NOT_FOUND:
  - Emit not-found message
  - Remain in NORMAL

Game handlers never observe disambiguation state.
They always receive a complete, fully resolved CommandIntent.

---

## Scope rules

In-scope objects at any turn:
  - Objects in current room's object list
  - Objects in open containers that are themselves in scope
  - Objects in player inventory
  - The time machine (when in player quarters)
  - The telescope (when in player quarters)

Out of scope:
  - Objects in closed or locked containers
  - Objects in other rooms
  - Objects in other time periods (except what the player carried in)

Scope is computed dynamically on every turn. Not cached.

---

## Build strategy

Both Lua and TypeScript runtimes are always kept in sync.
Workflow for every feature:
  1. Implement in Lua (no build step, fast iteration)
  2. Port to TypeScript immediately while logic is fresh
  3. Both must pass their respective test suites before moving on

The TypeScript build is the publicly visible version (embedded in WordPress).
The Lua build is the local development and test environment.

Multi-word verb synonyms ("look at", "pick up", "put down") are deferred
until after Milestone 1b. Use single-word synonyms only in M1.

---

## Milestone 0 — TypeScript project setup (do this first)

Goal: a working browser terminal, live on the website, with no game yet.

- [ ] Vite + TypeScript project under engine/typescript/
- [ ] Browser terminal UI: div structure, colour scheme, input, command history
- [ ] Placeholder state: terminal renders, accepts input, echoes "no game loaded"
- [ ] Build config: single index.html + game.js bundle
- [ ] WordPress embed instructions

---

## Milestone 1a — core pipeline, simple path (both languages)

Goal: end-to-end loop working simply, no disambiguation yet.

- [x] Verb lexicon (with resolveObj and resolveFirst fields)
- [x] Tokeniser
- [x] Tagger (single-word synonyms only)
- [x] Minimal world stub: current room, objects, inventory, scope query
- [x] Dispatcher with verify/check/action cycle
- [x] Simple resolver: first match only, no disambiguation
- [x] Default handlers: examine, look, inventory
- [x] test/parser_test.lua passing (12 tests)
- [x] TypeScript port of all of the above

Do not build in Milestone 1a:
  - verify() scoring or disambiguation
  - take, drop, go handlers
  - Terminal UI or LÖVE2D layer
  - JSON loader

---

## Milestone 1b — full resolver (both languages)

Goal: disambiguation and the full default handler set.

- [x] verify() scoring in resolver
- [x] Disambiguation FSM (NORMAL / AWAIT_CLARIFY)
- [x] Indirect object resolution (resolveFirst per verb)
- [x] Default handlers: take, drop, go
- [x] Extended tests covering disambiguation (34 passing)
- [x] TypeScript port of all of the above
- [x] Extended tests for two-object verbs (put, unlock, lock)

### M1b implementation notes

**Pre-M1b fixes applied to existing code:**
- `dispatcher.lua` / `dispatcher.ts` — blocking logic now checks all three
  message-carrying verify result types: `illogical`, `illogicalAlready`,
  `illogicalNow`. Previously only `illogical` was checked.
- `types.ts` — `VerifyResult` union expanded with `dangerous`, `illogicalAlready`,
  `illogicalNow`. `fixed?: boolean` added to `GameObject`.
- `dispatcher.lua` comment corrected: check() may set tracking flags on the
  object but must not change world state.

**Resolver changes:**
- `verifyRank()` helper added and exposed as `Resolver.verifyRank` (also exported
  from TypeScript resolver). Maps verify result types to numeric ranks.
- `Resolver.filterCandidates(wordList, candidates)` exposed for use in
  `handleClarification`. Runs the same adjective+noun matching as the resolver
  but restricted to a specific candidate list (avoids re-querying scope).
- `resolveNounPhrase` now scores multiple candidates with verify() and either
  auto-resolves (unique highest rank) or returns FAIL_AMBIGUOUS (tied).

**Disambiguation FSM (init.lua / index.ts):**
- `Parser.reset()` / `reset()` added — resets FSM state to NORMAL. Must be
  called between test runs (alongside `World.reset()`).
- Clarification matching uses `Resolver.filterCandidates` with stopword
  stripping, not just last-token noun matching. This ensures "copper key"
  correctly selects copper_key over iron_key.
- Auto-resolve prepends `(the [name])` only when N>1 candidates were scored.
  No prefix when a single candidate matched in the first place.

**World stub additions:**
- `copper_key` added as a second key (alias "key") to enable disambiguation
  tests. It is a stub object only — not part of the actual game content.
- `entrance_passage` room added with exits north/south to `player_quarters`.
- `World.moveTo(roomKey)` added (used by go handler).
- `chest` added: `portable=false`, `locked=true`, `lockKey="iron_key"`.
  Stub object for testing lock/unlock. Not game content.
- `locked?: bool` and `lockKey?: string` added to `GameObject` (types.ts).

**Additional handlers (post-M1b):**
- `put` — verify: dobj must be in inventory. Action: moves dobj to current
  room, returns "You put the X on/in the Y." using intent.prep. Full
  container placement (dobj inside iobj) deferred to Milestone 3.
- `unlock` / `lock` — verify: object must be lockable (locked != nil) and
  in the correct state. Check: `World.getObject(obj.lockKey) ~= intent.iobjRef`
  (identity comparison — no key property needed on objects). Action: toggles
  `obj.locked`.

**Direction verbs:**
- Each direction is its own canonical verb (`north`, `south`, `east`, `west`,
  `up`, `down`, `in`, `out`) with single-letter abbreviation synonyms where
  applicable (`n`, `s`, `e`, `w`, `u`, `d`).
- The go handler is registered under all direction names as well as "go".
- Direction source: `intent.dobjWords[1]` (for "go north") or `intent.verb`
  when verb is not "go" (for bare "north"). The handler checks
  `intent.verb ~= "go"` before falling back to `intent.verb`.
- `in` as a direction works safely — the tagger only scans `rest` (tokens
  after the verb) for prepositions, never `tokens[1]`.

**Verb set additions:**
- `lock` added alongside `unlock` (two-object, resolveFirst="dobj").
- `wait` (synonyms: wait, z), `help` (synonyms: help, ?), `quit` (synonyms:
  quit, q) added. Handlers to be implemented in Milestone 2 (terminal layer).
- Total canonical verbs: 25.

### M1b design notes — take, drop, go handlers

Researched against TADS 3 adv3 documentation. Key decisions:

**Object portability — two distinct properties, two distinct failure phases:**

- `fixed = true` on an object → fail at **verify** with `illogical`.
  For objects obviously part of the room (a wall, a built-in shelf).
  The resolver should never consider these as candidates during disambiguation.

- `portable = false` on an object → fail at **check**.
  For objects that look moveable but aren't (heavy furniture, etc.).
  These rank logically during disambiguation so the parser picks the right
  object, then block with an explanation at check.

The writing desk in the world stub is correctly `portable = false` (check
failure). It is not `fixed` — a player would logically try to take a desk.

**"Already held" → `illogicalAlready` at verify, not check.**
If the object is already in inventory, verify returns `{ illogicalAlready = "..." }`
(rank 40). This steers disambiguation away from already-held items while ranking
them above truly fixed objects (illogical, rank 30).

**take handler phases:**
- verify: if obj.fixed → { illogical = "..." }; if already in inventory →
  { illogicalAlready = "..." }; else → { logical = true }
- check: if obj.portable == false → return blocking string
- action: World.moveObject(obj, "inventory"); return "Taken."

**drop handler phases:**
- verify: obj must be in inventory (illogical if not holding it)
- action: World.moveObject(obj, World.currentRoomKey()); return "Dropped."
- Note: TADS has a dropLocation concept (items may not land in the room itself
  if the player is inside a nested location/vehicle). Defer to Milestone 3.

**go handler:**
- resolveObj = false; direction word is in intent.dobjWords, not a resolved object.
- action: look up direction in room.exits; handle string (room key) or function
  (per CLAUDE.md Rule 6); return describeCurrentRoom() on success.
- Requires new World.moveTo(roomKey) function.
- beforeTravel/afterTravel notifications: defer to Milestone 3.
- Darkness blocking travel: defer to Milestone 2/3.

---

## Milestone 2 — LÖVE2D terminal (Lua only)

- [x] Terminal shell: scrolling buffer, input line, command history
- [x] LÖVE2D main.lua wiring
- [x] Colour scheme (see architecture doc)
- [x] Room description rendering (calls description as function)
- [ ] love.filesystem save/load stub — deferred to Milestone 3

### M2 implementation notes

**`engine/lua/terminal.lua`** — full LÖVE2D terminal.
- `Terminal.init()` — loads font, sets window title, resets world, shows starting room.
- `Terminal.submit(raw)` — echoes command, resets scrollOffset to 0, calls
  `Parser.process()`, applies colour heuristics to output.
- `Terminal.keypressed(key)` — Enter, Backspace, Up/Down (history), PageUp/PageDown,
  Home, End, Ctrl+V (paste).
- `Terminal.textinput(t)` — appends typed character.
- `Terminal.wheelmoved(_, dy)` — dy > 0 = wheel up = scroll toward older content.
- `Terminal.updateCursor(dt)` — 0.5s blink cycle.
- `Terminal.draw()` — background, word-wrapped output lines, scrollbar, input line,
  blinking cursor.

**Room title colour heuristic:** if parser output contains a newline and the first
line is ≤ 40 chars with no sentence-ending punctuation, the first line is coloured
`roomTitle` and the rest `response`. Replaced by typed response objects in M3.

**Rendered-line cache:** `font:getWrap()` is called once per buffer change or window
resize, not every frame. Cache is invalidated via `renderDirty` flag set by `pushLine`.

**Scrollbar:** 4px track on the right edge of the output area, only visible when
content exceeds the viewport. Thumb position and height are proportional.

**`test` meta-command:** intercepted before the parser. Calls `runTests(printFn)`
from `test/parser_test.lua` with a colour-routing print function (PASS→system,
FAIL→error, headers→narrator, summary→error if failures). After the run, calls
`World.reset()`, `Parser.reset()`, and re-describes the starting room.

**`quit` / `q` meta-command:** intercepted before the parser. Calls
`love.event.push("quit")` after printing "Goodbye." so the final frame is drawn.

**`test/parser_test.lua`** — `run()` now accepts an optional `printFn` argument
(defaults to Lua's built-in `print`). Headless CLI behaviour unchanged.

**`world/defaults.lua` / `defaults.ts`** — `wait`, `help`, `quit` handlers added.
`wait` returns "Time passes.". `help` returns a command list. `quit` returns
"Goodbye." (fallback for headless/browser contexts; LÖVE2D terminal intercepts it).

---

## Milestone 3 — JSON loader and data schema (both languages)

- [x] Define JSON schema for rooms, objects (data-only subset; handler registry deferred)
- [x] Lua loader: reads JSON, instantiates world model
- [x] TypeScript loader: same JSON, same contract
- [ ] Handler registry: named handlers registered in engine,
      referenced by string from JSON
- [ ] AI narrator response layer: per-room, per-object, per-verb overrides
- [ ] Cross-period inventory tracking in world model
- [ ] Period overlay system for revisitable periods

### M3 implementation notes (data layer)

**JSON schema — current subset:**

`game/data/rooms.json` — `{ startRoom, rooms: { key: { name, description, exits, objects } } }`
Room `description` is either a plain string or `{ firstVisit, revisit }`. The loader
converts both forms to `function(self, ctx) → string` at load time. The `revisit`
key name avoids the Lua reserved word `repeat`.

`game/data/objects.json` — `{ key: { name, aliases, adjectives, description, location,
portable, fixed?, locked?, lockKey? } }`. JSON `null` location decodes to Lua `nil`
(field absent), which is the correct "not in world" sentinel.

**`lib/json.lua`** — rxi/json.lua (MIT). Works in both LÖVE2D and headless Lua.
Required as `require("lib.json")` from the project root.

**`engine/lua/loader.lua`** — `Loader.load()` reads both JSON files via `io.open`
(falls back to `love.filesystem.read` if available), parses them, builds room and
object tables, calls `World.load()`.

**`engine/typescript/src/world/loader.ts`** — `loadWorld()` uses Vite's static JSON
imports (`import roomsJson from '../../../../game/data/rooms.json'`). Requires
`"resolveJsonModule": true` in tsconfig.json.

**`world.lua` / `world.ts`** — hardcoded data removed. `World.load(rooms, objects,
startRoom)` populates the tables and snapshots mutable state (`location`, `locked`,
`visited`) for `reset()`. `World.reset()` restores from that snapshot rather than
hardcoded values. Both runtimes now load identically from the same JSON files.

**`test/parser_test.lua`** — calls `Loader.load()` at module level (before `run()`)
so the world is populated before any test calls `World.reset()`.

**`engine/lua/terminal.lua`** — `Terminal.init()` now calls `Loader.load()` then
`World.reset()` instead of just `World.reset()`.

---

## Milestone 4 — game content

- [ ] First rooms and objects authored in JSON
- [ ] Seed game: enough to walk around, pick things up, examine them
- [ ] Something playable and publicly visible on the website

---

## Running tests

Headless, no LÖVE2D required:

```bash
lua test/parser_test.lua
```

All tests must pass before any other work in a session begins.
If a test is failing at session start, fix it before adding anything new.

---

## End of session protocol

Before closing VS Code at the end of each session:

1. Run the test suite. Confirm all passing.
2. Ask Claude Code: "Update CLAUDE.md with any decisions made today
   that are not already recorded here."
3. Update GUIDE.md to reflect any new files, commands, or structure
   added during the session.
4. Commit everything including the updated CLAUDE.md and GUIDE.md.

This file is the project's memory. Keep it current.

---

## Developer guides

Each engine has its own GUIDE.md alongside the code:
  - engine/typescript/GUIDE.md — TypeScript/browser engine
  - engine/lua/GUIDE.md — Lua/LÖVE2D engine

The root GUIDE.md is an index only — do not put content there.

Update the relevant GUIDE.md whenever:
  - New files or directories are added to that engine
  - A new command is needed to build, test, or deploy
  - The server or tooling setup changes
  - A milestone is completed

Guides are written for someone new to web development.
They must always reflect the current state of the project.