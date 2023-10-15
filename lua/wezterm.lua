local uv = vim.loop
local fmt = string.format

local function err(e)
  vim.notify("Wezterm failed to " .. e, vim.log.levels.ERROR, {})
end

local function find_wezterm()
  if vim.fn.executable("wezterm") ~= 0 then
    return "wezterm"
  end
  if vim.fn.executable("wezterm.exe") ~= 0 then
    return "wezterm.exe"
  end

  err("find 'wezterm' executable")
  return nil
end

local wezterm = {
  switch_tab = {},
  switch_pane = {},
  split_pane = {},
}

local wezterm_executable = ""

---@class Wezterm.SplitOpts
---@field cwd string?
---@field pane number? The pane to split (default current)
---@field top boolean? (default false)
---@field left boolean? (default false)
---@field bottom boolean? (default false)
---@field right boolean? (default false)
---@field move_pane number? Move a pane instead of spawning a command in it (default nil/disabled)
---@field percent number? The percentage of the pane to split (default nil)
---@field program string[]|nil The program to spawn in the new pane (default nil/Wezterm default)
---@field top_level boolean? Split the window instead of the pane (default false)-

---@class Wezterm.SpawnOpts
---@field pane number? Set the current pane
---@field new_window boolean? Open in a new window
---@field workspace string? Set the workspace for the new window (requires new window)
---@field cwd string? Set the cwd for the spawned program
---@field args string[]? Additional args to pass to the spawned program

---Exec an arbitrary command in wezterm (does not return result)
---@param args string[]
---@param handler fun(exit_code, signal)
function wezterm.exec(args, handler)
  uv.spawn(wezterm_executable, { args = args }, handler)
end

---Set a user var in the current wezterm pane
---@param name string
---@param value string | number | boolean | table | nil
function wezterm.set_user_var(name, value)
  local base64_encode = function(data)
    local chars =
      "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    return (
      (data:gsub(".", function(x)
        local r, b = "", x:byte()
        for i = 8, 1, -1 do
          r = r .. (b % 2 ^ i - b % 2 ^ (i - 1) > 0 and "1" or "0")
        end
        return r
      end) .. "0000"):gsub("%d%d%d?%d?%d?%d?", function(x)
        if #x < 6 then
          return ""
        end
        local c = 0
        for i = 1, 6 do
          c = c + (x:sub(i, i) == "1" and 2 ^ (6 - i) or 0)
        end
        return chars:sub(c + 1, c + 1)
      end) .. ({ "", "==", "=" })[#data % 3 + 1]
    )
  end

  local ty = type(value)

  if ty == "table" then
    value = vim.json.encode(value)
  elseif ty == "function" or ty == "thread" then
    error("cannot serialize " .. ty)
  elseif ty == "boolean" then
    value = value and "true" or "false"
  elseif ty == "nil" then
    value = ""
  end

  local template = "\x1b]1337;SetUserVar=%s=%s\a"
  local command = template:format(name, base64_encode(tostring(value)))
  vim.api.nvim_chan_send(vim.v.stderr, command)
end

---Spawn a program in wezterm
---@param program string
---@param opts Wezterm.SpawnOpts
function wezterm.spawn(program, opts)
  opts = opts or {}
  local args = { "cli", "spawn" }
  args.insert = table.insert
  if opts.pane then
    args:insert("--pane-id")
    args:insert(fmt("%d", opts.pane))
  end
  if opts.new_window then
    args:insert("--new-window")
  end
  if opts.workspace then
    if not opts.new_window then
      err("workspace option requires new_window")
      return
    end
    args:insert("--workspace")
    args:insert(opts.workspace)
  end
  if opts.cwd then
    args:insert("--cwd")
    args:insert(opts.cwd)
  end
  if program then
    args:insert(program)
    if opts.args then
      for _, arg in ipairs(opts.args) do
        args:insert(arg)
      end
    end
  end

  wezterm.exec(args, function(code, _signal)
    if code ~= 0 then
      err("spawn " .. program .. " " .. table.concat(args, " "))
    end
  end)
end

---@param args string[]
---@param opts Wezterm.SplitOpts
local function split_pane_args(args, opts)
  if opts.cwd then
    table.insert(args, "--cwd")
    table.insert(args, opts.cwd)
  end
  if opts.percent then
    table.insert(args, "--percent")
    table.insert(args, fmt("%d", opts.percent))
  end
  if opts.pane then
    table.insert(args, "--pane-id")
    table.insert(args, fmt("%d", opts.pane))
  end
  if opts.top_level then
    table.insert(args, "--top-level")
  end
  if opts.move_pane then
    if opts.program then
      err("split: move_pane and program are mutually exclusive")
      return
    end
  elseif opts.program then
    for _, arg in ipairs(opts.program) do
      table.insert(args, arg)
    end
  end
end

