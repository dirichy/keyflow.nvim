vim.opt.runtimepath:prepend(vim.fn.getcwd())

local keyflow = require("keyflow")
local mode_mod = require("keyflow.mode")

local tests = {}

local function test(name, fn)
  table.insert(tests, { name = name, fn = fn })
end

local function eq(actual, expected)
  assert(vim.deep_equal(actual, expected), ("expected %s, got %s"):format(vim.inspect(expected), vim.inspect(actual)))
end

local function keys(input)
  return vim.keycode(input)
end

local function feed(input)
  vim.api.nvim_feedkeys(keys(input), "xt", false)
end

local function wait_for(fn)
  assert(vim.wait(1000, fn, 10), "timed out waiting for condition")
end

local function hint_windows()
  local result = {}

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.api.nvim_buf_get_name(buf) == "keyflow://hint" then
      table.insert(result, win)
    end
  end

  return result
end

local function reset_buffer(lines)
  vim.cmd.stopinsert()
  vim.cmd.enew({ bang = true })
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines or { "" })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
end

local function delmap(mode, lhs)
  pcall(vim.keymap.del, mode, lhs)
end

local function reset_maps()
  mode_mod._reset()
  delmap("i", "<Tab>")
  delmap("n", "z")
  delmap("n", "zj")
  delmap("n", "zk")
  delmap("n", "zq")
  delmap("n", "z<C-x>")
  delmap("n", "z<C-A>")
  delmap("n", "m<C-A>")
end

test("processor first step accepts", function()
  reset_maps()
  reset_buffer()
  keyflow.map("i", "<Tab>", {
    { condition = function() return true end, action = "A" },
    { condition = function() return true end, action = "B" },
  })

  feed("i<Tab><Esc>")
  eq(vim.api.nvim_get_current_line(), "A")
end)

test("processor first rejects and second accepts", function()
  reset_maps()
  reset_buffer()
  keyflow.map("i", "<Tab>", {
    { condition = function() return false end, action = "A" },
    { condition = function() return true end, action = "B" },
  })

  feed("i<Tab><Esc>")
  eq(vim.api.nvim_get_current_line(), "B")
end)

test("processor all reject falls back to original key", function()
  reset_maps()
  reset_buffer()
  keyflow.map("i", "<Tab>", {
    { condition = function() return false end, action = "A" },
  })

  feed("i<Tab><Esc>")
  eq(vim.api.nvim_get_current_line(), "\t")
end)

test("processor skips unloaded lazy plugin checks", function()
  reset_maps()
  reset_buffer()
  package.loaded.keyflow_fake_lazy = nil

  keyflow.map("i", "<Tab>", {
    {
      condition = function()
        return package.loaded.keyflow_fake_lazy ~= nil
      end,
      action = "A",
    },
    { condition = function() return true end, action = "B" },
  })

  feed("i<Tab><Esc>")
  eq(vim.api.nvim_get_current_line(), "B")
  eq(package.loaded.keyflow_fake_lazy, nil)
end)

test("processor function action", function()
  reset_maps()
  reset_buffer()
  local called = false

  keyflow.map("i", "<Tab>", {
    {
      condition = function() return true end,
      action = function()
        called = true
        vim.api.nvim_set_current_line("fn")
      end,
    },
  })

  feed("i<Tab><Esc>")
  wait_for(function()
    return called
  end)
  eq(called, true)
  eq(vim.api.nvim_get_current_line(), "fn")
end)

test("submode body plus head enters and escape exits", function()
  reset_maps()
  reset_buffer()
  local entered = 0
  local exited = 0
  local count = 0

  keyflow.mode({
    mode = "n",
    body = "z",
    heads = {
      j = function() count = count + 1 end,
    },
    on_enter = function() entered = entered + 1 end,
    on_exit = function() exited = exited + 1 end,
  })

  feed("zj")
  eq(entered, 1)
  eq(count, 1)
  assert(keyflow.active() ~= nil)

  feed("<Esc>")
  eq(exited, 1)
  eq(keyflow.active(), nil)
end)

test("submode hint opens and closes with mode", function()
  reset_maps()
  reset_buffer()

  keyflow.mode({
    name = "Move Screen",
    mode = "n",
    body = "z",
    heads = {
      j = { action = "<C-e>", desc = "scroll down" },
      k = { action = "<C-y>", desc = "scroll up" },
    },
  })

  feed("zj")
  wait_for(function()
    return #hint_windows() == 1
  end)

  local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(hint_windows()[1]), 0, -1, false)
  assert(table.concat(lines, "\n"):find("scroll down", 1, true) ~= nil)
  eq(vim.api.nvim_win_get_config(hint_windows()[1]).anchor, "SW")

  feed("<Esc>")
  wait_for(function()
    return #hint_windows() == 0
  end)
end)

