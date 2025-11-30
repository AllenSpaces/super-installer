local config = require("synapse.config")
local commands = require("synapse.commands")
local load_config = require("synapse.core.load")
local M = {}

--- Setup Synapse plugin manager
--- @param user_config table|nil
function M.setup(user_config)
	local merged_config = config.merge(user_config)
	commands.setup(merged_config)
	load_config.load_config(merged_config.opts.load_config)
end

return M
