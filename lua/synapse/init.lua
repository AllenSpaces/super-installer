local config = require("synapse.config")
local commands = require("synapse.commands")
local loadConfig = require("synapse.core.load")
local M = {}

--- Normalize path (expand ~, normalize separators, remove trailing slashes)
--- @param path string
--- @return string
local function norm(path)
	if path:sub(1, 1) == "~" then
		local home = vim.uv.os_homedir()
		if home:sub(-1) == "\\" or home:sub(-1) == "/" then
			home = home:sub(1, -2)
		end
		path = home .. path:sub(2)
	end
	path = path:gsub("\\", "/"):gsub("/+", "/")
	return path:sub(-1) == "/" and path:sub(1, -2) or path
end

--- Get synapse.nvim's own path
--- @return string
local function get_synapse_path()
	local me = debug.getinfo(1, "S").source:sub(2)
	me = norm(vim.fn.fnamemodify(me, ":p:h:h:h:h"))
	return me
end

--- Add plugin directory to runtimepath
--- This does the same as runtime.c:add_pack_dir_to_rtp
--- * find first after directory
--- * find synapse pack path
--- * insert right after synapse pack path or right before first after or at the end
--- * insert after dir right before first after or append to the end
--- @param pluginDir string Plugin directory path
local function add_to_rtp(pluginDir)
	local rtp = vim.api.nvim_get_runtime_file("", true)
	local idx_dir, idx_after
	local synapse_path = get_synapse_path()

	pluginDir = norm(pluginDir)

	-- Check if plugin directory is already in rtp
	local already_added = false
	for _, path in ipairs(rtp) do
		if norm(path) == pluginDir then
			already_added = true
			break
		end
	end

	if already_added then
		return
	end

	for i, path in ipairs(rtp) do
		path = norm(path)
		if path == synapse_path then
			idx_dir = i + 1
		elseif not idx_after and path:sub(-6, -1) == "/after" then
			idx_after = i + 1 -- +1 to offset the insert of the plugin dir
			idx_dir = idx_dir or i
			break
		end
	end

	table.insert(rtp, idx_dir or (#rtp + 1), pluginDir)

	local after = pluginDir .. "/after"
	if vim.uv.fs_stat(after) then
		-- Check if after directory is already in rtp
		local after_added = false
		for _, path in ipairs(rtp) do
			if norm(path) == norm(after) then
				after_added = true
				break
			end
		end
		if not after_added then
			table.insert(rtp, idx_after or (#rtp + 1), after)
		end
	end

	---@type vim.Option
	vim.opt.rtp = rtp
end

--- Scan installed plugins and add them to rtp (batch processing for better performance)
--- @param packagePath string Base package installation path
local function scan_and_add_plugins(packagePath)
	packagePath = norm(packagePath)

	-- Collect all plugin paths first (batch processing)
	local pluginPaths = {}
	local afterPaths = {}
	local synapse_path = get_synapse_path()

	-- Check synapse plugin (special location)
	local synapsePath = packagePath .. "/synapse.nvim"
	if vim.fn.isdirectory(synapsePath) == 1 then
		table.insert(pluginPaths, synapsePath)
	end

	-- Scan main plugins: package_path/plugin-name/plugin-name/
	for _, path in ipairs(vim.split(vim.fn.glob(packagePath .. "/*"), "\n")) do
		if vim.fn.isdirectory(path) == 1 then
			local pluginName = vim.fn.fnamemodify(path, ":t")
			-- Skip synapse.nvim as it's already checked above
			if pluginName ~= "synapse.nvim" and pluginName ~= "synapse" then
				-- Check if this is a main plugin directory (has plugin-name/plugin-name/ structure)
				local mainPluginPath = packagePath .. "/" .. pluginName .. "/" .. pluginName
				if vim.fn.isdirectory(mainPluginPath) == 1 then
					table.insert(pluginPaths, mainPluginPath)
					-- Check for after directory
					local after = mainPluginPath .. "/after"
					if vim.uv.fs_stat(after) then
						table.insert(afterPaths, after)
					end
				end
			end
		end
	end

	-- Scan dependencies in depend folders: package_path/main-plugin-name/depend/dependency-name/
	for _, path in ipairs(vim.split(vim.fn.glob(packagePath .. "/*/depend/*"), "\n")) do
		if vim.fn.isdirectory(path) == 1 then
			table.insert(pluginPaths, path)
			-- Check for after directory
			local after = path .. "/after"
			if vim.uv.fs_stat(after) then
				table.insert(afterPaths, after)
			end
		end
	end

	-- Scan shared dependencies in public folder: package_path/public/dependency-name/
	for _, path in ipairs(vim.split(vim.fn.glob(packagePath .. "/public/*"), "\n")) do
		if vim.fn.isdirectory(path) == 1 then
			table.insert(pluginPaths, path)
			-- Check for after directory
			local after = path .. "/after"
			if vim.uv.fs_stat(after) then
				table.insert(afterPaths, after)
			end
		end
	end

	-- Batch add all plugins to rtp (only one rtp update)
	if #pluginPaths > 0 or #afterPaths > 0 then
		local rtp = vim.api.nvim_get_runtime_file("", true)
		local rtpSet = {}
		local idx_dir, idx_after

		-- Build a set of existing rtp paths for fast lookup
		for _, path in ipairs(rtp) do
			rtpSet[norm(path)] = true
			path = norm(path)
			if path == synapse_path then
				idx_dir = #rtp + 1 -- Will be adjusted after insertions
			elseif not idx_after and path:sub(-6, -1) == "/after" then
				idx_after = #rtp + 1
			end
		end

		-- Find insertion point
		for i, path in ipairs(rtp) do
			path = norm(path)
			if path == synapse_path then
				idx_dir = i + 1
			elseif not idx_after and path:sub(-6, -1) == "/after" then
				idx_after = i + 1
				idx_dir = idx_dir or i
				break
			end
		end

		-- Add plugin directories
		for _, pluginDir in ipairs(pluginPaths) do
			pluginDir = norm(pluginDir)
			if not rtpSet[pluginDir] then
				rtpSet[pluginDir] = true
				table.insert(rtp, idx_dir or (#rtp + 1), pluginDir)
				if idx_dir then
					idx_dir = idx_dir + 1
					if idx_after then
						idx_after = idx_after + 1
					end
				end
			end
		end

		-- Add after directories
		for _, after in ipairs(afterPaths) do
			after = norm(after)
			if not rtpSet[after] then
				rtpSet[after] = true
				table.insert(rtp, idx_after or (#rtp + 1), after)
				if idx_after then
					idx_after = idx_after + 1
				end
			end
		end

		-- Update rtp once for all plugins
		---@type vim.Option
		vim.opt.rtp = rtp
	end
end

--- Setup Synapse plugin manager
--- @param userConfig table|nil User configuration table
function M.setup(userConfig)
	local mergedConfig = config.merge(userConfig)

	-- Get synapse.nvim's own path
	local synapse_path = get_synapse_path()

	-- Reset packpath if configured
	if mergedConfig.opts.performance and mergedConfig.opts.performance.reset_packpath then
		vim.go.packpath = vim.env.VIMRUNTIME
	end

	-- Reset rtp if configured (reset to basic paths for better startup performance)
	if mergedConfig.opts.performance and mergedConfig.opts.performance.rtp and mergedConfig.opts.performance.rtp.reset then
		local lib = vim.fn.fnamemodify(vim.v.progpath, ":p:h:h") .. "/lib"
		lib = vim.uv.fs_stat(lib .. "64") and (lib .. "64") or lib
		lib = lib .. "/nvim"
		---@type vim.Option
		vim.opt.rtp = {
			vim.fn.stdpath("config"),
			vim.fn.stdpath("data") .. "/site",
			synapse_path,
			vim.env.VIMRUNTIME,
			lib,
			vim.fn.stdpath("config") .. "/after",
		}
	end

	-- Add custom rtp paths if configured
	if mergedConfig.opts.performance and mergedConfig.opts.performance.rtp and mergedConfig.opts.performance.rtp.paths then
		for _, path in ipairs(mergedConfig.opts.performance.rtp.paths) do
			vim.opt.rtp:append(path)
		end
	end

	-- Scan and add installed plugins to rtp (replaces old wildcard approach)
	scan_and_add_plugins(mergedConfig.opts.package_path)

	-- Load configs (including dependency opt configurations and imports)
	-- Scans .config.lua files and import files from config_path
	if mergedConfig.opts.config_path then
		loadConfig.loadConfig(mergedConfig.opts.config_path, mergedConfig.imports)
	end

	-- Setup commands and keymaps
	commands.setup(mergedConfig)
end

return M
