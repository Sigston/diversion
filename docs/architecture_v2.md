# Engine Architecture Reference — v2
## Diversion — Interactive Fiction Engine

> **Runtimes:** Lua/LÖVE2D (local development) · TypeScript (web deployment)
> **Data format:** JSON (runtime-agnostic, loaded by both runtimes)
> **Design lineage:** Informed by TADS 3 adv3Lite, particularly its three-phase
> execution model and disambiguation-by-logicalness approach.
> **Changelog:** v2 incorporates corrections identified in `docs/tads3-adv3lite-reference.md`.
> See Section 18 of `docs/architecture.md` for a full explanation of each change.

---

## Table of Contents

1. [Design Principles](#1-design-principles)
2. [Layer Diagram](#2-layer-diagram)
3. [File & Module Structure](#3-file--module-structure)
4. [The Parser Pipeline](#4-the-parser-pipeline)
   - 4.1 [CommandIntent — the contract type](#41-commandintent--the-contract-type)
   - 4.2 [Stage 1: Tokeniser](#42-stage-1-tokeniser)
   - 4.3 [Stage 2: Tagger](#43-stage-2-tagger)
   - 4.4 [Stage 3: Resolver](#44-stage-3-resolver)
   - 4.5 [Disambiguation State Machine](#45-disambiguation-state-machine)
   - 4.6 [Indirect Object Resolution Order](#46-indirect-object-resolution-order)
5. [The Three-Phase Execution Cycle](#5-the-three-phase-execution-cycle)
   - 5.1 [Phase Overview](#51-phase-overview)
   - 5.2 [verify() — Logicalness Scoring](#52-verify--logicalness-scoring)
   - 5.3 [check() — Precondition Enforcement](#53-check--precondition-enforcement)
   - 5.4 [action() — Effect](#54-action--effect)
   - 5.5 [Dispatcher Lookup Order](#55-dispatcher-lookup-order)
6. [World Model](#6-world-model)
   - 6.1 [Rooms](#61-rooms)
   - 6.2 [Objects](#62-objects)
   - 6.3 [Scope Rules](#63-scope-rules)
   - 6.4 [Object Location Model](#64-object-location-model)
   - 6.5 [World Structure](#65-world-structure)
7. [Lexicon Tables](#7-lexicon-tables)
8. [The JSON Data Layer](#8-the-json-data-layer)
   - 8.1 [Schema: rooms.json](#81-schema-roomsjson)
   - 8.2 [Schema: objects.json](#82-schema-objectsjson)
   - 8.3 [Schema: events.json](#83-schema-eventsjson)
   - 8.4 [Schema: handlers.json](#84-schema-handlersjson)
   - 8.5 [The Loader](#85-the-loader)
   - 8.6 [Handler Registry](#86-handler-registry)
9. [The AI Narrator Response Layer](#9-the-ai-narrator-response-layer)
10. [The Terminal / UI Shell](#10-the-terminal--ui-shell)
11. [The LÖVE2D Presentation Layer](#11-the-löve2d-presentation-layer)
12. [The TypeScript / Browser Layer](#12-the-typescript--browser-layer)
13. [State Manager](#13-state-manager)
14. [Default Verb Handlers](#14-default-verb-handlers)
15. [Special Mechanics](#15-special-mechanics)
    - 15.1 [Time Machine](#151-time-machine)
    - 15.2 [Cross-Period Inventory](#152-cross-period-inventory)
    - 15.3 [Telescope](#153-telescope)
    - 15.4 [Revisitable Periods](#154-revisitable-periods)
16. [Known Extension Points](#16-known-extension-points)
17. [TADS 3 Design Influences](#17-tads-3-design-influences)

---

## 1. Design Principles

**Handlers return strings; they never print.** Output always flows upward to the
terminal layer. The entire game logic stack is testable without any runtime
(LÖVE2D or browser) running.

**Resolved intents are the contract.** Every component below the resolver
operates on `CommandIntent` structs, never raw strings. This is the single most
important architectural invariant.

**The verify/check/action cycle must never be collapsed.** These three phases are
meaningfully distinct. Conflating them produces bugs that are difficult to
diagnose. See Section 5.

**Object state lives on the object.** Properties like `locked`, `lit`, `open`
live on the object table. Global state flags are reserved for story-level events
(`bridge_open`, `met_hermit`). Never store object state in flags.

**Scope is computed dynamically.** The resolver queries the world model on every
command. Scope is never cached between turns.

**The disambiguation state machine lives in the parser.** Game handlers never
observe disambiguation state. They always receive a complete, fully resolved
`CommandIntent`.

**World data is fully separated from engine code.** Everything under `game/data/`
is pure JSON. No engine module is referenced from game data. Dependencies flow
downward only: presentation → parser → world → data.

**Room descriptions are functions, not strings.** Descriptions take a context
argument (at minimum: current state flags relevant to that room) and return a
string. Never read a description as a plain property.

**Exits may be functions.** An exit value may be a string (room key) or a
callable that returns a string or null/nil. The `go` handler must check type and
call accordingly. A null return means the exit is present but not currently
traversable — return a specific message from the blocking object, not a generic
fallback.

---

## 2. Layer Diagram

```
┌─────────────────────────────────────────────┐
│      Runtime Presentation Layer             │
│      main.lua  /  index.ts                  │
├─────────────────────────────────────────────┤
│      Terminal / UI Shell                    │
│      scrolling buffer, prompt, history,     │
│      colour output                          │
├─────────────────────────────────────────────┤
│      AI Narrator Response Layer             │
│      authored overrides, fallback messages  │
├─────────────────────────────────────────────┤
│      Parser Pipeline                        │
│      tokeniser → tagger → resolver          │
│               → disambiguator → dispatcher  │
├─────────────────────────────────────────────┤
│      Command Execution Cycle                │
│      verify() → check() → action()          │
├─────────────────────────────────────────────┤
│      World Model                            │
│      rooms, objects, scope, relations       │
├─────────────────────────────────────────────┤
│      Game Logic / Handler Registry          │
│      named handlers, event hooks            │
├─────────────────────────────────────────────┤
│      State Manager                          │
│      flags, period state, save/load         │
├─────────────────────────────────────────────┤
│      JSON Data Layer                        │
│      rooms.json, objects.json,              │
│      events.json, handlers.json             │
└─────────────────────────────────────────────┘
```

---

## 3. File & Module Structure

```
/
├── CLAUDE.md                         session briefing, updated each session
├── docs/
│   ├── architecture.md               v1 with change log appended
│   ├── architecture_v2.md            this document
│   ├── tads3-adv3lite-reference.md   source research document
│   └── [game design docs]            not engine concerns
│
├── engine/
│   ├── lua/
│   │   ├── main.lua                  LÖVE2D entry point
│   │   ├── terminal.lua              UI shell
│   │   ├── loader.lua                JSON loader + handler wiring
│   │   ├── parser/
│   │   │   ├── init.lua              parser entry point, disambiguation FSM
│   │   │   ├── tokeniser.lua
│   │   │   ├── tagger.lua
│   │   │   ├── resolver.lua
│   │   │   └── dispatcher.lua
│   │   ├── world/
│   │   │   ├── world.lua             world model, scope queries
│   │   │   ├── state.lua             flags, save/load
│   │   │   └── defaults.lua          default verb handlers
│   │   └── lexicon/
│   │       ├── verbs.lua
│   │       ├── prepositions.lua
│   │       └── stopwords.lua
│   │
│   └── typescript/
│       ├── src/
│       │   ├── main.ts               browser entry point
│       │   ├── terminal.ts           browser terminal UI
│       │   ├── loader.ts             JSON loader + handler wiring
│       │   ├── parser/
│       │   │   ├── index.ts
│       │   │   ├── tokeniser.ts
│       │   │   ├── tagger.ts
│       │   │   ├── resolver.ts
│       │   │   └── dispatcher.ts
│       │   ├── world/
│       │   │   ├── world.ts
│       │   │   ├── state.ts
│       │   │   └── defaults.ts
│       │   └── lexicon/
│       │       ├── verbs.ts
│       │       ├── prepositions.ts
│       │       └── stopwords.ts
│       ├── package.json
│       ├── tsconfig.json
│       └── vite.config.ts
│
├── game/
│   └── data/
│       ├── rooms.json
│       ├── objects.json
│       ├── events.json
│       └── handlers.json             named handler registry entries (data only)
│
└── test/
    ├── parser_test.lua               canonical smoke test — must pass first
    └── [additional test files]
```

> **Rule:** `game/data/` must never contain executable code. Logic lives in the
> engine's handler registry, referenced by name from the data files.

---

## 4. The Parser Pipeline

The parser transforms a raw player string into a fully resolved `CommandIntent`
through four stages, then passes it to the three-phase execution cycle.

```
raw string
    → [Tokeniser]     raw string → token list
    → [Tagger]        tokens → partial CommandIntent (verb, noun phrases, prep)
    → [Resolver]      noun phrases → object refs + verify scoring
    → [Disambiguator] FSM: resolve ambiguity or surface clarification question
    → [Dispatcher]    fully resolved intent → verify/check/action cycle
```

### 4.1 CommandIntent — the contract type

The contract shared across all pipeline stages. Define once; use everywhere
below the resolver.

**Lua:**
```lua
-- All fields present on every intent; unset fields are nil
{
    verb       = string,        -- canonical verb ("put", "take", "examine")
    dobjWords  = {string},      -- adjective(s) + noun of direct object
    dobjRef    = object|nil,    -- resolved object reference (set by resolver)
    prep       = string|nil,    -- preposition ("in", "on", "with", "from")
    iobjWords  = {string}|nil,  -- adjective(s) + noun of indirect object
    iobjRef    = object|nil,    -- resolved object reference (set by resolver)
    auxWords   = {string}|nil,  -- RESERVED: third noun phrase
    auxRef     = object|nil,    -- RESERVED: third resolved object
}
```

**TypeScript:**
```typescript
interface CommandIntent {
    verb:       string;
    dobjWords:  string[];
    dobjRef:    GameObject | null;
    prep:       string | null;
    iobjWords:  string[] | null;
    iobjRef:    GameObject | null;
    auxWords:   string[] | null;   // RESERVED
    auxRef:     GameObject | null; // RESERVED
}
```

> **Note:** The `aux` fields reserve space for three-object verbs
> (`PUT COIN IN SLOT WITH TONGS`). Do not implement in Milestone 1.
> Do not remove from the type definition.

---

### 4.2 Stage 1: Tokeniser

Lowercases input, strips punctuation, splits on whitespace. Returns a flat
array of strings. Optionally expands common contractions.

```
Input:  "Put the old leather satchel on the shelf!"
Output: ["put", "the", "old", "leather", "satchel", "on", "the", "shelf"]
```

Articles and determiners are preserved at this stage. They are stripped later
by the tagger. The tokeniser does not consult the lexicon.

---

### 4.3 Stage 2: Tagger

Applies grammar rules to produce a partially-populated `CommandIntent`. Does not
touch the world model — uses lexicon tables only.

**Algorithm:**
1. First non-stopword token looked up in verb lexicon → canonical verb
2. Scan remaining tokens for a known preposition → splits into dobj/iobj spans
3. Strip stopwords (articles, determiners) from each span
4. Remaining tokens in each span = adjective(s) + noun (last token assumed noun)

```
Input tokens: ["unlock", "the", "iron", "door", "with", "the", "hare", "key"]

Result:
{
    verb      = "unlock",
    dobjWords = ["iron", "door"],
    prep      = "with",
    iobjWords = ["hare", "key"],
}
```

Synonym normalisation happens here. The player's token is looked up against the
verb lexicon's synonym lists and replaced with the canonical verb. All downstream
components only ever see canonical verbs.

---

### 4.4 Stage 3: Resolver

Turns noun-phrase word lists into actual object references. This is where scope
is queried and disambiguation scoring runs.

**For each noun phrase (dobjWords, iobjWords):**

```
1. Query World.inScope() → candidate list
   Scope = current room objects
         + objects in open containers in scope
         + player inventory

2. Filter candidates:
   Match noun (last word in phrase) against object.name, object.aliases
   Match adjectives (preceding words) against object.adjectives
   A candidate must match the noun; adjectives narrow but are not required

3. If 0 candidates  → return FAIL_NOT_FOUND

4. If 1 candidate   → assign to intent.dobjRef / intent.iobjRef

5. If N candidates  → call handler.verify() on each candidate
                       Map result to numeric rank via verifyRank()
                       If one candidate has uniquely highest rank → AUTO-RESOLVE
                       If tied → return FAIL_AMBIGUOUS with tied candidate list
```

**verifyRank() helper** — maps verify result types to numeric ranks:

```lua
local function verifyRank(result)
    if not result                  then return 100 end
    if result.logical              then return result.rank or 100 end
    if result.dangerous            then return 90  end
    if result.illogicalAlready     then return 40  end
    if result.illogicalNow         then return 40  end
    if result.illogical            then return 30  end
    if result.nonObvious           then return 30  end
    return 100
end
```

> **TADS 3 insight:** `verify()` is called here, before action execution.
> Its purpose is disambiguation, not blocking. Only use `verify()` to express
> what is obvious to the player. Use `check()` for conditions the player
> could not know in advance. See Section 5.2.

> **Critical rule:** Verify functions must base their decision only on
> properties of their own object and on global state (State flags, World
> queries). They must **never** read `intent.dobjRef` or `intent.iobjRef` —
> the other object's reference is not guaranteed to be set when verify() is
> called during the resolver pass. When the resolver is scoring iobj candidates
> (resolveFirst = "iobj"), dobjRef is nil; when scoring dobj candidates,
> iobjRef may be nil.

**Resolution order for two-object verbs** is configurable per canonical verb.
Default: resolve indirect object first. See Section 4.6.

---

### 4.5 Disambiguation State Machine

Owned by `parser/init.lua` (Lua) or `parser/index.ts` (TypeScript).

```
States:
  NORMAL          standard input processing
  AWAIT_CLARIFY   resolver returned ambiguous; partial intent stored

─────────────────────────────────────────────────────────────────────

On AUTO-RESOLVE (one candidate has uniquely highest rank,
                 and N > 1 candidates were scored):
  1. Prepend "(the [object.name])" to the eventual output
  2. Assign resolved object to intent.dobjRef / intent.iobjRef
  3. Remain in NORMAL
  4. Continue to dispatch
  Note: if only one candidate matched at all, no announcement is printed.

On FAIL_AMBIGUOUS (top-ranked candidates are tied):
  1. Store partial intent + tied candidate list
  2. Transition → AWAIT_CLARIFY
  3. Emit: "Which do you mean — the [candidate 1], or the [candidate 2]?"

On next player input (while AWAIT_CLARIFY):
  1. Interpret input as noun/adjective selecting one candidate
  2. Complete stored intent
  3. Transition → NORMAL
  4. Dispatch completed intent

On FAIL_NOT_FOUND:
  1. Emit: "You don't see any [noun] here."
  2. Remain in NORMAL (no state change)

─────────────────────────────────────────────────────────────────────
```

Game handlers never observe disambiguation state. They always receive a
complete, fully resolved `CommandIntent`.

---

### 4.6 Indirect Object Resolution Order

For two-object verbs, resolution order matters semantically. This is
configurable per canonical verb in the lexicon.

```lua
-- lexicon/verbs.lua
verbLexicon["put"]    = { synonyms = {...}, resolveFirst = "iobj" }  -- default
verbLexicon["unlock"] = { synonyms = {...}, resolveFirst = "dobj" }  -- exception
verbLexicon["give"]   = { synonyms = {...}, resolveFirst = "iobj" }
```

Do not hardcode resolution order in the resolver. Always read from the verb entry.

---

## 5. The Three-Phase Execution Cycle

Once the resolver produces a fully resolved `CommandIntent`, the dispatcher runs
the three-phase cycle. **These phases must never be collapsed.**

### 5.1 Phase Overview

| Phase | Purpose | May modify state? | Used by resolver? |
|---|---|---|---|
| `verify()` | Is this action logical from the player's perspective? Ranks candidates for disambiguation. | **Never** | Yes — called during resolution |
| `check()` | Can this action proceed given conditions the player couldn't know? | Must not change world state. May set tracking flags. | No — called after resolution |
| `action()` | Execute the effect. Return output string. | Yes | No |

---

### 5.2 verify() — Logicalness Scoring

`verify()` has two jobs: disambiguation ranking, and hard-blocking obviously
impossible actions. It must never modify game state — it is called twice per
command (once during the resolver pass to rank candidates, once in the
dispatcher as a final gate).

**Core principle:** "Logical" means what the *player* thinks — not the author,
not the player character, not an omniscient narrator. The question is always
"would the player think this is an obviously stupid thing to try?"

**Full result type hierarchy (ranked most to least logical):**

```lua
-- Lua
{ logical = true }                        -- rank 100; no objection (default)
{ logical = true, rank = 150 }            -- custom rank; preferred candidate
{ dangerous = true }                      -- rank 90; explicit OK, no auto-select
{ illogicalAlready = "msg" }              -- rank 40; action already accomplished
{ illogicalNow = "msg" }                  -- rank 40; currently impossible (state)
{ illogical = "msg" }                     -- rank 30; inherently impossible always
{ nonObvious = true }                     -- rank 30; explicit OK, no auto-select
```

```typescript
// TypeScript
type VerifyResult =
    | { logical: true; rank?: number }
    | { dangerous: true }
    | { illogicalAlready: string }
    | { illogicalNow: string }
    | { illogical: string }
    | { nonObvious: true }
```

**When to use each:**

- `logical` — default; the action makes obvious sense for this object.
- `logicalRank(n)` — fine-tune preference when one candidate is clearly better
  than another. Use 150 for "especially good fit" (e.g. a key when unlocking).
- `dangerous` — the action is possible but should not be auto-selected (e.g.
  attacking an NPC, opening an airlock). The player must explicitly intend it.
- `illogicalAlready` — the action has already been done ("You're already
  carrying that.", "The door is already open."). Ranks above `illogical` so a
  "held item" loses disambiguation to an "in-scope item", not to a fixed fixture.
- `illogicalNow` — currently impossible due to game state ("The lamp is not
  lit.", "The raft is deflated."). Same rank as `illogicalAlready`.
- `illogical` — inherently wrong, always, for this object ("You can't take a
  wall.", "That's part of the room."). Use for `fixed = true` objects.
- `nonObvious` — the action is possible but shouldn't be auto-selected or used
  as a default. For puzzle solutions that shouldn't be obvious.

**`dangerous` vs `nonObvious`:** Both allow explicit commands and block
auto-selection. `dangerous` (rank 90) ranks above the default `logical` (100)
threshold, meaning it loses auto-selection to a logical candidate but is
preferred over illogical ones. `nonObvious` (rank 30) ties with `illogical`,
meaning it never wins auto-selection against any logical candidate.

**Example:**
```lua
objects["iron_door"].handlers.open = {
    verify = function(self, intent)
        if self.open then
            return { illogicalNow = "The door is already open." }
        end
        return { logical = true, rank = 150 }  -- prefer closed doors
    end,
}
```

> **Rule:** `verify()` must never call `World.move()`, change object properties,
> modify state flags, or produce any output. It is a pure read-only query.
> It must never read `intent.dobjRef` or `intent.iobjRef` (see Section 4.4).

---

### 5.3 check() — Precondition Enforcement

`check()` enforces conditions the player could not know in advance. It is called
after objects are fully resolved. It cannot influence disambiguation — the
resolver never calls it.

Returns `nil` to allow the action to proceed, or a string to block it.

```lua
objects["black_box"].handlers.open = {
    check = function(self, intent)
        if self.glued then
            return "The box has been sealed shut. You'd need something to work it open."
        end
        -- nil = allow
    end,
}
```

The distinction from `verify()`: the player cannot know the box is glued until
they try. If this condition were in `verify()`, the resolver might steer around
the black box silently during disambiguation — the player would never see the
"glued shut" message, which is the point.

**Design rule:** "Would a reasonable player consider this *obviously* the wrong
thing to try?" If yes → verify. If no → check.

> **State rule:** check() must not change world state (move objects, change
> room properties, set story flags). It *may* set tracking flags on the object
> itself to record player behaviour (e.g. `self.attemptedOpen = true`), for use
> in narrator responses or hint systems.

---

### 5.4 action() — Effect

Called only if `verify()` and `check()` both pass. Makes changes to game state
and returns the output string. Use `World.moveObject()` for all object moves —
never write `obj.location` directly.

```lua
objects["iron_door"].handlers.open = {
    action = function(self, intent)
        self.open = true
        State.set("iron_door_open", true)
        return "The door opens without resistance. Beyond it, a stair descends."
    end,
}
```

---

### 5.5 Dispatcher Lookup Order

```lua
function Dispatcher.dispatch(intent)
    local verb = intent.verb
    local obj  = intent.dobjRef     -- nil for verbs like look, inventory
    local room = World.currentRoom()

    -- 1. Object-specific handler
    if obj and obj.handlers and obj.handlers[verb] then
        return Dispatcher.runCycle(obj.handlers[verb], obj, intent)
    end

    -- 2. Room-level handler intercept
    if room.handlers and room.handlers[verb] then
        return Dispatcher.runCycle(room.handlers[verb], room, intent)
    end

    -- 3. Global default handler
    if Defaults[verb] then
        return Dispatcher.runCycle(Defaults[verb], obj, intent)
    end

    return Narrator.fallback("cantDo", intent)
end

function Dispatcher.runCycle(handler, obj, intent)
    -- Phase 1: verify (second pass — first was in the resolver)
    if handler.verify then
        local result = handler.verify(obj, intent)
        if result then
            local msg = result.illogical or result.illogicalAlready or result.illogicalNow
            if msg then
                return Narrator.override(msg, obj, intent) or msg
            end
        end
    end
    -- Phase 2: check
    if handler.check then
        local block = handler.check(obj, intent)
        if block then
            return Narrator.override(block, obj, intent) or block
        end
    end
    -- Phase 3: action
    if handler.action then
        local output = handler.action(obj, intent)
        return Narrator.wrap(output, obj, intent) or output
    end
    return Narrator.fallback("nothingHappens", intent)
end
```

**Two-object handler dispatch — deliberate simplification:** For two-object verbs
(PUT X IN Y), the dispatcher calls `runCycle` only on the **dobj's handler**.
The iobj's handler is consulted by the **resolver** during disambiguation scoring
(its verify() is called on iobj candidates), but once both objects are resolved,
the iobj's handler is not further invoked by the dispatcher.

The dobj's handler receives the full `intent` including `intent.iobjRef` and is
responsible for the complete action logic. This is a conscious simplification
from adv3Lite's split dobjFor/iobjFor chains. It is sufficient for this game's
scope. If a future verb needs iobj-level check logic, the dobj's action can
manually delegate to `intent.iobjRef.handlers[verb]`.

---

## 6. World Model

### 6.1 Rooms

```lua
rooms["player_quarters"] = {
    name        = "Your Quarters",
    description = function(ctx)
        -- ctx contains relevant state flags
        if ctx.firstVisit then
            return "Long description on first visit..."
        end
        return "Short description on subsequent visits..."
    end,
    exits   = {
        north = "observation_deck",
        down  = function()
            -- Exits may be functions returning a room key or nil
            if State.get("time_machine_ready") then
                return "time_machine_chamber"
            end
            return nil  -- not traversable; go handler uses blocking message
        end,
    },
    objects  = { "telescope", "time_machine", "writing_desk" },
    handlers = {},      -- room-level verb intercepts
    visited  = false,
    on_enter = function()
        -- Optional: fires on entry, return string or nil
    end,
}
```

---

### 6.2 Objects

**Portability properties — two distinct properties, two distinct failure phases:**

- `fixed = true` — The object is obviously, inherently part of the room (a wall
  fixture, a mounted torch, a built-in shelf). Fails at **verify** with
  `{ illogical = "..." }`. The resolver never considers fixed objects as
  candidates during disambiguation — rank 30 ensures any portable object wins.
  Equivalent to adv3Lite's `isFixed = true`.

- `portable = false` — The object looks moveable but isn't (heavy furniture, a
  boulder). Fails at **check** with an explanation string. The resolver *does*
  consider these as valid disambiguation candidates (rank 100, logical), then
  the check phase blocks with an explanation after resolution.

- Neither set (default) — Object is fully portable.

```lua
objects["iron_key"] = {
    name        = "iron key",
    aliases     = { "key", "hare key" },
    adjectives  = { "iron", "corroded", "small", "old" },
    description = "An iron key. The bow is cast in the form of a running hare.",
    location    = nil,
    fixed       = nil,      -- not fixed; default
    portable    = true,     -- default; fully portable
    handlers    = {
        examine = {
            action = function(self, intent)
                return self.description
            end,
        },
    },
    narratorResponses = {
        take    = "How convenient that you found it.",
        examine = nil,
    },
}

objects["writing_desk"] = {
    name        = "writing desk",
    aliases     = { "desk" },
    adjectives  = { "writing", "large", "wooden" },
    description = "A large wooden writing desk.",
    location    = "player_quarters",
    fixed       = nil,      -- not fixed: player would logically try to take it
    portable    = false,    -- check failure: too heavy to lift
    handlers    = {},
}

objects["wall_sconce"] = {
    name        = "wall sconce",
    aliases     = { "sconce", "torch" },
    adjectives  = { "wall", "iron" },
    description = "An iron sconce fixed to the wall.",
    location    = "player_quarters",
    fixed       = true,     -- verify failure: obviously part of the room
    handlers    = {},
}
```

---

### 6.3 Scope Rules

The resolver calls `World.inScope()` on every turn. The result is never cached.

**In scope:**
- Objects in the current room's `objects` list
- Objects in open containers that are themselves in scope (recursive)
- Objects in player inventory
- The time machine and telescope when in the player's quarters

**Out of scope:**
- Objects in closed or locked containers
- Objects in other rooms
- Objects in other time periods (except items the player carried in on this visit)

---

### 6.4 Object Location Model

Object `location` is one of:

```lua
"inventory"                         -- player is carrying it
"room_key"                          -- string: in named room, current period
{ period = "1963", room = "study" } -- in a specific room of a specific period
nil                                 -- not yet in the world (spawned by trigger)
```

This model supports cross-period inventory tracking without requiring changes to
the resolver. The resolver asks `World.inScope()`, which handles period-aware
location resolution internally.

---

### 6.5 World Structure

The primary structure is a **room graph**: locations as nodes, exits as directed
edges. Narrative events are hooks on rooms and objects (`on_enter`,
`on_first_examine`, `on_take`).

Branching narrative sequences (the time machine transition, the telescope view)
are modelled as pseudo-rooms or special handlers — not as a separate scene
system. Everything is a room. This keeps the architecture uniform.

---

## 7. Lexicon Tables

Built at load time into a reverse-lookup map (word → canonical verb). Game code
only ever sees canonical verb strings.

```lua
-- lexicon/verbs.lua
return {
    take     = { synonyms = {"take","get","pick up","grab","acquire"},
                 resolveObj = true, resolveFirst = "dobj" },
    drop     = { synonyms = {"drop","put down","leave","discard"},
                 resolveObj = true, resolveFirst = "dobj" },
    examine  = { synonyms = {"examine","x","inspect","look at","read"},
                 resolveObj = true, resolveFirst = "dobj" },
    go       = { synonyms = {"go","walk","move","travel","head"},
                 resolveObj = false },
    put      = { synonyms = {"put","place","insert","set","lay"},
                 resolveObj = true, resolveFirst = "iobj" },
    unlock   = { synonyms = {"unlock"},
                 resolveObj = true, resolveFirst = "dobj" },
    open     = { synonyms = {"open"},
                 resolveObj = true, resolveFirst = "dobj" },
    close    = { synonyms = {"close","shut"},
                 resolveObj = true, resolveFirst = "dobj" },
    look     = { synonyms = {"look","l"},
                 resolveObj = false },
    inventory= { synonyms = {"inventory","i","inv"},
                 resolveObj = false },
}
```

---

## 8. The JSON Data Layer

### 8.1 Schema: rooms.json

```json
{
  "player_quarters": {
    "name": "Your Quarters",
    "descriptionHandler": "handlers.rooms.playerQuarters.description",
    "exits": {
      "north": "observation_deck",
      "down": "handlers.exits.playerQuarters.down"
    },
    "objects": ["telescope", "time_machine", "writing_desk"],
    "onEnter": "handlers.rooms.playerQuarters.onEnter",
    "narratorResponses": {
      "look": "What a pleasure it is to be home."
    }
  }
}
```

Note: `descriptionHandler` and exit function values are string references into
the handler registry. The loader resolves these at startup.

---

### 8.2 Schema: objects.json

```json
{
  "iron_key": {
    "name": "iron key",
    "aliases": ["key", "hare key"],
    "adjectives": ["iron", "corroded", "small", "old"],
    "description": "An iron key. The bow is cast in the form of a running hare.",
    "location": null,
    "fixed": false,
    "portable": true,
    "properties": {
      "organic": true
    },
    "handlers": {
      "examine": {
        "action": "handlers.objects.ironKey.examine"
      },
      "take": {
        "action": "handlers.objects.ironKey.takeAction"
      }
    },
    "narratorResponses": {
      "take": "Interesting that you found that."
    }
  },
  "writing_desk": {
    "name": "writing desk",
    "aliases": ["desk"],
    "adjectives": ["writing", "large", "wooden"],
    "description": "A large wooden writing desk.",
    "location": "player_quarters",
    "fixed": false,
    "portable": false,
    "handlers": {}
  },
  "wall_sconce": {
    "name": "wall sconce",
    "aliases": ["sconce", "torch"],
    "adjectives": ["wall", "iron"],
    "description": "An iron sconce fixed to the wall.",
    "location": "player_quarters",
    "fixed": true,
    "handlers": {}
  }
}
```

**Condition table syntax** — for simple logic that doesn't require a named handler:

```json
"handlers": {
  "take": {
    "verify": {
      "type": "propertyCheck",
      "object": "self",
      "property": "fixed",
      "value": true,
      "illogical": "That's part of the room."
    },
    "check": {
      "type": "propertyCheck",
      "object": "self",
      "property": "portable",
      "value": false,
      "block": "That's not something you can pick up."
    },
    "action": "handlers.defaults.take"
  }
}
```

Supported condition types:
- `propertyCheck` — checks `object.property === value`
- `flagCheck` — checks `State.get(flag) === value`
- `inventoryCheck` — checks whether an object is in player inventory
- `locationCheck` — checks an object's current location

---

### 8.3 Schema: events.json

```json
{
  "intro": "string: displayed once at game start",
  "winCondition": "handlers.events.checkWin",
  "loseCondition": null,
  "ambient": [
    {
      "id": "ambient_key_glint",
      "condition": {
        "type": "flagCheck",
        "flag": "rubble_searched",
        "value": false
      },
      "roomCondition": "entrance_passage",
      "text": "Something catches the light at the base of the rubble heap.",
      "once": true
    }
  ],
  "hints": {
    "player_quarters": [
      "Your quarters contain more than you might think.",
      "Some things here could be useful elsewhere."
    ]
  }
}
```

---

### 8.4 Schema: handlers.json

The handler registry manifest. Lists all named handlers and the source file that
registers them. The loader uses this to wire string references to functions.

```json
{
  "handlers.rooms.playerQuarters.description": {
    "registeredBy": "engine/lua/world/room_handlers.lua"
  },
  "handlers.objects.ironKey.examine": {
    "registeredBy": "engine/lua/world/object_handlers.lua"
  },
  "handlers.defaults.take": {
    "registeredBy": "engine/lua/world/defaults.lua"
  }
}
```

---

### 8.5 The Loader

The loader is the only place where the two runtimes differ substantively. Both
implement the same contract:

```
1. Read and parse rooms.json, objects.json, events.json, handlers.json
2. Instantiate world model (populate rooms table, objects table)
3. For each string reference in the data:
   a. Look up in handler registry
   b. Replace string with function reference
4. Wire AI narrator responses into narrator layer
5. Apply any active period overlays (see Section 15.4)
6. Return initialised world ready for parser
```

The loader runs once at startup. After loading, the world model is fully
populated and the engine operates normally.

---

### 8.6 Handler Registry

Named handlers are registered in engine code, not in JSON. JSON files reference
them by dotted string key. Note the correct phase placement: `fixed` at verify,
`portable` at check, `World.moveObject()` in action.

```lua
-- engine/lua/world/defaults.lua
HandlerRegistry.register("handlers.defaults.take", {
    verify = function(obj, intent)
        if not obj   then return { illogical = "You don't see that here." } end
        if obj.fixed then return { illogical = "That's part of the room." } end
        if obj.location == "inventory" then
            return { illogicalAlready = "You're already carrying that." }
        end
        return { logical = true }
    end,
    check = function(obj, intent)
        if obj.portable == false then
            return "That's not something you can pick up."
        end
    end,
    action = function(obj, intent)
        World.moveObject(obj, "inventory")
        return "Taken."
    end,
})
```

---

## 9. The AI Narrator Response Layer

The AI narrator is the game's voice throughout. Its lines are authored
specifically — not generated. The engine must support narrator overrides at
three levels:

**Room level** — a response to a verb in a specific room:
```json
"narratorResponses": {
  "look": "What a pleasure it is to be home.",
  "go_north": "Of course. The observation deck is always available to you."
}
```

**Object level** — a response to a verb on a specific object:
```json
"narratorResponses": {
  "take": "How interesting that you want that.",
  "examine": null
}
```

**Global fallbacks** — used when no room or object override exists:
```lua
Narrator.fallbacks = {
    cantDo         = "I'm afraid that's not something you can do here.",
    notFound       = "I don't see that here.",
    nothingHappens = "Nothing seems to happen.",
    taken          = "Taken.",
    dropped        = "Dropped.",
}
```

**Override resolution order:**
1. Object-level `narratorResponses[verb]` — if present and non-null, use it
2. Room-level `narratorResponses[verb]` — if present and non-null, use it
3. Handler's own output (passed through `Narrator.wrap()` unmodified)
4. Global fallback

`null` at object or room level means "use handler output unmodified." An empty
string `""` means "suppress output entirely" (silent action).

---

## 10. The Terminal / UI Shell

The terminal layer owns the visual presentation. It is completely decoupled from
game logic. It never calls parser functions directly except through the one
submit path.

**Responsibilities:**
- Maintains a `lines` array of `{ text, colour }` entries
- Caps buffer at 200 lines; supports scrollback
- On Enter: passes raw input to `Parser.process()`, prints result
- Arrow keys: cycle command history (last 50 commands)
- Cursor blink: handled in the update loop with `dt`

**Colour scheme:**

| Key | Colour | Use |
|---|---|---|
| `input` | `#99DDFF` | Player input echo |
| `response` | `#FFFFFF` | Standard response |
| `roomTitle` | `#E6D99A` | Room name on entry |
| `narrator` | `#CCCCCC` | AI narrator lines |
| `error` | `#FF6666` | Failure / can't do |
| `system` | `#888888` | Meta messages |

**Submit path:**
```
Terminal.submit(rawInput)
    → print("> " + rawInput, colours.input)
    → output = Parser.process(rawInput)
    → print(output, colours.response)
```

Output is always a return value from the parser, never printed inside the game
logic stack.

---

## 11. The LÖVE2D Presentation Layer

LÖVE2D's role is minimal: font rendering, input capture, window management. The
engine is event-driven, not tick-driven. `love.update(dt)` is used only for
cursor blink.

```lua
-- main.lua
function love.load()
    Terminal.init()
    Game.init()   -- loads JSON, initialises world, runs intro
end

function love.keypressed(key)
    Terminal.keypressed(key)
end

function love.textinput(t)
    Terminal.textinput(t)
end

function love.draw()
    Terminal.draw()
end

function love.update(dt)
    Terminal.updateCursor(dt)
end
```

**Target version: LÖVE2D 11.4**

Save/load uses `love.filesystem`, which handles platform-appropriate paths
automatically across Mac, Windows, and Linux.

---

## 12. The TypeScript / Browser Layer

The TypeScript runtime is deployed as a static bundle (single HTML + JS file)
embedded in a WordPress page via an HTML block. No backend required. No
WordPress plugins required.

**Build tool:** Vite
**Output:** Single `index.html` + `game.js` bundle
**Deployment:** Upload to self-hosted VPS; embed in WordPress page with HTML block

**Browser terminal UI** — a styled `<div>` with overflow scroll:

```html
<div id="terminal">
    <div id="output"></div>
    <div id="input-line">
        <span id="prompt">&gt;&nbsp;</span>
        <input id="input" type="text" autocomplete="off" spellcheck="false" />
    </div>
</div>
```

The terminal div uses a monospace font, dark background, and the same colour
scheme as the Lua version.

**Functional parity target:** The TypeScript engine must produce identical output
to the Lua engine for any given sequence of inputs. The parser test suite is
the verification mechanism.

---

## 13. State Manager

`engine/lua/world/state.lua` / `engine/typescript/src/world/state.ts`

```lua
State = {
    flags     = {},     -- story-level key/value state
    period    = nil,    -- current active period key
    undoStack = {},     -- reserved; not implemented in Milestone 1
}

function State.set(key, value)  State.flags[key] = value end
function State.get(key)         return State.flags[key]  end
function State.is(key)          return State.flags[key] == true end

-- Save/load via love.filesystem (Lua) or localStorage (TypeScript)
function State.save(slot)  ... end
function State.load(slot)  ... end
```

**Period state:** When the player enters a time period, `State.period` is set to
the period key. The world model uses this to determine which room graph and
object set is active.

---

## 14. Default Verb Handlers

`engine/lua/world/defaults.lua`

Default handlers are reached only when no object-specific or room-level handler
intercepts first. They implement sensible behaviour for the standard verb set.

Note the phase placement throughout: `fixed` at verify, `portable` at check,
`World.moveObject()` in action (never `obj.location =` directly).

```lua
Defaults["take"] = {
    verify = function(obj, intent)
        if not obj   then return { illogical = "You don't see that here." } end
        if obj.fixed then return { illogical = "That's part of the room." } end
        if obj.location == "inventory" then
            return { illogicalAlready = "You're already carrying that." }
        end
        return { logical = true }
    end,
    check = function(obj, intent)
        if obj.portable == false then
            return "That's not something you can pick up."
        end
    end,
    action = function(obj, intent)
        World.moveObject(obj, "inventory")
        return "Taken."
    end,
}

Defaults["drop"] = {
    verify = function(obj, intent)
        if not obj then return { illogical = "You don't see that here." } end
        if obj.location ~= "inventory" then
            return { illogical = "You're not carrying that." }
        end
        return { logical = true }
    end,
    action = function(obj, intent)
        World.moveObject(obj, World.currentRoomKey())
        return "Dropped."
    end,
}

Defaults["examine"] = {
    action = function(obj, intent)
        if type(obj.description) == "function" then
            return obj.description(obj, World.currentContext())
        end
        return obj.description or "You see nothing special about it."
    end,
}

Defaults["go"] = {
    action = function(obj, intent)
        local dir  = intent.dobjWords[1]
        local room = World.currentRoom()
        local exit = room.exits[dir]
        if exit == nil then
            return "You can't go that way."
        end
        if type(exit) == "function" then
            exit = exit()
        end
        if exit == nil then
            return World.getBlockingMessage(dir) or "You can't go that way."
        end
        World.moveTo(exit)
        return World.describeCurrentRoom()
    end,
}

Defaults["look"] = {
    action = function(obj, intent)
        return World.describeCurrentRoom()
    end,
}

Defaults["inventory"] = {
    action = function(obj, intent)
        return World.describeInventory()
    end,
}
```

---

## 15. Special Mechanics

These are fully designed. Do not implement before Milestone 3. Do not make
decisions that would make them harder to add later.

### 15.1 Time Machine

The time machine is a special object in the player's quarters. It is always in
scope there. Entering it triggers a period transition.

**On transition:**
1. Run carry check on player's current inventory
2. Any non-organic items: leave behind in player's quarters (silent, no message)
   - First time only: AI narrator delivers authored line explaining the limitation
   - Subsequent times: no message
3. Set `State.period` to target period key
4. Load period's room graph and object set
5. Place player in period's entry room
6. Describe room

**Organic property:** Objects have an `organic` boolean property in their data.
The carry check reads this. All objects in the game that originated in the
player's house must have this property set.

**The carry rule is never stated by the engine.** The player discovers it through
the first transition where they lose something.

---

### 15.2 Cross-Period Inventory

Items can be carried between periods. The world model's location model (Section
6.4) supports this.

**Rules:**
- Items carried in remain in inventory across the transition
- Items placed or dropped in a period are stored at `{ period: "key", room: "key" }`
- Items in a period-room location are in scope when the player is in that period-room
- Items placed in a period on a previous visit are present on revisit (they persist)
- Taking an item from a period's room into inventory persists across the transition
  back to the player's quarters

---

### 15.3 Telescope

The telescope is a special examine target in the player's quarters, always in
scope there.

`EXAMINE TELESCOPE` or `LOOK THROUGH TELESCOPE` always returns the same authored
description: the far-future post-singularity world the player came from. This
description is authored once and never changes regardless of what the player has
done.

The telescope does not confirm puzzle solutions. It does not vary. Its invariance
is the game's argument. The AI narrator never comments on what it shows.

The telescope's description handler is registered in the handler registry and
sourced from the game data, not the engine. It is authored content, not engine
logic.

---

### 15.4 Revisitable Periods

Some periods have two versions: a base state and one or more overlay states
applied when specific flags are set.

**Data schema:**

```json
{
  "period_1963": {
    "baseRooms": "rooms_1963_base.json",
    "overlays": [
      {
        "condition": { "type": "flagCheck", "flag": "period_1987_solved", "value": true },
        "overlayRooms": "rooms_1963_overlay_a.json"
      }
    ]
  }
}
```

An overlay is a partial room/object definition that is merged over the base state
at load time when the condition is met.

---

## 16. Known Extension Points

| Feature | Approach | Status |
|---|---|---|
| Three-object verbs | `auxWords`/`auxRef` reserved in `CommandIntent` | Reserved |
| Implied action chaining | Dispatcher chains intents (unlock before open) | Designed |
| Undo stack | State snapshots before each action phase | Reserved |
| Multiple commands per line | Tokeniser splits on `then` or `;` | Reserved |
| AGAIN / G | Store last resolved intent; re-dispatch | Reserved |
| Sense passing (light/dark) | Add context to scope query; descriptions take `lit` arg | Partially implemented in seed game |
| Split iobj handler dispatch | Consult iobjRef's handler in runCycle for two-object verbs | Deferred; see §5.5 |

---

## 17. TADS 3 Design Influences

The following architectural patterns are derived from TADS 3 adv3Lite, reviewed
against the official documentation. See `docs/tads3-adv3lite-reference.md` for
full notes.

| Pattern | Origin | Notes |
|---|---|---|
| Three-phase execution cycle (verify/check/action) | adv3Lite action model | Single most important pattern. Must not be collapsed. |
| verify() for disambiguation scoring | adv3Lite resolver | Not just a gate — a ranking mechanism called before objects are resolved. |
| verify() runs twice per command | adv3Lite | Once in resolver (ranking candidates), once in dispatcher (final gate). |
| verify() must not modify state or read other-object refs | adv3Lite | Called during resolver pass when other object is unresolved. |
| Full verify result hierarchy with numeric ranks | adv3Lite | logical(100) > dangerous(90) > illogicalAlready/Now(40) > illogical/nonObvious(30). |
| check() for player-invisible conditions | adv3Lite | Separated so parser never uses hidden information for disambiguation. |
| check() may set tracking flags | adv3Lite | Not a pure read-only phase — can record that player attempted something. |
| fixed vs portable — distinct properties, distinct phases | adv3Lite (isFixed) | fixed → verify illogical; portable = false → check block. |
| iobj resolved before dobj by default | adv3Lite TIAction | Counterintuitive but matches natural language. Configurable per verb. |
| Dobj handler is sole dispatcher authority for two-object verbs | Simplification from adv3Lite | adv3Lite dispatches both dobjFor and iobjFor; we dispatch only dobj. |
| Scope computed dynamically | adv3Lite world model | Not cached. Closed containers excluded; open ones recursively included. |
| Auto-disambiguation before asking player | adv3Lite noun phrase resolution | Prefer the logical winner. Surface clarification only when genuinely tied. |
| Parenthetical disambiguation announcement | adv3Lite parser | When auto-resolving from N>1 candidates, print "(the iron key)" before output. |

---

*End of architecture reference v2.*
*This document supersedes `docs/architecture.md` for implementation purposes.*
*`docs/architecture.md` is preserved as a record of the original design and the*
*change log that produced this version.*
