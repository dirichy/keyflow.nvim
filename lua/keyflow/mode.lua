local action = require("keyflow.action")
local util = require("keyflow.util")

local M = {}

local ns = vim.api.nvim_create_namespace("keyflow.nvim")
local installed = false
local active = nil
local hint = nil

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

local function close_hint()
	if hint == nil then
		return
	end

	if hint.win ~= nil and vim.api.nvim_win_is_valid(hint.win) then
		pcall(vim.api.nvim_win_close, hint.win, true)
	end

	if hint.buf ~= nil and vim.api.nvim_buf_is_valid(hint.buf) then
		pcall(vim.api.nvim_buf_delete, hint.buf, { force = true })
	end

	hint = nil
end

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
	close_hint()

	if current.on_exit ~= nil then
		current.on_exit(current)
	end
end

local function head_desc(head)
	if head.desc ~= nil then
		return head.desc
	end

	if head.exit then
		return "exit"
	end

	if type(head.action) == "string" then
		return vim.fn.keytrans(head.action)
	end

	return head.lhs
end

local function sorted_heads(heads)
	local result = vim.tbl_values(heads)

	table.sort(result, function(left, right)
		return left.lhs < right.lhs
	end)

	return result
end

local function build_hint_items(definition)
	local items = {}

	for _, head in ipairs(sorted_heads(definition.heads)) do
		local padding = string.rep(" ", math.max(1, 8 - #head.lhs))
		table.insert(items, {
			text = ("_%s_%s%s"):format(head.lhs, padding, head_desc(head)),
		})
	end

	local padding = string.rep(" ", math.max(1, 8 - #"<Esc>"))
	table.insert(items, {
		text = ("_%s_%s%s"):format("<Esc>", padding, "exit"),
	})

	return items
end

local function build_hint_lines(definition)
	if type(definition.hint) == "string" then
		return vim.split(definition.hint, "\n", { plain = true })
	end

	if type(definition.hint) == "function" then
		local result = definition.hint(definition)
		if type(result) == "string" then
			return vim.split(result, "\n", { plain = true })
		end

		if type(result) == "table" then
			return result
		end
	end

	local items = build_hint_items(definition)
	local item_width = 0

	for _, item in ipairs(items) do
		item_width = math.max(item_width, vim.fn.strdisplaywidth(item.text))
	end

	item_width = item_width + 2

	local max_width = math.min(math.max(vim.o.columns - 8, 24), 80)
	local columns = math.max(1, math.min(3, math.floor(max_width / item_width)))
	local lines = {}

	for index = 1, #items, columns do
		local parts = {}

		for offset = 0, columns - 1 do
			local item = items[index + offset]
			if item == nil then
				break
			end

			table.insert(parts, item.text)
		end

		table.insert(lines, table.concat(parts, "  "))
	end

	return lines
end

local function parse_hint_markup(lines)
	local parsed = {}
	local marks = {}

	for row, line in ipairs(lines) do
		local output = {}
		local row_marks = {}
		local index = 1
		local col = 0

		while index <= #line do
			local first, last = line:find("_(.-)_", index)

			if first == nil then
				local text = line:sub(index)
				table.insert(output, text)
				col = col + #text
				break
			end

			local before = line:sub(index, first - 1)
			local key = line:sub(first + 1, last - 1)

			table.insert(output, before)
			col = col + #before
			table.insert(output, key)
			table.insert(row_marks, {
				start_col = col,
				end_col = col + #key,
			})
			col = col + #key
			index = last + 1
		end

		parsed[row] = table.concat(output)
		marks[row] = row_marks
	end

	return parsed, marks
end

local function highlight_hint_keys(buf, lines, definition, marks)
	local has_marks = false

	for row, row_marks in pairs(marks) do
		for _, mark in ipairs(row_marks) do
			has_marks = true
			vim.api.nvim_buf_set_extmark(buf, ns, row - 1, mark.start_col, {
				end_col = mark.end_col,
				hl_group = "KeyflowHintKey",
			})
		end
	end

	if has_marks then
		return
	end

	local keys = {}

	for _, head in pairs(definition.heads) do
		keys[head.lhs] = true
	end

	keys["<Esc>"] = true

	for row, line in ipairs(lines) do
		for key in pairs(keys) do
			local start = 1

			while true do
				local first, last = line:find(vim.pesc(key), start)
				if first == nil then
					break
				end

				vim.api.nvim_buf_set_extmark(buf, ns, row - 1, first - 1, {
					end_col = last,
					hl_group = "KeyflowHintKey",
				})
				start = last + 1
			end
		end
	end
end

local function show_hint(definition)
	vim.schedule(function()
		if active ~= definition then
			return
		end

		close_hint()

		local lines = build_hint_lines(definition)
		if #lines == 0 then
			return
		end

		local marks
		lines, marks = parse_hint_markup(lines)

		vim.api.nvim_set_hl(0, "KeyflowHintKey", { default = true, link = "Identifier" })
		vim.api.nvim_set_hl(0, "KeyflowHintTitle", { default = true, link = "Title" })

		local width = 1
		for _, line in ipairs(lines) do
			width = math.max(width, vim.fn.strdisplaywidth(line))
		end

		width = math.min(width, math.max(vim.o.columns - 4, 1))

		local buf = vim.api.nvim_create_buf(false, true)
		pcall(vim.api.nvim_buf_set_name, buf, "keyflow://hint")
		vim.bo[buf].bufhidden = "wipe"
		vim.bo[buf].modifiable = true
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
		highlight_hint_keys(buf, lines, definition, marks)
		vim.bo[buf].modifiable = false

		local win = vim.api.nvim_open_win(buf, false, {
			relative = "editor",
			anchor = "SE",
			row = vim.o.lines - vim.o.cmdheight - 2,
			col = vim.o.columns - 1,
			width = width,
			height = #lines,
			style = "minimal",
			border = "rounded",
			title = definition.name or "keyflow",
			title_pos = "center",
			focusable = false,
			noautocmd = true,
		})

		vim.wo[win].winhl = "FloatTitle:KeyflowHintTitle"
		hint = {
			buf = buf,
			win = win,
		}
	end)
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
		show_hint(definition)
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
		if current.on_key ~= nil then
			current.on_key(head.lhs, current)
		end

		if current.mode == "n" then
			action.normal(head.action)
		else
			action.run(head.action)
		end

		if head.exit then
			exit_current()
		end

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

	vim.keymap.set(spec.mode, spec.body, function()
		enter(definition)
	end, {
		desc = spec.desc or spec.name,
		noremap = true,
		silent = spec.silent ~= false,
		buffer = spec.buffer,
	})

	return definition
end

M.enter = enter
M.exit = exit_current

function M.active()
	return active
end

function M._reset()
	active = nil
	close_hint()
end

return M
