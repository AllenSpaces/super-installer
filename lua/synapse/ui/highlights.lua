local api = vim.api

local colors = {
	header = "#e6d5fb",
	plugin = "#d5fbd9",
	progress = "#fbe4d5",
}

local highlights_ready = false

local M = {}

--- Ensure all highlight groups are defined
--- @param ui table|nil
--- @param state table
function M.ensure_highlights(ui, state)
	if not highlights_ready then
		api.nvim_set_hl(0, "SynapseUIHeader", { fg = colors.header, bold = true })
		api.nvim_set_hl(0, "SynapseUIPlugin", { fg = colors.plugin })
		api.nvim_set_hl(0, "SynapseUIProgress", { fg = colors.progress })
		api.nvim_set_hl(0, "SynapseUIIcon", { fg = colors.progress })
		highlights_ready = true
	end

	if ui and ui.hl then
		if ui.hl:match("^#") then
			api.nvim_set_hl(0, "SynapseUIUserIcon", { fg = ui.hl })
			state.icon_hl = "SynapseUIUserIcon"
		else
			state.icon_hl = ui.hl
		end
	else
		state.icon_hl = "SynapseUIIcon"
	end

	local progress_cfg = ui and ui.icons and ui.icons.progress or {}
	local progress_hl_cfg = progress_cfg.hl or {}
	local default_hl = progress_hl_cfg.default or "SynapseProgressDefault"
	local progress_hl = progress_hl_cfg.progress or "SynapseUIProgress"
	local default_color = progress_hl_cfg.default_color or "#5c6370"
	local progress_color = progress_hl_cfg.progress_color or colors.progress
	api.nvim_set_hl(0, default_hl, { fg = default_color })
	api.nvim_set_hl(0, progress_hl, { fg = progress_color })
	state.progress_hl = {
		default = default_hl,
		progress = progress_hl,
	}
end

return M

