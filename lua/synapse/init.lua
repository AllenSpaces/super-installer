local M = {}

M.setup = function(user_config)
	local default_config = {
		method = "https",

		opts = {
			default = "OriginCoderPulse/synapse.nvim",
			package_path = os.getenv("HOME") .. "/.synapse/package",
			config_path = os.getenv("HOME") .. "/.config/nvim",

			ui = {
				style = "float",
				icons = {
					download = "",
					update = "󰚰",
					remove = "󰺝",
					check = "󱫁",
					package = "󰏖",
					progress = "",
				},
			},
		},

		keys = {
			download = "<leader>si",
			remove = "<leader>sr",
			upgrade = "<leader>su",
		},
	}

	local config = vim.tbl_deep_extend("force", default_config, user_config or {})

	vim.api.nvim_create_user_command("SynapseDownload", function()
		require("synapse.model.install").start(config)
	end, {})

	vim.api.nvim_create_user_command("SynapseRemove", function()
		require("synapse.model.remove").start(config)
	end, {})

	vim.api.nvim_create_user_command("SynapseUpgrade", function()
		require("synapse.model.update").start(config)
	end, {})

	local keymap_options = { noremap = true, silent = true }
	vim.keymap.set("n", config.keys.download, "<cmd>SynapseDownload<CR>", keymap_options)
	vim.keymap.set("n", config.keys.remove, "<cmd>SynapseRemove<CR>", keymap_options)
	vim.keymap.set("n", config.keys.upgrade, "<cmd>SynapseUpgrade<CR>", keymap_options)
end

return M
