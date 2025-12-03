local M = {}

--- Format JSON with indentation
--- @param data table
--- @param indent number
--- @return string
local function format_json(data, indent)
	indent = indent or 0
	local indent_str = string.rep("  ", indent)
	local next_indent_str = string.rep("  ", indent + 1)
	
	if type(data) == "table" then
		-- Check if it's an array
		-- An array is a table with only numeric keys starting from 1, consecutive
		local is_array = true
		local key_count = 0
		local max_index = 0
		
		for k, _ in pairs(data) do
			key_count = key_count + 1
			if type(k) == "number" and k >= 1 and k == math.floor(k) then
				if k > max_index then
					max_index = k
				end
			else
				is_array = false
				break
			end
		end
		
		-- If empty table, treat as array (for depend field, etc.)
		-- If has keys, check if they form a consecutive sequence from 1
		if key_count == 0 then
			is_array = true
		elseif is_array then
			-- Check if keys form consecutive sequence: 1, 2, 3, ..., max_index
			is_array = (max_index == key_count)
		end
		
		if is_array then
			-- It's an array
			if #data == 0 then
				return "[]"
			end
			local items = {}
			for i, v in ipairs(data) do
				table.insert(items, next_indent_str .. format_json(v, indent + 1))
			end
			return "[\n" .. table.concat(items, ",\n") .. "\n" .. indent_str .. "]"
		else
			-- It's an object
			local keys = {}
			for k, _ in pairs(data) do
				table.insert(keys, k)
			end
			table.sort(keys, function(a, b)
				-- Sort keys: total, update_time, hash first (root level), then plugins
				-- For plugin objects: name, repo, branch, tag, depend
				local root_order = { total = 1, update_time = 2, hash = 3, plugins = 4 }
				local plugin_order = { name = 1, repo = 2, branch = 3, tag = 4, depend = 5 }
				local a_order = root_order[a] or plugin_order[a] or 99
				local b_order = root_order[b] or plugin_order[b] or 99
				if a_order ~= b_order then
					return a_order < b_order
				end
				return tostring(a) < tostring(b)
			end)
			
			if #keys == 0 then
				return "{}"
			end
			
			local items = {}
			for _, k in ipairs(keys) do
				local key_str = '"' .. tostring(k):gsub('"', '\\"') .. '"'
				local value_str = format_json(data[k], indent + 1)
				table.insert(items, next_indent_str .. key_str .. ": " .. value_str)
			end
			return "{\n" .. table.concat(items, ",\n") .. "\n" .. indent_str .. "}"
		end
	elseif type(data) == "string" then
		-- Escape special characters
		local escaped = data
			:gsub("\\", "\\\\")
			:gsub('"', '\\"')
			:gsub("\n", "\\n")
			:gsub("\r", "\\r")
			:gsub("\t", "\\t")
		return '"' .. escaped .. '"'
	elseif type(data) == "number" then
		return tostring(data)
	elseif type(data) == "boolean" then
		return data and "true" or "false"
	elseif data == nil then
		return "null"
	else
		return '"' .. tostring(data):gsub('"', '\\"') .. '"'
	end
end

--- Write JSON file with formatting
--- @param filepath string
--- @param data table
--- @return boolean success
--- @return string|nil error
function M.write(filepath, data)
	local json_str = format_json(data, 0)
	-- Ensure file ends with newline
	if not json_str:match("\n$") then
		json_str = json_str .. "\n"
	end
	
	local ok, err = pcall(function()
		local file = io.open(filepath, "w")
		if not file then
			error("Failed to open file: " .. filepath)
		end
		file:write(json_str)
		file:close()
	end)
	
	if not ok then
		return false, err
	end
	
	return true, nil
end

--- Read JSON file
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
	
	-- Use vim.json for parsing JSON (available in Neovim 0.7+)
	local ok_parse, data = pcall(vim.json.decode, content)
	if not ok_parse then
		-- Fallback: try to parse manually for simple cases
		-- For now, return error
		return nil, "Failed to parse JSON: " .. tostring(data)
	end
	
	return data, nil
end

--- Get synapse.json file path
--- @param package_path string
--- @return string
function M.get_json_path(package_path)
	return package_path .. "/synapse.json"
end

return M

