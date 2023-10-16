local uv = vim.loop
local fmt = string.format

local wezterm = {
  switch_tab = {},
  switch_pane = {},
  split_pane = {},
}

---@private
local did_setup = false

---@private
local wezterm_executable

---@private
local function err(e)
  vim.notify("Wezterm failed to " .. e, vim.log.levels.ERROR, {})
end

---@private
local function exit_handler(msg)
  return function(obj)
    if obj.code ~= 0 then
      err(msg)
    end
  end
end

---@private
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

---@private
local function count_non_nil(...)
  local n = 0
  for i = 1, select("#", ...) do
    if select(i, ...) ~= nil then
      n = n + 1
    end
  end
  return n
end

---@class Wezterm.SplitOpts
---@field cwd string|nil
---@field pane number|nil The pane to split (default current)
---@field top boolean|nil (default false)
---@field left boolean|nil (default false)
---@field bottom boolean|nil (default false)
---@field right boolean|nil (default false)
---@field move_pane number|nil Move a pane instead of spawning a command in it (default nil/disabled)
---@field percent number|nil The percentage of the pane to split (default nil)
---@field program string[]|nil The program to spawn in the new pane (default nil/Wezterm default)
---@field top_level boolean|nil Split the window instead of the pane (default false)-

---@class Wezterm.SpawnOpts
---@field pane number|nil Set the current pane
---@field new_window boolean|nil Open in a new window
---@field workspace string|nil Set the workspace for the new window (requires new window)
---@field cwd string|nil Set the cwd for the spawned program
---@field args string[]|nil Additional args to pass to the spawned program

---@class Wezterm.GetTextOpts
---@field pane_id number|nil
---@field start_line number|nil
---@field end_line number|nil
---@field escapes boolean|nil Include escape sequences in the output

---Exec an arbitrary command in wezterm (does not return result)
---@param args string[]
---@param handler fun(res: vim.SystemObj)
function wezterm.exec(args, handler)
  if not wezterm.setup({}) then
    return
  end
  vim.system({ wezterm_executable, unpack(args) }, {
    text = true,
  }, handler)
end

---Synchronously exec an arbitrary command in wezterm
---@param args string[]
---@return boolean success
---@return string stdout
---@return string stderr
function wezterm.exec_sync(args)
  if not wezterm.setup({}) then
    return false, "", ""
  end
  local rv = vim
    .system({ wezterm_executable, unpack(args) }, {
      text = true,
    })
    :wait()

  return rv.code == 0, rv.stdout, rv.stderr
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

  local emsg = "spawn " .. program .. " " .. table.concat(args, " ")
  wezterm.exec(args, exit_handler(emsg))
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
  wezterm.exec(args, exit_handler("split pane"))
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
  wezterm.exec(args, exit_handler("split pane"))
end

---Set the title of a Wezterm tab
---@param title string
---@param id number | nil Tab id
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
  wezterm.exec(
    args,
    exit_handler(
      "set tab title to '"
        .. title
        .. (id == nil and "'" or "' for tab " .. id)
    )
  )
end

---Set the the title of a Wezterm window
---@param title string
---@param id number | nil Window id
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
  wezterm.exec(
    args,
    exit_handler(
      "set window title to '"
        .. title
        .. (id == nil and "'" or ("' for window " .. id))
    )
  )
end

