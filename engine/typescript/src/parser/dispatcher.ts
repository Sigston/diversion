// parser/dispatcher.ts
// See engine/lua/parser/dispatcher.lua for documentation.

import type { CommandIntent, Handler, GameObject } from '../types.ts'
import { World }    from '../world/world.ts'
import { Defaults } from '../world/defaults.ts'

function runCycle(handler: Handler, obj: GameObject | null, intent: CommandIntent): string {
    if (handler.verify) {
        const result = handler.verify(obj, intent)
        if (result && 'illogical' in result) {
            return result.illogical
        }
    }
    if (handler.check) {
        const block = handler.check(obj, intent)
        if (block) return block
    }
    if (handler.action) {
        return handler.action(obj, intent)
    }
    return 'Nothing happens.'
}

export function dispatch(intent: CommandIntent): string {
    const verb = intent.verb
    const obj  = intent.dobjRef
    const room = World.currentRoom()

    // 1. Object-specific handler
    if (obj && obj.handlers[verb]) {
        return runCycle(obj.handlers[verb], obj, intent)
    }

    // 2. Room-level handler
    if (room.handlers[verb]) {
        return runCycle(room.handlers[verb], room as unknown as GameObject, intent)
    }

    // 3. Default handler
    if (Defaults[verb]) {
        return runCycle(Defaults[verb], obj, intent)
    }

    return "You can't do that."
}
