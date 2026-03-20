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

Full specification in `docs/architecture.md`.
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
│   └── architecture.md
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

### 2. verify() must never modify game state
Called multiple times per turn during object resolution. Side effects will
fire at the wrong time or too many times. verify() may only read state and
return a result table / object.

### 3. Handlers return strings; they never print or console.log
All output flows upward to the terminal layer. Game logic is testable
without any runtime (LÖVE2D or browser) running.

### 4. The three phases must not be collapsed
verify(), check(), and action() are distinct phases with distinct purposes:
- verify(): is this logical from the player's perspective? Used for
  disambiguation. Must not modify state.
- check(): can this proceed given conditions the player couldn't know?
  Called after objects are resolved. May block with explanation.
- action(): execute the effect, return output string.

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

## The disambiguation state machine

States: NORMAL, AWAIT_CLARIFY

On FAIL_AMBIGUOUS from resolver:
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

- [ ] verify() scoring in resolver
- [ ] Disambiguation FSM (NORMAL / AWAIT_CLARIFY)
- [ ] Indirect object resolution (resolveFirst per verb)
- [ ] Default handlers: take, drop, go
- [ ] Extended tests covering disambiguation and two-object verbs
- [ ] TypeScript port of all of the above

---

## Milestone 2 — LÖVE2D terminal (Lua only)

- [ ] Terminal shell: scrolling buffer, input line, command history
- [ ] LÖVE2D main.lua wiring
- [ ] Colour scheme (see architecture doc)
- [ ] Room description rendering (calls description as function)
- [ ] love.filesystem save/load stub

---

## Milestone 3 — JSON loader and data schema (both languages)

- [ ] Define JSON schema for rooms, objects, events, handlers
- [ ] Lua loader: reads JSON, instantiates world model
- [ ] TypeScript loader: same JSON, same contract
- [ ] Handler registry: named handlers registered in engine,
      referenced by string from JSON
- [ ] AI narrator response layer: per-room, per-object, per-verb overrides
- [ ] Cross-period inventory tracking in world model
- [ ] Period overlay system for revisitable periods

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