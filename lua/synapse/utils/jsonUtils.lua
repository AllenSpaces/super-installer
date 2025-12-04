local M = {}

--- Format JSON data with proper indentation
--- @param data table|string|number|boolean|nil The data to format
--- @param indent number Current indentation level
--- @return string Formatted JSON string
local function formatJson(data, indent)
	indent = indent or 0
	local indentStr = string.rep("  ", indent)
	local nextIndentStr = string.rep("  ", indent + 1)
	
	if type(data) == "table" then
		-- Check if it's an array (only numeric keys starting from 1, consecutive)
		local isArray = true
		local keyCount = 0
		local maxIndex = 0
		
		for k, _ in pairs(data) do
			keyCount = keyCount + 1
			if type(k) == "number" and k >= 1 and k == math.floor(k) then
				if k > maxIndex then
					maxIndex = k
				end
			else
				isArray = false
				break
			end
		end
		
		-- Empty table is treated as array
		if keyCount == 0 then
			isArray = true
		elseif isArray then
			-- Check if keys form consecutive sequence: 1, 2, 3, ..., maxIndex
			isArray = (maxIndex == keyCount)
		end
		
		if isArray then
			-- It's an array
			if #data == 0 then
				return "[]"
			end
			local items = {}
			for i, v in ipairs(data) do
				table.insert(items, nextIndentStr .. formatJson(v, indent + 1))
			end
			return "[\n" .. table.concat(items, ",\n") .. "\n" .. indentStr .. "]"
		else
			-- It's an object
			local keys = {}
			for k, _ in pairs(data) do
				table.insert(keys, k)
			end
			table.sort(keys, function(a, b)
				-- Sort keys: total, update_time, hash first (root level), then plugins
				-- For plugin objects: name, repo, branch, tag, depend
				local rootOrder = { total = 1, update_time = 2, hash = 3, plugins = 4 }
				local pluginOrder = { name = 1, repo = 2, branch = 3, tag = 4, depend = 5 }
				local aOrder = rootOrder[a] or pluginOrder[a] or 99
				local bOrder = rootOrder[b] or pluginOrder[b] or 99
				if aOrder ~= bOrder then
					return aOrder < bOrder
				end
				return tostring(a) < tostring(b)
			end)
			
			if #keys == 0 then
				return "{}"
			end
			
			local items = {}
			for _, k in ipairs(keys) do
				local keyStr = '"' .. tostring(k):gsub('"', '\\"') .. '"'
				local valueStr = formatJson(data[k], indent + 1)
				table.insert(items, nextIndentStr .. keyStr .. ": " .. valueStr)
			end
			return "{\n" .. table.concat(items, ",\n") .. "\n" .. indentStr .. "}"
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

--- Write JSON data to file with formatting
--- @param filepath string Path to the JSON file
--- @param data table Data to write
--- @return boolean success Whether the operation succeeded
--- @return string|nil error Error message if failed
function M.write(filepath, data)
	local jsonStr = formatJson(data, 0)
	-- Ensure file ends with newline
	if not jsonStr:match("\n$") then
		jsonStr = jsonStr .. "\n"
	end
	
	local ok, err = pcall(function()
		local file = io.open(filepath, "w")
		if not file then
			error("Failed to open file: " .. filepath)
		end
		file:write(jsonStr)
		file:close()
	end)
	
	if not ok then
		return false, err
	end
	
	return true, nil
end

--- Read JSON file and parse it
--- @param filepath string Path to the JSON file
--- @return table|nil data Parsed JSON data
--- @return string|nil error Error message if failed
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
	local okParse, data = pcall(vim.json.decode, content)
	if not okParse then
		return nil, "Failed to parse JSON: " .. tostring(data)
	end
	
	return data, nil
end

--- Get the path to synapse.json file
--- @param packagePath string Base package path
--- @return string Full path to synapse.json
function M.getJsonPath(packagePath)
	return packagePath .. "/synapse.json"
end

return M

