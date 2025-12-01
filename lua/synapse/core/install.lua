local ui = require("synapse.ui")
local error_ui = require("synapse.ui.error")
local git_utils = require("synapse.utils.git")
local config_utils = require("synapse.utils.config")
local string_utils = require("synapse.utils.string")
local yaml_state = require("synapse.utils.yaml_state")

local M = {}

local installation_active = true

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

--- Ensure synapse.yaml exists, create empty file if it doesn't
--- @param config table
local function ensure_yaml_exists(config)
	yaml_state.ensure_yaml_exists(config.opts.package_path)
end

function M.start(config)
	installation_active = true
	-- Clear error cache at start
	error_ui.clear_cache()

	-- Check and create synapse.yaml if it doesn't exist
	ensure_yaml_exists(config)

	-- 从 config_path 读取配置文件
	local configs = config_utils.load_config_files(config.opts.config_path)
	
	-- 添加默认插件
	local default_config = {
		repo = config.opts.default,
		-- Don't set branch by default, let git use default branch
		config = {},
	}
	table.insert(configs, 1, default_config)

	local install_dir = config.opts.package_path

	local existing_plugins = {}
	for _, path in ipairs(vim.split(vim.fn.glob(install_dir .. "/*"), "\n")) do
		existing_plugins[vim.fn.fnamemodify(path, ":t")] = true
	end

	-- 收集所有需要安装的插件（包括依赖项）
	-- 首先建立主插件映射表（用于查找依赖项是否也是主插件）
	local main_plugin_map = {}
	for _, plugin_config in ipairs(configs) do
		if plugin_config.repo then
			main_plugin_map[plugin_config.repo] = plugin_config
		end
	end
	
	-- 收集所有插件（主插件 + 依赖项），使用 set 去重
	local all_plugins = {}
	local processed_repos = {} -- 用于去重的集合
	
	-- 首先添加所有主插件
	for _, plugin_config in ipairs(configs) do
		if plugin_config.repo then
			local repo = plugin_config.repo
			if not processed_repos[repo] then
				all_plugins[repo] = plugin_config
				processed_repos[repo] = true
			end
		end
	end
	
	-- 递归收集所有依赖项（去重）
	local function collect_dependencies(plugin_config)
		if not plugin_config.depend or type(plugin_config.depend) ~= "table" then
			return
		end
		
		for _, dep_item in ipairs(plugin_config.depend) do
			local dep_repo, dep_opt = config_utils.parse_dependency(dep_item)
			if dep_repo and not processed_repos[dep_repo] then
				-- 如果依赖项本身也是主插件，使用主插件的配置
				if main_plugin_map[dep_repo] then
					all_plugins[dep_repo] = main_plugin_map[dep_repo]
					-- 递归处理依赖项的依赖项
					collect_dependencies(main_plugin_map[dep_repo])
				else
					-- 如果只是依赖项，使用默认配置（不设置 branch，使用 git 默认分支）
					-- 如果有 opt 配置，保存它
					local dep_config = {
						repo = dep_repo,
						-- Don't set branch by default, let git use default branch
						config = {},
						depend = {},
					}
					if dep_opt then
						dep_config.opt = dep_opt
					end
					all_plugins[dep_repo] = dep_config
				end
				processed_repos[dep_repo] = true
			end
		end
	end
	
	-- 为所有主插件收集依赖项
	for _, plugin_config in ipairs(configs) do
		if plugin_config.repo then
			collect_dependencies(plugin_config)
		end
	end
	
	-- 建立主插件集合（通过 repo 路径）
	local main_plugin_repos = {}
	for _, plugin_config in ipairs(configs) do
		if plugin_config.repo then
			main_plugin_repos[plugin_config.repo] = true
		end
	end
	
	-- 转换为列表并过滤已安装的插件，确保依赖项在主插件之前安装
	local pending_install = {}
	local dependencies = {}
	local main_plugins = {}
	
	for repo, plugin_config in pairs(all_plugins) do
		local plugin_name = repo:match("([^/]+)$")
		plugin_name = plugin_name:gsub("%.git$", "")
		if not existing_plugins[plugin_name] and plugin_name ~= "synapse" and plugin_name ~= "synapse.nvim" then
			-- 如果是主插件，添加到主插件列表
			if main_plugin_repos[repo] then
				table.insert(main_plugins, plugin_config)
			else
				-- 如果是依赖项，添加到依赖项列表
				table.insert(dependencies, plugin_config)
			end
		end
	end
	
	-- 先添加依赖项，再添加主插件，确保依赖项先安装
	for _, dep in ipairs(dependencies) do
		table.insert(pending_install, dep)
	end
	for _, main in ipairs(main_plugins) do
		table.insert(pending_install, main)
	end

	if #pending_install == 0 then
		ui.log_message("All plugins are already installed.")
		return
	end

	local function run_install_queue(queue)
		if not queue or #queue == 0 then
			return
		end

		installation_active = true

		local plugin_names = {}
		for _, cfg in ipairs(queue) do
			-- UI 中直接显示完整 repo 名称（不再根据斜杠分割）
			table.insert(plugin_names, cfg.repo)
		end

		local progress_win = ui.open({
			header = config.opts.ui.header,
			icon = config.opts.ui.icons.download,
			plugins = plugin_names,
			ui = config.opts.ui,
		})

		vim.api.nvim_create_autocmd("WinClosed", {
			buffer = progress_win.buf,
			callback = function()
				installation_active = false
			end,
		})

		local total = #queue
		local errors = {}
		local failed_list = {}
		local installed_count = 0
		local completed = 0

		-- 初始化进度显示为 0
		vim.schedule(function()
			ui.update_progress(progress_win, nil, 0, total, config.opts.ui)
		end)

		local function finalize()
			if not installation_active then
				return
			end

			if #errors > 0 then
				-- Show failed plugins and allow retry
				ui.show_report(errors, installed_count, total, {
					ui = config.opts.ui,
					failed_plugins = failed_list,
					on_retry = function()
						-- Retry failed plugins
						local retry_queue = {}
						for _, err in ipairs(errors) do
							for _, cfg in ipairs(queue) do
								-- 这里 err.plugin 现在是完整 repo 名称，直接比较 repo 字段
								if cfg.repo == err.plugin then
									table.insert(retry_queue, cfg)
									break
								end
							end
						end
						if #retry_queue > 0 then
							-- Retry with the same main_plugin_repos context
							run_install_queue(retry_queue)
						end
					end,
				})
			else
				ui.close({ message = "Download Success", level = vim.log.levels.INFO })
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

		local function start_next_task()
			if not installation_active then
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
			local plugin_config = queue[queue_index]
			local display_name = plugin_config.repo
			local is_main_plugin = main_plugin_repos[plugin_config.repo] == true

			running_count = running_count + 1
			vim.schedule(function()
				ui.update_progress(progress_win, { plugin = display_name, status = "active" }, completed, total, config.opts.ui)
			end)

			M.install_plugin(plugin_config, config.method, config.opts.package_path, is_main_plugin, function(success, err)
				running_count = running_count - 1
				completed = completed + 1

				if success then
					installed_count = installed_count + 1
				else
					-- 错误和 UI 中都使用完整 repo 名称
					table.insert(errors, { plugin = display_name, error = err })
					table.insert(failed_list, display_name)
					error_ui.save_error(display_name, err or "Installation failed")
				end

				-- 立即更新进度条
				vim.schedule(function()
					ui.update_progress(
						progress_win,
						{ plugin = display_name, status = success and "done" or "failed" },
						completed,
						total,
						config.opts.ui
					)
				end)

				-- 尝试启动下一个任务
				start_next_task()
			end)
		end

		-- 启动初始任务（最多5个）
		for i = 1, math.min(MAX_CONCURRENT, #pending_queue) do
			start_next_task()
		end
	end

	run_install_queue(pending_install)
end

-- YAML metadata helpers are centralized in synapse.utils.yaml_state

function M.install_plugin(plugin_config, git_config, package_path, is_main_plugin, callback)
	if not installation_active then
		return
	end

	local repo = plugin_config.repo
	local plugin_name = string_utils.get_plugin_name(repo)
	local target_dir = git_utils.get_install_dir(plugin_name, "start", package_path)
	
	-- Determine branch and tag: if plugin already exists, try to get from synapse.yaml first
	-- But prioritize config tag if it exists
	local branch = plugin_config.branch  -- Don't default to "main", use nil if not specified
	local tag = plugin_config.tag  -- Always prioritize config tag
	if vim.fn.isdirectory(target_dir) == 1 then
		-- Plugin already exists, try to get branch and tag from synapse.yaml
		local yaml_branch, yaml_tag = yaml_state.get_branch_tag(package_path, plugin_name)
		-- Only use yaml_branch if it's not "main" or "master" (these shouldn't be used)
		if not branch and yaml_branch and yaml_branch ~= "main" and yaml_branch ~= "master" then
			branch = yaml_branch
		end
		-- Only use YAML tag if config doesn't have one
		if not tag and yaml_tag then
			tag = yaml_tag
		end
	else
		-- New plugin, use branch and tag from config (don't default to "main")
		branch = plugin_config.branch
		tag = plugin_config.tag
	end
	
	local repo_url = git_utils.get_repo_url(repo, git_config)

	local command
	if vim.fn.isdirectory(target_dir) == 1 then
		-- 如果目录已存在，更新到指定分支或 tag
		if tag then
			-- 如果有 tag，checkout 到该 tag
			command = string.format("cd %s && git fetch origin --tags && git checkout %s", 
				vim.fn.shellescape(target_dir), tag)
		elseif branch then
			-- 如果有 branch，更新到指定分支
		command = string.format("cd %s && git fetch origin && git checkout %s && git pull origin %s", 
				vim.fn.shellescape(target_dir), branch, branch)
	else
			-- 没有 branch 和 tag，直接 pull
			command = string.format("cd %s && git fetch origin && git pull origin", 
				vim.fn.shellescape(target_dir))
		end
	else
		-- 克隆仓库
		if tag then
			-- 如果有 tag，克隆后 checkout 到该 tag
			command = string.format("git clone %s %s && cd %s && git checkout %s", 
				repo_url, vim.fn.shellescape(target_dir), vim.fn.shellescape(target_dir), tag)
		elseif branch then
			-- 如果有 branch，克隆指定分支
			command = string.format("git clone --depth 1 -b %s %s %s", branch, repo_url, vim.fn.shellescape(target_dir))
		else
			-- 没有 branch 和 tag，克隆默认分支
			command = string.format("git clone --depth 1 %s %s", repo_url, vim.fn.shellescape(target_dir))
		end
	end

	git_utils.execute_command(command, function(success, err)
		if not success then
			return callback(false, err)
		end

		-- Execute post-install commands if specified
		if plugin_config.execute and #plugin_config.execute > 0 then
			execute_commands(plugin_config.execute, target_dir, function(exec_success, exec_err)
				if not exec_success then
					return callback(false, exec_err)
				end

				-- Update synapse.yaml on successful installation (only for main plugins)
				-- Pass the actual branch and tag used for installation
				yaml_state.update_main_plugin(package_path, plugin_name, plugin_config, branch, tag, is_main_plugin)
				callback(true, nil)
			end)
		else
			-- Update synapse.yaml on successful installation (only for main plugins)
			-- Pass the actual branch and tag used for installation
			yaml_state.update_main_plugin(package_path, plugin_name, plugin_config, branch, tag, is_main_plugin)
			callback(true, nil)
		end
	end)
end

return M
