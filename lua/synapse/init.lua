local config = require("synapse.config")
local commands = require("synapse.commands")
local load_config = require("synapse.core.load")
local M = {}

--- Setup Synapse plugin manager
--- @param user_config table|nil
function M.setup(user_config)
	local merged_config = config.merge(user_config)
	
	-- Load first-priority configs before setup (e.g., leader key, basic settings)
	if merged_config.opts.load_config then
		load_config.load_first_config(merged_config.opts.load_config)
	end
	
	-- Setup commands and keymaps
	commands.setup(merged_config)
	
	-- Load remaining configs
	load_config.load_config(merged_config.opts.load_config)
end

return M
