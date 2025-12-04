local jsonUtils = require("synapse.utils.jsonUtils")
local configLoader = require("synapse.utils.configLoader")
local stringUtils = require("synapse.utils.stringUtils")

local M = {}

--- Update metadata fields (total, updateTime, hash) in data
--- @param data table JSON data table to update
local function updateMetadata(data)
	-- Calculate total (number of main plugins + unique dependencies)
	-- Exclude synapse plugin from count
	local mainPluginCount = 0
	local uniqueDeps = {}
	
	if data.plugins and type(data.plugins) == "table" then
		-- Count plugins excluding synapse
		for _, plugin in ipairs(data.plugins) do
			if plugin.name ~= "synapse" and plugin.name ~= "synapse.nvim" then
				mainPluginCount = mainPluginCount + 1
			end
		end
		
		-- Collect all unique dependencies (excluding synapse)
		for _, plugin in ipairs(data.plugins) do
			if plugin.depend and type(plugin.depend) == "table" then
				for _, depItem in ipairs(plugin.depend) do
					local depRepo = configLoader.parseDependency(depItem)
					if depRepo then
						local depName = stringUtils.getPluginName(depRepo)
						-- Exclude synapse from dependencies
						if depName ~= "synapse" and depName ~= "synapse.nvim" then
							uniqueDeps[depRepo] = true
						end
					end
				end
			end
		end
	end
	
	-- Count unique dependencies
	local depCount = 0
	for _ in pairs(uniqueDeps) do
		depCount = depCount + 1
	end
	
	-- Total = main plugins + unique dependencies
	local total = mainPluginCount + depCount
	
	-- Get current timestamp
	local updateTime = os.time()
	
	-- Convert timestamp to hexadecimal
	local hash = string.format("%x", updateTime)
	
	-- Update metadata fields
	data.total = total
	data.update_time = updateTime
	data.hash = hash
end

--- Ensure synapse.json exists, create empty file if it doesn't
--- @param packagePath string Base package installation path
function M.ensureJsonExists(packagePath)
	local jsonPath = jsonUtils.getJsonPath(packagePath)

	if vim.fn.filereadable(jsonPath) == 1 then
		return
	end

	local jsonData = { plugins = {} }
	updateMetadata(jsonData)
	jsonUtils.write(jsonPath, jsonData)
end

--- Get plugin branch and tag from synapse.json
--- @param packagePath string Base package installation path
--- @param pluginName string Plugin name
--- @return string|nil branch Branch name
--- @return string|nil tag Tag name
function M.getBranchTag(packagePath, pluginName)
	local jsonPath = jsonUtils.getJsonPath(packagePath)
	local data, _ = jsonUtils.read(jsonPath)

	if data and data.plugins then
		for _, plugin in ipairs(data.plugins) do
			if plugin.name == pluginName then
				return plugin.branch, plugin.tag
			end
		end
	end

	return nil, nil
end

--- Internal helper: collect all dependency repos from a JSON data table
--- @param data table JSON data table
--- @return table<string, boolean> Set of dependency repository strings
local function collectAllDependRepos(data)
	local allDependRepos = {}
	if not data or not data.plugins then
		return allDependRepos
	end

	for _, plugin in ipairs(data.plugins) do
		if plugin.depend and type(plugin.depend) == "table" then
			for _, depItem in ipairs(plugin.depend) do
				local depRepo = configLoader.parseDependency(depItem)
				if depRepo then
					allDependRepos[depRepo] = true
				end
			end
		end
	end

	return allDependRepos
end

--- Normalize depend field to ensure it's always an array
--- @param plugin table Plugin data table
local function normalizeDependField(plugin)
	if plugin.depend then
		-- If depend is not an array, convert it
		if type(plugin.depend) ~= "table" then
			plugin.depend = {}
		else
			-- Check if it's an array (has only numeric keys)
			local isArray = true
			local hasNumericKeys = false
			for k, _ in pairs(plugin.depend) do
				if type(k) == "number" then
					hasNumericKeys = true
				else
					isArray = false
					break
				end
			end
			-- If it's not an array, convert to array
			if not isArray or not hasNumericKeys then
				plugin.depend = {}
			end
		end
	else
		plugin.depend = {}
	end
end

