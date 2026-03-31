// world/defaults.ts
// See engine/lua/world/defaults.lua for documentation.

import type { Handler } from '../types.ts'
import { World } from './world.ts'
import { Settings } from './settings.ts'

export const Defaults: Record<string, Handler> = {

    examine: {
        verify(obj, _intent) {
            if (!obj) return { illogical: "You don't see that here." }
            return { logical: true }
        },
        action(obj, _intent) {
            if (!obj) return "You don't see that here."
            let desc: string
            if (typeof obj.description === 'function') {
                desc = obj.description(obj, World.currentContext())
            } else {
                desc = obj.description ?? 'You see nothing special about it.'
            }
            // Append stateDesc if present (Examine only — not shown during LOOK).
            if (obj.stateDesc) {
                const state = typeof obj.stateDesc === 'function'
                    ? obj.stateDesc(obj)
                    : obj.stateDesc
                if (state) desc = desc + ' ' + state
            }
            // Sub-container summary for composite objects (remapIn / remapOn).
            if (obj.remapIn) {
                const sub = World.getObject(obj.remapIn)
                if (sub) {
                    if (!sub.isOpen) {
                        desc += '\n' + `The ${sub.name} is closed.`
                    } else {
                        const contents = World.contentsOf(sub._key!)
                        if (contents.length > 0) {
                            desc += '\n' + `The ${sub.name} is open. It contains: ${contents.map(c => c.name).join(', ')}.`
                        } else {
                            desc += '\n' + `The ${sub.name} is open and empty.`
                        }
                    }
                }
            }
            if (obj.remapOn) {
                const sub = World.getObject(obj.remapOn)
                if (sub) {
                    const contents = World.contentsOf(sub._key!)
                    if (contents.length > 0) {
                        desc += '\n' + `On the ${sub.name}: ${contents.map(c => c.name).join(', ')}.`
                    } else {
                        desc += '\n' + `The ${sub.name} is empty.`
                    }
                }
            }
            // Container state and contents for objects that are themselves containers (Examine only).
            if (obj.contType) {
                if (obj.contType === 'in') {
                    if (!obj.isOpen) {
                        desc += ' It is closed.'
                    } else {
                        desc += ' It is open.'
                        const contents = World.contentsOf(obj._key!)
                        if (contents.length > 0) {
                            desc += '\n' + 'It contains: ' + contents.map(c => c.name).join(', ') + '.'
                        } else {
                            desc += '\n' + 'It is empty.'
                        }
                    }
                } else if (obj.contType === 'on') {
                    const contents = World.contentsOf(obj._key!)
                    if (contents.length > 0) {
                        desc += '\n' + 'On it: ' + contents.map(c => c.name).join(', ') + '.'
                    } else {
                        desc += '\n' + 'It is empty.'
                    }
                }
            }
            return desc
        },
    },

    read: {
        verify(obj, _intent) {
            if (!obj) return { illogical: "You don't see that here." }
            if (!obj.readDesc) return { illogical: "There's nothing to read on that." }
            return { logical: true }
        },
        action(obj, _intent) {
            if (typeof obj.readDesc === 'function') return obj.readDesc(obj, World.currentContext())
            return obj.readDesc as string
        },
    },

    // Fallback when no terminal is in scope. Real work happens in the terminal
    // object's own handler (reached via scopeDispatch in the dispatcher).
    type: {
        action() {
            return "There's nothing here to type on."
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
            if (!obj.isLockable) return { illogical: "That doesn't have a lock." }
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
            if (obj!.otherSide) {
                const other = World.getObject(obj!.otherSide)
                if (other) other.locked = false
            }
            return 'Unlocked.'
        },
    },

    lock: {
        verify(obj, _intent) {
            if (!obj) return { illogical: "You don't see that here." }
            if (!obj.isLockable) return { illogical: "That doesn't have a lock." }
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
            if (obj!.otherSide) {
                const other = World.getObject(obj!.otherSide)
                if (other) other.locked = true
            }
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
            const container = World.resolveContainer(intent.iobjRef, prep)
            if (!container.contType || container.contType !== prep) {
                return `You can't put things ${prep} the ${container.name}.`
            }
            if (container.contType === 'in' && !container.isOpen) {
                return `The ${container.name} isn't open.`
            }
            World.moveObject(obj!, container._key!)
            return `You put the ${obj!.name} ${prep} the ${container.name}.`
        },
    },

    open: {
        verify(obj, _intent) {
            if (!obj) return { illogical: "You don't see that here." }
            // Remap to in-container sub-object if present (e.g. "open desk" → desk_drawer).
            const target = (obj.remapIn ? World.getObject(obj.remapIn) : null) ?? obj
            if (target.isOpen === undefined) return { illogical: "That doesn't open." }
            if (target.isOpen) return { illogicalAlready: "It's already open." }
            if (target.locked) return { illogicalNow: "It's locked." }
            return { logical: true }
        },
        action(obj, _intent) {
            const target = (obj!.remapIn ? World.getObject(obj!.remapIn) : null) ?? obj!
            target.isOpen = true
            return 'Opened.'
        },
    },

    close: {
        verify(obj, _intent) {
            if (!obj) return { illogical: "You don't see that here." }
            // Remap to in-container sub-object if present (e.g. "close desk" → desk_drawer).
            const target = (obj.remapIn ? World.getObject(obj.remapIn) : null) ?? obj
            if (target.isOpen === undefined) return { illogical: "That doesn't close." }
            if (!target.isOpen) return { illogicalAlready: "It's already closed." }
            return { logical: true }
        },
        action(obj, _intent) {
            const target = (obj!.remapIn ? World.getObject(obj!.remapIn) : null) ?? obj!
            target.isOpen = false
            return 'Closed.'
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
        const conn = World.getConnector(room, direction)
        if (!conn) return "You can't go that way."
        if (conn.canPass && !conn.canPass()) return conn.blockedMsg ?? "You can't go that way."
        const parts: string[] = []
        // Auto-open door if present and currently closed.
        if (conn.door) {
            const door = World.getObject(conn.door)
            if (door && door.isOpen === false) {
                door.isOpen = true
                if (door.otherSide) {
                    const other = World.getObject(door.otherSide)
                    if (other) other.isOpen = true
                }
                parts.push('You open the ' + door.name + '.')
            }
        }
        if (conn.traversalMsg) parts.push(conn.traversalMsg)
        World.moveTo(conn.dest)
        parts.push(World.describeCurrentRoom())
        // Auto-close door behind the player (if setting is enabled).
        if (conn.door && Settings.get('doorsCloseOnExit')) {
            const door = World.getObject(conn.door)
            if (door) {
                door.isOpen = false
                if (door.otherSide) {
                    const other = World.getObject(door.otherSide)
                    if (other) other.isOpen = false
                }
                parts.push('The ' + door.name + ' closes behind you.')
            }
        }
        return parts.join('\n\n')
    },
}

for (const verb of ['go', 'north', 'south', 'east', 'west', 'up', 'down', 'in', 'out']) {
    Defaults[verb] = goHandler
}

// wait — a turn passes with no other effect.
Defaults['wait'] = {
    action() { return 'Time passes.' },
}

// help — returns authored help text from events.json.
// "help" alone returns the default help block.
// "help <topic>" returns the topic text, or a "no help available" message.
Defaults['help'] = {
    action(_obj, intent) {
        const topic = (intent.dobjWords ?? []).join(' ')
        return World.getHelp(topic)
    },
}

// quit — no meaningful action in the browser; returns a farewell message.
Defaults['quit'] = {
    action() { return 'Goodbye.' },
}
