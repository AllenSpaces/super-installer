local M = {}

--- Parse a dependency item (supports both string and table formats)
--- @param dep string|table Dependency item (string: "user/repo", table: { "user/repo", primary = "...", opt = {...} })
--- @return string|nil repo Repository path
--- @return string|nil primary Primary plugin name
--- @return table|nil opt Optional configuration table
function M.parseDependency(dep)
	if type(dep) == "string" then
		return dep, nil, nil
	elseif type(dep) == "table" then
		-- Support format: { "user/repo", primary = "...", opt = {...} }
		local repo = dep[1]
		local primary = dep.primary
		local opt = dep.opt
		if type(repo) == "string" then
			return repo, primary, opt
		end
	end
	return nil, nil, nil
end

--- Remove duplicates from a table
--- @param tb table Table to process
--- @return table Table with duplicates removed
function M.removeDuplicates(tb)
	local seen = {}
	local result = {}

	for _, value in ipairs(tb) do
		if type(value) == "string" and not seen[value] then
			seen[value] = true
			table.insert(result, value)
		end
	end

	return result
end

--- Recursively build file paths from nested import structure
--- Supports arbitrary depth: { test = { test1 = { "ok" } } } -> configPath/lua/test/test1/ok.lua
--- @param currentPath string Current path being built (e.g., "lua/test/test1")
--- @param value table|string Current value (table for nested, string for filename)
--- @param configPath string Base config path
--- @param results table Output table to collect file paths
local function buildImportPaths(currentPath, value, configPath, results)
	if type(value) == "string" then
		-- Base case: string value means it's a filename
		local filePath = configPath .. "/" .. currentPath .. "/" .. value
		if vim.fn.filereadable(filePath) == 1 then
			table.insert(results, filePath)
		else
			-- Try with .lua extension
			filePath = filePath .. ".lua"
			if vim.fn.filereadable(filePath) == 1 then
				table.insert(results, filePath)
			end
		end
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
			for _, item in ipairs(value) do
				if type(item) == "string" then
					local filePath = configPath .. "/" .. currentPath .. "/" .. item
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
					buildImportPaths(newPath, v, configPath, results)
				elseif type(k) == "number" and type(v) == "string" then
					-- Direct array element at this level: { "test" } -> configPath/lua/test.lua
					local filePath = configPath .. "/" .. currentPath .. "/" .. v .. ".lua"
					if vim.fn.filereadable(filePath) == 1 then
						table.insert(results, filePath)
					end
				end
			end
		end
	end
end

--- Load import files specified in imports field
--- @param imports table|nil Imports configuration
--- @param configPath string Config path
--- @return table List of file paths
local function getImportFiles(imports, configPath)
	local importFiles = {}
	
	if not imports or type(imports) ~= "table" or not configPath then
		return importFiles
	end

	for category, files in pairs(imports) do
		if type(files) == "table" then
			-- Start building path from category (e.g., "lua")
			buildImportPaths(category, files, configPath, importFiles)
		end
	end
	
	return importFiles
end

--- Load all configuration files from configPath (recursive scan)
--- Scans .config.lua files and optionally loads import files
--- @param configPath string Base configuration directory path
--- @param imports table|nil Optional imports configuration
--- @return table Array of plugin configuration tables
function M.loadConfigFiles(configPath, imports)
	local configs = {}

	if not configPath or configPath == "" then
		return configs
	end

	if vim.fn.isdirectory(configPath) ~= 1 then
		return configs
	end

	-- Recursively get all .config.lua files
	local luaFiles = vim.fn.globpath(configPath, "**/*.config.lua", true, true)
	
	-- Add import files if specified
	if imports then
		local importFiles = getImportFiles(imports, configPath)
		for _, filePath in ipairs(importFiles) do
			table.insert(luaFiles, filePath)
		end
	end

	for _, filePath in ipairs(luaFiles) do
		if filePath ~= "" then
			local ok, config = pcall(function()
				-- Load and execute file to get returned config table
				local chunk = loadfile(filePath)
				if chunk then
					return chunk()
				end
				return nil
			end)

			if ok and config and type(config) == "table" then
				-- Check if repo field exists
				if config.repo and type(config.repo) == "string" and config.repo ~= "" then
					-- Extract config information
					local pluginConfig = {
						repo = config.repo,
						-- Don't set branch by default, only use it if explicitly specified
						branch = nil,
						config = config.config or {},
						depend = {}, -- Dependency list
					}

					-- Use branch from cloneConf if available
					if config.cloneConf and type(config.cloneConf) == "table" and config.cloneConf.branch then
						pluginConfig.branch = config.cloneConf.branch
					end

					-- Extract tag if tag field exists
					if config.tag and type(config.tag) == "string" and config.tag ~= "" then
						pluginConfig.tag = config.tag
					end

					-- Extract execute commands if execute field exists
					if config.execute then
						if type(config.execute) == "string" and config.execute ~= "" then
							pluginConfig.execute = { config.execute }
						elseif type(config.execute) == "table" then
							pluginConfig.execute = {}
							for _, cmd in ipairs(config.execute) do
								if type(cmd) == "string" and cmd ~= "" then
									table.insert(pluginConfig.execute, cmd)
								end
							end
						end
					end

					-- Extract dependencies if depend field exists
					if config.depend and type(config.depend) == "table" then
						for _, dep in ipairs(config.depend) do
							local repo, primary, opt = M.parseDependency(dep)
							if repo and repo ~= "" then
								-- Store as table format: { repo, primary = primary, opt = opt }
								if primary or opt then
									local depItem = { repo }
									if primary then
										depItem.primary = primary
									end
									if opt then
										depItem.opt = opt
									end
									table.insert(pluginConfig.depend, depItem)
								else
									-- Keep string format for backward compatibility
									table.insert(pluginConfig.depend, repo)
								end
							end
						end
					end

					table.insert(configs, pluginConfig)
				end
			end
		end
	end

	return configs
end

return M

