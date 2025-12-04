local ui = require("synapse.ui")
local errorUi = require("synapse.ui.errorUi")
local gitUtils = require("synapse.utils.gitUtils")
local configLoader = require("synapse.utils.configLoader")
local stringUtils = require("synapse.utils.stringUtils")
local jsonState = require("synapse.utils.jsonState")

local M = {}

local isUpdateAborted = false
local updateWin = nil
local jobs = {}

--- Execute commands sequentially in plugin directory
--- @param commands table Array of command strings
--- @param pluginDir string Plugin installation directory
--- @param callback function Callback function(success, err)
local function executeCommands(commands, pluginDir, callback)
	if not commands or #commands == 0 then
		return callback(true, nil)
	end

	local function runNext(index)
		if index > #commands then
			return callback(true, nil)
		end

		local cmd = commands[index]
		local fullCmd = string.format("cd %s && %s", vim.fn.shellescape(pluginDir), cmd)
		
		gitUtils.executeCommand(fullCmd, function(success, err)
			if success then
				runNext(index + 1)
			else
				callback(false, string.format("Execute command failed: %s - %s", cmd, err))
			end
		end)
	end

	runNext(1)
end

--- Start plugin update process
--- @param config table Configuration table
function M.start(config)
	isUpdateAborted = false
	jobs = {}
	-- Clear error cache at start
	errorUi.clearCache()

	-- Load configuration files from config_path (including import files)
	local configs = configLoader.loadConfigFiles(config.opts.config_path, config.imports)
	
	-- Add default plugin
	local defaultConfig = {
		repo = config.opts.default,
		-- Don't set branch by default, let git use default branch
		config = {},
	}
	table.insert(configs, 1, defaultConfig)

	-- Build repo to pluginConfig mapping (for getting tag info, etc.)
	local repoToConfig = {}
	local mainPluginRepos = {} -- For determining if it's a main plugin
	for _, pluginConfig in ipairs(configs) do
		if pluginConfig.repo then
			repoToConfig[pluginConfig.repo] = pluginConfig
			mainPluginRepos[pluginConfig.repo] = true
		end
	end

	-- Migrate dependencies from public folder back to single plugin's depend folder if they're no longer shared
	-- This should happen before checking what needs to be updated
	local packagePath = config.opts.package_path
	local publicDir = string.format("%s/public", packagePath)
	if vim.fn.isdirectory(publicDir) == 1 then
		-- Build dependency to main plugins mapping for current configuration
		local currentDepToMainPlugins = {}
		for _, pluginConfig in ipairs(configs) do
			if pluginConfig.repo and pluginConfig.depend and type(pluginConfig.depend) == "table" then
				for _, depItem in ipairs(pluginConfig.depend) do
					local depRepo = configLoader.parseDependency(depItem)
					if depRepo then
						if not currentDepToMainPlugins[depRepo] then
							currentDepToMainPlugins[depRepo] = {}
						end
						if not mainPluginRepos[depRepo] then
							table.insert(currentDepToMainPlugins[depRepo], pluginConfig.repo)
						end
					end
				end
			end
		end
		
		-- Check all dependencies in public folder
		local publicDeps = vim.split(vim.fn.glob(publicDir .. "/*"), "\n")
		for _, depPath in ipairs(publicDeps) do
			if vim.fn.isdirectory(depPath) == 1 then
				local depName = vim.fn.fnamemodify(depPath, ":t")
				-- Find the dependency repo in currentDepToMainPlugins
				local depRepo = nil
				for repo, _ in pairs(currentDepToMainPlugins) do
					local repoName = repo:match("([^/]+)$")
					repoName = repoName:gsub("%.git$", "")
					if repoName == depName then
						depRepo = repo
						break
					end
				end
				
				-- If dependency is found and only used by one main plugin, move it back
				if depRepo and currentDepToMainPlugins[depRepo] and #currentDepToMainPlugins[depRepo] == 1 then
					local mainRepo = currentDepToMainPlugins[depRepo][1]
					local stringUtils = require("synapse.utils.stringUtils")
					local mainPluginName = stringUtils.getPluginName(mainRepo)
					local targetDir = string.format("%s/%s/depend/%s", packagePath, mainPluginName, depName)
					
					-- Create depend directory if it doesn't exist
					local dependDir = string.format("%s/%s/depend", packagePath, mainPluginName)
					if vim.fn.isdirectory(dependDir) ~= 1 then
						vim.fn.mkdir(dependDir, "p")
					end
					
					-- Move the dependency back (only if target doesn't exist)
					if vim.fn.isdirectory(targetDir) ~= 1 then
						local moveCmd = string.format("mv %s %s", vim.fn.shellescape(depPath), vim.fn.shellescape(targetDir))
						vim.fn.system(moveCmd)
					end
				end
			end
		end
	end
	
	-- Extract all repo fields (including dependencies)
	-- Include synapse plugin itself in update list
	local plugins = {}
	local pluginSet = {}
	
	-- Add synapse plugin if it exists in package_path (special location: package_path/synapse.nvim/)
	local synapsePath = string.format("%s/synapse.nvim", packagePath)
	if vim.fn.isdirectory(synapsePath) == 1 then
		-- Use default repo from config, or fallback to common path
		local synapseRepo = config.opts.default or "OriginCoderPulse/synapse.nvim"
		if not pluginSet[synapseRepo] then
			table.insert(plugins, synapseRepo)
			pluginSet[synapseRepo] = true
			-- Create default config for synapse
			if not repoToConfig[synapseRepo] then
				repoToConfig[synapseRepo] = {
					repo = synapseRepo,
					config = {},
				}
			end
			mainPluginRepos[synapseRepo] = true
		end
	end
	
	for _, pluginConfig in ipairs(configs) do
		if pluginConfig.repo then
			-- Add main plugin
			if not pluginSet[pluginConfig.repo] then
				table.insert(plugins, pluginConfig.repo)
				pluginSet[pluginConfig.repo] = true
			end
			
			-- Add dependencies
			if pluginConfig.depend and type(pluginConfig.depend) == "table" then
				for _, depItem in ipairs(pluginConfig.depend) do
					local depRepo, depOpt = configLoader.parseDependency(depItem)
					if depRepo and not pluginSet[depRepo] then
						table.insert(plugins, depRepo)
						pluginSet[depRepo] = true
						-- Create default config for dependency (if not already exists)
						if not repoToConfig[depRepo] then
							local depConfig = {
								repo = depRepo,
								-- Don't set branch by default, let git use default branch
								config = {},
							}
							if depOpt then
								depConfig.opt = depOpt
							end
							repoToConfig[depRepo] = depConfig
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

	local function pluginNames(list)
		local names = {}
		for _, repo in ipairs(list) do
			-- UI directly displays full repo name
			table.insert(names, repo)
		end
		return names
	end

	local function attachCloseAutocmd(buf)
		vim.api.nvim_create_autocmd("WinClosed", {
			buffer = buf,
			callback = function()
				isUpdateAborted = true
				for _, job in ipairs(jobs) do
					vim.fn.jobstop(job)
				end
			end,
		})
	end

	local function startUpdateFlow(targets, attempt, aggregate)
		attempt = attempt or 1
		aggregate = aggregate or { errors = {}, success = 0, total = 0, checks = 0, checkSuccess = 0 }
		if not targets or #targets == 0 then
			ui.log_message("Nothing to update.")
			return
		end

		isUpdateAborted = false
		jobs = {}

		local closeRegistered = false

		local function ensureClose(buf)
			if closeRegistered then
				return
			end
			attachCloseAutocmd(buf)
			closeRegistered = true
		end

		local function extractRetryTargets(checkErrors)
			local retryTargets = {}
			local seen = {}
			for _, err in ipairs(checkErrors or {}) do
				if err.repo and not seen[err.repo] then
					seen[err.repo] = true
					table.insert(retryTargets, err.repo)
				end
			end
			return retryTargets
		end

		local function formatIcon(cfg)
			if type(cfg) == "table" then
				return cfg.glyph or cfg.text or cfg.icon or ""
			end
			return cfg or ""
		end

		local function finalizeRun()
			local failureCount = #aggregate.errors
			local failedLookup = {}
			local failedNames = {}
			for _, err in ipairs(aggregate.errors) do
				local name = err.plugin or err.repo or "unknown"
				if not failedLookup[name] then
					failedLookup[name] = true
					table.insert(failedNames, name)
				end
			end

			if failureCount > 0 then
				-- Show failed plugins and allow retry
				ui.show_report(aggregate.errors, aggregate.success, aggregate.total, {
					ui = config.opts.ui,
					failed_plugins = failedNames,
					on_retry = function()
						-- Retry failed plugins
						local retryTargets = {}
						local seen = {}
						for _, err in ipairs(aggregate.errors) do
							local repo = err.repo
							if repo and not seen[repo] then
								table.insert(retryTargets, repo)
								seen[repo] = true
							end
						end
						if #retryTargets > 0 then
							startUpdateFlow(retryTargets)
						end
					end,
				})
			else
				ui.close({ message = "Upgrade Success", level = vim.log.levels.INFO })
			end
		end

		local progressWin = ui.open({
			header = config.opts.ui.header,
			icon = config.opts.ui.icons.check,
			plugins = pluginNames(targets),
			ui = config.opts.ui,
		})
		ensureClose(progressWin.buf)

		-- Initialize progress display to 0
		vim.schedule(function()
			ui.update_progress(progressWin, nil, 0, #targets, config.opts.ui)
		end)

		-- Execute in same window: check → update immediately if needed, up to 10 concurrent plugin tasks
		local function runChecks(queue)
			local total = #queue
			local completed = 0
			local errors = {}
			local successCount = 0

			local function doneAll()
				aggregate.checks = aggregate.checks + total
				aggregate.checkSuccess = aggregate.checkSuccess + successCount
				aggregate.total = aggregate.total + total
				vim.list_extend(aggregate.errors, errors)
				finalizeRun()
			end

			local MAX_CONCURRENT = 10
			local pendingQueue = {}
			local runningCount = 0

			for i = 1, #queue do
				table.insert(pendingQueue, i)
			end

			local function startNextTask()
				if isUpdateAborted then
					return
				end

				-- All tasks completed
				if #pendingQueue == 0 and runningCount == 0 then
					doneAll()
					return
				end

				-- Reached concurrency limit or no pending tasks
				if runningCount >= MAX_CONCURRENT or #pendingQueue == 0 then
					return
				end

				-- Take next task from queue
				local queueIndex = table.remove(pendingQueue, 1)
				local repo = queue[queueIndex]
				-- Display name uses full repo
				local displayName = repo

				runningCount = runningCount + 1

				-- Mark as active
				vim.schedule(function()
					ui.update_progress(
						progressWin,
						{ plugin = displayName, status = "active" },
						completed,
						total,
						config.opts.ui
					)
				end)

				-- Determine if this is a main plugin
				local isMainPlugin = mainPluginRepos[repo] == true
				
				-- Determine if this is a main plugin (including synapse)
				local isMainPlugin = mainPluginRepos[repo] == true
				
				-- Task for single plugin: check first, then update if needed
				M.checkPlugin(repo, config.opts.package_path, repoToConfig[repo], function(ok, result)
					if not ok then
						-- Check failed, mark as error directly
						table.insert(errors, { plugin = displayName, error = result, repo = repo })
						errorUi.saveError(displayName, result or "Check failed")
						completed = completed + 1
						runningCount = runningCount - 1
						vim.schedule(function()
							ui.update_progress(
								progressWin,
								{ plugin = displayName, status = "failed" },
								completed,
								total,
								config.opts.ui
							)
							-- Try to start next task (in schedule to ensure immediate execution)
							startNextTask()
						end)
						return
					end

					if result == "need_update" then
						-- Needs update: immediately update current plugin
						local isMainPlugin = mainPluginRepos[repo] == true
						M.updatePlugin(
							repo,
							config.opts.package_path,
							repoToConfig[repo],
							isMainPlugin,
							config,
							function(ok2, err2)
								runningCount = runningCount - 1
								if ok2 then
									successCount = successCount + 1
									completed = completed + 1
									vim.schedule(function()
										ui.update_progress(
											progressWin,
											{ plugin = displayName, status = "done" },
											completed,
											total,
											config.opts.ui
										)
										-- Try to start next task (in schedule to ensure immediate execution)
										startNextTask()
									end)
								else
									table.insert(errors, { plugin = displayName, error = err2, repo = repo })
									errorUi.saveError(displayName, err2 or "Update failed")
									completed = completed + 1
									vim.schedule(function()
										ui.update_progress(
											progressWin,
											{ plugin = displayName, status = "failed" },
											completed,
											total,
											config.opts.ui
										)
										-- Try to start next task (in schedule to ensure immediate execution)
										startNextTask()
									end)
								end
							end
						)
					else
						-- Already up-to-date: mark as done directly
						successCount = successCount + 1
						completed = completed + 1
						runningCount = runningCount - 1
						vim.schedule(function()
							ui.update_progress(
								progressWin,
								{ plugin = displayName, status = "done" },
								completed,
								total,
								config.opts.ui
							)
							-- Try to start next task (in schedule to ensure immediate execution)
							startNextTask()
						end)
					end
				end)
			end

			-- Start initial tasks (up to MAX_CONCURRENT)
			for _ = 1, math.min(MAX_CONCURRENT, #pendingQueue) do
				startNextTask()
			end
		end

		-- Use single window: check + update immediately if needed
		runChecks(targets)
	end

	startUpdateFlow(plugins)
end

--- Check if plugin needs update
--- @param plugin string Plugin repository path
--- @param packagePath string Base package installation path
--- @param pluginConfig table|nil Plugin configuration
--- @param callback function Callback function(ok, result) where result is "need_update" or "already_updated"
function M.checkPlugin(plugin, packagePath, pluginConfig, callback)
	if isUpdateAborted then
		return callback(false, "Stop")
	end

	local pluginName = plugin:match("([^/]+)$")
	pluginName = pluginName:gsub("%.git$", "")
	
	-- Get plugin info to determine installation path
	local isMainPlugin, mainPluginName = jsonState.getPluginInfo(packagePath, pluginName)
	-- Check if it's a shared dependency (in public folder)
	local publicPath = string.format("%s/public/%s", packagePath, pluginName)
	local isSharedDependency = vim.fn.isdirectory(publicPath) == 1
	local installDir = gitUtils.getInstallDir(pluginName, "update", packagePath, isMainPlugin, mainPluginName, isSharedDependency)
	if vim.fn.isdirectory(installDir) ~= 1 then
		return callback(false, "Directory is not found")
	end

	-- Get current recorded branch / tag from JSON
	local jsonBranch, jsonTag = jsonState.getBranchTag(packagePath, pluginName)
	-- Tag / branch from config
	local configTag = pluginConfig and pluginConfig.tag or nil
	local configBranch = pluginConfig and pluginConfig.branch or nil
	
	-- 1. If tag in config differs from JSON, need update
	if configTag ~= jsonTag then
		return callback(true, "need_update")
	end

	-- 2. Tag consistent and tag exists: consider already at corresponding tag, no need to check branch
	if jsonTag or configTag then
		return callback(true, "already_updated")
	end

	-- 3. In no-tag mode, check if branch changed (cloneConf.branch)
	local function normalizeBranch(branch)
		if not branch or branch == "main" or branch == "master" then
			return nil
		end
		return branch
	end

	local normCfgBranch = normalizeBranch(configBranch)
	local normJsonBranch = normalizeBranch(jsonBranch)

	if normCfgBranch ~= normJsonBranch then
		-- Only branch difference also needs to execute update flow (trigger updatePlugin)
		return callback(true, "need_update")
	end

	local fetchCmd = string.format("cd %s && git fetch --quiet", installDir)
	local checkCmd = string.format("cd %s && git rev-list --count HEAD..@{upstream} 2>&1", installDir)

	local job = gitUtils.executeCommand(fetchCmd, function(fetchOk, _)
		if not fetchOk then
			return callback(false, "Warehouse synchronization failed")
		end

		gitUtils.executeCommand(checkCmd, function(_, result)
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

--- Update a single plugin
--- @param plugin string Plugin repository path
--- @param packagePath string Base package installation path
--- @param pluginConfig table|nil Plugin configuration
--- @param isMainPlugin boolean Whether this is a main plugin
--- @param config table Configuration table
--- @param callback function Callback function(success, err)
function M.updatePlugin(plugin, packagePath, pluginConfig, isMainPluginParam, config, callback)
	if isUpdateAborted then
		return callback(false, "Stop")
	end

	local pluginName = plugin:match("([^/]+)$")
	pluginName = pluginName:gsub("%.git$", "")
	
	-- Get plugin info to determine installation path
	local isMainPlugin, mainPluginName = jsonState.getPluginInfo(packagePath, pluginName)
	-- Use parameter if plugin info not found, otherwise use detected info
	if isMainPlugin == false and mainPluginName == nil then
		isMainPlugin = isMainPluginParam
	end
	-- Check if it's a shared dependency (in public folder)
	local publicPath = string.format("%s/public/%s", packagePath, pluginName)
	local isSharedDependency = vim.fn.isdirectory(publicPath) == 1
	local installDir = gitUtils.getInstallDir(pluginName, "update", packagePath, isMainPlugin, mainPluginName, isSharedDependency)

	-- Get tag and branch from config (branch comes from cloneConf.branch)
	local configTag = pluginConfig and pluginConfig.tag or nil
	local configBranch = pluginConfig and pluginConfig.branch or nil

	-- Get tag and branch recorded in JSON
	local jsonBranch, jsonTag = jsonState.getBranchTag(packagePath, pluginName)

	-- If directory doesn't exist, directly reinstall with current config
	local function reinstall(reason)
		local installModule = require("synapse.core.install")
		local gitMethod = (config and config.method) or "https"
		-- Check if it's a shared dependency
		local publicPath = string.format("%s/public/%s", packagePath, pluginName)
		local isSharedDep = vim.fn.isdirectory(publicPath) == 1
		installModule.installPlugin(pluginConfig, gitMethod, packagePath, isMainPlugin or isMainPluginParam, nil, isSharedDep, function(ok, err)
			if not ok then
				return callback(false, (reason or "Reinstall failed") .. ": " .. (err or "Unknown error"))
			end
			callback(true, reason or "Reinstalled")
		end)
	end

	if vim.fn.isdirectory(installDir) ~= 1 then
		return reinstall("Directory missing")
	end

	---------------------------------------------------------------------------
	-- 1. Handle tag changes first (tag has priority over branch)
	--    Rules:
	--    - tag changed to new value: fetch tags + checkout new tag on current repo
	--    - tag removed: delete repo, re-clone (without tag parameter)
	---------------------------------------------------------------------------
	if configTag ~= jsonTag then
		if configTag then
			local cmd = string.format(
				"cd %s && git fetch origin --tags && git checkout %s && git submodule update --init --recursive",
				vim.fn.shellescape(installDir),
				configTag
			)
			local job = gitUtils.executeCommand(cmd, function(ok, output)
				if not ok then
					return callback(false, output)
				end

				if isMainPlugin then
					-- Record new tag, branch can generally be ignored in tag mode
					jsonState.updateMainPlugin(packagePath, pluginName, pluginConfig, nil, configTag, true)
				end

				callback(true, "Switched tag and updated")
			end)
			table.insert(jobs, job)
			return
		else
			-- Tag removed: delete directory and re-clone with "no tag parameter" method
			local removeCmd = string.format("rm -rf %s", vim.fn.shellescape(installDir))
			return gitUtils.executeCommand(removeCmd, function(ok, err)
				if not ok then
					return callback(false, "Failed to remove plugin for tag removal: " .. (err or "Unknown error"))
				end
				reinstall("Tag removed, re-cloned without tag")
			end)
		end
	end

	---------------------------------------------------------------------------
	-- 2. Handle branch changes (only in no-tag mode)
	--    Rules:
	--    - cloneConf.branch changed to new branch: checkout new branch + pull on current repo
	--    - cloneConf.branch removed: delete repo, re-clone (without -b, use default branch)
	---------------------------------------------------------------------------
	local function normalizeBranch(branch)
		if not branch or branch == "main" or branch == "master" then
			return nil
		end
		return branch
	end

	local normCfgBranch = normalizeBranch(configBranch)
	local normJsonBranch = normalizeBranch(jsonBranch)

	if normCfgBranch ~= normJsonBranch then
		if normCfgBranch then
			-- From A -> B: use git checkout -B to create/reset local branch, then pull latest code
			-- Note: no longer strongly depends on origin/<branch> existing, to avoid errors like
			-- "fatal: 'origin/xxx' is not a commit and a branch 'xxx' cannot be created from it"
			local cmd = string.format(
				"cd %s && git fetch origin && git checkout -B %s && git pull origin %s && git submodule update --init --recursive",
				vim.fn.shellescape(installDir),
				normCfgBranch,
				normCfgBranch
			)
			local job = gitUtils.executeCommand(cmd, function(ok, output)
				if not ok then
					return callback(false, output)
				end

				if isMainPlugin then
					jsonState.updateMainPlugin(packagePath, pluginName, pluginConfig, normCfgBranch, nil, true)
				end

				callback(true, "Switched branch and updated")
			end)
			table.insert(jobs, job)
			return
		else
			-- Branch field removed: delete repo, re-clone (without -b)
			local removeCmd = string.format("rm -rf %s", vim.fn.shellescape(installDir))
			return gitUtils.executeCommand(removeCmd, function(ok, err)
				if not ok then
					return callback(false, "Failed to remove plugin for branch removal: " .. (err or "Unknown error"))
				end
				reinstall("Branch removed, re-cloned with default branch")
			end)
		end
	end

	---------------------------------------------------------------------------
	-- 3. Tag and branch unchanged: normal update
	---------------------------------------------------------------------------
	local cmd
	if configTag then
		-- Shouldn't reach here (tag already handled above), keep for logic adjustments
		cmd = string.format(
			"cd %s && git fetch origin --tags && git checkout %s && git submodule update --init --recursive",
			vim.fn.shellescape(installDir),
			configTag
		)
	else
		local branch = normCfgBranch or normJsonBranch
		if branch then
			cmd = string.format(
				"cd %s && git fetch origin && git checkout -B %s && git pull origin %s && git submodule update --init --recursive",
				vim.fn.shellescape(installDir),
				branch,
				branch
			)
		else
			cmd = string.format(
				"cd %s && git fetch origin && git pull origin && git submodule update --init --recursive",
				vim.fn.shellescape(installDir)
			)
		end
	end

	local job = gitUtils.executeCommand(cmd, function(ok, output)
		if not ok then
			return callback(false, output)
		end

		local executeCmds = pluginConfig and pluginConfig.execute or nil
		local function finalizeOk()
			if pluginConfig and isMainPlugin then
				local actualBranch = normCfgBranch or normJsonBranch
				local actualTag = configTag or jsonTag
				jsonState.updateMainPlugin(packagePath, pluginName, pluginConfig, actualBranch, actualTag, true)
			end
			callback(true, "Success")
		end

		-- Execute execute commands after update
		if executeCmds and type(executeCmds) == "table" and #executeCmds > 0 then
			executeCommands(executeCmds, installDir, function(execSuccess, execErr)
				if not execSuccess then
					return callback(false, execErr)
				end
				finalizeOk()
			end)
		else
			finalizeOk()
		end
	end)
	table.insert(jobs, job)
end

return M
