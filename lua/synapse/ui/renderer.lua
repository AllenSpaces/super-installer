local api = vim.api

local PADDING = 1
local namespace = api.nvim_create_namespace("SynapseUI")

local string_utils = require("synapse.utils.string")
local state = require("synapse.ui.state")

local M = {}

--- Push a line to line_specs
--- @param line_specs table
--- @param content_width table
--- @param text string
--- @param opts table|nil
--- @return number
local function push_line(line_specs, content_width, text, opts)
	opts = opts or {}
	local width = string_utils.display_width(text)
	content_width.value = math.max(content_width.value, width)
	table.insert(line_specs, {
		text = text,
		align = opts.align or "left",
		kind = opts.kind,
		meta = opts.meta,
	})
	return #line_specs
end

--- Render progress window
--- @param win table
--- @param ui table|nil
function M.render_progress(win, ui)
	if
		not (
			win
			and win.win_id
			and api.nvim_win_is_valid(win.win_id)
			and win.buf
			and api.nvim_buf_is_valid(win.buf)
		)
	then
		return
	end

	local side_padding = PADDING
	local vertical_padding = PADDING
	local line_specs = {}
	local content_width = { value = 0 }

	-- Header
	for _, header_text in ipairs(state.state.header_lines or { state.state.header or "Synapse" }) do
		push_line(line_specs, content_width, header_text, { kind = "header", align = "center" })
	end
	push_line(line_specs, content_width, "")

	-- Plugin list
	local visible_plugins
	if state.state.show_failures then
		visible_plugins = {}
		for _, name in ipairs(state.state.failed_plugins) do
			table.insert(visible_plugins, {
				name = name,
				status = "failed",
				failure = true,
				icon = state.state.failure_icon,
				icon_hl = state.state.failure_icon_hl,
			})
		end
	else
		visible_plugins = state.state.display
	end

	local screen_width = vim.o.columns
	local screen_height = vim.o.lines
	local max_width = math.max(20, screen_width - 4)
	local inner_limit = math.max(10, max_width - side_padding * 2)

	local filled_slots = 0
	for _, item in ipairs(visible_plugins) do
		if filled_slots >= state.state.max_visible then
			break
		end
		local icon = item.failure and (state.state.failure_icon or "")
			or (item.status == "failed" and (state.state.failure_icon or ""))
			or item.icon
		local text = string.format("%s %s", icon, item.name)
		push_line(line_specs, content_width, text, {
			kind = "plugin",
			meta = {
				icon = icon,
				name = item.name,
				failure = item.failure or item.status == "failed",
				icon_hl = item.icon_hl,
			},
			align = "center",
		})
		filled_slots = filled_slots + 1
	end

	-- Fill remaining slots with empty lines
	while filled_slots < state.state.max_visible do
		push_line(line_specs, content_width, " ", { kind = "plugin", align = "center", meta = { icon = "", name = "" } })
		filled_slots = filled_slots + 1
	end

	push_line(line_specs, content_width, "")

	-- Progress bar
	if not state.state.show_failures then
		local ratio = state.progress_ratio()
		local progress_icon = "Progress"
		local bar_width = math.max(10, math.min(content_width.value, inner_limit) - 6)
		local filled = math.floor(bar_width * ratio)
		local empty = math.max(0, bar_width - filled)
		local glyph = ui.icons.progress.glyph or "■"
		local glyph_bytes = #glyph
		local bar = string.rep(glyph, filled) .. string.rep(glyph, empty)
		local meta = string.format("%d/%d (%d%%)", state.state.completed, state.state.total, math.floor(ratio * 100))
		local progress_content = string.format("%s %s %s", progress_icon, bar, meta)
		push_line(line_specs, content_width, progress_content, {
			kind = "progress",
			meta = {
				filled = filled,
				empty = empty,
				label_len = string_utils.display_width(progress_icon .. " "),
				label_bytes = #(progress_icon .. " "),
				bar_width = bar_width,
				glyph_bytes = glyph_bytes,
			},
			align = "center",
		})
		push_line(line_specs, content_width, "")
	end

	-- Instructions
	local instructions
	if state.state.show_failures then
		instructions = "Press : 󰫾 | 󰫲󱎤󰫰 Quit · 󰫿 Retry"
	else
		instructions = "Press : 󰫾 | 󰫲󱎤󰫰 Quit"
	end
	push_line(line_specs, content_width, instructions, { align = "center" })

	-- Vertical padding
	if vertical_padding > 0 then
		for _ = 1, vertical_padding do
			table.insert(line_specs, 1, { text = "", align = "left", kind = "pad" })
		end
		for _ = 1, vertical_padding do
			table.insert(line_specs, { text = "", align = "left", kind = "pad" })
		end
	end

	-- Calculate dimensions
	local inner_width = math.min(inner_limit, math.max(content_width.value, 40))
	local target_width = math.min(max_width, inner_width + side_padding * 2)
	inner_width = target_width - side_padding * 2

	local target_height = math.min(screen_height - 4, math.max(#line_specs, 10))

	-- Update window config
	api.nvim_win_set_config(win.win_id, {
		relative = "editor",
		width = target_width,
		height = target_height,
		col = math.floor((screen_width - target_width) / 2),
		row = math.floor((screen_height - target_height) / 2),
	})

	-- Render lines
	local rendered_lines = {}
	local header_lines = {}
	local plugin_highlights = {}
	local progress_line = nil

	for idx, spec in ipairs(line_specs) do
		local center_shift = 0
		if spec.kind == "pad" then
			rendered_lines[idx] = string.rep(" ", target_width)
		elseif spec.align == "center" then
			local centered
			centered, center_shift = string_utils.center_text(spec.text, inner_width)
			rendered_lines[idx] = string.rep(" ", side_padding) .. centered .. string.rep(" ", side_padding)
			if spec.kind == "header" then
				table.insert(header_lines, idx)
			end
			spec.center_offset = center_shift
		else
			local padded = spec.text
			local padding_needed = inner_width - string_utils.display_width(padded)
			if padding_needed > 0 then
				padded = padded .. string.rep(" ", padding_needed)
			end
			rendered_lines[idx] = string.rep(" ", side_padding) .. padded .. string.rep(" ", side_padding)
			spec.center_offset = 0
		end

		if spec.kind == "pad" then
			-- skip highlight
		elseif spec.kind == "plugin" and spec.meta then
			local icon = spec.meta.icon or ""
			local name = spec.meta.name or ""
			local icon_bytes = #icon
			local name_bytes = #name
			local icon_col = side_padding + center_shift
			local icon_end = icon_col + icon_bytes
			local name_col = icon_end + 1
			local name_end = name_col + name_bytes
			table.insert(plugin_highlights, {
				line = idx,
				icon_col = icon_col,
				icon_end = icon_end,
				name_col = name_col,
				name_end = name_end,
				failure = spec.meta.failure,
				icon_hl = spec.meta.icon_hl,
			})
		elseif spec.kind == "progress" then
			progress_line = idx
		end
	end

	-- Set buffer lines
	api.nvim_buf_set_lines(win.buf, 0, -1, false, rendered_lines)
	api.nvim_buf_clear_namespace(win.buf, namespace, 0, -1)

	-- Apply highlights
	for _, header_idx in ipairs(header_lines) do
		api.nvim_buf_add_highlight(win.buf, namespace, "SynapseUIHeader", header_idx - 1, 0, -1)
	end

	for _, item in ipairs(plugin_highlights) do
		local line = item.line - 1
		local icon_hl = item.icon_hl
			or (item.failure and (state.state.failure_icon_hl or state.state.icon_hl) or state.state.icon_hl)
		api.nvim_buf_add_highlight(
			win.buf,
			namespace,
			icon_hl or "SynapseUIIcon",
			line,
			item.icon_col,
			item.icon_end
		)
		api.nvim_buf_add_highlight(
			win.buf,
			namespace,
			"SynapseUIPlugin",
			line,
			item.name_col,
			item.name_end
		)
	end

	-- Progress bar highlights
	if progress_line then
		local line = progress_line - 1
		local spec = line_specs[progress_line]
		local meta = spec.meta or {}
		local center_shift = spec.center_offset or 0
		local label_bytes = meta.label_bytes or #("Progress ")
		local glyph_bytes = meta.glyph_bytes or 1
		local bar_width = meta.bar_width or 0
		local filled = meta.filled or 0

		-- Calculate byte positions
		local bar_start_col = side_padding + center_shift + label_bytes
		local bar_total_bytes = bar_width * glyph_bytes
		local filled_bytes = filled * glyph_bytes

		local default_hl = state.state.progress_hl.default or "SynapseProgressDefault"
		local progress_hl = state.state.progress_hl.progress or "SynapseUIProgress"

		-- Step 1: Initialize entire bar with default color (gray)
		if bar_total_bytes > 0 then
			api.nvim_buf_add_highlight(
				win.buf,
				namespace,
				default_hl,
				line,
				bar_start_col,
				bar_start_col + bar_total_bytes
			)
		end

		-- Step 2: Override filled portion with progress color
		if filled_bytes > 0 and filled_bytes <= bar_total_bytes then
			api.nvim_buf_add_highlight(
				win.buf,
				namespace,
				progress_hl,
				line,
				bar_start_col,
				bar_start_col + filled_bytes
			)
		end
	end
end

return M

