local api = vim.api

local PADDING = 1

local M = {
	win_cache = nil,
}

--- Calculate window size
--- @return number width
--- @return number height
local function calculate_window_size()
	local width = math.max(50, math.floor(vim.o.columns * 0.55))
	local height = math.max(18, math.floor(vim.o.lines * 0.5))
	return width, height
end

--- Ensure keymaps are set on buffer
--- @param buf number
function M.ensure_keymaps(buf)
	local opts = { noremap = true, silent = true }
	api.nvim_buf_set_keymap(buf, "n", "q", "<cmd>q!<CR>", opts)
	api.nvim_buf_set_keymap(buf, "n", "<Esc>", "<cmd>q!<CR>", opts)
	api.nvim_buf_set_keymap(buf, "n", "R", "<cmd>lua require('synapse.ui').retry_failures()<CR>", opts)
end

--- Create or update floating window
--- @param ui table|nil UI configuration
--- @return table win
function M.create_window(ui)
	local width, height = calculate_window_size()
	local config = {
		relative = "editor",
		width = width,
		height = height,
		col = math.floor((vim.o.columns - width) / 2),
		row = math.floor((vim.o.lines - height) / 2),
		style = "minimal",
		border = "rounded",
	}

	if M.win_cache and api.nvim_win_is_valid(M.win_cache.win_id) then
		api.nvim_win_set_config(M.win_cache.win_id, config)
		api.nvim_buf_set_lines(M.win_cache.buf, 0, -1, false, {})
	else
		local buf = api.nvim_create_buf(false, true)
		-- Set buffer name
		api.nvim_buf_set_name(buf, "Synapse")
		local win_id = api.nvim_open_win(buf, true, config)
		M.win_cache = { win_id = win_id, buf = buf }
		M.ensure_keymaps(buf)
		
		-- Set cursor to transparent using config highlight groups
		api.nvim_win_set_option(win_id, "cursorline", false)
		api.nvim_win_set_option(win_id, "cursorcolumn", false)
		
		-- Highlight groups are set by highlights.ensure_highlights
		
		-- Create transparent cursor highlight using config group names
		api.nvim_set_hl(0, "SynapseTransparentCursor", {
			fg = "NONE",
			bg = "NONE",
			blend = 100,
		})
		-- Apply transparent cursor to window
		api.nvim_win_set_option(win_id, "winhl", "Cursor:SynapseTransparentCursor")
	end

	return M.win_cache
end

--- Close window
function M.close()
	if M.win_cache and M.win_cache.win_id and api.nvim_win_is_valid(M.win_cache.win_id) then
		pcall(api.nvim_win_close, M.win_cache.win_id, true)
	end
	M.win_cache = nil
end

return M

