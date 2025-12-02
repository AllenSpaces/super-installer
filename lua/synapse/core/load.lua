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

local config_utils = require("synapse.utils.config")
local string_utils = require("synapse.utils.string")

local M = {}

--- Load dependency opt configuration
--- @param repo string Plugin repository path
--- @param opt table Configuration table
local function load_dependency_opt(repo, opt)
	if not repo or not opt or type(opt) ~= "table" then
		return
	end

	-- Extract plugin name from repo (e.g., "nvim-lua/plenary.nvim" -> "plenary")
	local plugin_name = repo:match("([^/]+)$")
	plugin_name = plugin_name:gsub("%.git$", ""):gsub("%.nvim$", ""):gsub("%-nvim$", "")

	-- Try to require and setup the plugin
	local ok, plugin = pcall(require, plugin_name)
	if ok and plugin and plugin.setup then
		local setup_ok, setup_err = pcall(plugin.setup, opt)
		if not setup_ok then
			vim.notify(
				"Error setting up dependency " .. repo .. ": " .. tostring(setup_err),
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
--- @param mod table Module table (may contain repo field)
--- @param module_name string Module name (e.g., "pkgs.snips.config")
--- @param file_path string File path
--- @return string|nil Plugin name
local function extract_plugin_name(mod, module_name, file_path)
	-- First, try to extract from repo field if available
	if mod and mod.repo and type(mod.repo) == "string" then
		return string_utils.get_plugin_name(mod.repo)
	end

	-- Try to extract from module name
	-- Examples:
	--   "pkgs.snips.config" -> "snips"
	--   "configs.plugin.config" -> "plugin"
	--   "plugin.config" -> "plugin"
	local parts = {}
	for part in module_name:gmatch("([^%.]+)") do
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
	if file_path then
		local basename = vim.fn.fnamemodify(file_path, ":t:r")
		local name = basename:gsub("%.config$", "")
		if name and name ~= "" and name ~= "config" then
			return name
		end
	end

	return nil
end

--- Create a package wrapper function that handles recursive require paths
--- Supports both old style (package.mock_nvim_web_devicons()) and new style (package({ "install" }))
--- @param base_name string Base plugin name (e.g., "nvim-treesitter")
--- @return table Package wrapper (function + plugin module)
local function create_package_wrapper(base_name)
	local plugin_module = require(base_name)

	-- Create wrapper function
	local wrapper_func = function(paths)
		-- New style: package({ "install" }) or package({ "install" = { "log" }})
		if paths and type(paths) == "table" then
			-- Handle array format: {"install"} -> "plugin.install"
			if #paths > 0 then
				local path_parts = {}
				for _, part in ipairs(paths) do
					table.insert(path_parts, tostring(part))
				end
				local full_path = base_name .. "." .. table.concat(path_parts, ".")
				return require(full_path)
			end

			-- Handle table format: {install = {"log"}} -> "plugin.install.log"
			-- Recursively build the path
			local function build_path(tbl, current_path)
				local paths_list = {}

				for key, value in pairs(tbl) do
					local new_path = current_path .. "." .. tostring(key)

					if type(value) == "table" and next(value) ~= nil then
						-- Check if it's an array
						if #value > 0 then
							-- Array format: {install = {"log"}} -> "plugin.install.log"
							local path_parts = { new_path }
							for _, part in ipairs(value) do
								table.insert(path_parts, tostring(part))
							end
							table.insert(paths_list, table.concat(path_parts, "."))
						else
							-- Recursive case: nested table
							local nested_paths = build_path(value, new_path)
							for _, path in ipairs(nested_paths) do
								table.insert(paths_list, path)
							end
						end
					else
						-- Base case: just the path
						table.insert(paths_list, new_path)
					end
				end

				return paths_list
			end

			local path_list = build_path(paths, base_name)
			if #path_list > 0 then
				-- Return the first path
				return require(path_list[1])
			end
		end

		-- No arguments: return base module (for new style without args)
		return plugin_module
	end

	-- Create wrapper table that can be called as function and accessed as table
	local wrapper = {}

	-- Set metatable to allow method calls on wrapper
	-- This allows old style: package.mock_nvim_web_devicons()
	setmetatable(wrapper, {
		__index = plugin_module, -- Allow accessing plugin methods/properties
		__call = wrapper_func, -- Allow calling as function: package({ "install" })
	})

	return wrapper
end

--- Execute config function for a module
--- @param module table Module information
--- @param immediate boolean If true, execute immediately even if loaded is set
local function execute_config(module, immediate)
	if not module.enabled then
		return
	end

	local mod = safe_require(module.name, module.file_path)
	if not mod then
		return
	end

	-- Support config as table: directly call plugin.setup(config)
	if mod.config and type(mod.config) == "table" then
		local plugin_name = extract_plugin_name(mod, module.name, module.file_path)
		if not plugin_name then
			vim.notify(
				"Failed to extract plugin name from " .. module.name,
				vim.log.levels.WARN,
				{ title = "Synapse" }
			)
			return
		end

		-- Try multiple possible plugin names
		local possible_names = { plugin_name }

		-- If plugin_name contains uppercase, also try lowercase version
		if plugin_name:match("%u") then
			table.insert(possible_names, plugin_name:lower())
		end

		-- If plugin_name ends with -nvim or .nvim, try without it
		local base_name = plugin_name:gsub("%-nvim$", ""):gsub("%.nvim$", "")
		if base_name ~= plugin_name then
			table.insert(possible_names, base_name)
		end

		local setup_success = false
		for _, name in ipairs(possible_names) do
			local ok, plugin = pcall(require, name)
			if ok and plugin then
				-- Call initialization function if it exists, before setup
				if mod.initialization and type(mod.initialization) == "function" then
					-- Create package wrapper function for recursive require paths
					local package_wrapper = create_package_wrapper(name)
					local init_ok, init_err = pcall(mod.initialization, package_wrapper)
					if not init_ok then
						vim.notify(
							"Error executing initialization for " .. name .. ": " .. tostring(init_err),
							vim.log.levels.WARN,
							{ title = "Synapse" }
						)
					end
				end

				if plugin.setup then
					local setup_ok, setup_err = pcall(plugin.setup, mod.config)
					if setup_ok then
						setup_success = true
						break
					else
						vim.notify(
							"Error setting up " .. name .. ": " .. tostring(setup_err),
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

		if not setup_success then
			vim.notify(
				"Failed to setup plugin for " ..
				module.name .. " (tried: " .. table.concat(possible_names, ", ") .. "). Plugin may not be installed yet.",
				vim.log.levels.WARN,
				{ title = "Synapse" }
			)
		end

		return
	end

	-- Support config as function (original behavior)
	if mod.config and type(mod.config) == "function" then
		-- Call initialization function if it exists, before config
		if mod.initialization and type(mod.initialization) == "function" then
			-- Try to extract plugin name and require it
			local plugin_name = extract_plugin_name(mod, module.name, module.file_path)
			if plugin_name then
				-- Try multiple possible plugin names
				local possible_names = { plugin_name }
				if plugin_name:match("%u") then
					table.insert(possible_names, plugin_name:lower())
				end
				local base_name = plugin_name:gsub("%-nvim$", ""):gsub("%.nvim$", "")
				if base_name ~= plugin_name then
					table.insert(possible_names, base_name)
				end

				-- Try to require plugin and call initialization
				for _, name in ipairs(possible_names) do
					local ok, plugin = pcall(require, name)
					if ok and plugin then
						-- Create package wrapper function for recursive require paths
						local package_wrapper = create_package_wrapper(name)
						local init_ok, init_err = pcall(mod.initialization, package_wrapper)
						if not init_ok then
							vim.notify(
								"Error executing initialization for " .. name .. ": " .. tostring(init_err),
								vim.log.levels.WARN,
								{ title = "Synapse" }
							)
						end
						break
					end
				end
			end
		end

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
--- @param config_files_path string|nil Optional path to scan for plugin config files (for dependency opt loading)
function M.load_config(config_path, config_files_path)
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

	-- Step 1: Scan and load all .config.lua files first
	-- This ensures main plugins are set up before their dependencies
	local config_modules = scan_config_files(path)

	-- Load all modules (main plugin configurations)
	for _, module in ipairs(config_modules) do
		execute_config(module)
	end

	-- Step 2: Load dependency opt configurations from config files
	-- This happens after main plugins are set up, so dependencies can safely use them
	if config_files_path then
		local configs = config_utils.load_config_files(config_files_path)
		for _, plugin_config in ipairs(configs) do
			if plugin_config.depend and type(plugin_config.depend) == "table" then
				for _, dep_item in ipairs(plugin_config.depend) do
					local dep_repo, dep_opt = config_utils.parse_dependency(dep_item)
					if dep_repo and dep_opt then
						load_dependency_opt(dep_repo, dep_opt)
					end
				end
			end
		end
	end
end

return M
