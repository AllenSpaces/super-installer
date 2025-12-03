local ui = require("synapse.ui")
local error_ui = require("synapse.ui.error")
local git_utils = require("synapse.utils.git")
local config_utils = require("synapse.utils.config")
local json_state = require("synapse.utils.json_state")
local string_utils = require("synapse.utils.string")

local M = {}

local cleanup_active = true
local jobs = {}

function M.start(config)
	cleanup_active = true
	jobs = {}
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

	-- 即使没有需要删除的插件，也要更新 json 中的 depend 字段
	local function update_all_main_plugins_json()
		for _, plugin_config in ipairs(configs) do
			if plugin_config.repo then
				local plugin_name = plugin_config.repo:match("([^/]+)$")
				plugin_name = plugin_name:gsub("%.git$", "")
				local install_dir = git_utils.get_install_dir(plugin_name, "start", config.opts.package_path)
				
				-- 只更新已安装的主插件
				if vim.fn.isdirectory(install_dir) == 1 then
					-- 从 json 获取当前的 branch 和 tag（如果存在）
					local json_branch, json_tag = json_state.get_branch_tag(config.opts.package_path, plugin_name)
					-- 使用配置中的 branch 和 tag，如果配置中没有则使用 json 中的
					local actual_branch = plugin_config.branch or json_branch
					local actual_tag = plugin_config.tag or json_tag
					
					-- 更新 json 记录（这会同步 depend 字段）
					json_state.update_main_plugin(
						config.opts.package_path,
						plugin_name,
						plugin_config,
						actual_branch,
						actual_tag,
						true
					)
				end
			end
		end
	end

	if #removal_candidates == 0 then
		-- 即使没有需要删除的插件，也更新 json
		update_all_main_plugins_json()
		ui.log_message("No unused plugins found.")
		return
	end

	local function run_removal_queue(queue)
		if not queue or #queue == 0 then
			return
		end

		cleanup_active = true
		jobs = {}
		
		-- 保存 configs 和 config 的引用，供 finalize 使用
		local saved_configs = configs
		local saved_config = config

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
					for _, job in ipairs(jobs) do
						if job then
							vim.fn.jobstop(job)
						end
					end
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

			-- 在卸载完成后，更新所有主插件的 json 记录（同步 depend 字段）
			for _, plugin_config in ipairs(saved_configs) do
				if plugin_config.repo then
					local plugin_name = plugin_config.repo:match("([^/]+)$")
					plugin_name = plugin_name:gsub("%.git$", "")
					local install_dir = git_utils.get_install_dir(plugin_name, "start", saved_config.opts.package_path)
					
					-- 只更新已安装的主插件
					if vim.fn.isdirectory(install_dir) == 1 then
						-- 从 json 获取当前的 branch 和 tag（如果存在）
						local json_branch, json_tag = json_state.get_branch_tag(saved_config.opts.package_path, plugin_name)
						-- 使用配置中的 branch 和 tag，如果配置中没有则使用 json 中的
						local actual_branch = plugin_config.branch or json_branch
						local actual_tag = plugin_config.tag or json_tag
						
						-- 更新 json 记录（这会同步 depend 字段）
						json_state.update_main_plugin(
							saved_config.opts.package_path,
							plugin_name,
							plugin_config,
							actual_branch,
							actual_tag,
							true
						)
					end
				end
			end

			if #errors > 0 then
				-- Show failed plugins and allow retry
				ui.show_report(errors, removed_count, total, {
					ui = saved_config.opts.ui,
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

			local job_id = M.remove_plugin(plugin, config.opts.package_path, function(success, err)
				running_count = running_count - 1
				completed = completed + 1

				if success then
					removed_count = removed_count + 1
				else
					table.insert(errors, { plugin = plugin, error = err or "Removal failed" })
					table.insert(failed_list, plugin)
					error_ui.save_error(plugin, err or "Removal failed")
				end

				-- 立即更新进度条并启动下一个任务
				if progress_win then
					vim.schedule(function()
						ui.update_progress(
							progress_win,
							{ plugin = plugin, status = success and "done" or "failed" },
							completed,
							total,
							config.opts.ui
						)
						-- 尝试启动下一个任务（在 schedule 中确保立即执行）
						start_next_removal()
					end)
				else
					-- 如果没有进度窗口，直接启动下一个任务
					start_next_removal()
				end
			end)
			if job_id then
				table.insert(jobs, job_id)
			end
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

	-- Get dependencies from synapse.json
	local dependencies = json_state.get_plugin_dependencies(package_path, plugin_name)
	
	-- Remove the plugin
	local cmd = string.format("rm -rf %s", vim.fn.shellescape(install_path))
	local job_id = git_utils.execute_command(cmd, function(success, err)
		if success then
			-- Remove from synapse.json
			json_state.remove_plugin_entry(package_path, plugin_name)
			
			-- Check and remove unreferenced dependencies
			if dependencies and #dependencies > 0 then
				for _, dep_repo in ipairs(dependencies) do
					local dep_name = string_utils.get_plugin_name(dep_repo)
					-- Check if dependency is referenced by other plugins
					if not json_state.is_dependency_referenced(dep_name, package_path, plugin_name) then
						-- Remove unreferenced dependency
						local dep_path = git_utils.get_install_dir(dep_name, "start", package_path)
						if vim.fn.isdirectory(dep_path) == 1 then
							local dep_cmd = string.format("rm -rf %s", vim.fn.shellescape(dep_path))
							git_utils.execute_command(dep_cmd, function() end)
							json_state.remove_plugin_entry(package_path, dep_name)
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
	return job_id
end

return M
