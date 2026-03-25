# Diversion (working title)

A parser-driven interactive fiction engine, built twice — once in Lua/LÖVE2D
for local development, once in TypeScript for web deployment. Both runtimes
load the same JSON game data and produce identical output.

The engine is being built to run a specific game. This repository contains
the engine and stub game data used during development.

---

## Architecture

The engine is a classic four-stage parser pipeline:

```
Player input
    │
    ▼
Tokeniser      lowercase, strip punctuation, split on whitespace
    │
    ▼
Tagger         identify verb, preposition, noun phrases
    │
    ▼
Resolver       match noun phrases to in-scope objects; disambiguate
    │
    ▼
Dispatcher     run verify → check → action cycle on the matched handler
    │
    ▼
Output string
```

Game content (rooms, objects, exits) is defined in JSON. Neither runtime
hardcodes game data — all content is loaded at startup from `game/data/`.

---

## Runtimes

### Lua / LÖVE2D

Local development and testing. No build step.

**Run the game:**
```bash
love .
```

**Run tests (no LÖVE2D required):**
```bash
lua test/parser_test.lua
```

92 tests covering the full parser pipeline. All must pass before any new work.

### TypeScript / Browser

Web deployment via Vite. Requires Node.js v20+.

**Install dependencies** (first time, from `engine/typescript/`):
```bash
npm install
```

**Run locally:**
```bash
npm run dev
```

**Build:**
```bash
npm run build
```

The browser version runs the full test suite automatically on page load before
starting the game.

---

## Project structure

```
engine/
    lua/            Lua engine — parser, world model, terminal UI
    typescript/     TypeScript engine — same logic, browser target
game/
    data/           JSON game data (rooms, objects, events)
test/
    parser_test.lua Headless test suite
lib/
    json.lua        JSON parser (rxi/json, MIT licence)
```

---

## Current state

- Full parser pipeline in both runtimes
- Disambiguation with clarification prompts and auto-resolve
- Room description compositor with object listing and exit listing
- Containment model (surfaces, drawers, containers)
- Travel connectors with conditional blocking (flag-based)
- 25 default verb handlers: examine, look, inventory, take, drop, go,
  north/south/east/west/up/down/in/out, put, unlock, lock, open, close,
  wait, help, quit

---

## Licence

MIT. See individual source files.

&copy; A James Sigston
