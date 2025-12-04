local api = vim.api

local PADDING = 1

local M = {
	winCache = nil,
}

--- Calculate window size
--- @return number width Window width
--- @return number height Window height
local function calculateWindowSize()
	local width = math.max(50, math.floor(vim.o.columns * 0.55))
	local height = math.max(18, math.floor(vim.o.lines * 0.5))
	return width, height
end

--- Ensure keymaps are set on buffer
--- @param buf number Buffer number
function M.ensureKeymaps(buf)
	local opts = { noremap = true, silent = true }
	api.nvim_buf_set_keymap(buf, "n", "q", "<cmd>lua require('synapse.ui').close()<CR>", opts)
	api.nvim_buf_set_keymap(buf, "n", "<Esc>", "<cmd>lua require('synapse.ui').close()<CR>", opts)
	api.nvim_buf_set_keymap(buf, "n", "R", "<cmd>lua require('synapse.ui').retry_failures()<CR>", opts)
end

--- Create or update floating window
--- @param ui table|nil UI configuration
--- @return table win Window table
function M.createWindow(ui)
	local width, height = calculateWindowSize()
	local config = {
		relative = "editor",
		width = width,
		height = height,
		col = math.floor((vim.o.columns - width) / 2),
		row = math.floor((vim.o.lines - height) / 2),
		style = "minimal",
		border = "rounded",
	}

	if M.winCache and api.nvim_win_is_valid(M.winCache.win_id) then
		api.nvim_win_set_config(M.winCache.win_id, config)
		api.nvim_buf_set_lines(M.winCache.buf, 0, -1, false, {})
	else
		local buf = api.nvim_create_buf(false, true)
		-- Set buffer name
		api.nvim_buf_set_name(buf, "Synapse")
		local win_id = api.nvim_open_win(buf, true, config)
		M.winCache = { win_id = win_id, buf = buf }
		M.ensureKeymaps(buf)
		
		-- Set cursor to transparent using config highlight groups
		api.nvim_win_set_option(win_id, "cursorline", false)
		api.nvim_win_set_option(win_id, "cursorcolumn", false)
		
		-- Highlight groups are set by highlights.ensureHighlights
		
		-- Create transparent cursor highlight using config group names
		api.nvim_set_hl(0, "SynapseTransparentCursor", {
			fg = "NONE",
			bg = "NONE",
			blend = 100,
		})
		-- Apply transparent cursor to window
		api.nvim_win_set_option(win_id, "winhl", "Cursor:SynapseTransparentCursor")
	end

	return M.winCache
end

--- Close window
function M.close()
	if M.winCache then
		-- Close window if valid
		if M.winCache.win_id and api.nvim_win_is_valid(M.winCache.win_id) then
			pcall(api.nvim_win_close, M.winCache.win_id, true)
		end
		
		-- Delete buffer if valid
		if M.winCache.buf and api.nvim_buf_is_valid(M.winCache.buf) then
			pcall(api.nvim_buf_delete, M.winCache.buf, { force = true })
		end
		
		M.winCache = nil
	end
end

return M
