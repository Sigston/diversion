import './style.css'
import { loadWorld }        from './world/loader.ts'
import { World }            from './world/world.ts'
import { process, reset as parserReset } from './parser/index.ts'
import { State }            from './world/state.ts'
import { Settings }         from './world/settings.ts'
import { runTests }         from './test/parserTest.ts'

// Load world from JSON before any parser or world operations.
const prologue = loadWorld()

// ---------------------------------------------------------------------------
// Colour palette — matches architecture doc §10 and Lua implementation.
// ---------------------------------------------------------------------------
const colours = {
    input:     '#99DDFF',
    response:  '#FFFFFF',
    roomTitle: '#E6D99A',
    narrator:  '#C8A870',
    error:     '#FF6666',
    system:    '#888888',
}

// ---------------------------------------------------------------------------
// DOM elements
// ---------------------------------------------------------------------------
const output = document.getElementById('output') as HTMLDivElement
const input  = document.getElementById('input')  as HTMLInputElement

// ---------------------------------------------------------------------------
// Command history
// ---------------------------------------------------------------------------
const history: string[] = []
let historyIndex = -1

// ---------------------------------------------------------------------------
// Pause state.
// When awaitingContinue is true, the next Enter keypress advances to the
// next pending segment rather than submitting a command.
// ---------------------------------------------------------------------------
let awaitingContinue  = false
let pendingSegments: string[] = []

// ---------------------------------------------------------------------------
// print(text, colour)
// The only function that writes to the output div.
// Handles multi-line strings by splitting on newlines.
// ---------------------------------------------------------------------------
// appendLine — appends a single <p> line. italic=true adds font-style:italic.
function appendLine(text: string, colour: string, italic = false): void {
    const p = document.createElement('p')
    p.style.color = colour
    if (italic) p.style.fontStyle = 'italic'
    p.textContent = text || '\u00a0'
    output.appendChild(p)
}

function print(text: string, colour: string, italic = false): void {
    if (text === '') {
        appendLine('', colour, italic)
    } else {
        for (const line of text.split('\n')) {
            appendLine(line, colour, italic)
        }
    }
    output.scrollTop = output.scrollHeight
}

// ---------------------------------------------------------------------------
// splitOnPause — splits text on [PAUSE] markers, trimming surrounding
// newlines from each segment. Empty segments are discarded.
// ---------------------------------------------------------------------------
function splitOnPause(text: string): string[] {
    return text.split('[PAUSE]')
        .map(s => s.replace(/^\n+|\n+$/g, ''))
        .filter(s => s.length > 0)
}

// ---------------------------------------------------------------------------
// advancePause — shows the next pending segment, or clears paused state.
// ---------------------------------------------------------------------------
function advancePause(): void {
    if (pendingSegments.length === 0) {
        awaitingContinue = false
        return
    }
    const seg = pendingSegments.shift()!
    print('', colours.system)
    printOutput(seg)
    if (pendingSegments.length > 0) {
        print('', colours.system)
        print('[ Press Enter to continue ]', colours.system)
    } else {
        awaitingContinue = false
    }
}

