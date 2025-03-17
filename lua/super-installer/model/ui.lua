local M = {}

local function center_text(text, width)
	local padding = math.max(0, width - #text)
	local left = math.floor(padding / 2)
	return string.rep(" ", left) .. text .. string.rep(" ", padding - left)
end

function M.calculate_dimensions(content_lines, min_width)
	assert(type(content_lines) == "table", "content_lines must be table (got " .. type(content_lines) .. ")")

	local max_line_length = min_width or 0
	for _, line in ipairs(content_lines) do
		max_line_length = math.max(max_line_length, #line)
	end

	local screen_width = vim.o.columns
	local max_width = math.floor(screen_width * 0.5)
	return {
		width = math.min(max_width, max_line_length),
		height = math.min(20, #content_lines + 6),
	}
end

function M.update_progress(win, text, completed, total, ui)
	print(win, text, completed, total, ui)
	local FIXED_BAR_WIDTH = 50
	local progress = completed / total
	local filled = math.floor(FIXED_BAR_WIDTH * progress)

	local progress_bar = string.rep(" ", 2)
		.. string.rep(ui.progress.icon, filled)
		.. string.rep(" ", FIXED_BAR_WIDTH - filled)
		.. " "
		.. string.format("%s %d/%d (%d%%)", ui.manager.icon.package, completed, total, math.floor(progress * 100))

	vim.api.nvim_buf_set_lines(win.buf, 0, -1, false, {
		"",
		center_text(text, 68),
		"",
		center_text("Press 'q' to cease the operation", 67),
		"",
		center_text(progress_bar, 67),
		"",
	})
	vim.api.nvim_buf_set_keymap(win.buf, "n", "q", "<cmd>q!<CR>", { noremap = true, silent = true })
end

function M.create_window(title, content_lines)
	local dim = nil
	local win_config = {}

	if type(content_lines) == "string" then
		content_lines = { content_lines }
	elseif type(content_lines) == "number" then
		content_lines = { string.rep(" ", content_lines) }
	end

	dim = M.calculate_dimensions(content_lines, #title)

	win_config = {
		relative = "editor",
		width = dim.width,
		height = dim.height,
		col = math.floor((vim.o.columns - dim.width) / 2),
		row = math.floor((vim.o.lines - dim.height) / 2),
		style = "minimal",
		border = "rounded",
		title = title,
		title_pos = "center",
	}

	if M.win_cache and vim.api.nvim_win_is_valid(M.win_cache.win_id) then
		vim.api.nvim_win_set_config(M.win_cache.win_id, win_config)
		vim.api.nvim_buf_set_lines(M.win_cache.buf, 0, -1, false, {})
		return M.win_cache
	end

	local buf = vim.api.nvim_create_buf(false, true)
	local win_id = vim.api.nvim_open_win(buf, true, win_config)
	M.win_cache = { win_id = win_id, buf = buf }
	return M.win_cache
end

function M.show_report(errors, success_count, total, operation)
	local content = {}

	if #errors > 0 then
		table.insert(content, "")
		table.insert(content, center_text("Errors (" .. #errors .. "):", 67))
		table.insert(content, "")
		for i, e in ipairs(errors) do
			table.insert(content, center_text(string.format("%d. %s: %s", i, e.plugin, e.error), 67))
			table.insert(content, "")
			if i >= 5 then
				table.insert(content, center_text("... (truncated)", 67))
				table.insert(content, "")
				break
			end
		end
	else
		table.insert(content, "")
		table.insert(
			content,
			center_text(operation .. " Results (" .. success_count .. "/" .. total .. " successful)", 67)
		)
		table.insert(content, "")
		table.insert(content, center_text("✓ All operations completed successfully!", 67))
	end

	table.insert(content, "")
	table.insert(content, center_text("Press 'q' to quit", 67))

	local win = M.create_window(operation .. " Report", content)
	vim.api.nvim_buf_set_lines(win.buf, 0, -1, false, content)
	vim.api.nvim_buf_set_keymap(win.buf, "n", "q", "<cmd>q!<CR>", { noremap = true, silent = true })
end

function M.log_message(message)
	vim.notify(message, vim.log.levels.INFO, { title = "SuperInstaller" })
end

return M
