// lexicon/verbs.ts
// Verb lexicon. See engine/lua/lexicon/verbs.lua for full documentation.

import type { VerbEntry } from '../types.ts'

const verbTable: Record<string, VerbEntry> = {
    look: {
        synonyms:   ['look', 'l'],
        resolveObj: false,
    },
    examine: {
        synonyms:     ['examine', 'x', 'inspect', 'describe', 'read', 'look at'],
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
