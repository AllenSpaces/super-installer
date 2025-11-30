local ui = require("synapse.ui")
local error_ui = require("synapse.ui.error")
local git_utils = require("synapse.utils.git")
local config_utils = require("synapse.utils.config")
local string_utils = require("synapse.utils.string")
local yaml_utils = require("synapse.utils.yaml")

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
	local yaml_path = yaml_utils.get_yaml_path(config.opts.package_path)
	
	-- Check if synapse.yaml already exists
	if vim.fn.filereadable(yaml_path) == 1 then
		return
	end
	
	-- Create empty YAML file
	local yaml_data = { plugins = {} }
	yaml_utils.write(yaml_path, yaml_data)
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
		
		for _, dep_repo in ipairs(plugin_config.depend) do
			if not processed_repos[dep_repo] then
				-- 如果依赖项本身也是主插件，使用主插件的配置
				if main_plugin_map[dep_repo] then
					all_plugins[dep_repo] = main_plugin_map[dep_repo]
					-- 递归处理依赖项的依赖项
					collect_dependencies(main_plugin_map[dep_repo])
				else
					-- 如果只是依赖项，使用默认配置（不设置 branch，使用 git 默认分支）
					all_plugins[dep_repo] = {
						repo = dep_repo,
						-- Don't set branch by default, let git use default branch
						config = {},
						depend = {},
					}
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
			table.insert(plugin_names, string_utils.get_plugin_name(cfg.repo))
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
								local plugin_name = string_utils.get_plugin_name(cfg.repo)
								if plugin_name == err.plugin then
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

		local function process_next(index)
			if not installation_active then
				return
			end

			if index > total then
				finalize()
				return
			end

			local plugin_config = queue[index]
			local plugin_name = string_utils.get_plugin_name(plugin_config.repo)
			-- Check if this is a main plugin
			local is_main_plugin = main_plugin_repos[plugin_config.repo] == true

			ui.update_progress(progress_win, { plugin = plugin_name, status = "active" }, completed, total, config.opts.ui)

			M.install_plugin(plugin_config, config.method, config.opts.package_path, is_main_plugin, function(success, err)
				completed = completed + 1
				if success then
					installed_count = installed_count + 1
				else
					table.insert(errors, { plugin = plugin_name, error = err })
					table.insert(failed_list, plugin_name)
					-- Save error to cache (don't show window automatically)
					error_ui.save_error(plugin_name, err or "Installation failed")
				end

				ui.update_progress(
					progress_win,
					{ plugin = plugin_name, status = success and "done" or "failed" },
					completed,
					total,
					config.opts.ui
				)

				process_next(index + 1)
			end)
		end

		process_next(1)
	end

	run_install_queue(pending_install)
end

--- Get plugin branch and tag from synapse.yaml
--- @param package_path string
--- @param plugin_name string
--- @return string|nil branch
--- @return string|nil tag
local function get_branch_tag_from_yaml(package_path, plugin_name)
	local yaml_path = yaml_utils.get_yaml_path(package_path)
	local data, _ = yaml_utils.read(yaml_path)
	
	if data and data.plugins then
		for _, plugin in ipairs(data.plugins) do
			if plugin.name == plugin_name then
				return plugin.branch, plugin.tag
			end
		end
	end
	
	return nil, nil
end

--- Update synapse.yaml with plugin information (only for main plugins)
--- @param package_path string
--- @param plugin_name string
--- @param plugin_config table
--- @param actual_branch string|nil The actual branch used for installation
--- @param actual_tag string|nil The actual tag used for installation
--- @param is_main_plugin boolean Whether this is a main plugin
local function update_yaml(package_path, plugin_name, plugin_config, actual_branch, actual_tag, is_main_plugin)
	-- Only save main plugins, skip dependencies
	if not is_main_plugin then
		return
	end
	
	local yaml_path = yaml_utils.get_yaml_path(package_path)
	
	-- Read existing YAML or create new
	local data, err = yaml_utils.read(yaml_path)
	if not data then
		data = { plugins = {} }
	end
	
	-- Keep depend repos as full repo paths (e.g., "nvim-lua/plenary.nvim")
	local depend_repos = {}
	if plugin_config.depend and type(plugin_config.depend) == "table" then
		for _, dep_repo in ipairs(plugin_config.depend) do
			table.insert(depend_repos, dep_repo)
		end
	end
	
	-- Collect all repos that appear in any plugin's depend field
	local all_depend_repos = {}
	for _, plugin in ipairs(data.plugins) do
		if plugin.depend and type(plugin.depend) == "table" then
			for _, dep_repo in ipairs(plugin.depend) do
				all_depend_repos[dep_repo] = true
			end
		end
	end
	
	-- Also add current plugin's depend repos to the set
	for _, dep_repo in ipairs(depend_repos) do
		all_depend_repos[dep_repo] = true
	end
	
	-- Check if current plugin's repo is in any depend field
	local current_repo = plugin_config.repo
	local is_in_depend = all_depend_repos[current_repo] == true
	
	-- If this repo is in any depend field, don't save it as a main plugin
	if is_in_depend then
		return
	end
	
	-- Check if plugin already exists
	local found = false
	local found_index = nil
	for i, plugin in ipairs(data.plugins) do
		if plugin.name == plugin_name then
			found = true
			found_index = i
			break
		end
	end
	
	if found then
		-- Check if this plugin's repo is in any other plugin's depend field
		local is_in_other_depend = false
		for _, plugin in ipairs(data.plugins) do
			if plugin.name ~= plugin_name and plugin.depend and type(plugin.depend) == "table" then
				for _, dep_repo in ipairs(plugin.depend) do
					if dep_repo == current_repo then
						is_in_other_depend = true
						break
					end
				end
				if is_in_other_depend then
					break
				end
			end
		end
		
		-- If this plugin is in another plugin's depend, remove it from plugins list
		if is_in_other_depend then
			table.remove(data.plugins, found_index)
			-- Write back and return
			yaml_utils.write(yaml_path, data)
			return
		end
		
		-- Update existing entry
		-- Use actual_branch if provided, otherwise use plugin_config.branch
		local branch = actual_branch or plugin_config.branch
		if branch and branch ~= "main" and branch ~= "master" then
			data.plugins[found_index].branch = branch
		else
			-- Remove branch field if it's default
			data.plugins[found_index].branch = nil
		end
		-- Save tag if exists (use actual_tag if provided, otherwise use plugin_config.tag)
		local tag = actual_tag or plugin_config.tag
		if tag then
			data.plugins[found_index].tag = tag
		else
			data.plugins[found_index].tag = nil
		end
		data.plugins[found_index].repo = current_repo
		data.plugins[found_index].depend = depend_repos
	end
	
	-- Add new plugin if not found
	if not found then
		local plugin_entry = {
			name = plugin_name,
			repo = current_repo,
			depend = depend_repos,
		}
		-- Use actual_branch if provided, otherwise use plugin_config.branch
		local branch = actual_branch or plugin_config.branch
		if branch and branch ~= "main" and branch ~= "master" then
			plugin_entry.branch = branch
		end
		-- Save tag if exists (use actual_tag if provided, otherwise use plugin_config.tag)
		local tag = actual_tag or plugin_config.tag
		if tag then
			plugin_entry.tag = tag
		end
		table.insert(data.plugins, plugin_entry)
	end
	
	-- Write back to file
	yaml_utils.write(yaml_path, data)
end

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
		local yaml_branch, yaml_tag = get_branch_tag_from_yaml(package_path, plugin_name)
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
				update_yaml(package_path, plugin_name, plugin_config, branch, tag, is_main_plugin)
				callback(true, nil)
			end)
		else
			-- Update synapse.yaml on successful installation (only for main plugins)
			-- Pass the actual branch and tag used for installation
			update_yaml(package_path, plugin_name, plugin_config, branch, tag, is_main_plugin)
			callback(true, nil)
		end
	end)
end

return M
