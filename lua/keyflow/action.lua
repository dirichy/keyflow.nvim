local M = {}

local depth = 0

function M.run(action)
	if action == nil then
		return nil
	end

	depth = depth + 1
	local ok, result

	if type(action) == "function" then
		ok, result = pcall(action)
	elseif type(action) == "string" then
		local keys = vim.keycode(action)
		ok, result = pcall(vim.api.nvim_feedkeys, keys, "n", false)
	else
		depth = depth - 1
		error("keyflow action must be a string, function, or nil")
	end

	depth = depth - 1

	if not ok then
		error(result)
	end

	return result
end

return M
