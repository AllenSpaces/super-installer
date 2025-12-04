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

	-- Check existing plugins with new directory structure
	-- Main plugins: package_path/plugin-name/plugin-name/
	-- Dependencies: package_path/main-plugin-name/depend/dependency-name/
	-- Special: synapse plugin is directly in package_path/synapse.nvim/
	local existingPlugins = {}
	
	-- Check synapse plugin (special location)
	local synapsePath = string.format("%s/synapse.nvim", installDir)
	if vim.fn.isdirectory(synapsePath) == 1 then
		existingPlugins["synapse.nvim"] = true
		existingPlugins["synapse"] = true
	end
	
	for _, path in ipairs(vim.split(vim.fn.glob(installDir .. "/*"), "\n")) do
		if vim.fn.isdirectory(path) == 1 then
			local pluginName = vim.fn.fnamemodify(path, ":t")
			-- Skip synapse.nvim as it's already checked above
			if pluginName ~= "synapse.nvim" and pluginName ~= "synapse" then
				-- Check if this is a main plugin directory (has plugin-name/plugin-name/ structure)
				local mainPluginPath = string.format("%s/%s/%s", installDir, pluginName, pluginName)
				if vim.fn.isdirectory(mainPluginPath) == 1 then
					existingPlugins[pluginName] = true
				end
			end
		end
	end
	
	-- Also check dependencies in depend folders
	for _, path in ipairs(vim.split(vim.fn.glob(installDir .. "/*/depend/*"), "\n")) do
		if vim.fn.isdirectory(path) == 1 then
			local depName = vim.fn.fnamemodify(path, ":t")
			existingPlugins[depName] = true
		end
	end
	
	-- Check shared dependencies in public folder
	for _, path in ipairs(vim.split(vim.fn.glob(installDir .. "/public/*"), "\n")) do
		if vim.fn.isdirectory(path) == 1 then
			local depName = vim.fn.fnamemodify(path, ":t")
			existingPlugins[depName] = true
		end
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
	
	-- Migrate shared dependencies before checking what needs to be installed
	-- If a dependency is used by multiple plugins and already exists in a single plugin's depend folder,
	-- move it to public folder
	for depRepo, mainPluginReposList in pairs(depToMainPlugins) do
		if #mainPluginReposList > 1 then
			-- This is a shared dependency
			local depName = stringUtils.getPluginName(depRepo)
			local publicPath = string.format("%s/public/%s", installDir, depName)
			local publicExists = vim.fn.isdirectory(publicPath) == 1
			
			if not publicExists then
				-- Check if it exists in any single plugin's depend folder
				for _, mainRepo in ipairs(mainPluginReposList) do
					local mainPluginName = stringUtils.getPluginName(mainRepo)
					local oldPath = string.format("%s/%s/depend/%s", installDir, mainPluginName, depName)
					if vim.fn.isdirectory(oldPath) == 1 then
						-- Need to migrate: create public directory and move
						local publicDir = string.format("%s/public", installDir)
						if vim.fn.isdirectory(publicDir) ~= 1 then
							vim.fn.mkdir(publicDir, "p")
						end
						-- Move the dependency
						local moveCmd = string.format("mv %s %s", vim.fn.shellescape(oldPath), vim.fn.shellescape(publicPath))
						vim.fn.system(moveCmd)
						break -- Only move once
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
		
		-- Skip synapse plugin itself
		if pluginName == "synapse" or pluginName == "synapse.nvim" then
			goto continue
		end
		
		-- Check if plugin is already installed
		local isInstalled = false
		if pluginName == "synapse" or pluginName == "synapse.nvim" then
			-- Special handling for synapse: check package_path/synapse.nvim/
			local synapsePath = string.format("%s/synapse.nvim", installDir)
			isInstalled = vim.fn.isdirectory(synapsePath) == 1
		elseif mainPluginRepos[repo] then
			-- For main plugin, check if package_path/plugin-name/plugin-name/ exists
			local mainPluginPath = string.format("%s/%s/%s", installDir, pluginName, pluginName)
			isInstalled = vim.fn.isdirectory(mainPluginPath) == 1
		else
			-- For dependency, check if it exists in any depend folder or public folder
			isInstalled = existingPlugins[pluginName] == true
			-- Also check public folder explicitly
			if not isInstalled then
				local publicPath = string.format("%s/public/%s", installDir, pluginName)
				isInstalled = vim.fn.isdirectory(publicPath) == 1
			end
		end
		
		if not isInstalled then
			-- If it's a main plugin, add to main plugins list
			if mainPluginRepos[repo] then
				table.insert(mainPlugins, pluginConfig)
			else
				-- If it's a dependency, add to dependencies list
				table.insert(dependencies, pluginConfig)
			end
		end
		::continue::
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
			local isSharedDependency = false
			if not isMainPlugin then
				parentMainPlugins = depToMainPlugins[pluginConfig.repo] or {}
				-- Check if this dependency is shared (used by multiple main plugins)
				isSharedDependency = #parentMainPlugins > 1
			end
			
			local jobId = M.installPlugin(pluginConfig, config.method, config.opts.package_path, isMainPlugin, parentMainPlugins, isSharedDependency, function(success, err)
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
function M.installPlugin(pluginConfig, gitConfig, packagePath, isMainPlugin, parentMainPlugins, isSharedDependency, callback)
	if not installationActive then
		return
	end

	local repo = pluginConfig.repo
	local pluginName = stringUtils.getPluginName(repo)
	
	-- Determine main plugin name for dependencies
	local mainPluginName = nil
	if not isMainPlugin and parentMainPlugins and #parentMainPlugins > 0 then
		-- Use the first parent main plugin name
		mainPluginName = stringUtils.getPluginName(parentMainPlugins[1])
	end
	
	-- Check if this dependency is shared (used by multiple main plugins)
	-- Note: Migration is already handled before installation check
	local actualIsShared = isSharedDependency or false
	if not isMainPlugin and parentMainPlugins and #parentMainPlugins > 1 then
		actualIsShared = true
	end
	
	local targetDir = gitUtils.getInstallDir(pluginName, "start", packagePath, isMainPlugin, mainPluginName, actualIsShared)
	
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

	-- Ensure parent directories exist for new directory structure
	-- Special handling for synapse plugin: it's directly in package_path/synapse.nvim/
	-- Note: Migration of shared dependencies is handled before installation check
	if pluginName == "synapse" or pluginName == "synapse.nvim" then
		-- Synapse plugin doesn't need parent directory creation, it's directly in package_path
	elseif vim.fn.isdirectory(targetDir) ~= 1 then
		if isMainPlugin then
			-- For main plugin: create package_path/plugin-name/ directory
			local parentDir = string.format("%s/%s", packagePath, pluginName)
			if vim.fn.isdirectory(parentDir) ~= 1 then
				vim.fn.mkdir(parentDir, "p")
			end
		else
			if actualIsShared then
				-- For shared dependency: create package_path/public/ directory
				local publicDir = string.format("%s/public", packagePath)
				if vim.fn.isdirectory(publicDir) ~= 1 then
					vim.fn.mkdir(publicDir, "p")
				end
			else
				-- For single dependency: create package_path/main-plugin-name/depend/ directory
				if mainPluginName then
					local dependDir = string.format("%s/%s/depend", packagePath, mainPluginName)
					if vim.fn.isdirectory(dependDir) ~= 1 then
						vim.fn.mkdir(dependDir, "p")
					end
				end
			end
		end
	end

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
