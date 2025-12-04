local api = vim.api
local config = require("synapse.config")

local colors = {
	header = "#e6d5fb",
	plugin = "#d5fbd9",
	progress = "#fbe4d5",
}

local M = {}

-- Cache for auto-generated highlight groups from hex colors
local colorHlCache = {}

--- Check if a string is a hex color
--- @param str string String to check
--- @return boolean True if string is a hex color
local function isHexColor(str)
	return type(str) == "string" and str:match("^#%x%x%x%x%x%x$") ~= nil
end

--- Get or create highlight group for hex color
--- @param color string Hex color like "#bbc0ed"
--- @param prefix string Prefix for highlight group name
--- @return string Highlight group name
local function getColorHl(color, prefix)
	if not colorHlCache[color] then
		local hlName = "Synapse" .. prefix .. "Color" .. #colorHlCache
		api.nvim_set_hl(0, hlName, { fg = color })
		colorHlCache[color] = hlName
	end
	return colorHlCache[color]
end

--- Resolve highlight group name or color
--- @param hlValue string|nil Highlight group name or hex color
--- @param defaultPath string Config path for default value
--- @param defaultColor string|nil Default color if hl is nil
--- @param prefix string Prefix for auto-generated highlight group
--- @return string Highlight group name
local function resolveHl(hlValue, defaultPath, defaultColor, prefix)
	if not hlValue then
		hlValue = getDefaultHl(defaultPath) or defaultColor
	end
	
	if isHexColor(hlValue) then
		return getColorHl(hlValue, prefix)
	end
	
	return hlValue
end

--- Get default highlight name from config
--- @param path string Config path like "header.hl" or "icons.success.hl"
--- @return string|nil Highlight group name or nil
local function getDefaultHl(path)
	local defaultUi = config.default.opts.ui
	local parts = vim.split(path, ".", { plain = true })
	local value = defaultUi
	for _, part in ipairs(parts) do
		if value and type(value) == "table" and value[part] then
			value = value[part]
		else
			return nil
		end
	end
	return type(value) == "string" and value or nil
end

--- Ensure all highlight groups are defined
--- @param ui table|nil UI configuration
--- @param state table State table
function M.ensureHighlights(ui, state)
	-- Get default config if ui is nil
	local defaultUi = config.default.opts.ui
	
	-- Set header highlight from config (supports hex color)
	local headerHlValue = (ui and ui.header and ui.header.hl) or getDefaultHl("header.hl")
	local headerHl = resolveHl(headerHlValue, "header.hl", colors.header, "Header")
	if isHexColor(headerHlValue) then
		api.nvim_set_hl(0, headerHl, { fg = headerHlValue, bold = true })
	else
		api.nvim_set_hl(0, headerHl, { fg = colors.header, bold = true })
	end
	state.headerHl = headerHl

	-- Set plugin highlight from config (supports hex color)
	local pluginHlValue = (ui and ui.plug and ui.plug.hl) or getDefaultHl("plug.hl")
	local pluginHl = resolveHl(pluginHlValue, "plug.hl", colors.plugin, "Plugin")
	if isHexColor(pluginHlValue) then
		api.nvim_set_hl(0, pluginHl, { fg = pluginHlValue })
	else
		api.nvim_set_hl(0, pluginHl, { fg = colors.plugin })
	end
	state.pluginHl = pluginHl

	-- Set progress highlight groups from config (supports hex color)
	local progressCfg = (ui and ui.icons and ui.icons.progress) or defaultUi.icons.progress
	local progressHlCfg = progressCfg.hl or {}
	local defaultHlValue = progressHlCfg.default or getDefaultHl("icons.progress.hl.default")
	local progressHlValue = progressHlCfg.progress or getDefaultHl("icons.progress.hl.progress")
	local defaultColor = progressHlCfg.defaultColor or "#5c6370"
	local progressColor = progressHlCfg.progressColor or colors.progress
	
	local defaultHl = resolveHl(defaultHlValue, "icons.progress.hl.default", defaultColor, "ProgressDefault")
	local progressHl = resolveHl(progressHlValue, "icons.progress.hl.progress", progressColor, "Progress")
	
	if isHexColor(defaultHlValue) then
		api.nvim_set_hl(0, defaultHl, { fg = defaultHlValue })
	else
		api.nvim_set_hl(0, defaultHl, { fg = defaultColor })
	end
	
	if isHexColor(progressHlValue) then
		api.nvim_set_hl(0, progressHl, { fg = progressHlValue })
	else
		api.nvim_set_hl(0, progressHl, { fg = progressColor })
	end
	
	state.progressHl = {
		default = defaultHl,
		progress = progressHl,
	}

	-- Set success and failure highlight groups from config (supports hex color)
	local successCfg = (ui and ui.icons and ui.icons.success) or defaultUi.icons.success
	local successHlValue = successCfg.hl or getDefaultHl("icons.success.hl")
	local successHl = resolveHl(successHlValue, "icons.success.hl", "#bbc0ed", "Success")
	if isHexColor(successHlValue) then
		api.nvim_set_hl(0, successHl, { fg = successHlValue })
	else
		api.nvim_set_hl(0, successHl, { fg = "#bbc0ed" })
	end
	state.successHl = successHl

	local faildCfg = (ui and ui.icons and ui.icons.faild) or defaultUi.icons.faild
	local faildHlValue = faildCfg.hl or getDefaultHl("icons.faild.hl")
	local faildHl = resolveHl(faildHlValue, "icons.faild.hl", "#edbbbb", "Faild")
	if isHexColor(faildHlValue) then
		api.nvim_set_hl(0, faildHl, { fg = faildHlValue })
	else
		api.nvim_set_hl(0, faildHl, { fg = "#edbbbb" })
	end
	state.faildHl = faildHl

	-- Set icon highlight groups from config (download, upgrade, remove, check, package) (supports hex color)
	local iconTypes = { "download", "upgrade", "remove", "check", "package" }
	for _, iconType in ipairs(iconTypes) do
		local iconCfg = (ui and ui.icons and ui.icons[iconType]) or defaultUi.icons[iconType]
		if iconCfg and iconCfg.hl then
			local iconHl = resolveHl(iconCfg.hl, "icons." .. iconType .. ".hl", colors.progress, iconType:sub(1, 1):upper() .. iconType:sub(2))
			if isHexColor(iconCfg.hl) then
				api.nvim_set_hl(0, iconHl, { fg = iconCfg.hl })
			else
				api.nvim_set_hl(0, iconHl, { fg = colors.progress })
			end
		end
	end

	-- Set default icon highlight (use download icon hl as fallback) (supports hex color)
	local downloadCfg = (ui and ui.icons and ui.icons.download) or defaultUi.icons.download
	local downloadHlValue = downloadCfg and downloadCfg.hl or getDefaultHl("icons.download.hl")
	state.iconHl = resolveHl(downloadHlValue, "icons.download.hl", colors.progress, "Icon")
end

-- Backward compatibility alias
function M.ensure_highlights(ui, state)
	return M.ensureHighlights(ui, state)
end

return M
