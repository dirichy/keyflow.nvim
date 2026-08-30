local action = require("keyflow.action")
local hint = require("keyflow.hint")
local util = require("keyflow.util")

local M = {}

local ns = vim.api.nvim_create_namespace("keyflow.nvim")
local installed = false
local active = nil

local valid_foreign_keys = {
	pass = true,
	consume = true,
	exit = true,
	["exit-and-pass"] = true,
}

local function canonical_input(key)
	return vim.fn.keytrans(key)
end

local ESC = canonical_input(util.keycode("<Esc>"))

local function normalize_head(lhs, spec)
	local head = {
		lhs = lhs,
		key = canonical_input(util.keycode(lhs)),
	}

	if type(spec) == "string" or type(spec) == "function" or spec == nil then
		head.action = spec
		head.exit = false
	elseif type(spec) == "table" then
		head.action = spec.action
		head.exit = spec.exit == true
		head.desc = spec.desc
	else
		error("keyflow head must be a string, function, table, or nil")
	end

	return head
end

local function normalize_heads(heads)
	vim.validate("heads", heads, "table")

	local normalized = {}

	for lhs, spec in pairs(heads) do
		if type(lhs) == "number" then
			vim.validate("heads[" .. lhs .. "]", spec, "table")

			lhs = spec[1]
			spec = spec[2] or {
				action = spec.action,
				exit = spec.exit,
				desc = spec.desc,
			}
		end

		vim.validate("head lhs", lhs, "string")

		local head = normalize_head(lhs, spec)
		normalized[head.key] = head
	end

	return normalized
end

local function exit_current()
	local current = active
	if current == nil then
		return
	end

	active = nil
	hint.close()

	if current.on_exit ~= nil then
		current.on_exit(current)
	end
end

local function enter(definition)
	if active ~= nil then
		exit_current()
	end

	active = definition

	if definition.on_enter ~= nil then
		definition.on_enter(definition)
	end

	if definition.hint then
		hint.show(definition, function()
			return active == definition
		end)
	end
end

local function run_head(definition, head)
	if definition.on_key ~= nil then
		definition.on_key(head.lhs, definition)
	end

	if definition.mode == "n" then
		action.normal(head.action)
	else
		action.run(head.action)
	end

	if head.exit then
		exit_current()
	end
end

local function dispatch(_, typed)
	local current = active
	if current == nil or action.is_running() then
		return nil
	end

	if typed == nil or typed == "" then
		return nil
	end

	local input = canonical_input(typed)

	if not util.mode_matches(current.mode) then
		exit_current()
		return nil
	end

	local head = current.heads[input]

	if head ~= nil then
		run_head(current, head)
		return ""
	end

	if current.on_key ~= nil then
		current.on_key(input, current)
	end

	if input == ESC then
		exit_current()
		return ""
	end

	local policy = current.foreign_keys

	if policy == "pass" then
		return nil
	end

	if policy == "consume" then
		return ""
	end

	exit_current()

	if policy == "exit" then
		return ""
	end

	return nil
end

local function ensure_listener()
	if installed then
		return
	end

	vim.on_key(dispatch, ns)
	installed = true
end

function M.mode(spec)
	vim.validate("spec", spec, "table")
	vim.validate("spec.mode", spec.mode, "string")
	vim.validate("spec.body", spec.body, "string")

	local foreign_keys = spec.foreign_keys or "exit-and-pass"

	if not valid_foreign_keys[foreign_keys] then
		error("invalid keyflow foreign_keys policy: " .. tostring(foreign_keys))
	end

	local definition = {
		name = spec.name,
		mode = spec.mode,
		body = spec.body,
		heads = normalize_heads(spec.heads or {}),
		hint = spec.hint == nil and true or spec.hint,
		foreign_keys = foreign_keys,
		on_enter = spec.on_enter,
		on_exit = spec.on_exit,
		on_key = spec.on_key,
	}

	ensure_listener()

	for _, head in pairs(definition.heads) do
		vim.keymap.set(spec.mode, spec.body .. head.lhs, function()
			enter(definition)
			run_head(definition, head)
		end, {
			desc = head.desc or spec.desc or spec.name,
			noremap = true,
			silent = spec.silent ~= false,
			buffer = spec.buffer,
		})
	end

	return definition
end

M.enter = enter
M.exit = exit_current

function M.active()
	return active
end

function M._reset()
	active = nil
	hint.close()
end

return M
