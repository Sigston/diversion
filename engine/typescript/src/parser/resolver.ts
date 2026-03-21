// parser/resolver.ts
// See engine/lua/parser/resolver.lua for documentation.

import type { CommandIntent, GameObject, VerifyResult } from '../types.ts'
import { Verbs } from '../lexicon/verbs.ts'
import { World } from '../world/world.ts'
import { Defaults } from '../world/defaults.ts'

// ---------------------------------------------------------------------------
// Result types
// ---------------------------------------------------------------------------
export type ResolveOk = {
    ok:     true
    intent: CommandIntent
    auto:   { dobj?: GameObject; iobj?: GameObject }
}
export type ResolveFailNotFound = {
    ok:    false
    kind:  'NOT_FOUND'
    words: string[]
}
export type ResolveFailAmbiguous = {
    ok:         false
    kind:       'AMBIGUOUS'
    candidates: GameObject[]
    which:      'dobj' | 'iobj'
    intent:     CommandIntent
}
export type ResolveResult = ResolveOk | ResolveFailNotFound | ResolveFailAmbiguous

// ---------------------------------------------------------------------------
// verifyRank
//
// Maps a verify() result to a numeric rank for disambiguation scoring.
// Higher rank = more preferred candidate.
// ---------------------------------------------------------------------------
export function verifyRank(result: VerifyResult | null): number {
    if (!result)                        return 100
    if ('logical'          in result)   return result.rank ?? 100
    if ('dangerous'        in result)   return 90
    if ('illogicalAlready' in result)   return 40
    if ('illogicalNow'     in result)   return 40
    if ('illogical'        in result)   return 30
    if ('nonObvious'       in result)   return 30
    return 100
}

function matchObject(wordList: string[], candidates: GameObject[]): GameObject[] {
    if (wordList.length === 0) return []

    const noun       = wordList[wordList.length - 1]
    const adjectives = wordList.slice(0, -1)

    return candidates.filter(obj => {
        const nounMatch = obj.name.includes(noun) ||
                          obj.aliases.some(a => a.includes(noun))
        if (!nounMatch) return false
        if (adjectives.length > 0) {
            return adjectives.every(adj => obj.adjectives.includes(adj))
        }
        return true
    })
}

function getVerifyResult(obj: GameObject, verb: string, intent: CommandIntent): VerifyResult | null {
    const handler = obj.handlers[verb] ?? Defaults[verb]
    if (handler?.verify) return handler.verify(obj, intent)
    return null
}

type PhraseResult =
    | { ok: true;  obj: GameObject | null; autoResolved: boolean }
    | { ok: false; kind: 'NOT_FOUND'; words: string[] }
    | { ok: false; kind: 'AMBIGUOUS'; candidates: GameObject[] }

function resolveNounPhrase(
    wordList: string[] | null,
    verb: string,
    intent: CommandIntent,
): PhraseResult {
    if (!wordList || wordList.length === 0) {
        return { ok: true, obj: null, autoResolved: false }
    }

    const candidates = World.inScope()
    const matches    = matchObject(wordList, candidates)

    if (matches.length === 0) {
        return { ok: false, kind: 'NOT_FOUND', words: wordList }
    }

    if (matches.length === 1) {
        return { ok: true, obj: matches[0], autoResolved: false }
    }

    // Multiple candidates: score each with verify() and rank them.
    const scored = matches.map(obj => ({
        obj,
        rank: verifyRank(getVerifyResult(obj, verb, intent)),
    }))

    const best = Math.max(...scored.map(s => s.rank))
    const top  = scored.filter(s => s.rank === best).map(s => s.obj)

    if (top.length === 1) {
        return { ok: true, obj: top[0], autoResolved: true }
    }

    return { ok: false, kind: 'AMBIGUOUS', candidates: top }
}

// ---------------------------------------------------------------------------
// resolve(intent)
//
// Fills in dobjRef and iobjRef on the intent.
// Returns a ResolveResult discriminated union.
// ---------------------------------------------------------------------------
// Exposed for use in handleClarification: filters a candidate list using the
// same adjective+noun matching as the full resolver.
export function filterCandidates(wordList: string[], candidates: GameObject[]): GameObject[] {
    return matchObject(wordList, candidates)
}

export function resolve(intent: CommandIntent): ResolveResult {
    const verbEntry = Verbs[intent.verb as keyof typeof Verbs]

    if (!verbEntry?.resolveObj) {
        return { ok: true, intent, auto: {} }
    }

    const resolveFirst = verbEntry.resolveFirst ?? 'iobj'
    const auto: ResolveOk['auto'] = {}

    // Resolve one noun phrase, set the ref on intent, and update auto.
    // Returns a fail result if resolution failed, or undefined on success.
    function resolvePhrase(
        wordList: string[] | null,
        which: 'dobj' | 'iobj',
    ): ResolveFailNotFound | ResolveFailAmbiguous | undefined {
        const r = resolveNounPhrase(wordList, intent.verb, intent)
        if (!r.ok) {
            if (r.kind === 'NOT_FOUND') {
                return { ok: false, kind: 'NOT_FOUND', words: r.words }
            }
            return { ok: false, kind: 'AMBIGUOUS', candidates: r.candidates, which, intent }
        }
        if (which === 'dobj') intent.dobjRef = r.obj
        else                  intent.iobjRef = r.obj
        if (r.autoResolved && r.obj) auto[which] = r.obj
        return undefined
    }

    if (resolveFirst === 'iobj') {
        const e1 = resolvePhrase(intent.iobjWords, 'iobj')
        if (e1) return e1
        const e2 = resolvePhrase(intent.dobjWords, 'dobj')
        if (e2) return e2
    } else {
        const e1 = resolvePhrase(intent.dobjWords, 'dobj')
        if (e1) return e1
        const e2 = resolvePhrase(intent.iobjWords, 'iobj')
        if (e2) return e2
    }

    return { ok: true, intent, auto }
}
