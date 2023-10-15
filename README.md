# wezterm.nvim

Utilities for interacting with the wezterm cli through Lua/neovim. Spawn tasks and switch tabs/panes, all from within Neovim.

## Demo

[Wezterm.nvim.webm](https://user-images.githubusercontent.com/38540736/232179762-0ac68014-f0dc-421c-a19f-b202da4ff663.webm)

## Installation

With `folke/lazy.nvim`

```lua
{
    'willothy/wezterm.nvim',
    config = true
}
```

If you don't want the `WeztermSpawn` user command, use

```lua
{
    'willothy/wezterm.nvim',
    opts = {
        create_commands = false
    }
}
```

## Usage

For API documentation, see `:h wezterm.nvim` or `doc/wezterm.nvim.txt`.

### Functions

For keybindings, functions that take a numeric value (index, id, relno, etc.) will check vim.v.count if they aren't passed an index.

For example:

```lua
-- Switch tab by index using vim.v.count
vim.keymap.set("n", "<leader>wt", require('wezterm').switch_tab.index)
```

### User command

Use `WeztermSpawn <command> <args>...` to spawn a task in a new WezTerm tab.
