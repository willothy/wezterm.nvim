local Path = require("plenary.path")
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
  vim.notify("Wezterm failed to " .. e, vim.log.levels.ERROR, {
    title = "Wezterm",
  })
end

---@private
local function exit_handler(msg)
  ---@param obj vim.SystemCompleted
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

---@class wezterm.SplitOpts
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

---@class wezterm.SpawnOpts
---@field pane number|nil Set the current pane
---@field new_window boolean|nil Open in a new window
---@field workspace string|nil Set the workspace for the new window (requires new window)
---@field cwd string|nil Set the cwd for the spawned program
---@field args string[]|nil Additional args to pass to the spawned program

---@class wezterm.GetTextOpts
---@field pane_id number|nil
---@field start_line number|nil
---@field end_line number|nil
---@field escapes boolean|nil Include escape sequences in the output

---Exec an arbitrary command in wezterm (does not return result)
---@param args string[]
---@param handler fun(res: vim.SystemObj)
---@param stdin string|string[]|boolean If `true`, then a pipe to stdin is opened and can be written to via the `write()` method to SystemObj. If string or string[] then will be written to stdin
function wezterm.exec(args, handler, stdin)
  if not wezterm.setup({}) then
    return
  end
  vim.system({ wezterm_executable, unpack(args) }, {
    stdin = stdin,
    text = true,
  }, vim.schedule_wrap(handler))
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
  local command = template:format(name, vim.base64.encode(tostring(value)))
  vim.api.nvim_chan_send(vim.v.stderr, command)
end

---Show a desktop notification from wezterm
---@param title string
---@param body string
function wezterm.notify(title, body)
  local template = "\x1b]777;notify;%s;%s\x1b\\"
  local command = template:format(title or "", body or "")
  vim.api.nvim_chan_send(vim.v.stderr, command)
end

---Spawn a program in wezterm
---@param program string
---@param opts wezterm.SpawnOpts
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
    local path = Path:new(opts.cwd)
    args:insert(path:expand())
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
---@param opts wezterm.SplitOpts
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
---@param opts wezterm.SplitOpts
function wezterm.split_pane.vertical(opts)
  opts = opts or {}
  local args = { "cli", "split-pane" }
  split_pane_args(args, opts)
  if opts.top then
    table.insert(args, "--top")
  elseif opts.bottom then
    table.insert(args, "--bottom")
  end
  wezterm.exec(args, exit_handler("split pane"))
end

---Split a pane horizontally
---@param opts wezterm.SplitOpts
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
function wezterm.get_current_pane()
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

  if pane then
    table.insert(args, "--pane-id")
    table.insert(args, pane)
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

---@param opts wezterm.GetTextOpts
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

---Send text to a pane
---@param text string Text to send
---@param pane integer | nil Specify thecurrent pane
---@param no_paste boolean|nil (default false)
function wezterm.send_text(text, pane, no_paste)
  if not text then
    err("text is required for send-text")
  end

  local args = { "cli", "send-text" }

  if pane then
    table.insert(args, "--pane-id")
    table.insert(args, pane)
  end

  if no_paste then
    table.insert(args, "--no-paste")
  end

  wezterm.exec(args, exit_handler("send text to pane"), text)
end

local function trim(str)
  return str:gsub("^%s+", ""):gsub("%s+$", "")
end

---@text The size of a Wezterm pane
---@class Wezterm.PaneSize
---@field cols integer
---@field rows integer
---@field pixel_width integer
---@field pixel_height integer
---@field dpi integer

---@text Information about a Wezterm pane
---@class Wezterm.Pane
---@field cursor_shape string
---@field cursor_visibility string
---@field cursor_x integer
---@field cursor_y integer
---@field cwd string
---@field is_active boolean
---@field is_zoomed boolean
---@field left_col integer
---@field pane_id integer
---@field size Wezterm.PaneSize
---@field tab_id integer
---@field tab_title string
---@field title string
---@field top_row integer
---@field tty_name string
---@field window_id integer
---@field window_title string
---@field workspace string

---@text Information about a Wezterm tab
---@class Wezterm.Tab
---@field tab_id integer
---@field tab_title string
---@field window_id integer
---@field window_title string
---@field panes Wezterm.Pane[]

---@text Information about a Wezterm GUI window
---@class Wezterm.Window
---@field window_id integer
---@field window_title string
---@field tabs Wezterm.Tab[]

---@text Wrapper around `wezterm cli list`
---
---@return Wezterm.Pane[]?
function wezterm.list_panes()
  local ok, stdout, stderr =
    wezterm.exec_sync({ "cli", "list", "--format", "json" })
  if not ok then
    err("list panes: " .. stderr)
    return
  end
  local decoded, obj = pcall(vim.json.decode, trim(stdout), {
    luanil = {
      object = true,
      array = true,
    },
  })
  if not decoded then
    err("list panes: " .. obj)
    return
  end
  return obj
end

---@text Wrapper around `wezterm cli list`
---
---@return Wezterm.Tab[]?
function wezterm.list_tabs()
  local tabs = {}
  local by_id = {}
  local panes = wezterm.list_panes()
  if not panes then
    return
  end
  for _, pane in ipairs(panes) do
    local tab_id = pane.tab_id
    if not by_id[tab_id] then
      by_id[tab_id] = {
        tab_id = tab_id,
        tab_title = pane.tab_title,
        window_id = pane.window_id,
        window_title = pane.window_title,
        panes = {},
      }
      table.insert(tabs, by_id[tab_id])
    end
    table.insert(by_id[tab_id].panes, pane)
  end
  return tabs
end

---@text Wrapper around `wezterm cli list`
---
---@return Wezterm.Window[]?
function wezterm.list_windows()
  local windows = {}
  local by_id = {}

  local tabs = wezterm.list_tabs()
  if not tabs then
    return
  end

  for _, tab in ipairs(tabs) do
    local window_id = tab.window_id
    if not by_id[window_id] then
      by_id[window_id] = {
        window_id = window_id,
        window_title = tab.window_title,
        tabs = {},
      }
      table.insert(windows, by_id[window_id])
    end
    table.insert(by_id[window_id].tabs, tab)
  end

  return windows
end

---Wrapper around `wezterm cli list-clients`
---
---@return table[]?
function wezterm.list_clients()
  local ok, stdout, stderr =
    wezterm.exec_sync({ "cli", "list-clients", "--format", "json" })
  if not ok then
    err("list panes: " .. stderr)
    return
  end
  local decoded, obj = pcall(vim.json.decode, trim(stdout), {
    luanil = {
      object = true,
      array = true,
    },
  })
  if not decoded then
    err("list panes: " .. obj)
    return
  end
  return obj
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
---@class wezterm.Config
---@field create_commands boolean | nil
local config = {
  create_commands = true,
}

---@param opts wezterm.Config
function wezterm.setup(opts)
  if did_setup then
    return wezterm_executable ~= nil
  end
  did_setup = true

  opts = vim.tbl_deep_extend("force", config, opts or {})

  if vim.system == nil or vim.base64 == nil then
    vim.notify_once(
      "Wezterm.nvim requires Neovim >= 0.10. If you are using an older version, consider upgrading or pinning v0.4.0 of this plugin.",
      vim.log.levels.ERROR,
      {
        title = "Wezterm",
      }
    )
  end

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
