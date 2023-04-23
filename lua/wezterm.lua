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

local wezterm_executable = ''

---@param args string[]
---@param handler fun(exit_code, signal)
---Exec an arbitrary command in wezterm (does not return result)
function wezterm.exec(args, handler)
	uv.spawn(wezterm_executable, { args = args }, handler)
end

---@param opts SplitOpts
---@class SplitOpts
---@field pane? number The pane to split (default current)
---@field top? boolean (default false)
---@field move_pane? number|nil Move a pane instead of spawning a command in it (default nil/disabled)
---@field percent? number|nil The percentage of the pane to split (default nil)
---@field program string[]|nil The program to spawn in the new pane (default nil/Wezterm default)
---@field top_level boolean Split the window instead of the pane (default false)
function wezterm.split_pane.vertical(opts)
	opts = opts or {}
	local args = { "cli", "split-pane" }
	if opts.top then
		table.insert(args, "--top")
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
	wezterm.exec(args, function(code)
		if code ~= 0 then
			err("split pane")
		end
	end)
end

---@param opts SplitOpts
---@class SplitOpts
---@field left? boolean (default false)
---@field pane? number The pane to split (default current)
---@field move_pane? number|nil Move a pane instead of spawning a command in it (default nil/disabled)
---@field percent? number|nil The percentage of the pane to split (default nil)
---@field program string[]|nil The program to spawn in the new pane (default nil/Wezterm default)
---@field top_level boolean Split the window instead of the pane (default false)
function wezterm.split_pane.horizontal(opts)
	opts = opts or {}
	local args = { "cli", "split-pane" }
	if opts.left then
		table.insert(args, "--left")
	else
		table.insert(args, "--horizontal")
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
	wezterm.exec(args, function(code)
		if code ~= 0 then
			err("split pane")
		end
	end)
end

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
			err("set tab title to '" .. title .. (id == nil and "'" or "' for tab " .. id))
		end
	end)
end

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
			err("set window title to '" .. title .. (id == nil and "'" or ("' for window " .. id)))
		end
	end)
end

---@param program string
---@class SpawnOpts
---Set the current pane
---@field pane? number
---Open in a new window
---@field new_window? boolean
---Set the workspace for the new window (requires new window)
---@field workspace? string
---Set the cwd for the spawned program
---@field cwd? string
---@param opts SpawnOpts
---Spawn a program in wezterm
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

---@param relno number The relative number of tabs to switch
---Switch to the tab relative to the current tab
function wezterm.switch_tab.relative(relno)
	if not relno then
		relno = vim.v.count or 0
	end
	wezterm.exec({ "cli", "activate-tab", "--tab-relative", fmt("%d", relno) }, function(code, _signal)
		if code ~= 0 then
			err("activate tab relative " .. relno)
		end
	end)
end

---@param index number The absolute index of the tab to switch to
---Switch to the tab with the given index
function wezterm.switch_tab.index(index)
	if not index then
		index = vim.v.count or 0
	end
	wezterm.exec({ "cli", "activate-tab", "--tab-index", fmt("%d", index) }, function(code, _signal)
		if code ~= 0 then
			err("activate tab by index " .. index)
		end
	end)
end

---@param id number The id of the tab to switch to
---Switch to the tab with the given id
function wezterm.switch_tab.id(id)
	if not id then
		id = vim.v.count or 0
	end
	wezterm.exec({ "cli", "activate-tab", "--tab-id", fmt("%d", id) }, function(code, _signal)
		if code ~= 0 then
			err("activate tab by id " .. id)
		end
	end)
end

---@param id number The id of the pane to switch to
---Switch to the given pane
function wezterm.switch_pane.id(id)
	if not id then
		id = vim.v.count or 0
	end
	wezterm.exec({ "cli", "activate-pane", "--pane-id", fmt("%d", id) }, function(code, _signal)
		if code ~= 0 then
			err("activate pane by id " .. id)
		end
	end)
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

---@param direction "Up"|"Down"|"Left"|"Right"|"Next"|"Prev" The direction to switch to
---Switch pane in the given direction
function wezterm.switch_pane.direction(direction)
	if not direction or not directions[direction] then
		return
	end
	wezterm.exec({ "cli", "activate-pane-direction", direction }, function(code, _signal)
		if code ~= 0 then
			err("activate pane by direction " .. direction)
		end
	end)
end

function wezterm.create_commands()
	vim.api.nvim_create_user_command("WeztermSpawn", "lua require('wezterm').spawn(<f-args>)", {
		nargs = "*",
		complete = "shellcmd",
	})
end

local config = {
	create_commands = true,
}

function wezterm.setup(opts)
	opts = vim.tbl_deep_extend("force", config, opts or {})

	wezterm_executable = find_wezterm()

	if opts.create_commands == true then
		wezterm.create_commands()
	end
end

return wezterm
