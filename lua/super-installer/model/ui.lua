local M = {}

function M.create_window(title, height, width)
    local buf = vim.api.nvim_create_buf(false, true)
    local win_id = vim.api.nvim_open_win(buf, true, {
        relative = 'editor',
        width = width,
        height = height,
        col = math.floor((vim.o.columns - width) / 2),
        row = math.floor((vim.o.lines - height) / 2),
        style = 'minimal',
        border = 'rounded'
    })
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {title})
    return {win_id = win_id, buf = buf}
end

function M.update_progress(win, text, completed, total)
    local progress_percentage = math.floor((completed / total) * 100)
    local bar_length = 50
    local filled_length = math.floor((progress_percentage / 100) * bar_length)
    local progress_bar = string.rep("=", filled_length) .. string.rep(" ", bar_length - filled_length)
    local status_text = string.format("%d/%d (%d%%)", completed, total, progress_percentage)

    local lines = {
        text,
        status_text,
        "[" .. progress_bar .. "]"
    }
    vim.api.nvim_buf_set_lines(win.buf, 0, -1, false, lines)
end

function M.show_results(errors, success_count, total, operation)
    local content = {
        string.format("%s Results (%d/%d successful):", operation, success_count, total),
        ""
    }
    if #errors > 0 then
        table.insert(content, "Errors:")
        for _, e in ipairs(errors) do
            table.insert(content, string.format("• %s: %s", e.plugin, e.error))
        end
    else
        table.insert(content, "All operations completed successfully!")
    end
    table.insert(content, "")
    table.insert(content, "Press q to close")

    local height = math.min(#content + 2, 15)
    local width = 60
    local win = M.create_window(operation .. " Results", height, width)
    vim.api.nvim_buf_set_lines(win.buf, 0, -1, false, content)
    vim.api.nvim_buf_set_keymap(win.buf, 'n', 'q', '<cmd>q!<CR>', {noremap = true, silent = true})
end

return M