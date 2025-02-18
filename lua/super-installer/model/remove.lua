local ui = require("super-installer.model.ui")
local utils = require("super-installer.model.utils")

local M = {}

function M.start(config)
	local used_plugins = {}
    local plugins = config.install.use
    table.insert(plugins, 1, config.install.default)

	for _, plugin in ipairs(plugins) do
		used_plugins[plugin:match("/([^/]+)$")] = true
	end

	local install_dir = vim.fn.stdpath("data") .. "/site/pack/packer/start"
	local installed_plugins = vim.split(vim.fn.glob(install_dir .. "/*"), "\n")

	local to_remove = {}

	for _, path in ipairs(installed_plugins) do
		local plugin_name = vim.fn.fnamemodify(path, ":t")
		if not used_plugins[plugin_name] then
			if plugin_name ~= "super-installer" then
				table.insert(to_remove, plugin_name)
			end
		end
	end

	if #to_remove == 0 then
		ui.log_message("No plugins to remove.")
		return
	end

	local total = #to_remove
	local errors = {}
	local success_count = 0
	local progress_win = ui.create_window("Removing Plugins...", 65)

	local function remove_next_plugin(index)
		if index > total then
			ui.update_progress(progress_win, "Removing: Completed", total, total, config.ui.progress.icon)
			vim.api.nvim_win_close(progress_win.win_id, true)
			ui.show_results(errors, success_count, total, "Removal")
			return
		end
		local plugin = to_remove[index]
		ui.update_progress(progress_win, "Removing: " .. plugin, index - 1, total, config.ui.progress.icon)
		M.remove_plugin(plugin, function(ok, err)
			if ok then
				success_count = success_count + 1
			else
				table.insert(errors, { plugin = plugin, error = err })
			end
			remove_next_plugin(index + 1)
		end)
	end

	remove_next_plugin(1)
end

function M.remove_plugin(plugin_name, callback)
	local install_dir = utils.get_install_dir(plugin_name,"remove")

	if vim.fn.isdirectory(install_dir) ~= 1 then
		callback(true)
		return
	end

	local cmd = string.format("rm -rf %s", install_dir)
	utils.execute_command(cmd, callback)
end

return M
