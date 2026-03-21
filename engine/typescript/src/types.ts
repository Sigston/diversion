// types.ts
// Shared interfaces used across all engine modules.
// Define once here; import everywhere else.

export interface WorldContext {
    // Extended in later milestones: lit, period, flags, etc.
}

export interface GameObject {
    name:        string
    aliases:     string[]
    adjectives:  string[]
    description: string | ((self: GameObject, ctx: WorldContext) => string)
    location:    string | null
    fixed?:      boolean
    portable:    boolean
    locked?:     boolean
    lockKey?:    string
    handlers:    Record<string, Handler>
}

export interface Room {
    name:        string
    description: (self: Room, ctx: WorldContext) => string
    exits:       Record<string, string | (() => string | null)>
    objects:     string[]
    handlers:    Record<string, Handler>
    visited:     boolean
}

export type VerifyResult =
    | { logical: true; rank?: number }
    | { dangerous: true }
    | { illogicalAlready: string }
    | { illogicalNow: string }
    | { illogical: string }
    | { nonObvious: true }

export interface Handler {
    verify?: (obj: GameObject | null, intent: CommandIntent) => VerifyResult | null
    check?:  (obj: GameObject | null, intent: CommandIntent) => string | null
    action?: (obj: GameObject | null, intent: CommandIntent) => string
}

export interface CommandIntent {
    verb:      string
    dobjWords: string[]
    dobjRef:   GameObject | null
    prep:      string | null
    iobjWords: string[] | null
    iobjRef:   GameObject | null
    auxWords:  string[] | null   // RESERVED: three-object verbs
    auxRef:    GameObject | null // RESERVED: three-object verbs
}

export interface VerbEntry {
    synonyms:     string[]
    resolveObj:   boolean
    resolveFirst?: 'dobj' | 'iobj'
}
