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

--- Load configuration files from config_path
--- @param config_path string Path to scan for .config.lua files
function M.load_config(config_path)
	if not config_path or config_path == "" then
		return
	end
	
	-- Scan all .config.lua files in the specified path
	local config_modules = scan_config_files(config_path)
	
	-- Load and execute config functions
	for _, module in ipairs(config_modules) do
		if module.enabled then
			local mod = safe_require(module.name, module.file_path)
			if mod and mod.config then
				if mod.loaded then
					if mod.loaded.event and #mod.loaded.event > 0 then
						vim.api.nvim_create_autocmd(mod.loaded.event, {
							group = vim.api.nvim_create_augroup(module.name, { clear = true }),
							once = true,
							callback = function()
								mod.config()
							end,
						})
					elseif mod.loaded.ft and #mod.loaded.ft > 0 then
						vim.api.nvim_create_autocmd("FileType", {
							group = vim.api.nvim_create_augroup(module.name, { clear = true }),
							pattern = mod.loaded.ft,
							callback = function()
								mod.config()
							end,
						})
					end
				else
					mod.config()
				end
			end
		end
	end
end

return M

