# keyflow.nvim

Small, composable key-mapping primitives for Neovim input behavior.

`keyflow.nvim` provides small input state machines plus a native floating hint
for transient modes. It does not depend on `which-key.nvim`.

## Requirements

Neovim 0.12 or newer.

## Processor Mappings

```lua
local keyflow = require("keyflow")

keyflow.map("i", "<Tab>", {
  {
    condition = function()
      local blink = package.loaded["blink.cmp"]
      return blink ~= nil and blink.is_visible()
    end,
    action = function()
      require("blink.cmp").select_next()
    end,
  },
  {
    condition = function()
      local ls = package.loaded["luasnip"]
      return ls ~= nil and ls.locally_jumpable(1)
    end,
    action = function()
      require("luasnip").jump(1)
    end,
  },
})
```

Steps run in array order. The first accepted step executes and stops the chain.
If no step accepts, the original key is returned as the fallback.

## Transient Mode

The following reproduces a small `hydra.nvim` "Move Screen" configuration:

```lua
local keyflow = require("keyflow")

keyflow.mode({
  name = "Move Screen",
  mode = "n",
  body = "z",
  heads = {
    l = "zl",
    h = "zh",
    L = "zL",
    H = "zH",
    j = "<C-e>",
    k = "<C-y>",
    J = "<C-d>",
    K = "<C-u>",
  },
})
```

Press `z` plus any matching head, such as `zj`, to enter the transient mode and
run that head. After entry, matching heads are consumed and can be repeated.
Pressing the body alone is left for Neovim to handle normally. `<Esc>` exits.
By default, a foreign key exits and is passed back to Neovim. A small native
hint window opens at the bottom center while the transient mode is active and
closes when the mode exits.

Per-head configuration is also supported:

```lua
keyflow.mode({
  name = "Move Screen",
  mode = "n",
  body = "z",
  heads = {
    j = { action = "<C-e>", exit = false, desc = "scroll down" },
    q = { action = nil, exit = true, desc = "quit" },
  },
  foreign_keys = "exit-and-pass",
  hint = true,
  on_enter = function() end,
  on_exit = function() end,
  on_key = function(key) end,
})
```

Set `hint = false` to disable the floating hint for a mode. `hint` may also be
a string or a function returning a string/table of lines when you want to render
custom hint text. In custom hint text, `_key_` markup is rendered as a
highlighted key, similar to `hydra.nvim`.

Supported `foreign_keys` policies:

```lua
"pass"
"consume"
"exit"
"exit-and-pass"
```

## Tests

```sh
./run_tests.sh
```
