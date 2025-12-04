local api = vim.api

local M = {
	errorCache = {}, -- Store error information { pluginName, errorMessage }
	currentWin = nil,
	currentBuf = nil,
}

--- Calculate window size for error display
--- @return number width Window width
--- @return number height Window height
local function calculateWindowSize()
	-- Make error window larger to show full error messages
	local width = math.floor(vim.o.columns * 0.7)
	local height = math.floor(vim.o.lines * 0.6)
	return width, height
end

--- Format error content as markdown
--- @param pluginName string Plugin name
--- @param errorMessage string Error message
--- @return table lines Array of formatted lines
local function formatErrorContent(pluginName, errorMessage)
	local lines = {}

	-- Plugin name as level 1 heading
	table.insert(lines, "# " .. pluginName)
	table.insert(lines, "")

	-- Error message as error admonition
	table.insert(lines, "> [!ERROR]")
	-- Handle multi-line error messages and ensure all content is shown
	local errorMessageStr = errorMessage or ""
	if errorMessageStr == "" then
		errorMessageStr = "Unknown error"
	end

	-- Split by newlines and preserve all content
	local errorLines = vim.split(errorMessageStr, "\n")
	for _, line in ipairs(errorLines) do
		-- Preserve empty lines and all content
		if line == "" then
			table.insert(lines, ">")
		else
			table.insert(lines, "> " .. line)
		end
	end

	-- Remove trailing empty lines from error message
	while #lines > 0 and (lines[#lines] == ">" or lines[#lines] == "") do
		table.remove(lines)
	end

	return lines
end

--- Save error to cache without showing window
--- @param pluginName string Plugin name
--- @param errorMessage string Error message
function M.saveError(pluginName, errorMessage)
	-- Save error to cache
	table.insert(M.errorCache, {
		plugin = pluginName,
		error = errorMessage,
	})
end

--- Show error window
--- @param pluginName string Plugin name
--- @param errorMessage string Error message
function M.showError(pluginName, errorMessage)
	-- Save error to cache
	M.saveError(pluginName, errorMessage)

	-- Close existing window and buffer if any
	if M.currentWin and api.nvim_win_is_valid(M.currentWin) then
		api.nvim_win_close(M.currentWin, true)
	end
	if M.currentBuf and api.nvim_buf_is_valid(M.currentBuf) then
		api.nvim_buf_delete(M.currentBuf, { force = true })
	end

	-- Check for existing buffer with the same name and delete it
	for _, bufId in ipairs(api.nvim_list_bufs()) do
		if api.nvim_buf_is_valid(bufId) then
			local bufName = api.nvim_buf_get_name(bufId)
			if bufName == "SynapseError" or bufName:match("SynapseError") then
				-- Check if buffer is in a window
				local wins = api.nvim_list_wins()
				for _, winId in ipairs(wins) do
					if api.nvim_win_get_buf(winId) == bufId then
						api.nvim_win_close(winId, true)
					end
				end
				api.nvim_buf_delete(bufId, { force = true })
			end
		end
	end

	-- Format content - show all errors from cache
	local contentLines = {}
	for i, err in ipairs(M.errorCache) do
		if i > 1 then
			table.insert(contentLines, "")
			table.insert(contentLines, "---")
			table.insert(contentLines, "")
		end

		local pluginLines = formatErrorContent(err.plugin, err.error)
		for _, line in ipairs(pluginLines) do
			table.insert(contentLines, line)
		end
	end

	-- Remove trailing empty lines (including ">" lines from error formatting)
	while #contentLines > 0 and (contentLines[#contentLines] == "" or contentLines[#contentLines] == ">") do
		table.remove(contentLines)
	end

	-- Calculate window size (same as install/update windows)
	local width, height = calculateWindowSize()

	-- Create buffer
	local buf = api.nvim_create_buf(false, true)
	-- Set buffer name
	api.nvim_buf_set_name(buf, "SynapseError")

	-- Set filetype
	api.nvim_buf_set_option(buf, "filetype", "markdown")

	-- Enable line wrapping to show full error messages
	api.nvim_buf_set_option(buf, "wrap", true)
	api.nvim_buf_set_option(buf, "linebreak", true) -- Break at word boundaries

	-- Set content
	api.nvim_buf_set_lines(buf, 0, -1, false, contentLines)

	-- Make buffer readonly
	api.nvim_buf_set_option(buf, "readonly", true)
	api.nvim_buf_set_option(buf, "modifiable", false)

	-- Create floating window
	local config = {
		relative = "editor",
		width = width,
		height = height,
		col = math.floor((vim.o.columns - width) / 2),
		row = math.floor((vim.o.lines - height) / 2),
		style = "minimal",
		border = "rounded",
		title = " Synapse Error ",
		title_pos = "center",
	}

	local winId = api.nvim_open_win(buf, true, config)

	-- Enable line wrapping in window (must be after window creation)
	api.nvim_win_set_option(winId, "wrap", true)
	api.nvim_win_set_option(winId, "linebreak", true) -- Break at word boundaries

	-- Set keymaps
	local opts = { noremap = true, silent = true }
	api.nvim_buf_set_keymap(buf, "n", "q", "<cmd>lua require('synapse.ui.errorUi').close()<CR>", opts)
	api.nvim_buf_set_keymap(buf, "n", "<Esc>", "<cmd>lua require('synapse.ui.errorUi').close()<CR>", opts)

	-- Store window reference
	M.currentWin = winId
	M.currentBuf = buf
