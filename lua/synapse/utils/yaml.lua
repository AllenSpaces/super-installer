local M = {}

--- Escape YAML string
--- @param str string
--- @return string
local function escape_yaml(str)
	if type(str) ~= "string" then
		return tostring(str)
	end
	-- Simple escaping for basic cases
	if str:match("^[a-zA-Z0-9_/-]+$") then
		return str
	end
	-- Quote if contains special characters
	return '"' .. str:gsub('"', '\\"') .. '"'
end

--- Write YAML file
--- @param filepath string
--- @param data table
--- @return boolean success
--- @return string|nil error
function M.write(filepath, data)
	local lines = {}
	
	if data.plugins and type(data.plugins) == "table" then
		table.insert(lines, "plugins:")
		for _, plugin in ipairs(data.plugins) do
			table.insert(lines, "  - name: " .. escape_yaml(plugin.name))
			if plugin.repo then
				table.insert(lines, "    repo: " .. escape_yaml(plugin.repo))
			end
			-- Only write branch if it exists and is not the default "main"
			if plugin.branch and plugin.branch ~= "main" and plugin.branch ~= "master" then
				table.insert(lines, "    branch: " .. escape_yaml(plugin.branch))
			end
			if plugin.depend and type(plugin.depend) == "table" and #plugin.depend > 0 then
				table.insert(lines, "    depend:")
				for _, dep in ipairs(plugin.depend) do
					table.insert(lines, "      - " .. escape_yaml(dep))
				end
			end
		end
	end
	
	local content = table.concat(lines, "\n") .. "\n"
	
	local ok, err = pcall(function()
		local file = io.open(filepath, "w")
		if not file then
			error("Failed to open file: " .. filepath)
		end
		file:write(content)
		file:close()
	end)
	
	if not ok then
		return false, err
	end
	
	return true, nil
end

--- Read YAML file
--- @param filepath string
--- @return table|nil data
--- @return string|nil error
function M.read(filepath)
	if vim.fn.filereadable(filepath) ~= 1 then
		return nil, "File not found"
	end
	
	local ok, content = pcall(function()
		local file = io.open(filepath, "r")
		if not file then
			error("Failed to open file: " .. filepath)
		end
		local data = file:read("*a")
		file:close()
		return data
	end)
	
	if not ok then
		return nil, content
	end
	
	-- Simple YAML parser for our specific format
	local data = { plugins = {} }
	local current_plugin = nil
	local in_depend = false
	
	for line in content:gmatch("[^\r\n]+") do
		local trimmed = line:match("^%s*(.-)%s*$") -- trim
		local indent = #line - #trimmed
		
		if trimmed:match("^plugins:") then
			-- Start of plugins section
		elseif indent == 2 and trimmed:match("^%- name:") then
			-- New plugin (indent level 2)
			if current_plugin then
				table.insert(data.plugins, current_plugin)
			end
			local name = trimmed:match("name:%s*(.+)")
			if name then
				name = name:gsub('^"', ""):gsub('"$', ""):gsub('\\"', '"')
				current_plugin = { name = name, depend = {} }
				in_depend = false
			end
		elseif current_plugin and indent == 4 and trimmed:match("^repo:") then
			-- Repo field (indent level 4)
			local repo = trimmed:match("repo:%s*(.+)")
			if repo then
				repo = repo:gsub('^"', ""):gsub('"$', ""):gsub('\\"', '"')
				current_plugin.repo = repo
			end
			in_depend = false
		elseif current_plugin and indent == 4 and trimmed:match("^branch:") then
			-- Branch field (indent level 4)
			local branch = trimmed:match("branch:%s*(.+)")
			if branch then
				branch = branch:gsub('^"', ""):gsub('"$', ""):gsub('\\"', '"')
				current_plugin.branch = branch
			end
			in_depend = false
		elseif current_plugin and indent == 4 and trimmed:match("^depend:") then
			-- Depend section (indent level 4)
			in_depend = true
		elseif in_depend and indent == 6 and trimmed:match("^%-") then
			-- Dependency item (indent level 6)
			local dep = trimmed:match("%-%s*(.+)")
			if dep then
				dep = dep:gsub('^"', ""):gsub('"$', ""):gsub('\\"', '"')
				table.insert(current_plugin.depend, dep)
			end
		elseif trimmed ~= "" and indent <= 2 then
			-- New section or end of depend
			in_depend = false
		end
	end
	
	-- Add last plugin
	if current_plugin then
		table.insert(data.plugins, current_plugin)
	end
	
	return data, nil
end

--- Get synapse.yaml file path
--- @param package_path string
--- @return string
function M.get_yaml_path(package_path)
	return package_path .. "/synapse.yaml"
end

return M

