// parser/tagger.ts
// See engine/lua/parser/tagger.lua for documentation.

import type { CommandIntent } from '../types.ts'
import { synonymMap, Verbs } from '../lexicon/verbs.ts'
import { Prepositions }      from '../lexicon/prepositions.ts'
import { Stopwords }         from '../lexicon/stopwords.ts'

function stripStopwords(words: string[]): string[] {
    return words.filter(w => !Stopwords.has(w))
}

export function tag(tokens: string[]): CommandIntent | null {
    if (tokens.length === 0) return null

    // TODO (Milestone 1b): check two-token combinations first for multi-word synonyms.
    const verb = synonymMap.get(tokens[0])
    if (!verb) return null

    const rest = tokens.slice(1)

    // Find the first preposition in the remaining tokens.
    let prepIndex = -1
    let prep: string | null = null
    for (let i = 0; i < rest.length; i++) {
        if (Prepositions.has(rest[i])) {
            prepIndex = i
            prep = rest[i]
            break
        }
    }

    let dobjSpan: string[]
    let iobjSpan: string[] | null

    if (prepIndex >= 0) {
        dobjSpan = rest.slice(0, prepIndex)
        iobjSpan = rest.slice(prepIndex + 1)
    } else {
        dobjSpan = rest
        iobjSpan = null
    }

    // rawDobj verbs (e.g. type) preserve the typed phrase verbatim — no stripping.
    const verbEntry = Verbs[verb]
    const dobjWords = verbEntry?.rawDobj ? dobjSpan : stripStopwords(dobjSpan)

    return {
        verb,
        dobjWords,
        dobjRef:   null,
        prep:      prep,
        iobjWords: iobjSpan !== null ? stripStopwords(iobjSpan) : null,
        iobjRef:   null,
        auxWords:  null,
        auxRef:    null,
    }
}
