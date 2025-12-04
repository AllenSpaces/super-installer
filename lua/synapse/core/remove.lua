local ui = require("synapse.ui")
local errorUi = require("synapse.ui.errorUi")
local gitUtils = require("synapse.utils.gitUtils")
local configLoader = require("synapse.utils.configLoader")
local jsonState = require("synapse.utils.jsonState")
local stringUtils = require("synapse.utils.stringUtils")

local M = {}

local cleanupActive = true
local jobs = {}

--- Start plugin removal process
--- @param config table Configuration table
function M.start(config)
	cleanupActive = true
	jobs = {}
	-- Clear error cache at start
	errorUi.clearCache()
	
	-- Load configuration files from config_path (including import files)
	local configs = configLoader.loadConfigFiles(config.opts.config_path, config.imports)
	
	-- Add default plugin
	local defaultConfig = {
		repo = config.opts.default,
		branch = "main",
		config = {},
	}
	table.insert(configs, 1, defaultConfig)

	-- Collect all required plugins (including dependencies)
	local requiredPlugins = {}
	for _, pluginConfig in ipairs(configs) do
		if pluginConfig.repo then
			local pluginName = pluginConfig.repo:match("([^/]+)$")
			pluginName = pluginName:gsub("%.git$", "")
			requiredPlugins[pluginName] = true
			
			-- Add dependencies
			if pluginConfig.depend and type(pluginConfig.depend) == "table" then
				for _, depItem in ipairs(pluginConfig.depend) do
					local depRepo = configLoader.parseDependency(depItem)
					if depRepo then
						local depName = depRepo:match("([^/]+)$")
						depName = depName:gsub("%.git$", "")
						requiredPlugins[depName] = true
					end
				end
			end
		end
	end

	local packagePath = config.opts.package_path
	local installedPlugins = vim.split(vim.fn.glob(packagePath .. "/*"), "\n")

	local removalCandidates = {}
	for _, path in ipairs(installedPlugins) do
		-- Only process directories (plugins are directories, not files)
		if vim.fn.isdirectory(path) == 1 then
			local name = vim.fn.fnamemodify(path, ":t")
			if not requiredPlugins[name] and name ~= "synapse" and name ~= "synapse.nvim" then
				table.insert(removalCandidates, name)
			end
		end
	end

	if #removalCandidates == 0 then
		-- No plugins to remove, return directly without updating json
		ui.log_message("No unused plugins found.")
		return
	end

	local function runRemovalQueue(queue)
		if not queue or #queue == 0 then
			return
		end

		cleanupActive = true
		jobs = {}
		
		-- Save references to configs and config for use in finalize
		local savedConfigs = configs
		local savedConfig = config

		local progressWin = nil
		if #queue > 1 then
			progressWin = ui.open({
				header = config.opts.ui.header,
				icon = config.opts.ui.icons.remove,
				plugins = queue,
				ui = config.opts.ui,
			})

			vim.api.nvim_create_autocmd("WinClosed", {
				buffer = progressWin.buf,
				callback = function()
					cleanupActive = false
					for _, job in ipairs(jobs) do
						if job then
							vim.fn.jobstop(job)
						end
					end
				end,
			})

			-- Initialize progress display to 0
			vim.schedule(function()
				ui.update_progress(progressWin, nil, 0, #queue, config.opts.ui)
			end)
		end

		local total = #queue
		local errors = {}
		local removedCount = 0
		local completed = 0
		local failedList = {}

		local function finalize()
			if not cleanupActive then
				return
			end

			-- Only update json if plugins were actually removed (sync depend field)
			if removedCount > 0 then
				for _, pluginConfig in ipairs(savedConfigs) do
					if pluginConfig.repo then
						local pluginName = pluginConfig.repo:match("([^/]+)$")
						pluginName = pluginName:gsub("%.git$", "")
						local installDir = gitUtils.getInstallDir(pluginName, "start", savedConfig.opts.package_path)
						
						-- Only update installed main plugins
						if vim.fn.isdirectory(installDir) == 1 then
							-- Get current branch and tag from json (if exists)
							local jsonBranch, jsonTag = jsonState.getBranchTag(savedConfig.opts.package_path, pluginName)
							-- Use branch and tag from config, or from json if config doesn't have them
							local actualBranch = pluginConfig.branch or jsonBranch
							local actualTag = pluginConfig.tag or jsonTag
							
							-- Update json record (this will sync depend field)
							jsonState.updateMainPlugin(
								savedConfig.opts.package_path,
								pluginName,
								pluginConfig,
								actualBranch,
								actualTag,
								true
							)
						end
					end
				end
			end

			if #errors > 0 then
				-- Show failed plugins and allow retry
				ui.show_report(errors, removedCount, total, {
					ui = savedConfig.opts.ui,
					failed_plugins = failedList,
					on_retry = function()
						-- Retry failed plugins
						local retryQueue = {}
						for _, err in ipairs(errors) do
							for _, plugin in ipairs(queue) do
								if plugin == err.plugin then
									table.insert(retryQueue, plugin)
									break
								end
							end
						end
						if #retryQueue > 0 then
							runRemovalQueue(retryQueue)
						end
					end,
				})
			else
				vim.notify("Remove Success", vim.log.levels.INFO, { title = "Synapse" })
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

		local function startNextRemoval()
			if not cleanupActive then
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
			local plugin = queue[queueIndex]

			runningCount = runningCount + 1
			if progressWin then
				vim.schedule(function()
					ui.update_progress(progressWin, { plugin = plugin, status = "active" }, completed, total, config.opts.ui)
				end)
			end

			local jobId = M.removePlugin(plugin, config.opts.package_path, function(success, err)
				runningCount = runningCount - 1
				completed = completed + 1

				if success then
					removedCount = removedCount + 1
				else
					table.insert(errors, { plugin = plugin, error = err or "Removal failed" })
					table.insert(failedList, plugin)
					errorUi.saveError(plugin, err or "Removal failed")
				end

				-- Immediately update progress bar and start next task
				if progressWin then
					vim.schedule(function()
						ui.update_progress(
							progressWin,
							{ plugin = plugin, status = success and "done" or "failed" },
							completed,
							total,
							config.opts.ui
						)
						-- Try to start next task (in schedule to ensure immediate execution)
						startNextRemoval()
					end)
				else
					-- If no progress window, directly start next task
					startNextRemoval()
				end
			end)
			if jobId then
				table.insert(jobs, jobId)
			end
		end

		-- Start initial tasks (up to MAX_CONCURRENT)
		for i = 1, math.min(MAX_CONCURRENT, #pendingQueue) do
			startNextRemoval()
		end
	end

	runRemovalQueue(removalCandidates)
end

--- Remove a single plugin
--- @param pluginName string Plugin name to remove
--- @param packagePath string Base package installation path
--- @param callback function Callback function(success, err)
--- @return number|nil jobId Job ID for tracking
function M.removePlugin(pluginName, packagePath, callback)
	local installPath = gitUtils.getInstallDir(pluginName, "start", packagePath)

	if vim.fn.isdirectory(installPath) ~= 1 then
		callback(true)
		return
	end

	-- Get dependencies from synapse.json
	local dependencies = jsonState.getPluginDependencies(packagePath, pluginName)
	
	-- Remove the plugin
	local cmd = string.format("rm -rf %s", vim.fn.shellescape(installPath))
	local jobId = gitUtils.executeCommand(cmd, function(success, err)
		if success then
			-- Remove from synapse.json
			jsonState.removePluginEntry(packagePath, pluginName)
			
			-- Check and remove unreferenced dependencies
			if dependencies and #dependencies > 0 then
				for _, depRepo in ipairs(dependencies) do
					local depName = stringUtils.getPluginName(depRepo)
					-- Check if dependency is referenced by other plugins
					if not jsonState.isDependencyReferenced(depName, packagePath, pluginName) then
						-- Remove unreferenced dependency
						local depPath = gitUtils.getInstallDir(depName, "start", packagePath)
						if vim.fn.isdirectory(depPath) == 1 then
							local depCmd = string.format("rm -rf %s", vim.fn.shellescape(depPath))
							gitUtils.executeCommand(depCmd, function() end)
							jsonState.removePluginEntry(packagePath, depName)
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
	return jobId
end

return M
