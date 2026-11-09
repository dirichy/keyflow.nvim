# keyflow.nvim

Small, composable key-mapping primitives for Neovim input behavior.

`keyflow.nvim` provides conditional mappings and transient modes with a native
floating hint.

## Requirements

Neovim 0.12 or newer.

## Conditional mappings

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

## Transient mode

```lua
local keyflow = require("keyflow")

keyflow.mode({
  name = "Move Screen",
  vimmode = "n",
  trigger = "z",
  maps = {
    j = { action = "<C-e>", desc = "scroll down" },
    k = { action = "<C-y>", desc = "scroll up" },
    q = { action = function(mode) mode:exit() end, desc = "quit" },
  },
})
```

`trigger` plus a key in `maps` enters the mode and runs that action. Matching
keys can then be repeated. Once entered, the mode reads keys exclusively until
it exits; existing normal-mode mappings do not compete with its maps. `<Esc>`
exits by default. A foreign key exits and is passed back to Neovim by default.

Each map value can be a string, a function, or a table with `action` and an
optional `desc`. Set `lazy = false` to map `trigger` by itself and enter the
mode before processing subsequent keys.

Supported `foreign_policy` values are `"pass"`, `"consume"`, `"exit"`, and
`"exit_and_pass"`. `count_mode` can be `false`, `true`, or `"repeat"`.

Set `hint = false` to disable the floating hint. A table such as
`{ lines = { "j: down" }, marks = {} }` can provide custom lines and extmarks;
a function may return `lines, marks`.

The active mode is available through `keyflow.active()`. Lifecycle callbacks
are `on_enter`, `on_exit`, and `on_key`.

## Tests

```sh
./run_tests.sh
```
