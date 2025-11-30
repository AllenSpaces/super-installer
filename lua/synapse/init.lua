local config = require("synapse.config")
local commands = require("synapse.commands")
local load_config = require("synapse.core.load")
local M = {}

--- Setup Synapse plugin manager
--- @param user_config table|nil
function M.setup(user_config)
	local merged_config = config.merge(user_config)
	vim.opt.rtp:append(merged_config.opts.package_path .. "/*")
	vim.opt.rtp:append(merged_config.opts.package_path .. "/*/after")
	
	-- Load configs (including dependency opt configurations)
	if merged_config.opts.load_config then
		load_config.load_config(merged_config.opts.load_config, merged_config.opts.config_path)
	end

	-- Setup commands and keymaps
	commands.setup(merged_config)
end

return M
