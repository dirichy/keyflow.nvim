local util = require("keyflow.util")
local action = require("keyflow.action")
local hint = require("keyflow.hint")
local function noop() end
---@alias Keyflow.Mode.foreignPolicy "pass"|"exit"|"exit_and_pass"|"consume"
---@alias Keyflow.Rhs {action:string|function,desc:string?}
---@class Keyflow.Mode
---@field name string name of the custom mode
---@field vimmode string[] coresponding vim mode of the custom mode, usually "n"
---@field trigger string? keymap used to enter the mode, if nil, keymap won't be set user should enter the mode manually.
---@field lazy boolean if true, it will enter the mode by `trigger..lhs`, where lhs is the key of one of map in `maps`. if false, it will enter the mode by `trigger` alone.
---@field maps table<string,Keyflow.Rhs> keymap of the mode. for now, only support single key.
---@field hint boolean|string[]|{lines:string[],marks:table}|fun(self:Keyflow.Mode):string[],table whether to show hint.
---@field foreign_policy Keyflow.Mode.foreignPolicy how to deal with keys not in `maps`.
---@field on_enter fun(self:Keyflow.Mode)
---@field on_exit fun(self:Keyflow.Mode)
---@field on_key fun(self:Keyflow.Mode,key:string):string?
---@field enter fun(self:Keyflow.Mode)
---@field exit fun(self:Keyflow.Mode?)
local Mode = { on_enter = noop, on_exit = noop, on_key = noop, foreign_policy = "exit_and_pass", lazy = true }
Mode.__index = Mode
local function normalize_vimmode(m)
	if not m then
		return { "n" }
	end
	if type(m) == "string" then
		return { m }
	end
	return m
end

local function normalize_rhs(rhs)
	if type(rhs) == "table" then
		return rhs
	end
	return { action = rhs, desc = type(rhs) == "string" and rhs or "lua function" }
end

local Mode_index = 0

--- To create a mode
---@param spec table
---@return Keyflow.Mode
function Mode.new(spec)
	if not spec.trigger then
		error("No enter key")
	end
	Mode_index = Mode_index + 1
	---@type Keyflow.Mode
	local result = vim.deepcopy(spec)
	result.name = spec.name or ("KeyFlow Mode" .. tostring(Mode_index))
	result.vimmode = normalize_vimmode(spec.vimmode)
	if result.hint == nil then
		result.hint = true
	end
	result.foreign_policy = spec.foreign_policy
	result.maps = result.maps or {}
	for lhs, rhs in pairs(result.maps) do
		result.maps[lhs] = normalize_rhs(rhs)
	end
	setmetatable(result, Mode)
	if result.lazy then
		for lhs, rhs in pairs(result.maps) do
			vim.keymap.set(result.vimmode, result.trigger .. lhs, function()
				result:enter()
				return result:feed(lhs)
			end, {
				desc = rhs.desc or result.name,
				noremap = true,
				-- silent = result.silent ~= false,
				-- buffer = result.buffer,
			})
		end
	else
		vim.keymap.set(result.vimmode, result.trigger, function()
			result:enter()
		end, {
			desc = result.name,
			noremap = true,
			-- silent = result.silent ~= false,
			-- buffer = result.buffer,
		})
	end
	return result
end

local ESC = "<Esc>"
---@type Keyflow.Mode?
local active_mode = nil

function Mode.exit()
	local current = active_mode
	if current == nil then
		return
	end
	active_mode = nil
	hint.close()
	current:on_exit()
end

function Mode:enter()
	if active_mode ~= nil then
		Mode.exit()
	end
	active_mode = self
	if self.hint then
		hint.show(self)
	end
	self:on_enter()
end

local function listener(key, typed)
	local current = active_mode
	if current == nil then
		return nil
	end

	if typed == nil or typed == "" then
		return nil
	end

	local input = vim.fn.keytrans(typed)
	return current:feed(input)
end

local ns = vim.api.nvim_create_namespace("keyflow.nvim")
vim.on_key(listener, ns)

--- feed a key to the mode processer
---@param key string
---@nodiscard
---@return string?
function Mode:feed(key)
	local temp = self:on_key(key)
	if temp and temp ~= "" then
		action.run(temp)
		return ""
	end
	if temp == "" then
		return ""
	end

	if not util.mode_matches(self.vimmode) then
		self:exit()
		return nil
	end

	local rhs = self.maps[key]

	if rhs then
		--TODO: need to read action.lua

		-- if self.vimmode == "n" then
		-- action.normal(rhs.action)
		-- else
		action.run(rhs.action)
		-- end
		-- if rhs.exit then
		-- 	self:exit()
		-- end
		return ""
	end

	if key == ESC then
		self:exit()
		return ""
	end

	local policy = self.foreign_policy

	if policy == "pass" then
		return nil
	end

	if policy == "consume" then
		return ""
	end

	if policy == "exit" then
		self:exit()
		return ""
	end

	if policy == "exit_and_pass" then
		self:exit()
		return nil
	end
end
return Mode
