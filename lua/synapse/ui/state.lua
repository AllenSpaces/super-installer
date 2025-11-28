local M = {
	state = {
		display = {},
		queue = {},
		lookup = {},
		max_visible = 10,
		failed_plugins = {},
		failed_lookup = {},
		completed = 0,
		total = 0,
		show_failures = false,
		retry_cb = nil,
		ui = {},
		progress_hl = {
			default = "SynapseProgressDefault",
			progress = "SynapseUIProgress",
		},
	},
}

--- Reset plugins state
function M.reset_plugins_state()
	M.state.display = {}
	M.state.queue = {}
	M.state.lookup = {}
end

--- Iterate over all entries (display + queue)
--- @param callback function
function M.for_each_entry(callback)
	for _, entry in ipairs(M.state.display or {}) do
		callback(entry)
	end
	for _, entry in ipairs(M.state.queue or {}) do
		callback(entry)
	end
end

--- Set plugins list
--- @param plugin_names table
function M.set_plugins(plugin_names)
	M.reset_plugins_state()
	for _, name in ipairs(plugin_names or {}) do
		local entry = {
			name = name,
			status = "pending",
			icon = M.state.icon,
			icon_hl = nil,
		}
		M.state.lookup[name] = entry
		if #M.state.display < M.state.max_visible then
			table.insert(M.state.display, entry)
		else
			table.insert(M.state.queue, entry)
		end
	end
end

--- Promote an entry from queue to display
function M.promote_from_queue()
	if #M.state.queue == 0 then
		return
	end
	local entry = table.remove(M.state.queue, 1)
	entry.icon = M.state.icon
	entry.status = "pending"
	entry.icon_hl = nil
	table.insert(M.state.display, entry)
end

--- Remove an entry from display or queue
--- @param entry table
function M.remove_entry(entry)
	for idx, item in ipairs(M.state.display) do
		if item == entry then
			table.remove(M.state.display, idx)
			if #M.state.queue > 0 then
				M.promote_from_queue()
			end
			M.state.lookup[entry.name] = nil
			return
		end
	end
	for idx, item in ipairs(M.state.queue) do
		if item == entry then
			table.remove(M.state.queue, idx)
			M.state.lookup[entry.name] = nil
			return
		end
	end
end

--- Get entry by name
--- @param name string
--- @return table|nil
function M.get_entry(name)
	local entry = M.state.lookup[name]
	if entry then
		return entry
	end
	return nil
end

--- Set plugin status
--- @param name string
--- @param status string
function M.set_plugin_status(name, status)
	local entry = M.get_entry(name)
	if not entry then
		entry = {
			name = name,
			status = status or "pending",
			icon = M.state.icon,
		}
		M.state.lookup[name] = entry
		if #M.state.display < M.state.max_visible then
			table.insert(M.state.display, entry)
		else
			table.insert(M.state.queue, entry)
		end
	end

	entry.status = status or entry.status

	if status == "failed" then
		entry.icon = M.state.failure_icon
		entry.icon_hl = M.state.failure_icon_hl or M.state.icon_hl
		-- Only remove if there are more than max_visible plugins
		if #M.state.display + #M.state.queue > M.state.max_visible then
			M.remove_entry(entry)
		end
	elseif status == "done" then
		entry.icon = M.state.success_icon or entry.icon
		entry.icon_hl = "SynapseUIPlugin"
		-- Only remove if there are more than max_visible plugins
		if #M.state.display + #M.state.queue > M.state.max_visible then
			M.remove_entry(entry)
		end
	elseif status == "active" then
		entry.icon = M.state.icon
		entry.icon_hl = nil
	end
end

--- Calculate progress ratio
--- @return number
function M.progress_ratio()
	if M.state.total == 0 then
		return 0
	end
	return math.min(1, math.max(0, M.state.completed / M.state.total))
end

return M

