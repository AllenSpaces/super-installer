local M = {}

M.setup = function(user_config)
	local default_config = {
		methods = "https",

		opts = {
			default = "OriginCoderPulse/synapse.nvim",
			package_path = os.getenv("HOME") .. "/.super/package",
			config_path = os.getenv("HOME") .. "/.config/nvim",
		},

		keymaps = {
			install = "<leader>si",
			remove = "<leader>sr",
			update = "<leader>su",
		},

		ui = {
			progress = {
				icon = "",
			},
			manager = {
				icon = {
					install = "",
					update = "",
					remove = "󰺝",
					check = "󱫁",
					package = "󰏖",
				},
			},
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
	vim.keymap.set("n", config.keymaps.install, "<cmd>SynapseDownload<CR>", keymap_options)
	vim.keymap.set("n", config.keymaps.remove, "<cmd>SynapseRemove<CR>", keymap_options)
	vim.keymap.set("n", config.keymaps.update, "<cmd>SynapseUpgrade<CR>", keymap_options)

	-- 默认自动安装
	vim.api.nvim_create_autocmd("VimEnter", {
		pattern = { "*" },
		callback = function()
			vim.fn.execute("SynapseDownload")
		end,
	})
end

return M
