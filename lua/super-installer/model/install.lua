local ui = require("super-installer.model.ui")
local utils = require("super-installer.model.utils")

local M = {}

local installation_active = true

function M.start(config)
	installation_active = true

	local plugins = {}
	table.insert(plugins, config.install.default)
	for _, plugin in ipairs(config.install.use) do
		table.insert(plugins, plugin)
	end

	local install_dir = vim.fn.stdpath("data") .. "/site/pack/packer/start"

	local existing_plugins = {}
	for _, path in ipairs(vim.split(vim.fn.glob(install_dir .. "/*"), "\n")) do
		existing_plugins[vim.fn.fnamemodify(path, ":t")] = true
	end

	local pending_install = {}
	for _, plugin in ipairs(plugins) do
		local plugin_name = plugin:match("([^/]+)$")
		if not existing_plugins[plugin_name] and plugin_name ~= "super-installer" then
			table.insert(pending_install, plugin)
		end
	end

	if #pending_install == 0 then
		ui.log_message("All plugins are already installed.")
		return
	end

	local total = #pending_install
	local errors = {}
	local installed_count = 0
	local progress_win = ui.create_window("Plugin Installation Progress", 72)

	vim.api.nvim_create_autocmd("WinClosed", {
		buffer = progress_win.buf,
		callback = function()
			installation_active = false
		end,
	})

	local function process_next(index)
		if not installation_active then
			return
		end

		if index > total then
			ui.update_progress(
				progress_win,
				config.ui.manager.icon.install .. " Finalizing installation...",
				total,
				total,
				config.ui
			)
			vim.defer_fn(function()
				vim.api.nvim_win_close(progress_win.win_id, true)
				ui.show_report(errors, installed_count, total, "installation")
			end, 500)
			return
		end

		local plugin = pending_install[index]
		ui.update_progress(progress_win, "Installing: " .. plugin, index, total, config.ui)

		M.install_plugin(plugin, config.git, function(success, err)
			if success then
				installed_count = installed_count + 1
			else
				table.insert(errors, { plugin = plugin, error = err })
			end
			process_next(index + 1)
		end)
	end

	process_next(1)
end

function M.install_plugin(plugin, git_config, callback)
	if not installation_active then
		return
	end

	local repo_url = utils.get_repo_url(plugin, git_config)
	local target_dir = utils.get_install_dir(plugin, "start")

	local command = vim.fn.isdirectory(target_dir) == 1 and string.format("cd %s && git pull --rebase", target_dir)
		or string.format("git clone --depth 1 %s %s", repo_url, target_dir)

	utils.execute_command(command, callback)
end

return M
