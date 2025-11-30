--- Scan all .config.lua files in the specified directory (recursive)
--- @param config_path string Path to scan for .config.lua files
--- @return table
local function scan_config_files(config_path)
	local configs = {}
	
	if not config_path or config_path == "" then
		return configs
	end
	
	if vim.fn.isdirectory(config_path) ~= 1 then
		return configs
	end
	
	-- Recursively get all .config.lua files
	local files = vim.fn.globpath(config_path, "**/*.config.lua", true, true)
	
	for _, file in ipairs(files) do
		if file ~= "" then
			-- Get relative path from config_path
			local relative_path = file:gsub("^" .. config_path .. "/", ""):gsub("%.config%.lua$", "")
			local module_name = relative_path:gsub("/", ".")
			table.insert(configs, { name = module_name, file_path = file, enabled = true })
		end
	end
	
	return configs
end

--- Safely require a module from file path
--- @param module_name string
--- @param file_path string
--- @return table|nil
local function safe_require(module_name, file_path)
	if file_path then
		local ok, result = pcall(dofile, file_path)
		if not ok then
			vim.notify(
				"Failed to load module: " .. module_name .. " - " .. result,
				vim.log.levels.WARN,
				{ title = "Nvim" }
			)
			return nil
		end
		return result
	else
		local ok, result = pcall(require, module_name)
		if not ok then
			vim.notify(
				"Failed to load module: " .. module_name .. " - " .. result,
				vim.log.levels.WARN,
				{ title = "Nvim" }
			)
			return nil
		end
		return result
	end
end

local M = {}

--- Execute config function for a module
--- @param module table Module information
--- @param immediate boolean If true, execute immediately even if loaded is set
local function execute_config(module, immediate)
	if not module.enabled then
		return
	end
	
	local mod = safe_require(module.name, module.file_path)
	if mod and mod.config then
		-- If immediate is true, skip lazy loading and execute immediately
		if immediate then
			local ok, err = pcall(mod.config)
			if not ok then
				vim.notify(
					"Error executing config for " .. module.name .. ": " .. tostring(err),
					vim.log.levels.WARN,
					{ title = "Synapse" }
				)
			end
		elseif mod.loaded then
			if mod.loaded.event and #mod.loaded.event > 0 then
				vim.api.nvim_create_autocmd(mod.loaded.event, {
					group = vim.api.nvim_create_augroup(module.name, { clear = true }),
					once = true,
					callback = function()
						local ok, err = pcall(mod.config)
						if not ok then
							vim.notify(
								"Error executing config for " .. module.name .. ": " .. tostring(err),
								vim.log.levels.WARN,
								{ title = "Synapse" }
							)
						end
					end,
				})
			elseif mod.loaded.ft and #mod.loaded.ft > 0 then
				vim.api.nvim_create_autocmd("FileType", {
					group = vim.api.nvim_create_augroup(module.name, { clear = true }),
					pattern = mod.loaded.ft,
					callback = function()
						local ok, err = pcall(mod.config)
						if not ok then
							vim.notify(
								"Error executing config for " .. module.name .. ": " .. tostring(err),
								vim.log.levels.WARN,
								{ title = "Synapse" }
							)
						end
					end,
				})
			end
		else
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
end

