local M = {}

--- Parse a dependency item (supports both string and table formats)
--- @param dep string|table Dependency item (string: "user/repo", table: { "user/repo", primary = "...", opt = {...} })
--- @return string repo Repository path
--- @return string|nil primary Primary plugin name
--- @return table|nil opt Optional configuration table
function M.parse_dependency(dep)
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

--- Load all configuration files from config_path (recursive scan)
--- Only scans .config.lua files
--- @param config_path string
--- @return table
function M.load_config_files(config_path)
	local configs = {}

	if not config_path or config_path == "" then
		return configs
	end

	if vim.fn.isdirectory(config_path) ~= 1 then
		return configs
	end

	-- Recursively get all .config.lua files
	local lua_files = vim.fn.globpath(config_path, "**/*.config.lua", true, true)

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
						-- Don't set branch by default, only use it if explicitly specified
						branch = nil,
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
							local repo, primary, opt = M.parse_dependency(dep)
							if repo and repo ~= "" then
								-- Store as table format: { repo, primary = primary, opt = opt }
								if primary or opt then
									local dep_item = { repo }
									if primary then
										dep_item.primary = primary
									end
									if opt then
										dep_item.opt = opt
									end
									table.insert(plugin_config.depend, dep_item)
								else
									-- Keep string format for backward compatibility
									table.insert(plugin_config.depend, repo)
								end
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
