local api = vim.api

local VERTICAL_PADDING = 1
local HORIZONTAL_PADDING = 3
local namespace = api.nvim_create_namespace("SynapseUI")

local stringUtils = require("synapse.utils.stringUtils")
local state = require("synapse.ui.state")

local M = {}

--- Push a line to lineSpecs
--- @param lineSpecs table Line specifications table
--- @param contentWidth table Content width table with value field
--- @param text string Text to add
--- @param opts table|nil Options table
--- @return number Line index
local function pushLine(lineSpecs, contentWidth, text, opts)
	opts = opts or {}
	local width = stringUtils.displayWidth(text)
	contentWidth.value = math.max(contentWidth.value, width)
	table.insert(lineSpecs, {
		text = text,
		align = opts.align or "left",
		kind = opts.kind,
		meta = opts.meta,
	})
	return #lineSpecs
end

--- Render progress window
--- @param win table Window table
--- @param ui table|nil UI configuration
function M.renderProgress(win, ui)
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
	local sidePadding = HORIZONTAL_PADDING
	local verticalPadding = VERTICAL_PADDING
	local lineSpecs = {}
	local contentWidth = { value = 0 }

	-- Header
	for _, headerText in ipairs(state.state.headerLines or { state.state.header or "Synapse" }) do
		pushLine(lineSpecs, contentWidth, headerText, { kind = "header", align = "center" })
	end
	pushLine(lineSpecs, contentWidth, "")

	-- Plugin list
	local visiblePlugins
	if state.state.showFailures then
		visiblePlugins = {}
		for _, name in ipairs(state.state.failedPlugins) do
			table.insert(visiblePlugins, {
				name = name,
				status = "failed",
				failure = true,
				icon = state.state.failureIcon,
				iconHl = state.state.failureIconHl,
			})
		end
	else
		visiblePlugins = state.state.display
	end

	local screenWidth = vim.o.columns
	local screenHeight = vim.o.lines
	local maxWidth = math.max(20, screenWidth - 4)
	local innerLimit = math.max(10, maxWidth - sidePadding * 2)

	local filledSlots = 0
	for _, item in ipairs(visiblePlugins) do
		if filledSlots >= state.state.maxVisible then
			break
		end
		local icon = item.failure and (state.state.failureIcon or "")
			or (item.status == "failed" and (state.state.failureIcon or ""))
			or item.icon
		local text = string.format("%s %s", icon, item.name)
		pushLine(lineSpecs, contentWidth, text, {
			kind = "plugin",
			meta = {
				icon = icon,
				name = item.name,
				failure = item.failure or item.status == "failed",
				iconHl = item.iconHl,
			},
			align = "center",
		})
		filledSlots = filledSlots + 1
	end

	-- Fill remaining slots with empty lines
	while filledSlots < state.state.maxVisible do
		pushLine(lineSpecs, contentWidth, " ", { kind = "plugin", align = "center", meta = { icon = "", name = "" } })
		filledSlots = filledSlots + 1
	end

	pushLine(lineSpecs, contentWidth, "")

	-- Progress bar
	if not state.state.showFailures then
		local ratio = state.progressRatio()
		local glyph = ui.icons.progress.glyph or "■"
		local glyphBytes = #glyph
		local glyphDisplayWidth = stringUtils.displayWidth(glyph)
		
		-- Calculate percentage
		local percentage = math.floor(ratio * 100)
		local meta
		if percentage < 10 then
			-- Single digit: display as "01%"
			meta = string.format("0%d%%", percentage)
		else
			-- Double digit or more: display as "10%"
			meta = string.format("%d%%", percentage)
		end
		local metaDisplayWidth = stringUtils.displayWidth(meta)
		
		-- Calculate base bar width
		local baseBarWidth = math.max(10, math.min(contentWidth.value, innerLimit) - 6)
		
		-- Calculate how many glyphs the percentage text occupies
		-- Round up to ensure we have enough space
		local metaGlyphCount = math.ceil(metaDisplayWidth / glyphDisplayWidth)
		
		-- If percentage is 10+ digits, reduce one glyph to make room
		local barWidth = baseBarWidth
		if percentage >= 10 then
			-- Reduce one glyph for 10+ digits
			barWidth = math.max(1, barWidth - 1)
		end
		
		-- Calculate where to insert percentage (middle of the bar)
		local midPoint = math.floor(barWidth / 2)
		local metaStartGlyph = math.max(0, midPoint - math.floor(metaGlyphCount / 2))
		
		-- Calculate filled and empty portions (in glyphs, excluding percentage area)
		local totalFilledGlyphs = math.floor(barWidth * ratio)
		
		-- Build progress bar with percentage in the middle
		local barParts = {}
		for i = 1, barWidth do
			if i > metaStartGlyph and i <= metaStartGlyph + metaGlyphCount then
				-- Insert percentage text at the middle position
				if i == metaStartGlyph + 1 then
					table.insert(barParts, meta)
				end
				-- Skip glyph positions occupied by percentage text
			else
				table.insert(barParts, glyph)
			end
		end
		local bar = table.concat(barParts, "")
		
		-- Calculate filled portions for highlighting
		-- Filled portion before percentage area
		local filledBefore = math.min(totalFilledGlyphs, metaStartGlyph)
		-- Filled portion after percentage area
		local filledAfter = math.max(0, totalFilledGlyphs - (metaStartGlyph + metaGlyphCount))
		
		pushLine(lineSpecs, contentWidth, bar, {
			kind = "progress",
			meta = {
				filled = totalFilledGlyphs,
				empty = barWidth - totalFilledGlyphs,
				filledBefore = filledBefore,
				filledAfter = filledAfter,
				metaStartGlyph = metaStartGlyph,
				metaGlyphCount = metaGlyphCount,
				metaDisplayWidth = metaDisplayWidth,
				metaBytes = #meta,
				barWidth = barWidth,
				glyphBytes = glyphBytes,
				glyphDisplayWidth = glyphDisplayWidth,
			},
			align = "center",
		})
		pushLine(lineSpecs, contentWidth, "")
	end

	-- Instructions
	local instructions
	if state.state.showFailures then
		instructions = "Press 󰫿 to Retry | Press 󰫾 or 󰫲󱎤󰫰 to Quit"
	else
		instructions = "Press 󰫾 or 󰫲󱎤󰫰 to Quit"
	end
	pushLine(lineSpecs, contentWidth, instructions, { align = "center" })

	-- Vertical padding
	if verticalPadding > 0 then
		for _ = 1, verticalPadding do
			table.insert(lineSpecs, 1, { text = "", align = "left", kind = "pad" })
		end
		for _ = 1, verticalPadding do
			table.insert(lineSpecs, { text = "", align = "left", kind = "pad" })
		end
	end

	-- Calculate dimensions
	local innerWidth = math.min(innerLimit, math.max(contentWidth.value, 40))
	local targetWidth = math.min(maxWidth, innerWidth + sidePadding * 2)
	innerWidth = targetWidth - sidePadding * 2

	local targetHeight = math.min(screenHeight - 4, math.max(#lineSpecs, 10))

	-- Update window config
	api.nvim_win_set_config(win.win_id, {
		relative = "editor",
		width = targetWidth,
		height = targetHeight,
		col = math.floor((screenWidth - targetWidth) / 2),
		row = math.floor((screenHeight - targetHeight) / 2),
	})

	-- Render lines
	local renderedLines = {}
	local headerLines = {}
	local pluginHighlights = {}
	local progressLine = nil

	for idx, spec in ipairs(lineSpecs) do
		local centerShift = 0
		if spec.kind == "pad" then
			renderedLines[idx] = string.rep(" ", targetWidth)
		elseif spec.align == "center" then
			local centered
			centered, centerShift = stringUtils.centerText(spec.text, innerWidth)
			renderedLines[idx] = string.rep(" ", sidePadding) .. centered .. string.rep(" ", sidePadding)
			if spec.kind == "header" then
				table.insert(headerLines, idx)
			end
			spec.centerOffset = centerShift
		else
			local padded = spec.text
			local paddingNeeded = innerWidth - stringUtils.displayWidth(padded)
			if paddingNeeded > 0 then
				padded = padded .. string.rep(" ", paddingNeeded)
			end
			renderedLines[idx] = string.rep(" ", sidePadding) .. padded .. string.rep(" ", sidePadding)
			spec.centerOffset = 0
		end

		if spec.kind == "pad" then
			-- skip highlight
		elseif spec.kind == "plugin" and spec.meta then
			local icon = spec.meta.icon or ""
			local name = spec.meta.name or ""
			local iconBytes = #icon
			local nameBytes = #name
			local iconCol = sidePadding + centerShift
			local iconEnd = iconCol + iconBytes
			local nameCol = iconEnd + 1
			local nameEnd = nameCol + nameBytes
			table.insert(pluginHighlights, {
				line = idx,
				iconCol = iconCol,
				iconEnd = iconEnd,
				nameCol = nameCol,
				nameEnd = nameEnd,
				failure = spec.meta.failure,
				iconHl = spec.meta.iconHl,
			})
		elseif spec.kind == "progress" then
			progressLine = idx
		end
	end

	-- Set buffer lines
	api.nvim_buf_set_lines(win.buf, 0, -1, false, renderedLines)
	api.nvim_buf_clear_namespace(win.buf, namespace, 0, -1)

	-- Apply highlights
	local headerHl = state.state.headerHl
	for _, headerIdx in ipairs(headerLines) do
		api.nvim_buf_add_highlight(win.buf, namespace, headerHl, headerIdx - 1, 0, -1)
	end

	local pluginHl = state.state.pluginHl
	for _, item in ipairs(pluginHighlights) do
		local line = item.line - 1
		local iconHl = item.iconHl
			or (item.failure and (state.state.faildHl or state.state.iconHl) or state.state.iconHl)
		api.nvim_buf_add_highlight(
			win.buf,
			namespace,
			iconHl,
			line,
			item.iconCol,
			item.iconEnd
		)
		api.nvim_buf_add_highlight(
			win.buf,
			namespace,
			pluginHl,
			line,
			item.nameCol,
			item.nameEnd
		)
	end

	-- Progress bar highlights
	if progressLine then
		local line = progressLine - 1
		local spec = lineSpecs[progressLine]
		local meta = spec.meta or {}
		local centerShift = spec.centerOffset or 0
		local glyphBytes = meta.glyphBytes or 1
		local barWidth = meta.barWidth or 0
		local filledBefore = meta.filledBefore or 0
		local filledAfter = meta.filledAfter or 0
		local metaStartGlyph = meta.metaStartGlyph or 0
		local metaGlyphCount = meta.metaGlyphCount or 0
		local metaBytes = meta.metaBytes or 0

		-- Calculate byte positions
		local barStartCol = sidePadding + centerShift
		local metaStartCol = barStartCol + metaStartGlyph * glyphBytes
		local metaEndCol = metaStartCol + metaBytes
		local barEndCol = barStartCol + (barWidth - metaGlyphCount) * glyphBytes + metaBytes

		local defaultHl = state.state.progressHl.default
		local progressHl = state.state.progressHl.progress

		-- Step 1: Initialize entire bar with default color (gray)
		-- Before percentage
		if metaStartGlyph > 0 then
			api.nvim_buf_add_highlight(
				win.buf,
				namespace,
				defaultHl,
				line,
				barStartCol,
				metaStartCol
			)
		end
		-- After percentage
		if metaEndCol < barEndCol then
			api.nvim_buf_add_highlight(
				win.buf,
				namespace,
				defaultHl,
				line,
				metaEndCol,
				barEndCol
			)
		end

		-- Step 2: Override filled portion with progress color
		-- Filled portion before percentage
		if filledBefore > 0 then
			local filledBeforeBytes = filledBefore * glyphBytes
			api.nvim_buf_add_highlight(
				win.buf,
				namespace,
				progressHl,
				line,
				barStartCol,
				barStartCol + filledBeforeBytes
			)
		end
		-- Filled portion after percentage
		if filledAfter > 0 then
			local filledAfterBytes = filledAfter * glyphBytes
			api.nvim_buf_add_highlight(
				win.buf,
				namespace,
				progressHl,
				line,
				metaEndCol,
				metaEndCol + filledAfterBytes
			)
		end
	end
end

return M

