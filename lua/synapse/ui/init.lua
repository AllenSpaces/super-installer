local state = require("synapse.ui.state")
local window = require("synapse.ui.window")
local renderer = require("synapse.ui.renderer")
local highlights = require("synapse.ui.highlights")
local stringUtils = require("synapse.utils.stringUtils")

local M = {}

-- Expose state for external access
M.state = state.state

--- Open progress window
--- @param opts table|nil Options table
--- @return table win Window table
function M.open(opts)
	opts = opts or {}
	-- Reset plugin display state before opening window each time, to avoid leftover names from previous stage
	state.resetPluginsState()
	highlights.ensureHighlights(opts.ui, state.state) -- Backward compatible: ensureHighlights calls ensure_highlights internally
	local win = window.createWindow(opts.ui)

	local initialPlugins = opts.plugins or {}
	local pluginTotal = #initialPlugins

	-- Handle new header structure: { text = {...}, hl = "..." } or old string format
	local newHeader = opts.header or opts.title or state.state.header
	if type(newHeader) == "table" and newHeader.text then
		-- New structure: { text = {...}, hl = "..." }
		state.state.headerLines = type(newHeader.text) == "table" and newHeader.text or { tostring(newHeader.text) }
		state.state.headerHl = newHeader.hl
	elseif type(newHeader) == "table" then
		-- Old array format
		state.state.headerLines = newHeader
		state.state.headerHl = (opts.ui and opts.ui.header and opts.ui.header.hl)
	else
		-- String format
		state.state.header = type(newHeader) == "string" and newHeader or state.state.header
		state.state.headerLines = stringUtils.normalizeHeader(newHeader or state.state.headerLines)
		state.state.headerHl = (opts.ui and opts.ui.header and opts.ui.header.hl)
	end
	-- headerHl will be set by highlights.ensureHighlights if not set
	state.state.icon = stringUtils.resolveIcon(opts.icon) or state.state.icon
	local successIconCfg = opts.successIcon or (opts.ui and opts.ui.icons and opts.ui.icons.success)
	state.state.successIcon = stringUtils.resolveIcon(successIconCfg) or state.state.successIcon or "✓"
	if type(opts.icon) == "table" and opts.icon.hl then
		state.state.iconHl = opts.icon.hl
	end
	local failureIconCfg = opts.failureIcon or (opts.ui and opts.ui.icons and opts.ui.icons.faild)
	state.state.failureIcon = stringUtils.resolveIcon(failureIconCfg) or state.state.failureIcon
	if type(failureIconCfg) == "table" and failureIconCfg.hl then
		state.state.failureIconHl = failureIconCfg.hl
	else
		state.state.failureIconHl = state.state.iconHl
	end
	state.state.completed = 0
	state.state.total = opts.total or pluginTotal
	state.state.showFailures = false
	state.state.failedPlugins = {}
	state.state.failedLookup = {}
	state.state.retryCb = nil
	state.state.ui = opts.ui or state.state.ui

	state.setPlugins(opts.plugins or {})

	renderer.renderProgress(win, opts.ui or state.state.ui)
	return win
end

--- Update progress display
--- @param win table|nil Window table
--- @param ctx table|nil Context table with plugin and status
--- @param completed number|nil Completed count
--- @param total number|nil Total count
--- @param ui table|nil UI configuration
function M.update_progress(win, ctx, completed, total, ui)
	if not win then
		return
	end

	highlights.ensureHighlights(ui or state.state.ui, state.state)
	state.state.total = total or state.state.total
	state.state.completed = completed or state.state.completed

	if ctx and ctx.plugin then
		state.setPluginStatus(ctx.plugin, ctx.status or "active")
		if ctx.status == "failed" then
			if not state.state.failedLookup[ctx.plugin] then
				state.state.failedLookup[ctx.plugin] = true
				table.insert(state.state.failedPlugins, ctx.plugin)
			end
		end
	end

	renderer.renderProgress(win, ui or state.state.ui)
end

--- Show error report
--- @param errors table|nil Array of error objects
--- @param successCount number|nil Success count
--- @param total number|nil Total count
--- @param opts table|nil Options table
function M.show_report(errors, successCount, total, opts)
	opts = opts or {}
	highlights.ensureHighlights(opts.ui or state.state.ui, state.state)
	local win = window.winCache
	if not win then
		return
	end

	if not errors or #errors == 0 then
		state.state.showFailures = false
		state.state.completed = total or successCount or 0
		state.state.total = total or successCount or 0
		state.setPlugins({ string.format("%s Done", opts.operation or "Operation") })
		state.forEachEntry(function(item)
			item.status = "done"
			item.icon = state.state.successIcon
			item.iconHl = state.state.successHl or state.state.pluginHl
		end)
		renderer.renderProgress(win, opts.ui or state.state.ui)
		return
	end

	-- Rebuild failed plugins list here, only based on current errors, to avoid mixing in already successful plugins
	local failedPlugins = {}
	local seen = {}
	for _, err in ipairs(errors) do
		local pluginName = err.plugin or err.repo or "unknown"
		if pluginName and pluginName ~= "" and not seen[pluginName] then
			table.insert(failedPlugins, pluginName)
			seen[pluginName] = true
		end
	end

	-- Reset internal failedLookup to avoid cross-contamination between multiple calls
	state.state.failedLookup = {}
	for _, name in ipairs(failedPlugins) do
		state.state.failedLookup[name] = true
	end

	-- Set failed plugins in display
	state.setPlugins(failedPlugins)
	-- Mark all as failed
	for _, name in ipairs(failedPlugins) do
		state.setPluginStatus(name, "failed")
	end

	state.state.failedPlugins = failedPlugins
	state.state.showFailures = true
	state.state.retryCb = opts.on_retry
	state.state.failureIcon = opts.failureIcon or state.state.failureIcon
	-- Reset progress for retry
	state.state.completed = 0
	state.state.total = #failedPlugins

	renderer.renderProgress(win, opts.ui or state.state.ui)
end

--- Retry failed operations
function M.retry_failures()
	if state.state.showFailures and type(state.state.retryCb) == "function" then
		-- Save failed plugins list before reset
		local failedPlugins = {}
		for _, name in ipairs(state.state.failedPlugins) do
			table.insert(failedPlugins, name)
		end
		
		-- Clear error cache before retry
		local errorUi = require("synapse.ui.errorUi")
		errorUi.clearCache()
		
		-- Reset state for retry
		state.state.showFailures = false
		state.state.completed = 0
		state.state.total = #failedPlugins
		state.state.failedPlugins = {}
		state.state.failedLookup = {}
		
		-- Reset plugins list to failed plugins for retry
		state.setPlugins(failedPlugins)
		for _, entry in ipairs(state.state.display) do
			entry.status = "pending"
			entry.icon = state.state.icon
			entry.iconHl = nil
		end
		
		-- Re-render UI to show progress bar after retry
		local win = window.winCache
		if win then
			renderer.renderProgress(win, state.state.ui)
		end
		
		local cb = state.state.retryCb
		state.state.retryCb = nil
		cb()
	else
		vim.notify("No pending retryable operation", vim.log.levels.INFO, { title = "Synapse" })
	end
end

--- Log a message
--- @param message string Message to log
function M.log_message(message)
	vim.notify(message, vim.log.levels.INFO, { title = "Synapse" })
end

--- Close progress window
--- @param opts table|nil Options table
function M.close(opts)
	opts = opts or {}
	window.close()
	if opts.message then
		vim.notify(opts.message, opts.level or vim.log.levels.INFO, { title = "Synapse" })
	end
end

return M
