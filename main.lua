-- main.lua
-- LÖVE2D entry point.
-- In Milestone 1a: runs the parser test suite on startup for debugging.
-- Terminal UI and full game wiring added in Milestone 2.

package.path = "./?.lua;" .. package.path

local runTests = require("test.parser_test")

function love.load()
    runTests()
end
