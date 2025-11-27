local ui = require("synapse.model.ui")
local utils = require("synapse.model.utils")

local M = {}

local installation_active = true

function M.start(config)
	installation_active = true

	-- 从 config_path 读取配置文件
	local configs = utils.load_config_files(config.opts.config_path)
	
	-- 添加默认插件
	local default_config = {
		repo = config.opts.default,
		branch = "main",
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
					-- 如果只是依赖项，使用默认配置
					all_plugins[dep_repo] = {
						repo = dep_repo,
						branch = "main",
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
	
	-- 转换为列表并过滤已安装的插件
	local pending_install = {}
	for repo, plugin_config in pairs(all_plugins) do
		local plugin_name = repo:match("([^/]+)$")
		plugin_name = plugin_name:gsub("%.git$", "")
		if not existing_plugins[plugin_name] and plugin_name ~= "synapse" and plugin_name ~= "synapse.nvim" then
			table.insert(pending_install, plugin_config)
		end
	end

	if #pending_install == 0 then
		ui.log_message("All plugins are already installed.")
		return
	end

	local total = #pending_install
	local errors = {}
	local installed_count = 0
	local completed = 0
	local progress_win = ui.create_window(config.opts.ui.icons.download .. " Plugin Installation Progress", 68)

	vim.api.nvim_create_autocmd("WinClosed", {
		buffer = progress_win.buf,
		callback = function()
			installation_active = false
		end,
	})

	local function process_next(index)
		if not installation_active then
			return
		end

		if index > total then
			ui.update_progress(
				progress_win,
				config.opts.ui.icons.download .. " Finalizing installation...",
				total,
				total,
				config.opts.ui
			)
			vim.defer_fn(function()
				vim.api.nvim_win_close(progress_win.win_id, true)
				ui.show_report(errors, installed_count, total, "installation")
			end, 500)
			return
		end

		local plugin_config = pending_install[index]
		local plugin_name = plugin_config.repo:match("([^/]+)$")
		plugin_name = plugin_name:gsub("%.git$", "")
		ui.update_progress(progress_win, "Installing: " .. plugin_name, completed, total, config.opts.ui)

		M.install_plugin(plugin_config, config.method, config.opts.package_path, function(success, err)
			completed = completed + 1
			if success then
				installed_count = installed_count + 1
			else
				table.insert(errors, { plugin = plugin_name, error = err })
			end
			process_next(index + 1)
		end)
	end

	process_next(1)
end

function M.install_plugin(plugin_config, git_config, package_path, callback)
	if not installation_active then
		return
	end

	local repo = plugin_config.repo
	local branch = plugin_config.branch or "main"
	
	local repo_url = utils.get_repo_url(repo, git_config)
	local plugin_name = repo:match("([^/]+)$")
	plugin_name = plugin_name:gsub("%.git$", "")
	local target_dir = utils.get_install_dir(plugin_name, "start", package_path)

	local command
	if vim.fn.isdirectory(target_dir) == 1 then
		-- 如果目录已存在，更新到指定分支
		command = string.format("cd %s && git fetch origin && git checkout %s && git pull origin %s", 
			target_dir, branch, branch)
	else
		-- 克隆指定分支
		if branch == "main" or branch == "master" then
			command = string.format("git clone --depth 1 %s %s", repo_url, target_dir)
		else
			command = string.format("git clone --depth 1 -b %s %s %s", branch, repo_url, target_dir)
		end
	end

	utils.execute_command(command, callback)
end

return M
