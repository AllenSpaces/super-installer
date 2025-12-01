local ui = require("synapse.ui")
local error_ui = require("synapse.ui.error")
local git_utils = require("synapse.utils.git")
local config_utils = require("synapse.utils.config")
local yaml_state = require("synapse.utils.yaml_state")
local string_utils = require("synapse.utils.string")

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
					local dep_repo = config_utils.parse_dependency(dep_item)
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

			-- 初始化进度显示为 0
			vim.schedule(function()
				ui.update_progress(progress_win, nil, 0, #queue, config.opts.ui)
			end)
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

		-- 并发执行器：最多同时执行10个任务
		local MAX_CONCURRENT = 10
		local pending_queue = {}
		local running_count = 0

		-- 初始化待执行队列
		for i = 1, #queue do
			table.insert(pending_queue, i)
		end

		local function start_next_removal()
			if not cleanup_active then
				return
			end

			-- 如果队列为空且没有正在运行的任务，完成
			if #pending_queue == 0 and running_count == 0 then
				finalize()
				return
			end

			-- 如果正在运行的任务达到上限或队列为空，等待
			if running_count >= MAX_CONCURRENT or #pending_queue == 0 then
				return
			end

			-- 从队列中取出一个任务
			local queue_index = table.remove(pending_queue, 1)
			local plugin = queue[queue_index]

			running_count = running_count + 1
			if progress_win then
				vim.schedule(function()
					ui.update_progress(progress_win, { plugin = plugin, status = "active" }, completed, total, config.opts.ui)
				end)
			end

			M.remove_plugin(plugin, config.opts.package_path, function(success, err)
				running_count = running_count - 1
				completed = completed + 1

				if success then
					removed_count = removed_count + 1
				else
					table.insert(errors, { plugin = plugin, error = err or "Removal failed" })
					table.insert(failed_list, plugin)
					error_ui.save_error(plugin, err or "Removal failed")
				end

				-- 立即更新进度条
				if progress_win then
					vim.schedule(function()
						ui.update_progress(
							progress_win,
							{ plugin = plugin, status = success and "done" or "failed" },
							completed,
							total,
							config.opts.ui
						)
					end)
				end

				-- 尝试启动下一个任务
				start_next_removal()
			end)
		end

		-- 启动初始任务（最多5个）
		for i = 1, math.min(MAX_CONCURRENT, #pending_queue) do
			start_next_removal()
		end
	end

	run_removal_queue(removal_candidates)
end

function M.remove_plugin(plugin_name, package_path, callback)
	local install_path = git_utils.get_install_dir(plugin_name, "start", package_path)

	if vim.fn.isdirectory(install_path) ~= 1 then
		callback(true)
		return
	end

	-- Get dependencies from synapse.yaml
	local dependencies = yaml_state.get_plugin_dependencies(package_path, plugin_name)
	
	-- Remove the plugin
	local cmd = string.format("rm -rf %s", vim.fn.shellescape(install_path))
	git_utils.execute_command(cmd, function(success, err)
		if success then
			-- Remove from synapse.yaml
			yaml_state.remove_plugin_entry(package_path, plugin_name)
			
			-- Check and remove unreferenced dependencies
			if dependencies and #dependencies > 0 then
				for _, dep_repo in ipairs(dependencies) do
					local dep_name = string_utils.get_plugin_name(dep_repo)
					-- Check if dependency is referenced by other plugins
					if not yaml_state.is_dependency_referenced(dep_name, package_path, plugin_name) then
						-- Remove unreferenced dependency
						local dep_path = git_utils.get_install_dir(dep_name, "start", package_path)
						if vim.fn.isdirectory(dep_path) == 1 then
							local dep_cmd = string.format("rm -rf %s", vim.fn.shellescape(dep_path))
							git_utils.execute_command(dep_cmd, function() end)
							yaml_state.remove_plugin_entry(package_path, dep_name)
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
