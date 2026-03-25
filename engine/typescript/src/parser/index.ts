// parser/index.ts
// Entry point for the parser pipeline.
// See engine/lua/parser/init.lua for documentation.

import { tokenise }                                         from './tokeniser.ts'
import { tag }                                              from './tagger.ts'
import { Stopwords }                                        from '../lexicon/stopwords.ts'
import { resolve, filterCandidates }                        from './resolver.ts'
import type { ResolveFailAmbiguous }                        from './resolver.ts'
import { dispatch }                                         from './dispatcher.ts'
import type { GameObject }                                  from '../types.ts'

// ---------------------------------------------------------------------------
// Disambiguation state machine
// States: 'NORMAL' | 'AWAIT_CLARIFY'
// ---------------------------------------------------------------------------
type State = 'NORMAL' | 'AWAIT_CLARIFY'

let state:   State = 'NORMAL'
let pending: ResolveFailAmbiguous | null = null

function buildClarificationQuestion(candidates: GameObject[]): string {
    if (candidates.length === 2) {
        return `Which do you mean, the ${candidates[0].name} or the ${candidates[1].name}?`
    }
    const parts = candidates.map((c, i) =>
        i < candidates.length - 1 ? `the ${c.name}` : `or the ${c.name}`
    )
    return `Which do you mean, ${parts.join(', ')}?`
}

function handleClarification(rawInput: string): string {
    if (!pending) return ''

    // Strip stopwords so "the copper key" and "copper key" both work.
    const words = tokenise(rawInput).filter(t => !Stopwords.has(t))

    // Use the same adjective+noun matching as the resolver, restricted to
    // the stored candidate list so we don't re-query scope.
    const matches = filterCandidates(words, pending.candidates)
    const matched = matches.length === 1 ? matches[0] : null

    if (!matched) {
        return `I didn't understand that. ${buildClarificationQuestion(pending.candidates)}`
    }

    const resolvedIntent = pending.intent
    if (pending.which === 'dobj') resolvedIntent.dobjRef = matched
    else                          resolvedIntent.iobjRef = matched

    state   = 'NORMAL'
    pending = null
    return dispatch(resolvedIntent)
}

// ---------------------------------------------------------------------------
// process(rawInput)
// ---------------------------------------------------------------------------
export function process(rawInput: string): string {
    if (state === 'AWAIT_CLARIFY') {
        return handleClarification(rawInput)
    }

    const tokens = tokenise(rawInput)
    if (tokens.length === 0) return ''

    const intent = tag(tokens)
    if (!intent) {
        return `You don't need to use the word "${tokens[0]}".`
    }

    const result = resolve(intent)

    if (!result.ok) {
        if (result.kind === 'NOT_FOUND') {
            const phrase = result.words.length > 0 ? result.words.join(' ') : 'that'
            return `You don't see any ${phrase} here.`
        }
        // AMBIGUOUS
        state   = 'AWAIT_CLARIFY'
        pending = result
        return buildClarificationQuestion(result.candidates)
    }

    const output = dispatch(result.intent)

    let prefix = ''
    if (result.auto.dobj) prefix += `(the ${result.auto.dobj.name}) `
    if (result.auto.iobj) prefix += `(the ${result.auto.iobj.name}) `

    return prefix + output
}

// Resets disambiguation state. Call between test runs.
export function reset(): void {
    state   = 'NORMAL'
    pending = null
}
