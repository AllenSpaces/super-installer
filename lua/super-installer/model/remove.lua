local ui = require("super-installer.model.ui")
local utils = require("super-installer.model.utils")

local M = {}

function M.start(config)
	local required_plugins = {}
	local plugin_specs = { config.install.default }

	for _, spec in ipairs(config.install.use) do
		table.insert(plugin_specs, spec)
	end

	for _, spec in ipairs(plugin_specs) do
		required_plugins[spec:match("/([^/]+)$")] = true
	end

	local packer_path = vim.fn.stdpath("data") .. "/site/pack/packer/start"
	local installed_plugins = vim.split(vim.fn.glob(packer_path .. "/*"), "\n")

	local removal_candidates = {}
	for _, path in ipairs(installed_plugins) do
		local name = vim.fn.fnamemodify(path, ":t")
		if not required_plugins[name] and name ~= "super-installer" then
			table.insert(removal_candidates, name)
		end
	end

	if #removal_candidates == 0 then
		ui.log_message("No unused plugins found.")
		return
	end

	local total = #removal_candidates
	local errors = {}
	local removed_count = 0
	local progress_win = ui.create_window("Plugin Cleanup Progress", 70)

	local function process_next(index)
		if index > total then
			ui.update_progress(progress_win, "Finalizing cleanup...", total, total, config.ui)
			vim.defer_fn(function()
				vim.api.nvim_win_close(progress_win.win_id, true)
				ui.show_report(errors, removed_count, total, "removal")
			end, 300)
			return
		end

		local plugin = removal_candidates[index]
		ui.update_progress(
			progress_win,
			config.ui.manager.icon.remove .. " Removing: " .. plugin,
			index - 1,
			total,
			config.ui
		)

		M.remove_plugin(plugin, function(success, err)
			if success then
				removed_count = removed_count + 1
			else
				table.insert(errors, { plugin = plugin, error = err })
			end
			process_next(index + 1)
		end)
	end

	process_next(1)
end

function M.remove_plugin(plugin_name, callback)
	local install_path = utils.get_install_dir(plugin_name, "start")

	if vim.fn.isdirectory(install_path) ~= 1 then
		callback(true)
		return
	end

	local cmd = string.format("rm -rf %s", vim.fn.shellescape(install_path))
	utils.execute_command(cmd, function(success, err)
		if success then
			vim.schedule(function()
				vim.cmd("redrawtabline")
				vim.cmd("redrawstatus")
			end)
		end
		callback(success, err)
	end)
end

return M
