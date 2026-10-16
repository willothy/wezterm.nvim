local M = {}

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.ERROR, { title = "Wezterm" })
end

local function parse_get_text(args)
  local opts = {}
  for _, arg in ipairs(args) do
    local name, value = arg:match("^([%w_]+)=(.*)$")
    if name ~= "pane_id" and name ~= "start_line" then
      notify("Expected pane_id=<integer> or start_line=<integer>: " .. arg)
      return
    end
    local number = tonumber(value)
    if not value:match("^%-?%d+$") or not number or number % 1 ~= 0 then
      notify(name .. " must be an integer")
      return
    end
    if name == "pane_id" and number < 0 then
      notify("pane_id must be non-negative")
      return
    end
    opts[name] = number
  end
  return opts
end

local function pane_label(pane)
  return string.format(
    "pane %s | tab %s | %s | %s",
    pane.pane_id,
    pane.tab_id,
    pane.workspace or "",
    pane.title or ""
  )
end

local function select_pane(panes, on_choice)
  local ok, telescope = pcall(function()
    return {
      pickers = require("telescope.pickers"),
      finders = require("telescope.finders"),
      config = require("telescope.config").values,
      actions = require("telescope.actions"),
      state = require("telescope.actions.state"),
    }
  end)

  if not ok then
    vim.ui.select(panes, {
      prompt = "Select WezTerm pane",
      format_item = pane_label,
    }, on_choice)
    return
  end

  telescope.pickers.new({}, {
    prompt_title = "WezTerm panes",
    finder = telescope.finders.new_table({
      results = panes,
      entry_maker = function(pane)
        local label = pane_label(pane)
        return { value = pane, display = label, ordinal = label }
      end,
    }),
    sorter = telescope.config.generic_sorter({}),
    attach_mappings = function(prompt_bufnr)
      telescope.actions.select_default:replace(function()
        local selection = telescope.state.get_selected_entry()
        telescope.actions.close(prompt_bufnr)
        if selection then
          on_choice(selection.value)
        end
      end)
      return true
    end,
  }):find()
end

local function show_text(wezterm, opts)
  local text = wezterm.get_text(opts)
  if text == nil then
    return
  end

  local lines = vim.split(text, "\n", { plain = true })
  if #lines > 1 and lines[#lines] == "" then
    table.remove(lines)
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.api.nvim_buf_set_name(
    buf,
    string.format("wezterm://pane/%s/%s", opts.pane_id, buf)
  )
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.cmd("botright split")
  vim.api.nvim_win_set_buf(0, buf)
end

function M.setup(wezterm)
  vim.api.nvim_create_user_command("WeztermSpawn", function(command)
    wezterm.spawn(command.fargs[1], {
      args = vim.list_slice(command.fargs, 2),
    })
  end, {
    nargs = "*",
    complete = "shellcmd",
    desc = "Spawn a task in a new WezTerm tab",
  })

  vim.api.nvim_create_user_command("WeztermGetText", function(command)
    local opts = parse_get_text(command.fargs)
    if not opts then
      return
    end
    if opts.pane_id ~= nil then
      show_text(wezterm, opts)
      return
    end

    local panes = wezterm.list_panes()
    if not panes then
      return
    end
    if #panes == 0 then
      notify("No WezTerm panes found", vim.log.levels.WARN)
      return
    end
    select_pane(panes, function(pane)
      if pane then
        opts.pane_id = pane.pane_id
        show_text(wezterm, opts)
      end
    end)
  end, {
    nargs = "*",
    complete = function(arglead)
      return vim.tbl_filter(function(option)
        return vim.startswith(option, arglead)
      end, { "pane_id=", "start_line=" })
    end,
    desc = "Read a WezTerm pane into a scratch buffer",
  })
end

return M
