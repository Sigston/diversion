import './style.css'
import { loadWorld } from './world/loader.ts'
import { process }   from './parser/index.ts'
import { runTests }  from './test/parserTest.ts'

// Load world from JSON before any parser or world operations.
loadWorld()

// ---------------------------------------------------------------------------
// Colour palette — matches architecture doc §10 and Lua implementation.
// ---------------------------------------------------------------------------
const colours = {
    input:     '#99DDFF',
    response:  '#FFFFFF',
    roomTitle: '#E6D99A',
    narrator:  '#CCCCCC',
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
// print(text, colour)
// The only function that writes to the output div.
// Handles multi-line strings by splitting on newlines.
// ---------------------------------------------------------------------------
function print(text: string, colour: string): void {
    if (text === '') {
        const p = document.createElement('p')
        p.innerHTML = '&nbsp;'
        p.style.color = colour
        output.appendChild(p)
    } else {
        for (const line of text.split('\n')) {
            const p = document.createElement('p')
            p.textContent = line
            p.style.color = colour
            output.appendChild(p)
        }
    }
    output.scrollTop = output.scrollHeight
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
        print(output_text, colours.response)
    }
}

// ---------------------------------------------------------------------------
// Keyboard handler
// ---------------------------------------------------------------------------
input.addEventListener('keydown', (e: KeyboardEvent) => {
    if (e.key === 'Enter') {
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
// Startup: run tests, then show the game prompt.
// ---------------------------------------------------------------------------
print('Diversion — parser test suite', colours.roomTitle)
runTests(print, colours)
print('', colours.system)
print('Parser loaded. Type look, examine lamp, inventory, etc.', colours.system)
