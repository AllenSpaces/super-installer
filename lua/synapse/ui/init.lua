local state = require("synapse.ui.state")
local window = require("synapse.ui.window")
local renderer = require("synapse.ui.renderer")
local highlights = require("synapse.ui.highlights")
local string_utils = require("synapse.utils.string")

local M = {}

-- Expose state for external access
M.state = state.state

--- Open progress window
--- @param opts table|nil
--- @return table win
function M.open(opts)
	opts = opts or {}
	highlights.ensure_highlights(opts.ui, state.state)
	local win = window.create_window(opts.ui)

	local initial_plugins = opts.plugins or {}
	local plugin_total = #initial_plugins

	-- Handle new header structure: { text = {...}, hl = "..." } or old string format
	local new_header = opts.header or opts.title or state.state.header
	if type(new_header) == "table" and new_header.text then
		-- New structure: { text = {...}, hl = "..." }
		state.state.header_lines = type(new_header.text) == "table" and new_header.text or { tostring(new_header.text) }
		state.state.header_hl = new_header.hl
	elseif type(new_header) == "table" then
		-- Old array format
		state.state.header_lines = new_header
		state.state.header_hl = (opts.ui and opts.ui.header and opts.ui.header.hl)
	else
		-- String format
		state.state.header = type(new_header) == "string" and new_header or state.state.header
		state.state.header_lines = string_utils.normalize_header(new_header or state.state.header_lines)
		state.state.header_hl = (opts.ui and opts.ui.header and opts.ui.header.hl)
	end
	-- header_hl will be set by highlights.ensure_highlights if not set
	state.state.icon = string_utils.resolve_icon(opts.icon) or state.state.icon
	local success_icon_cfg = opts.success_icon or (opts.ui and opts.ui.icons and opts.ui.icons.success)
	state.state.success_icon = string_utils.resolve_icon(success_icon_cfg) or state.state.success_icon or "✓"
	if type(opts.icon) == "table" and opts.icon.hl then
		state.state.icon_hl = opts.icon.hl
	end
	local failure_icon_cfg = opts.failure_icon or (opts.ui and opts.ui.icons and opts.ui.icons.faild)
	state.state.failure_icon = string_utils.resolve_icon(failure_icon_cfg) or state.state.failure_icon
	if type(failure_icon_cfg) == "table" and failure_icon_cfg.hl then
		state.state.failure_icon_hl = failure_icon_cfg.hl
	else
		state.state.failure_icon_hl = state.state.icon_hl
	end
	state.state.completed = 0
	state.state.total = opts.total or plugin_total
	state.state.show_failures = false
	state.state.failed_plugins = {}
	state.state.failed_lookup = {}
	state.state.retry_cb = nil
	state.state.ui = opts.ui or state.state.ui

	state.set_plugins(opts.plugins or {})

	renderer.render_progress(win, opts.ui or state.state.ui)
	return win
end

--- Update progress
--- @param win table|nil
--- @param ctx table|nil
--- @param completed number|nil
--- @param total number|nil
--- @param ui table|nil
function M.update_progress(win, ctx, completed, total, ui)
	if not win then
		return
	end

	highlights.ensure_highlights(ui or state.state.ui, state.state)
	state.state.total = total or state.state.total
	state.state.completed = completed or state.state.completed

	if ctx and ctx.plugin then
		state.set_plugin_status(ctx.plugin, ctx.status or "active")
		if ctx.status == "failed" then
			if not state.state.failed_lookup[ctx.plugin] then
				state.state.failed_lookup[ctx.plugin] = true
				table.insert(state.state.failed_plugins, ctx.plugin)
			end
		end
	end

	renderer.render_progress(win, ui or state.state.ui)
end

--- Show error report
--- @param errors table|nil
--- @param success_count number|nil
--- @param total number|nil
--- @param opts table|nil
function M.show_report(errors, success_count, total, opts)
	opts = opts or {}
	highlights.ensure_highlights(opts.ui or state.state.ui, state.state)
	local win = window.win_cache
	if not win then
		return
	end

	if not errors or #errors == 0 then
		state.state.show_failures = false
		state.state.completed = total or success_count or 0
		state.state.total = total or success_count or 0
		state.set_plugins({ string.format("%s Done", opts.operation or "Operation") })
		state.for_each_entry(function(item)
			item.status = "done"
			item.icon = state.state.success_icon
			item.icon_hl = state.state.success_hl or state.state.plugin_hl
		end)
		renderer.render_progress(win, opts.ui or state.state.ui)
		return
	end

	local failed_plugins = opts.failed_plugins or {}
	if #failed_plugins == 0 then
		for _, err in ipairs(errors) do
			local plugin_name = err.plugin or err.repo or "unknown"
			if not state.state.failed_lookup[plugin_name] then
				table.insert(failed_plugins, plugin_name)
				state.state.failed_lookup[plugin_name] = true
			end
		end
	end

	-- Set failed plugins in display
	state.set_plugins(failed_plugins)
	-- Mark all as failed
	for _, name in ipairs(failed_plugins) do
		state.set_plugin_status(name, "failed")
	end

	state.state.failed_plugins = failed_plugins
	state.state.show_failures = true
	state.state.retry_cb = opts.on_retry
	state.state.failure_icon = opts.failure_icon or state.state.failure_icon
	-- Reset progress for retry
	state.state.completed = 0
	state.state.total = #failed_plugins

	renderer.render_progress(win, opts.ui or state.state.ui)
end

--- Retry failed operations
function M.retry_failures()
	if state.state.show_failures and type(state.state.retry_cb) == "function" then
		-- Save failed plugins list before reset
		local failed_plugins = {}
		for _, name in ipairs(state.state.failed_plugins) do
			table.insert(failed_plugins, name)
		end
		
		-- Clear error cache before retry
		local error_ui = require("synapse.ui.error")
		error_ui.clear_cache()
		
		-- Reset state for retry
		state.state.show_failures = false
		state.state.completed = 0
		state.state.total = #failed_plugins
		state.state.failed_plugins = {}
		state.state.failed_lookup = {}
		
		-- Reset plugins list to failed plugins for retry
		state.set_plugins(failed_plugins)
		for _, entry in ipairs(state.state.display) do
			entry.status = "pending"
			entry.icon = state.state.icon
			entry.icon_hl = nil
		end
		
		-- Re-render UI to show progress bar after retry
		local win = window.win_cache
		if win then
			renderer.render_progress(win, state.state.ui)
		end
		
		local cb = state.state.retry_cb
		state.state.retry_cb = nil
		cb()
	else
		vim.notify("No pending retryable operation", vim.log.levels.INFO, { title = "Synapse" })
	end
end

--- Log a message
--- @param message string
function M.log_message(message)
	vim.notify(message, vim.log.levels.INFO, { title = "Synapse" })
end

--- Close progress window
--- @param opts table|nil
function M.close(opts)
	opts = opts or {}
	window.close()
	if opts.message then
		vim.notify(opts.message, opts.level or vim.log.levels.INFO, { title = "Synapse" })
	end
end

return M

