// world/loader.ts
//
// Reads game/data/rooms.json and game/data/objects.json (static imports bundled
// by Vite), instantiates the world model, and calls World.load().
//
// Call loadWorld() once at startup before any parser or world operations.

import type { Room, GameObject, WorldContext } from '../types.ts'
import { World } from './world.ts'
import roomsJson  from '../../../../game/data/rooms.json'
import objectsJson from '../../../../game/data/objects.json'
import eventsJson from '../../../../game/data/events.json'

// ---------------------------------------------------------------------------
// JSON shape types — the raw data as it comes from the files.
// ---------------------------------------------------------------------------
interface RoomJson {
    name:        string
    description: string | { firstVisit: string; revisit: string }
    exits:       Record<string, string>
    objects:     string[]
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
        rooms[key] = {
            name:        data.name,
            description: makeDescription(data.description),
            exits:       data.exits   ?? {},
            objects:     data.objects ?? [],
            handlers:    {},
            visited:     false,
        }
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
        if (data.fixed   !== undefined) obj.fixed   = data.fixed
        if (data.locked  !== undefined) obj.locked  = data.locked
        if (data.lockKey !== undefined) obj.lockKey = data.lockKey
        objects[key] = obj
    }

    World.load(rooms, objects, roomsData.startRoom)
    return (eventsJson as { intro?: string }).intro ?? ''
}
