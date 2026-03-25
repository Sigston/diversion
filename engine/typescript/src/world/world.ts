// world/world.ts
//
// The world model. Owns all rooms and objects, answers scope queries,
// and handles player movement.
//
// Populated at startup by loadWorld() / World.load(). Never hardcodes game
// content — all data comes from JSON via the loader.

import type { GameObject, Room, WorldContext } from '../types.ts'

// ---------------------------------------------------------------------------
// Module-level state — populated by World.load()
// ---------------------------------------------------------------------------
let rooms:          Record<string, Room>       = {}
let objects:        Record<string, GameObject> = {}
let currentRoomKey  = ''
let startRoomKey    = ''

interface ObjectSnap { location: string | null; locked?: boolean; moved?: boolean }
interface RoomSnap   { visited: boolean }
const initialState: Record<string, ObjectSnap | RoomSnap> = {}

// ---------------------------------------------------------------------------
// Internal compositor helpers
// ---------------------------------------------------------------------------

function isIlluminated(room: Room): boolean {
    return room.isLit !== false
}

function unmentionAll(room: Room): void {
    for (const key of room.objects) {
        const obj = objects[key]
        if (obj) obj.mentioned = false
    }
}

function hasActiveSpecialDesc(obj: GameObject): boolean {
    if (obj.initSpecialDesc && !obj.moved) return true
    if (obj.specialDesc) return true
    return false
}

function showSpecialDesc(obj: GameObject): string | null {
    let text: string | ((self: GameObject) => string) | undefined
    if (obj.initSpecialDesc && !obj.moved) {
        text = obj.initSpecialDesc
    } else {
        text = obj.specialDesc
    }
    if (!text) return null
    const result = typeof text === 'function' ? text(obj) : text
    obj.mentioned = true
    return result
}

function buildMiscSentence(items: GameObject[]): string {
    const names = items.map(obj => {
        obj.mentioned = true
        return obj.name
    })
    if (names.length === 1) return `You can also see: ${names[0]}.`
    if (names.length === 2) return `You can also see: ${names[0]} and ${names[1]}.`
    const last = names.pop()!
    return `You can also see: ${names.join(', ')}, and ${last}.`
}

function listContents(room: Room, ctx: Required<Pick<WorldContext, 'excluded'>>): string | null {
    const firstSpecial:  GameObject[] = []
    const miscItems:     GameObject[] = []
    const secondSpecial: GameObject[] = []

    for (const key of room.objects) {
        const obj = objects[key]
        if (!obj || ctx.excluded[key] || obj.mentioned) continue
        if (obj.location !== currentRoomKey) continue

        if (hasActiveSpecialDesc(obj)) {
            if (obj.specialDescBeforeContents !== false) {
                firstSpecial.push(obj)
            } else {
                secondSpecial.push(obj)
            }
        } else if (obj.listed !== false) {
            miscItems.push(obj)
        }
    }

    const byOrder = (a: GameObject, b: GameObject) =>
        (a.specialDescOrder ?? 100) - (b.specialDescOrder ?? 100)
    firstSpecial.sort(byOrder)
    secondSpecial.sort(byOrder)

    const result: string[] = []

    for (const obj of firstSpecial) {
        const text = showSpecialDesc(obj)
        if (text) result.push(text)
    }

    if (miscItems.length > 0) {
        result.push(buildMiscSentence(miscItems))
    }

    for (const obj of secondSpecial) {
        const text = showSpecialDesc(obj)
        if (text) result.push(text)
    }

    return result.length > 0 ? result.join('\n\n') : null
}

function listExits(room: Room): string | null {
    const available: string[] = []
    for (const [dir, exit] of Object.entries(room.exits)) {
        const dest = typeof exit === 'function' ? exit() : exit
        if (dest) available.push(dir)
    }
    if (available.length === 0) return null
    available.sort()
    return 'Exits: ' + available.join(', ') + '.'
}

// ---------------------------------------------------------------------------
// World API
// ---------------------------------------------------------------------------
export const World = {

    load(
        roomsTable:   Record<string, Room>,
        objectsTable: Record<string, GameObject>,
        startRoom:    string
    ): void {
        rooms          = roomsTable
        objects        = objectsTable
        startRoomKey   = startRoom
        currentRoomKey = startRoom

        for (const [key, obj] of Object.entries(objects)) {
            const snap: ObjectSnap = { location: obj.location }
            if (obj.locked !== undefined) snap.locked = obj.locked
            if (obj.moved  !== undefined) snap.moved  = obj.moved
            initialState[key] = snap
        }
        for (const key of Object.keys(rooms)) {
            initialState[key] = { visited: false }
        }
    },

    currentRoom(): Room {
        return rooms[currentRoomKey]
    },

    currentRoomKey(): string {
        return currentRoomKey
    },

    currentContext(): WorldContext {
        return {}
    },

    inScope(): GameObject[] {
        const scope: GameObject[] = []
        const room = rooms[currentRoomKey]

        for (const key of room.objects) {
            const obj = objects[key]
            if (obj && obj.location === currentRoomKey) {
                scope.push(obj)
            }
        }
        for (const obj of Object.values(objects)) {
            if (obj.location === 'inventory') {
                scope.push(obj)
            }
        }
        return scope
    },

    describeCurrentRoom(): string {
        const room = rooms[currentRoomKey]

        // Step 1: Reset mentioned flags.
        unmentionAll(room)

        const parts: string[] = []

        // Step 2: Room title.
        parts.push(isIlluminated(room) ? room.name : (room.darkName ?? 'In the dark'))

        // Step 3: Dark branch.
        if (!isIlluminated(room)) {
            const raw = room.darkDesc ?? "It is pitch black; you can't see a thing."
            parts.push(typeof raw === 'function' ? raw(room) : raw)
            room.visited = true
            return parts.join('\n')
        }

        // Step 4: Build room context.
        const excluded: Record<string, boolean> = {}
        const ctx: WorldContext = {
            firstVisit: !room.visited,
            excluded,
            exclude: (key: string) => { excluded[key] = true },
        }

        // Step 5: Room description body.
        // Title and body join with a single newline; subsequent blocks use double.
        let out = parts[0] + '\n' + room.description(room, ctx)

        // Steps 6–7: Object listing and exit listing.
        if (!room.suppressListing) {
            const listing = listContents(room, { excluded })
            if (listing) out += '\n\n' + listing

            const exits = listExits(room)
            if (exits) out += '\n\n' + exits
        }

        // Step 8: Mark as visited.
        room.visited = true

        return out
    },

    describeInventory(): string {
        const carried = Object.values(objects)
            .filter(o => o.location === 'inventory')
            .map(o => o.name)
        if (carried.length === 0) return 'You are carrying nothing.'
        return 'You are carrying: ' + carried.join(', ') + '.'
    },

    reset(): void {
        for (const [key, snap] of Object.entries(initialState)) {
            if (key in rooms) {
                rooms[key].visited = false
            } else if (key in objects) {
                const s = snap as ObjectSnap
                objects[key].location = s.location
                if (s.locked !== undefined) objects[key].locked = s.locked
                objects[key].moved = s.moved
            }
        }
        currentRoomKey = startRoomKey
    },

    moveTo(roomKey: string): void {
        currentRoomKey = roomKey
    },

    moveObject(obj: GameObject, location: string | null): void {
        if (location === 'inventory' && obj.location !== 'inventory') {
            obj.moved = true
        }
        obj.location = location
    },

    getObject(key: string): GameObject | undefined {
        return objects[key]
    },
}