--- Update synapse.json with plugin information (only for main plugins)
--- This keeps dependency repos as full repo strings
--- @param packagePath string Base package installation path
--- @param pluginName string Plugin name
--- @param pluginConfig table Plugin configuration
--- @param actualBranch string|nil Actual branch name
--- @param actualTag string|nil Actual tag name
--- @param isMainPlugin boolean Whether this is a main plugin
function M.updateMainPlugin(packagePath, pluginName, pluginConfig, actualBranch, actualTag, isMainPlugin)
	if not isMainPlugin then
		return
	end

	-- Don't write synapse plugin itself to json
	if pluginName == "synapse" or pluginName == "synapse.nvim" then
		return
	end

	local jsonPath = jsonUtils.getJsonPath(packagePath)
	local data, _ = jsonUtils.read(jsonPath)
	if not data then
		data = { plugins = {} }
	end
	
	-- Remove synapse plugin if it exists in the data
	if data.plugins then
		for i = #data.plugins, 1, -1 do
			local plugin = data.plugins[i]
			if plugin.name == "synapse" or plugin.name == "synapse.nvim" then
				table.remove(data.plugins, i)
			end
		end
	end
	
	-- Normalize all existing plugins' depend fields
	for _, plugin in ipairs(data.plugins) do
		normalizeDependField(plugin)
	end

	-- Collect depend repos from current pluginConfig (excluding synapse)
	local dependRepos = {}
	if pluginConfig.depend and type(pluginConfig.depend) == "table" then
		for _, depItem in ipairs(pluginConfig.depend) do
			local depRepo = configLoader.parseDependency(depItem)
			if depRepo then
				local depName = stringUtils.getPluginName(depRepo)
				-- Exclude synapse from dependencies
				if depName ~= "synapse" and depName ~= "synapse.nvim" then
					table.insert(dependRepos, depRepo)
				end
			end
		end
	end

	-- Collect all repos that appear in any plugin's depend field (including current plugin)
	local allDependRepos = collectAllDependRepos(data)
	for _, depRepo in ipairs(dependRepos) do
		allDependRepos[depRepo] = true
	end

	local currentRepo = pluginConfig.repo

	-- If this repo is in any depend field, don't save it as a main plugin
	if allDependRepos[currentRepo] then
		return
	end

	-- Check if plugin already exists
	local found = false
	local foundIndex = nil
	for i, plugin in ipairs(data.plugins) do
		if plugin.name == pluginName then
			found = true
			foundIndex = i
			break
		end
	end

	local function setBranchAndTag(target)
		local branch = actualBranch or pluginConfig.branch
		if branch and branch ~= "main" and branch ~= "master" then
			target.branch = branch
		else
			target.branch = nil
		end

		local tag = actualTag or pluginConfig.tag
		if tag then
			target.tag = tag
		else
			target.tag = nil
		end
	end

	if found then
		-- Ensure this plugin is not now only a dependency of others
		local isInOtherDepend = false
		for _, plugin in ipairs(data.plugins) do
			if plugin.name ~= pluginName and plugin.depend and type(plugin.depend) == "table" then
				for _, depItem in ipairs(plugin.depend) do
					local depRepo = configLoader.parseDependency(depItem)
					if depRepo == currentRepo then
						isInOtherDepend = true
						break
					end
				end
			end
			if isInOtherDepend then
				break
			end
		end

		if isInOtherDepend then
			table.remove(data.plugins, foundIndex)
			updateMetadata(data)
			jsonUtils.write(jsonPath, data)
			return
		end

		-- Update existing entry
		data.plugins[foundIndex].repo = currentRepo
		data.plugins[foundIndex].depend = dependRepos
		setBranchAndTag(data.plugins[foundIndex])
	else
		-- Add new plugin if not found
		local entry = {
			name = pluginName,
			repo = currentRepo,
			depend = dependRepos,
		}
		setBranchAndTag(entry)
		table.insert(data.plugins, entry)
	end

	updateMetadata(data)
	jsonUtils.write(jsonPath, data)
end

--- Remove plugin record from synapse.json
--- @param packagePath string Base package installation path
--- @param pluginName string Plugin name to remove
function M.removePluginEntry(packagePath, pluginName)
	-- Don't remove synapse plugin from json (it shouldn't be there anyway)
	if pluginName == "synapse" or pluginName == "synapse.nvim" then
		return
	end

	local jsonPath = jsonUtils.getJsonPath(packagePath)
	local data, _ = jsonUtils.read(jsonPath)

	if not data or not data.plugins then
		return
	end

	for i, plugin in ipairs(data.plugins) do
		if plugin.name == pluginName then
			table.remove(data.plugins, i)
			break
		end
	end

	updateMetadata(data)
	jsonUtils.write(jsonPath, data)
end

--- Get dependencies of a plugin from synapse.json
--- @param packagePath string Base package installation path
--- @param pluginName string Plugin name
--- @return table|nil Dependencies array or nil if not found
function M.getPluginDependencies(packagePath, pluginName)
	local jsonPath = jsonUtils.getJsonPath(packagePath)
	local data, _ = jsonUtils.read(jsonPath)

	if not data or not data.plugins then
		return nil
	end

	for _, plugin in ipairs(data.plugins) do
		if plugin.name == pluginName then
			return plugin.depend or {}
		end
	end

	return nil
end

