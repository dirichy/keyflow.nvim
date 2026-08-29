local action = require("keyflow.action")

local M = {}

local function accepts(step)
  if step.condition == nil then
    return true
  end
  return step.condition() and true or false
end

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
    if action.is_running() then
      return lhs
    end

    for _, step in ipairs(normalized) do
      if accepts(step) then
        return action.expr(step.action)
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
