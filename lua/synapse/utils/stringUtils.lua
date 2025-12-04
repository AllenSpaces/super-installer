local fn = vim.fn

local M = {}

--- Get display width of text (handles multi-byte characters)
--- @param text string Text to measure
--- @return number Display width
function M.displayWidth(text)
	return fn.strdisplaywidth(text or "")
end

--- Center text within a given width
--- @param text string Text to center
--- @param width number Total width
--- @return string centeredText Centered text
--- @return number leftPadding Left padding size
function M.centerText(text, width)
	local padding = math.max(0, width - M.displayWidth(text))
	local left = math.floor(padding / 2)
	local right = padding - left
	return string.rep(" ", left) .. text .. string.rep(" ", right), left
end

--- Resolve icon from various formats (table or string)
--- @param icon string|table Icon in various formats
--- @return string Icon glyph/character
function M.resolveIcon(icon)
	if type(icon) == "table" then
		return icon.glyph or icon.text or icon.icon or icon[1]
	end
	return icon
end

--- Normalize header to array of strings
--- @param header string|table Header in various formats
--- @return table Array of header lines
function M.normalizeHeader(header)
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
--- @param repo string Repository path (e.g., "user/repo" or "user/repo.git")
--- @return string Clean plugin name
function M.getPluginName(repo)
	assert(type(repo) == "string" and repo ~= "", "Invalid repo: " .. tostring(repo))
	local pluginName = repo:match("([^/]+)$") or repo
	local cleanName = pluginName:gsub("%.git$", "")
	return cleanName
end

return M

