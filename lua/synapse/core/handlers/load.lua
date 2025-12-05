local configLoader = require("synapse.utils.configLoader")
local stringUtils = require("synapse.utils.stringUtils")

local M = {}

-- Plugin registry for lazy loading
M.plugins = {} -- plugin_name -> { config, module, file_path, handlers }

--- Scan all .config.lua files in the specified directory (recursive)
--- @param configPath string Path to scan for .config.lua files
--- @return table Array of module information tables
local function scanConfigFiles(configPath)
	local configs = {}

	if not configPath or configPath == "" then
		return configs
	end

	if vim.fn.isdirectory(configPath) ~= 1 then
		return configs
	end

	-- Recursively get all .config.lua files
	local files = vim.fn.globpath(configPath, "**/*.config.lua", true, true)

	for _, file in ipairs(files) do
		if file ~= "" then
			-- Get relative path from configPath
			local relativePath = file:gsub("^" .. configPath .. "/", ""):gsub("%.config%.lua$", "")
			local moduleName = relativePath:gsub("/", ".")
			table.insert(configs, { name = moduleName, file_path = file, enabled = true })
		end
	end

	return configs
end

--- Safely require a module from file path
--- @param moduleName string Module name
--- @param filePath string|nil File path (if nil, uses require)
--- @return table|nil Module table or nil if failed
local function safeRequire(moduleName, filePath)
	if filePath then
		local ok, result = pcall(dofile, filePath)
		if not ok then
			vim.notify(
				"Failed to load module: " .. moduleName .. " - " .. result,
				vim.log.levels.WARN,
				{ title = "Nvim" }
			)
			return nil
		end
		return result
	else
		local ok, result = pcall(require, moduleName)
		if not ok then
			vim.notify(
				"Failed to load module: " .. moduleName .. " - " .. result,
				vim.log.levels.WARN,
				{ title = "Nvim" }
			)
			return nil
		end
		return result
	end
end

--- Load dependency opt configuration
--- @param repo string Plugin repository path
--- @param primary string|nil Primary plugin name
--- @param opt table Configuration table
local function loadDependencyOpt(repo, primary, opt)
	if not repo or not opt or type(opt) ~= "table" then
		return
	end

	-- Extract plugin name: use primary parameter if available, otherwise extract from repo
	local pluginName = nil
	if primary and type(primary) == "string" and primary ~= "" then
		pluginName = primary
	else
		-- Extract plugin name from repo (e.g., "nvim-lua/plenary.nvim" -> "plenary")
		pluginName = repo:match("([^/]+)$")
		pluginName = pluginName:gsub("%.git$", ""):gsub("%.nvim$", ""):gsub("%-nvim$", "")
	end

	-- Try to require and setup the plugin
	local ok, plugin = pcall(require, pluginName)
	if ok and plugin and plugin.setup then
		local setupOk, setupErr = pcall(plugin.setup, opt)
		if not setupOk then
			vim.notify(
				"Error setting up dependency " .. repo .. ": " .. tostring(setupErr),
				vim.log.levels.WARN,
				{ title = "Synapse" }
			)
		end
	elseif not ok then
		-- Plugin not found, silently skip (it might not be installed yet)
	elseif plugin and not plugin.setup then
		vim.notify(
			"Dependency " .. repo .. " does not have a setup function",
			vim.log.levels.WARN,
			{ title = "Synapse" }
		)
	end
end

