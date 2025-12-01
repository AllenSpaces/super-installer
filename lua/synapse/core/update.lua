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
			-- UI 中直接显示完整 repo 名称
			table.insert(names, repo)
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

		-- 在同一个窗口里执行：检查 → 如需更新则立即更新，最多同时执行 10 个插件任务
		local function run_checks(queue)
			local total = #queue
			local completed = 0
			local errors = {}
			local success_count = 0

			local function done_all()
				aggregate.checks = aggregate.checks + total
				aggregate.check_success = aggregate.check_success + success_count
				aggregate.total = aggregate.total + total
				vim.list_extend(aggregate.errors, errors)
				finalize_run()
			end

			local MAX_CONCURRENT = 10
			local pending_queue = {}
			local running_count = 0

			for i = 1, #queue do
				table.insert(pending_queue, i)
			end

			local function start_next_task()
				if is_update_aborted then
					return
				end

				-- 所有任务都完成
				if #pending_queue == 0 and running_count == 0 then
					done_all()
					return
				end

				-- 已达并发上限或没有待执行任务
				if running_count >= MAX_CONCURRENT or #pending_queue == 0 then
					return
				end

				-- 取出下一个任务
				local queue_index = table.remove(pending_queue, 1)
				local repo = queue[queue_index]
				-- 显示名称使用完整 repo
				local display_name = repo

				running_count = running_count + 1

				-- 标记为 active
				vim.schedule(function()
					ui.update_progress(
						progress_win,
						{ plugin = display_name, status = "active" },
						completed,
						total,
						config.opts.ui
					)
				end)

				-- 针对单个插件的任务：先 check 再（如需要）update
				M.check_plugin(repo, config.opts.package_path, repo_to_config[repo], function(ok, result)
					if not ok then
						-- 检查失败，直接记为错误
						table.insert(errors, { plugin = display_name, error = result, repo = repo })
						error_ui.save_error(display_name, result or "Check failed")
						completed = completed + 1
						running_count = running_count - 1
						vim.schedule(function()
							ui.update_progress(
								progress_win,
								{ plugin = display_name, status = "failed" },
								completed,
								total,
								config.opts.ui
							)
						end)
						-- 尝试启动下一个任务
						start_next_task()
						return
					end

					if result == "need_update" then
						-- 需要更新：立即更新当前插件
						local is_main_plugin = main_plugin_repos[repo] == true
						M.update_plugin(
							repo,
							config.opts.package_path,
							repo_to_config[repo],
							is_main_plugin,
							config,
							function(ok2, err2)
								if ok2 then
									success_count = success_count + 1
									completed = completed + 1
									vim.schedule(function()
										ui.update_progress(
											progress_win,
											{ plugin = display_name, status = "done" },
											completed,
											total,
											config.opts.ui
										)
									end)
								else
									table.insert(errors, { plugin = display_name, error = err2, repo = repo })
									error_ui.save_error(display_name, err2 or "Update failed")
									completed = completed + 1
									vim.schedule(function()
										ui.update_progress(
											progress_win,
											{ plugin = display_name, status = "failed" },
											completed,
											total,
											config.opts.ui
										)
									end)
								end
								running_count = running_count - 1
								start_next_task()
							end
						)
					else
						-- 已是最新：直接标记为 done
						success_count = success_count + 1
						completed = completed + 1
						running_count = running_count - 1
						vim.schedule(function()
							ui.update_progress(
								progress_win,
								{ plugin = display_name, status = "done" },
								completed,
								total,
								config.opts.ui
							)
						end)
						start_next_task()
					end
				end)
			end

			-- 启动初始任务（最多 MAX_CONCURRENT 个）
			for _ = 1, math.min(MAX_CONCURRENT, #pending_queue) do
				start_next_task()
			end
		end

		-- 只用一个窗口：检查 + 按需立即更新
		run_checks(targets)
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
			-- 从 A -> B：使用 git checkout -B 创建/重置本地分支，再拉最新代码
			-- 注意这里不再强依赖 origin/<branch> 已存在，避免类似
			-- "fatal: 'origin/xxx' is not a commit and a branch 'xxx' cannot be created from it"
			local cmd = string.format(
				"cd %s && git fetch origin && git checkout -B %s && git pull origin %s && git submodule update --init --recursive",
				vim.fn.shellescape(install_dir),
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
				"cd %s && git fetch origin && git checkout -B %s && git pull origin %s && git submodule update --init --recursive",
				vim.fn.shellescape(install_dir),
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
