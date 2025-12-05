local load = require("synapse.core.handlers.load")

local M = {}

-- Active event handlers: eventId -> { pluginName -> true }
M.active = {}

-- Autocmd group
M.group = vim.api.nvim_create_augroup("synapse_handler_event", { clear = true })

-- A table of mappings for custom events (e.g., VimStarted for post-startup loading)
-- @type table<string, { event: string, pattern: string }>
M.mappings = {
	VimStarted = { event = "User", pattern = "VimStarted" },
}
M.mappings["User VimStarted"] = M.mappings.VimStarted

--- Parse event spec (string, array, or table with event and pattern)
--- @param eventSpec string|string[]|table|nil Event specification
--- @return table[]|nil Array of event tables { event, pattern, id }
local function parseEventSpec(eventSpec)
	if not eventSpec then
		return nil
	end

	local events = {}

	if type(eventSpec) == "string" then
		-- Check if it's a mapped event (like "VimStarted")
		local mapped = M.mappings[eventSpec]
		if mapped then
			table.insert(events, { id = eventSpec, event = mapped.event, pattern = mapped.pattern })
		else
			-- Parse "EventName pattern" or just "EventName"
			local event, pattern = eventSpec:match("^(%w+)%s+(.*)$")
			event = event or eventSpec
			table.insert(events, { id = eventSpec, event = event, pattern = pattern })
		end
	elseif type(eventSpec) == "table" then
		-- Check if it's an array
		local isArray = true
		for k, _ in pairs(eventSpec) do
			if type(k) ~= "number" then
				isArray = false
				break
			end
		end

		if isArray then
			-- Array of event strings
			for _, evt in ipairs(eventSpec) do
				if type(evt) == "string" then
					local mapped = M.mappings[evt]
					if mapped then
						table.insert(events, { id = evt, event = mapped.event, pattern = mapped.pattern })
					else
						local event, pattern = evt:match("^(%w+)%s+(.*)$")
						event = event or evt
						table.insert(events, { id = evt, event = event, pattern = pattern })
					end
				end
			end
		else
			-- Table with event and pattern fields
			if eventSpec.event then
				local event = type(eventSpec.event) == "string" and eventSpec.event or eventSpec.event[1]
				local id = eventSpec.id or event
				table.insert(events, {
					id = id,
					event = event,
					pattern = eventSpec.pattern,
				})
			end
		end
	end

	return #events > 0 and events or nil
end

--- Setup lazy loading for events
--- @param pluginName string Plugin name
--- @param eventSpec string|string[]|table|nil Event specification
function M.setup(pluginName, eventSpec)
	if not pluginName or not eventSpec then
		return
	end

	local events = parseEventSpec(eventSpec)
	if not events then
		return
	end

	for _, evt in ipairs(events) do
		local eventId = evt.id or (evt.event .. (evt.pattern and (" " .. evt.pattern) or ""))
		
		if not M.active[eventId] then
			M.active[eventId] = {}
			-- Create autocmd that will load the plugin
			vim.api.nvim_create_autocmd(evt.event, {
				group = M.group,
				once = true,
				pattern = evt.pattern,
				callback = function()
					if M.active[eventId] and M.active[eventId][pluginName] then
						load.loadPlugin(pluginName)
					end
				end,
			})
		end
		M.active[eventId][pluginName] = true
	end
end

return M

