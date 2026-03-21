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

// Snapshot of mutable object/room state taken at load time, used by reset().
interface ObjectSnap { location: string | null; locked?: boolean }
interface RoomSnap   { visited: boolean }
const initialState: Record<string, ObjectSnap | RoomSnap> = {}

// ---------------------------------------------------------------------------
// World.load — called once by loadWorld() after parsing JSON.
// ---------------------------------------------------------------------------
export const World = {

    load(
        roomsTable:  Record<string, Room>,
        objectsTable: Record<string, GameObject>,
        startRoom:   string
    ): void {
        rooms          = roomsTable
        objects        = objectsTable
        startRoomKey   = startRoom
        currentRoomKey = startRoom

        // Snapshot mutable state for reset()
        for (const [key, obj] of Object.entries(objects)) {
            const snap: ObjectSnap = { location: obj.location }
            if (obj.locked !== undefined) snap.locked = obj.locked
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
        const desc = room.description(room, World.currentContext())
        room.visited = true
        return room.name + '\n' + desc
    },

    describeInventory(): string {
        const carried = Object.values(objects)
            .filter(o => o.location === 'inventory')
            .map(o => o.name)
        if (carried.length === 0) return 'You are carrying nothing.'
        return 'You are carrying: ' + carried.join(', ') + '.'
    },

    // Resets all mutable world state to the values captured at load time.
    reset(): void {
        for (const [key, snap] of Object.entries(initialState)) {
            if (key in rooms) {
                rooms[key].visited = false
            } else if (key in objects) {
                const s = snap as ObjectSnap
                objects[key].location = s.location
                if (s.locked !== undefined) objects[key].locked = s.locked
            }
        }
        currentRoomKey = startRoomKey
    },

    moveTo(roomKey: string): void {
        currentRoomKey = roomKey
    },

    moveObject(obj: GameObject, location: string | null): void {
        obj.location = location
    },

    getObject(key: string): GameObject | undefined {
        return objects[key]
    },
}
