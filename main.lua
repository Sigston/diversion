-- main.lua
-- LÖVE2D entry point.
--
-- Wires the terminal UI to the LÖVE2D event loop.
-- The game initialises inside Terminal.init() until the JSON loader
-- is built in Milestone 3, at which point Terminal.init() will call
-- Game.init() instead of setting up the world stub directly.
--
-- To run headless tests (no LÖVE2D required):
--   lua test/parser_test.lua

package.path = "./?.lua;" .. package.path

local Terminal = require("engine.lua.terminal")

function love.load()
    Terminal.init()
end

function love.keypressed(key)
    Terminal.keypressed(key)
end

function love.textinput(t)
    Terminal.textinput(t)
end

function love.draw()
    Terminal.draw()
end

function love.update(dt)
    Terminal.updateCursor(dt)
end

function love.wheelmoved(x, y)
    Terminal.wheelmoved(x, y)
end
