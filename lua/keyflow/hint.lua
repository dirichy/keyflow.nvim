local M = {}

vim.api.nvim_set_hl(0, "KeyflowHintKey", { default = true, link = "Special" })
vim.api.nvim_set_hl(0, "KeyflowHintSep", { default = true, link = "Comment" })
vim.api.nvim_set_hl(0, "KeyflowHintDesc", { default = true, link = "Identifier" })
local ns = vim.api.nvim_create_namespace("keyflow.nvim.hint")
local state
function M.close()
	if state == nil then
		return
	end

	if state.win ~= nil and vim.api.nvim_win_is_valid(state.win) then
		pcall(vim.api.nvim_win_close, state.win, true)
	end

	if state.buf ~= nil and vim.api.nvim_buf_is_valid(state.buf) then
		pcall(vim.api.nvim_buf_delete, state.buf, { force = true })
	end

	state = nil
end
local function generate_hint(mode, width, sep, gap)
	local maps = mode.maps
	sep = sep or " ↦ "
	gap = gap or 2
	local lines = {}
	local marks = {}
	local max_key_width = 1
	local max_desc_width = 1
	for lhs, rhs in pairs(maps) do
		max_key_width = math.max(#lhs, max_key_width)
		max_desc_width = math.max(#rhs.desc, max_desc_width)
	end
	if not width then
		width = vim.o.columns
	end
	local line_term = math.floor((width + gap) / (max_key_width + max_desc_width + #sep + gap))
	local line = ""
	local index = 1
	for lhs, rhs in pairs(maps) do
		marks[#marks + 1] = { #lines, #line, #line + max_key_width, "KeyflowHintKey" }
		marks[#marks + 1] = { #lines, #line + max_key_width, #line + max_key_width + #sep, "KeyflowHintSep" }
		marks[#marks + 1] = {
			#lines,
			#line + max_key_width + #sep,
			#line + max_key_width + #sep + max_desc_width,
			"KeyflowHintDesc",
		}
		line = line
			.. string.rep(" ", max_key_width - #lhs)
			.. lhs
			.. sep
			.. rhs.desc
			.. string.rep(" ", max_desc_width - #rhs.desc)
		if index % line_term == 0 then
			lines[#lines + 1] = line
			line = ""
		else
			line = line .. string.rep(" ", gap)
		end
		index = index + 1
	end
	lines[#lines + 1] = line
	return lines, marks
end

--- Show hint for a mode
---@param mode Keyflow.Mode
function M.show(mode)
	M.close()
	local lines, marks
	if mode.hint == true then
		lines, marks = generate_hint(mode)
	elseif type(mode.hint) == "table" then
		lines = mode.hint.lines or mode.hint
		marks = mode.hint.marks or {}
	elseif type(mode.hint) == "function" then
		lines, marks = mode:hint()
	end
	local width = vim.fn.strdisplaywidth(mode.name)
	for _, line in ipairs(lines) do
		width = math.max(width, vim.fn.strdisplaywidth(line))
	end

	width = math.min(width, math.max(vim.o.columns, 1))

	local buf = vim.api.nvim_create_buf(false, true)
	pcall(vim.api.nvim_buf_set_name, buf, "keyflow://hint")
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].modifiable = true
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	if marks then
		for _, mark in ipairs(marks) do
			vim.api.nvim_buf_set_extmark(buf, ns, mark[1], mark[2], { end_col = mark[3], hl_group = mark[4] })
		end
	end
	vim.bo[buf].modifiable = false
	local win = vim.api.nvim_open_win(buf, false, {
		relative = "editor",
		anchor = "SW",
		row = vim.o.lines - vim.o.cmdheight,
		col = math.max(0, math.floor((vim.o.columns - width) / 2)),
		width = width,
		height = #lines,
		style = "minimal",
		border = "rounded",
		title = mode.name or "keyflow",
		title_pos = "center",
		focusable = false,
		noautocmd = true,
	})

	vim.wo[win].winhl = "FloatTitle:KeyflowHintTitle"
	state = {
		buf = buf,
		win = win,
	}
end
return M
