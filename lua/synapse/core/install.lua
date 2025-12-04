local ui = require("synapse.ui")
local errorUi = require("synapse.ui.errorUi")
local gitUtils = require("synapse.utils.gitUtils")
local configLoader = require("synapse.utils.configLoader")
local stringUtils = require("synapse.utils.stringUtils")
local jsonState = require("synapse.utils.jsonState")

local M = {}

local installationActive = true
local jobs = {}

--- Execute commands sequentially in plugin directory
--- @param commands table Array of command strings
--- @param pluginDir string Plugin installation directory
--- @param callback function Callback function(success, err)
--- @return number|nil jobId Job ID for tracking
local function executeCommands(commands, pluginDir, callback)
	if not commands or #commands == 0 then
		return callback(true, nil)
	end

	local jobIds = {}

	local function runNext(index)
		if index > #commands then
			return callback(true, nil)
		end

		local cmd = commands[index]
		local fullCmd = string.format("cd %s && %s", vim.fn.shellescape(pluginDir), cmd)
		
		local jobId = gitUtils.executeCommand(fullCmd, function(success, err)
			if success then
				runNext(index + 1)
			else
				callback(false, string.format("Execute command failed: %s - %s", cmd, err))
			end
		end)
		if jobId then
			table.insert(jobIds, jobId)
		end
	end

	runNext(1)
	return jobIds[1] -- Return first jobId for tracking
end

--- Ensure synapse.json exists, create empty file if it doesn't
--- @param config table Configuration table
local function ensureJsonExists(config)
	jsonState.ensureJsonExists(config.opts.package_path)
end

