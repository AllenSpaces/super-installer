local load = require("synapse.core.handlers.load")
local eventHandler = require("synapse.core.handlers.loadEvent")

local M = {}

-- Active filetype handlers: ft -> { pluginName -> true }
M.active = {}

--- Parse filetype spec (string or array of strings)
--- @param ftSpec string|string[]|nil Filetype specification
--- @return string[]|nil Array of filetype names
local function parseFtSpec(ftSpec)
	if not ftSpec then
		return nil
	end

	if type(ftSpec) == "string" then
		return { ftSpec }
	elseif type(ftSpec) == "table" then
		local fts = {}
		for _, ft in ipairs(ftSpec) do
			if type(ft) == "string" then
				table.insert(fts, ft)
			end
		end
		return #fts > 0 and fts or nil
	end

	return nil
end

--- Setup lazy loading for filetypes
--- @param pluginName string Plugin name
--- @param ftSpec string|string[]|nil Filetype specification
function M.setup(pluginName, ftSpec)
	if not pluginName or not ftSpec then
		return
	end

	local fts = parseFtSpec(ftSpec)
	if not fts then
		return
	end

	for _, ft in ipairs(fts) do
		if not M.active[ft] then
			M.active[ft] = {}
			-- Use FileType event for lazy loading
			vim.api.nvim_create_autocmd("FileType", {
				group = eventHandler.group,
				once = true,
				pattern = ft,
				callback = function()
					if M.active[ft] and M.active[ft][pluginName] then
						load.loadPlugin(pluginName)
					end
				end,
			})
		end
		M.active[ft][pluginName] = true
	end
end

return M