---Switch to the tab relative to the current tab
---@param relno number The relative number of tabs to switch
function wezterm.switch_tab.relative(relno)
  if not relno then
    relno = vim.v.count or 0
  end
  wezterm.exec(
    { "cli", "activate-tab", "--tab-relative", fmt("%d", relno) },
    exit_handler("activate tab relative " .. relno)
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
    exit_handler("activate tab by index " .. index)
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
    exit_handler("activate tab by id " .. id)
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
    exit_handler("activate pane by id " .. id)
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

---@param dir 'Up' | 'Down' | 'Left' | 'Right' | 'Next' | 'Prev'
---@param pane integer | nil Specify the current pane
function wezterm.get_pane_direction(dir, pane)
  if not dir then
    err("dir is required for get-pane-direction")
  end
  local first_char = dir:sub(1, 1)
  dir = first_char:upper() .. dir:sub(2, -1)

  if not directions[dir] then
    err("get pane: invalid direction " .. vim.inspect(dir))
  end

  local args = { "cli", "get-pane-direction" }

  if pane then
    table.insert(args, "--pane-id")
    table.insert(args, pane)
  end

  table.insert(args, dir)

  local ok, pane_id, errmsg = wezterm.exec_sync(args)

  if not ok then
    errmsg("get pane direction: " .. errmsg)
    return
  end

  pane_id = pane_id:gsub("^%s+", ""):gsub("%s+$", "")

  return tonumber(pane_id)
end

---Get the id of the current pane
---@return number | nil
function wezterm.current_pane()
  local id = vim.env.WEZTERM_PANE
  if id then
    id = id:gsub("^%s+", ""):gsub("%s+$", "")
    return tonumber(id)
  end
end

---Zoom or unzoom a pane.
---
---If no options are provided, toggles zoom for the provided (or current) pane.
---@param pane number | nil The pane to zoom (default current)
---@param opts { zoom: boolean, unzoom: boolean, toggle: boolean } # Default: { toggle = true }
function wezterm.zoom_pane(pane, opts)
  opts = opts or {}
  local args = { "cli", "zoom-pane" }

  if count_non_nil(opts.zoom, opts.unzoom, opts.toggle) > 1 then
    err("zoom pane: 'zoom', 'unzoom', and 'toggle' are mutually exclusive")
    return
  end

  if opts.zoom then
    table.insert(args, "--zoom")
  elseif opts.unzoom then
    table.insert(args, "--unzoom")
  else
    table.insert(args, "--toggle")
  end
  wezterm.exec(args, exit_handler("zoom pane"))
end

---@param opts Wezterm.GetTextOpts
function wezterm.get_text(opts)
  local args = {}

  if opts.pane_id then
    table.insert(args, "--pane-id")
    table.insert(args, opts.pane_id)
  end

  if opts.start_line then
    table.insert(args, "--start-line")
    table.insert(args, opts.start_line)
  end

  if opts.end_line then
    table.insert(args, "--end-line")
    table.insert(args, opts.end_line)
  end

  if opts.escapes then
    table.insert(args, "--escapes")
  end

  local ok, stdout, stderr = wezterm.exec_sync(args)

  if not ok then
    err("get text: " .. stderr)
    return
  end

  return stdout
end

---Switch pane in the given direction
---@param dir 'Up' | 'Down' | 'Left' | 'Right' | 'Next' | 'Prev' The direction to switch to
---@param pane integer | nil Specify the current pane
function wezterm.switch_pane.direction(dir, pane)
  if not dir then
    err("dir is required for split-pane")
  end

  local first_char = dir:sub(1, 1)
  dir = first_char:upper() .. dir:sub(2, -1)

  if not directions[dir] then
    err("switch pane: invalid direction " .. vim.inspect(dir))
    return
  end

  local args = { "cli", "activate-pane-direction" }

  if pane then
    table.insert(args, "--pane-id")
    table.insert(args, pane)
  end

  table.insert(args, dir)

  wezterm.exec(args, exit_handler("activate pane by direction " .. dir))
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
---@field create_commands boolean | nil
local config = {
  create_commands = true,
}

---@param opts Wezterm.Config
function wezterm.setup(opts)
  if did_setup then
    return wezterm_executable ~= nil
  end
  did_setup = true

  opts = vim.tbl_deep_extend("force", config, opts or {})

  local exe = find_wezterm()
  if not exe then
    err("find 'wezterm' executable")
    return false
  end
  wezterm_executable = exe

  if opts.create_commands == true then
    wezterm.create_commands()
  end

  return true
end

return wezterm
