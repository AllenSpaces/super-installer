local config = require("synapse.config")
local commands = require("synapse.commands")
local loadConfig = require("synapse.core.load")
local M = {}

--- Setup Synapse plugin manager
--- @param userConfig table|nil User configuration table
function M.setup(userConfig)
	local mergedConfig = config.merge(userConfig)
	vim.opt.rtp:append(mergedConfig.opts.package_path .. "/*")
	vim.opt.rtp:append(mergedConfig.opts.package_path .. "/*/after")

	-- Load configs (including dependency opt configurations and imports)
	-- Scans .config.lua files and import files from config_path
	if mergedConfig.opts.config_path then
		loadConfig.loadConfig(mergedConfig.opts.config_path, mergedConfig.imports)
	end

	-- Setup commands and keymaps
	commands.setup(mergedConfig)
end

return M
