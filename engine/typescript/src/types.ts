// types.ts
// Shared interfaces used across all engine modules.
// Define once here; import everywhere else.

export interface WorldContext {
    firstVisit?: boolean
    excluded?:   Record<string, boolean>
    exclude?:    (key: string) => void
}

export interface GameObject {
    name:        string
    aliases:     string[]
    adjectives:  string[]
    description: string | ((self: GameObject, ctx: WorldContext) => string)
    location:    string | null
    fixed?:      boolean
    portable:    boolean
    isLockable?: boolean
    locked?:     boolean
    lockKey?:    string
    isOpen?:     boolean
    contType?:   'in' | 'on'
    remapIn?:    string
    remapOn?:    string
    _key?:       string
    scenery?:         boolean
    notImportantMsg?: string
    otherSide?:       string
    listed?:     boolean
    mentioned?:  boolean
    moved?:      boolean
    specialDesc?:              string | ((self: GameObject) => string)
    initSpecialDesc?:          string | ((self: GameObject) => string)
    specialDescBeforeContents?: boolean
    specialDescOrder?:         number
    stateDesc?:                string | ((self: GameObject) => string)
    handlers:    Record<string, Handler>
}

export interface Connector {
    dest:          string
    traversalMsg?: string
    blockedMsg?:   string
    door?:         string
    canPass?:      () => boolean
}

export interface Room {
    name:             string
    description:      (self: Room, ctx: WorldContext) => string
    exits:            Record<string, Connector>
    objects:          string[]
    handlers:         Record<string, Handler>
    visited:          boolean
    isLit?:           boolean
    darkName?:        string
    darkDesc?:        string | ((self: Room) => string)
    suppressListing?: boolean
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
