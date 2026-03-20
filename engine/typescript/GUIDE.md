# TypeScript Engine — Developer Guide

Plain-English reference for the TypeScript/browser version of the engine.
For overall project architecture see `docs/architecture.md`.

---

## What this is

The web-facing version of the Diversion IF engine. It runs in the browser
and is embedded in a WordPress page on the live site. The same game logic
that runs here also runs in the Lua/LÖVE2D version — they share the same
JSON game data files.

---

## Directory structure

```
engine/typescript/
├── index.html          The page. Just the terminal HTML structure.
├── vite.config.ts      Vite build config. Sets the base path to /game/.
├── tsconfig.json       TypeScript compiler config.
├── package.json        Project metadata and npm script shortcuts.
├── node_modules/       Installed dependencies (never edit, never commit).
└── src/
    ├── main.ts         Terminal behaviour: print, submit, history,
    │                   keyboard handling, mobile viewport fix.
    ├── style.css       Terminal appearance: layout, colours, fonts.
    ├── types.ts        Shared TypeScript interfaces (CommandIntent, etc.)
    ├── lexicon/
    │   ├── verbs.ts        Verb table + synonymMap
    │   ├── prepositions.ts Set of known prepositions
    │   └── stopwords.ts    Set of stopwords stripped before matching
    ├── parser/
    │   ├── tokeniser.ts    Stage 1: raw string -> token list
    │   ├── tagger.ts       Stage 2: tokens -> partial CommandIntent
    │   ├── resolver.ts     Stage 3: fills dobjRef and iobjRef
    │   ├── dispatcher.ts   Stage 4: runs verify/check/action cycle
    │   └── index.ts        Entry point: process(rawInput)
    ├── world/
    │   ├── world.ts        World model: rooms, objects, scope, inventory
    │   └── defaults.ts     Default verb handlers
    └── test/
        └── parserTest.ts   12-test suite, runs on page load
```

---

## What each config file does

**`package.json`** — defines the project name and the three npm scripts:
- `npm run dev` — starts a local development server with live reload
- `npm run build` — compiles TypeScript and bundles everything into `dist/`
- `npm run preview` — serves the built `dist/` locally to check before deploying

**`tsconfig.json`** — tells the TypeScript compiler how strict to be and
what JavaScript features to target. `strict: true` catches common mistakes.
`noEmit: true` means TypeScript only type-checks; Vite handles the actual
compilation.

**`vite.config.ts`** — minimal config. The only setting is `base: '/game/'`
which tells Vite the app lives at `/game/` on the server, so asset paths
are generated correctly.

---

## Running locally

From `engine/typescript/`:

```bash
npm run dev
```

Opens at `http://localhost:5173`. Changes to `.ts` or `.css` files reload
the browser automatically — no need to rebuild.

---

## Building and deploying

**Build** (from `engine/typescript/`):
```bash
npm run build
```

Produces `engine/typescript/dist/` containing:
- `index.html` — the page
- `assets/index-[hash].js` — compiled and bundled TypeScript
- `assets/index-[hash].css` — the stylesheet

The hash in the filename changes every build so browsers always load
the fresh version.

**Deploy** (from the project root):
```bash
rsync -av engine/typescript/dist/ root@192.248.144.39:/var/www/html/game/
```

Copies only changed files. The game is then live at `http://a-james.com/game/`.

**Build + deploy in one step** (from the project root):
```bash
cd engine/typescript && npm run build && cd ../.. && rsync -av engine/typescript/dist/ root@192.248.144.39:/var/www/html/game/
```

---

## Current state — Milestone 1a complete

Full parser pipeline running in the browser. The game is live at
`http://a-james.com/game/`.

**Colour scheme:**

| Name      | Hex       | Used for                     |
|-----------|-----------|------------------------------|
| input     | `#99DDFF` | Player's typed commands      |
| response  | `#FFFFFF` | Standard game responses      |
| roomTitle | `#E6D99A` | Room names on entry          |
| narrator  | `#CCCCCC` | AI narrator lines            |
| error     | `#FF6666` | Failure / can't do messages  |
| system    | `#888888` | Meta messages (not in-world) |

---

## Node.js setup note

Node is managed via nvm (Node Version Manager), not the system package.
If `node` or `npm` aren't found after opening a new terminal:

```bash
source ~/.bashrc
nvm use 22
```

To make v22 the permanent default: `nvm alias default 22`
