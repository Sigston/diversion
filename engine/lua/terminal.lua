-- engine/lua/terminal.lua
--
-- LÖVE2D terminal UI.
--
-- Responsibilities:
--   * Maintains a scrolling line buffer (max 200 lines)
--   * Renders output + input line each frame
--   * Handles keypressed / textinput / cursor blink
--   * Calls Parser.process() and prints the result
--   * Interprets "quit" at the terminal level (requires love.event)
--
-- Called from main.lua — see Section 11 of docs/architecture_v2.md.

local Parser   = require("engine.lua.parser.init")
local World    = require("engine.lua.world.world")
local Loader   = require("engine.lua.loader")
local runTests = require("test.parser_test")

local Terminal = {}

-- ---------------------------------------------------------------------------
-- Colour palette — LÖVE2D uses 0..1 float components.
-- Keys match the TypeScript implementation and architecture doc §10.
-- ---------------------------------------------------------------------------
local C = {
    input      = { 0.600, 0.867, 1.000 },   -- #99DDFF  player input echo
    response   = { 1.000, 1.000, 1.000 },   -- #FFFFFF  standard response
    roomTitle  = { 0.902, 0.851, 0.604 },   -- #E6D99A  room name on entry
    narrator   = { 0.800, 0.800, 0.800 },   -- #CCCCCC  AI narrator lines
    error_col  = { 1.000, 0.400, 0.400 },   -- #FF6666  failure messages
    system     = { 0.533, 0.533, 0.533 },   -- #888888  meta messages
    background = { 0.102, 0.102, 0.102 },   -- #1A1A1A  window background
    separator  = { 0.200, 0.200, 0.200 },   -- #333333  input-line border
    prompt     = { 1.000, 1.000, 1.000 },   -- #FFFFFF  "> " prompt symbol
}

-- ---------------------------------------------------------------------------
-- Internal state
-- ---------------------------------------------------------------------------
local font
local lineHeight

local PADDING      = 16
local MAX_LINES    = 200
local MAX_HIST     = 50
local BLINK_RATE   = 0.5    -- seconds per half-cycle
local SCROLL_SPEED = 3      -- rendered lines per mouse-wheel notch

local lines      = {}     -- { text = string, colour = {r,g,b} }
local inputText  = ""
local history    = {}     -- most-recent first
local histIdx    = -1     -- -1 = not browsing history
local cursorOn   = true
local cursorTimer = 0.0

-- Scroll state.
-- scrollOffset: how many rendered lines from the bottom we are (0 = at bottom).
-- renderedCache: flat list of {text,colour} after word-wrap is applied to every
--   logical line. Rebuilt whenever lines change or the window width changes.
-- maxVisibleCached: updated each draw; used by keypressed for page scrolling.
local scrollOffset    = 0
local renderedCache   = {}
local renderDirty     = true
local lastAvailableW  = 0
local maxVisibleCached = 0

