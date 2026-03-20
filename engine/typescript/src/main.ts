import './style.css'

// ---------------------------------------------------------------------------
// Colour palette
// Every piece of output uses one of these six colours. They match the scheme
// defined in docs/architecture.md §10.
// ---------------------------------------------------------------------------
const colours = {
  input:     '#99DDFF',  // player's own typed commands (blue)
  response:  '#FFFFFF',  // standard game responses (white)
  roomTitle: '#E6D99A',  // room names on entry (warm yellow)
  narrator:  '#CCCCCC',  // AI narrator lines (light grey)
  error:     '#FF6666',  // failure / can't do messages (red)
  system:    '#888888',  // meta messages, not in-world (dark grey)
}

// ---------------------------------------------------------------------------
// DOM elements
// The 'as HTMLDivElement' and 'as HTMLInputElement' parts are TypeScript
// telling the compiler what type these elements are. getElementById returns
// a generic Element type; we narrow it so TypeScript knows what properties
// are available (e.g. .scrollTop on a div, .value on an input).
// ---------------------------------------------------------------------------
const output = document.getElementById('output') as HTMLDivElement
const input  = document.getElementById('input')  as HTMLInputElement

// ---------------------------------------------------------------------------
// Command history
// history[] stores previously submitted commands, most recent first.
// historyIndex tracks where we are when the player presses arrow keys.
// -1 means "not currently browsing history".
// ---------------------------------------------------------------------------
const history: string[] = []
let historyIndex = -1

// ---------------------------------------------------------------------------
// print(text, colour)
// The only function that touches the DOM output area. Creates a <p> element,
// sets its colour, appends it to #output, and scrolls to the bottom.
// All game output must flow through this — nothing else should write to
// the output div directly.
// ---------------------------------------------------------------------------
function print(text: string, colour: string): void {
  const p = document.createElement('p')
  p.textContent = text
  p.style.color = colour
  output.appendChild(p)
  output.scrollTop = output.scrollHeight
}

// ---------------------------------------------------------------------------
// submit(raw)
// Called when the player hits Enter. Trims whitespace, echoes the input
// back in the input colour, then passes it to the game engine.
// Currently just prints "No game loaded." — this is where Parser.process()
// will be called once the engine exists.
// ---------------------------------------------------------------------------
function submit(raw: string): void {
  const text = raw.trim()
  if (!text) return

  history.unshift(text)   // add to front of history array
  historyIndex = -1        // reset history browsing position

  print('> ' + text, colours.input)
  print('No game loaded.', colours.system)
}

// ---------------------------------------------------------------------------
// Keyboard handler
// Enter    — submit the current input
// ArrowUp  — go back through command history
// ArrowDown — go forward through command history (or clear if at newest)
// ---------------------------------------------------------------------------
input.addEventListener('keydown', (e: KeyboardEvent) => {
  if (e.key === 'Enter') {
    submit(input.value)
    input.value = ''
  } else if (e.key === 'ArrowUp') {
    e.preventDefault()   // prevent cursor jumping to start of input
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

// ---------------------------------------------------------------------------
// Keep the input focused
// Clicking anywhere on the page refocuses the input so the player can
// always just start typing.
// ---------------------------------------------------------------------------
document.addEventListener('click', () => input.focus())
input.focus()

// ---------------------------------------------------------------------------
// Mobile keyboard handling
// On mobile, when the on-screen keyboard appears it shrinks the visible
// area (the "visual viewport"). Without this, the terminal overflows and
// the top of the screen gets pushed out of view.
// We listen to the visualViewport API and resize the terminal to match
// the actual available height.
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
// Initial output
// Printed once when the page loads.
// ---------------------------------------------------------------------------
print('Diversion', colours.roomTitle)
print('No game loaded.', colours.system)
