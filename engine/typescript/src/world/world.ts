// world/world.ts
// See engine/lua/world/world.lua for full documentation.

import type { GameObject, Room, WorldContext } from '../types.ts'

// ---------------------------------------------------------------------------
// Objects
// ---------------------------------------------------------------------------
interface ObjectStore { [key: string]: GameObject }

const initialLocations: Record<string, string> = {
    iron_key:     'player_quarters',
    copper_key:   'player_quarters',
    oil_lamp:     'player_quarters',
    writing_desk: 'player_quarters',
    chest:        'player_quarters',
}

const objects: ObjectStore = {
    iron_key: {
        name:        'iron key',
        aliases:     ['key'],
        adjectives:  ['iron', 'old', 'small'],
        description: 'A small iron key. The bow is cast in the shape of a hare.',
        location:    'player_quarters',
        portable:    true,
        handlers:    {},
    },
    copper_key: {
        name:        'copper key',
        aliases:     ['key'],
        adjectives:  ['copper', 'small'],
        description: "A small copper key. Simpler in design than you'd expect.",
        location:    'player_quarters',
        portable:    true,
        handlers:    {},
    },
    oil_lamp: {
        name:        'oil lamp',
        aliases:     ['lamp'],
        adjectives:  ['oil', 'brass', 'old'],
        description: 'A brass oil lamp. The reservoir is about half full.',
        location:    'player_quarters',
        portable:    true,
        handlers:    {},
    },
    writing_desk: {
        name:        'writing desk',
        aliases:     ['desk'],
        adjectives:  ['writing', 'large', 'wooden'],
        description: 'A large wooden desk. Its surface is bare except for a ' +
                     'faint ring left by some long-gone cup.',
        location:    'player_quarters',
        portable:    false,
        handlers:    {},
    },
    chest: {
        name:        'small chest',
        aliases:     ['chest'],
        adjectives:  ['small', 'wooden'],
        description: 'A small wooden chest secured with an iron lock.',
        location:    'player_quarters',
        portable:    false,
        locked:      true,
        lockKey:     'iron_key',
        handlers:    {},
    },
}

// ---------------------------------------------------------------------------
// Rooms
// ---------------------------------------------------------------------------
const rooms: Record<string, Room> = {
    player_quarters: {
        name: 'Your Quarters',
        description(self, _ctx) {
            if (!self.visited) {
                return 'Your quarters are exactly as you left them — which is to ' +
                       'say, arranged with the particular chaos of someone who ' +
                       'knows where everything is. The writing desk dominates one ' +
                       'wall. An oil lamp sits where you last set it down. ' +
                       'Somewhere nearby, an iron key catches the light.'
            }
            return 'Your quarters. The writing desk, the lamp, the key.'
        },
        exits:    { north: 'entrance_passage' },
        objects:  ['iron_key', 'copper_key', 'oil_lamp', 'writing_desk', 'chest'],
        handlers: {},
        visited:  false,
    },

    entrance_passage: {
        name: 'Entrance Passage',
        description(self, _ctx) {
            if (!self.visited) {
                return 'A narrow stone passage leads away from your quarters. ' +
                       'Bare walls, bare floor. The way back is to the south.'
            }
            return 'The entrance passage. Bare stone.'
        },
        exits:    { south: 'player_quarters' },
        objects:  [],
        handlers: {},
        visited:  false,
    },
}

let currentRoomKey = 'player_quarters'

// ---------------------------------------------------------------------------
// World API
// ---------------------------------------------------------------------------
export const World = {

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

    moveTo(roomKey: string): void {
        currentRoomKey = roomKey
    },

    moveObject(obj: GameObject, location: string | null): void {
        obj.location = location
    },

    getObject(key: string): GameObject | undefined {
        return objects[key]
    },

    reset(): void {
        for (const room of Object.values(rooms)) {
            room.visited = false
        }
        for (const [key, loc] of Object.entries(initialLocations)) {
            objects[key].location = loc
        }
        objects.chest.locked = true
        currentRoomKey = 'player_quarters'
    },
}
