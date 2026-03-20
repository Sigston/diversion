// parser/index.ts
// Entry point for the parser pipeline.
// See engine/lua/parser/init.lua for documentation.

import { tokenise }          from './tokeniser.ts'
import { tag }               from './tagger.ts'
import { resolve, FAIL_NOT_FOUND } from './resolver.ts'
import { dispatch }          from './dispatcher.ts'

export function process(rawInput: string): string {
    const tokens = tokenise(rawInput)
    if (tokens.length === 0) return ''

    const intent = tag(tokens)
    if (!intent) {
        return `You don't need to use the word "${tokens[0]}".`
    }

    const result = resolve(intent)
    if (result === FAIL_NOT_FOUND) {
        const noun = intent.dobjWords.at(-1) ?? 'that'
        return `You don't see any ${noun} here.`
    }

    return dispatch(result)
}
