-- Run from the repository root: nvim --headless -u NONE -l tests/commands.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd())

local function equal(actual, expected)
  assert(vim.deep_equal(actual, expected), vim.inspect({
    actual = actual,
    expected = expected,
  }))
end

local notifications = {}
vim.notify = function(message, level)
  table.insert(notifications, { message, level })
end

-- Exercise the real get_text and exec_sync without a live WezTerm process.
local executable = vim.fn.executable
vim.fn.executable = function(name)
  return name == "wezterm" and 1 or executable(name)
end
local wezterm = require("wezterm")
assert(wezterm.setup({ create_commands = false }))
equal(vim.fn.exists(":WeztermGetText"), 0)
equal(vim.fn.exists(":WeztermSpawn"), 0)

local process_args
local response = { code = 0, stdout = "output\n", stderr = "" }
vim.system = function(args, opts)
  process_args = args
  assert(opts.text)
  return { wait = function() return response end }
end
equal(wezterm.get_text(), "output\n")
equal(process_args, { "wezterm", "cli", "get-text" })
equal(wezterm.get_text({
  pane_id = 0, start_line = -200, end_line = 0, escapes = true,
}), "output\n")
equal(process_args, {
  "wezterm", "cli", "get-text", "--pane-id", "0",
  "--start-line", "-200", "--end-line", "0", "--escapes",
})
response = { code = 1, stdout = "", stderr = "pane missing" }
equal(wezterm.get_text({ pane_id = 999 }), nil)
equal(notifications[#notifications], {
  "Wezterm failed to get text: pane missing", vim.log.levels.ERROR,
})

-- Exercise the real spawn implementation, including omitted program/options.
wezterm.spawn()
equal(process_args, { "wezterm", "cli", "spawn" })
wezterm.spawn(nil, { pane = 0, cwd = "/tmp" })
equal(process_args, {
  "wezterm", "cli", "spawn", "--pane-id", "0", "--cwd", "/tmp",
})

-- Run commands through Neovim so Ex argument splitting is also exercised.
local reads, list_calls = {}, 0
local output = "first\nsecond\n"
local panes = {
  { pane_id = 0, tab_id = 1, workspace = "main", title = "shell" },
  { pane_id = 7, tab_id = 2, workspace = "work", title = "server" },
}
wezterm.get_text = function(opts)
  table.insert(reads, vim.deepcopy(opts))
  return output
end
wezterm.list_panes = function()
  list_calls = list_calls + 1
  return panes
end
wezterm.create_commands()

vim.cmd("WeztermSpawn")
equal(process_args, { "wezterm", "cli", "spawn" })
vim.cmd("WeztermSpawn bash")
equal(process_args, { "wezterm", "cli", "spawn", "bash" })
vim.cmd([[WeztermSpawn printf %s hello\ world]])
equal(process_args, {
  "wezterm", "cli", "spawn", "printf", "%s", "hello world",
})
equal(vim.fn.getcompletion("WeztermGetText sta", "cmdline"), {
  "start_line=",
})

local function close_output()
  local buf = vim.api.nvim_get_current_buf()
  equal(vim.bo[buf].buftype, "nofile")
  equal(vim.bo[buf].bufhidden, "wipe")
  assert(not vim.bo[buf].swapfile)
  assert(vim.api.nvim_buf_get_name(buf):match("^wezterm://pane/"))
  vim.cmd("close")
  assert(not vim.api.nvim_buf_is_valid(buf))
end

vim.cmd("WeztermGetText start_line=-200 pane_id=0")
equal(reads[#reads], { pane_id = 0, start_line = -200 })
equal(list_calls, 0)
equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "first", "second" })
close_output()

output = ""
vim.cmd("WeztermGetText pane_id=7 start_line=0")
equal(reads[#reads], { pane_id = 7, start_line = 0 })
equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "" })
close_output()

local window_count = #vim.api.nvim_list_wins()
output = nil
vim.cmd("WeztermGetText pane_id=999")
equal(#vim.api.nvim_list_wins(), window_count)
output = "selected pane\n"

local read_count = #reads
local old_list_calls = list_calls
for _, arg in ipairs({
  "pane_id=", "pane_id=-1", "pane_id=1.5", "pane_id=abc",
  "start_line=", "start_line=1e2", "start_line=1.5",
  "unknown=1", "pane_id", "start_line=" .. string.rep("9", 400),
}) do
  local count = #notifications
  vim.cmd("WeztermGetText " .. arg)
  equal(#notifications, count + 1)
  equal(notifications[#notifications][2], vim.log.levels.ERROR)
end
equal(#reads, read_count)
equal(list_calls, old_list_calls)
equal(#vim.api.nvim_list_wins(), window_count)

-- Without Telescope, the UI callback can run asynchronously or be cancelled.
package.preload["telescope.pickers"] = function()
  error("Telescope is not installed")
end
local choose, selected_items, selected_opts
vim.ui.select = function(items, opts, callback)
  selected_items, selected_opts, choose = items, opts, callback
end
vim.cmd("WeztermGetText start_line=-25")
equal(selected_items, panes)
assert(selected_opts.format_item(panes[2]):find("server", 1, true))
equal(#reads, read_count)
choose(panes[2])
equal(reads[#reads], { pane_id = 7, start_line = -25 })
close_output()
read_count = #reads
vim.cmd("WeztermGetText")
choose(nil)
equal(#reads, read_count)
equal(#vim.api.nvim_list_wins(), window_count)

-- An empty/failed pane listing must not open a picker or create a buffer.
choose = nil
local saved_panes = panes
panes = {}
vim.cmd("WeztermGetText")
equal(choose, nil)
equal(notifications[#notifications][2], vim.log.levels.WARN)
panes = nil
vim.cmd("WeztermGetText")
equal(choose, nil)
panes = saved_panes

-- Check Telescope entry mapping and close-before-read behavior.
local picker, accept, selected, closed
local telescope = {
  ["telescope.pickers"] = {
    new = function(_, opts)
      picker = opts
      return { find = function() opts.attach_mappings(123) end }
    end,
  },
  ["telescope.finders"] = { new_table = function(opts) return opts end },
  ["telescope.config"] = {
    values = { generic_sorter = function() return {} end },
  },
  ["telescope.actions"] = {
    select_default = { replace = function(_, callback) accept = callback end },
    close = function(bufnr) closed = bufnr end,
  },
  ["telescope.actions.state"] = {
    get_selected_entry = function() return selected end,
  },
}
for name, module in pairs(telescope) do
  package.loaded[name] = nil
  package.preload[name] = function() return module end
end
vim.ui.select = function() error("Expected the Telescope picker") end
vim.cmd("WeztermGetText start_line=-50")
equal(picker.finder.results, panes)
selected = picker.finder.entry_maker(panes[2])
equal(selected.value, panes[2])
assert(selected.ordinal:find("server", 1, true))
wezterm.get_text = function(opts)
  equal(closed, 123)
  table.insert(reads, vim.deepcopy(opts))
  return output
end
accept()
equal(reads[#reads], { pane_id = 7, start_line = -50 })
close_output()
read_count = #reads
vim.cmd("WeztermGetText")
selected = nil
accept()
equal(#reads, read_count)
equal(#vim.api.nvim_list_wins(), window_count)

print("PASS: get_text, commands, completion, buffers, validation, spawn, and both pane pickers")
