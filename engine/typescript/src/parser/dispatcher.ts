// parser/dispatcher.ts
// See engine/lua/parser/dispatcher.lua for documentation.

import type { CommandIntent, Handler, GameObject } from '../types.ts'
import { World }    from '../world/world.ts'
import { Defaults } from '../world/defaults.ts'
import { Verbs }    from '../lexicon/verbs.ts'

function runCycle(handler: Handler, obj: GameObject | null, intent: CommandIntent): string {
    if (handler.verify) {
        const result = handler.verify(obj, intent)
        if (result) {
            if ('illogical'      in result) return result.illogical
            if ('illogicalAlready' in result) return result.illogicalAlready
            if ('illogicalNow'   in result) return result.illogicalNow
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

    // Scenery interception: non-examine/read verbs bounce off scenery objects.
    if (obj && obj.scenery && verb !== 'examine' && verb !== 'read') {
        return obj.notImportantMsg ?? "That's not something you need to worry about."
    }

    // 1. Object-specific handler
    if (obj && obj.handlers[verb]) {
        return runCycle(obj.handlers[verb], obj, intent)
    }

    // 1b. scopeDispatch: verb has no resolved dobjRef but wants an ambient
    // receiver. Scan scope for the first object that has a handler for this verb.
    if (!obj && Verbs[verb]?.scopeDispatch) {
        for (const candidate of World.inScope()) {
            if (candidate.handlers[verb]) {
                return runCycle(candidate.handlers[verb], candidate, intent)
            }
        }
        // Nothing found; fall through to room/default.
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
