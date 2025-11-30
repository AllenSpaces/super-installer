local ui = require("synapse.ui")
local error_ui = require("synapse.ui.error")
local git_utils = require("synapse.utils.git")
local config_utils = require("synapse.utils.config")
local yaml_utils = require("synapse.utils.yaml")
local string_utils = require("synapse.utils.string")

--- Parse a dependency item (supports both string and table formats)
--- @param dep string|table Dependency item
--- @return string repo Repository path
--- @return table|nil opt Optional configuration table
local function parse_dependency(dep)
	return config_utils.parse_dependency(dep)
end

local M = {}

local cleanup_active = true

function M.start(config)
	cleanup_active = true
	-- Clear error cache at start
	error_ui.clear_cache()
	-- 从 config_path 读取配置文件
	local configs = config_utils.load_config_files(config.opts.config_path)
	
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
				for _, dep_item in ipairs(plugin_config.depend) do
					local dep_repo = parse_dependency(dep_item)
					if dep_repo then
						local dep_name = dep_repo:match("([^/]+)$")
						dep_name = dep_name:gsub("%.git$", "")
						required_plugins[dep_name] = true
					end
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

	local function run_removal_queue(queue)
		if not queue or #queue == 0 then
			return
		end

		cleanup_active = true

		local progress_win = nil
		if #queue > 1 then
			progress_win = ui.open({
				header = config.opts.ui.header,
				icon = config.opts.ui.icons.remove,
				plugins = queue,
				ui = config.opts.ui,
			})

			vim.api.nvim_create_autocmd("WinClosed", {
				buffer = progress_win.buf,
				callback = function()
					cleanup_active = false
				end,
			})
		end

		local total = #queue
		local errors = {}
		local removed_count = 0
		local completed = 0
		local failed_list = {}

		local function finalize()
			if not cleanup_active then
				return
			end

			if #errors > 0 then
				-- Show failed plugins and allow retry
				ui.show_report(errors, removed_count, total, {
					ui = config.opts.ui,
					failed_plugins = failed_list,
					on_retry = function()
						-- Retry failed plugins
						local retry_queue = {}
						for _, err in ipairs(errors) do
							for _, plugin in ipairs(queue) do
								if plugin == err.plugin then
									table.insert(retry_queue, plugin)
									break
								end
							end
						end
						if #retry_queue > 0 then
							run_removal_queue(retry_queue)
						end
					end,
				})
			else
				vim.notify("Remove Success", vim.log.levels.INFO, { title = "Synapse" })
			end
		end

		local function process_next(index)
			if not cleanup_active then
				return
			end

			if index > total then
				finalize()
				return
			end

			local plugin = queue[index]
			if progress_win then
				ui.update_progress(progress_win, { plugin = plugin, status = "active" }, completed, total, config.opts.ui)
			end

			M.remove_plugin(plugin, config.opts.package_path, function(success, err)
				completed = completed + 1
				if success then
					removed_count = removed_count + 1
				else
					table.insert(errors, { plugin = plugin, error = err or "Removal failed" })
					table.insert(failed_list, plugin)
					-- Save error to cache (don't show window automatically)
					error_ui.save_error(plugin, err or "Removal failed")
				end

				if progress_win then
					ui.update_progress(
						progress_win,
						{ plugin = plugin, status = success and "done" or "failed" },
						completed,
						total,
						config.opts.ui
					)
				end

				process_next(index + 1)
			end)
		end

		process_next(1)
	end

	run_removal_queue(removal_candidates)
end

--- Check if a dependency is referenced by other plugins
--- @param dep_name string
--- @param package_path string
--- @param exclude_plugin string|nil Plugin name to exclude from check
--- @return boolean
local function is_dependency_referenced(dep_name, package_path, exclude_plugin)
	local yaml_path = yaml_utils.get_yaml_path(package_path)
	local data, _ = yaml_utils.read(yaml_path)
	
	if not data or not data.plugins then
		return false
	end
	
	-- Check all plugins except the one being removed
	for _, plugin in ipairs(data.plugins) do
		if plugin.name ~= exclude_plugin and plugin.depend then
			for _, dep_item in ipairs(plugin.depend) do
				local dep_repo = parse_dependency(dep_item)
				if dep_repo then
					local dep_plugin_name = string_utils.get_plugin_name(dep_repo)
					if dep_plugin_name == dep_name then
						return true
					end
				end
			end
		end
	end
	
	return false
end

--- Remove plugin from synapse.yaml
--- @param package_path string
--- @param plugin_name string
local function remove_from_yaml(package_path, plugin_name)
	local yaml_path = yaml_utils.get_yaml_path(package_path)
	local data, _ = yaml_utils.read(yaml_path)
	
	if not data or not data.plugins then
		return
	end
	
	-- Remove plugin from list
	for i, plugin in ipairs(data.plugins) do
		if plugin.name == plugin_name then
			table.remove(data.plugins, i)
			break
		end
	end
	
	-- Write back to file
	yaml_utils.write(yaml_path, data)
end

--- Get dependencies of a plugin from synapse.yaml
--- @param package_path string
--- @param plugin_name string
--- @return table|nil
local function get_plugin_dependencies(package_path, plugin_name)
	local yaml_path = yaml_utils.get_yaml_path(package_path)
	local data, _ = yaml_utils.read(yaml_path)
	
	if not data or not data.plugins then
		return nil
	end
	
	for _, plugin in ipairs(data.plugins) do
		if plugin.name == plugin_name then
			return plugin.depend or {}
		end
	end
	
	return nil
end

function M.remove_plugin(plugin_name, package_path, callback)
	local install_path = git_utils.get_install_dir(plugin_name, "start", package_path)

	if vim.fn.isdirectory(install_path) ~= 1 then
		callback(true)
		return
	end

	-- Get dependencies from synapse.yaml
	local dependencies = get_plugin_dependencies(package_path, plugin_name)
	
	-- Remove the plugin
	local cmd = string.format("rm -rf %s", vim.fn.shellescape(install_path))
	git_utils.execute_command(cmd, function(success, err)
		if success then
			-- Remove from synapse.yaml
			remove_from_yaml(package_path, plugin_name)
			
			-- Check and remove unreferenced dependencies
			if dependencies and #dependencies > 0 then
				for _, dep_repo in ipairs(dependencies) do
					local dep_name = string_utils.get_plugin_name(dep_repo)
					-- Check if dependency is referenced by other plugins
					if not is_dependency_referenced(dep_name, package_path, plugin_name) then
						-- Remove unreferenced dependency
						local dep_path = git_utils.get_install_dir(dep_name, "start", package_path)
						if vim.fn.isdirectory(dep_path) == 1 then
							local dep_cmd = string.format("rm -rf %s", vim.fn.shellescape(dep_path))
							git_utils.execute_command(dep_cmd, function() end)
							remove_from_yaml(package_path, dep_name)
						end
					end
				end
			end
			
			vim.schedule(function()
				vim.cmd("redrawtabline")
				vim.cmd("redrawstatus")
			end)
		end
		callback(success, err)
	end)
end

return M
