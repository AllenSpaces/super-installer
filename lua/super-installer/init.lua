local M = {}

M.setup = function(user_config)
	local default_config = {
		git = "https",

		install = {
			default = "wukuohao2003/super-installer",
			auto_update = false,
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

	local rt_paths = vim.opt.runtimepath:get()

	for _, rt_path in ipairs(rt_paths) do
		if rt_path ~= config.install.package_path then
			vim.opt.runtimepath:append(config.install.package_path)
		end
	end

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

	if M.config.install.auto_update then
		vim.api.nvim_create_autocmd("VimEnter", {
			pattern = { "*" },
			callback = function()
				local installer, _ = pcall(vim.fn.execute, "SuperInstall")
				local need_install = require("super-installer.model.install").need_install
				if need_install then
					if not installer then
						vim.notify("Check SuperInstaller Status", vim.log.levels.WARN, { title = "SuperInstaller" })
					end
				else
					return false
				end
			end,
		})
	end
end

return M
