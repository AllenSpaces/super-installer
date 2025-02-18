local M = {}

function M.calculate_dimensions(content_lines, min_width)
    local max_line_length = min_width or 0
    for _, line in ipairs(content_lines) do
        max_line_length = math.max(max_line_length, #line)
    end
    
    local screen_width = vim.o.columns
    local screen_height = vim.o.lines
    local max_width = math.floor(screen_width * 0.5)
    local max_height = math.floor(screen_height * 0.5)
    
    return {
        width = math.min(max_width, max_line_length + 4),  -- 增加边框间距
        height = math.min(max_height, #content_lines + 4)  -- 增加标题和边距
    }
end

function M.create_window(title, content_lines)
    local dim = M.calculate_dimensions(content_lines, #title)
    local win_config = {
        relative = 'editor',
        width = dim.width,
        height = dim.height,
        col = math.floor((vim.o.columns - dim.width) / 2),
        row = math.floor((vim.o.lines - dim.height) / 2),
        style = 'minimal',
        border = 'rounded',
        title = center_text(title, dim.width - 4)  -- 标题居中
    }
    
    local buf = vim.api.nvim_create_buf(false, true)
    local win_id = vim.api.nvim_open_win(buf, true, win_config)
    
    -- 设置关闭快捷键
    vim.api.nvim_buf_set_keymap(buf, 'n', 'q', '<cmd>q!<CR>', {noremap = true, silent = true})
    return {win_id = win_id, buf = buf}
end

function M.update_progress(win, text, completed, total)
    local FIXED_BAR_WIDTH = 30  -- 固定进度条宽度
    local progress_percentage = math.floor((completed / total) * 100)
    local status_text = string.format("%d/%d (%d%%)", completed, total, progress_percentage)
    
    -- 进度条生成逻辑
    local filled_length = math.floor(FIXED_BAR_WIDTH * (progress_percentage / 100))
    local progress_bar = "[" .. string.rep("=", filled_length) 
        .. string.rep(" ", FIXED_BAR_WIDTH - filled_length) .. "]"
    
    -- 居中组合
    local lines = {
        center_text(progress_bar, FIXED_BAR_WIDTH + 4),  -- 包含边框
        center_text(status_text, FIXED_BAR_WIDTH + 4)
    }
    
    vim.api.nvim_buf_set_lines(win.buf, 0, -1, false, lines)
end

function M.show_results(errors, success_count, total, operation)
    local content = {
        string.format("%s Results (%d/%d successful):", operation, success_count, total),
        ""
    }
    
    -- 动态生成内容
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

    -- 自动计算窗口尺寸
    local dim = M.calculate_dimensions(content, 40)  -- 最小宽度40
    local centered_content = {}
    for _, line in ipairs(content) do
        table.insert(centered_content, center_text(line, dim.width - 4))  -- 考虑边框
    end

    local win = M.create_window(operation .. " Results", content)
    vim.api.nvim_buf_set_lines(win.buf, 0, -1, false, centered_content)
end


return M