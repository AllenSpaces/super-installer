local api = vim.api
local config = require("synapse.config")

local colors = {
	header = "#e6d5fb",
	plugin = "#d5fbd9",
	progress = "#fbe4d5",
}

local M = {}

-- Cache for auto-generated highlight groups from hex colors
local color_hl_cache = {}

--- Check if a string is a hex color
--- @param str string
--- @return boolean
local function is_hex_color(str)
	return type(str) == "string" and str:match("^#%x%x%x%x%x%x$") ~= nil
end

--- Get or create highlight group for hex color
--- @param color string hex color like "#bbc0ed"
--- @param prefix string prefix for highlight group name
--- @return string highlight group name
local function get_color_hl(color, prefix)
	if not color_hl_cache[color] then
		local hl_name = "Synapse" .. prefix .. "Color" .. #color_hl_cache
		api.nvim_set_hl(0, hl_name, { fg = color })
		color_hl_cache[color] = hl_name
	end
	return color_hl_cache[color]
end

--- Resolve highlight group name or color
--- @param hl_value string|nil highlight group name or hex color
--- @param default_path string config path for default value
--- @param default_color string|nil default color if hl is nil
--- @param prefix string prefix for auto-generated highlight group
--- @return string highlight group name
local function resolve_hl(hl_value, default_path, default_color, prefix)
	if not hl_value then
		hl_value = get_default_hl(default_path) or default_color
	end
	
	if is_hex_color(hl_value) then
		return get_color_hl(hl_value, prefix)
	end
	
	return hl_value
end

--- Get default highlight name from config
--- @param path string config path like "header.hl" or "icons.success.hl"
--- @return string|nil
local function get_default_hl(path)
	local default_ui = config.default.opts.ui
	local parts = vim.split(path, ".", { plain = true })
	local value = default_ui
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
--- @param ui table|nil
--- @param state table
function M.ensure_highlights(ui, state)
	-- Get default config if ui is nil
	local default_ui = config.default.opts.ui
	
	-- Set header highlight from config (supports hex color)
	local header_hl_value = (ui and ui.header and ui.header.hl) or get_default_hl("header.hl")
	local header_hl = resolve_hl(header_hl_value, "header.hl", colors.header, "Header")
	if is_hex_color(header_hl_value) then
		api.nvim_set_hl(0, header_hl, { fg = header_hl_value, bold = true })
	else
		api.nvim_set_hl(0, header_hl, { fg = colors.header, bold = true })
	end
	state.header_hl = header_hl

	-- Set plugin highlight from config (supports hex color)
	local plugin_hl_value = (ui and ui.plug and ui.plug.hl) or get_default_hl("plug.hl")
	local plugin_hl = resolve_hl(plugin_hl_value, "plug.hl", colors.plugin, "Plugin")
	if is_hex_color(plugin_hl_value) then
		api.nvim_set_hl(0, plugin_hl, { fg = plugin_hl_value })
	else
		api.nvim_set_hl(0, plugin_hl, { fg = colors.plugin })
	end
	state.plugin_hl = plugin_hl

	-- Set progress highlight groups from config (supports hex color)
	local progress_cfg = (ui and ui.icons and ui.icons.progress) or default_ui.icons.progress
	local progress_hl_cfg = progress_cfg.hl or {}
	local default_hl_value = progress_hl_cfg.default or get_default_hl("icons.progress.hl.default")
	local progress_hl_value = progress_hl_cfg.progress or get_default_hl("icons.progress.hl.progress")
	local default_color = progress_hl_cfg.default_color or "#5c6370"
	local progress_color = progress_hl_cfg.progress_color or colors.progress
	
	local default_hl = resolve_hl(default_hl_value, "icons.progress.hl.default", default_color, "ProgressDefault")
	local progress_hl = resolve_hl(progress_hl_value, "icons.progress.hl.progress", progress_color, "Progress")
	
	if is_hex_color(default_hl_value) then
		api.nvim_set_hl(0, default_hl, { fg = default_hl_value })
	else
		api.nvim_set_hl(0, default_hl, { fg = default_color })
	end
	
	if is_hex_color(progress_hl_value) then
		api.nvim_set_hl(0, progress_hl, { fg = progress_hl_value })
	else
		api.nvim_set_hl(0, progress_hl, { fg = progress_color })
	end
	
	state.progress_hl = {
		default = default_hl,
		progress = progress_hl,
	}

	-- Set success and failure highlight groups from config (supports hex color)
	local success_cfg = (ui and ui.icons and ui.icons.success) or default_ui.icons.success
	local success_hl_value = success_cfg.hl or get_default_hl("icons.success.hl")
	local success_hl = resolve_hl(success_hl_value, "icons.success.hl", "#bbc0ed", "Success")
	if is_hex_color(success_hl_value) then
		api.nvim_set_hl(0, success_hl, { fg = success_hl_value })
	else
		api.nvim_set_hl(0, success_hl, { fg = "#bbc0ed" })
	end
	state.success_hl = success_hl

	local faild_cfg = (ui and ui.icons and ui.icons.faild) or default_ui.icons.faild
	local faild_hl_value = faild_cfg.hl or get_default_hl("icons.faild.hl")
	local faild_hl = resolve_hl(faild_hl_value, "icons.faild.hl", "#edbbbb", "Faild")
	if is_hex_color(faild_hl_value) then
		api.nvim_set_hl(0, faild_hl, { fg = faild_hl_value })
	else
		api.nvim_set_hl(0, faild_hl, { fg = "#edbbbb" })
	end
	state.faild_hl = faild_hl

	-- Set icon highlight groups from config (download, upgrade, remove, check, package) (supports hex color)
	local icon_types = { "download", "upgrade", "remove", "check", "package" }
	for _, icon_type in ipairs(icon_types) do
		local icon_cfg = (ui and ui.icons and ui.icons[icon_type]) or default_ui.icons[icon_type]
		if icon_cfg and icon_cfg.hl then
			local icon_hl = resolve_hl(icon_cfg.hl, "icons." .. icon_type .. ".hl", colors.progress, icon_type:sub(1, 1):upper() .. icon_type:sub(2))
			if is_hex_color(icon_cfg.hl) then
				api.nvim_set_hl(0, icon_hl, { fg = icon_cfg.hl })
			else
				api.nvim_set_hl(0, icon_hl, { fg = colors.progress })
			end
		end
	end

	-- Set default icon highlight (use download icon hl as fallback) (supports hex color)
	local download_cfg = (ui and ui.icons and ui.icons.download) or default_ui.icons.download
	local download_hl_value = download_cfg and download_cfg.hl or get_default_hl("icons.download.hl")
	state.icon_hl = resolve_hl(download_hl_value, "icons.download.hl", colors.progress, "Icon")
end

return M

