local load = require("synapse.core.handlers.load")

local M = {}

-- Active command handlers: cmd -> { pluginName -> true }
M.active = {}

--- Parse command spec (string or array of strings)
--- @param cmdSpec string|string[]|nil Command specification
--- @return string[]|nil Array of command names
local function parseCmdSpec(cmdSpec)
	if not cmdSpec then
		return nil
	end

	if type(cmdSpec) == "string" then
		return { cmdSpec }
	elseif type(cmdSpec) == "table" then
		local cmds = {}
		for _, cmd in ipairs(cmdSpec) do
			if type(cmd) == "string" then
				table.insert(cmds, cmd)
			end
		end
		return #cmds > 0 and cmds or nil
	end

	return nil
end

--- Load plugin when command is triggered
--- @param cmd string Command name
local function loadOnCommand(cmd)
	if not M.active[cmd] then
		return
	end
	
	-- Get the first plugin name for this command
	local pluginName = next(M.active[cmd])
	if not pluginName then
		return
	end
	
	-- Remove the command handler before loading
	vim.api.nvim_del_user_command(cmd)
	
	-- Load the plugin
	load.loadPlugin(pluginName)
	
	-- Re-execute the command after loading
	vim.schedule(function()
		local info = vim.api.nvim_get_commands({})[cmd] or vim.api.nvim_buf_get_commands(0, {})[cmd]
		if info then
			vim.cmd(cmd)
		else
			vim.notify("Command `" .. cmd .. "` not found after loading plugin", vim.log.levels.WARN, { title = "Synapse" })
		end
	end)
end

--- Setup lazy loading for commands
--- @param pluginName string Plugin name
--- @param cmdSpec string|string[]|nil Command specification
function M.setup(pluginName, cmdSpec)
	if not pluginName or not cmdSpec then
		return
	end

	local cmds = parseCmdSpec(cmdSpec)
	if not cmds then
		return
	end

	for _, cmd in ipairs(cmds) do
		if not M.active[cmd] then
			M.active[cmd] = {}
			-- Create user command that will load the plugin
			vim.api.nvim_create_user_command(cmd, function(event)
				loadOnCommand(cmd)
			end, {
				bang = true,
				range = true,
				nargs = "*",
			})
		end
		M.active[cmd][pluginName] = true
	end
end

return M

