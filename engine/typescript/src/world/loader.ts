// world/loader.ts
//
// Reads JSON data files (static imports bundled by Vite), instantiates the
// world model, and calls World.load().
//
// loadWorld()     — loads game/data/diversion/ (the real game)
// loadTestWorld() — loads game/data/test/ (parser test fixtures)

import type { Room, GameObject, WorldContext, Connector, Handler } from '../types.ts'
import { World } from './world.ts'
import { State } from './state.ts'
import { Settings } from './settings.ts'

import configJson from '../../../../game/config.json'

// ---------------------------------------------------------------------------
// Game datasets — add a new entry here when adding a new game folder.
// Each entry key must match the "game" value in game/config.json.
// ---------------------------------------------------------------------------
import diversionRoomsJson    from '../../../../game/data/diversion/rooms.json'
import diversionObjectsJson  from '../../../../game/data/diversion/objects.json'
import diversionEventsJson   from '../../../../game/data/diversion/events.json'
import diversionSettingsJson from '../../../../game/data/diversion/settings.json'

import crossWordsRoomsJson    from '../../../../game/data/cross-words/rooms.json'
import crossWordsObjectsJson  from '../../../../game/data/cross-words/objects.json'
import crossWordsEventsJson   from '../../../../game/data/cross-words/events.json'
import crossWordsSettingsJson from '../../../../game/data/cross-words/settings.json'

const gameDatasets: Record<string, {
    rooms:    unknown
    objects:  unknown
    events:   unknown
    settings: unknown
}> = {
    diversion: {
        rooms:    diversionRoomsJson,
        objects:  diversionObjectsJson,
        events:   diversionEventsJson,
        settings: diversionSettingsJson,
    },
    'cross-words': {
        rooms:    crossWordsRoomsJson,
        objects:  crossWordsObjectsJson,
        events:   crossWordsEventsJson,
        settings: crossWordsSettingsJson,
    },
    // To add a new game:
    //   1. Add its imports above
    //   2. Add an entry here matching the folder name in game/data/
}

import testRoomsJson   from '../../../../game/data/test/rooms.json'
import testObjectsJson from '../../../../game/data/test/objects.json'
import testEventsJson  from '../../../../game/data/test/events.json'

// ---------------------------------------------------------------------------
// JSON shape types — the raw data as it comes from the files.
// ---------------------------------------------------------------------------
interface ConditionJson { type: string; flag?: string; object?: string; property?: string; value: unknown }
interface EffectJson    { type: string; flag?: string; object?: string; property?: string; value: unknown }
interface ExitJson {
    dest:          string
    condition?:    ConditionJson
    traversalMsg?: string
    blockedMsg?:   string
    door?:         string
}
interface TypeResponseJson {
    phrases:     string[]
    when?:       ConditionJson[]
    effects?:    EffectJson[]
    text:        string
    redescribe?: boolean
}

interface AfterTurnRuleJson {
    when?: ConditionJson[]
    text:  string
}

interface DescriptionBlockJson {
    when?:       ConditionJson[]
    firstVisit?: string
    revisit?:    string
}

interface ObjectDescBlockJson {
    when?:  ConditionJson[]
    text:   string
}

interface RoomJson {
    name:             string
    description:      string | { firstVisit: string; revisit: string } | DescriptionBlockJson[]
    exits:            Record<string, string | ExitJson>
    isLit?:           boolean | ConditionJson
    darkName?:        string
    darkDesc?:        string
    suppressListing?: boolean | ConditionJson
    afterTurn?:       AfterTurnRuleJson[]
}

interface ObjectJson {
    name:        string
    aliases:     string[]
    adjectives:  string[]
    description: string | ObjectDescBlockJson[]
    location:    string | null
    portable:    boolean
    fixed?:      boolean
    isLockable?: boolean
    locked?:     boolean
    lockKey?:    string
    isOpen?:     boolean
    openable?:   boolean
    contType?:   'in' | 'on'
    remapIn?:    string
    remapOn?:    string
    listed?:          boolean
    visibleInDark?:   boolean
    readDesc?:        string
    specialDesc?:              string | ObjectDescBlockJson[]
    initSpecialDesc?:          string
    specialDescBeforeContents?: boolean
    specialDescOrder?:         number
    stateDesc?:                string | { open: string; closed: string }
    scenery?:                  boolean
    notImportantMsg?:          string
    otherSide?:                string
    typeDefault?:              string
    typeResponses?:            TypeResponseJson[]
}

