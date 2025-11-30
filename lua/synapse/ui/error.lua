local api = vim.api

local M = {
	error_cache = {}, -- 存储错误信息 { plugin_name, error_message }
}

--- Calculate window size for error display
--- @return number width
--- @return number height
local function calculate_window_size()
	-- Make error window larger to show full error messages
	local width = math.floor(vim.o.columns * 0.7)
	local height = math.floor(vim.o.lines * 0.6)
	return width, height
end

--- Format error content as markdown
--- @param plugin_name string
--- @param error_message string
--- @return table lines
local function format_error_content(plugin_name, error_message)
	local lines = {}
	
	-- Plugin name as level 1 heading
	table.insert(lines, "# " .. plugin_name)
	table.insert(lines, "")
	
	-- Error message as error admonition
	table.insert(lines, "> [!ERROR]")
	-- Handle multi-line error messages and ensure all content is shown
	local error_message_str = error_message or ""
	if error_message_str == "" then
		error_message_str = "Unknown error"
	end
	
	-- Split by newlines and preserve all content
	local error_lines = vim.split(error_message_str, "\n")
	for _, line in ipairs(error_lines) do
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
--- @param plugin_name string
--- @param error_message string
function M.save_error(plugin_name, error_message)
	-- Save error to cache
	table.insert(M.error_cache, {
		plugin = plugin_name,
		error = error_message,
	})
end

--- Show error window
--- @param plugin_name string
--- @param error_message string
function M.show_error(plugin_name, error_message)
	-- Save error to cache
	M.save_error(plugin_name, error_message)
	
	-- Close existing window and buffer if any
	if M.current_win and api.nvim_win_is_valid(M.current_win) then
		api.nvim_win_close(M.current_win, true)
	end
	if M.current_buf and api.nvim_buf_is_valid(M.current_buf) then
		api.nvim_buf_delete(M.current_buf, { force = true })
	end
	
	-- Check for existing buffer with the same name and delete it
	for _, buf_id in ipairs(api.nvim_list_bufs()) do
		if api.nvim_buf_is_valid(buf_id) then
			local buf_name = api.nvim_buf_get_name(buf_id)
			if buf_name == "SynapseError" or buf_name:match("SynapseError") then
				-- Check if buffer is in a window
				local wins = api.nvim_list_wins()
				for _, win_id in ipairs(wins) do
					if api.nvim_win_get_buf(win_id) == buf_id then
						api.nvim_win_close(win_id, true)
					end
				end
				api.nvim_buf_delete(buf_id, { force = true })
			end
		end
	end
	
	-- Format content - show all errors from cache
	local content_lines = {}
	for i, err in ipairs(M.error_cache) do
		if i > 1 then
			table.insert(content_lines, "")
			table.insert(content_lines, "---")
			table.insert(content_lines, "")
		end
		
		local plugin_lines = format_error_content(err.plugin, err.error)
		for _, line in ipairs(plugin_lines) do
			table.insert(content_lines, line)
		end
	end
	
	-- Remove trailing empty lines (including ">" lines from error formatting)
	while #content_lines > 0 and (content_lines[#content_lines] == "" or content_lines[#content_lines] == ">") do
		table.remove(content_lines)
	end
	
	-- Calculate window size (same as install/update windows)
	local width, height = calculate_window_size()
	
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
	api.nvim_buf_set_lines(buf, 0, -1, false, content_lines)
	
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
	
	local win_id = api.nvim_open_win(buf, true, config)
	
	-- Enable line wrapping in window (must be after window creation)
	api.nvim_win_set_option(win_id, "wrap", true)
	api.nvim_win_set_option(win_id, "linebreak", true) -- Break at word boundaries
	
	-- Set keymaps
	local opts = { noremap = true, silent = true }
	api.nvim_buf_set_keymap(buf, "n", "q", "<cmd>lua require('synapse.ui.error').close()<CR>", opts)
	api.nvim_buf_set_keymap(buf, "n", "<Esc>", "<cmd>lua require('synapse.ui.error').close()<CR>", opts)
	
	-- Store window reference
	M.current_win = win_id
	M.current_buf = buf
end

--- Show all errors from cache
function M.show_all_errors()
	-- Toggle: if window is already open, close it
	if M.current_win and api.nvim_win_is_valid(M.current_win) then
		M.close()
		return
	end
	
	if #M.error_cache == 0 then
		vim.notify("No errors to display", vim.log.levels.INFO, { title = "Synapse" })
		return
	end
	
	-- Clean up any existing windows and buffers
	if M.current_win and api.nvim_win_is_valid(M.current_win) then
		api.nvim_win_close(M.current_win, true)
	end
	if M.current_buf and api.nvim_buf_is_valid(M.current_buf) then
		api.nvim_buf_delete(M.current_buf, { force = true })
	end
	
	-- Check for existing buffer with the same name and delete it
	for _, buf_id in ipairs(api.nvim_list_bufs()) do
		if api.nvim_buf_is_valid(buf_id) then
			local buf_name = api.nvim_buf_get_name(buf_id)
			if buf_name == "SynapseError" or buf_name:match("SynapseError") then
				-- Check if buffer is in a window
				local wins = api.nvim_list_wins()
				for _, win_id in ipairs(wins) do
					if api.nvim_win_get_buf(win_id) == buf_id then
						api.nvim_win_close(win_id, true)
					end
				end
				api.nvim_buf_delete(buf_id, { force = true })
			end
		end
	end
	
	local content_lines = {}
	
	for i, err in ipairs(M.error_cache) do
		if i > 1 then
			table.insert(content_lines, "")
			table.insert(content_lines, "---")
			table.insert(content_lines, "")
		end
		
		local plugin_lines = format_error_content(err.plugin, err.error)
		for _, line in ipairs(plugin_lines) do
			table.insert(content_lines, line)
		end
	end
	
	-- Remove trailing empty lines (including ">" lines from error formatting)
	while #content_lines > 0 and (content_lines[#content_lines] == "" or content_lines[#content_lines] == ">") do
		table.remove(content_lines)
	end
	
	-- Calculate window size (same as install/update windows)
	local width, height = calculate_window_size()
	
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
	api.nvim_buf_set_lines(buf, 0, -1, false, content_lines)
	
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
	
	local win_id = api.nvim_open_win(buf, true, config)
	
	-- Enable line wrapping in window (must be after window creation)
	api.nvim_win_set_option(win_id, "wrap", true)
	api.nvim_win_set_option(win_id, "linebreak", true) -- Break at word boundaries
	
	-- Set keymaps
	local opts = { noremap = true, silent = true }
	api.nvim_buf_set_keymap(buf, "n", "q", "<cmd>lua require('synapse.ui.error').close()<CR>", opts)
	api.nvim_buf_set_keymap(buf, "n", "<Esc>", "<cmd>lua require('synapse.ui.error').close()<CR>", opts)
	
	-- Store window reference
	M.current_win = win_id
	M.current_buf = buf
end

--- Close error window
function M.close()
	if M.current_win and api.nvim_win_is_valid(M.current_win) then
		api.nvim_win_close(M.current_win, true)
	end
	
	if M.current_buf and api.nvim_buf_is_valid(M.current_buf) then
		api.nvim_buf_delete(M.current_buf, { force = true })
	end
	
	M.current_win = nil
	M.current_buf = nil
end

--- Clear error cache
function M.clear_cache()
	M.error_cache = {}
end

return M

