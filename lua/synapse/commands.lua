local M = {}

--- Setup user commands and keymaps
--- @param config table
function M.setup(config)
	-- User commands
	vim.api.nvim_create_user_command("SynapseDownload", function()
		require("synapse.core.install").start(config)
	end, {})

	vim.api.nvim_create_user_command("SynapseRemove", function()
		require("synapse.core.remove").start(config)
	end, {})

	vim.api.nvim_create_user_command("SynapseUpgrade", function()
		require("synapse.core.update").start(config)
	end, {})

	-- Keymaps
	local keymap_options = { noremap = true, silent = true }
	vim.keymap.set("n", config.keys.download, "<cmd>SynapseDownload<CR>", keymap_options)
	vim.keymap.set("n", config.keys.remove, "<cmd>SynapseRemove<CR>", keymap_options)
	vim.keymap.set("n", config.keys.upgrade, "<cmd>SynapseUpgrade<CR>", keymap_options)
end

return M

