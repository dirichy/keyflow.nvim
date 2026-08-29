local M = {}

local depth = 0

function M.is_running()
  return depth > 0
end

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

function M.normal(action)
  if action == nil then
    return nil
  end

  if type(action) == "function" then
    return M.run(action)
  end

  if type(action) ~= "string" then
    error("keyflow action must be a string, function, or nil")
  end

  depth = depth + 1
  local ok, result = pcall(vim.api.nvim_cmd, {
    cmd = "normal",
    bang = true,
    args = { vim.keycode(action) },
  }, {})
  depth = depth - 1

  if not ok then
    error(result)
  end

  return result
end

function M.expr(action)
  if action == nil then
    return ""
  end

  if type(action) == "function" then
    vim.schedule(function()
      local ok, err = pcall(action)
      if not ok then
        error(err)
      end
    end)
    return ""
  end

  if type(action) == "string" then
    return action
  end

  error("keyflow action must be a string, function, or nil")
end

return M