// ---------------------------------------------------------------------------
// assignFirstIds — replaces every [FIRST] tag in a string with [FIRST:N]
// using a module-level counter. Called on all text fields during loading so
// authors write plain [FIRST] and IDs are assigned automatically.
// ---------------------------------------------------------------------------
let firstIdCounter = 0
function assignFirstIds(text: string): string {
    return text.replace(/\[FIRST\]/g, () => `[FIRST:${firstIdCounter++}]`)
}

// ---------------------------------------------------------------------------
// makeConnector — normalises a raw JSON exit value to a Connector object.
// ---------------------------------------------------------------------------
function makeConnector(raw: string | ExitJson): Connector {
    if (typeof raw === 'string') return { dest: raw }
    const conn: Connector = { dest: raw.dest }
    if (raw.traversalMsg) conn.traversalMsg = assignFirstIds(raw.traversalMsg)
    if (raw.blockedMsg)   conn.blockedMsg   = assignFirstIds(raw.blockedMsg)
    if (raw.door)         conn.door         = raw.door
    if (raw.condition?.type === 'flagCheck') {
        const { flag, value } = raw.condition
        conn.canPass = () => State.get(flag as string) === value
    } else if (raw.condition?.type === 'objectState') {
        const { object: objKey, property: prop, value } = raw.condition
        conn.canPass = () => {
            const obj = World.getObject(objKey as string)
            return obj !== null && (obj as unknown as Record<string, unknown>)[prop as string] === value
        }
    }
    return conn
}

// ---------------------------------------------------------------------------
// makeDescription — converts JSON description to the Room description function.
// ---------------------------------------------------------------------------
function makeDescription(
    desc: string | { firstVisit: string; revisit: string } | DescriptionBlockJson[]
): (self: Room, ctx: WorldContext) => string {
    if (typeof desc === 'string') {
        const text = assignFirstIds(desc)
        return () => text
    }
    if (Array.isArray(desc)) {
        const blocks = desc.map(block => ({
            conditions: (block.when ?? []).map(makeCondition),
            firstVisit: assignFirstIds(block.firstVisit ?? ''),
            revisit:    assignFirstIds(block.revisit    ?? ''),
        }))
        return (self) => {
            for (const block of blocks) {
                if (block.conditions.every(c => c())) {
                    return self.visited ? block.revisit : block.firstVisit
                }
            }
            return ''
        }
    }
    const firstVisit = assignFirstIds(desc.firstVisit)
    const revisit    = assignFirstIds(desc.revisit)
    return (self) => self.visited ? revisit : firstVisit
}

// ---------------------------------------------------------------------------
// makeObjectDescription — converts an object description from JSON.
// Plain string → string (assignFirstIds applied, compatible with existing handler).
// Array of blocks → function; first block whose when[] conditions pass wins.
// Uses "text" per block (no firstVisit/revisit — objects don't track visits yet).
// ---------------------------------------------------------------------------
function makeObjectDescription(
    desc: string | ObjectDescBlockJson[]
): string | ((self: GameObject, ctx: WorldContext) => string) {
    if (typeof desc === 'string') return assignFirstIds(desc)
    const blocks = desc.map(block => ({
        conditions: (block.when ?? []).map(makeCondition),
        text:       assignFirstIds(block.text),
    }))
    return () => {
        for (const block of blocks) {
            if (block.conditions.every(c => c())) return block.text
        }
        return ''
    }
}

// ---------------------------------------------------------------------------
// makeCondition / makeEffect — compile JSON condition/effect objects to closures.
// Condition types match the connector condition schema.
// Effect types:
//   { type: "setFlag",       flag, value }
//   { type: "setObjectProp", object, property, value }
// ---------------------------------------------------------------------------
function makeCondition(cond: ConditionJson): () => boolean {
    if (cond.type === 'flagCheck') {
        const { flag, value } = cond
        return () => State.get(flag as string) === value
    }
    if (cond.type === 'objectState') {
        const { object: objKey, property: prop, value } = cond
        return () => {
            const obj = World.getObject(objKey as string)
            return obj !== null && (obj as unknown as Record<string, unknown>)[prop as string] === value
        }
    }
    return () => true  // unknown type; always pass
}

