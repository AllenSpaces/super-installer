local M = {}

M.setup = function(user_config)
	local default_config = {
		git = "https",

		install = {
			default = "wukuohao2003/super-installer",
			use = {},
		},

		keymaps = {
			install = "<leader>si",
			remove = "<leader>sr",
			update = "<leader>su",
		},

		ui = {
			progress = {
				icon = "",
			},
		},
	}

	M.config = vim.tbl_deep_extend("force", default_config, user_config or {})

	vim.api.nvim_create_user_command("SuperInstall", function()
		require("super-installer.model.install").start(M.config)
	end, {})

	vim.api.nvim_create_user_command("SuperRemove", function()
		require("super-installer.model.remove").start(M.config)
	end, {})

	vim.api.nvim_create_user_command("SuperUpdate", function()
		require("super-installer.model.update").start(M.config)
	end, {})

	local keymap_opts = { noremap = true, silent = true }
	vim.keymap.set("n", M.config.keymaps.install, "<cmd>SuperInstall<CR>", keymap_opts)
	vim.keymap.set("n", M.config.keymaps.remove, "<cmd>SuperRemove<CR>", keymap_opts)
	vim.keymap.set("n", M.config.keymaps.update, "<cmd>SuperUpdate<CR>", keymap_opts)
end

return M
