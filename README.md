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

### Functions: General

<details>
<summary>
For keybindings, functions that take a numeric value (index, id, relno, etc.) will check vim.v.count if they aren't passed an index.
</summary>

For example:

```lua
-- Switch tab by index using vim.v.count
vim.keymap.set("n", "<leader>wt", require('wezterm').switch_tab.index)
```

</details>

#### Spawn a program in wezterm

```lua
wezterm.spawn(program, opts)
```

- program? (string): The program to start (wezterm default if nil)
- pane? (number): Set the current pane
- new_window? (boolean): Open in a new window
- workspace? (string): Set the workspace for the new window (requires new window)
- cwd? (string): Set the cwd for the spawned program
- args? (string[]): Args to pass to the program

#### Execute any wezterm CLI command (does not yet return result)

```lua
wezterm.exec(args, handler)
```

- args (string[]): Wezterm CLI arguments
- handler (fun(exitcode, signal))

#### Set window title

```lua
wezterm.set_window_title(title, id)
```

- title (string): The new window title
- id? (number): Optional window id to set (defaults to current tab)

### Functions: Tabs

#### Set tab title

```lua
wezterm.set_tab_title(title, id)
```

- title (string): The new tab title
- id? (number): Optional tab id to set (defaults to current tab)

#### Switch tabs by relative number

```lua
wezterm.switch_tab.relative(relno)
```

- relno (number): The relative number to switch to (-1 for prev, 1 for next, etc.)

#### Switch tabs by index

```lua
wezterm.switch_tab.index(index)
```

- index (number): The index of the tab to switch to (0-indexed)

#### Switch tabs by id

```lua
wezterm.switch_tab.id(id)
```

- id (number): The id of the tab to switch to

### Functions: Panes

#### Split pane vertically

```lua
wezterm.split_pane.vertical(opts)
```

- opts (table):
  - pane? (number): The pane to split (default current)
  - top? (boolean): Place the pane on top
  - bottom? (boolean): Place the pane on bottom
  - cwd? (string): Set the cwd for the spawned program
  - percent? (number): The percentage of the pane that the split should take up (default 50%)
  - top_level? (boolean): Split the top level window instead of the selected pane
  - move_pane? (boolean): Move the pane instead of spawning a command in it (cannot be used with program)
  - program? (string): The program to spawn in the new pane (wezterm default if nil)

#### Split pane horizontally

```lua
wezterm.split_pane.horizontal(opts)
```

- opts (table):
  - pane? (number): The pane to split (default current)
  - left? (boolean): Place the pane on the left
  - right? (boolean): Place the pane on the right
  - cwd? (string): Set the cwd for the spawned program
  - percent? (number): The percentage of the pane that the split should take up (default 50%)
  - top_level? (boolean): Split the top level window instead of the selected pane
  - move_pane? (boolean): Move the pane instead of spawning a command in it (cannot be used with program)
  - program? (string): The program to spawn in the new pane (wezterm default if nil)

#### Switch panes by id

```lua
wezterm.switch_pane.id(id)
```

- id (number): The id of the pane to switch to

#### Switch panes by direction

```lua
wezterm.switch_pane.direction(direction)
```

- direction (string): The direction of the pane to switch to
  - Directions: "Up" | "Down" | "Left" | "Right" | "Next" | "Prev"

### User command

Use `WeztermSpawn <binary> <args>...` to spawn a task in a new WezTerm tab.
