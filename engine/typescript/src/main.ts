import './style.css'

const colours = {
  input:     '#99DDFF',
  response:  '#FFFFFF',
  roomTitle: '#E6D99A',
  narrator:  '#CCCCCC',
  error:     '#FF6666',
  system:    '#888888',
}

const output = document.getElementById('output') as HTMLDivElement
const input  = document.getElementById('input')  as HTMLInputElement

const history: string[] = []
let historyIndex = -1

function print(text: string, colour: string): void {
  const p = document.createElement('p')
  p.textContent = text
  p.style.color = colour
  output.appendChild(p)
  output.scrollTop = output.scrollHeight
}

function submit(raw: string): void {
  const text = raw.trim()
  if (!text) return

  history.unshift(text)
  historyIndex = -1

  print('> ' + text, colours.input)
  print('No game loaded.', colours.system)
}

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

print('Diversion', colours.roomTitle)
print('No game loaded.', colours.system)