function makeEffect(eff: EffectJson): () => void {
    if (eff.type === 'setFlag') {
        const { flag, value } = eff
        return () => State.set(flag as string, value)
    }
    if (eff.type === 'setObjectProp') {
        const { object: objKey, property: prop, value } = eff
        return () => {
            const obj = World.getObject(objKey as string)
            if (obj) (obj as unknown as Record<string, unknown>)[prop as string] = value
        }
    }
    return () => {}  // unknown type; no-op
}

// ---------------------------------------------------------------------------
// Compiled terminal rule — internal shape after JSON compilation.
// ---------------------------------------------------------------------------
interface CompiledRule {
    phrases:    Set<string>
    conditions: (() => boolean)[]
    effects:    (() => void)[]
    text:       string
    redescribe: boolean
}

// ---------------------------------------------------------------------------
// terminalTypeHandler — built-in handler assigned to objects with typeResponses.
//
// Iterates the object's compiled typeResponses in order. For each rule whose
// phrases include the typed input and whose conditions all pass, applies effects
// and returns the rule's text. Falls through to typeDefault if nothing matches.
// ---------------------------------------------------------------------------
const terminalTypeHandler: Handler = {
    verify(_obj, intent) {
        if (!intent.dobjWords || intent.dobjWords.length === 0) {
            return { illogicalNow: 'Type what?' }
        }
        return { logical: true }
    },

    action(obj, intent) {
        const phrase = intent.dobjWords.join(' ')
        const rules  = (obj as unknown as { typeResponses: CompiledRule[] }).typeResponses
        const dflt   = (obj as unknown as { typeDefault?: string }).typeDefault
        for (const rule of rules) {
            if (rule.phrases.has(phrase)) {
                if (rule.conditions.every(c => c())) {
                    rule.effects.forEach(e => e())
                    if (rule.redescribe) {
                        World.currentRoom().visited = false
                        return rule.text + '\n\n' + World.describeCurrentRoom()
                    }
                    return rule.text
                }
            }
        }
        return dflt ?? "The cursor blinks. Nothing happens."
    },
}

// ---------------------------------------------------------------------------
// buildWorld — shared loader logic for any data set.
// Returns the intro string from events.json (empty string if none).
// ---------------------------------------------------------------------------
interface EventsJson {
    intro?:  string
    flags?:  Record<string, unknown>
    help?:   { default?: string; topics?: Record<string, string> }
}

