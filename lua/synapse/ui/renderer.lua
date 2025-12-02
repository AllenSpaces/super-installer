local api = vim.api

local VERTICAL_PADDING = 1
local HORIZONTAL_PADDING = 3
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

	-- Use same padding value for both horizontal and vertical
	local side_padding = HORIZONTAL_PADDING
	local vertical_padding = VERTICAL_PADDING
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
		local glyph = ui.icons.progress.glyph or "■"
		local glyph_bytes = #glyph
		local glyph_display_width = string_utils.display_width(glyph)
		
		-- Calculate percentage
		local percentage = math.floor(ratio * 100)
		local meta
		if percentage < 10 then
			-- 个位数：显示为 "01%"
			meta = string.format("0%d%%", percentage)
		else
			-- 十位数及以上：显示为 "10%"
			meta = string.format("%d%%", percentage)
		end
		local meta_display_width = string_utils.display_width(meta)
		
		-- Calculate base bar width
		local base_bar_width = math.max(10, math.min(content_width.value, inner_limit) - 6)
		
		-- Calculate how many glyphs the percentage text occupies
		-- Round up to ensure we have enough space
		local meta_glyph_count = math.ceil(meta_display_width / glyph_display_width)
		
		-- If percentage is 10+ digits, reduce one glyph to make room
		local bar_width = base_bar_width
		if percentage >= 10 then
			-- Reduce one glyph for 10+ digits
			bar_width = math.max(1, bar_width - 1)
		end
		
		-- Calculate where to insert percentage (middle of the bar)
		local mid_point = math.floor(bar_width / 2)
		local meta_start_glyph = math.max(0, mid_point - math.floor(meta_glyph_count / 2))
		
		-- Calculate filled and empty portions (in glyphs, excluding percentage area)
		local total_filled_glyphs = math.floor(bar_width * ratio)
		
		-- Build progress bar with percentage in the middle
		local bar_parts = {}
		for i = 1, bar_width do
			if i > meta_start_glyph and i <= meta_start_glyph + meta_glyph_count then
				-- Insert percentage text at the middle position
				if i == meta_start_glyph + 1 then
					table.insert(bar_parts, meta)
				end
				-- Skip glyph positions occupied by percentage text
			else
				table.insert(bar_parts, glyph)
			end
		end
		local bar = table.concat(bar_parts, "")
		
		-- Calculate filled portions for highlighting
		-- Filled portion before percentage area
		local filled_before = math.min(total_filled_glyphs, meta_start_glyph)
		-- Filled portion after percentage area
		local filled_after = math.max(0, total_filled_glyphs - (meta_start_glyph + meta_glyph_count))
		
		push_line(line_specs, content_width, bar, {
			kind = "progress",
			meta = {
				filled = total_filled_glyphs,
				empty = bar_width - total_filled_glyphs,
				filled_before = filled_before,
				filled_after = filled_after,
				meta_start_glyph = meta_start_glyph,
				meta_glyph_count = meta_glyph_count,
				meta_display_width = meta_display_width,
				meta_bytes = #meta,
				bar_width = bar_width,
				glyph_bytes = glyph_bytes,
				glyph_display_width = glyph_display_width,
			},
			align = "center",
		})
		push_line(line_specs, content_width, "")
	end

	-- Instructions
	local instructions
	if state.state.show_failures then
		instructions = "Press 󰫿 to Retry | Press 󰫾 or 󰫲󱎤󰫰 to Quit"
	else
		instructions = "Press 󰫾 or 󰫲󱎤󰫰 to Quit"
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
	local header_hl = state.state.header_hl
	for _, header_idx in ipairs(header_lines) do
		api.nvim_buf_add_highlight(win.buf, namespace, header_hl, header_idx - 1, 0, -1)
	end

	local plugin_hl = state.state.plugin_hl
	for _, item in ipairs(plugin_highlights) do
		local line = item.line - 1
		local icon_hl = item.icon_hl
			or (item.failure and (state.state.faild_hl or state.state.icon_hl) or state.state.icon_hl)
		api.nvim_buf_add_highlight(
			win.buf,
			namespace,
			icon_hl,
			line,
			item.icon_col,
			item.icon_end
		)
		api.nvim_buf_add_highlight(
			win.buf,
			namespace,
			plugin_hl,
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
		local glyph_bytes = meta.glyph_bytes or 1
		local bar_width = meta.bar_width or 0
		local filled_before = meta.filled_before or 0
		local filled_after = meta.filled_after or 0
		local meta_start_glyph = meta.meta_start_glyph or 0
		local meta_glyph_count = meta.meta_glyph_count or 0
		local meta_bytes = meta.meta_bytes or 0

		-- Calculate byte positions
		local bar_start_col = side_padding + center_shift
		local meta_start_col = bar_start_col + meta_start_glyph * glyph_bytes
		local meta_end_col = meta_start_col + meta_bytes
		local bar_end_col = bar_start_col + (bar_width - meta_glyph_count) * glyph_bytes + meta_bytes

		local default_hl = state.state.progress_hl.default
		local progress_hl = state.state.progress_hl.progress

		-- Step 1: Initialize entire bar with default color (gray)
		-- Before percentage
		if meta_start_glyph > 0 then
			api.nvim_buf_add_highlight(
				win.buf,
				namespace,
				default_hl,
				line,
				bar_start_col,
				meta_start_col
			)
		end
		-- After percentage
		if meta_end_col < bar_end_col then
			api.nvim_buf_add_highlight(
				win.buf,
				namespace,
				default_hl,
				line,
				meta_end_col,
				bar_end_col
			)
		end

		-- Step 2: Override filled portion with progress color
		-- Filled portion before percentage
		if filled_before > 0 then
			local filled_before_bytes = filled_before * glyph_bytes
			api.nvim_buf_add_highlight(
				win.buf,
				namespace,
				progress_hl,
				line,
				bar_start_col,
				bar_start_col + filled_before_bytes
			)
		end
		-- Filled portion after percentage
		if filled_after > 0 then
			local filled_after_bytes = filled_after * glyph_bytes
			api.nvim_buf_add_highlight(
				win.buf,
				namespace,
				progress_hl,
				line,
				meta_end_col,
				meta_end_col + filled_after_bytes
			)
		end
	end
end

return M

