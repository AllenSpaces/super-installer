local M = {
	state = {
		display = {},
		queue = {},
		lookup = {},
		maxVisible = 10,
		failedPlugins = {},
		failedLookup = {},
		completed = 0,
		total = 0,
		showFailures = false,
		retryCb = nil,
		ui = {},
		progressHl = {},
		-- UI state fields (initialized by ui/init.lua)
		header = nil,
		headerLines = {},
		headerHl = nil,
		icon = nil,
		iconHl = nil,
		successIcon = nil,
		successHl = nil,
		failureIcon = nil,
		failureIconHl = nil,
		pluginHl = nil,
		faildHl = nil,
	},
}

--- Reset plugins state
function M.resetPluginsState()
	M.state.display = {}
	M.state.queue = {}
	M.state.lookup = {}
end

--- Iterate over all entries (display + queue)
--- @param callback function Callback function to execute for each entry
function M.forEachEntry(callback)
	for _, entry in ipairs(M.state.display or {}) do
		callback(entry)
	end
	for _, entry in ipairs(M.state.queue or {}) do
		callback(entry)
	end
end

--- Set plugins list
--- @param pluginNames table Array of plugin names
function M.setPlugins(pluginNames)
	M.resetPluginsState()
	for _, name in ipairs(pluginNames or {}) do
		local entry = {
			name = name,
			status = "pending",
			icon = M.state.icon,
			iconHl = nil,
		}
		M.state.lookup[name] = entry
		if #M.state.display < M.state.maxVisible then
			table.insert(M.state.display, entry)
		else
			table.insert(M.state.queue, entry)
		end
	end
end

--- Promote an entry from queue to display
function M.promoteFromQueue()
	if #M.state.queue == 0 then
		return
	end
	local entry = table.remove(M.state.queue, 1)
	entry.icon = M.state.icon
	entry.status = "pending"
	entry.iconHl = nil
	table.insert(M.state.display, entry)
end

--- Remove an entry from display or queue
--- @param entry table Entry to remove
function M.removeEntry(entry)
	for idx, item in ipairs(M.state.display) do
		if item == entry then
			table.remove(M.state.display, idx)
			if #M.state.queue > 0 then
				M.promoteFromQueue()
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
--- @param name string Plugin name
--- @return table|nil Entry table or nil if not found
function M.getEntry(name)
	local entry = M.state.lookup[name]
	if entry then
		return entry
	end
	return nil
end

--- Set plugin status
--- @param name string Plugin name
--- @param status string Status ("pending", "active", "done", "failed")
function M.setPluginStatus(name, status)
	local entry = M.getEntry(name)
	if not entry then
		entry = {
			name = name,
			status = status or "pending",
			icon = M.state.icon,
		}
		M.state.lookup[name] = entry
		if #M.state.display < M.state.maxVisible then
			table.insert(M.state.display, entry)
		else
			table.insert(M.state.queue, entry)
		end
	end

	entry.status = status or entry.status

	if status == "failed" then
		entry.icon = M.state.failureIcon
		entry.iconHl = M.state.faildHl or M.state.failureIconHl or M.state.iconHl
		-- Only remove if there are more than maxVisible plugins
		if #M.state.display + #M.state.queue > M.state.maxVisible then
			M.removeEntry(entry)
		end
	elseif status == "done" then
		entry.icon = M.state.successIcon or entry.icon
		entry.iconHl = M.state.successHl or M.state.pluginHl
		-- Only remove if there are more than maxVisible plugins
		if #M.state.display + #M.state.queue > M.state.maxVisible then
			M.removeEntry(entry)
		end
	elseif status == "active" then
		entry.icon = M.state.icon
		entry.iconHl = nil
	end
end

--- Calculate progress ratio
--- @return number Progress ratio (0.0 to 1.0)
function M.progressRatio()
	if M.state.total == 0 then
		return 0
	end
	return math.min(1, math.max(0, M.state.completed / M.state.total))
end

return M
