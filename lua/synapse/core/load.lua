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

--- Load configuration files from config_path
--- @param config_path string|table Path to scan for .config.lua files
function M.load_config(config_path)
	if not config_path then
		return
	end
	
	-- Handle both string and table formats
	local path = config_path
	
	if type(config_path) == "table" then
		path = config_path.path
	end
	
	-- If path is not set, use default config directory
	if not path or path == "" then
		path = vim.fn.stdpath("config") .. "/lua"
	end
	
	-- Normalize path
	path = vim.fn.fnamemodify(path, ":p")
	path = path:gsub("/$", "") -- Remove trailing slash
	
	-- Scan all .config.lua files in the specified path
	local config_modules = scan_config_files(path)
	
	-- Load all modules
	for _, module in ipairs(config_modules) do
		execute_config(module)
	end
end

return M

