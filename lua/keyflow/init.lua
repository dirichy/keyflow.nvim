local M = {}

local map = require("keyflow.map")
local mode = require("keyflow.mode")

M.map = map.map
M.mode = mode
M.active = mode.active

return M
