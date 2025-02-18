local M = {}

local function center_text(text, width)
    local padding = math.max(0, width - #text)
    local left_padding = math.floor(padding / 2)
    local right_padding = padding - left_padding
    return string.rep(" ", left_padding) .. text .. string.rep(" ", right_padding)
end

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

    local centered_title = center_text(title, width - 2) 
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {centered_title})
    return {win_id = win_id, buf = buf}
end

function M.update_progress(win, text, completed, total)
    local progress_percentage = math.floor((completed / total) * 100)
    local width = #text + 5
    local status_text = string.format("%d/%d (%d%%)", completed, total, progress_percentage)
    local progress_bar_length = width - #status_text - 2 -- 减去状态文本长度和前后符号长度
    local filled_length = math.floor((progress_percentage / 100) * progress_bar_length)
    local progress_bar = string.rep("-", filled_length) .. string.rep(" ", progress_bar_length - filled_length)

    local lines = {
        "·" .. progress_bar .. "· " .. string.format("%-".. width.."s", status_text),
    }

    -- 使进度条内容居中
    local centered_lines = {}
    for _, line in ipairs(lines) do
        table.insert(centered_lines, center_text(line, width))
    end

    vim.api.nvim_buf_set_lines(win.buf, 0, -1, false, centered_lines)
    vim.api.nvim_buf_set_name(win.buf, text)
    vim.api.nvim_buf_set_keymap(win.buf, 'n', 'q', '<cmd>q!<CR>', {noremap = true, silent = true})
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

    local height = #content + 2
    local width = 60

    local centered_content = {}
    for _, line in ipairs(content) do
        table.insert(centered_content, center_text(line, width - 2))
    end

    local win = M.create_window(operation .. " Results", height, width)
    vim.api.nvim_buf_set_lines(win.buf, 0, -1, false, centered_content)
    vim.api.nvim_buf_set_keymap(win.buf, 'n', 'q', '<cmd>q!<CR>', {noremap = true, silent = true})
end

return M