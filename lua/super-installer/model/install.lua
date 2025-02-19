local ui = require("super-installer.model.ui")
local utils = require("super-installer.model.utils")

local M = {}

local is_installation_aborted = false
local job_id = nil

function M.start(config)
	is_installation_aborted = false

	local used_plugins = {}
    local plugins = config.install.use
    table.insert(plugins, 1, config.install.default)

	used_plugins = utils.table_duplicates(used_plugins)

	for _, plugin in ipairs(plugins) do
		used_plugins[plugin] = true
	end

	local install_dir = vim.fn.stdpath("data") .. "/site/pack/packer/start"
	local installed_plugins = vim.split(vim.fn.glob(install_dir .. "/*"), "\n")

	local to_install = {}

	for _, path in ipairs(installed_plugins) do
		local plugin_name = vim.fn.fnamemodify(path, ":t")
		used_plugins[plugin_name] = true
	end

	for _, plugin in ipairs(plugins) do
		if not used_plugins[plugin:match("/([^/]+)$")] then
			if plugin_name ~= "super-installer" then
				table.insert(to_install, plugin)
			end
		end
	end

	if #to_install == 0 then
		ui.log_message("No plugins to install.")
		return
	end

	local total = #to_install
	local errors = {}
	local success_count = 0
	local progress_win = ui.create_window("Installing Plugins", 65)

	vim.api.nvim_create_autocmd("WinClosed", {
		buffer = progress_win.buf,
		callback = function()
			vim.notify(job_id)
			if(job_id) then
				vim.fn.jobstop(job_id)
			end
			is_installation_aborted = true
			ui.log_message("Plugin installation aborted by user.")
		end,
	})

	local function install_next_plugin(index)
		if is_installation_aborted then
			return
		end

		if index > total then
			ui.update_progress(progress_win, "Installing: Completed", total, total, config.ui.progress.icon)
			vim.api.nvim_win_close(progress_win.win_id, true)
			ui.show_results(errors, success_count, total, "Installation")
			return
		end

		local plugin = to_install[index]
		ui.update_progress(progress_win, "Installing: " .. plugin, index - 1, total, config.ui.progress.icon)
		M.install_plugin(plugin, config.git, function(ok, err)
			if ok then
				success_count = success_count + 1
			else
				table.insert(errors, { plugin = plugin, error = err })
			end
			install_next_plugin(index + 1)
		end)
	end

	install_next_plugin(1)
end

function M.install_plugin(plugin, git_type, callback)
	if is_installation_aborted then
		return
	end

	local repo_url = utils.get_repo_url(plugin, git_type)
	local install_dir = utils.get_install_dir(plugin,"install")

	local cmd
	if vim.fn.isdirectory(install_dir) == 1 then
		cmd = string.format("cd %s && git pull", install_dir)
	else
		cmd = string.format("git clone --depth 1 %s %s", repo_url, install_dir)
	end

	job_id = utils.execute_command(cmd, callback)
end

return M
