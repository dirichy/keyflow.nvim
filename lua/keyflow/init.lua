local M = {}

local map = require("keyflow.map")
local mode = require("keyflow.mode")

M.map = map.map
M.mode = mode.mode
M.enter = mode.enter
M.exit = mode.exit
M.active = mode.active

return M
