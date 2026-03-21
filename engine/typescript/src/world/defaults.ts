// world/defaults.ts
// See engine/lua/world/defaults.lua for documentation.

import type { Handler } from '../types.ts'
import { World } from './world.ts'

export const Defaults: Record<string, Handler> = {

    examine: {
        verify(obj, _intent) {
            if (!obj) return { illogical: "You don't see that here." }
            return { logical: true }
        },
        action(obj, _intent) {
            if (!obj) return "You don't see that here."
            if (typeof obj.description === 'function') {
                return obj.description(obj, World.currentContext())
            }
            return obj.description ?? 'You see nothing special about it.'
        },
    },

    look: {
        action() {
            return World.describeCurrentRoom()
        },
    },

    inventory: {
        action() {
            return World.describeInventory()
        },
    },

    take: {
        verify(obj, _intent) {
            if (!obj) return { illogical: "You don't see that here." }
            if (obj.fixed) return { illogical: "That's fixed in place." }
            if (obj.location === 'inventory') return { illogicalAlready: "You're already carrying that." }
            return { logical: true }
        },
        check(obj, _intent) {
            if (obj && obj.portable === false) return "You can't pick that up."
            return null
        },
        action(obj, _intent) {
            World.moveObject(obj!, 'inventory')
            return 'Taken.'
        },
    },

    drop: {
        verify(obj, _intent) {
            if (!obj) return { illogical: "You aren't carrying that." }
            if (obj.location !== 'inventory') return { illogical: "You aren't carrying that." }
            return { logical: true }
        },
        action(obj, _intent) {
            World.moveObject(obj!, World.currentRoomKey())
            return 'Dropped.'
        },
    },

    unlock: {
        verify(obj, _intent) {
            if (!obj) return { illogical: "You don't see that here." }
            if (obj.locked === undefined) return { illogical: "That doesn't have a lock." }
            if (!obj.locked) return { illogicalAlready: "It's not locked." }
            return { logical: true }
        },
        check(obj, intent) {
            if (!intent.iobjRef) return "You'll need a key for that."
            if (obj && World.getObject(obj.lockKey!) !== intent.iobjRef) return "That key doesn't fit."
            return null
        },
        action(obj, _intent) {
            obj!.locked = false
            return 'Unlocked.'
        },
    },

    lock: {
        verify(obj, _intent) {
            if (!obj) return { illogical: "You don't see that here." }
            if (obj.locked === undefined) return { illogical: "That doesn't have a lock." }
            if (obj.locked) return { illogicalAlready: "It's already locked." }
            return { logical: true }
        },
        check(obj, intent) {
            if (!intent.iobjRef) return "You'll need a key for that."
            if (obj && World.getObject(obj.lockKey!) !== intent.iobjRef) return "That key doesn't fit."
            return null
        },
        action(obj, _intent) {
            obj!.locked = true
            return 'Locked.'
        },
    },

    put: {
        verify(obj, _intent) {
            if (!obj) return { illogical: "You don't see that here." }
            if (obj.location !== 'inventory') return { illogical: "You aren't holding that." }
            return { logical: true }
        },
        action(obj, intent) {
            if (!intent.iobjRef) return `Put the ${obj!.name} where?`
            const prep = intent.prep ?? 'in'
            World.moveObject(obj!, World.currentRoomKey())
            return `You put the ${obj!.name} ${prep} the ${intent.iobjRef.name}.`
        },
    },

}

// go / directions
// Registered under "go" and all eight direction verbs so bare "north"
// works identically to "go north".
const goHandler: import('../types.ts').Handler = {
    action(_obj, intent) {
        const direction = intent.dobjWords[0] ??
                          (intent.verb !== 'go' ? intent.verb : undefined)
        if (!direction) return 'Go where?'
        const room = World.currentRoom()
        const exit = room.exits[direction]
        if (!exit) return "You can't go that way."
        const destKey = typeof exit === 'function' ? exit() : exit
        if (!destKey) return "You can't go that way."
        World.moveTo(destKey)
        return World.describeCurrentRoom()
    },
}

for (const verb of ['go', 'north', 'south', 'east', 'west', 'up', 'down', 'in', 'out']) {
    Defaults[verb] = goHandler
}

// wait — a turn passes with no other effect.
Defaults['wait'] = {
    action() { return 'Time passes.' },
}

// help — lists available commands.
Defaults['help'] = {
    action() {
        return 'Commands: look, examine [thing], take [thing], drop [thing],\n' +
               'inventory, go [direction], north, south, east, west,\n' +
               'put [thing] in/on [thing], unlock/lock [thing] with [key],\n' +
               'wait, quit.'
    },
}

// quit — no meaningful action in the browser; returns a farewell message.
Defaults['quit'] = {
    action() { return 'Goodbye.' },
}