-- ---------------------------------------------------------------------------
-- pushLine / printLines — the only functions that write to the buffer
-- ---------------------------------------------------------------------------
local function pushLine(text, colour)
    lines[#lines + 1] = { text = text, colour = colour }
    if #lines > MAX_LINES then
        table.remove(lines, 1)
    end
    renderDirty = true
end

local function printLines(text, colour)
    if text == "" then
        pushLine("", colour)
        return
    end
    for segment in (text .. "\n"):gmatch("([^\n]*)\n") do
        pushLine(segment, colour)
    end
end

-- ---------------------------------------------------------------------------
-- printOutput — applies colour heuristics to parser output.
--
-- Room descriptions are returned as "Title\nBody" from the go and look
-- handlers. We detect this by checking for a short first line with no
-- sentence-ending punctuation. In Milestone 3, handlers will return
-- typed response objects instead, making this heuristic unnecessary.
-- ---------------------------------------------------------------------------
local function printOutput(text)
    if text == "" then return end
    local title, body = text:match("^([^\n]+)\n(.+)$")
    if title and body and #title <= 40 and not title:match("[%.!%?]") then
        pushLine(title, C.roomTitle)
        printLines(body, C.response)
    else
        printLines(text, C.response)
    end
end

-- ---------------------------------------------------------------------------
-- rebuildCache — flattens all logical lines into rendered sub-lines after
-- word-wrap. Called lazily from draw() when renderDirty is true or the
-- window width has changed.
-- ---------------------------------------------------------------------------
local function rebuildCache(availableW)
    renderedCache = {}
    for i = 1, #lines do
        local ln = lines[i]
        local subLines
        if ln.text == "" then
            subLines = { "" }
        else
            local _, wrapped = font:getWrap(ln.text, availableW)
            subLines = wrapped
        end
        for _, sub in ipairs(subLines) do
            renderedCache[#renderedCache + 1] = { text = sub, colour = ln.colour }
        end
    end
    renderDirty    = false
    lastAvailableW = availableW
end

-- ---------------------------------------------------------------------------
-- Terminal.print — public; allows main.lua to write system messages
-- ---------------------------------------------------------------------------
function Terminal.print(text, colourKey)
    printLines(text, C[colourKey] or C.response)
end

-- ---------------------------------------------------------------------------
-- Terminal.submit — called when the player hits Enter
-- ---------------------------------------------------------------------------
function Terminal.submit(raw)
    local text = raw:match("^%s*(.-)%s*$")
    if text == "" then return end

    -- record in history
    table.insert(history, 1, text)
    if #history > MAX_HIST then table.remove(history) end
    histIdx = -1

    -- always snap to bottom when a command is submitted (mirrors TypeScript behaviour)
    scrollOffset = 0

    -- echo the command
    pushLine("> " .. text, C.input)

    -- quit is handled at the terminal level — it requires love.event.quit()
    -- which is a LÖVE2D primitive outside the parser's responsibility.
    if text == "quit" or text == "q" then
        pushLine("Goodbye.", C.system)
        -- push the quit event so the message is drawn before we exit
        love.event.push("quit")
        return
    end

    -- test is a dev-only meta-command; not a game verb.
    -- Runs the parser test suite and renders results with colour coding.
    if text == "test" then
        pushLine("", C.system)
        local function testPrint(msg)
            if msg == "" or msg == "\n" then
                pushLine("", C.system)
            elseif msg:sub(1, 1) == "\n" then
                -- header lines come with a leading newline
                pushLine(msg:sub(2), C.narrator)
            elseif msg:match("^PASS:") then
                pushLine(msg, C.system)
            elseif msg:match("^FAIL:") or msg:match("^  ") then
                pushLine(msg, C.error_col)
            elseif msg:match("%d+ passed") then
                local hasFailed = not msg:match(", 0 failed")
                pushLine(msg, hasFailed and C.error_col or C.system)
            else
                pushLine(msg, C.response)
            end
        end
        local _, failed = runTests(testPrint)
        -- restore clean world state so the game is still playable after tests
        World.reset()
        Parser.reset()
        local intro = World.describeCurrentRoom()
        pushLine("", C.system)
        printOutput(intro)
        return
    end

    local result = Parser.process(text)
    if result ~= "" then
        printOutput(result)
    end
end

-- ---------------------------------------------------------------------------
-- Terminal.init — call once from love.load()
-- ---------------------------------------------------------------------------
function Terminal.init()
    -- LÖVE2D's default font is used here. To switch to a bundled monospace
    -- TTF, replace with: love.graphics.newFont("assets/fonts/YourFont.ttf", 16)
    font       = love.graphics.newFont(16)
    lineHeight = math.floor(font:getHeight() * 1.6)

    love.window.setTitle("Diversion")

    Loader.load()
    World.reset()

    -- Show the starting room on startup (same as typing "look")
    local intro = World.describeCurrentRoom()
    printOutput(intro)
end

-- ---------------------------------------------------------------------------
-- Terminal.keypressed — special keys (Enter, Backspace, arrows, Ctrl+V)
-- ---------------------------------------------------------------------------
function Terminal.keypressed(key)
    if key == "return" or key == "kpenter" then
        Terminal.submit(inputText)
        inputText   = ""
        histIdx     = -1
        cursorOn    = true
        cursorTimer = 0.0

    elseif key == "backspace" then
        inputText = inputText:sub(1, -2)
        cursorOn  = true
        cursorTimer = 0.0

    elseif key == "up" then
        if histIdx < #history - 1 then
            histIdx   = histIdx + 1
            inputText = history[histIdx + 1]
        end

    elseif key == "down" then
        if histIdx > 0 then
            histIdx   = histIdx - 1
            inputText = history[histIdx + 1]
        elseif histIdx == 0 then
            histIdx   = -1
            inputText = ""
        end

    elseif key == "pageup" then
        local pageSize = math.max(1, maxVisibleCached - 1)
        scrollOffset = scrollOffset + pageSize

    elseif key == "pagedown" then
        local pageSize = math.max(1, maxVisibleCached - 1)
        scrollOffset = math.max(0, scrollOffset - pageSize)

    elseif key == "home" then
        -- jump to the very top of the buffer
        scrollOffset = math.max(0, #renderedCache - maxVisibleCached)

    elseif key == "end" then
        scrollOffset = 0

    elseif key == "v" and
           (love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")) then
        local clip = love.system.getClipboardText()
        if clip then
            inputText = inputText .. clip:gsub("[\r\n]+", " ")
        end
        cursorOn  = true
        cursorTimer = 0.0
    end
end

-- ---------------------------------------------------------------------------
-- Terminal.textinput — printable character input
-- ---------------------------------------------------------------------------
function Terminal.textinput(t)
    inputText   = inputText .. t
    cursorOn    = true
    cursorTimer = 0.0
end

-- ---------------------------------------------------------------------------
-- Terminal.updateCursor — cursor blink timer; call from love.update(dt)
-- ---------------------------------------------------------------------------
function Terminal.updateCursor(dt)
    cursorTimer = cursorTimer + dt
    if cursorTimer >= BLINK_RATE then
        cursorTimer = cursorTimer - BLINK_RATE
        cursorOn    = not cursorOn
    end
end

-- ---------------------------------------------------------------------------
-- Terminal.wheelmoved — mouse wheel scrolling; call from love.wheelmoved()
-- ---------------------------------------------------------------------------
function Terminal.wheelmoved(_, dy)
    -- dy > 0: wheel up → scroll toward older content (increase offset)
    -- dy < 0: wheel down → scroll toward newer content (decrease offset)
    scrollOffset = math.max(0, scrollOffset + dy * SCROLL_SPEED)
    -- upper cap is applied in draw() once we know the rendered line count
end

-- ---------------------------------------------------------------------------
-- Terminal.draw — render output buffer and input line; call from love.draw()
-- ---------------------------------------------------------------------------
function Terminal.draw()
    local W, H = love.graphics.getDimensions()

    -- Background
    love.graphics.setColor(C.background)
    love.graphics.rectangle("fill", 0, 0, W, H)

    love.graphics.setFont(font)

    local SB_W       = 4                      -- scrollbar width in pixels
    local SB_PAD     = 4                      -- gap between scrollbar and text
    local x          = PADDING
    local availableW = W - PADDING * 2 - SB_W - SB_PAD
    local glyphH     = font:getHeight()

    -- Layout
    local inputAreaH  = lineHeight + PADDING
    local outputAreaH = H - inputAreaH - PADDING * 2
    local maxVisible  = math.floor(outputAreaH / lineHeight)
    maxVisibleCached  = maxVisible

    -- Rebuild rendered-line cache when the buffer or window width changed.
    if renderDirty or availableW ~= lastAvailableW then
        rebuildCache(availableW)
    end

    local total     = #renderedCache
    local maxScroll = math.max(0, total - maxVisible)
    scrollOffset    = math.min(scrollOffset, maxScroll)   -- clamp upper bound

    -- Which slice of the cache to show.
    -- endIdx   = last visible rendered line (inclusive), 1-based.
    -- startIdx = first visible rendered line (inclusive), 1-based.
    local endIdx   = total - scrollOffset
    local startIdx = math.max(1, endIdx - maxVisible + 1)

    -- Draw output lines
    local y = PADDING
    for i = startIdx, endIdx do
        local ln = renderedCache[i]
        love.graphics.setColor(ln.colour)
        love.graphics.print(ln.text, x, y)
        y = y + lineHeight
    end

    -- Scrollbar — only drawn when there is content above the visible area.
    if maxScroll > 0 then
        local sbX  = W - PADDING - SB_W
        local sbY  = PADDING
        local sbH  = outputAreaH

        -- Track (the full scrollbar height, greyed out)
        love.graphics.setColor(0.20, 0.20, 0.20)
        love.graphics.rectangle("fill", sbX, sbY, SB_W, sbH)

        -- Thumb (proportional, showing where we are in the buffer)
        local thumbH = math.max(20, sbH * maxVisible / total)
        -- scrollOffset=0 → thumb at bottom; scrollOffset=maxScroll → thumb at top
        local thumbFraction = scrollOffset / maxScroll
        local thumbY = sbY + (1 - thumbFraction) * (sbH - thumbH)
        love.graphics.setColor(0.50, 0.50, 0.50)
        love.graphics.rectangle("fill", sbX, thumbY, SB_W, thumbH)
    end

    -- Separator line above the input area
    local sepY = H - inputAreaH - PADDING * 0.5
    love.graphics.setColor(C.separator)
    love.graphics.line(PADDING, sepY, W - PADDING, sepY)

    -- Input line: prompt, typed text, and cursor all share the same y so
    -- they sit on the same baseline. Cursor height = glyphH (not lineHeight)
    -- so it matches the actual character height exactly.
    local inputY = H - glyphH - PADDING
    love.graphics.setColor(C.prompt)
    love.graphics.print("> ", x, inputY)

    local promptW = font:getWidth("> ")
    love.graphics.setColor(C.input)
    love.graphics.print(inputText, x + promptW, inputY)

    if cursorOn then
        local cursorX = x + promptW + font:getWidth(inputText)
        love.graphics.setColor(C.input)
        love.graphics.rectangle("fill", cursorX, inputY, 2, glyphH)
    end

    -- Reset to white so nothing else is accidentally tinted
    love.graphics.setColor(1, 1, 1)
end

return Terminal
