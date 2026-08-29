local M = {}

function M.keycode(key)
  if key == nil then
    return nil
  end
  return vim.keycode(key)
end

function M.keytrans(key)
  if key == nil then
    return nil
  end
  return vim.fn.keytrans(key)
end

function M.split_keycodes(keys)
  local result = {}
  local index = 1

  while index <= #keys do
    local byte = keys:byte(index)
    if byte == 0x80 and index + 2 <= #keys then
      table.insert(result, keys:sub(index, index + 2))
      index = index + 3
    else
      table.insert(result, keys:sub(index, index))
      index = index + 1
    end
  end

  return result
end

function M.mode_matches(expected)
  if expected == nil then
    return true
  end

  local current = vim.api.nvim_get_mode().mode
  local modes = type(expected) == "table" and expected or { expected }

  for _, mode in ipairs(modes) do
    if current == mode or current:sub(1, #mode) == mode then
      return true
    end
  end

  return false
end

return M
