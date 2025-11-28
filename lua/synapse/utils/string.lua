local fn = vim.fn

local M = {}

--- Get display width of text (handles multi-byte characters)
--- @param text string
--- @return number
function M.display_width(text)
	return fn.strdisplaywidth(text or "")
end

--- Center text within a given width
--- @param text string
--- @param width number
--- @return string, number -- centered text, left padding
function M.center_text(text, width)
	local padding = math.max(0, width - M.display_width(text))
	local left = math.floor(padding / 2)
	local right = padding - left
	return string.rep(" ", left) .. text .. string.rep(" ", right), left
end

--- Resolve icon from various formats
--- @param icon string|table
--- @return string
function M.resolve_icon(icon)
	if type(icon) == "table" then
		return icon.glyph or icon.text or icon.icon or icon[1]
	end
	return icon
end

--- Normalize header to array of strings
--- @param header string|table
--- @return table
function M.normalize_header(header)
	if type(header) == "table" then
		if #header == 0 then
			return { "Synapse" }
		end
		local copy = {}
		for _, line in ipairs(header) do
			table.insert(copy, line)
		end
		return copy
	end

	if type(header) == "string" then
		local lines = vim.split(header, "\n", { plain = true })
		local normalized = {}
		for _, line in ipairs(lines) do
			if line ~= "" then
				table.insert(normalized, line)
			end
		end
		if #normalized == 0 then
			return { "Synapse" }
		end
		return normalized
	end

	return { "Synapse" }
end

--- Extract plugin name from repository string
--- @param repo string
--- @return string
function M.get_plugin_name(repo)
	assert(type(repo) == "string" and repo ~= "", "Invalid repo: " .. tostring(repo))
	local plugin_name = repo:match("([^/]+)$") or repo
	local clean_name = plugin_name:gsub("%.git$", "")
	return clean_name
end

return M

