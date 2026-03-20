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
}