end

--- Show all errors from cache
function M.showAllErrors()
	-- Toggle: if window is already open, close it
	if M.currentWin and api.nvim_win_is_valid(M.currentWin) then
		M.close()
		return
	end

	if #M.errorCache == 0 then
		vim.notify("No errors to display", vim.log.levels.INFO, { title = "Synapse" })
		return
	end

	-- Clean up any existing windows and buffers
	if M.currentWin and api.nvim_win_is_valid(M.currentWin) then
		api.nvim_win_close(M.currentWin, true)
	end
	if M.currentBuf and api.nvim_buf_is_valid(M.currentBuf) then
		api.nvim_buf_delete(M.currentBuf, { force = true })
	end

	-- Check for existing buffer with the same name and delete it
	for _, bufId in ipairs(api.nvim_list_bufs()) do
		if api.nvim_buf_is_valid(bufId) then
			local bufName = api.nvim_buf_get_name(bufId)
			if bufName == "SynapseError" or bufName:match("SynapseError") then
				-- Check if buffer is in a window
				local wins = api.nvim_list_wins()
				for _, winId in ipairs(wins) do
					if api.nvim_win_get_buf(winId) == bufId then
						api.nvim_win_close(winId, true)
					end
				end
				api.nvim_buf_delete(bufId, { force = true })
			end
		end
	end

	local contentLines = {}

	for i, err in ipairs(M.errorCache) do
		if i > 1 then
			table.insert(contentLines, "")
			table.insert(contentLines, "---")
			table.insert(contentLines, "")
		end

		local pluginLines = formatErrorContent(err.plugin, err.error)
		for _, line in ipairs(pluginLines) do
			table.insert(contentLines, line)
		end
	end

	-- Remove trailing empty lines (including ">" lines from error formatting)
	while #contentLines > 0 and (contentLines[#contentLines] == "" or contentLines[#contentLines] == ">") do
		table.remove(contentLines)
	end

	-- Calculate window size (same as install/update windows)
	local width, height = calculateWindowSize()

	-- Create buffer
	local buf = api.nvim_create_buf(false, true)
	-- Set buffer name
	api.nvim_buf_set_name(buf, "SynapseError")

	-- Set filetype
	api.nvim_buf_set_option(buf, "filetype", "markdown")

	-- Enable line wrapping to show full error messages
	api.nvim_buf_set_option(buf, "wrap", true)
	api.nvim_buf_set_option(buf, "linebreak", true) -- Break at word boundaries

	-- Set content
	api.nvim_buf_set_lines(buf, 0, -1, false, contentLines)

	-- Make buffer readonly
	api.nvim_buf_set_option(buf, "readonly", true)
	api.nvim_buf_set_option(buf, "modifiable", false)

	-- Create floating window
	local config = {
		relative = "editor",
		width = width,
		height = height,
		col = math.floor((vim.o.columns - width) / 2),
		row = math.floor((vim.o.lines - height) / 2),
		style = "minimal",
		border = "rounded",
		title = " Synapse Error ",
		title_pos = "center",
	}

	local winId = api.nvim_open_win(buf, true, config)

	-- Enable line wrapping in window (must be after window creation)
	api.nvim_win_set_option(winId, "wrap", true)
	api.nvim_win_set_option(winId, "linebreak", true) -- Break at word boundaries

	-- Set keymaps
	local opts = { noremap = true, silent = true }
	api.nvim_buf_set_keymap(buf, "n", "q", "<cmd>lua require('synapse.ui.errorUi').close()<CR>", opts)
	api.nvim_buf_set_keymap(buf, "n", "<Esc>", "<cmd>lua require('synapse.ui.errorUi').close()<CR>", opts)

	-- Store window reference
	M.currentWin = winId
	M.currentBuf = buf
end

--- Close error window
function M.close()
	if M.currentWin and api.nvim_win_is_valid(M.currentWin) then
		api.nvim_win_close(M.currentWin, true)
	end

	if M.currentBuf and api.nvim_buf_is_valid(M.currentBuf) then
		api.nvim_buf_delete(M.currentBuf, { force = true })
	end

	M.currentWin = nil
	M.currentBuf = nil
end

--- Clear error cache
function M.clearCache()
	M.errorCache = {}
end

-- Backward compatibility aliases (will be removed after full refactoring)
function M.save_error(pluginName, errorMessage)
	return M.saveError(pluginName, errorMessage)
end

function M.show_error(pluginName, errorMessage)
	return M.showError(pluginName, errorMessage)
end

function M.show_all_errors()
	return M.showAllErrors()
end

function M.clear_cache()
	return M.clearCache()
end

return M

