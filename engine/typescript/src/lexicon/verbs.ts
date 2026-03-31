// lexicon/verbs.ts
// Verb lexicon. See engine/lua/lexicon/verbs.lua for full documentation.

import type { VerbEntry } from '../types.ts'

const verbTable: Record<string, VerbEntry> = {
    look: {
        synonyms:   ['look', 'l'],
        resolveObj: false,
    },
    examine: {
        synonyms:     ['examine', 'x', 'inspect', 'describe', 'look at'],
        resolveObj:   true,
        resolveFirst: 'dobj',
    },
    read: {
        synonyms:     ['read'],
        resolveObj:   true,
        resolveFirst: 'dobj',
    },
    inventory: {
        synonyms:   ['inventory', 'i', 'inv'],
        resolveObj: false,
    },
    take: {
        synonyms:     ['take', 'get', 'pick up', 'grab', 'acquire'],
        resolveObj:   true,
        resolveFirst: 'dobj',
    },
    drop: {
        synonyms:     ['drop', 'put down', 'leave', 'discard'],
        resolveObj:   true,
        resolveFirst: 'dobj',
    },
    go: {
        synonyms:   ['go', 'walk', 'move', 'travel', 'head', 'enter'],
        resolveObj: false,
    },
    put: {
        synonyms:     ['put', 'place', 'insert', 'set', 'lay'],
        resolveObj:   true,
        resolveFirst: 'iobj',
    },
    unlock: {
        synonyms:     ['unlock'],
        resolveObj:   true,
        resolveFirst: 'dobj',
    },
    lock: {
        synonyms:     ['lock'],
        resolveObj:   true,
        resolveFirst: 'dobj',
    },
    open: {
        synonyms:     ['open'],
        resolveObj:   true,
        resolveFirst: 'dobj',
    },
    close: {
        synonyms:     ['close', 'shut'],
        resolveObj:   true,
        resolveFirst: 'dobj',
    },
    light: {
        synonyms:     ['light', 'ignite', 'kindle', 'burn'],
        resolveObj:   true,
        resolveFirst: 'dobj',
    },
    push: {
        synonyms:     ['push', 'shove', 'press'],
        resolveObj:   true,
        resolveFirst: 'dobj',
    },
    search: {
        synonyms:     ['search', 'rummage'],
        resolveObj:   true,
        resolveFirst: 'dobj',
    },
    // Directions. Each is its own canonical verb so bare "north" works the
    // same as "go north". The go handler is registered under all of these.
    north: { synonyms: ['north', 'n'], resolveObj: false },
    south: { synonyms: ['south', 's'], resolveObj: false },
    east:  { synonyms: ['east',  'e'], resolveObj: false },
    west:  { synonyms: ['west',  'w'], resolveObj: false },
    up:    { synonyms: ['up',    'u'], resolveObj: false },
    down:  { synonyms: ['down',  'd'], resolveObj: false },
    in:    { synonyms: ['in'        ], resolveObj: false },
    out:   { synonyms: ['out'       ], resolveObj: false },

    type: {
        synonyms:      ['type', 'enter', 'input'],
        resolveObj:    false,
        rawDobj:       true,   // preserve typed phrase verbatim; no stopword stripping
        scopeDispatch: true,   // dispatcher scans scope for a handler-bearing object
    },

    wait: {
        synonyms:   ['wait', 'z'],
        resolveObj: false,
    },
    help: {
        synonyms:   ['help', '?'],
        resolveObj: false,
    },
    quit: {
        synonyms:   ['quit', 'q'],
        resolveObj: false,
    },
}

// Reverse lookup: word -> canonical verb name.
// e.g. synonymMap.get("get") === "take"
export const synonymMap = new Map<string, string>()
for (const [canonical, entry] of Object.entries(verbTable)) {
    for (const word of entry.synonyms) {
        synonymMap.set(word, canonical)
    }
}

export const Verbs = verbTable
