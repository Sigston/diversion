// parser/resolver.ts
// See engine/lua/parser/resolver.lua for documentation.

import type { CommandIntent, GameObject } from '../types.ts'
import { Verbs } from '../lexicon/verbs.ts'
import { World } from '../world/world.ts'

export const FAIL_NOT_FOUND = 'FAIL_NOT_FOUND' as const
export const FAIL_AMBIGUOUS = 'FAIL_AMBIGUOUS' as const

function matchObject(wordList: string[], candidates: GameObject[]): GameObject[] {
    if (wordList.length === 0) return []

    const noun       = wordList[wordList.length - 1]
    const adjectives = wordList.slice(0, -1)

    return candidates.filter(obj => {
        // Check noun against name and aliases
        const nounMatch = obj.name.includes(noun) ||
                          obj.aliases.some(a => a.includes(noun))
        if (!nounMatch) return false

        // Check all adjectives
        if (adjectives.length > 0) {
            return adjectives.every(adj => obj.adjectives.includes(adj))
        }
        return true
    })
}

function resolveNounPhrase(wordList: string[] | null): GameObject | null | typeof FAIL_NOT_FOUND {
    if (!wordList || wordList.length === 0) return null

    const candidates = World.inScope()
    const matches    = matchObject(wordList, candidates)

    if (matches.length === 0) return FAIL_NOT_FOUND

    // Milestone 1a: first match. Milestone 1b: verify() scoring.
    return matches[0]
}

export function resolve(intent: CommandIntent): CommandIntent | typeof FAIL_NOT_FOUND {
    const verbEntry = Verbs[intent.verb as keyof typeof Verbs]

    if (!verbEntry) return intent
    if (!verbEntry.resolveObj) return intent

    const resolveFirst = verbEntry.resolveFirst ?? 'iobj'

    if (resolveFirst === 'iobj') {
        const iobjRef = resolveNounPhrase(intent.iobjWords)
        if (iobjRef === FAIL_NOT_FOUND) return FAIL_NOT_FOUND
        const dobjRef = resolveNounPhrase(intent.dobjWords)
        if (dobjRef === FAIL_NOT_FOUND) return FAIL_NOT_FOUND
        intent.iobjRef = iobjRef
        intent.dobjRef = dobjRef
    } else {
        const dobjRef = resolveNounPhrase(intent.dobjWords)
        if (dobjRef === FAIL_NOT_FOUND) return FAIL_NOT_FOUND
        const iobjRef = resolveNounPhrase(intent.iobjWords)
        if (iobjRef === FAIL_NOT_FOUND) return FAIL_NOT_FOUND
        intent.dobjRef = dobjRef
        intent.iobjRef = iobjRef
    }

    return intent
}
