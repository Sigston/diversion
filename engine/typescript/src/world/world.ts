// world/world.ts
//
// The world model. Owns all rooms and objects, answers scope queries,
// and handles player movement.
//
// Populated at startup by loadWorld() / World.load(). Never hardcodes game
// content — all data comes from JSON via the loader.

import type { Connector, GameObject, Room, WorldContext } from '../types.ts'

// ---------------------------------------------------------------------------
// Module-level state — populated by World.load()
// ---------------------------------------------------------------------------
let rooms:          Record<string, Room>       = {}
let objects:        Record<string, GameObject> = {}
let currentRoomKey  = ''
let startRoomKey    = ''

interface ObjectSnap { location: string | null; locked?: boolean; isOpen?: boolean; moved?: boolean }
interface RoomSnap   { visited: boolean }
const initialState: Record<string, ObjectSnap | RoomSnap> = {}

// ---------------------------------------------------------------------------
// Internal compositor helpers
// ---------------------------------------------------------------------------

function isIlluminated(room: Room): boolean {
    return room.isLit !== false
}

function unmentionAll(): void {
    for (const obj of Object.values(objects)) {
        obj.mentioned = false
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

function article(name: string): string {
    return /^[aeiou]/i.test(name) ? 'an' : 'a'
}

function buildMiscSentence(items: GameObject[]): string {
    const names = items.map(obj => {
        obj.mentioned = true
        return `${article(obj.name)} ${obj.name}`
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
        } else if (obj.listed !== false && !obj.scenery
                   && !obj.remapIn && !obj.remapOn
                   && !(obj.contType === 'in' && obj.isOpen)) {
            miscItems.push(obj)
        }
    }

    miscItems.sort((a, b) => a.name.localeCompare(b.name))

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

    // Stage 4A: Composite objects (remapIn / remapOn) get a dedicated paragraph.
    // They are excluded from the misc sentence and described here instead.
    for (const key of room.objects) {
        const obj = objects[key]
        if (!obj || ctx.excluded[key] || obj.mentioned) continue
        if (obj.location !== currentRoomKey) continue
        if (!obj.remapIn && !obj.remapOn) continue

        const lines: string[] = [`There is a ${obj.name} here.`]

        if (obj.remapOn) {
            const sub = World.getObject(obj.remapOn)
            if (sub) {
                const names = World.contentsOf(sub._key!)
                    .filter(item => !item.mentioned)
                    .map(item => { item.mentioned = true; return item.name })
                if (names.length > 0) {
                    lines.push(`On the ${sub.name}: ${names.join(', ')}.`)
                }
                sub.mentioned = true
            }
        }

        if (obj.remapIn) {
            const sub = World.getObject(obj.remapIn)
            if (sub) {
                if (sub.isOpen) {
                    const names = World.contentsOf(sub._key!)
                        .filter(item => !item.mentioned)
                        .map(item => { item.mentioned = true; return item.name })
                    if (names.length > 0) {
                        lines.push(`The ${sub.name} is open. It contains: ${names.join(', ')}.`)
                    } else {
                        lines.push(`The ${sub.name} is open and empty.`)
                    }
                }
                sub.mentioned = true
            }
        }

        obj.mentioned = true
        result.push(lines.join(' '))
    }

    // Stage 4B: Direct containers in the room (on-surfaces and open in-containers).
    for (const key of room.objects) {
        const cont = objects[key]
        if (!cont || !cont.contType || ctx.excluded[key] || cont.mentioned) continue
        if (cont.location !== currentRoomKey) continue

        if (cont.contType === 'on') {
            const names = World.contentsOf(key)
                .filter(item => !item.mentioned)
                .map(item => { item.mentioned = true; return item.name })
            if (names.length > 0) {
                result.push(`On the ${cont.name}: ${names.join(', ')}.`)
            }
            cont.mentioned = true
        } else if (cont.contType === 'in' && cont.isOpen) {
            const names = World.contentsOf(key)
                .filter(item => !item.mentioned)
                .map(item => { item.mentioned = true; return item.name })
            if (names.length > 0) {
                result.push(`The ${cont.name} is open. It contains: ${names.join(', ')}.`)
            } else {
                result.push(`The ${cont.name} is open and empty.`)
            }
            cont.mentioned = true
        }
        // Closed in-containers: skip (in misc list or invisible if listed:false).
    }

    return result.length > 0 ? result.join('\n\n') : null
}

function listExits(room: Room): string | null {
    const dirs = Object.keys(room.exits)
    if (dirs.length === 0) return null
    dirs.sort()
    return 'Exits: ' + dirs.join(', ') + '.'
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
            obj._key = key
            const snap: ObjectSnap = { location: obj.location }
            if (obj.locked  !== undefined) snap.locked  = obj.locked
            if (obj.isOpen  !== undefined) snap.isOpen  = obj.isOpen
            if (obj.moved   !== undefined) snap.moved   = obj.moved
            initialState[key] = snap
        }
        for (const key of Object.keys(rooms)) {
            initialState[key] = { visited: false }
        }

        // Build room.objects (direct children only) from object location properties.
        for (const room of Object.values(rooms)) room.objects = []
        for (const [objKey, obj] of Object.entries(objects)) {
            const loc = obj.location
            if (loc && rooms[loc]) rooms[loc].objects.push(objKey)
        }
        for (const room of Object.values(rooms)) room.objects.sort()
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

        // Recursively add contents of an object container, sorted by key.
        function addContainerContents(contKey: string): void {
            const children = Object.values(objects)
                .filter(o => o.location === contKey)
                .sort((a, b) => (a._key ?? '').localeCompare(b._key ?? ''))
            for (const obj of children) {
                scope.push(obj)
                if (obj.contType === 'on'
                        || (obj.contType === 'in' && obj.isOpen)) {
                    addContainerContents(obj._key!)
                }
            }
        }

        // Top-level room objects (room.objects is kept sorted by key).
        // In an unlit room, only objects with visibleInDark = true are in scope.
        const dark = !isIlluminated(room)
        for (const key of room.objects) {
            const obj = objects[key]
            if (obj && (!dark || obj.visibleInDark)) {
                scope.push(obj)
                if (obj.contType === 'on'
                        || (obj.contType === 'in' && obj.isOpen)) {
                    addContainerContents(obj._key!)
                }
            }
        }

        // Inventory (sorted by key for determinism).
        const inv = Object.values(objects)
            .filter(o => o.location === 'inventory')
            .sort((a, b) => (a._key ?? '').localeCompare(b._key ?? ''))
        for (const obj of inv) scope.push(obj)

        return scope
    },

    contentsOf(objKey: string): GameObject[] {
        const result = Object.values(objects).filter(o => o.location === objKey)
        result.sort((a, b) => a.name.localeCompare(b.name))
        return result
    },

    resolveContainer(obj: GameObject, prep: string): GameObject {
        if (prep === 'in' && obj.remapIn) return objects[obj.remapIn]!
        if (prep === 'on' && obj.remapOn) return objects[obj.remapOn]!
        return obj
    },

    describeCurrentRoom(): string {
        const room = rooms[currentRoomKey]

        // Step 1: Reset mentioned flags.
        unmentionAll()

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
            .sort()
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
                if (s.isOpen !== undefined) objects[key].isOpen = s.isOpen
                objects[key].moved = s.moved
            }
        }
        currentRoomKey = startRoomKey

        // Rebuild room.objects from restored object locations.
        for (const room of Object.values(rooms)) room.objects = []
        for (const [objKey, obj] of Object.entries(objects)) {
            const loc = obj.location
            if (loc && rooms[loc]) rooms[loc].objects.push(objKey)
        }
        for (const room of Object.values(rooms)) room.objects.sort()
    },

    moveTo(roomKey: string): void {
        currentRoomKey = roomKey
    },

    moveObject(obj: GameObject, location: string | null): void {
        if (location === 'inventory' && obj.location !== 'inventory') {
            obj.moved = true
        }

        // Remove from old room's direct-child list if it was directly in a room.
        const oldLoc = obj.location
        if (oldLoc && rooms[oldLoc]) {
            const oldObjs = rooms[oldLoc].objects
            const idx = oldObjs.indexOf(obj._key!)
            if (idx !== -1) oldObjs.splice(idx, 1)
        }

        obj.location = location

        // Add to new room's direct-child list if moving directly into a room.
        if (location && rooms[location]) {
            rooms[location].objects.push(obj._key!)
        }
    },

    getObject(key: string): GameObject | undefined {
        return objects[key]
    },

    getConnector(room: Room, dir: string): Connector | undefined {
        return room.exits[dir]
    },
}
