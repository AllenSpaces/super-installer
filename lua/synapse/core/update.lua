local ui = require("synapse.ui")
local error_ui = require("synapse.ui.error")
local git_utils = require("synapse.utils.git")
local config_utils = require("synapse.utils.config")
local string_utils = require("synapse.utils.string")
local yaml_state = require("synapse.utils.yaml_state")

local M = {}

local is_update_aborted = false
local update_win = nil
local jobs = {}

--- Execute commands sequentially in plugin directory
--- @param commands table Array of command strings
--- @param plugin_dir string Plugin installation directory
--- @param callback function Callback function(success, err)
local function execute_commands(commands, plugin_dir, callback)
	if not commands or #commands == 0 then
		return callback(true, nil)
	end

	local function run_next(index)
		if index > #commands then
			return callback(true, nil)
		end

		local cmd = commands[index]
		local full_cmd = string.format("cd %s && %s", vim.fn.shellescape(plugin_dir), cmd)
		
		git_utils.execute_command(full_cmd, function(success, err)
			if success then
				run_next(index + 1)
			else
				callback(false, string.format("Execute command failed: %s - %s", cmd, err))
			end
		end)
	end

	run_next(1)
end

function M.start(config)
	is_update_aborted = false
	jobs = {}
	-- Clear error cache at start
	error_ui.clear_cache()

	-- 从 config_path 读取配置文件
	local configs = config_utils.load_config_files(config.opts.config_path)
	
	-- 添加默认插件
	local default_config = {
		repo = config.opts.default,
		-- Don't set branch by default, let git use default branch
		config = {},
	}
	table.insert(configs, 1, default_config)

	-- 建立 repo 到 plugin_config 的映射（用于获取 tag 等信息）
	local repo_to_config = {}
	local main_plugin_repos = {} -- 用于判断是否是主插件
	for _, plugin_config in ipairs(configs) do
		if plugin_config.repo then
			repo_to_config[plugin_config.repo] = plugin_config
			main_plugin_repos[plugin_config.repo] = true
		end
	end

	-- 提取所有 repo 字段（包括依赖项）
	local plugins = {}
	local plugin_set = {}
	
	for _, plugin_config in ipairs(configs) do
		if plugin_config.repo then
			-- 添加主插件
			if not plugin_set[plugin_config.repo] then
				table.insert(plugins, plugin_config.repo)
				plugin_set[plugin_config.repo] = true
			end
			
			-- 添加依赖项
			if plugin_config.depend and type(plugin_config.depend) == "table" then
				for _, dep_item in ipairs(plugin_config.depend) do
					local dep_repo, dep_opt = config_utils.parse_dependency(dep_item)
					if dep_repo and not plugin_set[dep_repo] then
						table.insert(plugins, dep_repo)
						plugin_set[dep_repo] = true
						-- 为依赖项创建默认配置（如果还没有）
						if not repo_to_config[dep_repo] then
							local dep_config = {
								repo = dep_repo,
								-- Don't set branch by default, let git use default branch
								config = {},
							}
							if dep_opt then
								dep_config.opt = dep_opt
							end
							repo_to_config[dep_repo] = dep_config
						end
					end
				end
			end
		end
	end

	if #plugins == 0 then
		ui.log_message("Nothing to update.")
		return
	end

	local function plugin_names(list)
		local names = {}
		for _, repo in ipairs(list) do
			table.insert(names, string_utils.get_plugin_name(repo))
		end
		return names
	end

	local function attach_close_autocmd(buf)
		vim.api.nvim_create_autocmd("WinClosed", {
			buffer = buf,
			callback = function()
				is_update_aborted = true
				for _, job in ipairs(jobs) do
					vim.fn.jobstop(job)
				end
			end,
		})
	end

	local function start_update_flow(targets, attempt, aggregate)
		attempt = attempt or 1
		aggregate = aggregate or { errors = {}, success = 0, total = 0, checks = 0, check_success = 0 }
		if not targets or #targets == 0 then
			ui.log_message("Nothing to update.")
			return
		end

		is_update_aborted = false
		jobs = {}

		local close_registered = false

		local function ensure_close(buf)
			if close_registered then
				return
			end
			attach_close_autocmd(buf)
			close_registered = true
		end

		local function extract_retry_targets(check_errors)
			local retry_targets = {}
			local seen = {}
			for _, err in ipairs(check_errors or {}) do
				if err.repo and not seen[err.repo] then
					seen[err.repo] = true
					table.insert(retry_targets, err.repo)
				end
			end
			return retry_targets
		end

		local function format_icon(cfg)
			if type(cfg) == "table" then
				return cfg.glyph or cfg.text or cfg.icon or ""
			end
			return cfg or ""
		end

		local function finalize_run()
			local failure_count = #aggregate.errors
			local failed_lookup = {}
			local failed_names = {}
			for _, err in ipairs(aggregate.errors) do
				local name = err.plugin or err.repo or "unknown"
				if not failed_lookup[name] then
					failed_lookup[name] = true
					table.insert(failed_names, name)
				end
			end

			if failure_count > 0 then
				-- Show failed plugins and allow retry
				ui.show_report(aggregate.errors, aggregate.success, aggregate.total, {
					ui = config.opts.ui,
					failed_plugins = failed_names,
					on_retry = function()
						-- Retry failed plugins
						local retry_targets = {}
						local seen = {}
						for _, err in ipairs(aggregate.errors) do
							local repo = err.repo
							if repo and not seen[repo] then
								table.insert(retry_targets, repo)
								seen[repo] = true
							end
						end
						if #retry_targets > 0 then
							start_update_flow(retry_targets)
						end
					end,
				})
			else
				ui.close({ message = "Upgrade Success", level = vim.log.levels.INFO })
			end
		end

		local progress_win = ui.open({
			header = config.opts.ui.header,
			icon = config.opts.ui.icons.check,
			plugins = plugin_names(targets),
			ui = config.opts.ui,
		})
		ensure_close(progress_win.buf)

		-- 初始化进度显示为 0
		vim.schedule(function()
			ui.update_progress(progress_win, nil, 0, #targets, config.opts.ui)
		end)

		local function run_checks(queue, callback)
			local total = #queue
			local completed = 0
			local errors = {}
			local pending_update = {}

			-- 并发执行器：最多同时执行10个任务
			local MAX_CONCURRENT = 10
			local pending_queue = {}
			local running_count = 0

			-- 初始化待执行队列
			for i = 1, #queue do
				table.insert(pending_queue, i)
			end

			local function start_next_check()
				if is_update_aborted then
					return
				end

				-- 如果队列为空且没有正在运行的任务，完成
				if #pending_queue == 0 and running_count == 0 then
					aggregate.checks = aggregate.checks + total
					aggregate.check_success = aggregate.check_success + math.max(0, total - #errors)
					callback(pending_update, errors)
					return
				end

				-- 如果正在运行的任务达到上限或队列为空，等待
				if running_count >= MAX_CONCURRENT or #pending_queue == 0 then
					return
				end

				-- 从队列中取出一个任务
				local queue_index = table.remove(pending_queue, 1)
				local repo = queue[queue_index]
				local plugin_name = string_utils.get_plugin_name(repo)

				running_count = running_count + 1
				vim.schedule(function()
					ui.update_progress(
						progress_win,
						{ plugin = plugin_name, status = "active" },
						completed,
						total,
						config.opts.ui
					)
				end)

				M.check_plugin(repo, config.opts.package_path, repo_to_config[repo], function(ok, result)
					running_count = running_count - 1
					completed = completed + 1

					if ok and result == "need_update" then
						table.insert(pending_update, repo)
					elseif not ok then
						table.insert(errors, { plugin = plugin_name, error = result, repo = repo })
						error_ui.save_error(plugin_name, result or "Check failed")
					end

					-- 立即更新进度条
					vim.schedule(function()
						ui.update_progress(
							progress_win,
							{ plugin = plugin_name, status = ok and "done" or "failed" },
							completed,
							total,
							config.opts.ui
						)
					end)

					-- 尝试启动下一个任务
					start_next_check()
				end)
			end

			-- 启动初始任务（最多5个）
			for i = 1, math.min(MAX_CONCURRENT, #pending_queue) do
				start_next_check()
			end
		end

		local function run_updates(queue, check_failures, attempt_id, aggregate_stats, on_complete)
			if is_update_aborted then
				return
			end

			local update_errors = {}
			local update_win = ui.open({
				header = config.opts.ui.header,
				icon = config.opts.ui.icons.update,
				plugins = plugin_names(queue),
				ui = config.opts.ui,
			})
			ensure_close(update_win.buf)

			local total = #queue
			local completed = 0
			local success_count = 0

			-- 初始化进度显示为 0
			vim.schedule(function()
				ui.update_progress(update_win, nil, 0, total, config.opts.ui)
			end)

			local function finalize_updates()
				if is_update_aborted then
					return
				end

				aggregate_stats.success = aggregate_stats.success + success_count
				aggregate_stats.total = aggregate_stats.total + total
				vim.list_extend(aggregate_stats.errors, update_errors)

				if check_failures and #check_failures > 0 then
					if attempt_id < 2 then
						local retry_targets = extract_retry_targets(check_failures)
						if #retry_targets > 0 then
							start_update_flow(retry_targets, attempt_id + 1, aggregate_stats)
							return
						end
					else
						vim.list_extend(aggregate_stats.errors, check_failures)
					end
				end

				on_complete()
			end

			-- 并发执行器：最多同时执行10个任务
			local MAX_CONCURRENT = 10
			local pending_queue = {}
			local running_count = 0

			-- 初始化待执行队列
			for i = 1, #queue do
				table.insert(pending_queue, i)
			end

			local function start_next_update()
				if is_update_aborted then
					return
				end

				-- 如果队列为空且没有正在运行的任务，完成
				if #pending_queue == 0 and running_count == 0 then
					finalize_updates()
					return
				end

				-- 如果正在运行的任务达到上限或队列为空，等待
				if running_count >= MAX_CONCURRENT or #pending_queue == 0 then
					return
				end

				-- 从队列中取出一个任务
				local queue_index = table.remove(pending_queue, 1)
				local repo = queue[queue_index]
				local plugin_name = string_utils.get_plugin_name(repo)
				local is_main_plugin = main_plugin_repos[repo] == true

				running_count = running_count + 1
				vim.schedule(function()
					ui.update_progress(
						update_win,
						{ plugin = plugin_name, status = "active" },
						completed,
						total,
						config.opts.ui
					)
				end)

				M.update_plugin(repo, config.opts.package_path, repo_to_config[repo], is_main_plugin, config, function(ok, err)
					running_count = running_count - 1
					completed = completed + 1

					if ok then
						success_count = success_count + 1
					else
						table.insert(update_errors, { plugin = plugin_name, error = err, repo = repo })
						error_ui.save_error(plugin_name, err or "Update failed")
					end

					-- 立即更新进度条
					vim.schedule(function()
						ui.update_progress(
							update_win,
							{ plugin = plugin_name, status = ok and "done" or "failed" },
							completed,
							total,
							config.opts.ui
						)
					end)

					-- 尝试启动下一个任务
					start_next_update()
				end)
			end

			-- 启动初始任务（最多5个）
			for i = 1, math.min(MAX_CONCURRENT, #pending_queue) do
				start_next_update()
			end
		end

		run_checks(targets, function(pending_update, check_errors)
			if is_update_aborted then
				return
			end

			local function handle_completion()
				if #check_errors > 0 then
					if attempt < 2 then
						local retry_targets = extract_retry_targets(check_errors)
						if #retry_targets > 0 then
							start_update_flow(retry_targets, attempt + 1, aggregate)
							return
						end
					else
						vim.list_extend(aggregate.errors, check_errors)
					end
				end
				finalize_run()
			end

			if #pending_update == 0 then
				handle_completion()
				return
			end

			run_updates(pending_update, check_errors, attempt, aggregate, handle_completion)
		end)
	end

	start_update_flow(plugins)
end

function M.check_plugin(plugin, package_path, plugin_config, callback)
	if is_update_aborted then
		return callback(false, "Stop")
	end

	local plugin_name = plugin:match("([^/]+)$")
	plugin_name = plugin_name:gsub("%.git$", "")
	local install_dir = git_utils.get_install_dir(plugin_name, "update", package_path)
	if vim.fn.isdirectory(install_dir) ~= 1 then
		return callback(false, "Directory is not found")
	end

	-- 从 YAML 获取当前记录的 branch / tag
	local yaml_branch, yaml_tag = yaml_state.get_branch_tag(package_path, plugin_name)
	-- 配置中的 tag / branch
	local config_tag = plugin_config and plugin_config.tag or nil
	local config_branch = plugin_config and plugin_config.branch or nil
	
	-- 1. 如果配置中的 tag 与 YAML 中的不同，需要更新
	if config_tag ~= yaml_tag then
		return callback(true, "need_update")
	end

	-- 2. tag 一致且存在 tag：认为已经是对应 tag，不再检查分支
	if yaml_tag or config_tag then
		return callback(true, "already_updated")
	end

	-- 3. 无 tag 模式下，检查 branch 是否变化（clone_conf.branch）
	local function normalize_branch(branch)
		if not branch or branch == "main" or branch == "master" then
			return nil
		end
		return branch
	end

	local norm_cfg_branch = normalize_branch(config_branch)
	local norm_yaml_branch = normalize_branch(yaml_branch)

	if norm_cfg_branch ~= norm_yaml_branch then
		-- 仅分支不同也需要执行更新流程（触发 update_plugin）
		return callback(true, "need_update")
	end

	local fetch_cmd = string.format("cd %s && git fetch --quiet", install_dir)
	local check_cmd = string.format("cd %s && git rev-list --count HEAD..@{upstream} 2>&1", install_dir)

	local job = git_utils.execute_command(fetch_cmd, function(fetch_ok, _)
		if not fetch_ok then
			return callback(false, "Warehouse synchronization failed")
		end

		git_utils.execute_command(check_cmd, function(_, result)
			local count = tonumber(result:match("%d+"))
			if count and count > 0 then
				callback(true, "need_update")
			else
				callback(true, "already_updated")
			end
		end)
	end)
	table.insert(jobs, job)
end

function M.update_plugin(plugin, package_path, plugin_config, is_main_plugin, config, callback)
	if is_update_aborted then
		return callback(false, "Stop")
	end

	local plugin_name = plugin:match("([^/]+)$")
	plugin_name = plugin_name:gsub("%.git$", "")
	local install_dir = git_utils.get_install_dir(plugin_name, "update", package_path)

	-- 获取配置中的 tag 和 branch（branch 源自 clone_conf.branch）
	local config_tag = plugin_config and plugin_config.tag or nil
	local config_branch = plugin_config and plugin_config.branch or nil

	-- 获取 YAML 中记录的 tag 和 branch
	local yaml_branch, yaml_tag = yaml_state.get_branch_tag(package_path, plugin_name)

	-- 如果目录不存在，直接按当前配置重新安装
	local function reinstall(reason)
		local install_module = require("synapse.core.install")
		local git_method = (config and config.method) or "https"
		install_module.install_plugin(plugin_config, git_method, package_path, is_main_plugin, function(ok, err)
			if not ok then
				return callback(false, (reason or "Reinstall failed") .. ": " .. (err or "Unknown error"))
			end
			callback(true, reason or "Reinstalled")
		end)
	end

	if vim.fn.isdirectory(install_dir) ~= 1 then
		return reinstall("Directory missing")
	end

	---------------------------------------------------------------------------
	-- 1. 先处理 tag 的变化（tag 优先级高于 branch）
	--    规则：
	--    - tag 改成新的值：在当前仓库上 fetch tags + checkout 新 tag
	--    - tag 从有到无：删除仓库，重新 clone（不带 tag 参数）
	---------------------------------------------------------------------------
	if config_tag ~= yaml_tag then
		if config_tag then
			local cmd = string.format(
				"cd %s && git fetch origin --tags && git checkout %s && git submodule update --init --recursive",
				vim.fn.shellescape(install_dir),
				config_tag
			)
			local job = git_utils.execute_command(cmd, function(ok, output)
				if not ok then
					return callback(false, output)
				end

				if is_main_plugin then
					-- 记录新的 tag，branch 在 tag 模式下一般可以忽略
					yaml_state.update_main_plugin(package_path, plugin_name, plugin_config, nil, config_tag, true)
				end

				callback(true, "Switched tag and updated")
			end)
			table.insert(jobs, job)
			return
		else
			-- tag 被移除：删除目录并用“无 tag 参数”的方式重新克隆
			local remove_cmd = string.format("rm -rf %s", vim.fn.shellescape(install_dir))
			return git_utils.execute_command(remove_cmd, function(ok, err)
				if not ok then
					return callback(false, "Failed to remove plugin for tag removal: " .. (err or "Unknown error"))
				end
				reinstall("Tag removed, re-cloned without tag")
			end)
		end
	end

	---------------------------------------------------------------------------
	-- 2. 再处理 branch 的变化（仅在没有 tag 模式下）
	--    规则：
	--    - clone_conf.branch 改成新的分支：当前仓库上 checkout 新分支 + pull
	--    - clone_conf.branch 从有到无：删除仓库，重新 clone（不带 -b，走默认分支）
	---------------------------------------------------------------------------
	local function normalize_branch(branch)
		if not branch or branch == "main" or branch == "master" then
			return nil
		end
		return branch
	end

	local norm_cfg_branch = normalize_branch(config_branch)
	local norm_yaml_branch = normalize_branch(yaml_branch)

	if norm_cfg_branch ~= norm_yaml_branch then
		if norm_cfg_branch then
			-- 从 A -> B：使用 git checkout -b/-B 基于远端分支创建/重置本地分支，再拉最新代码
			local cmd = string.format(
				"cd %s && git fetch origin && git checkout -B %s origin/%s && git pull origin %s && git submodule update --init --recursive",
				vim.fn.shellescape(install_dir),
				norm_cfg_branch,
				norm_cfg_branch,
				norm_cfg_branch
			)
			local job = git_utils.execute_command(cmd, function(ok, output)
				if not ok then
					return callback(false, output)
				end

				if is_main_plugin then
					yaml_state.update_main_plugin(package_path, plugin_name, plugin_config, norm_cfg_branch, nil, true)
				end

				callback(true, "Switched branch and updated")
			end)
			table.insert(jobs, job)
			return
		else
			-- branch 字段被移除：删除仓库，重新 clone（不带 -b）
			local remove_cmd = string.format("rm -rf %s", vim.fn.shellescape(install_dir))
			return git_utils.execute_command(remove_cmd, function(ok, err)
				if not ok then
					return callback(false, "Failed to remove plugin for branch removal: " .. (err or "Unknown error"))
				end
				reinstall("Branch removed, re-cloned with default branch")
			end)
		end
	end

	---------------------------------------------------------------------------
	-- 3. tag 和 branch 都没变：普通更新
	---------------------------------------------------------------------------
	local cmd
	if config_tag then
		-- 理论上不会到这里（上面已经处理 tag），保留以防逻辑调整
		cmd = string.format(
			"cd %s && git fetch origin --tags && git checkout %s && git submodule update --init --recursive",
			vim.fn.shellescape(install_dir),
			config_tag
		)
	else
		local branch = norm_cfg_branch or norm_yaml_branch
		if branch then
			cmd = string.format(
				"cd %s && git fetch origin && git checkout -B %s origin/%s && git pull origin %s && git submodule update --init --recursive",
				vim.fn.shellescape(install_dir),
				branch,
				branch,
				branch
			)
		else
			cmd = string.format(
				"cd %s && git fetch origin && git pull origin && git submodule update --init --recursive",
				vim.fn.shellescape(install_dir)
			)
		end
	end

	local job = git_utils.execute_command(cmd, function(ok, output)
		if not ok then
			return callback(false, output)
		end

		local execute_cmds = plugin_config and plugin_config.execute or nil
		local function finalize_ok()
			if plugin_config and is_main_plugin then
				local actual_branch = norm_cfg_branch or norm_yaml_branch
				local actual_tag = config_tag or yaml_tag
				yaml_state.update_main_plugin(package_path, plugin_name, plugin_config, actual_branch, actual_tag, true)
			end
			callback(true, "Success")
		end

		-- 更新后执行 execute
		if execute_cmds and type(execute_cmds) == "table" and #execute_cmds > 0 then
			execute_commands(execute_cmds, install_dir, function(exec_success, exec_err)
				if not exec_success then
					return callback(false, exec_err)
				end
				finalize_ok()
			end)
		else
			finalize_ok()
		end
	end)
	table.insert(jobs, job)
end

return M
