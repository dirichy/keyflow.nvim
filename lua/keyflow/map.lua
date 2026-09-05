local util = require("keyflow.util")

local M = {}
local function normalize_steps(steps)
	vim.validate("steps", steps, "table")

	local normalized = {}
	for index, step in ipairs(steps) do
		if type(step) == "function" or type(step) == "string" then
			step = { action = step }
		end

		vim.validate("steps[" .. index .. "]", step, "table")
		table.insert(normalized, {
			condition = step.condition,
			action = step.action,
			desc = step.desc,
		})
	end

	return normalized
end

function M.map(mode, lhs, steps, opts)
	vim.validate("mode", mode, { "string", "table" })
	vim.validate("lhs", lhs, "string")

	local normalized = normalize_steps(steps)
	opts = vim.tbl_extend("force", {
		expr = true,
		noremap = true,
		silent = true,
		replace_keycodes = true,
	}, opts or {})

	vim.keymap.set(mode, lhs, function()
		for _, step in ipairs(normalized) do
			if step.condition == nil or step.condition() then
				local action = step.action
				if type(action) == "function" then
					return action()
				else
					return action
				end
			end
		end

		return lhs
	end, opts)

	return {
		mode = mode,
		lhs = lhs,
		steps = normalized,
		opts = opts,
	}
end

return M
