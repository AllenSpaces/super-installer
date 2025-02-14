local M = {}
local namespace = vim.api.nvim_create_namespace("SuperInstallerUI")

-- 通用窗口配置
local function create_window(title, height, lines)
    local width = 60
    local buf = vim.api.nvim_create_buf(false, true)
    local win = vim.api.nvim_open_win(buf, true, {
        relative = "editor",
        width = width,
        height = height,
        col = (vim.o.columns - width) / 2,
        row = (vim.o.lines - height) / 2,
        style = "minimal",
        border = "rounded"
    })

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_buf_add_highlight(buf, namespace, "Title", 0, 0, -1)
    return { win = win, buf = buf }
end

-- 安装UI
function M.show_install_ui(total)
    M.install_win = create_window("Installing", 5, {
        " Installing Plugins ",
        "",
        "Progress: [          ] 0/" .. total,
        "",
        "Current: "
    })
end

function M.update_install_ui(current, total, plugin)
    if not M.install_win then return end

    local progress = math.floor((current / total) * 10)
    local progress_bar = "[" .. string.rep("=", progress) .. string.rep(" ", 10 - progress) .. "]"
    
    vim.api.nvim_buf_set_lines(M.install_win.buf, 2, 3, false, {
        "Progress: " .. progress_bar .. " " .. current .. "/" .. total
    })
    vim.api.nvim_buf_set_lines(M.install_win.buf, 4, 5, false, {
        "Current: " .. plugin
    })
end

-- 移除UI
function M.show_remove_ui(total)
    M.remove_win = create_window("Removing", 5, {
        " Removing Plugins ",
        "",
        "Progress: [          ] 0/" .. total,
        "",
        "Current: "
    })
end

function M.update_remove_ui(current, total, plugin)
    if not M.remove_win then return end

    local progress = math.floor((current / total) * 10)
    local progress_bar = "[" .. string.rep("=", progress) .. string.rep(" ", 10 - progress) .. "]"
    
    vim.api.nvim_buf_set_lines(M.remove_win.buf, 2, 3, false, {
        "Progress: " .. progress_bar .. " " .. current .. "/" .. total
    })
    vim.api.nvim_buf_set_lines(M.remove_win.buf, 4, 5, false, {
        "Current: " .. plugin
    })
end

-- 通用关闭函数
function M.close_install_ui()
    if M.install_win and vim.api.nvim_win_is_valid(M.install_win.win) then
        vim.api.nvim_win_close(M.install_win.win, true)
    end
    M.install_win = nil
end

function M.close_remove_ui()
    if M.remove_win and vim.api.nvim_win_is_valid(M.remove_win.win) then
        vim.api.nvim_win_close(M.remove_win.win, true)
    end
    M.remove_win = nil
end

-- 结果显示UI
function M.show_result_ui(errors, title)
    local lines = { " " .. title .. " " }
    table.insert(lines, "")
    
    for _, e in ipairs(errors) do
        table.insert(lines, string.format("• %s: %s", e.plugin, e.error))
    end
    
    table.insert(lines, "")
    table.insert(lines, "Press q to close")
    
    local win = create_window(title, #lines + 2, lines)
    vim.api.nvim_buf_set_keymap(win.buf, "n", "q", "<cmd>q!<CR>", { noremap = true, silent = true })
end

return M