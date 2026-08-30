local M = {}

local ns = vim.api.nvim_create_namespace("keyflow.nvim.hint")
local state = nil

local function display_width(text)
	return vim.fn.strdisplaywidth(text or "")
end

local function pad_right(text, width)
	local padding = width - display_width(text)
	if padding <= 0 then
		return text
	end

	return text .. string.rep(" ", padding)
end

local function split_lines(text)
	return vim.split(text, "\n", { plain = true })
end

local function head_desc(head)
	if head.desc ~= nil then
		return head.desc
	end

	if head.exit then
		return "exit"
	end

	if type(head.action) == "string" then
		return vim.fn.keytrans(vim.keycode(head.action))
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

local function parse_markup(lines)
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

local function build_auto_lines(definition)
	local heads = sorted_heads(definition.heads)
	local key_width = display_width("<Esc>")
	local desc_width = display_width("exit")

	for _, head in ipairs(heads) do
		key_width = math.max(key_width, display_width(head.lhs))
		desc_width = math.max(desc_width, display_width(head_desc(head)))
	end

	local items = {}
	for _, head in ipairs(heads) do
		local key = pad_right(head.lhs, key_width)
		local desc = pad_right(head_desc(head), desc_width)
		table.insert(items, ("_%s_  %s"):format(key, desc))
	end

	table.insert(items, ("_%s_  %s"):format(pad_right("<Esc>", key_width), pad_right("exit", desc_width)))

	local rendered_width = key_width + 2 + desc_width
	local gap = 4
	local max_width = math.max(vim.o.columns - 4, 20)
	local columns = math.max(1, math.min(4, math.floor((max_width + gap) / (rendered_width + gap))))
	local lines = {}

	for index = 1, #items, columns do
		local parts = {}

		for offset = 0, columns - 1 do
			local item = items[index + offset]
			if item == nil then
				break
			end

			if offset < columns - 1 and items[index + offset + 1] ~= nil then
				item = pad_right(item, rendered_width + 2) .. string.rep(" ", gap - 2)
			end

			table.insert(parts, item)
		end

		table.insert(lines, table.concat(parts))
	end

	return parse_markup(lines)
end

local function build_custom_lines(definition)
	local value = definition.hint

	if type(value) == "function" then
		value = value(definition)
	end

	if type(value) == "string" then
		return parse_markup(split_lines(value))
	end

	if type(value) == "table" then
		return parse_markup(value)
	end

	return build_auto_lines(definition)
end

local function set_highlights()
	vim.api.nvim_set_hl(0, "KeyflowHintKey", { default = true, link = "Identifier" })
	vim.api.nvim_set_hl(0, "KeyflowHintTitle", { default = true, link = "Title" })
end

local function apply_marks(buf, marks)
	for row, row_marks in pairs(marks) do
		for _, mark in ipairs(row_marks) do
			vim.api.nvim_buf_set_extmark(buf, ns, row - 1, mark.start_col, {
				end_col = mark.end_col,
				hl_group = "KeyflowHintKey",
			})
		end
	end
end

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

function M.show(definition, is_active)
	vim.schedule(function()
		if is_active ~= nil and not is_active(definition) then
			return
		end

		M.close()

		local lines, marks = build_custom_lines(definition)
		if #lines == 0 then
			return
		end

		set_highlights()

		local width = 1
		for _, line in ipairs(lines) do
			width = math.max(width, display_width(line))
		end

		width = math.min(width, math.max(vim.o.columns - 4, 1))

		local buf = vim.api.nvim_create_buf(false, true)
		pcall(vim.api.nvim_buf_set_name, buf, "keyflow://hint")
		vim.bo[buf].bufhidden = "wipe"
		vim.bo[buf].modifiable = true
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
		apply_marks(buf, marks)
		vim.bo[buf].modifiable = false

		local win = vim.api.nvim_open_win(buf, false, {
			relative = "editor",
			anchor = "SW",
			row = vim.o.lines - vim.o.cmdheight - 2,
			col = math.max(0, math.floor((vim.o.columns - width) / 2)),
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
		state = {
			buf = buf,
			win = win,
		}
	end)
end

return M
