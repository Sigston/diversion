// world/loader.ts
//
// Reads JSON data files (static imports bundled by Vite), instantiates the
// world model, and calls World.load().
//
// loadWorld()     — loads game/data/diversion/ (the real game)
// loadTestWorld() — loads game/data/test/ (parser test fixtures)

import type { Room, GameObject, WorldContext, Connector } from '../types.ts'
import { World } from './world.ts'
import { State } from './state.ts'

import diversionRoomsJson   from '../../../../game/data/diversion/rooms.json'
import diversionObjectsJson from '../../../../game/data/diversion/objects.json'
import diversionEventsJson  from '../../../../game/data/diversion/events.json'

import testRoomsJson   from '../../../../game/data/test/rooms.json'
import testObjectsJson from '../../../../game/data/test/objects.json'
import testEventsJson  from '../../../../game/data/test/events.json'

// ---------------------------------------------------------------------------
// JSON shape types — the raw data as it comes from the files.
// ---------------------------------------------------------------------------
interface ConditionJson { type: string; flag?: string; object?: string; property?: string; value: unknown }
interface ExitJson {
    dest:          string
    condition?:    ConditionJson
    traversalMsg?: string
    blockedMsg?:   string
}

interface RoomJson {
    name:             string
    description:      string | { firstVisit: string; revisit: string }
    exits:            Record<string, string | ExitJson>
    objects:          string[]
    isLit?:           boolean
    darkName?:        string
    darkDesc?:        string
    suppressListing?: boolean
}

interface ObjectJson {
    name:        string
    aliases:     string[]
    adjectives:  string[]
    description: string
    location:    string | null
    portable:    boolean
    fixed?:      boolean
    locked?:     boolean
    lockKey?:    string
    isOpen?:     boolean
    contType?:   'in' | 'on'
    remapIn?:    string
    remapOn?:    string
    listed?:     boolean
    specialDesc?:              string
    initSpecialDesc?:          string
    specialDescBeforeContents?: boolean
    specialDescOrder?:         number
    stateDesc?:                string
    scenery?:                  boolean
    notImportantMsg?:          string
    otherSide?:                string
}

// ---------------------------------------------------------------------------
// makeConnector — normalises a raw JSON exit value to a Connector object.
// ---------------------------------------------------------------------------
function makeConnector(raw: string | ExitJson): Connector {
    if (typeof raw === 'string') return { dest: raw }
    const conn: Connector = { dest: raw.dest }
    if (raw.traversalMsg) conn.traversalMsg = raw.traversalMsg
    if (raw.blockedMsg)   conn.blockedMsg   = raw.blockedMsg
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
    desc: string | { firstVisit: string; revisit: string }
): (self: Room, ctx: WorldContext) => string {
    if (typeof desc === 'string') {
        return () => desc
    }
    return (self) => self.visited ? desc.revisit : desc.firstVisit
}

// ---------------------------------------------------------------------------
// buildWorld — shared loader logic for any data set.
// Returns the intro string from events.json (empty string if none).
// ---------------------------------------------------------------------------
function buildWorld(
    roomsJson:   { startRoom: string; rooms: Record<string, RoomJson> },
    objectsJson: Record<string, ObjectJson>,
    eventsJson:  { intro?: string }
): string {
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
            objects:     data.objects ?? [],
            handlers:    {},
            visited:     false,
        }
        if (data.isLit           !== undefined) room.isLit           = data.isLit
        if (data.darkName        !== undefined) room.darkName        = data.darkName
        if (data.darkDesc        !== undefined) room.darkDesc        = data.darkDesc
        if (data.suppressListing !== undefined) room.suppressListing = data.suppressListing
        rooms[key] = room
    }

    const objects: Record<string, GameObject> = {}
    for (const [key, data] of Object.entries(objectsJson)) {
        const obj: GameObject = {
            name:        data.name,
            aliases:     data.aliases    ?? [],
            adjectives:  data.adjectives ?? [],
            description: data.description,
            location:    data.location,
            portable:    data.portable,
            handlers:    {},
        }
        if (data.fixed                    !== undefined) obj.fixed                    = data.fixed
        if (data.locked                   !== undefined) obj.locked                   = data.locked
        if (data.lockKey                  !== undefined) obj.lockKey                  = data.lockKey
        if (data.isOpen                   !== undefined) obj.isOpen                   = data.isOpen
        if (data.contType                 !== undefined) obj.contType                 = data.contType
        if (data.remapIn                  !== undefined) obj.remapIn                  = data.remapIn
        if (data.remapOn                  !== undefined) obj.remapOn                  = data.remapOn
        if (data.listed                   !== undefined) obj.listed                   = data.listed
        if (data.specialDesc              !== undefined) obj.specialDesc              = data.specialDesc
        if (data.initSpecialDesc          !== undefined) obj.initSpecialDesc          = data.initSpecialDesc
        if (data.specialDescBeforeContents !== undefined) obj.specialDescBeforeContents = data.specialDescBeforeContents
        if (data.specialDescOrder         !== undefined) obj.specialDescOrder         = data.specialDescOrder
        if (data.stateDesc                !== undefined) obj.stateDesc                = data.stateDesc
        if (data.scenery                  !== undefined) obj.scenery                  = data.scenery
        if (data.notImportantMsg          !== undefined) obj.notImportantMsg          = data.notImportantMsg
        if (data.otherSide                !== undefined) obj.otherSide                = data.otherSide
        objects[key] = obj
    }

    World.load(rooms, objects, roomsJson.startRoom)
    return eventsJson.intro ?? ''
}

// ---------------------------------------------------------------------------
// loadWorld — loads the real game data (game/data/diversion/).
// Call once at startup; returns the intro string.
// ---------------------------------------------------------------------------
export function loadWorld(): string {
    return buildWorld(
        diversionRoomsJson  as { startRoom: string; rooms: Record<string, RoomJson> },
        diversionObjectsJson as Record<string, ObjectJson>,
        diversionEventsJson  as { intro?: string }
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
        testEventsJson  as { intro?: string }
    )
}