---Split a pane vertically
---@param opts Wezterm.SplitOpts
function wezterm.split_pane.vertical(opts)
  opts = opts or {}
  local args = { "cli", "split-pane" }
  split_pane_args(args, opts)
  if opts.top then
    table.insert(args, "--top")
  elseif opts.bottom then
    table.insert(args, "--bottom")
  else
    table.insert(args, "--vertical")
  end
  wezterm.exec(args, function(code)
    if code ~= 0 then
      err("split pane")
    end
  end)
end

---Split a pane horizontally
---@param opts Wezterm.SplitOpts
function wezterm.split_pane.horizontal(opts)
  opts = opts or {}
  local args = { "cli", "split-pane" }
  split_pane_args(args, opts)
  if opts.left then
    table.insert(args, "--left")
  elseif opts.right then
    table.insert(args, "--right")
  else
    table.insert(args, "--horizontal")
  end
  wezterm.exec(args, function(code)
    if code ~= 0 then
      err("split pane")
    end
  end)
end

---Set the title of a Wezterm tab
---@param title string
---@param id number
function wezterm.set_tab_title(title, id)
  if not title then
    return
  end
  local args = { "cli", "set-tab-title" }
  if id then
    table.insert(args, "--tab-id")
    table.insert(args, fmt("%d", id))
    table.insert(args, title)
  else
    table.insert(args, title)
  end
  wezterm.exec(args, function(code, _signal)
    if code ~= 0 then
      err(
        "set tab title to '"
          .. title
          .. (id == nil and "'" or "' for tab " .. id)
      )
    end
  end)
end

---Set the the title of a Wezterm window
---@param title string
---@param id number
function wezterm.set_win_title(title, id)
  if not title then
    return
  end
  local args = { "cli", "set-window-title" }
  if id then
    table.insert(args, "--window-id")
    table.insert(args, fmt("%d", id))
    table.insert(args, title)
  else
    table.insert(args, title)
  end
  wezterm.exec(args, function(code, _signal)
    if code ~= 0 then
      err(
        "set window title to '"
          .. title
          .. (id == nil and "'" or ("' for window " .. id))
      )
    end
  end)
end

---Switch to the tab relative to the current tab
---@param relno number The relative number of tabs to switch
function wezterm.switch_tab.relative(relno)
  if not relno then
    relno = vim.v.count or 0
  end
  wezterm.exec(
    { "cli", "activate-tab", "--tab-relative", fmt("%d", relno) },
    function(code, _signal)
      if code ~= 0 then
        err("activate tab relative " .. relno)
      end
    end
  )
end

---Switch to the tab with the given index
---@param index number The absolute index of the tab to switch to
function wezterm.switch_tab.index(index)
  if not index then
    index = vim.v.count or 0
  end
  wezterm.exec(
    { "cli", "activate-tab", "--tab-index", fmt("%d", index) },
    function(code, _signal)
      if code ~= 0 then
        err("activate tab by index " .. index)
      end
    end
  )
end

---Switch to the tab with the given id
---@param id number The id of the tab to switch to
function wezterm.switch_tab.id(id)
  if not id then
    id = vim.v.count or 0
  end
  wezterm.exec(
    { "cli", "activate-tab", "--tab-id", fmt("%d", id) },
    function(code, _signal)
      if code ~= 0 then
        err("activate tab by id " .. id)
      end
    end
  )
end

---Switch to the given pane
---@param id number The id of the pane to switch to
function wezterm.switch_pane.id(id)
  if not id then
    id = vim.v.count or 0
  end
  wezterm.exec(
    { "cli", "activate-pane", "--pane-id", fmt("%d", id) },
    function(code, _signal)
      if code ~= 0 then
        err("activate pane by id " .. id)
      end
    end
  )
end

---Used for validating directions
local directions = {
  Up = true,
  Down = true,
  Left = true,
  Right = true,
  Next = true,
  Prev = true,
}

---Switch pane in the given direction
---@param direction 'Up' | 'Down' | 'Left' | 'Right' | 'Next' | 'Prev' The direction to switch to
function wezterm.switch_pane.direction(direction)
  if not direction or not directions[direction] then
    return
  end
  wezterm.exec(
    { "cli", "activate-pane-direction", direction },
    function(code, _signal)
      if code ~= 0 then
        err("activate pane by direction " .. direction)
      end
    end
  )
end

---@private
function wezterm.create_commands()
  vim.api.nvim_create_user_command(
    "WeztermSpawn",
    "lua require('wezterm').spawn(<f-args>)",
    {
      nargs = "*",
      complete = "shellcmd",
    }
  )
end

---@private
---@class Wezterm.Config
---@field create_commands boolean
local config = {
  create_commands = true,
}

---@private
---@param opts Wezterm.Config
function wezterm.setup(opts)
  opts = vim.tbl_deep_extend("force", config, opts or {})

  wezterm_executable = find_wezterm()

  if opts.create_commands == true then
    wezterm.create_commands()
  end
end

return wezterm
