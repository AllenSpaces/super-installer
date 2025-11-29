local M = {}

--- Remove duplicates from a table
--- @param tb table
--- @return table
function M.table_duplicates(tb)
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

--- Recursively get all .lua files in a directory
--- @param dir_path string
--- @return table
local function get_lua_files(dir_path)
	local files = {}

	-- Get .lua files in current directory
	local current_files = vim.split(vim.fn.glob(dir_path .. "/*.lua"), "\n")
	for _, file in ipairs(current_files) do
		if file ~= "" then
			table.insert(files, file)
		end
	end

	-- Recursively get files from subdirectories
	local subdirs = vim.split(vim.fn.glob(dir_path .. "/*/"), "\n")
	for _, subdir in ipairs(subdirs) do
		if subdir ~= "" and vim.fn.isdirectory(subdir) == 1 then
			local subdir_files = get_lua_files(subdir)
			for _, file in ipairs(subdir_files) do
				table.insert(files, file)
			end
		end
	end

	return files
end

--- Load all configuration files from config_path (recursive scan)
--- @param config_path string
--- @return table
function M.load_config_files(config_path)
	local configs = {}

	if vim.fn.isdirectory(config_path) ~= 1 then
		return configs
	end

	-- Recursively get all .lua files
	local lua_files = get_lua_files(config_path)

	for _, file_path in ipairs(lua_files) do
		if file_path ~= "" then
			local ok, config = pcall(function()
				-- Load and execute file to get returned config table
				local chunk = loadfile(file_path)
				if chunk then
					return chunk()
				end
				return nil
			end)

			if ok and config and type(config) == "table" then
				-- Check if repo field exists
				if config.repo and type(config.repo) == "string" and config.repo ~= "" then
					-- Extract config information
					local plugin_config = {
						repo = config.repo,
						branch = "main", -- Default main branch
						config = config.config or {},
						depend = {}, -- Dependency list
					}

					-- Use branch from clone_conf if available
					if config.clone_conf and type(config.clone_conf) == "table" and config.clone_conf.branch then
						plugin_config.branch = config.clone_conf.branch
					end

					-- Extract tag if tag field exists
					if config.tag and type(config.tag) == "string" and config.tag ~= "" then
						plugin_config.tag = config.tag
					end

					-- Extract execute commands if execute field exists
					if config.execute then
						if type(config.execute) == "string" and config.execute ~= "" then
							plugin_config.execute = { config.execute }
						elseif type(config.execute) == "table" then
							plugin_config.execute = {}
							for _, cmd in ipairs(config.execute) do
								if type(cmd) == "string" and cmd ~= "" then
									table.insert(plugin_config.execute, cmd)
								end
							end
						end
					end

					-- Extract dependencies if depend field exists
					if config.depend and type(config.depend) == "table" then
						for _, dep in ipairs(config.depend) do
							if type(dep) == "string" and dep ~= "" then
								table.insert(plugin_config.depend, dep)
							end
						end
					end

					table.insert(configs, plugin_config)
				end
			end
		end
	end

	return configs
end

return M

