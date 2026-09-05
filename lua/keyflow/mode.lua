local util = require("keyflow.util")
local hint = require("keyflow.hint")
local function noop() end
---@alias Keyflow.Mode.foreignPolicy.enum "pass"|"exit"|"exit_and_pass"|"consume"
---@alias Keyflow.Mode.foreignPolicy Keyflow.Mode.foreignPolicy.enum|fun(self:Keyflow.Mode,key:string):Keyflow.Mode.foreignPolicy.enum
---@alias Keyflow.Rhs {action:string|function,desc:string?}
---@class Keyflow.Mode.spec
---@field name string? name of the custom mode
---@field vimmode string|string[]|nil coresponding vim mode of the custom mode, usually "n"
---@field trigger string? keymap used to enter the mode, if nil, keymap won't be set user should enter the mode manually.
---@field lazy boolean? if true, it will enter the mode by `trigger..lhs`, where lhs is the key of one of map in `maps`. if false, it will enter the mode by `trigger` alone.
---@field maps table<string,Keyflow.Rhs|string|fun(self:Keyflow.Mode,key:string,count:number):string?>? keymap of the mode. for now, only support single key.
---@field hint boolean|string[]|{lines:string[],marks:table}|fun(self:Keyflow.Mode):string[],table|nil whether to show hint.
---@field foreign_policy Keyflow.Mode.foreignPolicy? how to deal with keys not in `maps`.
---@field map_esc boolean? whether map esc as a exit key, default true.
---@field count_mode boolean|"repeat"|nil false to disable, true will pass count to maps, or get count by vim.v.count, "repeat" will repeat the action `count` times.
---@field count_max number? only used for count_mode "repeat" to avoid lag. default 99
---@field on_enter fun(self:Keyflow.Mode)|nil
---@field on_exit fun(self:Keyflow.Mode)|nil
---@field on_key fun(self:Keyflow.Mode,key:string):string?|nil
---@class Keyflow.Mode
---@field name string name of the custom mode
---@field vimmode string[] coresponding vim mode of the custom mode, usually "n"
---@field trigger string? keymap used to enter the mode, if nil, keymap won't be set user should enter the mode manually.
---@field lazy boolean if true, it will enter the mode by `trigger..lhs`, where lhs is the key of one of map in `maps`. if false, it will enter the mode by `trigger` alone.
---@field maps table<string,Keyflow.Rhs> keymap of the mode. for now, only support single key.
---@field hint boolean|string[]|{lines:string[],marks:table}|fun(self:Keyflow.Mode):string[],table whether to show hint.
---@field foreign_policy Keyflow.Mode.foreignPolicy how to deal with keys not in `maps`.
---@field map_esc boolean? whether map esc as a exit key, default true.
---@field count_mode boolean|"repeat" false to disable, true will pass count to maps, or get count by vim.v.count, "repeat" will repeat the action `count` times.
---@field count_max number only used for count_mode "repeat" to avoid lag. default 100
---@field on_enter fun(self:Keyflow.Mode)
---@field on_exit fun(self:Keyflow.Mode)
---@field on_key fun(self:Keyflow.Mode,key:string):string?
---@field enter fun(self:Keyflow.Mode)
---@field exit fun(self:Keyflow.Mode?)
---@field feed fun(self:Keyflow.Mode,key:string,count:number):string?
local Mode = {
	on_enter = noop,
	on_exit = noop,
	on_key = noop,
	foreign_policy = "exit_and_pass",
	lazy = true,
	hint = true,
	count_mode = true,
	count_max = 99,
	maps = {},
	map_esc = true,
}
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
---@param spec Keyflow.Mode.spec
---@return Keyflow.Mode
function Mode.new(spec)
	Mode_index = Mode_index + 1
	---@type Keyflow.Mode
	local result = vim.deepcopy(spec)
	result.name = spec.name or ("KeyFlow Mode" .. tostring(Mode_index))
	result.vimmode = normalize_vimmode(spec.vimmode)
	if result.map_esc then
		result.maps["<Esc>"] = Mode.exit
	end
	setmetatable(result, Mode)
	for lhs, rhs in pairs(result.maps) do
		local norm_lhs = util.normalize_key(lhs)
		result.maps[norm_lhs] = normalize_rhs(rhs)
		if norm_lhs ~= lhs then
			result.maps[lhs] = nil
		end
	end
	if result.trigger then
		if result.lazy then
			for lhs, rhs in pairs(result.maps) do
				vim.keymap.set(result.vimmode, result.trigger .. lhs, function()
					if vim.v.count == 0 then
						result:enter()
						local output = result:feed(lhs, vim.v.count)
						if output ~= "" then
							util.feed_key(output or result.trigger .. lhs)
						end
						return
					end
					local output = result:feed(lhs, vim.v.count)
					if output ~= "" then
						util.feed_key(tostring(vim.v.count .. output or result.trigger .. lhs))
					end
				end, {
					desc = rhs.desc or result.name,
					noremap = true,
				})
			end
		else
			vim.keymap.set(result.vimmode, result.trigger, function()
				if vim.v.count > 0 then
					util.feed_key(result.trigger)
				end
				result:enter()
			end, {
				desc = result.name,
				noremap = true,
			})
		end
	end
	return result
end

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

local function listener(_, typed)
	local current = active_mode
	if current == nil then
		return nil
	end

	if typed == nil or typed == "" then
		return nil
	end

	local input = vim.fn.keytrans(typed)
	local output = current:feed(input, vim.v.count)
	if output == "" or output == nil then
		return output
	end
	util.feed_key(output)
	return ""
end

local ns = vim.api.nvim_create_namespace("keyflow.nvim")
vim.on_key(listener, ns)

--- feed a key to the mode processer
---@param key string
---@param count number
---@nodiscard
---@return string?
function Mode:feed(key, count)
	local temp = self:on_key(key)
	if temp and temp ~= "" then
		util.feed_key(temp)
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
		if type(rhs.action) == "function" then
			if self.count_mode == "repeat" then
				count = count > 0 and count or 1
				for _ = 1, count do
					rhs.action(self, key)
				end
			elseif self.count_mode == true then
				rhs.action(self, key, count)
			else
				rhs.action(self, key)
			end
			return ""
		end
		return rhs.action
	else
		if self.count_mode and string.byte(key) <= string.byte("9") then
			if string.byte("1") <= string.byte(key) then
				return nil
			end
			if string.byte("0") <= string.byte(key) and count > 0 then
				return nil
			end
		end
	end

	local policy = self.foreign_policy
	if type(policy) == "function" then
		policy = policy(self, key)
	end

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
	self:exit()
	return nil
end
return Mode
