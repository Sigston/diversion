// world/loader.ts
//
// Reads game/data/rooms.json and game/data/objects.json (static imports bundled
// by Vite), instantiates the world model, and calls World.load().
//
// Call loadWorld() once at startup before any parser or world operations.

import type { Room, GameObject, WorldContext, Connector } from '../types.ts'
import { World } from './world.ts'
import { State } from './state.ts'
import roomsJson  from '../../../../game/data/rooms.json'
import objectsJson from '../../../../game/data/objects.json'
import eventsJson from '../../../../game/data/events.json'

// ---------------------------------------------------------------------------
// JSON shape types — the raw data as it comes from the files.
// ---------------------------------------------------------------------------
interface ConditionJson { type: string; flag: string; value: unknown }
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
        conn.canPass = () => State.get(flag) === value
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
// loadWorld — public entry point.
// Returns the intro string from events.json (empty string if none).
// ---------------------------------------------------------------------------
export function loadWorld(): string {
    const roomsData   = (roomsJson  as { startRoom: string; rooms: Record<string, RoomJson> })
    const objectsData = (objectsJson as Record<string, ObjectJson>)

    const rooms: Record<string, Room> = {}
    for (const [key, data] of Object.entries(roomsData.rooms)) {
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
        if (data.isLit          !== undefined) room.isLit          = data.isLit
        if (data.darkName       !== undefined) room.darkName       = data.darkName
        if (data.darkDesc       !== undefined) room.darkDesc       = data.darkDesc
        if (data.suppressListing !== undefined) room.suppressListing = data.suppressListing
        rooms[key] = room
    }

    const objects: Record<string, GameObject> = {}
    for (const [key, data] of Object.entries(objectsData)) {
        const obj: GameObject = {
            name:        data.name,
            aliases:     data.aliases    ?? [],
            adjectives:  data.adjectives ?? [],
            description: data.description,
            location:    data.location,
            portable:    data.portable,
            handlers:    {},
        }
        if (data.fixed                   !== undefined) obj.fixed                   = data.fixed
        if (data.locked                  !== undefined) obj.locked                  = data.locked
        if (data.lockKey                 !== undefined) obj.lockKey                 = data.lockKey
        if (data.isOpen                  !== undefined) obj.isOpen                  = data.isOpen
        if (data.contType                !== undefined) obj.contType                = data.contType
        if (data.remapIn                 !== undefined) obj.remapIn                 = data.remapIn
        if (data.remapOn                 !== undefined) obj.remapOn                 = data.remapOn
        if (data.listed                  !== undefined) obj.listed                  = data.listed
        if (data.specialDesc             !== undefined) obj.specialDesc             = data.specialDesc
        if (data.initSpecialDesc         !== undefined) obj.initSpecialDesc         = data.initSpecialDesc
        if (data.specialDescBeforeContents !== undefined) obj.specialDescBeforeContents = data.specialDescBeforeContents
        if (data.specialDescOrder        !== undefined) obj.specialDescOrder        = data.specialDescOrder
        if (data.stateDesc               !== undefined) obj.stateDesc               = data.stateDesc
        objects[key] = obj
    }

    World.load(rooms, objects, roomsData.startRoom)
    return (eventsJson as { intro?: string }).intro ?? ''
}