--- Load only first-priority configuration files
--- @param config_path string|table Path to scan for .config.lua files, or table with path and first fields
function M.load_first_config(config_path)
	if not config_path then
		return
	end
	
	-- Handle both string and table formats
	local path = config_path
	local first_list = {}
	
	if type(config_path) == "table" then
		path = config_path.path
		if config_path.first and type(config_path.first) == "table" then
			first_list = config_path.first
		end
	end
	
	-- If path is not set, use default config directory
	if not path or path == "" then
		path = vim.fn.stdpath("config") .. "/lua"
	end
	
	if #first_list == 0 then
		return
	end
	
	-- Normalize path
	path = vim.fn.fnamemodify(path, ":p")
	path = path:gsub("/$", "") -- Remove trailing slash
	
	-- Scan all .config.lua files in the specified path
	local config_modules = scan_config_files(path)
	
	if #config_modules == 0 then
		return
	end
	
	-- Find and load only first-priority modules in order
	for _, first_name in ipairs(first_list) do
		-- Normalize first_name: remove .config suffix if present
		local first_base = first_name:gsub("%.config$", "")
		
		local found = false
		for _, module in ipairs(config_modules) do
			-- Check if module name matches
			-- Support formats: "custom.config", "configs.custom", "configs.custom.config"
			local module_name = module.name
			
			-- Exact match
			if module_name == first_name or module_name == first_base then
				execute_config(module, true)
				found = true
				break
			end
			
			-- Match by ending (e.g., "configs.custom" matches "custom" or "custom.config")
			if module_name:match("%." .. first_base:gsub("%.", "%%.") .. "$") or
			   module_name:match("%." .. first_name:gsub("%.", "%%.") .. "$") then
				execute_config(module, true)
				found = true
				break
			end
			
			-- Match by filename (e.g., "custom.config.lua" matches "custom.config" or "custom")
			local file_name = vim.fn.fnamemodify(module.file_path, ":t")
			local file_base = file_name:gsub("%.config%.lua$", "")
			if file_base == first_name or file_base == first_base then
				execute_config(module, true)
				found = true
				break
			end
		end
	end
end

--- Load configuration files from config_path
--- @param config_path string|table Path to scan for .config.lua files, or table with path and first fields
function M.load_config(config_path)
	if not config_path then
		return
	end
	
	-- Handle both string and table formats
	local path = config_path
	local first_list = {}
	
	if type(config_path) == "table" then
		path = config_path.path
		if config_path.first and type(config_path.first) == "table" then
			first_list = config_path.first
		end
	end
	
	-- If path is not set, use default config directory
	if not path or path == "" then
		path = vim.fn.stdpath("config") .. "/lua"
	end
	
	-- Scan all .config.lua files in the specified path
	local config_modules = scan_config_files(path)
	
	-- Separate first-priority modules and other modules
	local first_modules = {}
	local other_modules = {}
	local first_set = {}
	
	-- Create a set for quick lookup
	for _, first_name in ipairs(first_list) do
		first_set[first_name] = true
	end
	
	-- Categorize modules
	for _, module in ipairs(config_modules) do
		-- Check if module name matches any first-priority name
		local is_first = false
		local matched_first_name = nil
		
		for first_name, _ in pairs(first_set) do
			-- Match by exact name, ending with the first name, or containing the first name as a segment
			-- Examples: "configs.custom.config" matches "custom.config"
			--           "configs.keymaps.config" matches "keymaps.config"
			--           "custom.config" matches "custom.config"
			local pattern = "([^%.]+%.)?" .. first_name:gsub("%.", "%%.") .. "$"
			if module.name == first_name or module.name:match(pattern) then
				is_first = true
				matched_first_name = first_name
				break
			end
		end
		
		if is_first then
			table.insert(first_modules, { module = module, first_name = matched_first_name })
		else
			table.insert(other_modules, module)
		end
	end
	
	-- Sort first_modules according to first_list order
	if #first_modules > 0 and #first_list > 0 then
		local sorted_first = {}
		local used_indices = {}
		
		-- Add modules in the order specified in first_list
		for _, first_name in ipairs(first_list) do
			local pattern = "([^%.]+%.)?" .. first_name:gsub("%.", "%%.") .. "$"
			for i, item in ipairs(first_modules) do
				if not used_indices[i] and (item.module.name == first_name or item.module.name:match(pattern)) then
					table.insert(sorted_first, item.module)
					used_indices[i] = true
					break
				end
			end
		end
		
		-- Add any remaining first_modules that weren't in first_list
		for i, item in ipairs(first_modules) do
			if not used_indices[i] then
				table.insert(sorted_first, item.module)
			end
		end
		
		first_modules = sorted_first
	else
		-- If no first_list, just extract modules from first_modules items
		local extracted = {}
		for _, item in ipairs(first_modules) do
			table.insert(extracted, item.module)
		end
		first_modules = extracted
	end
	
	-- Load first-priority modules first
	for _, module in ipairs(first_modules) do
		execute_config(module)
	end
	
	-- Then load other modules
	for _, module in ipairs(other_modules) do
		execute_config(module)
	end
end

return M

