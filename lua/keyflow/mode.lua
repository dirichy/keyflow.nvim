local util = require("keyflow.util")
local hint = require("keyflow.hint")

local function noop() end

---@alias Keyflow.Mode.foreignPolicy.enum "pass"|"exit"|"exit_and_pass"|"consume"
---@alias Keyflow.Mode.foreignPolicy Keyflow.Mode.foreignPolicy.enum|fun(self:Keyflow.Mode,key:string):Keyflow.Mode.foreignPolicy.enum
---@alias Keyflow.Rhs {action:string|function,desc:string?}
---@class Keyflow.Mode.spec
---@field name string?
---@field vimmode string|string[]|nil
---@field trigger string?
---@field lazy boolean?
---@field maps table<string,Keyflow.Rhs|string|fun(self:Keyflow.Mode,key:string,count:number):string?>?
---@field hint boolean|{lines:string[],marks:table}|fun(self:Keyflow.Mode):string[],table|nil
---@field foreign_policy Keyflow.Mode.foreignPolicy?
---@field map_esc boolean?
---@field count_mode boolean|"repeat"|nil
---@field count_max number?
---@field on_enter fun(self:Keyflow.Mode)|nil
---@field on_exit fun(self:Keyflow.Mode)|nil
---@field on_key fun(self:Keyflow.Mode,key:string):string?|nil
---@class Keyflow.Mode
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
		return vim.tbl_extend("force", {
			desc = type(rhs.action) == "string" and rhs.action or "lua function",
		}, rhs)
	end
	return { action = rhs, desc = type(rhs) == "string" and rhs or "lua function" }
end

local Mode_index = 0
---@type Keyflow.Mode?
local active_mode = nil

---@param spec Keyflow.Mode.spec
---@return Keyflow.Mode
function Mode.new(spec)
	vim.validate("spec", spec, "table")
	Mode_index = Mode_index + 1

	---@type Keyflow.Mode
	local result = vim.tbl_extend("force", {
		foreign_policy = "exit_and_pass",
		lazy = true,
		hint = true,
		count_mode = true,
		count_max = 99,
		maps = {},
		map_esc = true,
	}, vim.deepcopy(spec))
	result.name = spec.name or ("KeyFlow Mode" .. tostring(Mode_index))
	result.vimmode = normalize_vimmode(spec.vimmode)
	if result.map_esc then
		result.maps["<Esc>"] = Mode.exit
	end

	setmetatable(result, Mode)
	local normalized_maps = {}
	for lhs, rhs in pairs(result.maps) do
		normalized_maps[util.normalize_key(lhs)] = normalize_rhs(rhs)
	end
	result.maps = normalized_maps

	if result.trigger then
		if result.lazy then
			for lhs, rhs in pairs(result.maps) do
				vim.keymap.set(result.vimmode, result.trigger .. lhs, function()
					result:run({ lhs }, vim.v.count)
				end, {
					desc = rhs.desc or result.name,
					noremap = true,
				})
			end
		else
			vim.keymap.set(result.vimmode, result.trigger, function()
				result:run(nil, vim.v.count)
			end, {
				desc = result.name,
				noremap = true,
			})
		end
	end

	return result
end

function Mode.active()
	return active_mode
end

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
	if active_mode ~= nil and active_mode ~= self then
		Mode.exit()
	end
	active_mode = self
	if self.hint then
		hint.show(self)
	end
	self:on_enter()
end

local function normalize_input(key)
	return util.normalize_key(key)
end

--- Process one key. The second return value requests passing the key back to Nvim.
---@param key string
---@param count number
---@return string?, boolean
function Mode:feed(key, count)
	local temp = self:on_key(key)
	if temp and temp ~= "" then
		util.feed_key(temp)
		return "", false
	end
	if temp == "" then
		return "", false
	end

	if not util.mode_matches(self.vimmode) then
		self:exit()
		return nil, true
	end

	local rhs = self.maps[key]
	if rhs then
		if type(rhs.action) == "function" then
			if self.count_mode == "repeat" then
				count = math.min(count > 0 and count or 1, self.count_max)
				for _ = 1, count do
					rhs.action(self, key)
				end
			elseif self.count_mode == true then
				rhs.action(self, key, count)
			else
				rhs.action(self, key)
			end
			return "", false
		end
		return rhs.action, false
	end

	local policy = self.foreign_policy
	if type(policy) == "function" then
		policy = policy(self, key)
	end
	if policy == "pass" then
		return nil, true
	elseif policy == "consume" then
		return "", false
	elseif policy == "exit" then
		self:exit()
		return "", false
	elseif policy == "exit_and_pass" then
		self:exit()
		return nil, true
	end

	self:exit()
	return nil, true
end

local function is_count_key(key)
	return #key == 1 and key >= "0" and key <= "9"
end

--- Run an exclusive input session until this mode exits.
---@param init_keys string[]?
---@param initial_count number?
---@return any
function Mode:run(init_keys, initial_count)
	local pending_count = initial_count or 0
	local result

	local function process(key)
		key = normalize_input(key)
		if self.count_mode and is_count_key(key) then
			if key ~= "0" or pending_count > 0 then
				pending_count = math.min(pending_count * 10 + tonumber(key), self.count_max)
				return
			end
		end

		local count = pending_count
		pending_count = 0
		local output, pass = self:feed(key, count)
		if output and output ~= "" then
			util.feed_key(output)
		elseif pass then
			util.feed_key(key)
		end
	end

	local ok, err = xpcall(function()
		self:enter()
		for _, key in ipairs(init_keys or {}) do
			process(key)
			if active_mode ~= self then
				return
			end
		end
		while active_mode == self do
			local read_ok, key = pcall(vim.fn.getcharstr, -1)
			if not read_ok then
				if tostring(key) ~= "Keyboard interrupt" then
					error(key, 0)
				end
				self:exit()
				break
			elseif key == "" or key == "\3" then
				self:exit()
				break
			end
			process(key)
		end
	end, debug.traceback)

	if not ok then
		if active_mode == self then
			Mode.exit()
		end
		error(err, 0)
	end
	return result
end

return Mode