// ---------------------------------------------------------------------------
// printOutput — applies colour heuristics to parser output.
// Pre-splits on [I]/[/I] so italic spans work across \n\n paragraph breaks,
// then processes each chunk's paragraphs. Normal chunks get room-title
// detection; italic chunks render in narrator colour with italic style.
// ---------------------------------------------------------------------------
function printOutput(text: string): void {
    if (!text) return

    // Build ordered list of { text, italic } chunks by splitting on [I]/[/I].
    type Chunk = { text: string; italic: boolean }
    const chunks: Chunk[] = []
    if (!text.includes('[I]') && !text.includes('[/I]')) {
        chunks.push({ text, italic: false })
    } else {
        const firstOpen  = text.includes('[I]')  ? text.indexOf('[I]')  : Infinity
        const firstClose = text.includes('[/I]') ? text.indexOf('[/I]') : Infinity
        let italic = firstClose < firstOpen
        for (const part of text.split(/(\[I\]|\[\/I\])/)) {
            if (part === '[I]')  { italic = true;  continue }
            if (part === '[/I]') { italic = false; continue }
            if (part) chunks.push({ text: part, italic })
        }
    }

    let isFirst = true
    for (const { text: chunk, italic } of chunks) {
        const colour = italic ? colours.narrator : colours.response
        for (const block of chunk.split('\n\n')) {
            if (!block) continue
            if (!isFirst) print('', colour)
            isFirst = false
            if (!italic) {
                const nl = block.indexOf('\n')
                if (nl !== -1) {
                    const title = block.slice(0, nl)
                    const body  = block.slice(nl + 1)
                    if (title.length <= 40 && !/[.!?]/.test(title)) {
                        print(title, colours.roomTitle)
                        print(body,  colours.response)
                        continue
                    }
                }
            }
            print(block, colour, italic)
        }
    }
}

// ---------------------------------------------------------------------------
// processOutput — like printOutput but handles [PAUSE] markers.
// Use this for all output that reaches the player.
// ---------------------------------------------------------------------------
function processOutput(text: string): void {
    if (!text) return
    const segments = splitOnPause(text)
    if (segments.length === 0) return
    printOutput(segments[0])
    if (segments.length > 1) {
        pendingSegments = segments.slice(1)
        print('', colours.system)
        print('[ Press Enter to continue ]', colours.system)
        awaitingContinue = true
    }
}

// ---------------------------------------------------------------------------
// submit(raw)
// Called when the player hits Enter.
// ---------------------------------------------------------------------------
function submit(raw: string): void {
    const text = raw.trim()
    if (!text) return

    history.unshift(text)
    historyIndex = -1

    print('> ' + text, colours.input)

    const output_text = process(text)
    if (output_text !== '') {
        processOutput(output_text)
    }
}

// ---------------------------------------------------------------------------
// Keyboard handler
// ---------------------------------------------------------------------------
input.addEventListener('keydown', (e: KeyboardEvent) => {
    if (e.key === 'Enter') {
        if (awaitingContinue) {
            output.scrollTop = output.scrollHeight
            input.value  = ''
            historyIndex = -1
            advancePause()
            return
        }
        submit(input.value)
        input.value = ''
    } else if (e.key === 'ArrowUp') {
        e.preventDefault()
        if (historyIndex < history.length - 1) {
            historyIndex++
            input.value = history[historyIndex]
        }
    } else if (e.key === 'ArrowDown') {
        e.preventDefault()
        if (historyIndex > 0) {
            historyIndex--
            input.value = history[historyIndex]
        } else {
            historyIndex = -1
            input.value = ''
        }
    }
})

document.addEventListener('click', () => input.focus())
input.focus()

// ---------------------------------------------------------------------------
// Mobile keyboard handling
// ---------------------------------------------------------------------------
const terminal = document.getElementById('terminal') as HTMLDivElement

function fitToViewport(): void {
    const vv = window.visualViewport
    if (vv) {
        terminal.style.height = vv.height + 'px'
        terminal.style.top    = vv.offsetTop + 'px'
    }
}

window.visualViewport?.addEventListener('resize', fitToViewport)
window.visualViewport?.addEventListener('scroll', fitToViewport)
fitToViewport()

// ---------------------------------------------------------------------------
// Startup: run tests, reset, then show prologue and starting room.
// ---------------------------------------------------------------------------
if (Settings.get('integrityCheck') !== false) {
    runTests(print, colours)
    print('', colours.system)
}
print('--- game start ---', colours.system)
print('', colours.system)

// Reload game data so World.reset() uses the game snapshot, not the test snapshot.
// State.reset() first so loadWorld() applies clean initial flags from events.json.
State.reset()
parserReset()
loadWorld()
World.reset()

const roomDesc = World.describeCurrentRoom()
if (prologue) {
    processOutput(prologue + '\n[PAUSE]\n' + roomDesc)
} else {
    processOutput(roomDesc)
}