--- Check if a dependency is referenced by other plugins
--- @param depName string Dependency name to check
--- @param packagePath string Base package installation path
--- @param excludePlugin string|nil Plugin name to exclude from check
--- @return boolean Whether the dependency is referenced
function M.isDependencyReferenced(depName, packagePath, excludePlugin)
	local jsonPath = jsonUtils.getJsonPath(packagePath)
	local data, _ = jsonUtils.read(jsonPath)

	if not data or not data.plugins then
		return false
	end

	for _, plugin in ipairs(data.plugins) do
		if plugin.name ~= excludePlugin and plugin.depend then
			for _, depItem in ipairs(plugin.depend) do
				local depRepo = configLoader.parseDependency(depItem)
				if depRepo then
					local depPluginName = stringUtils.getPluginName(depRepo)
					if depPluginName == depName then
						return true
					end
				end
			end
		end
	end

	return false
end

--- Add a dependency to a main plugin's depend field in synapse.json
--- Only updates if the main plugin already exists in json
--- @param packagePath string Base package installation path
--- @param mainPluginName string Main plugin name
--- @param depRepo string Dependency repository string
function M.addDependencyToMainPlugin(packagePath, mainPluginName, depRepo)
	-- Don't add synapse as a dependency
	if mainPluginName == "synapse" or mainPluginName == "synapse.nvim" then
		return
	end

	local jsonPath = jsonUtils.getJsonPath(packagePath)
	local data, _ = jsonUtils.read(jsonPath)
	if not data or not data.plugins then
		-- Main plugin not in json yet, will be updated when main plugin is installed
		return
	end

	-- Normalize all existing plugins' depend fields
	for _, plugin in ipairs(data.plugins) do
		normalizeDependField(plugin)
	end
	
	-- Find the main plugin in json
	local foundIndex = nil
	for i, plugin in ipairs(data.plugins) do
		if plugin.name == mainPluginName then
			foundIndex = i
			break
		end
	end

	if foundIndex then
		-- Plugin exists, ensure depend is an array
		normalizeDependField(data.plugins[foundIndex])
		
		-- Check if dependency already exists
		local depExists = false
		for _, existingDep in ipairs(data.plugins[foundIndex].depend) do
			if existingDep == depRepo then
				depExists = true
				break
			end
		end
		
		-- Add dependency if it doesn't exist
		if not depExists then
			table.insert(data.plugins[foundIndex].depend, depRepo)
			updateMetadata(data)
			jsonUtils.write(jsonPath, data)
		end
	end
	-- If main plugin not found in json, it will be created when main plugin is installed
end

--- Get plugin information (is main plugin, and which main plugin it belongs to if it's a dependency)
--- @param packagePath string Base package installation path
--- @param pluginName string Plugin name to check
--- @return boolean isMainPlugin Whether this is a main plugin
--- @return string|nil mainPluginName Main plugin name if this is a dependency, nil otherwise
function M.getPluginInfo(packagePath, pluginName)
	local jsonPath = jsonUtils.getJsonPath(packagePath)
	local data, _ = jsonUtils.read(jsonPath)
	
	-- Special handling for synapse plugin: it's directly in package_path/synapse.nvim/
	if pluginName == "synapse" or pluginName == "synapse.nvim" then
		local synapsePath = string.format("%s/synapse.nvim", packagePath)
		if vim.fn.isdirectory(synapsePath) == 1 then
			return true, nil
		end
		-- If not found, still return as main plugin (for new installations)
		return true, nil
	end
	
	-- First check directory structure (most reliable for existing plugins)
	local mainPluginPath = string.format("%s/%s/%s", packagePath, pluginName, pluginName)
	if vim.fn.isdirectory(mainPluginPath) == 1 then
		return true, nil
	end
	
	-- Check if it's in public folder (shared dependency)
	local publicPath = string.format("%s/public/%s", packagePath, pluginName)
	if vim.fn.isdirectory(publicPath) == 1 then
		return false, nil -- Shared dependency, no specific main plugin
	end
	
	-- Check if it's in a depend folder (single dependency)
	if data and data.plugins then
		for _, plugin in ipairs(data.plugins) do
			local dependPath = string.format("%s/%s/depend/%s", packagePath, plugin.name, pluginName)
			if vim.fn.isdirectory(dependPath) == 1 then
				return false, plugin.name
			end
		end
	end
	
	-- Then check JSON data
	if data and data.plugins then
		-- Check if it's a main plugin
		for _, plugin in ipairs(data.plugins) do
			if plugin.name == pluginName then
				return true, nil
			end
		end
		
		-- Check if it's a dependency and find which main plugin it belongs to
		for _, plugin in ipairs(data.plugins) do
			if plugin.depend and type(plugin.depend) == "table" then
				for _, depItem in ipairs(plugin.depend) do
					local depRepo = configLoader.parseDependency(depItem)
					if depRepo then
						local depName = stringUtils.getPluginName(depRepo)
						if depName == pluginName then
							return false, plugin.name
						end
					end
				end
			end
		end
	end
	
	-- Default: assume it's a main plugin if we can't determine
	-- This is safe for new installations
	return true, nil
end

return M