--- Start plugin installation process
--- @param config table Configuration table
function M.start(config)
	installationActive = true
	jobs = {}
	-- Clear error cache at start
	errorUi.clearCache()

	-- Check and create synapse.json if it doesn't exist
	ensureJsonExists(config)

	-- Load configuration files from config_path (including import files)
	local configs = configLoader.loadConfigFiles(config.opts.config_path, config.imports)
	
	-- Add default plugin
	local defaultConfig = {
		repo = config.opts.default,
		-- Don't set branch by default, let git use default branch
		config = {},
	}
	table.insert(configs, 1, defaultConfig)

	local installDir = config.opts.package_path

	local existingPlugins = {}
	for _, path in ipairs(vim.split(vim.fn.glob(installDir .. "/*"), "\n")) do
		existingPlugins[vim.fn.fnamemodify(path, ":t")] = true
	end

	-- Collect all plugins to install (including dependencies)
	-- First build main plugin map (for checking if dependency is also a main plugin)
	local mainPluginMap = {}
	for _, pluginConfig in ipairs(configs) do
		if pluginConfig.repo then
			mainPluginMap[pluginConfig.repo] = pluginConfig
		end
	end
	
	-- Collect all plugins (main plugins + dependencies), using set for deduplication
	local allPlugins = {}
	local processedRepos = {} -- Set for deduplication
	
	-- First add all main plugins
	for _, pluginConfig in ipairs(configs) do
		if pluginConfig.repo then
			local repo = pluginConfig.repo
			if not processedRepos[repo] then
				allPlugins[repo] = pluginConfig
				processedRepos[repo] = true
			end
		end
	end
	
	-- Recursively collect all dependencies (deduplicated)
	local function collectDependencies(pluginConfig)
		if not pluginConfig.depend or type(pluginConfig.depend) ~= "table" then
			return
		end
		
		for _, depItem in ipairs(pluginConfig.depend) do
			local depRepo, depOpt = configLoader.parseDependency(depItem)
			if depRepo and not processedRepos[depRepo] then
				-- If dependency is also a main plugin, use main plugin's config
				if mainPluginMap[depRepo] then
					allPlugins[depRepo] = mainPluginMap[depRepo]
					-- Recursively process dependencies of dependencies
					collectDependencies(mainPluginMap[depRepo])
				else
					-- If it's just a dependency, use default config (don't set branch, use git default)
					-- If there's opt config, save it
					local depConfig = {
						repo = depRepo,
						-- Don't set branch by default, let git use default branch
						config = {},
						depend = {},
					}
					if depOpt then
						depConfig.opt = depOpt
					end
					allPlugins[depRepo] = depConfig
				end
				processedRepos[depRepo] = true
			end
		end
	end
	
	-- Collect dependencies for all main plugins
	for _, pluginConfig in ipairs(configs) do
		if pluginConfig.repo then
			collectDependencies(pluginConfig)
		end
	end
	
	-- Build main plugin set (by repo path)
	local mainPluginRepos = {}
	for _, pluginConfig in ipairs(configs) do
		if pluginConfig.repo then
			mainPluginRepos[pluginConfig.repo] = true
		end
	end
	
	-- Build dependency to main plugins mapping (for updating main plugin's json when installing dependency)
	local depToMainPlugins = {} -- depRepo -> {mainPluginRepo1, mainPluginRepo2, ...}
	for _, pluginConfig in ipairs(configs) do
		if pluginConfig.repo and pluginConfig.depend and type(pluginConfig.depend) == "table" then
			for _, depItem in ipairs(pluginConfig.depend) do
				local depRepo = configLoader.parseDependency(depItem)
				if depRepo then
					if not depToMainPlugins[depRepo] then
						depToMainPlugins[depRepo] = {}
					end
					-- Only record which main plugin it belongs to if dependency is not a main plugin
					if not mainPluginRepos[depRepo] then
						table.insert(depToMainPlugins[depRepo], pluginConfig.repo)
					end
				end
			end
		end
	end
	
	-- Convert to list and filter already installed plugins, ensure dependencies are installed before main plugins
	local pendingInstall = {}
	local dependencies = {}
	local mainPlugins = {}
	
	for repo, pluginConfig in pairs(allPlugins) do
		local pluginName = repo:match("([^/]+)$")
		pluginName = pluginName:gsub("%.git$", "")
		if not existingPlugins[pluginName] and pluginName ~= "synapse" and pluginName ~= "synapse.nvim" then
			-- If it's a main plugin, add to main plugins list
			if mainPluginRepos[repo] then
				table.insert(mainPlugins, pluginConfig)
			else
				-- If it's a dependency, add to dependencies list
				table.insert(dependencies, pluginConfig)
			end
		end
	end
	
	-- Add dependencies first, then main plugins, to ensure dependencies are installed first
	for _, dep in ipairs(dependencies) do
		table.insert(pendingInstall, dep)
	end
	for _, main in ipairs(mainPlugins) do
		table.insert(pendingInstall, main)
	end

	if #pendingInstall == 0 then
		ui.log_message("All plugins are already installed.")
		return
	end

	local function runInstallQueue(queue)
		if not queue or #queue == 0 then
			return
		end

		installationActive = true
		jobs = {}

		local pluginNames = {}
		for _, cfg in ipairs(queue) do
			-- UI directly displays full repo name (no longer split by slash)
			table.insert(pluginNames, cfg.repo)
		end

		local progressWin = ui.open({
			header = config.opts.ui.header,
			icon = config.opts.ui.icons.download,
			plugins = pluginNames,
			ui = config.opts.ui,
		})

		vim.api.nvim_create_autocmd("WinClosed", {
			buffer = progressWin.buf,
			callback = function()
				installationActive = false
				for _, job in ipairs(jobs) do
					if job then
						vim.fn.jobstop(job)
					end
				end
			end,
		})

		local total = #queue
		local errors = {}
		local failedList = {}
		local installedCount = 0
		local completed = 0

		-- Initialize progress display to 0
		vim.schedule(function()
			ui.update_progress(progressWin, nil, 0, total, config.opts.ui)
		end)

		local function finalize()
			if not installationActive then
				return
			end

			if #errors > 0 then
				-- Show failed plugins and allow retry
				ui.show_report(errors, installedCount, total, {
					ui = config.opts.ui,
					failed_plugins = failedList,
					on_retry = function()
						-- Retry failed plugins
						local retryQueue = {}
						for _, err in ipairs(errors) do
							for _, cfg in ipairs(queue) do
								-- err.plugin is now full repo name, directly compare repo field
								if cfg.repo == err.plugin then
									table.insert(retryQueue, cfg)
									break
								end
							end
						end
						if #retryQueue > 0 then
							-- Retry with the same mainPluginRepos context
							runInstallQueue(retryQueue)
						end
					end,
				})
			else
				ui.close({ message = "Download Success", level = vim.log.levels.INFO })
			end
		end

		-- Concurrent executor: execute up to 10 tasks simultaneously
		local MAX_CONCURRENT = 10
		local pendingQueue = {}
		local runningCount = 0

		-- Initialize pending queue
		for i = 1, #queue do
			table.insert(pendingQueue, i)
		end

		local function startNextTask()
			if not installationActive then
				return
			end

			-- If queue is empty and no tasks are running, finish
			if #pendingQueue == 0 and runningCount == 0 then
				finalize()
				return
			end

			-- If running tasks reach limit or queue is empty, wait
			if runningCount >= MAX_CONCURRENT or #pendingQueue == 0 then
				return
			end

			-- Take a task from queue
			local queueIndex = table.remove(pendingQueue, 1)
			local pluginConfig = queue[queueIndex]
			local displayName = pluginConfig.repo
			local isMainPlugin = mainPluginRepos[pluginConfig.repo] == true

			runningCount = runningCount + 1
			vim.schedule(function()
				ui.update_progress(progressWin, { plugin = displayName, status = "active" }, completed, total, config.opts.ui)
			end)

			-- Get list of main plugins that this dependency belongs to
			local parentMainPlugins = nil
			if not isMainPlugin then
				parentMainPlugins = depToMainPlugins[pluginConfig.repo] or {}
			end
			
			local jobId = M.installPlugin(pluginConfig, config.method, config.opts.package_path, isMainPlugin, parentMainPlugins, function(success, err)
				runningCount = runningCount - 1
				completed = completed + 1

				if success then
					installedCount = installedCount + 1
				else
					-- Use full repo name in both error and UI
					table.insert(errors, { plugin = displayName, error = err })
					table.insert(failedList, displayName)
					errorUi.saveError(displayName, err or "Installation failed")
				end

				-- Immediately update progress bar and start next task
				vim.schedule(function()
					ui.update_progress(
						progressWin,
						{ plugin = displayName, status = success and "done" or "failed" },
						completed,
						total,
						config.opts.ui
					)
					-- Try to start next task (in schedule to ensure immediate execution)
					startNextTask()
				end)
			end)
			if jobId then
				table.insert(jobs, jobId)
			end
		end

		-- Start initial tasks (up to MAX_CONCURRENT)
		for i = 1, math.min(MAX_CONCURRENT, #pendingQueue) do
			startNextTask()
		end
	end

	runInstallQueue(pendingInstall)
end

--- Install a single plugin
--- @param pluginConfig table Plugin configuration
--- @param gitConfig string Git method ("ssh" or "https")
--- @param packagePath string Base package installation path
--- @param isMainPlugin boolean Whether this is a main plugin
--- @param parentMainPlugins table|nil List of main plugin repos that depend on this plugin
--- @param callback function Callback function(success, err)
--- @return number|nil jobId Job ID for tracking
function M.installPlugin(pluginConfig, gitConfig, packagePath, isMainPlugin, parentMainPlugins, callback)
	if not installationActive then
		return
	end

	local repo = pluginConfig.repo
	local pluginName = stringUtils.getPluginName(repo)
	local targetDir = gitUtils.getInstallDir(pluginName, "start", packagePath)
	
	-- Determine branch and tag: if plugin already exists, try to get from synapse.json first
	-- But prioritize config tag if it exists
	local branch = pluginConfig.branch  -- Don't default to "main", use nil if not specified
	local tag = pluginConfig.tag  -- Always prioritize config tag
	if vim.fn.isdirectory(targetDir) == 1 then
		-- Plugin already exists, try to get branch and tag from synapse.json
		local jsonBranch, jsonTag = jsonState.getBranchTag(packagePath, pluginName)
		-- Only use jsonBranch if it's not "main" or "master" (these shouldn't be used)
		if not branch and jsonBranch and jsonBranch ~= "main" and jsonBranch ~= "master" then
			branch = jsonBranch
		end
		-- Only use JSON tag if config doesn't have one
		if not tag and jsonTag then
			tag = jsonTag
		end
	else
		-- New plugin, use branch and tag from config (don't default to "main")
		branch = pluginConfig.branch
		tag = pluginConfig.tag
	end
	
	local repoUrl = gitUtils.getRepoUrl(repo, gitConfig)

	local command
	if vim.fn.isdirectory(targetDir) == 1 then
		-- If directory exists, update to specified branch or tag
		if tag then
			-- If there's a tag, checkout to that tag
			command = string.format("cd %s && git fetch origin --tags && git checkout %s", 
				vim.fn.shellescape(targetDir), tag)
		elseif branch then
			-- If there's a branch, update to specified branch
			command = string.format("cd %s && git fetch origin && git checkout %s && git pull origin %s", 
				vim.fn.shellescape(targetDir), branch, branch)
		else
			-- No branch and tag, just pull
			command = string.format("cd %s && git fetch origin && git pull origin", 
				vim.fn.shellescape(targetDir))
		end
	else
		-- Clone repository
		if tag then
			-- If there's a tag, clone then checkout to that tag
			command = string.format("git clone %s %s && cd %s && git checkout %s", 
				repoUrl, vim.fn.shellescape(targetDir), vim.fn.shellescape(targetDir), tag)
		elseif branch then
			-- If there's a branch, clone specified branch
			command = string.format("git clone --depth 1 -b %s %s %s", branch, repoUrl, vim.fn.shellescape(targetDir))
		else
			-- No branch and tag, clone default branch
			command = string.format("git clone --depth 1 %s %s", repoUrl, vim.fn.shellescape(targetDir))
		end
	end

	local jobId = gitUtils.executeCommand(command, function(success, err)
		if not success then
			return callback(false, err)
		end

		-- Execute post-install commands if specified
		if pluginConfig.execute and #pluginConfig.execute > 0 then
			executeCommands(pluginConfig.execute, targetDir, function(execSuccess, execErr)
				if not execSuccess then
					return callback(false, execErr)
				end

				-- Update synapse.json on successful installation
				if isMainPlugin then
					-- Main plugin: directly update
					jsonState.updateMainPlugin(packagePath, pluginName, pluginConfig, branch, tag, true)
				elseif parentMainPlugins and #parentMainPlugins > 0 then
					-- Dependency: update depend field of all main plugins that include it
					for _, mainRepo in ipairs(parentMainPlugins) do
						local mainPluginName = mainRepo:match("([^/]+)$")
						mainPluginName = mainPluginName:gsub("%.git$", "")
						jsonState.addDependencyToMainPlugin(packagePath, mainPluginName, pluginConfig.repo)
					end
				end
				callback(true, nil)
			end)
		else
			-- Update synapse.json on successful installation
			if isMainPlugin then
				-- Main plugin: directly update
				jsonState.updateMainPlugin(packagePath, pluginName, pluginConfig, branch, tag, true)
			elseif parentMainPlugins and #parentMainPlugins > 0 then
				-- Dependency: update depend field of all main plugins that include it
				for _, mainRepo in ipairs(parentMainPlugins) do
					local mainPluginName = mainRepo:match("([^/]+)$")
					mainPluginName = mainPluginName:gsub("%.git$", "")
					jsonState.addDependencyToMainPlugin(packagePath, mainPluginName, pluginConfig.repo)
				end
			end
			callback(true, nil)
		end
	end)
	return jobId
end

return M