--- Extract plugin name from module, repo, module name or file path
--- @param mod table Module table (may contain repo, primary field)
--- @param moduleName string Module name (e.g., "pkgs.snips.config")
--- @param filePath string File path
--- @return string|nil Plugin name
local function extractPluginName(mod, moduleName, filePath)
	-- First, check for primary field (highest priority)
	if mod and mod.primary and type(mod.primary) == "string" and mod.primary ~= "" then
		return mod.primary
	end

	-- Second, try to extract from repo field if available
	if mod and mod.repo and type(mod.repo) == "string" then
		return stringUtils.getPluginName(mod.repo)
	end

	-- Try to extract from module name
	-- Examples:
	--   "pkgs.snips.config" -> "snips"
	--   "configs.plugin.config" -> "plugin"
	--   "plugin.config" -> "plugin"
	local parts = {}
	for part in moduleName:gmatch("([^%.]+)") do
		table.insert(parts, part)
	end

	-- Remove "config" suffix if present
	if #parts > 0 and parts[#parts] == "config" then
		table.remove(parts)
	end

	-- Get the last part as plugin name
	if #parts > 0 then
		local name = parts[#parts]
		if name and name ~= "config" then
			return name
		end
	end

	-- Try from file path
	if filePath then
		local basename = vim.fn.fnamemodify(filePath, ":t:r")
		local name = basename:gsub("%.config$", "")
		if name and name ~= "" and name ~= "config" then
			return name
		end
	end

	return nil
end

--- Recursively build require path from nested table structure
--- Supports arbitrary depth: { test = { test1 = { "ok" } } } -> "plugin.test.test1.ok"
--- @param value table|string Current value
--- @param currentPath string Current path being built
--- @return string|nil Final require path
local function buildRequirePath(value, currentPath)
	if type(value) == "string" then
		-- Base case: string means it's the final module name
		return currentPath .. "." .. value
	elseif type(value) == "table" then
		-- Check if it's an array (has numeric keys)
		local isArray = false
		local hasStringKeys = false
		for k, _ in pairs(value) do
			if type(k) == "number" then
				isArray = true
			elseif type(k) == "string" then
				hasStringKeys = true
			end
		end
		
		if isArray and not hasStringKeys then
			-- Array format: { "ok" } -> append to path
			if #value > 0 then
				local pathParts = { currentPath }
				for _, part in ipairs(value) do
					if type(part) == "string" then
						table.insert(pathParts, part)
					end
				end
				return table.concat(pathParts, ".")
			end
		else
			-- Table format: continue recursion
			-- Find the first string key and continue
			for k, v in pairs(value) do
				if type(k) == "string" then
					local newPath = currentPath .. "." .. k
					local result = buildRequirePath(v, newPath)
					if result then
						return result
					end
				end
			end
		end
	end
	return nil
end

--- Create a package wrapper function that handles recursive require paths
--- Supports both old style (package.mock_nvim_web_devicons()) and new style (package({ "install" }))
--- Supports arbitrary depth: package({ test = { test1 = { "ok" } } })
--- @param baseName string Base plugin name (e.g., "nvim-treesitter")
--- @return table Package wrapper (function + plugin module)
local function createPackageWrapper(baseName)
	local pluginModule = require(baseName)

	-- Create wrapper function
	local wrapperFunc = function(paths)
		-- New style: package({ "install" }) or package({ "install" = { "log" }}) or package({ test = { test1 = { "ok" } } })
		if paths and type(paths) == "table" then
			-- Handle array format: {"install"} -> "plugin.install"
			local isArray = false
			local hasStringKeys = false
			for k, _ in pairs(paths) do
				if type(k) == "number" then
					isArray = true
				elseif type(k) == "string" then
					hasStringKeys = true
				end
			end
			
			if isArray and not hasStringKeys and #paths > 0 then
				-- Simple array format: {"install"} -> "plugin.install"
				local pathParts = { baseName }
				for _, part in ipairs(paths) do
					table.insert(pathParts, tostring(part))
				end
				local fullPath = table.concat(pathParts, ".")
				return require(fullPath)
			elseif hasStringKeys then
				-- Table format: recursively build path
				local fullPath = buildRequirePath(paths, baseName)
				if fullPath then
					return require(fullPath)
				end
			end
		end

		-- No arguments: return base module (for new style without args)
		return pluginModule
	end

	-- Create wrapper table that can be called as function and accessed as table
	local wrapper = {}

	-- Set metatable to allow method calls on wrapper
	-- This allows old style: package.mock_nvim_web_devicons()
	setmetatable(wrapper, {
		__index = pluginModule, -- Allow accessing plugin methods/properties
		__call = wrapperFunc, -- Allow calling as function: package({ "install" })
	})

	return wrapper
end

--- Check if plugin should be lazy loaded
--- @param mod table Module configuration
--- @return boolean
local function shouldLazyLoad(mod)
	if not mod then
		return false
	end
	-- Check for lazy loading triggers: cmd, event, or ft
	return (mod.cmd ~= nil) or (mod.event ~= nil) or (mod.ft ~= nil)
end

--- Execute config function for a module
--- @param module table Module information
--- @param forceLoad boolean|nil Force immediate load (skip lazy loading)
local function executeConfig(module, forceLoad)
	if not module.enabled then
		return
	end

	local mod = safeRequire(module.name, module.file_path)
	if not mod then
		return
	end

	-- Check if plugin should be lazy loaded
	local isLazy = not forceLoad and shouldLazyLoad(mod)
	
	-- Extract plugin name
	local pluginName = extractPluginName(mod, module.name, module.file_path)
	if not pluginName then
		vim.notify(
			"Failed to extract plugin name from " .. module.name,
			vim.log.levels.WARN,
			{ title = "Synapse" }
		)
		return
	end

	-- Register plugin for lazy loading if needed
	if isLazy then
		M.plugins[pluginName] = {
			config = mod,
			module = module,
			file_path = module.file_path,
			handlers = {
				cmd = mod.cmd,
				event = mod.event,
				ft = mod.ft,
			},
		}
		-- Setup lazy loading handlers
		require("synapse.core.handlers.loadCommand").setup(pluginName, mod.cmd)
		require("synapse.core.handlers.loadEvent").setup(pluginName, mod.event)
		require("synapse.core.handlers.loadFileType").setup(pluginName, mod.ft)
		return
	end

	-- Immediate load (non-lazy plugins)
	-- Support opts as table: directly call plugin.setup(opts)
	-- opts must be a table, not a function
	if mod.opts and type(mod.opts) == "table" then
		-- If primary field is specified, use it directly without trying variations
		local possibleNames = {}
		if mod.primary and type(mod.primary) == "string" and mod.primary ~= "" then
			-- Use primary field directly
			table.insert(possibleNames, mod.primary)
		else
			-- Try multiple possible plugin names
			table.insert(possibleNames, pluginName)

			-- If pluginName contains uppercase, also try lowercase version
			if pluginName:match("%u") then
				table.insert(possibleNames, pluginName:lower())
			end

			-- If pluginName ends with -nvim or .nvim, try without it
			local baseName = pluginName:gsub("%-nvim$", ""):gsub("%.nvim$", "")
			if baseName ~= pluginName then
				table.insert(possibleNames, baseName)
			end
		end

		local setupSuccess = false
		for _, name in ipairs(possibleNames) do
			local ok, plugin = pcall(require, name)
			if ok and plugin then
				-- Call initialization function if it exists, before setup
				if mod.initialization and type(mod.initialization) == "function" then
					-- Create package wrapper function for recursive require paths
					local packageWrapper = createPackageWrapper(name)
					local initOk, initErr = pcall(mod.initialization, packageWrapper)
					if not initOk then
						vim.notify(
							"Error executing initialization for " .. name .. ": " .. tostring(initErr),
							vim.log.levels.WARN,
							{ title = "Synapse" }
						)
					end
				end

				if plugin.setup then
					local setupOk, setupErr = pcall(plugin.setup, mod.opts)
					if setupOk then
						setupSuccess = true
						break
					else
						vim.notify(
							"Error setting up " .. name .. ": " .. tostring(setupErr),
							vim.log.levels.WARN,
							{ title = "Synapse" }
						)
					end
				else
					vim.notify(
						"Plugin " .. name .. " does not have a setup function",
						vim.log.levels.WARN,
						{ title = "Synapse" }
					)
				end
			end
		end

		if not setupSuccess then
			vim.notify(
				"Failed to setup plugin for " ..
				module.name .. " (tried: " .. table.concat(possibleNames, ", ") .. "). Plugin may not be installed yet.",
				vim.log.levels.WARN,
				{ title = "Synapse" }
			)
		end

		return
	end

	-- Support config as function
	if mod.config and type(mod.config) == "function" then
		-- Call initialization function if it exists, before config
		if mod.initialization and type(mod.initialization) == "function" then
			-- Try to extract plugin name and require it
			if pluginName then
				-- If primary field is specified, use it directly without trying variations
				local possibleNames = {}
				if mod.primary and type(mod.primary) == "string" and mod.primary ~= "" then
					-- Use primary field directly
					table.insert(possibleNames, mod.primary)
				else
					-- Try multiple possible plugin names
					table.insert(possibleNames, pluginName)
					if pluginName:match("%u") then
						table.insert(possibleNames, pluginName:lower())
					end
					local baseName = pluginName:gsub("%-nvim$", ""):gsub("%.nvim$", "")
					if baseName ~= pluginName then
						table.insert(possibleNames, baseName)
					end
				end

				-- Try to require plugin and call initialization
				for _, name in ipairs(possibleNames) do
					local ok, plugin = pcall(require, name)
					if ok and plugin then
						-- Create package wrapper function for recursive require paths
						local packageWrapper = createPackageWrapper(name)
						local initOk, initErr = pcall(mod.initialization, packageWrapper)
						if not initOk then
							vim.notify(
								"Error executing initialization for " .. name .. ": " .. tostring(initErr),
								vim.log.levels.WARN,
								{ title = "Synapse" }
							)
						end
						break
					end
				end
			end
		end

		-- Execute config function safely
		local ok, err = pcall(mod.config)
		if not ok then
			vim.notify(
				"Error executing config for " .. module.name .. ": " .. tostring(err),
				vim.log.levels.WARN,
				{ title = "Synapse" }
			)
		end
	end
end

--- Load a plugin immediately (called by lazy load handlers)
--- @param pluginName string Plugin name
function M.loadPlugin(pluginName)
	if not pluginName then
		return
	end

	local plugin = M.plugins[pluginName]
	if not plugin then
		-- Plugin might have been loaded already or doesn't exist
		return
	end

	-- Remove from lazy loading registry before loading
	M.plugins[pluginName] = nil

	-- Load the plugin immediately (force load)
	executeConfig(plugin.module, true)
end

--- Load configuration files from configPath
--- Scans .config.lua files for both auto-setup and installation config
--- @param configPath string|table Path to scan for .config.lua files
--- @param imports table|nil Optional imports configuration
function M.loadConfig(configPath, imports)
	if not configPath then
		return
	end

	-- Handle both string and table formats
	local path = configPath

	if type(configPath) == "table" then
		path = configPath.path
	end

	-- If path is not set, use default config directory
	if not path or path == "" then
		path = vim.fn.stdpath("config") .. "/lua"
	end

	-- Normalize path
	path = vim.fn.fnamemodify(path, ":p")
	path = path:gsub("/$", "") -- Remove trailing slash

	-- Step 1: Scan and load all .config.lua files for auto-setup
	-- This ensures main plugins are set up before their dependencies
	local configModules = scanConfigFiles(path)
	
	-- Also load import files for auto-setup
	if imports then
		-- Recursively build file paths from nested import structure
		local function buildImportPathsForLoad(currentPath, value, basePath, results)
			if type(value) == "string" then
				-- Base case: string value means it's a filename
				local filePath = basePath .. "/" .. currentPath .. "/" .. value
				if vim.fn.filereadable(filePath) == 1 then
					table.insert(results, filePath)
				else
					filePath = filePath .. ".lua"
					if vim.fn.filereadable(filePath) == 1 then
						table.insert(results, filePath)
					end
				end
			elseif type(value) == "table" then
				local isArray = false
				local hasStringKeys = false
				for k, _ in pairs(value) do
					if type(k) == "number" then
						isArray = true
					elseif type(k) == "string" then
						hasStringKeys = true
					end
				end
				
				if isArray and not hasStringKeys then
					-- Array format: { "ok" } -> append to path
					for _, item in ipairs(value) do
						if type(item) == "string" then
							local filePath = basePath .. "/" .. currentPath .. "/" .. item
							if vim.fn.filereadable(filePath) == 1 then
								table.insert(results, filePath)
							else
								filePath = filePath .. ".lua"
								if vim.fn.filereadable(filePath) == 1 then
									table.insert(results, filePath)
								end
							end
						end
					end
				else
					-- Table format: continue recursion
					for k, v in pairs(value) do
						if type(k) == "string" then
							local newPath = currentPath .. "/" .. k
							buildImportPathsForLoad(newPath, v, basePath, results)
						elseif type(k) == "number" and type(v) == "string" then
							local filePath = basePath .. "/" .. currentPath .. "/" .. v .. ".lua"
							if vim.fn.filereadable(filePath) == 1 then
								table.insert(results, filePath)
							end
						end
					end
				end
			end
		end
		
		local importFilePaths = {}
		for category, files in pairs(imports) do
			if type(files) == "table" then
				buildImportPathsForLoad(category, files, path, importFilePaths)
			end
		end
		
		for _, filePath in ipairs(importFilePaths) do
			-- Extract relative path for module name
			local relativePath = filePath:gsub("^" .. path .. "/", ""):gsub("%.lua$", "")
			local moduleName = relativePath:gsub("/", ".")
			table.insert(configModules, { name = moduleName, file_path = filePath, enabled = true })
		end
	end

	-- Load all modules (main plugin configurations)
	for _, module in ipairs(configModules) do
		executeConfig(module, false)
	end

	-- Step 2: Load dependency opt configurations from the same configPath
	-- This happens after main plugins are set up, so dependencies can safely use them
	local configs = configLoader.loadConfigFiles(path, imports)
	for _, pluginConfig in ipairs(configs) do
		if pluginConfig.depend and type(pluginConfig.depend) == "table" then
			for _, depItem in ipairs(pluginConfig.depend) do
				local depRepo, depPrimary, depOpt = configLoader.parseDependency(depItem)
				if depRepo and depOpt then
					loadDependencyOpt(depRepo, depPrimary, depOpt)
				end
			end
		end
	end
end

return M

