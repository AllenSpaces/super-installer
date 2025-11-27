local ui = require("synapse.model.ui")
local utils = require("synapse.model.utils")

local M = {}

function M.start(config)
	-- 从 config_path 读取配置文件
	local configs = utils.load_config_files(config.opts.config_path)
	
	-- 添加默认插件
	local default_config = {
		repo = config.opts.default,
		branch = "main",
		config = {},
	}
	table.insert(configs, 1, default_config)

	-- 收集所有需要的插件（包括依赖项）
	local required_plugins = {}
	for _, plugin_config in ipairs(configs) do
		if plugin_config.repo then
			local plugin_name = plugin_config.repo:match("([^/]+)$")
			plugin_name = plugin_name:gsub("%.git$", "")
			required_plugins[plugin_name] = true
			
			-- 添加依赖项
			if plugin_config.depend and type(plugin_config.depend) == "table" then
				for _, dep_repo in ipairs(plugin_config.depend) do
					local dep_name = dep_repo:match("([^/]+)$")
					dep_name = dep_name:gsub("%.git$", "")
					required_plugins[dep_name] = true
				end
			end
		end
	end

	local packer_path = config.opts.package_path
	local installed_plugins = vim.split(vim.fn.glob(packer_path .. "/*"), "\n")

	local removal_candidates = {}
	for _, path in ipairs(installed_plugins) do
		local name = vim.fn.fnamemodify(path, ":t")
		if not required_plugins[name] and name ~= "synapse" and name ~= "synapse.nvim" then
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
	local completed = 0
	local progress_win = ui.create_window("Plugin Cleanup Progress", 68)

	local function process_next(index)
		if index > total then
			ui.update_progress(progress_win, "Finalizing cleanup...", total, total, config.opts.ui)
			vim.defer_fn(function()
				vim.api.nvim_win_close(progress_win.win_id, true)
				ui.show_report(errors, removed_count, total, "removal")
			end, 300)
			return
		end

		local plugin = removal_candidates[index]
		ui.update_progress(
			progress_win,
			config.opts.ui.icons.remove .. " Removing: " .. plugin,
			completed,
			total,
			config.opts.ui
		)

		M.remove_plugin(plugin, config.opts.package_path, function(success, err)
			completed = completed + 1
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

function M.remove_plugin(plugin_name, package_path, callback)
	local install_path = utils.get_install_dir(plugin_name, "start", package_path)

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