function buildWorld(
    roomsJson:    { startRoom: string; rooms: Record<string, RoomJson> },
    objectsJson:  Record<string, ObjectJson>,
    eventsJson:   EventsJson,
    settingsJson: Record<string, unknown> = {}
): string {
    Settings.load(settingsJson)
    const rooms: Record<string, Room> = {}
    for (const [key, data] of Object.entries(roomsJson.rooms)) {
        const exits: Record<string, Connector> = {}
        for (const [dir, raw] of Object.entries(data.exits ?? {})) {
            exits[dir] = makeConnector(raw)
        }
        const room: Room = {
            name:        data.name,
            description: makeDescription(data.description),
            exits,
            objects:     [],
            handlers:    {},
            visited:     false,
        }
        if (data.isLit !== undefined) {
            room.isLit = typeof data.isLit === 'object'
                ? makeCondition(data.isLit) as unknown as boolean
                : data.isLit
        }
        if (data.darkName        !== undefined) room.darkName        = data.darkName
        if (data.darkDesc        !== undefined) room.darkDesc        = assignFirstIds(data.darkDesc)
        if (data.suppressListing !== undefined) {
            room.suppressListing = typeof data.suppressListing === 'object'
                ? makeCondition(data.suppressListing) as unknown as boolean
                : data.suppressListing
        }
        if (data.afterTurn) {
            room.afterTurn = data.afterTurn.map(rule => ({
                conditions: (rule.when ?? []).map(makeCondition),
                text:       assignFirstIds(rule.text),
            }))
        }
        rooms[key] = room
    }

    const objects: Record<string, GameObject> = {}
    for (const [key, data] of Object.entries(objectsJson)) {
        const obj: GameObject = {
            name:        data.name,
            aliases:     data.aliases    ?? [],
            adjectives:  data.adjectives ?? [],
            description: makeObjectDescription(data.description),
            location:    data.location,
            portable:    data.portable,
            handlers:    {},
        }
        if (data.fixed                    !== undefined) obj.fixed                    = data.fixed
        if (data.isLockable               !== undefined) obj.isLockable               = data.isLockable
        if (data.locked                   !== undefined) obj.locked                   = data.locked
        if (data.lockKey                  !== undefined) obj.lockKey                  = data.lockKey
        if (data.isOpen                   !== undefined) obj.isOpen                   = data.isOpen
        if (data.openable                 !== undefined) obj.openable                 = data.openable
        if (data.contType                 !== undefined) obj.contType                 = data.contType
        if (data.remapIn                  !== undefined) obj.remapIn                  = data.remapIn
        if (data.remapOn                  !== undefined) obj.remapOn                  = data.remapOn
        if (data.listed                   !== undefined) obj.listed                   = data.listed
        if (data.specialDesc              !== undefined) obj.specialDesc              = makeObjectDescription(data.specialDesc) as string
        if (data.initSpecialDesc          !== undefined) obj.initSpecialDesc          = assignFirstIds(data.initSpecialDesc)
        if (data.specialDescBeforeContents !== undefined) obj.specialDescBeforeContents = data.specialDescBeforeContents
        if (data.specialDescOrder         !== undefined) obj.specialDescOrder         = data.specialDescOrder
        if (data.stateDesc !== undefined) {
            if (typeof data.stateDesc === 'object') {
                const openMsg   = assignFirstIds(data.stateDesc.open)
                const closedMsg = assignFirstIds(data.stateDesc.closed)
                obj.stateDesc = (self: GameObject) => self.isOpen ? openMsg : closedMsg
            } else {
                obj.stateDesc = assignFirstIds(data.stateDesc)
            }
        }
        if (data.visibleInDark            !== undefined) obj.visibleInDark            = data.visibleInDark
        if (data.readDesc                 !== undefined) obj.readDesc                 = assignFirstIds(data.readDesc)
        if (data.scenery                  !== undefined) obj.scenery                  = data.scenery
        if (data.notImportantMsg          !== undefined) obj.notImportantMsg          = assignFirstIds(data.notImportantMsg)
        if (data.otherSide                !== undefined) obj.otherSide                = data.otherSide
        // Compile typeResponses into runtime form and assign built-in handler.
        if (data.typeResponses) {
            const compiled: CompiledRule[] = data.typeResponses.map(rule => ({
                phrases:    new Set(rule.phrases),
                conditions: (rule.when    ?? []).map(makeCondition),
                effects:    (rule.effects ?? []).map(makeEffect),
                text:       assignFirstIds(rule.text),
                redescribe: rule.redescribe ?? false,
            }));
            (obj as unknown as { typeResponses: CompiledRule[]; typeDefault?: string }).typeResponses = compiled;
            (obj as unknown as { typeDefault?: string }).typeDefault = data.typeDefault ? assignFirstIds(data.typeDefault) : data.typeDefault
            obj.handlers['type'] = terminalTypeHandler
        }
        objects[key] = obj
    }

    World.load(rooms, objects, roomsJson.startRoom)

    // Apply initial flag values from events.json.
    for (const [flag, value] of Object.entries(eventsJson.flags ?? {})) {
        State.set(flag, value)
    }

    // Load help content from events.json (process directives in help texts).
    const help = eventsJson.help ?? {}
    if (help.default) help.default = assignFirstIds(help.default)
    if (help.topics) {
        for (const [k, v] of Object.entries(help.topics)) {
            help.topics[k] = assignFirstIds(v)
        }
    }
    World.loadHelp(help)

    return assignFirstIds(eventsJson.intro ?? '')
}

// ---------------------------------------------------------------------------
// loadWorld — loads the game specified in game/config.json.
// Call once at startup; returns the intro string.
// ---------------------------------------------------------------------------
export function loadWorld(): string {
    const gameName = (configJson as { game: string }).game
    const dataset = gameDatasets[gameName]
    if (!dataset) throw new Error(`game/config.json specifies unknown game: "${gameName}". Add it to gameDatasets in loader.ts.`)
    return buildWorld(
        dataset.rooms    as { startRoom: string; rooms: Record<string, RoomJson> },
        dataset.objects  as Record<string, ObjectJson>,
        dataset.events   as EventsJson,
        dataset.settings as Record<string, unknown>
    )
}

// ---------------------------------------------------------------------------
// loadTestWorld — loads the parser test fixtures (game/data/test/).
// Called by runTests() in parserTest.ts before running the suite.
// ---------------------------------------------------------------------------
export function loadTestWorld(): string {
    return buildWorld(
        testRoomsJson   as { startRoom: string; rooms: Record<string, RoomJson> },
        testObjectsJson as Record<string, ObjectJson>,
        testEventsJson  as EventsJson
    )
}