test("submode hint keeps special keys readable and aligned", function()
  reset_maps()
  reset_buffer()

  keyflow.mode({
    mode = "n",
    body = "z",
    heads = {
      j = { action = "<C-e>", desc = "down" },
      ["<C-A>"] = { action = "<C-A>", desc = "increment by count with a long enough label to force one column" },
    },
  })

  feed("zj")
  wait_for(function()
    return #hint_windows() == 1
  end)

  local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(hint_windows()[1]), 0, -1, false)
  local text = table.concat(lines, "\n")
  assert(text:find("<C%-A>", 1, false) ~= nil)
  assert(text:find("<lt>", 1, true) == nil)

  local j_line
  local ctrl_a_line
  for _, line in ipairs(lines) do
    if line:find("down", 1, true) then
      j_line = line
    elseif line:find("increment", 1, true) then
      ctrl_a_line = line
    end
  end

  local j_col = j_line:find("down", 1, true)
  local ctrl_a_col = ctrl_a_line:find("increment", 1, true)
  eq(j_col, ctrl_a_col)

  feed("<Esc>")
end)

test("submode hint can be disabled", function()
  reset_maps()
  reset_buffer()

  keyflow.mode({
    mode = "n",
    body = "z",
    hint = false,
    heads = {
      j = "<C-e>",
    },
  })

  feed("zj")
  vim.wait(50)
  eq(#hint_windows(), 0)
end)

test("submode hint parses hydra key markup", function()
  reset_maps()
  reset_buffer()

  keyflow.mode({
    mode = "n",
    body = "z",
    hint = "_j_: down\n_k_: up",
    heads = {
      j = "<C-e>",
      k = "<C-y>",
    },
  })

  feed("zj")
  wait_for(function()
    return #hint_windows() == 1
  end)

  local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(hint_windows()[1]), 0, -1, false)
  eq(lines, { "j: down", "k: up" })

  feed("<Esc>")
end)

test("submode head is consumed and repeatable", function()
  reset_maps()
  reset_buffer()
  local count = 0

  keyflow.mode({
    mode = "n",
    body = "z",
    heads = {
      j = function() count = count + 1 end,
    },
  })

  feed("zjj")
  eq(count, 2)
  assert(keyflow.active() ~= nil)
end)

test("submode exit-and-pass foreign key", function()
  reset_maps()
  reset_buffer({ "one two" })
  local count = 0

  keyflow.mode({
    mode = "n",
    body = "z",
    heads = {
      j = function() count = count + 1 end,
    },
  })

  feed("zjjw")
  eq(count, 2)
  eq(keyflow.active(), nil)
  eq(vim.fn.col("."), 5)
end)

test("submode consume foreign key", function()
  reset_maps()
  reset_buffer({ "one two" })
  local count = 0

  keyflow.mode({
    mode = "n",
    body = "z",
    foreign_keys = "consume",
    heads = {
      j = function() count = count + 1 end,
    },
  })

  feed("zjw")
  eq(count, 1)
  assert(keyflow.active() ~= nil)
  eq(vim.fn.col("."), 1)
end)

test("submode head exit", function()
  reset_maps()
  reset_buffer()
  local count = 0

  keyflow.mode({
    mode = "n",
    body = "z",
    heads = {
      q = { action = function() count = count + 1 end, exit = true },
    },
  })

  feed("zq")
  eq(count, 1)
  eq(keyflow.active(), nil)
end)

test("submode string action is not interpreted as a head", function()
  reset_maps()
  reset_buffer({ "abc" })

  keyflow.mode({
    mode = "n",
    body = "z",
    heads = {
      j = "x",
    },
  })

  feed("zjj")
  eq(vim.api.nvim_get_current_line(), "c")
  assert(keyflow.active() ~= nil)
end)

test("submode exits on incompatible mode", function()
  reset_maps()
  reset_buffer()
  keyflow.mode({
    mode = "n",
    body = "z",
    heads = {},
  })

  feed("zjia<Esc>")
  eq(keyflow.active(), nil)
  eq(vim.api.nvim_get_current_line(), "a")
end)

test("submode special control key head", function()
  reset_maps()
  reset_buffer()
  local count = 0

  keyflow.mode({
    mode = "n",
    body = "z",
    heads = {
      ["<C-x>"] = function() count = count + 1 end,
    },
  })

  feed("z<C-x>")
  eq(count, 1)
  assert(keyflow.active() ~= nil)
end)

test("submode body alone falls through to native mapping", function()
  reset_maps()
  reset_buffer({ "abc" })

  keyflow.mode({
    mode = "n",
    body = "m",
    heads = {
      ["<C-A>"] = function() end,
    },
  })

  feed("ma")
  eq(vim.api.nvim_buf_get_mark(0, "a"), { 1, 0 })
  eq(keyflow.active(), nil)
end)

local failures = {}

for _, item in ipairs(tests) do
  local ok, err = xpcall(item.fn, debug.traceback)
  if ok then
    print("ok - " .. item.name)
  else
    print("not ok - " .. item.name)
    print(err)
    table.insert(failures, item.name)
  end
end

if #failures > 0 then
  error(("%d test(s) failed"):format(#failures))
end

print(("%d test(s) passed"):format(#tests))
