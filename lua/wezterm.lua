local uv = vim.loop
local fmt = string.format

local err = function(e)
	vim.notify("Wezterm failed to " .. e, vim.log.levels.ERROR, {})
end

local wezterm = {
	switch_tab = {},
	switch_pane = {},
}

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

	uv.spawn("wezterm", {
		args = args,
	}, function(code, _signal)
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
	local _handle, _pid = uv.spawn("wezterm", {
		args = { "cli", "activate-tab", "--tab-relative", fmt("%d", relno) },
	}, function(code, _signal)
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
	local _handle, _pid = uv.spawn("wezterm", {
		args = { "cli", "activate-tab", "--tab-index", fmt("%d", index) },
	}, function(code, _signal)
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
	local _handle, _pid = uv.spawn("wezterm", {
		args = { "cli", "activate-tab", "--tab-id", fmt("%d", id) },
	}, function(code, _signal)
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
	local _handle, _pid = uv.spawn("wezterm", {
		args = { "cli", "activate-pane", "--pane-id", fmt("%d", id) },
	}, function(code, _signal)
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
	local _handle, _pid = uv.spawn("wezterm", {
		args = { "cli", "activate-pane-direction", direction },
	}, function(code, _signal)
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

	if opts.create_commands == true then
		wezterm.create_commands()
	end
end

return wezterm
