local M = {}

M.setup = function(user_config)
	local default_config = {
		git = "https",

		install = {
			default = "wukuohao2003/super-installer",
			auto_download = false,
			package_path = os.getenv("HOME") .. "/.super/package",
			use = {},
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

	vim.api.nvim_create_user_command("SuperInstall", function()
		require("super-installer.model.install").start(config)
	end, {})

	vim.api.nvim_create_user_command("SuperRemove", function()
		require("super-installer.model.remove").start(config)
	end, {})

	vim.api.nvim_create_user_command("SuperUpdate", function()
		require("super-installer.model.update").start(config)
	end, {})

	local keymap_options = { noremap = true, silent = true }
	vim.keymap.set("n", config.keymaps.install, "<cmd>SuperInstall<CR>", keymap_options)
	vim.keymap.set("n", config.keymaps.remove, "<cmd>SuperRemove<CR>", keymap_options)
	vim.keymap.set("n", config.keymaps.update, "<cmd>SuperUpdate<CR>", keymap_options)

	if config.install.auto_download then
		vim.api.nvim_create_autocmd("VimEnter", {
			pattern = { "*" },
			callback = function()
				vim.fn.execute("SuperInstall")
			end,
		})
	end
end

return M
