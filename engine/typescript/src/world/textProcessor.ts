// world/textProcessor.ts
//
// Processes inline text directives in any string before display.
// TypeScript port of engine/lua/world/text_processor.lua — see there for docs.

import { State } from './state.ts'

// ---------------------------------------------------------------------------
// processFirst — resolves [FIRST:N]...[FIRST END] blocks.
// Uses indexOf for the closing tag so multiline content is handled correctly.
// ---------------------------------------------------------------------------
function processFirst(text: string): string {
    const parts: string[] = []
    const closeTag = '[FIRST END]'
    const tagRe = /\[FIRST:(\d+)\]/g
    let pos = 0
    let match: RegExpExecArray | null
    while ((match = tagRe.exec(text)) !== null) {
        parts.push(text.slice(pos, match.index))
        const id       = match[1]
        const afterOpen = match.index + match[0].length
        const closeIdx  = text.indexOf(closeTag, afterOpen)
        if (closeIdx === -1) {
            // Malformed: no closing tag — include everything from here.
            parts.push(text.slice(match.index))
            pos = text.length
            break
        }
        const content = text.slice(afterOpen, closeIdx)
        const key = `_first_${id}`
        if (!State.get(key)) {
            State.set(key, true)
            parts.push(content)
        }
        pos = closeIdx + closeTag.length
        tagRe.lastIndex = pos
    }
    parts.push(text.slice(pos))
    return parts.join('')
}

// ---------------------------------------------------------------------------
// processOneOf — resolves [ONE OF]...[OR]...[ONE OF END] blocks.
// ---------------------------------------------------------------------------
function processOneOf(text: string): string {
    const parts:    string[] = []
    const openTag  = '[ONE OF]'
    const closeTag = '[ONE OF END]'
    const orTag    = '[OR]'
    let pos = 0
    while (true) {
        const openIdx = text.indexOf(openTag, pos)
        if (openIdx === -1) {
            parts.push(text.slice(pos))
            break
        }
        parts.push(text.slice(pos, openIdx))
        const afterOpen = openIdx + openTag.length
        const closeIdx  = text.indexOf(closeTag, afterOpen)
        if (closeIdx === -1) {
            // Malformed: no closing tag — include everything from here.
            parts.push(text.slice(openIdx))
            break
        }
        const inner   = text.slice(afterOpen, closeIdx)
        const options = inner.split(orTag)
        parts.push(options[Math.floor(Math.random() * options.length)])
        pos = closeIdx + closeTag.length
    }
    return parts.join('')
}

// ---------------------------------------------------------------------------
// TextProcessor.process — apply all directives in order.
// ---------------------------------------------------------------------------
export const TextProcessor = {
    process(text: string): string {
        return processOneOf(processFirst(text))
    }
}
